import Foundation

/// Pure, unit-testable computation of daily energy and macro targets.
struct GoalCalculator {
    /// Energy content of 1 kg of body weight (kcal).
    static let kcalPerKg: Double = 7700
    /// Lowest calorie target ever proposed.
    static let minimumCalories: Double = 1200

    /// Full set of computed values (used by the onboarding summary and the profile screen).
    struct Targets: Equatable {
        var bmr: Double
        var tdee: Double
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    /// Basal metabolic rate, Mifflin-St Jeor equation (kcal / day).
    static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// Total daily energy expenditure (kcal / day).
    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    /// Daily calorie target: TDEE adjusted by the weekly rate (7700 kcal per kg), floored at 1200 kcal.
    static func calorieTarget(tdee: Double, goal: WeightGoal, weeklyRateKg: Double) -> Double {
        let dailyDelta = abs(weeklyRateKg) * kcalPerKg / 7
        let target: Double
        switch goal {
        case .lose: target = tdee - dailyDelta
        case .maintain: target = tdee
        case .gain: target = tdee + dailyDelta
        }
        return max(minimumCalories, target)
    }

    /// Protein by body weight (2.0 g/kg when losing, 1.8 g/kg otherwise), fat 25 % of energy
    /// (minimum 0.6 g/kg), carbs = remaining energy (never negative).
    static func macroTargets(calories: Double, weightKg: Double, goal: WeightGoal)
        -> (protein: Double, carbs: Double, fat: Double)
    {
        let proteinPerKg: Double
        switch goal {
        case .lose: proteinPerKg = 2.0
        case .maintain: proteinPerKg = 1.8
        case .gain: proteinPerKg = 1.8
        }
        let protein = proteinPerKg * weightKg
        let fat = max(calories * 0.25 / 9, 0.6 * weightKg)
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4)
        return (protein: protein, carbs: carbs, fat: fat)
    }

    /// All targets for the given parameters; calories and macros rounded to whole numbers.
    static func targets(sex: Sex, weightKg: Double, heightCm: Double, age: Int,
                        activity: ActivityLevel, goal: WeightGoal, weeklyRateKg: Double) -> Targets
    {
        let b = bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age)
        let t = tdee(bmr: b, activity: activity)
        let calories = calorieTarget(tdee: t, goal: goal, weeklyRateKg: weeklyRateKg).rounded()
        let macros = macroTargets(calories: calories, weightKg: weightKg, goal: goal)
        return Targets(bmr: b, tdee: t, calories: calories,
                       protein: macros.protein.rounded(), carbs: macros.carbs.rounded(),
                       fat: macros.fat.rounded())
    }

    /// Computed targets for a profile (ignores `manualTargets`).
    static func targets(for profile: UserProfile) -> Targets {
        targets(sex: profile.sex, weightKg: profile.weightKg, heightCm: profile.heightCm,
                age: profile.age, activity: profile.activity, goal: profile.goal,
                weeklyRateKg: profile.weeklyRateKg)
    }

    /// Recomputes calorie and macro targets of `profile` unless `manualTargets` is set.
    /// Fiber and water targets are left untouched (user preferences).
    /// Only for the very first targets (onboarding): afterwards the adaptive coach owns the targets
    /// (`CoachingService.refreshTargets` / weekly check-in), so do not call this on profile edits.
    static func apply(to profile: UserProfile) {
        guard !profile.manualTargets else { return }
        let t = targets(for: profile)
        profile.calorieTarget = t.calories
        profile.proteinTarget = t.protein
        profile.carbsTarget = t.carbs
        profile.fatTarget = t.fat
    }

    /// Suggested fiber target: 14 g per 1000 kcal, at least 25 g.
    static func fiberTarget(calories: Double) -> Double {
        max(25, (calories / 1000 * 14).rounded())
    }

    /// Suggested water target: 35 ml/kg rounded to 100 ml, between 1500 and 4000 ml.
    static func waterTarget(weightKg: Double) -> Double {
        min(4000, max(1500, (weightKg * 35 / 100).rounded() * 100))
    }
}
