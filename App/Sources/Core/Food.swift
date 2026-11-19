import Foundation

/// Category of an OpenNutrition food (matches `food.type` in foods.sqlite).
enum FoodKind: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case everyday = 0
    case prepared = 1
    case restaurant = 2
    case grocery = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .everyday: "Aliment"
        case .prepared: "Plat préparé"
        case .restaurant: "Restaurant"
        case .grocery: "Produit de marque"
        }
    }

    var systemImage: String {
        switch self {
        case .everyday: "leaf"
        case .prepared: "frying.pan"
        case .restaurant: "fork.knife"
        case .grocery: "cart"
        }
    }
}

/// Where a loggable food comes from.
enum FoodSource: String, Codable, Hashable, Sendable {
    /// Bundled OpenNutrition database. `ref` = food.id (Int64 as string).
    case openNutrition
    /// User-created food or recipe (CustomFood). `ref` = CustomFood.id.uuidString.
    case custom
    /// Fetched online from Open Food Facts. `ref` = barcode.
    case openFoodFacts
    /// Quick add (calories/macros typed by hand). `ref` = nil.
    case quickAdd

    var label: String {
        switch self {
        case .openNutrition: "OpenNutrition"
        case .custom: "Mes aliments"
        case .openFoodFacts: "Open Food Facts"
        case .quickAdd: "Ajout rapide"
        }
    }
}

/// A row of the bundled OpenNutrition database.
struct Food: Identifiable, Hashable, Sendable {
    let id: Int64
    let extId: String
    let name: String
    let brand: String?
    let kind: FoodKind
    let ean: String?
    /// e.g. "slice", "cup", "oz" (English, from the dataset).
    let servingUnit: String?
    let servingQuantity: Double?
    /// Grams (or ml when `isLiquid`) of one dataset serving.
    let servingGrams: Double?
    let isLiquid: Bool
    let packageGrams: Double?
    /// Values per 100 g / 100 ml.
    let per100: NutrientValues
    /// OpenNutrition illustration basename (CDN: `<icon>@4x.webp`), exact or best generic
    /// match computed by tools/build_db.py. nil when unknown. Last so the memberwise init
    /// keeps working without it.
    var icon: String? = nil

    /// Name without the trailing " by Brand".
    var displayName: String {
        guard let brand, name.hasSuffix(" by \(brand)") else { return name }
        return String(name.dropLast(brand.count + 4))
    }

    var item: FoodItem {
        FoodItem(
            source: .openNutrition,
            ref: String(id),
            name: displayName,
            brand: brand,
            kind: kind,
            servingLabel: FoodItem.servingLabel(unit: servingUnit, quantity: servingQuantity),
            servingGrams: servingGrams,
            packageGrams: packageGrams,
            isLiquid: isLiquid,
            ean: ean,
            per100: per100,
            icon: icon
        )
    }
}

/// Unified, value-type description of anything that can be logged in the journal.
/// Built from a `Food`, a `CustomFood`, an Open Food Facts product or a past `JournalEntry`.
struct FoodItem: Identifiable, Hashable, Sendable {
    var source: FoodSource
    var ref: String?
    var name: String
    var brand: String?
    var kind: FoodKind?
    /// Human label of one serving, e.g. "1 slice", "1,5 cup". nil when unknown.
    var servingLabel: String?
    /// Grams of one serving; nil = only grams can be entered.
    var servingGrams: Double?
    var packageGrams: Double?
    var isLiquid: Bool = false
    var ean: String?
    var per100: NutrientValues
    /// OpenNutrition illustration basename (see `FoodIconView`). Must stay the LAST stored
    /// property (defaulted) so existing memberwise `FoodItem(...)` calls keep compiling.
    var icon: String? = nil

    /// Stable key, used for favorites and de-duplication: "source:ref" (or "source:name").
    var id: String { "\(source.rawValue):\(ref ?? name)" }

    /// "g" or "ml".
    var unitSymbol: String { isLiquid ? "ml" : "g" }

    /// Default quantity (grams) proposed when logging.
    var defaultGrams: Double { servingGrams ?? 100 }

    static func servingLabel(unit: String?, quantity: Double?) -> String? {
        guard let unit, !unit.isEmpty else { return nil }
        let q = quantity ?? 1
        return "\(Formatters.number(q, maxFractionDigits: 2)) \(unit)"
    }
}
