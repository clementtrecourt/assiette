import Foundation

/// Weekly calorie target from the current expenditure estimate.
enum EngineCoach {
    enum Goal: Equatable, Sendable {
        /// Lose `ratePercent` % of body weight per week.
        case lose(ratePercent: Double)
        /// Stay around `goalWeightKg`; outside the tolerance band, move back at `correctionRatePercent` %/week.
        case maintain(goalWeightKg: Double, correctionRatePercent: Double)
        /// Gain `ratePercent` % of body weight per week. MacroFactor adds a varying extra surplus on top
        /// of this (+0 to +150 kcal in the calibration data) that is not modelled yet.
        case gain(ratePercent: Double)
    }

    /// Daily energy change (kcal) for a weekly rate in % of body weight.
    static func dailyDelta(ratePercent: Double, weightKg: Double, parameters: EngineParameters = .calibrated) -> Double {
        ratePercent / 100 * weightKg * parameters.coachingEnergyDensity / 7
    }

    /// Calorie target (kcal/day, rounded). The weekly rate applies to the **latest scale reading**,
    /// like MacroFactor; the maintenance band is checked against the trend weight.
    static func calorieTarget(expenditure: Double, latestScaleWeightKg: Double, trendWeightKg: Double,
                              goal: Goal, parameters: EngineParameters = .calibrated) -> Double
    {
        let target: Double
        switch goal {
        case let .lose(rate):
            target = expenditure - dailyDelta(ratePercent: rate, weightKg: latestScaleWeightKg, parameters: parameters)
        case let .gain(rate):
            target = expenditure + dailyDelta(ratePercent: rate, weightKg: latestScaleWeightKg, parameters: parameters)
        case let .maintain(goalWeight, correction):
            let gap = trendWeightKg - goalWeight
            let delta = dailyDelta(ratePercent: correction, weightKg: latestScaleWeightKg, parameters: parameters)
            if gap > parameters.maintenanceToleranceKg {
                target = expenditure - delta
            } else if gap < -parameters.maintenanceToleranceKg {
                target = expenditure + delta
            } else {
                target = expenditure
            }
        }
        return max(parameters.minimumCalories, target).rounded()
    }
}
