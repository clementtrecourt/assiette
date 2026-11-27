import Foundation

// Program preferences set by the "Modifier le programme" wizard: diet (macro split), calorie
// floor, training, weekly calorie distribution and protein level. Stored in UserDefaults as JSON.
// The defaults reproduce the historical behavior exactly (GoalCalculator.macroTargets, 1200 kcal
// floor, same target every day), so nothing changes until the wizard is used.

enum ProgramDiet: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced, lowFat, lowCarb, keto
    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Équilibré"
        case .lowFat: "Pauvre en lipides"
        case .lowCarb: "Pauvre en glucides"
        case .keto: "Cétogène"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "Répartition standard des glucides et des lipides."
        case .lowFat: "Les lipides sont réduits au profit des glucides et des protéines."
        case .lowCarb: "Les glucides sont réduits au profit des lipides et des protéines."
        case .keto: "Glucides très limités pour permettre plus de lipides."
        }
    }

    var symbol: String {
        switch self {
        case .balanced: "scalemass.fill"
        case .lowFat: "drop.degreesign.slash"
        case .lowCarb: "leaf.fill"
        case .keto: "flame.fill"
        }
    }

    /// Share of the calories given to fat (keto: fat takes everything left after the carb cap).
    var fatShare: Double {
        switch self {
        case .balanced: 0.25
        case .lowFat: 0.20
        case .lowCarb: 0.40
        case .keto: 0.70
        }
    }

    /// Keto carb cap (g/day).
    static let ketoCarbCap: Double = 30
}

enum CalorieFloor: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, low
    var id: String { rawValue }

    var kcal: Double { self == .standard ? 1200 : 800 }

    var title: String { self == .standard ? "Plancher standard" : "Plancher bas" }

    var detail: String {
        self == .standard
            ? "Vos objectifs caloriques ne descendront jamais sous 1 200 kcal."
            : "Vos objectifs caloriques ne descendront jamais sous 800 kcal (avec prudence)."
    }

    var symbol: String { self == .standard ? "star.circle.fill" : "exclamationmark.circle.fill" }
}

enum ProgramTraining: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, lifting, cardio, both
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Aucune ou activité légère"
        case .lifting: "Musculation"
        case .cardio: "Cardio"
        case .both: "Cardio et musculation"
        }
    }

    var symbol: String {
        switch self {
        case .none: "figure.mind.and.body"
        case .lifting: "dumbbell.fill"
        case .cardio: "figure.run"
        case .both: "checkmark.circle.fill"
        }
    }

    /// Protein multiplier: resistance training keeps the full protein level.
    var proteinFactor: Double {
        switch self {
        case .none: 0.9
        case .cardio: 0.95
        case .lifting, .both: 1
        }
    }
}

enum ProteinLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, moderate, high, extraHigh
    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Faible"
        case .moderate: "Modéré"
        case .high: "Élevé"
        case .extraHigh: "Très élevé"
        }
    }

    var detail: String {
        switch self {
        case .low: "Dans le bas de la plage optimale."
        case .moderate: "Au milieu de la plage optimale."
        case .high: "Dans le haut de la plage optimale."
        case .extraHigh: "Apport maximal recommandé."
        }
    }

    var symbol: String {
        switch self {
        case .low: "circle.bottomhalf.filled"
        case .moderate: "circle.lefthalf.filled"
        case .high: "circle.fill"
        case .extraHigh: "plus.circle.fill"
        }
    }

    /// g/kg added to the base level (2.0 g/kg when losing, 1.8 g/kg otherwise).
    var offsetPerKg: Double {
        switch self {
        case .low: -0.4
        case .moderate: 0
        case .high: 0.4
        case .extraHigh: 0.8
        }
    }
}

enum CalorieDistribution: String, Codable, CaseIterable, Identifiable, Sendable {
    case even, shift
    var id: String { rawValue }

    var title: String { self == .even ? "Répartir uniformément" : "Décaler les calories" }

    var detail: String {
        self == .even
            ? "Le même objectif calorique tous les jours de la semaine."
            : "Plus de calories certains jours, un peu moins les autres. La moyenne de la semaine ne change pas."
    }

    var symbol: String { self == .even ? "equal" : "water.waves" }
}

/// Fixed recurring targets sit on top of either program distribution. Keys are ISO weekdays
/// (Monday = 1, Sunday = 7), independent of the device's first weekday setting.
struct WeekdayCalorieTargets: Equatable, Sendable {
    static let storageKey = "program.weekdayCalorieTargets"
    static let allowedCalories = 800...10000
    private(set) var values: [Int: Int] = [:]

    init(data: Data? = nil) {
        if let data, let decoded = try? JSONDecoder().decode([Int: Int].self, from: data) {
            values = decoded.filter { (1...7).contains($0.key) && Self.allowedCalories.contains($0.value) }
        }
    }

    static var current: Self { Self(data: UserDefaults.standard.data(forKey: storageKey)) }

    /// Set or clear just one day, leaving the program and other weekdays alone.
    @MainActor @discardableResult
    static func set(_ kcal: Int?, forISOWeekday day: Int) -> Bool {
        guard (1...7).contains(day), kcal.map(allowedCalories.contains) ?? true else { return false }
        var targets = current.values
        guard targets[day] != kcal else { return true }
        targets[day] = kcal
        if targets.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else {
            guard let data = try? JSONEncoder().encode(targets) else { return false }
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        return true
    }

    func calories(on day: Date) -> Double? {
        values[CoachingFormat.mondayIndex(of: day) + 1].map(Double.init)
    }
}

struct ProgramPreferences: Codable, Equatable, Sendable {
    struct MacroSplit: Codable, Equatable, Sendable {
        var protein: Double
        var fat: Double
        var carbs: Double { 100 - protein - fat }

        var isValid: Bool {
            protein >= 0 && fat >= 0 && carbs >= 0 && protein <= 100 && fat <= 100
        }
    }

    var collaborativeSplit: MacroSplit?
    var diet: ProgramDiet = .balanced
    var floor: CalorieFloor = .standard
    var training: ProgramTraining = .both
    var distribution: CalorieDistribution = .even
    /// High-calorie days when `distribution == .shift` (0 = Monday … 6 = Sunday).
    var highDays: Set<Int> = [5, 6]
    /// Extra calories on high days, in % of the average target.
    var shiftPercent: Double = 20
    var protein: ProteinLevel = .moderate

    static let storageKey = "program.preferences"
    static let shiftChoices: [Double] = [10, 20, 30]

    static var current: ProgramPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var decoded = try? JSONDecoder().decode(ProgramPreferences.self, from: data)
        else { return ProgramPreferences() }
        if !CoachingSettings.isCollaborative { decoded.collaborativeSplit = nil }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: Macros

    /// Average-day macros for a calorie target. With the default preferences this equals
    /// `GoalCalculator.macroTargets` (2.0 / 1.8 g/kg protein, 25 % fat, at least 0.6 g/kg fat).
    func macros(calories: Double, weightKg: Double, goal: WeightGoal)
        -> (protein: Double, carbs: Double, fat: Double)
    {
        if let split = collaborativeSplit, split.isValid {
            return (calories * split.protein / 400, calories * split.carbs / 400, calories * split.fat / 900)
        }
        let base = goal == .lose ? 2.0 : 1.8
        let perKg = max(1.2, base + protein.offsetPerKg) * training.proteinFactor
        let proteinG = perKg * weightKg
        let left = max(0, calories - proteinG * 4)
        if diet == .keto {
            let carbs = min(ProgramDiet.ketoCarbCap, left / 4)
            return (proteinG, carbs, max(0, (left - carbs * 4) / 9))
        }
        let minFat = diet == .lowFat ? 0.5 * weightKg : 0.6 * weightKg
        let fat = max(calories * diet.fatShare / 9, minFat)
        let carbs = max(0, (calories - proteinG * 4 - fat * 9) / 4)
        return (proteinG, carbs, fat)
    }

    // MARK: Weekly distribution

    /// Calories of each weekday (0 = Monday) for an average target. Same weekly total; low days
    /// never go under the calorie floor.
    func weekCalories(average: Double) -> [Double] {
        let k = highDays.count
        guard distribution == .shift, k > 0, k < 7 else { return Array(repeating: average, count: 7) }
        var high = average * (1 + shiftPercent / 100)
        var low = (7 * average - Double(k) * high) / Double(7 - k)
        if low < floor.kcal {
            low = min(floor.kcal, average)
            high = (7 * average - Double(7 - k) * low) / Double(k)
        }
        return (0..<7).map { highDays.contains($0) ? high.rounded() : low.rounded() }
    }

    /// Targets of one weekday: protein and fat stay constant, carbs absorb the calorie shift
    /// (fat does on keto).
    func dayTargets(weekday index: Int, calories: Double, protein: Double, carbs: Double, fat: Double,
                    overrides: WeekdayCalorieTargets = .current)
        -> (calories: Double, protein: Double, carbs: Double, fat: Double)
    {
        let index = min(max(index, 0), 6)
        let kcal = overrides.values[index + 1].map(Double.init) ?? weekCalories(average: calories)[index]
        let delta = kcal - calories
        guard delta != 0 else { return (calories, protein, carbs, fat) }
        if let split = collaborativeSplit, split.isValid {
            return (kcal, (kcal * split.protein / 400).rounded(), (kcal * split.carbs / 400).rounded(),
                    (kcal * split.fat / 900).rounded())
        }
        if diet == .keto {
            return (kcal, protein, carbs, max(0, (fat + delta / 9).rounded()))
        }
        return (kcal, protein, max(0, (carbs + delta / 4).rounded()), fat)
    }
}

extension CoachingCheckIn {
    /// Older records contain base targets, not the distribution that was in effect. Preserve
    /// their recorded values unless an explicit recurring target applies to the requested day.
    func targets(on day: Date, preferences: ProgramPreferences = .current,
                 overrides: WeekdayCalorieTargets = .current) -> NutrientValues {
        guard overrides.calories(on: day) != nil else {
            return NutrientValues([.calories: calorieTarget, .protein: proteinTarget,
                                   .carbohydrates: carbsTarget, .totalFat: fatTarget])
        }
        let t = preferences.dayTargets(weekday: CoachingFormat.mondayIndex(of: day),
                                       calories: calorieTarget, protein: proteinTarget,
                                       carbs: carbsTarget, fat: fatTarget, overrides: overrides)
        return NutrientValues([.calories: t.calories, .protein: t.protein,
                               .carbohydrates: t.carbs, .totalFat: t.fat])
    }
}

extension UserProfile {
    /// Targets of `day`, with the weekly calorie distribution applied (fiber unchanged).
    func targets(on day: Date, preferences: ProgramPreferences = .current,
                 overrides: WeekdayCalorieTargets = .current) -> NutrientValues {
        let t = preferences.dayTargets(weekday: CoachingFormat.mondayIndex(of: day),
                                       calories: calorieTarget, protein: proteinTarget,
                                       carbs: carbsTarget, fat: fatTarget, overrides: overrides)
        return NutrientValues([
            .calories: t.calories, .protein: t.protein,
            .carbohydrates: t.carbs, .totalFat: t.fat, .dietaryFiber: fiberTarget,
        ])
    }
}
