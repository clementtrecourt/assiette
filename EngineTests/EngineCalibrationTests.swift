import XCTest
@testable import AssietteEngine

/// Replays the owner's MacroFactor history (reference/, gitignored) and checks the engine stays
/// as close to MacroFactor as the calibration found. Skipped when the data is absent.
final class EngineCalibrationTests: XCTestCase {
    private func loadDays() throws -> (days: [EngineDay], rows: [[String: String]]) {
        guard let rows = EngineReference.table("daily.csv") else {
            throw XCTSkip("reference/daily.csv absent (run tools/mf/parse_export.py on a MacroFactor export)")
        }
        // The owner's surgery period (manual targets in MacroFactor, from the first to the last
        // "manual" check-in) is replayed as an exception period, like it is set up in the app.
        let manual = (EngineReference.table("checkins.csv") ?? []).filter { $0["goal"] == "manual" }.compactMap { $0["date"] }
        let exception = manual.min().flatMap { first in manual.max().map { first...$0 } }
        let days = rows.enumerated().map { i, row in
            EngineDay(date: EngineFixtures.date(i), intakeKcal: row.number("kcal"), scaleWeightKg: row.number("weight"),
                      isExcluded: row["date"].map { exception?.contains($0) ?? false } ?? false)
        }
        return (days, rows)
    }

    func testSmoothedTrendMatchesMacroFactor() throws {
        let (days, rows) = try loadDays()
        let points = EngineWeightTrend.compute(scaleWeights: days.map(\.scaleWeightKg))
        let pairs = zip(points, rows).compactMap { p, r in r.number("trend").map { (p!.smoothed, $0) } }
        let fit = engineRMSE(pairs)
        print("trend vs MacroFactor: RMSE \(fit.rmse) kg, max \(fit.max) kg over \(pairs.count) days")
        XCTAssertLessThan(fit.rmse, 0.08)
    }

    func testExpenditureMatchesMacroFactor() throws {
        let (days, rows) = try loadDays()
        guard let checkins = EngineReference.table("checkins.csv"), let first = checkins.first?["date"],
              let accountStart = rows.firstIndex(where: { $0["date"] == first }),
              let seed = rows[accountStart].number("expenditure")
        else { throw XCTSkip("reference/checkins.csv absent") }
        // Seed with MacroFactor's value on the first check-in day, then let the engine run alone.
        let trend = EngineWeightTrend.compute(scaleWeights: days.map(\.scaleWeightKg)).map { $0?.realtime }
        let estimate = EngineExpenditure.estimate(days: days, realtimeTrend: trend, initial: seed,
                                                  startIndex: accountStart + 1)
        let pairs = ((accountStart + 1)..<days.count).compactMap { i in rows[i].number("expenditure").map { (estimate[i], $0) } }
        let fit = engineRMSE(pairs)
        print("expenditure vs MacroFactor: RMSE \(fit.rmse) kcal, max \(fit.max) kcal over \(pairs.count) days")
        XCTAssertLessThan(fit.rmse, 32)
        XCTAssertLessThan(fit.max, 60)
        let bias = pairs.map { $0.0 - $0.1 }.reduce(0, +) / Double(pairs.count)
        print("expenditure bias vs MacroFactor: \(bias) kcal")
        XCTAssertLessThan(abs(bias), 10)
    }

    func testCheckInTargetsMatchMacroFactor() throws {
        guard let checkins = EngineReference.table("checkins.csv") else { throw XCTSkip("reference/checkins.csv absent") }
        var gainGaps: [Double] = []
        var checked = 0
        for (i, row) in checkins.enumerated() {
            guard let expenditure = row.number("expenditure"), let weight = row.number("scale_weight"),
                  let trend = row.number("trend"), let rate = row.number("rate_percent"),
                  let actual = row.number("target") else { continue }
            let goal: EngineCoach.Goal
            switch row["goal"] {
            case "lose": goal = .lose(ratePercent: rate)
            case "gain": goal = .gain(ratePercent: rate)
            case "maintain": goal = .maintain(goalWeightKg: row.number("goal_weight") ?? trend, correctionRatePercent: rate)
            default: continue
            }
            let predicted = EngineCoach.calorieTarget(expenditure: expenditure, latestScaleWeightKg: weight,
                                                      trendWeightKg: trend, goal: goal)
            if case .gain = goal { gainGaps.append(actual - predicted); continue }
            if i == 0 { continue } // account creation day: target set by the onboarding, not the coach
            XCTAssertEqual(predicted, actual, accuracy: 2, "check-in \(row["date"] ?? "?") (\(row["goal"] ?? ""))")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 5)
        if !gainGaps.isEmpty {
            print("gain check-ins: MacroFactor adds \(gainGaps.min()!)…\(gainGaps.max()!) kcal on top of the formula (not modelled yet)")
        }
    }
}
