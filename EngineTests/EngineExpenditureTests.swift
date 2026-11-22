import XCTest
@testable import AssietteEngine

final class EngineExpenditureTests: XCTestCase {
    private func run(_ days: [EngineDay], initial: Double) -> [Double] {
        NutritionEngine.run(days: days, initialExpenditure: initial).map(\.expenditure)
    }

    func testConvergesFromWrongInitialEstimate() {
        let days = EngineFixtures.synthetic(days: 200, trueExpenditure: 2500, intake: 2000)
        let estimate = run(days, initial: 2000)
        XCTAssertEqual(estimate.last!, 2500, accuracy: 60)
        XCTAssertEqual(run(days, initial: 3000).last!, 2500, accuracy: 60)
    }

    func testMovesSlowly() {
        let days = EngineFixtures.synthetic(days: 120, trueExpenditure: 2800, intake: 2300)
        let estimate = run(days, initial: 2200)
        for i in 1..<estimate.count {
            XCTAssertLessThan(abs(estimate[i] - estimate[i - 1]), 25, "day \(i)")
        }
    }

    func testUnloggedDaysAreIgnoredNotZero() {
        var days = EngineFixtures.synthetic(days: 200, trueExpenditure: 2500, intake: 2500)
        for i in stride(from: 0, to: days.count, by: 3) { days[i].intakeKcal = nil }
        for i in stride(from: 1, to: days.count, by: 7) { days[i].isPartial = true; days[i].intakeKcal = 400 }
        XCTAssertEqual(run(days, initial: 2500).last!, 2500, accuracy: 60)
    }

    func testAnchorResetsEstimateThenKeepsAdapting() {
        let days = EngineFixtures.synthetic(days: 120, trueExpenditure: 2500, intake: 2000)
        let anchored = NutritionEngine.run(days: days, initialExpenditure: 2000,
                                           anchor: .init(index: 60, kcal: 2300)).map(\.expenditure)
        let free = run(days, initial: 2000)
        XCTAssertEqual(Array(anchored[..<60]), Array(free[..<60]), "days before the anchor are unchanged")
        XCTAssertEqual(anchored[60], 2300)
        XCTAssertGreaterThan(anchored[61], 2300, "adapts toward the true value after the anchor")
        XCTAssertLessThan(abs(anchored[61] - 2300), 25, "moves slowly from the anchor")
    }

    func testFirstWindowWaitsForHistory() {
        let days = EngineFixtures.synthetic(days: 10, trueExpenditure: 2500, intake: 2000)
        let estimate = run(days, initial: 2100)
        let window = EngineParameters.calibrated.expenditureWindowDays
        for i in 0..<window { XCTAssertEqual(estimate[i], 2100) }
        XCTAssertNotEqual(estimate[window], 2100)
    }

    func testExceptionPeriodFreezesEstimate() {
        var days = EngineFixtures.synthetic(days: 120, trueExpenditure: 2500, intake: 2500)
        for i in 60..<80 { days[i].isExcluded = true; days[i].intakeKcal = 800 }
        let estimate = run(days, initial: 2500)
        let window = EngineParameters.calibrated.expenditureWindowDays
        for i in 60..<(80 + window) { XCTAssertEqual(estimate[i], estimate[59], "day \(i)") }
        XCTAssertNotEqual(estimate[80 + window], estimate[59])
    }

    func testHoldsWithTooLittleData() {
        var days = EngineFixtures.synthetic(days: 60, trueExpenditure: 2500, intake: 2000)
        // Days 30…39: only two logged days and no weigh-in → the estimate holds.
        for i in 30..<40 {
            days[i].scaleWeightKg = nil
            if i != 31 && i != 35 { days[i].intakeKcal = nil }
        }
        let results = NutritionEngine.run(days: days, initialExpenditure: 2100)
        XCTAssertTrue(results[39].isHolding)
        XCTAssertEqual(results[39].expenditure, results[38].expenditure)
        XCTAssertFalse(results[55].isHolding)
        XCTAssertTrue(results[0].isHolding, "no history yet")
    }

    func testStartIndexKeepsInitialBefore() {
        let days = EngineFixtures.synthetic(days: 40, trueExpenditure: 2500, intake: 2000)
        let trend = EngineWeightTrend.compute(scaleWeights: days.map(\.scaleWeightKg)).map { $0?.realtime }
        let estimate = EngineExpenditure.estimate(days: days, realtimeTrend: trend, initial: 2400, startIndex: 20)
        XCTAssertEqual(estimate[19], 2400)
        XCTAssertNotEqual(estimate[20], 2400)
    }

    func testContiguousFillsGapsAndSorts() {
        let days = EngineDay.contiguous([
            EngineDay(date: EngineFixtures.date(3), intakeKcal: 2000),
            EngineDay(date: EngineFixtures.date(0), scaleWeightKg: 70),
        ], calendar: EngineFixtures.calendar)
        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(days[0].scaleWeightKg, 70)
        XCTAssertNil(days[1].intakeKcal)
        XCTAssertEqual(days[3].intakeKcal, 2000)
        XCTAssertTrue(EngineDay.contiguous([]).isEmpty)
    }
}
