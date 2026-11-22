import Foundation

/// Tunable constants of the adaptive engine (trend weight, expenditure, coaching).
///
/// Defaults come from replaying a real 181-day MacroFactor export (2026-05 → 2026-11) with
/// `tools/mf/` and keeping the values that best reproduce its published numbers:
/// trend weight ≈ 0.06 kg RMSE, expenditure ≈ 30 kcal RMSE (with the owner's surgery period marked as an
/// exception), loss targets within ±1 kcal.
struct EngineParameters: Equatable, Sendable {
    // MARK: Weight trend (local linear trend Kalman model, one observation per day)

    /// Day-to-day variance of the true weight level (kg²).
    var trendLevelNoise: Double = 1e-3
    /// Day-to-day variance of the weight slope (kg²/day²). Small = slow-turning trend.
    var trendSlopeNoise: Double = 1e-5
    /// Variance of one scale reading around the true level (kg²): water, food, scale noise.
    var scaleNoise: Double = 0.3

    // MARK: Expenditure

    /// Days of intake and trend change used for each daily energy-balance estimate.
    var expenditureWindowDays: Int = 7
    /// Energy content of one kg of trend-weight change (kcal/kg), used by the expenditure estimate.
    /// Loosely determined by the calibration (4400–6700 fit equally well); 5000 is the best fit.
    var expenditureEnergyDensity: Double = 5000
    /// Fraction of the gap to the latest energy-balance estimate closed each day.
    /// 0.02 with trimming (0.017 was the best fit without it).
    var expenditureAdaptationRate: Double = 0.02
    /// Intake days dropped at each end (lowest and highest) before averaging the window, so one
    /// party or fasting day doesn't move the estimate. MacroFactor barely reacts to such days;
    /// trimming one each side cuts the bias against it from +25 to +3 kcal on the calibration data.
    var expenditureTrimmedDays: Int = 1
    /// Trimming only applies when the window holds at least this many usable intake days.
    var expenditureTrimMinimumDays: Int = 5
    /// MacroFactor "holding": the estimate only updates when the window holds at least this many
    /// logged days…
    var expenditureMinimumIntakeDays: Int = 3
    /// …and at least this many weigh-ins; otherwise it holds its last value.
    var expenditureMinimumWeighIns: Int = 1

    // MARK: Coaching

    /// Energy content of one kg of body weight used to turn a weekly rate into calories (kcal/kg).
    /// MacroFactor's loss targets match 7700 exactly.
    var coachingEnergyDensity: Double = 7700
    /// Lowest calorie target the coach ever proposes.
    var minimumCalories: Double = 1200
    /// Maintenance: distance between trend weight and goal weight tolerated before the coach
    /// starts correcting (kg). Not calibrated yet (0.4 kg off → no correction, 2.5 kg → correction).
    var maintenanceToleranceKg: Double = 1.0

    static let calibrated = EngineParameters()
}
