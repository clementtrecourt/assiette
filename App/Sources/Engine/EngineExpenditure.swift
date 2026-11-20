import Foundation

/// Adaptive estimate of total daily energy expenditure from logged intake and trend weight.
///
/// Each day, an energy-balance estimate is taken over the last `expenditureWindowDays` days:
/// mean intake of the usable days − (real-time trend change × energy density) / window. The
/// published expenditure then moves only a small fraction of the way toward it, which keeps it
/// stable (a few kcal per day) while still following real changes within a few weeks.
/// Unlogged and partial days are ignored, never counted as zero.
enum EngineExpenditure {
    /// Energy-balance expenditure for the window ending at `index`, or nil when it can't be measured.
    static func energyBalance(at index: Int, days: [EngineDay], realtimeTrend: [Double?],
                              parameters: EngineParameters = .calibrated) -> Double?
    {
        let window = parameters.expenditureWindowDays
        let start = index - window
        guard window > 0, start >= 0, index < days.count,
              let trendNow = realtimeTrend[index], let trendBefore = realtimeTrend[start]
        else { return nil }
        // The trend reference day (start) must also be clear of exception days.
        guard !(start...index).contains(where: { days[$0].isExcluded }) else { return nil }
        let intakes = ((start + 1)...index).compactMap { days[$0].usableIntake }
        guard !intakes.isEmpty else { return nil }
        let meanIntake = intakes.reduce(0, +) / Double(intakes.count)
        return meanIntake - (trendNow - trendBefore) * parameters.expenditureEnergyDensity / Double(window)
    }

    /// Expenditure for every day. `initial` (e.g. a Mifflin-St Jeor × activity estimate, or a value
    /// the user enters) is the estimate on the day before `days[startIndex]`; days before
    /// `startIndex` keep it, earlier history still feeds the energy-balance windows.
    static func estimate(days: [EngineDay], realtimeTrend: [Double?], initial: Double, startIndex: Int = 0,
                         parameters: EngineParameters = .calibrated) -> [Double]
    {
        var expenditure = initial
        return days.indices.map { index in
            if index >= startIndex, let balance = energyBalance(at: index, days: days, realtimeTrend: realtimeTrend, parameters: parameters) {
                expenditure += parameters.expenditureAdaptationRate * (balance - expenditure)
            }
            return expenditure
        }
    }
}
