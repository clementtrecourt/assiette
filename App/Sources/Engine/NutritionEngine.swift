import Foundation

/// Runs the whole adaptive pipeline over a day-by-day history: trend weight, then expenditure.
/// Pure and deterministic, no SwiftUI/SwiftData: also built as the `AssietteEngine` Swift package
/// so it can be tested on Linux (`swift test`).
enum NutritionEngine {
    struct DayResult: Equatable, Sendable {
        var date: Date
        /// Trend weight known that day (kg), nil before the first weigh-in.
        var realtimeTrendKg: Double?
        /// Trend weight revised with later readings (kg), what charts show for past days.
        var smoothedTrendKg: Double?
        /// Expenditure estimate at the end of that day (kcal/day).
        var expenditure: Double
        /// The expenditure did not update that day: too little data in the window ("holding").
        var isHolding: Bool = false
        /// Raw 7-day energy-balance measurement the estimate moved toward that day (nil when holding).
        var energyBalance: Double?
    }

    /// - Parameters:
    ///   - days: contiguous history, one entry per calendar day (see `EngineDay.contiguous`).
    ///   - initialExpenditure: starting estimate, e.g. `GoalCalculator.tdee`.
    ///   - anchor: known expenditure on one day, the estimate restarts from it (see `EngineExpenditure.Anchor`).
    static func run(days: [EngineDay], initialExpenditure: Double, anchor: EngineExpenditure.Anchor? = nil,
                    parameters: EngineParameters = .calibrated) -> [DayResult]
    {
        let trend = EngineWeightTrend.compute(scaleWeights: days.map(\.scaleWeightKg), parameters: parameters)
        let realtime = trend.map { $0?.realtime }
        let expenditure = EngineExpenditure.estimate(days: days, realtimeTrend: realtime,
                                                     initial: initialExpenditure, anchor: anchor,
                                                     parameters: parameters)
        return days.indices.map { i in
            let balance = EngineExpenditure.energyBalance(at: i, days: days, realtimeTrend: realtime,
                                                          parameters: parameters)
            return DayResult(date: days[i].date, realtimeTrendKg: trend[i]?.realtime,
                             smoothedTrendKg: trend[i]?.smoothed, expenditure: expenditure[i],
                             isHolding: anchor?.index != i && balance == nil, energyBalance: balance)
        }
    }
}
