import Foundation

/// Nutrients tracked by the app. Raw values are the OpenNutrition keys and the
/// column names in the bundled `foods.sqlite` (see tools/build_db.py — keep in sync).
/// All values are stored per 100 g (or per 100 ml for liquids).
enum NutrientKey: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case calories
    case protein
    case carbohydrates
    case totalFat = "total_fat"
    case saturatedFats = "saturated_fats"
    case monounsaturatedFats = "monounsaturated_fats"
    case polyunsaturatedFats = "polyunsaturated_fats"
    case transFats = "trans_fats"
    case cholesterol
    case dietaryFiber = "dietary_fiber"
    case totalSugars = "total_sugars"
    case addedSugars = "added_sugars"
    case sodium
    case potassium
    case calcium
    case iron
    case magnesium
    case zinc
    case phosphorus
    case vitaminA = "vitamin_a"
    case vitaminC = "vitamin_c"
    case vitaminD = "vitamin_d"
    case vitaminE = "vitamin_e"
    case vitaminK = "vitamin_k"
    case thiamin
    case riboflavin
    case niacin
    case vitaminB6 = "vitamin_b6"
    case folate = "folate_dfe"
    case vitaminB12 = "vitamin_b12"
    case omega3 = "omega_3"
    case caffeine
    case alcohol = "ethyl_alcohol"
    case water

    var id: String { rawValue }

    enum Group: String, CaseIterable, Sendable {
        case energy, macros, fats, carbs, minerals, vitamins, other

        var label: String {
            switch self {
            case .energy: "Énergie"
            case .macros: "Macronutriments"
            case .fats: "Lipides"
            case .carbs: "Glucides"
            case .minerals: "Minéraux"
            case .vitamins: "Vitamines"
            case .other: "Autres"
            }
        }
    }

    /// French display name.
    var label: String {
        switch self {
        case .calories: "Calories"
        case .protein: "Protéines"
        case .carbohydrates: "Glucides"
        case .totalFat: "Lipides"
        case .saturatedFats: "Acides gras saturés"
        case .monounsaturatedFats: "Acides gras mono-insaturés"
        case .polyunsaturatedFats: "Acides gras polyinsaturés"
        case .transFats: "Acides gras trans"
        case .cholesterol: "Cholestérol"
        case .dietaryFiber: "Fibres"
        case .totalSugars: "Sucres"
        case .addedSugars: "Sucres ajoutés"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .iron: "Fer"
        case .magnesium: "Magnésium"
        case .zinc: "Zinc"
        case .phosphorus: "Phosphore"
        case .vitaminA: "Vitamine A"
        case .vitaminC: "Vitamine C"
        case .vitaminD: "Vitamine D"
        case .vitaminE: "Vitamine E"
        case .vitaminK: "Vitamine K"
        case .thiamin: "Vitamine B1 (thiamine)"
        case .riboflavin: "Vitamine B2 (riboflavine)"
        case .niacin: "Vitamine B3 (niacine)"
        case .vitaminB6: "Vitamine B6"
        case .folate: "Vitamine B9 (folates)"
        case .vitaminB12: "Vitamine B12"
        case .omega3: "Oméga-3"
        case .caffeine: "Caféine"
        case .alcohol: "Alcool"
        case .water: "Eau"
        }
    }

    /// Short label for compact UI (macro rings, chips).
    var shortLabel: String {
        switch self {
        case .calories: "kcal"
        case .protein: "Prot."
        case .carbohydrates: "Gluc."
        case .totalFat: "Lip."
        case .dietaryFiber: "Fibres"
        case .totalSugars: "Sucres"
        default: label
        }
    }

    /// Unit of the stored value.
    var unit: String {
        switch self {
        case .calories: "kcal"
        case .protein, .carbohydrates, .totalFat, .saturatedFats, .monounsaturatedFats,
             .polyunsaturatedFats, .transFats, .dietaryFiber, .totalSugars, .addedSugars,
             .omega3, .alcohol, .water:
            "g"
        case .cholesterol, .sodium, .potassium, .calcium, .iron, .magnesium, .zinc,
             .phosphorus, .vitaminC, .vitaminE, .thiamin, .riboflavin, .niacin, .vitaminB6,
             .caffeine:
            "mg"
        case .vitaminA, .vitaminD, .vitaminK, .folate, .vitaminB12:
            "µg"
        }
    }

    var group: Group {
        switch self {
        case .calories: .energy
        case .protein, .carbohydrates, .totalFat: .macros
        case .saturatedFats, .monounsaturatedFats, .polyunsaturatedFats, .transFats,
             .cholesterol, .omega3:
            .fats
        case .dietaryFiber, .totalSugars, .addedSugars: .carbs
        case .sodium, .potassium, .calcium, .iron, .magnesium, .zinc, .phosphorus: .minerals
        case .vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .thiamin, .riboflavin,
             .niacin, .vitaminB6, .folate, .vitaminB12:
            .vitamins
        case .caffeine, .alcohol, .water: .other
        }
    }

    /// Adult reference daily intake (EU/FDA style), in `unit`. nil = no reference.
    var dailyReference: Double? {
        switch self {
        case .calories: 2000
        case .protein: 50
        case .carbohydrates: 260
        case .totalFat: 70
        case .saturatedFats: 20
        case .dietaryFiber: 30
        case .totalSugars: 90
        case .addedSugars: 50
        case .cholesterol: 300
        case .sodium: 2300
        case .potassium: 3500
        case .calcium: 1000
        case .iron: 14
        case .magnesium: 375
        case .zinc: 10
        case .phosphorus: 700
        case .vitaminA: 800
        case .vitaminC: 80
        case .vitaminD: 15
        case .vitaminE: 12
        case .vitaminK: 75
        case .thiamin: 1.1
        case .riboflavin: 1.4
        case .niacin: 16
        case .vitaminB6: 1.4
        case .folate: 400
        case .vitaminB12: 2.5
        case .caffeine: 400
        default: nil
        }
    }

    /// The four headline nutrients.
    static let macros: [NutrientKey] = [.protein, .carbohydrates, .totalFat]
}

/// A sparse bag of nutrient amounts. Missing key = unknown (not zero).
struct NutrientValues: Codable, Hashable, Sendable {
    private(set) var storage: [String: Double]

    init(_ values: [NutrientKey: Double] = [:]) {
        storage = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }

    subscript(_ key: NutrientKey) -> Double? {
        get { storage[key.rawValue] }
        set { storage[key.rawValue] = newValue }
    }

    /// Value or 0 when unknown.
    func value(_ key: NutrientKey) -> Double { storage[key.rawValue] ?? 0 }

    var calories: Double { value(.calories) }
    var protein: Double { value(.protein) }
    var carbs: Double { value(.carbohydrates) }
    var fat: Double { value(.totalFat) }

    var isEmpty: Bool { storage.isEmpty }
    var knownKeys: [NutrientKey] { NutrientKey.allCases.filter { storage[$0.rawValue] != nil } }

    /// Multiply every value by `factor` (e.g. grams / 100 to go from per-100g to a portion).
    func scaled(by factor: Double) -> NutrientValues {
        var copy = self
        copy.storage = storage.mapValues { $0 * factor }
        return copy
    }

    /// Per-100 g values -> amounts for `grams`.
    func forGrams(_ grams: Double) -> NutrientValues { scaled(by: grams / 100) }

    static func + (lhs: NutrientValues, rhs: NutrientValues) -> NutrientValues {
        var result = lhs
        result.storage.merge(rhs.storage, uniquingKeysWith: +)
        return result
    }

    static func += (lhs: inout NutrientValues, rhs: NutrientValues) { lhs = lhs + rhs }

    static func sum<S: Sequence>(_ values: S) -> NutrientValues where S.Element == NutrientValues {
        // In-place merge: avoids copying the accumulated dictionary at every step.
        var result = NutrientValues()
        for value in values {
            result.storage.merge(value.storage, uniquingKeysWith: +)
        }
        return result
    }

    // MARK: Data round-trip (used by SwiftData models)

    /// JSON encoding (sorted keys so identical values give identical bytes and share one
    /// decode-cache slot). The result is also seeded into the decode cache.
    var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let encoded = try? encoder.encode(storage) else { return Data() }
        NutrientValuesDecodeCache.shared.insert(storage, for: encoded)
        return encoded
    }

    /// Decodes JSON produced by `data`. Decoding is memoized by content: SwiftData models
    /// (JournalEntry.per100, .nutrients…) call this on every access, many times per render,
    /// and JSONDecoder is by far the most expensive part of that path.
    init(data: Data?) {
        guard let data, !data.isEmpty else {
            storage = [:]
            return
        }
        if let cached = NutrientValuesDecodeCache.shared.lookup(data) {
            storage = cached
            return
        }
        let decoded = (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
        NutrientValuesDecodeCache.shared.insert(decoded, for: data)
        storage = decoded
    }
}

/// Thread-safe memo of decoded nutrient JSON blobs, keyed by the raw bytes (so it can never
/// return stale values: a changed blob is a different key). Bounded; flushed when full.
final class NutrientValuesDecodeCache: @unchecked Sendable {
    static let shared = NutrientValuesDecodeCache()

    private let lock = NSLock()
    private var storage: [Data: [String: Double]] = [:]
    private let limit = 4096

    func lookup(_ data: Data) -> [String: Double]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[data]
    }

    func insert(_ values: [String: Double], for data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count >= limit { storage.removeAll(keepingCapacity: true) }
        storage[data] = values
    }
}
