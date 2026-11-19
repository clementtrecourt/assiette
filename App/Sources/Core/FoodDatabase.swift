import Foundation
import SQLite3

/// Read-only access to the bundled OpenNutrition database (`foods.sqlite`, built by
/// tools/build_db.py). Thread-safe: every call is serialized on an internal lock, so it
/// can be used from any task. Queries are fast (< 20 ms) but prefer calling from a
/// background task (`Task.detached` or an `async` wrapper) for search-as-you-type.
final class FoodDatabase: @unchecked Sendable {
    static let shared = FoodDatabase()

    private var db: OpaquePointer?
    private let lock = NSLock()

    /// nil when the database could not be opened (e.g. resource missing in a dev build).
    private(set) var openError: String?

    private static let nutrientColumns = NutrientKey.allCases.map(\.rawValue)
    private static let selectColumns =
        "f.id, f.ext_id, f.name, f.brand, f.type, f.ean, f.serving_unit, f.serving_qty, "
        + "f.serving_g, f.is_liquid, f.package_g, "
        + nutrientColumns.map { "f.\($0)" }.joined(separator: ", ")

    init(url: URL? = Bundle.main.url(forResource: "foods", withExtension: "sqlite")) {
        guard let url else {
            openError = "Base d'aliments introuvable dans l'application."
            return
        }
        var handle: OpaquePointer?
        let uri = "file:\(url.path)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK {
            db = handle
        } else {
            openError = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite open failed"
            sqlite3_close(handle)
        }
    }

    deinit { sqlite3_close(db) }

    var isAvailable: Bool { db != nil }

    /// Number of foods in the database.
    lazy var count: Int = {
        (try? query("SELECT count(*) FROM food", bind: []) { sqlite3_column_int64($0, 0) })
            .flatMap(\.first).map(Int.init) ?? 0
    }()

    /// Dataset version string, e.g. "OpenNutrition 2025.1".
    lazy var datasetVersion: String = {
        (try? query("SELECT value FROM meta WHERE key='dataset'", bind: []) {
            String(cString: sqlite3_column_text($0, 0))
        })?.first ?? "OpenNutrition"
    }()

    // MARK: - Public API

    /// Full-text search (prefix matching, accent-insensitive). French words are expanded
    /// with English equivalents via `FrenchFoodLexicon` since the dataset is in English.
    /// Results: generic foods first, then by relevance, shorter names breaking ties.
    func search(_ text: String, kinds: Set<FoodKind>? = nil, limit: Int = 60) -> [Food] {
        guard let match = Self.ftsQuery(for: text) else { return [] }
        var sql = """
            SELECT \(Self.selectColumns), bm25(food_fts, 10.0, 2.0) AS score
            FROM food_fts JOIN food f ON f.id = food_fts.rowid
            WHERE food_fts MATCH ?
            """
        if let kinds, !kinds.isEmpty, kinds.count < FoodKind.allCases.count {
            sql += " AND f.type IN (\(kinds.map { String($0.rawValue) }.joined(separator: ",")))"
        }
        // Grab a generous candidate set ordered by FTS relevance, then re-rank in Swift.
        sql += " ORDER BY score LIMIT \(max(limit * 4, 200))"
        let rows: [(Food, Double)] = (try? query(sql, bind: [.text(match)]) { stmt in
            (Self.readFood(stmt), sqlite3_column_double(stmt, Int32(11 + Self.nutrientColumns.count)))
        }) ?? []

        let tokens = Self.tokens(of: text)
        let ranked = rows.map { food, score -> (Food, Double) in
            var s = score // bm25: lower (more negative) is better
            let lower = food.displayName.lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            if let first = tokens.first, lower.hasPrefix(first) { s -= 4 }
            if tokens.allSatisfy({ lower.contains($0) }) { s -= 3 }
            s += Double(food.kind == .grocery ? 6 : food.kind == .restaurant ? 3 : 0)
            s += Double(food.displayName.count) * 0.04
            return (food, s)
        }
        return ranked.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    func food(id: Int64) -> Food? {
        try? query("SELECT \(Self.selectColumns) FROM food f WHERE f.id = ?", bind: [.int(id)],
                   Self.readFood).first
    }

    /// Lookup by barcode. Accepts EAN-13, UPC-A (12 digits, zero-padded) and EAN-8.
    func food(barcode: String) -> Food? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        var candidates = [digits]
        if digits.count < 13 { candidates.append(String(repeating: "0", count: 13 - digits.count) + digits) }
        if digits.count == 13, digits.hasPrefix("0") { candidates.append(String(digits.dropFirst())) }
        for code in candidates {
            if let f = try? query("SELECT \(Self.selectColumns) FROM food f WHERE f.ean = ? LIMIT 1",
                                  bind: [.text(code)], Self.readFood).first {
                return f
            }
        }
        return nil
    }

    // MARK: - Query building

    static func tokens(of text: String) -> [String] {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Builds an FTS5 MATCH expression: every token must match (as a prefix), French
    /// tokens are OR-ed with their English translations.
    static func ftsQuery(for text: String) -> String? {
        let words = tokens(of: text).filter { !FrenchFoodLexicon.stopWords.contains($0) }
        guard !words.isEmpty else { return nil }
        let clauses = words.map { word -> String in
            var alternatives = ["\"\(word)\"*"]
            for translation in FrenchFoodLexicon.translations(for: word) {
                // Multi-word translations become a phrase ("ground beef").
                let t = tokens(of: translation).joined(separator: " ")
                guard !t.isEmpty else { continue }
                alternatives.append("\"\(t)\"" + (t.contains(" ") ? "" : "*"))
            }
            let unique = Array(NSOrderedSet(array: alternatives)) as? [String] ?? alternatives
            return unique.count == 1 ? unique[0] : "(" + unique.joined(separator: " OR ") + ")"
        }
        return clauses.joined(separator: " AND ")
    }

    // MARK: - SQLite plumbing

    enum Binding {
        case text(String)
        case int(Int64)
    }

    struct SQLError: Error, CustomStringConvertible {
        let description: String
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func query<T>(_ sql: String, bind: [Binding], _ read: (OpaquePointer) -> T) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw SQLError(description: openError ?? "database unavailable") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLError(description: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in bind.enumerated() {
            switch b {
            case .text(let s): sqlite3_bind_text(stmt, Int32(i + 1), s, -1, Self.transient)
            case .int(let v): sqlite3_bind_int64(stmt, Int32(i + 1), v)
            }
        }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(read(stmt))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLError(description: String(cString: sqlite3_errmsg(db)))
            }
        }
        return out
    }

    private static func readFood(_ stmt: OpaquePointer) -> Food {
        func text(_ i: Int32) -> String? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        func double(_ i: Int32) -> Double? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
        }
        var values = NutrientValues()
        for (offset, key) in NutrientKey.allCases.enumerated() {
            values[key] = double(Int32(11 + offset))
        }
        return Food(
            id: sqlite3_column_int64(stmt, 0),
            extId: text(1) ?? "",
            name: text(2) ?? "",
            brand: text(3),
            kind: FoodKind(rawValue: Int(sqlite3_column_int(stmt, 4))) ?? .grocery,
            ean: text(5),
            servingUnit: text(6),
            servingQuantity: double(7),
            servingGrams: double(8),
            isLiquid: sqlite3_column_int(stmt, 9) != 0,
            packageGrams: double(10),
            per100: values
        )
    }
}

extension FoodDatabase {
    /// Async convenience for UI code.
    func searchAsync(_ text: String, kinds: Set<FoodKind>? = nil, limit: Int = 60) async -> [Food] {
        await Task.detached(priority: .userInitiated) { [self] in
            search(text, kinds: kinds, limit: limit)
        }.value
    }
}
