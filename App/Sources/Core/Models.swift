import Foundation
import SwiftData

// All persistent user data lives in SwiftData (local, on device).
// Registered in AssietteApp via `.modelContainer(for: AppSchema.models)`.

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        JournalEntry.self,
        UserProfile.self,
        WeightEntry.self,
        WaterEntry.self,
        CustomFood.self,
        FavoriteFood.self,
    ]
}

enum Meal: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case breakfast, lunch, snack, dinner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        case .lunch: "Déjeuner"
        case .snack: "Collation"
        case .dinner: "Dîner"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .snack: "carrot"
        case .dinner: "moon.stars"
        }
    }

    /// Display order in the journal.
    var order: Int { Meal.allCases.firstIndex(of: self) ?? 0 }

    /// Meal suggested for a given time of day.
    static func suggested(for date: Date = .now) -> Meal {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 15..<18: .snack
        default: .dinner
        }
    }
}

/// One logged food in the journal. Stores a full snapshot of the food (per 100 g values),
/// so the entry stays correct even if the source food changes or disappears.
@Model
final class JournalEntry {
    var id: UUID = UUID()
    /// Start of the day (Calendar.current.startOfDay) this entry belongs to.
    var day: Date = Date.now
    var mealRaw: String = Meal.breakfast.rawValue
    var createdAt: Date = Date.now

    var name: String = ""
    var brand: String?
    var sourceRaw: String = FoodSource.quickAdd.rawValue
    var ref: String?
    var kindRaw: Int?
    var servingLabel: String?
    var servingGrams: Double?
    var isLiquid: Bool = false

    /// Quantity eaten, in grams (ml for liquids). Quick adds use 100 with absolute per100 values.
    var grams: Double = 100
    var per100Data: Data = Data()

    init(item: FoodItem, grams: Double, day: Date, meal: Meal) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.mealRaw = meal.rawValue
        self.createdAt = .now
        self.name = item.name
        self.brand = item.brand
        self.sourceRaw = item.source.rawValue
        self.ref = item.ref
        self.kindRaw = item.kind?.rawValue
        self.servingLabel = item.servingLabel
        self.servingGrams = item.servingGrams
        self.isLiquid = item.isLiquid
        self.grams = grams
        self.per100Data = item.per100.data
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .quickAdd }

    var per100: NutrientValues {
        get { NutrientValues(data: per100Data) }
        set { per100Data = newValue.data }
    }

    /// Nutrients for the logged quantity.
    var nutrients: NutrientValues { per100.forGrams(grams) }

    /// Rebuild a loggable item (to log it again, or edit).
    var item: FoodItem {
        FoodItem(source: source, ref: ref, name: name, brand: brand,
                 kind: kindRaw.flatMap(FoodKind.init(rawValue:)),
                 servingLabel: servingLabel, servingGrams: servingGrams,
                 packageGrams: nil, isLiquid: isLiquid, ean: nil, per100: per100)
    }

    /// e.g. "150 g" or "2 × 1 slice (90 g)".
    var quantityDescription: String {
        let unit = isLiquid ? "ml" : "g"
        let g = Formatters.number(grams, maxFractionDigits: 0)
        if source == .quickAdd { return "Ajout rapide" }
        if let servingGrams, servingGrams > 0, let servingLabel {
            let n = grams / servingGrams
            if abs(n - n.rounded()) < 0.01 || abs(n * 4 - (n * 4).rounded()) < 0.01 {
                return "\(Formatters.number(n, maxFractionDigits: 2)) × \(servingLabel) (\(g) \(unit))"
            }
        }
        return "\(g) \(unit)"
    }
}

enum Sex: String, CaseIterable, Codable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Homme" : "Femme" }
}

enum ActivityLevel: String, CaseIterable, Codable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedentary: "Sédentaire"
        case .light: "Légèrement actif"
        case .moderate: "Modérément actif"
        case .active: "Actif"
        case .veryActive: "Très actif"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Travail de bureau, peu ou pas de sport"
        case .light: "Sport 1 à 3 fois par semaine"
        case .moderate: "Sport 3 à 5 fois par semaine"
        case .active: "Sport intense 6 à 7 fois par semaine"
        case .veryActive: "Travail physique + entraînement quotidien"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

enum WeightGoal: String, CaseIterable, Codable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lose: "Perdre du poids"
        case .maintain: "Maintenir"
        case .gain: "Prendre du poids / muscle"
        }
    }
}

/// Single-row user profile + daily targets. Use `UserProfile.current(in:)` to fetch or create.
@Model
final class UserProfile {
    var createdAt: Date = Date.now
    var hasCompletedOnboarding: Bool = false

    var sexRaw: String = Sex.male.rawValue
    var birthYear: Int = 1995
    var heightCm: Double = 175
    var weightKg: Double = 75
    var activityRaw: String = ActivityLevel.moderate.rawValue
    var goalRaw: String = WeightGoal.maintain.rawValue
    /// Desired weekly change in kg (positive number, direction given by goal).
    var weeklyRateKg: Double = 0.5
    var targetWeightKg: Double?

    /// Daily targets actually used by the app.
    var calorieTarget: Double = 2000
    var proteinTarget: Double = 120
    var carbsTarget: Double = 220
    var fatTarget: Double = 70
    var fiberTarget: Double = 30
    var waterTargetMl: Double = 2000
    /// When true, targets are typed by the user and not recomputed from the profile.
    var manualTargets: Bool = false

    init() {}

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var goal: WeightGoal {
        get { WeightGoal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }

    var age: Int { max(0, Calendar.current.component(.year, from: .now) - birthYear) }

    var targets: NutrientValues {
        NutrientValues([
            .calories: calorieTarget, .protein: proteinTarget,
            .carbohydrates: carbsTarget, .totalFat: fatTarget, .dietaryFiber: fiberTarget,
        ])
    }

    @MainActor
    static func current(in context: ModelContext) -> UserProfile {
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }
}

@Model
final class WeightEntry {
    var date: Date = Date.now
    var kg: Double = 0
    init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

@Model
final class WaterEntry {
    var day: Date = Date.now
    var createdAt: Date = Date.now
    var ml: Double = 250
    init(day: Date, ml: Double) {
        self.day = Calendar.current.startOfDay(for: day)
        self.createdAt = .now
        self.ml = ml
    }
}

/// A recipe ingredient, stored as JSON inside CustomFood.
struct RecipeIngredient: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var grams: Double
    var per100: NutrientValues
}

/// A food or recipe created by the user.
@Model
final class CustomFood {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var name: String = ""
    var brand: String?
    var ean: String?
    var isLiquid: Bool = false
    /// Serving label, e.g. "1 portion", "1 bol".
    var servingLabel: String?
    var servingGrams: Double?
    var per100Data: Data = Data()
    /// Non-nil for recipes: JSON-encoded [RecipeIngredient].
    var ingredientsData: Data?
    /// For recipes: total cooked weight in grams (defaults to sum of ingredients).
    var totalGrams: Double?

    init(name: String, brand: String? = nil, per100: NutrientValues = NutrientValues()) {
        self.id = UUID()
        self.createdAt = .now
        self.name = name
        self.brand = brand
        self.per100Data = per100.data
    }

    var per100: NutrientValues {
        get { NutrientValues(data: per100Data) }
        set { per100Data = newValue.data }
    }

    var isRecipe: Bool { ingredientsData != nil }

    var ingredients: [RecipeIngredient] {
        get {
            guard let ingredientsData else { return [] }
            return (try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)) ?? []
        }
        set { ingredientsData = try? JSONEncoder().encode(newValue) }
    }

    var item: FoodItem {
        FoodItem(source: .custom, ref: id.uuidString, name: name, brand: brand, kind: nil,
                 servingLabel: servingLabel, servingGrams: servingGrams, packageGrams: nil,
                 isLiquid: isLiquid, ean: ean, per100: per100)
    }
}

/// A food the user starred. Snapshot of the FoodItem so it can be logged without lookup.
@Model
final class FavoriteFood {
    /// FoodItem.id ("source:ref").
    var key: String = ""
    var createdAt: Date = Date.now
    var name: String = ""
    var brand: String?
    var sourceRaw: String = FoodSource.openNutrition.rawValue
    var ref: String?
    var kindRaw: Int?
    var servingLabel: String?
    var servingGrams: Double?
    var isLiquid: Bool = false
    var per100Data: Data = Data()

    init(item: FoodItem) {
        self.key = item.id
        self.createdAt = .now
        self.name = item.name
        self.brand = item.brand
        self.sourceRaw = item.source.rawValue
        self.ref = item.ref
        self.kindRaw = item.kind?.rawValue
        self.servingLabel = item.servingLabel
        self.servingGrams = item.servingGrams
        self.isLiquid = item.isLiquid
        self.per100Data = item.per100.data
    }

    var item: FoodItem {
        FoodItem(source: FoodSource(rawValue: sourceRaw) ?? .openNutrition, ref: ref, name: name,
                 brand: brand, kind: kindRaw.flatMap(FoodKind.init(rawValue:)),
                 servingLabel: servingLabel, servingGrams: servingGrams, packageGrams: nil,
                 isLiquid: isLiquid, ean: nil, per100: NutrientValues(data: per100Data))
    }
}
