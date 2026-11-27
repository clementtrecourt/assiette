import XCTest
@testable import Assiette

final class ProgramPreferencesTests: XCTestCase {
    func testDefaultsMatchGoalCalculator() {
        let prefs = ProgramPreferences()
        for goal in [WeightGoal.lose, .maintain, .gain] {
            for (calories, weight) in [(2000.0, 80.0), (1200, 120), (3000, 70)] {
                let a = prefs.macros(calories: calories, weightKg: weight, goal: goal)
                let b = GoalCalculator.macroTargets(calories: calories, weightKg: weight, goal: goal)
                XCTAssertEqual(a.protein, b.protein, accuracy: 1e-9)
                XCTAssertEqual(a.fat, b.fat, accuracy: 1e-9)
                XCTAssertEqual(a.carbs, b.carbs, accuracy: 1e-9)
            }
        }
    }

    func testKetoCapsCarbsAndKeepsEnergy() {
        var prefs = ProgramPreferences()
        prefs.diet = .keto
        let m = prefs.macros(calories: 2000, weightKg: 80, goal: .lose)
        XCTAssertEqual(m.carbs, ProgramDiet.ketoCarbCap, accuracy: 1e-9)
        XCTAssertEqual(m.protein * 4 + m.carbs * 4 + m.fat * 9, 2000, accuracy: 1e-6)
    }

    func testLowFatAndProteinLevels() {
        var prefs = ProgramPreferences()
        prefs.diet = .lowFat
        prefs.protein = .high
        let m = prefs.macros(calories: 2000, weightKg: 70, goal: .lose)
        XCTAssertEqual(m.protein, 2.4 * 70, accuracy: 1e-9)
        XCTAssertEqual(m.fat, 2000 * 0.20 / 9, accuracy: 1e-9)
    }

    func testEvenWeekIsFlat() {
        XCTAssertEqual(ProgramPreferences().weekCalories(average: 1900), Array(repeating: 1900, count: 7))
    }

    func testShiftKeepsWeeklyTotal() {
        var prefs = ProgramPreferences()
        prefs.distribution = .shift
        prefs.highDays = [5, 6]
        prefs.shiftPercent = 20
        let week = prefs.weekCalories(average: 2000)
        XCTAssertEqual(week[5], 2400)
        XCTAssertEqual(week[0], 1840)
        XCTAssertEqual(week.reduce(0, +), 14000, accuracy: 3) // rounding
    }

    @MainActor
    func testSettingAndClearingOneISOWeekdayDoesNotChangeOtherDays() async throws {
        let key = WeekdayCalorieTargets.storageKey
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        defaults.removeObject(forKey: key)

        XCTAssertTrue(WeekdayCalorieTargets.set(800, forISOWeekday: 1))
        XCTAssertTrue(WeekdayCalorieTargets.set(10000, forISOWeekday: 7))
        XCTAssertFalse(WeekdayCalorieTargets.set(799, forISOWeekday: 1))
        XCTAssertFalse(WeekdayCalorieTargets.set(10001, forISOWeekday: 7))
        XCTAssertFalse(WeekdayCalorieTargets.set(2000, forISOWeekday: 0))
        XCTAssertFalse(WeekdayCalorieTargets.set(nil, forISOWeekday: 8))
        let data = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: data), ["1": 800, "7": 10000])
        XCTAssertTrue(WeekdayCalorieTargets.set(nil, forISOWeekday: 1))
        XCTAssertEqual(WeekdayCalorieTargets.current.values, [7: 10000])
        XCTAssertTrue(WeekdayCalorieTargets.set(nil, forISOWeekday: 1))
        XCTAssertTrue(WeekdayCalorieTargets.set(nil, forISOWeekday: 7))
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testOverrideRecursAcrossWeeksAndOtherDaysKeepTheShift() throws {
        let overrides = WeekdayCalorieTargets(data: Data(#"{"1":2300,"7":1800,"0":2000,"4":25000}"#.utf8))
        XCTAssertEqual(overrides.values, [1: 2300, 7: 1800])
        let monday = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 23, hour: 12)))
        var prefs = ProgramPreferences()
        prefs.distribution = .shift
        let profile = UserProfile()
        profile.calorieTarget = 2000
        profile.carbsTarget = 200
        profile.proteinTarget = 120
        profile.fatTarget = 80
        // Mon → Sun → Mon across the March DST change in France; Sunday is also a high day.
        let expected = [2300.0, 1840, 1840, 1840, 1840, 2400, 1800, 2300]
        for (offset, kcal) in expected.enumerated() {
            let day = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: offset, to: monday))
            let targets = profile.targets(on: day, preferences: prefs, overrides: overrides)
            XCTAssertEqual(targets.calories, kcal)
            XCTAssertEqual(targets.carbs, 200 + (kcal - 2000) / 4)
            XCTAssertEqual(targets.protein, 120)
            XCTAssertEqual(targets.fat, 80)
            XCTAssertEqual(targets.value(.dietaryFiber), profile.fiberTarget)
        }
        profile.calorieTarget = 2200 // A later check-in changes the base, not Monday's fixed target.
        XCTAssertEqual(profile.targets(on: monday, preferences: prefs, overrides: overrides).calories, 2300)
        XCTAssertEqual(profile.calorieTarget, 2200)
    }

    func testHistoricalCheckInRetainsRecordedTargetsExceptOnOverriddenDays() throws {
        let saturday = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 28)))
        let sunday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: saturday))
        var prefs = ProgramPreferences()
        prefs.distribution = .shift
        let overrides = WeekdayCalorieTargets(data: Data(#"{"7":2100}"#.utf8))
        let change = CoachingCheckIn(date: saturday, kindRaw: "weekly")
        change.calorieTarget = 1900
        change.carbsTarget = 200
        let unmodified = change.targets(on: saturday, preferences: prefs, overrides: overrides)
        XCTAssertEqual(unmodified.calories, 1900) // No historical distribution was recorded.
        XCTAssertEqual(unmodified.carbs, 200)
        let modified = change.targets(on: sunday, preferences: prefs, overrides: overrides)
        XCTAssertEqual(modified.calories, 2100)
        XCTAssertEqual(modified.carbs, 250)
        XCTAssertEqual(change.calorieTarget, 1900)
    }

    func testCustomDayUsesTheProgramsMacroRule() {
        var prefs = ProgramPreferences()
        let overrides = WeekdayCalorieTargets(data: Data(#"{"2":2360}"#.utf8))
        prefs.diet = .keto
        let keto = prefs.dayTargets(weekday: 1, calories: 2000, protein: 120, carbs: 30, fat: 156, overrides: overrides)
        XCTAssertEqual(keto.carbs, 30)
        XCTAssertEqual(keto.protein, 120)
        XCTAssertEqual(keto.fat, 196)
        prefs.collaborativeSplit = .init(protein: 25, fat: 30)
        let split = prefs.dayTargets(weekday: 1, calories: 2000, protein: 125, carbs: 225, fat: 67, overrides: overrides)
        XCTAssertEqual(split.protein, 148)
        XCTAssertEqual(split.carbs, 266)
        XCTAssertEqual(split.fat, 79)
    }

    func testShiftRespectsFloor() {
        var prefs = ProgramPreferences()
        prefs.distribution = .shift
        prefs.highDays = [0, 1, 2, 3, 4, 5]
        prefs.shiftPercent = 30
        let week = prefs.weekCalories(average: 1300)
        XCTAssertGreaterThanOrEqual(week[6], 1200)
        XCTAssertEqual(week.reduce(0, +), 9100, accuracy: 7)
    }
}
