import SwiftData
import XCTest
@testable import Assiette

final class GoalCalculatorTests: XCTestCase {
    func testBMRMifflinStJeor() {
        // 10 × 80 + 6.25 × 180 − 5 × 30 + 5
        XCTAssertEqual(GoalCalculator.bmr(sex: .male, weightKg: 80, heightCm: 180, age: 30), 1780, accuracy: 1e-9)
        // 10 × 60 + 6.25 × 165 − 5 × 25 − 161
        XCTAssertEqual(GoalCalculator.bmr(sex: .female, weightKg: 60, heightCm: 165, age: 25), 1345.25, accuracy: 1e-9)
    }

    func testBMRDecreasesWithAge() {
        let young = GoalCalculator.bmr(sex: .female, weightKg: 65, heightCm: 170, age: 25)
        let old = GoalCalculator.bmr(sex: .female, weightKg: 65, heightCm: 170, age: 55)
        XCTAssertEqual(young - old, 150, accuracy: 1e-9)
    }

    func testTDEE() {
        XCTAssertEqual(GoalCalculator.tdee(bmr: 1780, activity: .sedentary), 2136, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.tdee(bmr: 1780, activity: .moderate), 2759, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.tdee(bmr: 1000, activity: .veryActive), 1900, accuracy: 1e-9)
        var previous = 0.0
        for level in ActivityLevel.allCases {
            let value = GoalCalculator.tdee(bmr: 1500, activity: level)
            XCTAssertGreaterThan(value, previous, "\(level)")
            previous = value
        }
    }

    func testCalorieTarget() {
        // 0.5 kg/week × 7700 / 7 = 550 kcal/day
        XCTAssertEqual(GoalCalculator.calorieTarget(tdee: 2500, goal: .lose, weeklyRateKg: 0.5), 1950, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.calorieTarget(tdee: 2500, goal: .gain, weeklyRateKg: 0.25), 2775, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.calorieTarget(tdee: 2500, goal: .maintain, weeklyRateKg: 0.5), 2500, accuracy: 1e-9)
    }

    func testCalorieTargetFloor() {
        XCTAssertEqual(GoalCalculator.calorieTarget(tdee: 1500, goal: .lose, weeklyRateKg: 1.0), 1200, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(GoalCalculator.calorieTarget(tdee: 800, goal: .maintain, weeklyRateKg: 0), 1200)
    }

    func testMacroTargetsLose() {
        let m = GoalCalculator.macroTargets(calories: 2000, weightKg: 80, goal: .lose)
        XCTAssertEqual(m.protein, 160, accuracy: 1e-9)          // 2.0 g/kg
        XCTAssertEqual(m.fat, 2000 * 0.25 / 9, accuracy: 1e-9)  // 25 % of energy
        XCTAssertEqual(m.carbs, (2000 - 160 * 4 - 2000 * 0.25) / 4, accuracy: 1e-9)
        XCTAssertEqual(m.protein * 4 + m.carbs * 4 + m.fat * 9, 2000, accuracy: 1e-6)
    }

    func testMacroTargetsMaintainAndGain() {
        XCTAssertEqual(GoalCalculator.macroTargets(calories: 2500, weightKg: 70, goal: .maintain).protein, 126, accuracy: 1e-9)
        XCTAssertEqual(GoalCalculator.macroTargets(calories: 3000, weightKg: 70, goal: .gain).protein, 126, accuracy: 1e-9)
    }

    func testFatMinimumPerKg() {
        // 25 % of 1200 kcal = 33 g < 0.6 g/kg × 120 kg = 72 g
        let m = GoalCalculator.macroTargets(calories: 1200, weightKg: 120, goal: .maintain)
        XCTAssertEqual(m.fat, 72, accuracy: 1e-9)
    }

    func testCarbsNeverNegative() {
        let m = GoalCalculator.macroTargets(calories: 1200, weightKg: 150, goal: .lose)
        XCTAssertEqual(m.carbs, 0, accuracy: 1e-9)
    }

    @MainActor
    func testApplyRecomputesTargets() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let profile = UserProfile.current(in: context)
        profile.sex = .male
        profile.birthYear = Calendar.current.component(.year, from: .now) - 30
        profile.heightCm = 180
        profile.weightKg = 80
        profile.activity = .sedentary
        profile.goal = .maintain
        profile.manualTargets = false
        profile.fiberTarget = 33
        profile.waterTargetMl = 2400

        GoalCalculator.apply(to: profile)

        // BMR 1780 × 1.2 = 2136 kcal
        XCTAssertEqual(profile.calorieTarget, 2136, accuracy: 1)
        XCTAssertEqual(profile.proteinTarget, 144, accuracy: 1)
        XCTAssertEqual(profile.fatTarget, 2136 * 0.25 / 9, accuracy: 1)
        XCTAssertEqual(profile.carbsTarget, (2136 - 144 * 4 - 2136 * 0.25) / 4, accuracy: 1)
        // User preferences are left alone.
        XCTAssertEqual(profile.fiberTarget, 33, accuracy: 1e-9)
        XCTAssertEqual(profile.waterTargetMl, 2400, accuracy: 1e-9)
    }

    @MainActor
    func testApplyLoseGoal() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile.current(in: container.mainContext)
        profile.sex = .female
        profile.birthYear = Calendar.current.component(.year, from: .now) - 25
        profile.heightCm = 165
        profile.weightKg = 60
        profile.activity = .moderate
        profile.goal = .lose
        profile.weeklyRateKg = 0.5
        profile.manualTargets = false

        GoalCalculator.apply(to: profile)

        // 1345.25 × 1.55 − 550 = 1535.1
        XCTAssertEqual(profile.calorieTarget, 1345.25 * 1.55 - 550, accuracy: 1)
        XCTAssertEqual(profile.proteinTarget, 120, accuracy: 1)
    }

    @MainActor
    func testApplyKeepsManualTargets() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfile.current(in: container.mainContext)
        profile.manualTargets = true
        profile.calorieTarget = 1800
        profile.proteinTarget = 100
        profile.carbsTarget = 200
        profile.fatTarget = 60
        profile.weightKg = 120

        GoalCalculator.apply(to: profile)

        XCTAssertEqual(profile.calorieTarget, 1800, accuracy: 1e-9)
        XCTAssertEqual(profile.proteinTarget, 100, accuracy: 1e-9)
        XCTAssertEqual(profile.carbsTarget, 200, accuracy: 1e-9)
        XCTAssertEqual(profile.fatTarget, 60, accuracy: 1e-9)
    }
}
