import Foundation
import SwiftData

/// JSON backup of all user data (journal, weights, water, custom foods, favorites, profile,
/// coaching exception periods and check-in history).
struct ProfileBackup: Codable {
    static let currentVersion = 1

    var version: Int
    var app: String
    var exportedAt: Date
    var entries: [Entry]
    var weights: [Weight]
    var water: [Water]
    var customFoods: [Custom]
    var favorites: [Favorite]
    var profile: Profile?
    /// Coaching exception periods (absent from backups made before coaching).
    var exceptions: [Exception]
    /// Coaching history: weekly check-ins and program changes (absent before coaching).
    var checkIns: [CheckIn]

    var healthDays: [Health] = []
    var programPreferences: ProgramPreferences?
    var weekdayCalorieTargets: [Int: Int]?
    /// Display preferences (`@AppStorage` toggles), only the ones the user has set.
    var settings: [String: Bool]?

    static let settingKeys = ["dashboard.showRemaining", "dashboard.balanceExpenditure",
                              "today.headerShowsConsumed", "today.hideFoodDetails", "today.hideEmptyHours"]

    struct Health: Codable {
        var day: Date
        var kcal: Double
        var protein: Double?
        var carbs: Double?
        var fat: Double?
    }

    struct Entry: Codable {
        var id: UUID
        var day: Date
        var meal: String
        var createdAt: Date
        var name: String
        var brand: String?
        var source: String
        var ref: String?
        var kind: Int?
        var servingLabel: String?
        var servingGrams: Double?
        var isLiquid: Bool
        var grams: Double
        var per100: NutrientValues
    }

    struct Weight: Codable {
        var date: Date
        var kg: Double
    }

    struct Water: Codable {
        var day: Date
        var createdAt: Date
        var ml: Double
    }

    struct Custom: Codable {
        var id: UUID
        var createdAt: Date
        var name: String
        var brand: String?
        var ean: String?
        var isLiquid: Bool
        var servingLabel: String?
        var servingGrams: Double?
        var per100: NutrientValues
        var ingredients: [RecipeIngredient]?
        var totalGrams: Double?
    }

    struct Favorite: Codable {
        var key: String
        var createdAt: Date
        var name: String
        var brand: String?
        var source: String
        var ref: String?
        var kind: Int?
        var servingLabel: String?
        var servingGrams: Double?
        var isLiquid: Bool
        var per100: NutrientValues
    }

    struct Profile: Codable {
        var sex: String
        var birthYear: Int
        var heightCm: Double
        var weightKg: Double
        var activity: String
        var goal: String
        var weeklyRateKg: Double
        var targetWeightKg: Double?
        var calorieTarget: Double
        var proteinTarget: Double
        var carbsTarget: Double
        var fatTarget: Double
        var fiberTarget: Double
        var waterTargetMl: Double
        var manualTargets: Bool
        // Coaching (optional: older backups do not have them).
        var createdAt: Date?
        var weeklyRatePercent: Double?
        var checkInWeekday: Int?
        var lastCheckInDate: Date?
        var initialExpenditure: Double?
        var expenditureAnchorKcal: Double?
        var expenditureAnchorDate: Date?
        /// `@AppStorage("coaching.collaborative")`.
        var collaborative: Bool?
        var displayName: String?
        var hasCompletedOnboarding: Bool?
    }

    struct Exception: Codable {
        var id: UUID
        var start: Date
        var end: Date
        var note: String

        private enum CodingKeys: String, CodingKey { case id, start, end, note }

        init(id: UUID, start: Date, end: Date, note: String) {
            self.id = id
            self.start = start
            self.end = end
            self.note = note
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            start = try c.decode(Date.self, forKey: .start)
            end = try c.decodeIfPresent(Date.self, forKey: .end) ?? start
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        }
    }

    struct CheckIn: Codable {
        var date: Date
        var kind: String
        var expenditure: Double
        var trendKg: Double?
        var scaleKg: Double?
        var averageIntake: Double?
        var goal: String
        var ratePercent: Double
        var calorieTarget: Double
        var proteinTarget: Double
        var carbsTarget: Double
        var fatTarget: Double

        private enum CodingKeys: String, CodingKey {
            case date, kind, expenditure, trendKg, scaleKg, averageIntake, goal, ratePercent
            case calorieTarget, proteinTarget, carbsTarget, fatTarget
        }

        init(date: Date, kind: String, expenditure: Double, trendKg: Double?, scaleKg: Double?,
             averageIntake: Double?, goal: String, ratePercent: Double, calorieTarget: Double,
             proteinTarget: Double, carbsTarget: Double, fatTarget: Double)
        {
            self.date = date
            self.kind = kind
            self.expenditure = expenditure
            self.trendKg = trendKg
            self.scaleKg = scaleKg
            self.averageIntake = averageIntake
            self.goal = goal
            self.ratePercent = ratePercent
            self.calorieTarget = calorieTarget
            self.proteinTarget = proteinTarget
            self.carbsTarget = carbsTarget
            self.fatTarget = fatTarget
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(Date.self, forKey: .date)
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "weekly"
            expenditure = try c.decodeIfPresent(Double.self, forKey: .expenditure) ?? 0
            trendKg = try c.decodeIfPresent(Double.self, forKey: .trendKg)
            scaleKg = try c.decodeIfPresent(Double.self, forKey: .scaleKg)
            averageIntake = try c.decodeIfPresent(Double.self, forKey: .averageIntake)
            goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? WeightGoal.maintain.rawValue
            ratePercent = try c.decodeIfPresent(Double.self, forKey: .ratePercent) ?? 0
            calorieTarget = try c.decodeIfPresent(Double.self, forKey: .calorieTarget) ?? 0
            proteinTarget = try c.decodeIfPresent(Double.self, forKey: .proteinTarget) ?? 0
            carbsTarget = try c.decodeIfPresent(Double.self, forKey: .carbsTarget) ?? 0
            fatTarget = try c.decodeIfPresent(Double.self, forKey: .fatTarget) ?? 0
        }
    }

    init(version: Int = ProfileBackup.currentVersion, app: String = "Assiette", exportedAt: Date = .now,
         entries: [Entry] = [], weights: [Weight] = [], water: [Water] = [],
         customFoods: [Custom] = [], favorites: [Favorite] = [], profile: Profile? = nil,
         exceptions: [Exception] = [], checkIns: [CheckIn] = [])
    {
        self.version = version
        self.app = app
        self.exportedAt = exportedAt
        self.entries = entries
        self.weights = weights
        self.water = water
        self.customFoods = customFoods
        self.favorites = favorites
        self.profile = profile
        self.exceptions = exceptions
        self.checkIns = checkIns
    }

    private enum CodingKeys: String, CodingKey {
        case version, app, exportedAt, entries, weights, water, customFoods, favorites, profile
        case exceptions, checkIns, healthDays, programPreferences, weekdayCalorieTargets, settings
    }

    /// Lenient decoding: missing arrays are treated as empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? "Assiette"
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        weights = try c.decodeIfPresent([Weight].self, forKey: .weights) ?? []
        water = try c.decodeIfPresent([Water].self, forKey: .water) ?? []
        customFoods = try c.decodeIfPresent([Custom].self, forKey: .customFoods) ?? []
        favorites = try c.decodeIfPresent([Favorite].self, forKey: .favorites) ?? []
        profile = try c.decodeIfPresent(Profile.self, forKey: .profile)
        healthDays = (try? c.decodeIfPresent([Health].self, forKey: .healthDays)) ?? []
        programPreferences = try? c.decodeIfPresent(ProgramPreferences.self, forKey: .programPreferences)
        weekdayCalorieTargets = try? c.decodeIfPresent([Int: Int].self, forKey: .weekdayCalorieTargets)
        settings = try? c.decodeIfPresent([String: Bool].self, forKey: .settings)
        // Coaching data is optional and must never make an otherwise valid backup unreadable.
        exceptions = (try? c.decodeIfPresent([Exception].self, forKey: .exceptions)) ?? []
        checkIns = (try? c.decodeIfPresent([CheckIn].self, forKey: .checkIns)) ?? []
    }

    var isEmpty: Bool {
        entries.isEmpty && weights.isEmpty && water.isEmpty && customFoods.isEmpty
            && favorites.isEmpty && profile == nil && exceptions.isEmpty && checkIns.isEmpty && healthDays.isEmpty
    }

    /// "123 entrées, 12 pesées, …" (French summary of the content).
    var contentSummary: String {
        var parts: [String] = []
        parts.append(ProfileBackup.plural(entries.count, "entrée du journal", "entrées du journal"))
        parts.append(ProfileBackup.plural(weights.count, "pesée", "pesées"))
        parts.append(ProfileBackup.plural(water.count, "ajout d'eau", "ajouts d'eau"))
        parts.append(ProfileBackup.plural(customFoods.count, "aliment perso", "aliments perso"))
        parts.append(ProfileBackup.plural(favorites.count, "favori", "favoris"))
        if !exceptions.isEmpty { parts.append(ProfileBackup.plural(exceptions.count, "exception", "exceptions")) }
        if !checkIns.isEmpty { parts.append(ProfileBackup.plural(checkIns.count, "bilan", "bilans")) }
        if !healthDays.isEmpty { parts.append("\(healthDays.count) j. Santé") }
        if profile != nil { parts.append("profil") }
        return parts.joined(separator: ", ")
    }

    static func plural(_ n: Int, _ singular: String, _ pluralForm: String) -> String {
        "\(n) \(n > 1 ? pluralForm : singular)"
    }
}

enum ProfileImportMode {
    /// Delete current data then restore the backup (profile included).
    case replace
    /// Add missing items, keep the current profile.
    case merge
}

struct ProfileImportResult {
    var entries = 0
    var weights = 0
    var water = 0
    var customFoods = 0
    var favorites = 0
    var exceptions = 0
    var checkIns = 0
    var profileRestored = false

    var summary: String {
        var parts = [
            ProfileBackup.plural(entries, "entrée", "entrées"),
            ProfileBackup.plural(weights, "pesée", "pesées"),
            ProfileBackup.plural(water, "ajout d'eau", "ajouts d'eau"),
            ProfileBackup.plural(customFoods, "aliment perso", "aliments perso"),
            ProfileBackup.plural(favorites, "favori", "favoris"),
        ]
        if exceptions > 0 { parts.append(ProfileBackup.plural(exceptions, "exception", "exceptions")) }
        if checkIns > 0 { parts.append(ProfileBackup.plural(checkIns, "bilan", "bilans")) }
        if profileRestored { parts.append("profil restauré") }
        return "Importé : " + parts.joined(separator: ", ") + "."
    }
}

enum ProfileBackupError: LocalizedError {
    case unreadable
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Impossible de lire le fichier."
        case .invalidFormat: return "Ce fichier n'est pas une sauvegarde Assiette valide."
        }
    }
}

/// Export / import / reset of all SwiftData user data.
@MainActor
enum ProfileBackupService {
    // MARK: - Build

    static func makeBackup(context: ModelContext) throws -> ProfileBackup {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\JournalEntry.day), SortDescriptor(\JournalEntry.createdAt)]))
        let weights = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\WeightEntry.date)]))
        let water = try context.fetch(FetchDescriptor<WaterEntry>(sortBy: [SortDescriptor(\WaterEntry.createdAt)]))
        let customs = try context.fetch(FetchDescriptor<CustomFood>(sortBy: [SortDescriptor(\CustomFood.createdAt)]))
        let favorites = try context.fetch(FetchDescriptor<FavoriteFood>(sortBy: [SortDescriptor(\FavoriteFood.createdAt)]))
        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        let exceptions = try context.fetch(FetchDescriptor<ExceptionPeriod>(sortBy: [SortDescriptor(\ExceptionPeriod.start)]))
        let checkIns = try context.fetch(FetchDescriptor<CoachingCheckIn>(sortBy: [SortDescriptor(\CoachingCheckIn.date)]))
        let health = try context.fetch(FetchDescriptor<HealthDay>(sortBy: [SortDescriptor(\HealthDay.day)]))

        var backup = ProfileBackup()
        backup.healthDays = health.map { .init(day: $0.day, kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat) }
        backup.programPreferences = ProgramPreferences.current
        backup.weekdayCalorieTargets = WeekdayCalorieTargets.current.values
        backup.settings = ProfileBackup.settingKeys.reduce(into: [String: Bool]()) { result, key in
            if let value = UserDefaults.standard.object(forKey: key) as? Bool { result[key] = value }
        }
        backup.entries = entries.map { e in
            ProfileBackup.Entry(id: e.id, day: e.day, meal: e.mealRaw, createdAt: e.createdAt, name: e.name,
                                brand: e.brand, source: e.sourceRaw, ref: e.ref, kind: e.kindRaw,
                                servingLabel: e.servingLabel, servingGrams: e.servingGrams,
                                isLiquid: e.isLiquid, grams: e.grams, per100: e.per100)
        }
        backup.weights = weights.map { ProfileBackup.Weight(date: $0.date, kg: $0.kg) }
        backup.water = water.map { ProfileBackup.Water(day: $0.day, createdAt: $0.createdAt, ml: $0.ml) }
        backup.customFoods = customs.map { f in
            ProfileBackup.Custom(id: f.id, createdAt: f.createdAt, name: f.name, brand: f.brand, ean: f.ean,
                                 isLiquid: f.isLiquid, servingLabel: f.servingLabel,
                                 servingGrams: f.servingGrams, per100: f.per100,
                                 ingredients: f.isRecipe ? f.ingredients : nil, totalGrams: f.totalGrams)
        }
        backup.favorites = favorites.map { f in
            ProfileBackup.Favorite(key: f.key, createdAt: f.createdAt, name: f.name, brand: f.brand,
                                   source: f.sourceRaw, ref: f.ref, kind: f.kindRaw,
                                   servingLabel: f.servingLabel, servingGrams: f.servingGrams,
                                   isLiquid: f.isLiquid, per100: NutrientValues(data: f.per100Data))
        }
        if let p = profile {
            backup.profile = ProfileBackup.Profile(
                sex: p.sexRaw, birthYear: p.birthYear, heightCm: p.heightCm, weightKg: p.weightKg,
                activity: p.activityRaw, goal: p.goalRaw, weeklyRateKg: p.weeklyRateKg,
                targetWeightKg: p.targetWeightKg, calorieTarget: p.calorieTarget,
                proteinTarget: p.proteinTarget, carbsTarget: p.carbsTarget, fatTarget: p.fatTarget,
                fiberTarget: p.fiberTarget, waterTargetMl: p.waterTargetMl, manualTargets: p.manualTargets,
                createdAt: p.createdAt, weeklyRatePercent: p.weeklyRatePercent,
                checkInWeekday: p.checkInWeekday, lastCheckInDate: p.lastCheckInDate,
                initialExpenditure: p.initialExpenditure,
                expenditureAnchorKcal: p.expenditureAnchorKcal,
                expenditureAnchorDate: p.expenditureAnchorDate,
                collaborative: UserDefaults.standard.bool(forKey: CoachingSettings.collaborativeKey),
                displayName: UserDefaults.standard.string(forKey: "profile.displayName"),
                hasCompletedOnboarding: p.hasCompletedOnboarding)
        }
        backup.exceptions = exceptions.map {
            ProfileBackup.Exception(id: $0.id, start: $0.start, end: $0.end, note: $0.note)
        }
        backup.checkIns = checkIns.map { r in
            ProfileBackup.CheckIn(date: r.date, kind: r.kindRaw, expenditure: r.expenditure, trendKg: r.trendKg,
                                  scaleKg: r.scaleKg, averageIntake: r.averageIntake, goal: r.goalRaw,
                                  ratePercent: r.ratePercent, calorieTarget: r.calorieTarget,
                                  proteinTarget: r.proteinTarget, carbsTarget: r.carbsTarget,
                                  fatTarget: r.fatTarget)
        }
        return backup
    }

    static func encode(_ backup: ProfileBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> ProfileBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ProfileBackup.self, from: data)
        } catch {
            throw ProfileBackupError.invalidFormat
        }
    }

    /// Reads a backup from a file picked with `fileImporter` (handles security-scoped URLs).
    static func readBackup(at url: URL) throws -> ProfileBackup {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ProfileBackupError.unreadable }
        return try decode(data)
    }

    // MARK: - CSV

    static let csvHeader = "date;repas;aliment;marque;quantite_g;kcal;proteines_g;glucides_g;lipides_g;fibres_g"

    static func journalCSV(context: ModelContext) throws -> (csv: String, rows: Int) {
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\JournalEntry.day), SortDescriptor(\JournalEntry.createdAt)]))
        let sorted = entries.sorted { a, b in
            if a.day != b.day { return a.day < b.day }
            if a.meal.order != b.meal.order { return a.meal.order < b.meal.order }
            return a.createdAt < b.createdAt
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var lines = [csvHeader]
        lines.reserveCapacity(sorted.count + 1)
        for e in sorted {
            let n = e.nutrients
            let fields = [
                dayFormatter.string(from: e.day),
                csvField(e.meal.label),
                csvField(e.name),
                csvField(e.brand ?? ""),
                csvNumber(e.grams, digits: 1),
                csvNumber(n.calories, digits: 0),
                csvNumber(n.protein, digits: 1),
                csvNumber(n.carbs, digits: 1),
                csvNumber(n.fat, digits: 1),
                csvNumber(n.value(.dietaryFiber), digits: 1),
            ]
            lines.append(fields.joined(separator: ";"))
        }
        return (lines.joined(separator: "\r\n") + "\r\n", sorted.count)
    }

    private static func csvField(_ s: String) -> String {
        if s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// French decimal comma, no grouping.
    private static func csvNumber(_ v: Double, digits: Int) -> String {
        let value = v.isFinite ? v : 0
        return String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Files

    /// Writes "Assiette-journal-<date>.csv" and "Assiette-sauvegarde-<date>.json" into the temp directory.
    static func writeExportFiles(context: ModelContext) throws -> (csv: URL, json: URL, entryCount: Int, backup: ProfileBackup) {
        let stamp = fileStamp()
        let dir = FileManager.default.temporaryDirectory
        let csvURL = dir.appendingPathComponent("Assiette-journal-\(stamp).csv")
        let jsonURL = dir.appendingPathComponent("Assiette-sauvegarde-\(stamp).json")

        let (csv, rows) = try journalCSV(context: context)
        // UTF-8 BOM so spreadsheet apps detect the encoding (accents).
        var csvData = Data([0xEF, 0xBB, 0xBF])
        csvData.append(Data(csv.utf8))
        try csvData.write(to: csvURL, options: .atomic)

        let backup = try makeBackup(context: context)
        try encode(backup).write(to: jsonURL, options: .atomic)
        return (csvURL, jsonURL, rows, backup)
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    // MARK: - Import

    @discardableResult
    static func importBackup(_ backup: ProfileBackup, mode: ProfileImportMode,
                             context: ModelContext) throws -> ProfileImportResult
    {
        var result = ProfileImportResult()
        if mode == .replace {
            try deleteUserData(context: context)
        }

        // Journal
        let existingEntryIDs: Set<UUID> = try mode == .merge
            ? Set(context.fetch(FetchDescriptor<JournalEntry>()).map(\.id)) : []
        for dto in backup.entries where !existingEntryIDs.contains(dto.id) {
            let item = FoodItem(source: FoodSource(rawValue: dto.source) ?? .quickAdd, ref: dto.ref,
                                name: dto.name, brand: dto.brand,
                                kind: dto.kind.flatMap(FoodKind.init(rawValue:)),
                                servingLabel: dto.servingLabel, servingGrams: dto.servingGrams,
                                packageGrams: nil, isLiquid: dto.isLiquid, ean: nil, per100: dto.per100)
            let entry = JournalEntry(item: item, grams: dto.grams, day: dto.day,
                                     meal: Meal(rawValue: dto.meal) ?? .snack)
            entry.id = dto.id
            entry.mealRaw = dto.meal
            entry.createdAt = dto.createdAt
            entry.sourceRaw = dto.source
            context.insert(entry)
            result.entries += 1
        }

        // Weights
        func weightKey(_ date: Date, _ kg: Double) -> String {
            "\(Int(date.timeIntervalSince1970.rounded()))|\(kg)"
        }
        let existingWeights: Set<String> = try mode == .merge
            ? Set(context.fetch(FetchDescriptor<WeightEntry>()).map { weightKey($0.date, $0.kg) }) : []
        for dto in backup.weights where !existingWeights.contains(weightKey(dto.date, dto.kg)) {
            context.insert(WeightEntry(date: dto.date, kg: dto.kg))
            result.weights += 1
        }

        // Water
        func waterKey(_ created: Date, _ ml: Double) -> String {
            "\(Int(created.timeIntervalSince1970.rounded()))|\(ml)"
        }
        let existingWater: Set<String> = try mode == .merge
            ? Set(context.fetch(FetchDescriptor<WaterEntry>()).map { waterKey($0.createdAt, $0.ml) }) : []
        for dto in backup.water where !existingWater.contains(waterKey(dto.createdAt, dto.ml)) {
            let w = WaterEntry(day: dto.day, ml: dto.ml)
            w.createdAt = dto.createdAt
            context.insert(w)
            result.water += 1
        }

        // Custom foods
        let existingCustom: Set<UUID> = try mode == .merge
            ? Set(context.fetch(FetchDescriptor<CustomFood>()).map(\.id)) : []
        for dto in backup.customFoods where !existingCustom.contains(dto.id) {
            let f = CustomFood(name: dto.name, brand: dto.brand, per100: dto.per100)
            f.id = dto.id
            f.createdAt = dto.createdAt
            f.ean = dto.ean
            f.isLiquid = dto.isLiquid
            f.servingLabel = dto.servingLabel
            f.servingGrams = dto.servingGrams
            if let ingredients = dto.ingredients {
                f.ingredients = ingredients
            }
            f.totalGrams = dto.totalGrams
            context.insert(f)
            result.customFoods += 1
        }

        // Favorites
        let existingFavorites: Set<String> = try mode == .merge
            ? Set(context.fetch(FetchDescriptor<FavoriteFood>()).map(\.key)) : []
        var seenFavorites = existingFavorites
        for dto in backup.favorites where !seenFavorites.contains(dto.key) {
            seenFavorites.insert(dto.key)
            let item = FoodItem(source: FoodSource(rawValue: dto.source) ?? .openNutrition, ref: dto.ref,
                                name: dto.name, brand: dto.brand,
                                kind: dto.kind.flatMap(FoodKind.init(rawValue:)),
                                servingLabel: dto.servingLabel, servingGrams: dto.servingGrams,
                                packageGrams: nil, isLiquid: dto.isLiquid, ean: nil, per100: dto.per100)
            let fav = FavoriteFood(item: item)
            fav.key = dto.key
            fav.createdAt = dto.createdAt
            context.insert(fav)
            result.favorites += 1
        }

        // Coaching exception periods
        let existingExceptions: Set<UUID> = mode == .merge
            ? Set(((try? context.fetch(FetchDescriptor<ExceptionPeriod>())) ?? []).map(\.id)) : []
        for dto in backup.exceptions where !existingExceptions.contains(dto.id) {
            let period = ExceptionPeriod(start: dto.start, end: dto.end, note: dto.note)
            period.id = dto.id
            context.insert(period)
            result.exceptions += 1
        }

        // Coaching history (one row per day and kind)
        func checkInKey(_ date: Date, _ kind: String) -> String {
            "\(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))|\(kind)"
        }
        var seenCheckIns: Set<String> = mode == .merge
            ? Set(((try? context.fetch(FetchDescriptor<CoachingCheckIn>())) ?? []).map { checkInKey($0.date, $0.kindRaw) })
            : []
        for dto in backup.checkIns where !seenCheckIns.contains(checkInKey(dto.date, dto.kind)) {
            seenCheckIns.insert(checkInKey(dto.date, dto.kind))
            let row = CoachingCheckIn(date: dto.date, kindRaw: dto.kind)
            row.expenditure = dto.expenditure
            row.trendKg = dto.trendKg
            row.scaleKg = dto.scaleKg
            row.averageIntake = dto.averageIntake
            row.goalRaw = dto.goal
            row.ratePercent = dto.ratePercent
            row.calorieTarget = dto.calorieTarget
            row.proteinTarget = dto.proteinTarget
            row.carbsTarget = dto.carbsTarget
            row.fatTarget = dto.fatTarget
            context.insert(row)
            result.checkIns += 1
        }

        var existingHealthDays = try Set(context.fetch(FetchDescriptor<HealthDay>()).map { $0.day.startOfDay })
        for dto in backup.healthDays where existingHealthDays.insert(dto.day.startOfDay).inserted {
            let health = HealthDay(day: dto.day, kcal: dto.kcal)
            health.protein = dto.protein
            health.carbs = dto.carbs
            health.fat = dto.fat
            context.insert(health)
        }

        // Profile (replace only; merge keeps the current profile)
        let profile = UserProfile.current(in: context)
        if let dto = backup.profile, mode == .replace || !profile.hasCompletedOnboarding {
            profile.sexRaw = dto.sex
            profile.birthYear = dto.birthYear
            profile.heightCm = dto.heightCm
            profile.weightKg = dto.weightKg
            profile.activityRaw = dto.activity
            profile.goalRaw = dto.goal
            profile.weeklyRateKg = dto.weeklyRateKg
            profile.targetWeightKg = dto.targetWeightKg
            profile.calorieTarget = dto.calorieTarget
            profile.proteinTarget = dto.proteinTarget
            profile.carbsTarget = dto.carbsTarget
            profile.fatTarget = dto.fatTarget
            profile.fiberTarget = dto.fiberTarget
            profile.waterTargetMl = dto.waterTargetMl
            profile.manualTargets = dto.manualTargets
            if let createdAt = dto.createdAt { profile.createdAt = createdAt }
            // Older backups: derive the % rate from kg, schedule the first check-in a week from now.
            profile.weeklyRatePercent = dto.weeklyRatePercent
                ?? (dto.weightKg > 0 ? dto.weeklyRateKg / dto.weightKg * 100 : 0)
            profile.checkInWeekday = dto.checkInWeekday.map { min(7, max(1, $0)) }
                ?? Calendar.current.component(.weekday, from: .now)
            profile.lastCheckInDate = dto.lastCheckInDate ?? Calendar.current.startOfDay(for: .now)
            profile.initialExpenditure = dto.initialExpenditure
            if mode == .replace {
                profile.expenditureAnchorKcal = dto.expenditureAnchorKcal
                profile.expenditureAnchorDate = dto.expenditureAnchorDate
            } else if let kcal = dto.expenditureAnchorKcal, let date = dto.expenditureAnchorDate {
                profile.expenditureAnchorKcal = kcal
                profile.expenditureAnchorDate = date
            }
            if let collaborative = dto.collaborative {
                UserDefaults.standard.set(collaborative, forKey: CoachingSettings.collaborativeKey)
            }
            profile.hasCompletedOnboarding = dto.hasCompletedOnboarding ?? true
            result.profileRestored = true
        }

        try context.save()
        if mode == .replace || result.profileRestored {
            backup.programPreferences?.save()
            if let values = backup.weekdayCalorieTargets {
                for day in 1...7 { _ = WeekdayCalorieTargets.set(values[day], forISOWeekday: day) }
            } else if mode == .replace {
                UserDefaults.standard.removeObject(forKey: WeekdayCalorieTargets.storageKey)
            }
            if let name = backup.profile?.displayName { UserDefaults.standard.set(name, forKey: "profile.displayName") }
            for key in ProfileBackup.settingKeys {
                if let value = backup.settings?[key] {
                    UserDefaults.standard.set(value, forKey: key)
                } else if mode == .replace, backup.settings != nil {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        return result
    }

    // MARK: - Reset

    /// Deletes every journal entry, weight, water entry, custom food, favorite, exception period and
    /// coaching history row (not the profile).
    static func deleteUserData(context: ModelContext) throws {
        // Delete object by object (batch deletes do not always refresh @Query on iOS 17).
        for e in try context.fetch(FetchDescriptor<JournalEntry>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<WeightEntry>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<WaterEntry>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<CustomFood>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<FavoriteFood>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<ExceptionPeriod>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<CoachingCheckIn>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<HealthDay>()) { context.delete(e) }
        try context.save()
        // The next Apple Health sync imports the weigh-ins again (deduplicated against the backup).
        HealthImport.resetWeightAnchor()
    }

    /// Erases everything and resets the profile to defaults, which brings back the onboarding.
    static func eraseEverything(context: ModelContext) throws {
        try deleteUserData(context: context)
        let profile = UserProfile.current(in: context)
        let defaults = UserProfile()
        profile.sexRaw = defaults.sexRaw
        profile.birthYear = defaults.birthYear
        profile.heightCm = defaults.heightCm
        profile.weightKg = defaults.weightKg
        profile.activityRaw = defaults.activityRaw
        profile.goalRaw = defaults.goalRaw
        profile.weeklyRateKg = defaults.weeklyRateKg
        profile.targetWeightKg = nil
        profile.calorieTarget = defaults.calorieTarget
        profile.proteinTarget = defaults.proteinTarget
        profile.carbsTarget = defaults.carbsTarget
        profile.fatTarget = defaults.fatTarget
        profile.fiberTarget = defaults.fiberTarget
        profile.waterTargetMl = defaults.waterTargetMl
        profile.manualTargets = false
        profile.weeklyRatePercent = defaults.weeklyRatePercent
        profile.checkInWeekday = defaults.checkInWeekday
        profile.lastCheckInDate = nil
        profile.initialExpenditure = nil
        profile.expenditureAnchorKcal = nil
        profile.expenditureAnchorDate = nil
        profile.createdAt = .now
        profile.hasCompletedOnboarding = false
        try context.save()
        UserDefaults.standard.removeObject(forKey: CoachingSettings.collaborativeKey)
        UserDefaults.standard.removeObject(forKey: WeekdayCalorieTargets.storageKey)
        UserDefaults.standard.removeObject(forKey: ProgramPreferences.storageKey)
        HealthImport.disconnect()

        let store = UserDefaults.standard
        for key in store.dictionaryRepresentation().keys where key.hasPrefix("lastGrams.") {
            store.removeObject(forKey: key)
        }
    }
}
