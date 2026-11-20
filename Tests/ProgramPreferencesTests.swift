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
