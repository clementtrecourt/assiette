import SwiftData
import XCTest
@testable import Assiette

/// SwiftData tests run on the main actor (mainContext is main-actor isolated).
final class ModelsTests: XCTestCase {
    /// Fresh in-memory store per test. Keep the container alive for the whole test.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(AppSchema.models),
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private let bread = FoodItem(source: .openNutrition, ref: "42", name: "Bread", brand: "Acme",
                                 kind: .grocery, servingLabel: "1 slice", servingGrams: 40,
                                 packageGrams: 680, isLiquid: false, ean: "0012345678905",
                                 per100: NutrientValues([.calories: 250, .protein: 10, .carbohydrates: 45]))

    @MainActor
    func testJournalEntrySnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let noon = try XCTUnwrap(Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now))
        let entry = JournalEntry(item: bread, grams: 80, day: noon, meal: .lunch)
        context.insert(entry)
        try context.save()

        XCTAssertEqual(entry.day, noon.startOfDay, "day is normalized to start of day")
        XCTAssertEqual(entry.meal, .lunch)
        XCTAssertEqual(entry.mealRaw, "lunch")
        XCTAssertEqual(entry.source, .openNutrition)
        XCTAssertEqual(entry.per100, bread.per100)
        XCTAssertEqual(entry.nutrients.calories, 200, accuracy: 1e-9)
        XCTAssertEqual(entry.nutrients.protein, 8, accuracy: 1e-9)

        let item = entry.item
        XCTAssertEqual(item.id, bread.id)
        XCTAssertEqual(item.name, "Bread")
        XCTAssertEqual(item.brand, "Acme")
        XCTAssertEqual(item.kind, .grocery)
        XCTAssertEqual(item.servingGrams, 40)
        XCTAssertEqual(item.per100, bread.per100)

        entry.meal = .dinner
        XCTAssertEqual(entry.mealRaw, "dinner")
    }

    @MainActor
    func testQuantityDescription() throws {
        // Models are created without being inserted; keep a container for the schema alive.
        let container = try makeContainer()
        defer { _ = container }
        XCTAssertTrue(JournalEntry(item: bread, grams: 80, day: .now, meal: .lunch)
            .quantityDescription.contains("2 × 1 slice"))
        XCTAssertEqual(JournalEntry(item: bread, grams: 73, day: .now, meal: .lunch).quantityDescription, "73 g")

        let quick = FoodItem(source: .quickAdd, ref: nil, name: "Ajout rapide",
                             per100: NutrientValues([.calories: 350]))
        let quickEntry = JournalEntry(item: quick, grams: 100, day: .now, meal: .snack)
        XCTAssertEqual(quickEntry.quantityDescription, "Ajout rapide")
        XCTAssertEqual(quickEntry.nutrients.calories, 350, accuracy: 1e-9)

        let juice = FoodItem(source: .custom, ref: "j", name: "Jus", isLiquid: true,
                             per100: NutrientValues([.calories: 45]))
        XCTAssertEqual(JournalEntry(item: juice, grams: 250, day: .now, meal: .breakfast).quantityDescription, "250 ml")
    }

    @MainActor
    func testFetchEntriesByDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let today = Date.now.startOfDay
        let yesterday = today.adding(days: -1)
        context.insert(JournalEntry(item: bread, grams: 40, day: today, meal: .breakfast))
        context.insert(JournalEntry(item: bread, grams: 80, day: today, meal: .dinner))
        context.insert(JournalEntry(item: bread, grams: 100, day: yesterday, meal: .lunch))
        try context.save()

        let day = today
        let descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate<JournalEntry> { $0.day == day })
        let entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 2)
        let total = NutrientValues.sum(entries.map(\.nutrients))
        XCTAssertEqual(total.calories, 300, accuracy: 1e-9)
    }

    @MainActor
    func testUserProfileCurrentIsSingleton() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = UserProfile.current(in: context)
        let second = UserProfile.current(in: context)
        XCTAssertTrue(first === second)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserProfile>()), 1)
        XCTAssertFalse(first.hasCompletedOnboarding)
    }

    @MainActor
    func testUserProfileEnumsAndTargets() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = UserProfile.current(in: context)
        profile.sex = .female
        profile.activity = .veryActive
        profile.goal = .gain
        XCTAssertEqual(profile.sexRaw, "female")
        XCTAssertEqual(profile.activityRaw, "veryActive")
        XCTAssertEqual(profile.goalRaw, "gain")

        profile.sexRaw = "garbage"
        XCTAssertEqual(profile.sex, .male)

        profile.birthYear = Calendar.current.component(.year, from: .now) - 40
        XCTAssertEqual(profile.age, 40)

        profile.calorieTarget = 1900
        profile.proteinTarget = 110
        let targets = profile.targets
        XCTAssertEqual(targets.calories, 1900, accuracy: 1e-9)
        XCTAssertEqual(targets.protein, 110, accuracy: 1e-9)
        XCTAssertNotNil(targets[.dietaryFiber])
    }

    @MainActor
    func testWaterAndWeightEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let evening = try XCTUnwrap(Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now))
        let water = WaterEntry(day: evening, ml: 500)
        XCTAssertEqual(water.day, evening.startOfDay)
        context.insert(water)
        context.insert(WaterEntry(day: .now, ml: 250))
        context.insert(WeightEntry(date: .now, kg: 72.5))
        try context.save()

        let waters = try context.fetch(FetchDescriptor<WaterEntry>())
        XCTAssertEqual(waters.reduce(0) { $0 + $1.ml }, 750, accuracy: 1e-9)
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        XCTAssertEqual(weights.first?.kg, 72.5)
    }

    @MainActor
    func testCustomFoodAndRecipe() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = CustomFood(name: "Granola maison", brand: nil,
                              per100: NutrientValues([.calories: 450, .protein: 12]))
        food.servingGrams = 50
        food.servingLabel = "1 bol"
        food.ean = "1234567890128"
        context.insert(food)
        try context.save()

        XCTAssertFalse(food.isRecipe)
        XCTAssertEqual(food.ingredients, [])
        let item = food.item
        XCTAssertEqual(item.source, .custom)
        XCTAssertEqual(item.ref, food.id.uuidString)
        XCTAssertEqual(item.id, "custom:\(food.id.uuidString)")
        XCTAssertEqual(item.ean, "1234567890128")
        XCTAssertEqual(item.servingGrams, 50)
        XCTAssertEqual(item.per100.calories, 450, accuracy: 1e-9)

        let recipe = CustomFood(name: "Salade")
        let ingredients = [
            RecipeIngredient(name: "Tomate", grams: 200, per100: NutrientValues([.calories: 18])),
            RecipeIngredient(name: "Huile", grams: 10, per100: NutrientValues([.calories: 900])),
        ]
        recipe.ingredients = ingredients
        context.insert(recipe)
        try context.save()
        XCTAssertTrue(recipe.isRecipe)
        XCTAssertEqual(recipe.ingredients, ingredients)

        let ean: String? = "1234567890128"
        let byEan = try context.fetch(FetchDescriptor<CustomFood>(predicate: #Predicate<CustomFood> { $0.ean == ean }))
        XCTAssertEqual(byEan.count, 1)
        XCTAssertEqual(byEan.first?.name, "Granola maison")
    }

    @MainActor
    func testFavoriteFoodSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let favorite = FavoriteFood(item: bread)
        context.insert(favorite)
        try context.save()

        XCTAssertEqual(favorite.key, bread.id)
        let item = favorite.item
        XCTAssertEqual(item.id, bread.id)
        XCTAssertEqual(item.name, bread.name)
        XCTAssertEqual(item.kind, .grocery)
        XCTAssertEqual(item.per100, bread.per100)

        let key = bread.id
        let found = try context.fetch(FetchDescriptor<FavoriteFood>(predicate: #Predicate<FavoriteFood> { $0.key == key }))
        XCTAssertEqual(found.count, 1)
        context.delete(favorite)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FavoriteFood>()), 0)
    }
}
