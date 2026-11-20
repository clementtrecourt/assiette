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

    /// SELECT list shared by every query. Databases built before the `icon` / `fluent`
    /// columns existed get `NULL` instead, so the layout (and `readFood`) never changes.
    private let selectColumns: String
    /// `f.name_en, f.staple` (dataset name and staple rank of the foods renamed in French),
    /// or `NULL, 0` on databases built before those columns existed.
    private let stapleColumns: String

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
            stapleColumns = "NULL, 0"
            return
        }
        var handle: OpaquePointer?
        let uri = "file:\(url.path)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        var hasIcon = false
        var hasFluent = false
        var hasStaple = false
        if sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle {
            db = handle
            hasIcon = Self.hasColumn("icon", table: "food", in: handle)
            hasFluent = Self.hasColumn("fluent", table: "food", in: handle)
            hasStaple = Self.hasColumn("name_en", table: "food", in: handle)
                && Self.hasColumn("staple", table: "food", in: handle)
        } else {
            openError = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite open failed"
            sqlite3_close(handle)
        }
        selectColumns = Self.baseColumns + (hasIcon ? ", f.icon" : ", NULL")
            + (hasFluent ? ", f.fluent" : ", NULL")
        stapleColumns = hasStaple ? "f.name_en, f.staple" : "NULL, 0"
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

    /// Full-text search, accent-insensitive; the last word is prefix-matched (search as you
    /// type). French compound names are rewritten ("pommes de terre" -> "potato") and French
    /// words expanded with English equivalents via `FrenchFoodLexicon`, since the dataset is
    /// in English. Ranking (`SearchRanking`): foods whose name matches every word
    /// first, whole words before prefixes, names starting with the query and with few other
    /// words, staples (foods renamed in French) and generic foods before brands.
    /// - Parameter history: food id -> number of times the user logged it; those foods are
    ///   ranked first when they match.
    func search(_ text: String, kinds: Set<FoodKind>? = nil, limit: Int = 60,
                history: [Int64: Int] = [:]) -> [Food] {
        let rewritten = FrenchFoodLexicon.rewritingPhrases(text)
        let typed = Self.searchTerms(for: text)
        // A last word coming from a rewritten phrase is complete ("jambon blanc" -> "ham",
        // which must not match "Hamburger").
        let terms = rewritten == typed.map(\.word).joined(separator: " ")
            ? typed
            : Self.searchTerms(for: rewritten, lastWordIsComplete: typed.last?.word != Self.tokens(of: rewritten).last)
        guard let strict = Self.ftsQuery(terms), limit > 0 else { return [] }
        let allowed = kinds.flatMap { $0.isEmpty ? nil : $0 } ?? Set(FoodKind.allCases)
        let typeList = { (kinds: [FoodKind]) in kinds.map { String($0.rawValue) }.sorted().joined(separator: ",") }
        let light = "SELECT f.id, f.name, f.brand, f.type, \(stapleColumns) FROM food_fts "
            + "JOIN food f ON f.id = food_fts.rowid WHERE food_fts MATCH ?"
        var candidates: [Int64: SearchCandidate] = [:]
        var match = strict
        func collect(_ sql: String) {
            let rows = (try? query(sql, bind: [.text(match)], Self.readCandidate)) ?? []
            for row in rows { candidates[row.id] = row }
        }
        func collectAll() {
            // Generic foods, dishes and restaurants (~13k rows in all): every match is ranked, so
            // the best one ("Lait entier" for "milk") can never be cut by the FTS order.
            let generic = allowed.subtracting([.grocery])
            if !generic.isEmpty {
                collect(light + " AND f.type IN (\(typeList(Array(generic)))) LIMIT 6000")
            }
            // Branded products (300k rows): the best FTS matches only; not for a single letter
            // (slow, and brands cannot be told apart yet).
            let isSingleLetter = terms.count == 1 && terms[0].word.count == 1
            if allowed.contains(.grocery), !isSingleLetter || allowed == [.grocery] {
                collect(light + " AND f.type = \(FoodKind.grocery.rawValue) ORDER BY bm25(food_fts, 10.0, 1.0) LIMIT 400")
            }
            // Foods already logged, wherever their FTS rank.
            if !history.isEmpty {
                let ids = history.keys.sorted().prefix(500).map(String.init).joined(separator: ",")
                collect(light + " AND f.id IN (\(ids)) AND f.type IN (\(typeList(Array(allowed))))")
            }
        }
        collectAll()
        // No food has every word (a word unknown to the dataset: "pavé de saumon" before the
        // lexicon knew "pavé"): any word may match, the ranking puts the best matches first.
        if candidates.isEmpty, terms.count > 1, let relaxed = Self.ftsQuery(terms, requireAll: false) {
            match = relaxed
            collectAll()
        }

        let ranking = SearchRanking(terms: terms, typedTerms: typed)
        let best = candidates.values
            .map { ($0.id, ranking.score($0, timesLogged: history[$0.id] ?? 0)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit)
            .map(\.0)
        guard !best.isEmpty else { return [] }
        let ids = best.map(String.init).joined(separator: ",")
        let foods = (try? query("SELECT \(selectColumns) FROM food f WHERE f.id IN (\(ids))",
                                bind: [], Self.readFood)) ?? []
        let byId = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return best.compactMap { byId[$0] }
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

    /// Lowercased, accent-folded words ("Œufs brouillés" -> ["oeufs", "brouilles"]).
    static func tokens(of text: String) -> [String] {
        // Fast path for ASCII names (most of the dataset): ranking tokenizes every candidate.
        if text.utf8.allSatisfy({ $0 < 0x80 }) {
            var out: [String] = []
            var current: [UInt8] = []
            current.reserveCapacity(16)
            for byte in text.utf8 {
                switch byte {
                case 0x41...0x5A: current.append(byte + 0x20)
                case 0x61...0x7A, 0x30...0x39: current.append(byte)
                default:
                    if !current.isEmpty {
                        out.append(String(decoding: current, as: UTF8.self))
                        current.removeAll(keepingCapacity: true)
                    }
                }
            }
            if !current.isEmpty { out.append(String(decoding: current, as: UTF8.self)) }
            return out
        }
        return text.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Query words (stop words removed) with their alternatives. The last word is matched
    /// as a prefix while it is being typed, unless it is a complete French word ("riz" must
    /// not match "Rizo" nor "pain" "Painkiller"). Other words and every translation are
    /// matched as whole words, singular or plural ("egg" matches "Eggs", not "Eggplant").
    static func searchTerms(for text: String, lastWordIsComplete: Bool = false) -> [SearchTerm] {
        let words = tokens(of: text).filter { !FrenchFoodLexicon.stopWords.contains($0) }
        return words.enumerated().map { index, word in
            let isPrefix = index == words.count - 1 && !lastWordIsComplete
                && !FrenchFoodLexicon.isKnownWord(word)
            var alternatives = isPrefix
                ? [SearchAlternative(tokens: [word], isPrefix: true)]
                : wordForms(word).map { SearchAlternative(tokens: [$0], isPrefix: false) }
            // A complete word that is not French (English, or produced by a phrase rewrite such
            // as "ham") is not translated: prefix translations are only for words being typed.
            let translations = isPrefix || FrenchFoodLexicon.isKnownWord(word)
                ? FrenchFoodLexicon.translations(for: word) : []
            for translation in translations {
                var phrase = tokens(of: translation)
                guard let last = phrase.popLast() else { continue }
                for form in wordForms(last) {
                    alternatives.append(SearchAlternative(tokens: phrase + [form], isPrefix: false))
                }
            }
            var seen = Set<SearchAlternative>()
            return SearchTerm(word: word, alternatives: alternatives.filter { seen.insert($0).inserted })
        }
    }

    /// The word and its likely singular / plural forms, French and English
    /// ("oeuf" -> oeufs, "berry" -> berries, "tomatoes" -> tomato, "gateau" -> gateaux).
    static func wordForms(_ word: String) -> [String] {
        var forms = [word]
        func add(_ form: String) { if form.count >= 2, !forms.contains(form) { forms.append(form) } }
        guard word.count >= 3, word.allSatisfy(\.isLetter) else { return forms }
        if word.hasSuffix("ies"), word.count > 4 {
            add(String(word.dropLast(3)) + "y")
        } else if word.hasSuffix("es"), word.count > 4,
                  ["s", "x", "z", "ch", "sh", "o"].contains(where: { word.dropLast(2).hasSuffix($0) }) {
            add(String(word.dropLast(2)))
        }
        if word.hasSuffix("aux"), word.count > 4 { add(String(word.dropLast(3)) + "al") }
        if (word.hasSuffix("s") || word.hasSuffix("x")), word.count > 3 {
            add(String(word.dropLast()))
            return forms
        }
        add(word + "s")
        if word.hasSuffix("eau") || word.hasSuffix("eu") { add(word + "x") }
        if word.hasSuffix("al") { add(String(word.dropLast(2)) + "aux") }
        if ["s", "x", "z", "ch", "sh", "o"].contains(where: { word.hasSuffix($0) }) { add(word + "es") }
        if word.hasSuffix("y"), let before = word.dropLast().last, !"aeiou".contains(before) {
            add(String(word.dropLast()) + "ies")
        }
        return forms
    }

    /// FTS5 MATCH expression: every term must match (AND), through any alternative (OR).
    static func ftsQuery(for text: String) -> String? {
        ftsQuery(searchTerms(for: text))
    }

    /// - Parameter requireAll: AND between terms (default), else OR.
    static func ftsQuery(_ terms: [SearchTerm], requireAll: Bool = true) -> String? {
        guard !terms.isEmpty else { return nil }
        return terms.map { term in
            // Tokens are alphanumeric only, so quoting them is always safe.
            let parts = term.alternatives.map { "\"" + $0.tokens.joined(separator: " ") + "\"" + ($0.isPrefix ? "*" : "") }
            return parts.count == 1 ? parts[0] : "(" + parts.joined(separator: " OR ") + ")"
        }.joined(separator: requireAll ? " AND " : " OR ")
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

    /// Row of the light candidate queries of `search` (id, name, brand, type, name_en, staple).
    private static func readCandidate(_ stmt: OpaquePointer) -> SearchCandidate {
        func text(_ i: Int32) -> String? {
            guard sqlite3_column_type(stmt, i) != SQLITE_NULL, let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }
        return SearchCandidate(
            id: sqlite3_column_int64(stmt, 0),
            name: text(1) ?? "",
            brand: text(2),
            kind: FoodKind(rawValue: Int(sqlite3_column_int(stmt, 3))) ?? .grocery,
            englishName: text(4),
            stapleRank: Int(sqlite3_column_int(stmt, 5))
        )
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
    func searchAsync(_ text: String, kinds: Set<FoodKind>? = nil, limit: Int = 60,
                     history: [Int64: Int] = [:]) async -> [Food] {
        await Task.detached(priority: .userInitiated) { [self] in
            search(text, kinds: kinds, limit: limit, history: history)
        }.value
    }
}

/// One spelling that can match a query word: a token sequence (a phrase when there are
/// several), the last token matched as a prefix when `isPrefix`.
struct SearchAlternative: Hashable, Sendable {
    var tokens: [String]
    var isPrefix: Bool
}

/// A query word and every alternative that can match it (see `FoodDatabase.searchTerms`).
struct SearchTerm: Hashable, Sendable {
    var word: String
    var alternatives: [SearchAlternative]
}

/// Light row read for ranking, before the full `Food` of the kept results is loaded.
struct SearchCandidate: Sendable {
    let id: Int64
    let name: String
    let brand: String?
    let kind: FoodKind
    /// Dataset (English) name of a staple food renamed in French.
    var englishName: String? = nil
    /// 0 = not a staple, 1 = staple, 2 = reference food of its family ("Œufs entiers").
    var stapleRank: Int = 0
}

/// Scores a search candidate from how its name matches the query words (the FTS match
/// may come from alternate names only). Higher is better.
struct SearchRanking: Sendable {
    private let matcher: Matcher
    /// The words as typed, before phrase rewriting ("jambon blanc" rather than "ham"): also
    /// tried on French names.
    private let typedMatcher: Matcher?

    var terms: [SearchTerm] { matcher.terms }

    init(terms: [SearchTerm], typedTerms: [SearchTerm]? = nil) {
        matcher = Matcher(terms: terms)
        typedMatcher = typedTerms.flatMap { $0 == terms || $0.isEmpty ? nil : Matcher(terms: $0) }
    }

    /// How a name matches the query.
    struct NameMatch: Comparable {
        /// 0…1: average match quality per word (whole word 1, prefix or brand only 1/2).
        var quality: Double
        var matchesAll: Bool
        /// A query word is the main word of the name, as a whole word: the first word of a
        /// French name, the last word before the first comma of an English one ("Whole
        /// Milk", "Chicken Breast, Raw").
        var matchesHead: Bool
        /// The first query word is the first word of the name.
        var startsWith: Bool
        /// Name words not matched by the query (stop words excluded).
        var extraWords: Int

        var isExact: Bool { quality == 1 && extraWords == 0 }

        static func < (a: NameMatch, b: NameMatch) -> Bool { a.points < b.points }

        var points: Double {
            var p = quality * 10
            if matchesAll { p += 6 }
            if matchesHead { p += 3 }
            if startsWith { p += 1 }
            p += isExact ? 4 : -0.8 * Double(min(extraWords, 8))
            return p
        }
    }

    func score(_ candidate: SearchCandidate, timesLogged: Int = 0) -> Double {
        var display = candidate.name
        if let b = candidate.brand, display.hasSuffix(" by \(b)") { display = String(display.dropLast(b.count + 4)) }
        let isFrench = candidate.englishName != nil
        var nameMatch = matcher.match(name: display, brand: candidate.brand, headFirst: isFrench)
        if let english = candidate.englishName {
            nameMatch = max(nameMatch, matcher.match(name: english, brand: candidate.brand, headFirst: false))
        }
        if isFrench, let typedMatcher {
            nameMatch = max(nameMatch, typedMatcher.match(name: display, brand: candidate.brand, headFirst: true))
        }
        var s = nameMatch.points
        switch candidate.kind {
        case .everyday: s += 4
        case .prepared: s += 2
        case .restaurant: break
        case .grocery: s -= 2
        }
        // Staples, when they are what the query names ("Thon au naturel" for "thon", not for
        // "eau" through "Tuna, Canned in Water").
        if candidate.stapleRank > 0, nameMatch.matchesAll {
            if nameMatch.quality == 1, nameMatch.matchesHead {
                s += candidate.stapleRank >= 2 ? 9 : 5
            } else {
                s += 2
            }
        }
        if timesLogged > 0 { s += (nameMatch.matchesAll ? 10 : 4) + Double(min(timesLogged, 5)) }
        return s - Double(display.count) * 0.01
    }
}

/// Matches a name against query terms (see `SearchRanking`).
private struct Matcher: Sendable {
    let terms: [SearchTerm]
    /// Per term and alternative: singular / plural forms of a prefix alternative's last
    /// token, which count as whole words ("egg" typed, "Eggs" in the name).
    private let prefixForms: [[Set<String>]]

    init(terms: [SearchTerm]) {
        self.terms = terms
        prefixForms = terms.map { term in
            term.alternatives.map { alternative in
                guard alternative.isPrefix, let last = alternative.tokens.last else { return [] }
                return Set(FoodDatabase.wordForms(last))
            }
        }
    }

    typealias NameMatch = SearchRanking.NameMatch

    /// - Parameter headFirst: French name (main word first) rather than English (main word
    ///   last, before the first comma).
    func match(name text: String, brand: String?, headFirst: Bool) -> NameMatch {
        let name: [String]
        let head: Int
        if let comma = text.firstIndex(of: ",") {
            let first = FoodDatabase.tokens(of: String(text[..<comma]))
            name = first + FoodDatabase.tokens(of: String(text[comma...]))
            head = headFirst ? 0 : max(0, first.count - 1)
        } else {
            name = FoodDatabase.tokens(of: text)
            head = headFirst ? 0 : max(0, name.count - 1)
        }
        guard !terms.isEmpty, !name.isEmpty else {
            return NameMatch(quality: 0, matchesAll: false, matchesHead: false, startsWith: false, extraWords: name.count)
        }
        var brandTokens: [String]?
        var used = [Bool](repeating: false, count: name.count)
        var total = 0.0
        var matchesAll = true
        var matchesHead = false
        var startsWith = false
        for (index, term) in terms.enumerated() {
            var best = 0.0
            var bestRange: Range<Int>?
            for (a, alternative) in term.alternatives.enumerated() {
                let n = alternative.tokens.count
                guard n > 0, n <= name.count else { continue }
                for start in 0...(name.count - n) {
                    let q = quality(of: alternative, forms: prefixForms[index][a], at: start, in: name)
                    guard q > 0 else { continue }
                    if q == 3, start <= head, head < start + n { matchesHead = true }
                    if q > best || (q == best && start == 0) {
                        best = q
                        bestRange = start..<(start + n)
                    }
                }
            }
            if let range = bestRange {
                for i in range { used[i] = true }
                if index == 0, range.lowerBound == 0 { startsWith = true }
            } else if let brand {
                // Brand-only match ("danone"): counts, but less than the name.
                let tokens = brandTokens ?? FoodDatabase.tokens(of: brand)
                brandTokens = tokens
                if term.alternatives.contains(where: { alternative in
                    alternative.tokens.allSatisfy { t in tokens.contains { $0 == t || (alternative.isPrefix && $0.hasPrefix(t)) } }
                }) {
                    best = 1.5
                }
            }
            if best == 0 { matchesAll = false }
            total += best
        }
        var extra = 0
        for i in name.indices where !used[i] && !FrenchFoodLexicon.stopWords.contains(name[i]) { extra += 1 }
        return NameMatch(quality: total / Double(terms.count * 3), matchesAll: matchesAll,
                         matchesHead: matchesHead, startsWith: startsWith, extraWords: extra)
    }

    /// 3 = whole words (singular or plural), 1.5 = the last token is only the beginning of
    /// a longer name word ("egg" in "Eggplant"), 0 = no match.
    private func quality(of alternative: SearchAlternative, forms: Set<String>, at start: Int, in name: [String]) -> Double {
        var q = 3.0
        let last = alternative.tokens.count - 1
        for (k, want) in alternative.tokens.enumerated() {
            let token = name[start + k]
            if token == want { continue }
            if k == last, alternative.isPrefix {
                if forms.contains(token) { continue }
                if token.hasPrefix(want) { q = 1.5; continue }
            }
            return 0
        }
        return q
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
