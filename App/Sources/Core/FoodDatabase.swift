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
    private static let baseColumns =
        "f.id, f.ext_id, f.name, f.brand, f.type, f.ean, f.serving_unit, f.serving_qty, "
        + "f.serving_g, f.is_liquid, f.package_g, "
        + nutrientColumns.map { "f.\($0)" }.joined(separator: ", ")
    /// Column index of `icon` in `selectColumns` (always present: NULL on older databases).
    private static let iconColumn = Int32(11 + nutrientColumns.count)
    /// Column index of `fluent` (Fluent Emoji name), right after `icon`; NULL on older databases.
    private static let fluentColumn = iconColumn + 1
    /// First column after the shared SELECT list (e.g. the bm25 score in `search`).
    private static let extraColumn = fluentColumn + 1

    /// SELECT list shared by every query. Databases built before the `icon` / `fluent`
    /// columns existed get `NULL` instead, so the layout (and `readFood`) never changes.
    private let selectColumns: String

    /// Small in-memory cache for `food(id:)` (journal rows, icon lookups). Thread-safe.
    private let foodCache: NSCache<NSNumber, FoodDatabaseCachedFood> = {
        let cache = NSCache<NSNumber, FoodDatabaseCachedFood>()
        cache.countLimit = 1000
        return cache
    }()

    init(url: URL? = Bundle.main.url(forResource: "foods", withExtension: "sqlite")) {
        guard let url else {
            openError = "Base d'aliments introuvable dans l'application."
            selectColumns = Self.baseColumns + ", NULL, NULL"
            return
        }
        var handle: OpaquePointer?
        let uri = "file:\(url.path)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        var hasIcon = false
        var hasFluent = false
        if sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle {
            db = handle
            hasIcon = Self.hasColumn("icon", table: "food", in: handle)
            hasFluent = Self.hasColumn("fluent", table: "food", in: handle)
        } else {
            openError = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite open failed"
            sqlite3_close(handle)
        }
        selectColumns = Self.baseColumns + (hasIcon ? ", f.icon" : ", NULL")
            + (hasFluent ? ", f.fluent" : ", NULL")
    }

    /// `PRAGMA table_info` check, run once at open time.
    private static func hasColumn(_ column: String, table: String, in db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1), String(cString: name) == column {
                return true
            }
        }
        return false
    }

    deinit { sqlite3_close(db) }

    var isAvailable: Bool { db != nil }

    /// Cached `count`, guarded by `lock` (filled outside `query`, which takes the lock itself).
    private var cachedCount: Int?

    /// Number of foods in the database. Safe to read from any thread (the launch prewarm
    /// task and the search sheet may read it concurrently).
    var count: Int {
        lock.lock()
        let cached = cachedCount
        lock.unlock()
        if let cached { return cached }
        let value = (try? query("SELECT count(*) FROM food", bind: []) { sqlite3_column_int64($0, 0) })
            .flatMap(\.first).map(Int.init) ?? 0
        lock.lock()
        cachedCount = value
        lock.unlock()
        return value
    }

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
            SELECT \(selectColumns), bm25(food_fts, 10.0, 2.0) AS score
            FROM food_fts JOIN food f ON f.id = food_fts.rowid
            WHERE food_fts MATCH ?
            """
        if let kinds, !kinds.isEmpty, kinds.count < FoodKind.allCases.count {
            sql += " AND f.type IN (\(kinds.map { String($0.rawValue) }.joined(separator: ",")))"
        }
        // Grab a generous candidate set ordered by FTS relevance, then re-rank in Swift.
        sql += " ORDER BY score LIMIT \(max(limit * 4, 200))"
        let rows: [(Food, Double)] = (try? query(sql, bind: [.text(match)]) { stmt in
            (Self.readFood(stmt), sqlite3_column_double(stmt, Self.extraColumn))
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

    /// Food by primary key. Results (including misses) are cached in memory.
    func food(id: Int64) -> Food? {
        let key = NSNumber(value: id)
        if let cached = foodCache.object(forKey: key) { return cached.food }
        guard let rows = try? query("SELECT \(selectColumns) FROM food f WHERE f.id = ?",
                                    bind: [.int(id)], Self.readFood) else { return nil }
        let food = rows.first
        foodCache.setObject(FoodDatabaseCachedFood(food), forKey: key)
        return food
    }

    /// Illustration basename of a food (see `FoodIconView`), nil when none / unknown id.
    func iconName(forFoodId id: Int64) -> String? {
        food(id: id)?.icon
    }

    /// Both icon sources of a food: bundled Fluent Emoji name and OpenNutrition illustration.
    func iconNames(forFoodId id: Int64) -> FoodIconNames {
        let food = food(id: id)
        return FoodIconNames(fluent: food?.fluent, icon: food?.icon)
    }

    /// Lookup by barcode. Accepts EAN-13, UPC-A (12 digits, zero-padded) and EAN-8.
    func food(barcode: String) -> Food? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        var candidates = [digits]
        if digits.count < 13 { candidates.append(String(repeating: "0", count: 13 - digits.count) + digits) }
        if digits.count == 13, digits.hasPrefix("0") { candidates.append(String(digits.dropFirst())) }
        for code in candidates {
            if let f = try? query("SELECT \(selectColumns) FROM food f WHERE f.ean = ? LIMIT 1",
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
            per100: values,
            icon: text(iconColumn).flatMap { $0.isEmpty ? nil : $0 },
            fluent: text(fluentColumn).flatMap { $0.isEmpty ? nil : $0 }
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

/// Icon sources of a dataset food, in display order (see `FoodIconView`).
struct FoodIconNames: Hashable, Sendable {
    var fluent: String?
    var icon: String?
}

/// Boxed `food(id:)` result for NSCache (nil = known miss).
final class FoodDatabaseCachedFood {
    let food: Food?

    init(_ food: Food?) {
        self.food = food
    }
}
