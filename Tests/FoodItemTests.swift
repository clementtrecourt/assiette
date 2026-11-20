import XCTest
@testable import Assiette

final class FoodItemTests: XCTestCase {
    private func makeFood(name: String, brand: String?, kind: FoodKind = .grocery,
                          servingUnit: String? = "slice", servingQuantity: Double? = 1,
                          servingGrams: Double? = 45) -> Food {
        Food(id: 42, extId: "fd_test", name: name, brand: brand, kind: kind, ean: "0012345678905",
             servingUnit: servingUnit, servingQuantity: servingQuantity, servingGrams: servingGrams,
             isLiquid: false, packageGrams: 680,
             per100: NutrientValues([.calories: 250, .protein: 12]))
    }

    func testDisplayNameStripsBrandSuffix() {
        let food = makeFood(name: "Organic Bread by Acme", brand: "Acme")
        XCTAssertEqual(food.displayName, "Organic Bread")
    }

    func testDisplayNameKeepsNameWithoutSuffix() {
        XCTAssertEqual(makeFood(name: "Banana", brand: nil, kind: .everyday).displayName, "Banana")
        XCTAssertEqual(makeFood(name: "Acme Bread", brand: "Acme").displayName, "Acme Bread")
    }

    func testFoodToItem() {
        let item = makeFood(name: "Organic Bread by Acme", brand: "Acme").item
        XCTAssertEqual(item.source, .openNutrition)
        XCTAssertEqual(item.ref, "42")
        XCTAssertEqual(item.id, "openNutrition:42")
        XCTAssertEqual(item.name, "Organic Bread")
        XCTAssertEqual(item.brand, "Acme")
        XCTAssertEqual(item.kind, .grocery)
        XCTAssertEqual(item.servingLabel, "1 slice")
        XCTAssertEqual(item.servingGrams, 45)
        XCTAssertEqual(item.packageGrams, 680)
        XCTAssertEqual(item.ean, "0012345678905")
        XCTAssertEqual(item.per100.calories, 250, accuracy: 1e-9)
        XCTAssertEqual(item.defaultGrams, 45, accuracy: 1e-9)
        XCTAssertEqual(item.unitSymbol, "g")
    }

    func testItemWithoutServing() {
        let item = makeFood(name: "Banana", brand: nil, kind: .everyday,
                            servingUnit: nil, servingQuantity: nil, servingGrams: nil).item
        XCTAssertNil(item.servingLabel)
        XCTAssertEqual(item.defaultGrams, 100, accuracy: 1e-9)
    }

    func testItemIdFallsBackOnName() {
        let item = FoodItem(source: .quickAdd, ref: nil, name: "Ajout rapide",
                            per100: NutrientValues([.calories: 300]))
        XCTAssertEqual(item.id, "quickAdd:Ajout rapide")
        XCTAssertFalse(item.isLiquid)
        let liquid = FoodItem(source: .custom, ref: "abc", name: "Jus", isLiquid: true,
                              per100: NutrientValues())
        XCTAssertEqual(liquid.id, "custom:abc")
        XCTAssertEqual(liquid.unitSymbol, "ml")
    }

    func testServingLabel() {
        XCTAssertNil(FoodItem.servingLabel(unit: nil, quantity: 2))
        XCTAssertNil(FoodItem.servingLabel(unit: "", quantity: 2))
        XCTAssertEqual(FoodItem.servingLabel(unit: "cup", quantity: nil), "1 cup")
        XCTAssertEqual(FoodItem.servingLabel(unit: "cup", quantity: 1.5), "1,5 cup")
        XCTAssertEqual(FoodItem.servingLabel(unit: "oz", quantity: 2), "2 oz")
    }

    func testFoodKindRawValuesMatchDatabase() {
        XCTAssertEqual(FoodKind.everyday.rawValue, 0)
        XCTAssertEqual(FoodKind.prepared.rawValue, 1)
        XCTAssertEqual(FoodKind.restaurant.rawValue, 2)
        XCTAssertEqual(FoodKind.grocery.rawValue, 3)
    }

    // MARK: Formatters & dates

    func testFormattersUseFrenchDecimalSeparator() {
        XCTAssertEqual(Formatters.number(1.5), "1,5")
        XCTAssertEqual(Formatters.number(2), "2")
        XCTAssertEqual(Formatters.number(1.26, maxFractionDigits: 1), "1,3")
        XCTAssertEqual(Formatters.percent(0.234), "23 %")
        XCTAssertTrue(Formatters.kcal(512.4).hasSuffix(" kcal"))
        XCTAssertTrue(Formatters.kcal(512.4).hasPrefix("512"))
        XCTAssertEqual(Formatters.amount(12.34, of: .protein), "12,3 g")
        XCTAssertEqual(Formatters.amount(450, of: .sodium), "450 mg")
    }

    func testDateHelpers() throws {
        let cal = Calendar.current
        let date = try XCTUnwrap(cal.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 15, minute: 42)))
        let start = date.startOfDay
        XCTAssertEqual(start, cal.startOfDay(for: date))
        XCTAssertEqual(cal.component(.hour, from: start), 0)
        let next = start.adding(days: 1)
        XCTAssertEqual(cal.component(.day, from: next), 11)
        XCTAssertEqual(next.adding(days: -1), start)
    }

    func testMealSuggestion() throws {
        let cal = Calendar.current
        func at(_ hour: Int) throws -> Date {
            try XCTUnwrap(cal.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: hour)))
        }
        XCTAssertEqual(Meal.suggested(for: try at(8)), .breakfast)
        XCTAssertEqual(Meal.suggested(for: try at(12)), .lunch)
        XCTAssertEqual(Meal.suggested(for: try at(16)), .snack)
        XCTAssertEqual(Meal.suggested(for: try at(20)), .dinner)
        XCTAssertEqual(Meal.suggested(for: try at(2)), .dinner)
        XCTAssertEqual(Meal.allCases.map(\.order), [0, 1, 2, 3])
    }

    func testLogContextAndAppState() {
        let state = AppState()
        XCTAssertEqual(state.selectedTab, .progress) // the app opens on Accueil
        XCTAssertEqual(state.selectedDay, state.selectedDay.startOfDay)
        XCTAssertTrue(Calendar.current.isDate(state.selectedDay, inSameDayAs: .now)
            || Calendar.current.isDate(state.selectedDay, inSameDayAs: Date.now.adding(days: -1)))
        XCTAssertEqual(state.addTabContext.day, state.selectedDay)
        let context = LogContext.now
        XCTAssertEqual(context.day, context.day.startOfDay)
        XCTAssertEqual(LogContext(day: context.day, meal: .dinner).meal, .dinner)
    }
}
