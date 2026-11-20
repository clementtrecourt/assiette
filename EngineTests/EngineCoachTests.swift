import XCTest
@testable import AssietteEngine

final class EngineCoachTests: XCTestCase {
    func testLoseUsesScaleWeightAnd7700() {
        // 1 % of 80 kg per week = 0.8 kg × 7700 / 7 = 880 kcal/day.
        let target = EngineCoach.calorieTarget(expenditure: 2600, latestScaleWeightKg: 80, trendWeightKg: 81,
                                               goal: .lose(ratePercent: 1))
        XCTAssertEqual(target, 1720)
    }

    func testGainAddsSurplus() {
        let target = EngineCoach.calorieTarget(expenditure: 2600, latestScaleWeightKg: 70, trendWeightKg: 70,
                                               goal: .gain(ratePercent: 0.25))
        XCTAssertEqual(target, (2600 + 0.0025 * 70 * 1100).rounded())
    }

    func testMaintainInsideBandEqualsExpenditure() {
        let target = EngineCoach.calorieTarget(expenditure: 2400.4, latestScaleWeightKg: 70.6, trendWeightKg: 70.5,
                                               goal: .maintain(goalWeightKg: 70, correctionRatePercent: 0.15))
        XCTAssertEqual(target, 2400)
    }

    func testMaintainCorrectsTowardGoal() {
        let above = EngineCoach.calorieTarget(expenditure: 2500, latestScaleWeightKg: 75, trendWeightKg: 74,
                                              goal: .maintain(goalWeightKg: 70, correctionRatePercent: 0.2))
        XCTAssertEqual(above, (2500 - 0.002 * 75 * 1100).rounded())
        let below = EngineCoach.calorieTarget(expenditure: 2500, latestScaleWeightKg: 65, trendWeightKg: 66,
                                              goal: .maintain(goalWeightKg: 70, correctionRatePercent: 0.2))
        XCTAssertEqual(below, (2500 + 0.002 * 65 * 1100).rounded())
    }

    func testFloor() {
        let target = EngineCoach.calorieTarget(expenditure: 1600, latestScaleWeightKg: 60, trendWeightKg: 60,
                                               goal: .lose(ratePercent: 1.5))
        XCTAssertEqual(target, EngineParameters.calibrated.minimumCalories)
    }
}
