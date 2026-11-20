import Foundation

/// Screens pushed from the dashboard (handled by `navigationDestination` in DashboardView).
enum DashboardRoute: Hashable {
    case expenditure, weightTrend, goal, energyBalance, nutrients, weights
}

/// Daily targets read from the profile (UserProfile defaults when there is no profile yet).
struct DashboardTargets {
    var calories: Double = 2000
    var carbs: Double = 220
    var protein: Double = 120
    var fat: Double = 70
    var fiber: Double = 30

    /// Targets of `day` (weekly calorie distribution applied).
    init(profile: UserProfile?, day: Date = .now) {
        guard let profile else { return }
        let t = profile.targets(on: day)
        calories = t.calories
        carbs = t.carbs
        protein = t.protein
        fat = t.fat
        fiber = profile.fiberTarget
    }

    /// Target of `key`: the profile targets, otherwise the adult reference intake.
    func value(for key: NutrientKey) -> Double {
        switch key {
        case .calories: calories
        case .carbohydrates: carbs
        case .protein: protein
        case .totalFat: fat
        case .dietaryFiber: fiber
        default: key.dailyReference ?? 0
        }
    }
}

enum DashboardFormat {
    /// "Vendredi 20 novembre"
    static func dateLine(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Formatters.locale))
        return text.prefix(1).uppercased() + String(text.dropFirst())
    }

    /// Signed number with a real minus sign: "−649", "+120", "0".
    static func signed(_ value: Double, maxFractionDigits: Int = 0) -> String {
        let factor = pow(10, Double(maxFractionDigits))
        let rounded = (value * factor).rounded() / factor
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "")
        return sign + Formatters.number(abs(rounded), maxFractionDigits: maxFractionDigits)
    }

    /// Whole kcal ("2 356"), or "–" when unknown.
    static func kcalNumber(_ value: Double?) -> String {
        guard let value, value > 0 else { return "–" }
        return Formatters.number(value, maxFractionDigits: 0)
    }

    /// "depuis aujourd'hui", "depuis 1 jour", "depuis 11 jours".
    static func since(_ start: Date, today: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: start.startOfDay, to: today.startOfDay).day ?? 0
        switch days {
        case ...0: return "depuis aujourd'hui"
        case 1: return "depuis 1 jour"
        default: return "depuis \(days) jours"
        }
    }
}

/// Progress toward the goal weight, measured on the trend weight.
struct DashboardGoalProgress {
    var startDate: Date
    var startKg: Double
    var currentKg: Double
    var targetKg: Double
    /// 0…1 share of the way from `startKg` to `targetKg`.
    var fraction: Double

    var remainingKg: Double { abs(targetKg - currentKg) }
    var isReached: Bool { fraction >= 0.999 }

    /// Nil without a goal weight, or in maintenance.
    /// - Parameters:
    ///   - checkIns: sorted by date, ascending.
    ///   - weights: sorted by date, ascending.
    static func compute(profile: UserProfile?, checkIns: [CoachingCheckIn], weights: [WeightEntry],
                        snapshot: CoachingSnapshot) -> DashboardGoalProgress?
    {
        guard let profile, profile.goal != .maintain, let target = profile.targetWeightKg else { return nil }
        let current = snapshot.trendKg ?? weights.last?.kg ?? profile.weightKg

        // The goal started at the first check-in of the latest run with the current goal.
        var startCheckIn: CoachingCheckIn?
        for checkIn in checkIns.reversed() {
            guard checkIn.goalRaw == profile.goalRaw else { break }
            startCheckIn = checkIn
        }

        let startDate: Date
        var startKg: Double?
        if let startCheckIn {
            startDate = startCheckIn.date
            startKg = startCheckIn.trendKg ?? startCheckIn.scaleKg
        } else if let first = weights.first {
            startDate = first.date
        } else {
            startDate = profile.createdAt
        }
        if startKg == nil {
            let day = startDate.startOfDay
            startKg = snapshot.days.first(where: { $0.date >= day && $0.smoothedTrendKg != nil })?.smoothedTrendKg
                ?? weights.first(where: { $0.date >= day })?.kg
                ?? weights.last?.kg
                ?? profile.weightKg
        }
        let start = startKg ?? current

        let total = start - target
        let fraction: Double
        if abs(total) < 0.05 {
            fraction = 1
        } else {
            fraction = min(max((start - current) / total, 0), 1)
        }
        return DashboardGoalProgress(startDate: startDate, startKg: start, currentKg: current,
                                     targetKg: target, fraction: fraction)
    }
}

enum DashboardData {
    /// Last `count` days (oldest first, today included) of intake vs expenditure.
    /// Today uses the live `todayIntake` (partial); past days the engine's usable intake.
    static func balancePoints(snapshot: CoachingSnapshot, count: Int, today: Date,
                              todayIntake: Double) -> [ProgressBalancePoint]
    {
        let todayStart = today.startOfDay
        let indices = snapshot.days.indices.suffix(count)
        return indices.map { index in
            let day = snapshot.days[index]
            let isToday = day.date.startOfDay == todayStart
            let intake: Double?
            if isToday {
                intake = todayIntake > 0 ? todayIntake : nil
            } else {
                intake = index < snapshot.intake.count ? snapshot.intake[index] : nil
            }
            return ProgressBalancePoint(date: day.date, intake: intake, expenditure: day.expenditure,
                                        isPartial: isToday)
        }
    }

    /// One flag per day for the last `count` days (oldest first, today last).
    static func presence(of days: Set<Date>, count: Int, today: Date) -> [Bool] {
        let todayStart = today.startOfDay
        return (0..<count).map { offset in
            days.contains(todayStart.adding(days: offset - (count - 1)).startOfDay)
        }
    }
}
