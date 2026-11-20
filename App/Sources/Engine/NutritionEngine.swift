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
    }

    /// - Parameters:
    ///   - days: contiguous history, one entry per calendar day (see `EngineDay.contiguous`).
    ///   - initialExpenditure: starting estimate, e.g. `GoalCalculator.tdee`.
    static func run(days: [EngineDay], initialExpenditure: Double,
                    parameters: EngineParameters = .calibrated) -> [DayResult]
    {
        let trend = EngineWeightTrend.compute(scaleWeights: days.map(\.scaleWeightKg), parameters: parameters)
        let realtime = trend.map { $0?.realtime }
        let expenditure = EngineExpenditure.estimate(days: days, realtimeTrend: realtime,
                                                     initial: initialExpenditure, parameters: parameters)
        return days.indices.map { i in
            DayResult(date: days[i].date, realtimeTrendKg: trend[i]?.realtime,
                      smoothedTrendKg: trend[i]?.smoothed, expenditure: expenditure[i])
        }
    }
}
