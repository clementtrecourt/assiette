import Foundation
import SwiftData

/// Everything the dashboard, the program tab and the check-in need from the adaptive engine,
/// computed from the whole SwiftData history.
struct CoachingSnapshot {
    /// One result per calendar day, from the first logged day / weigh-in to today.
    var days: [NutritionEngine.DayResult] = []
    /// Logged intake per day (kcal), same indices as `days` (nil = not logged / partial / excluded).
    var intake: [Double?] = []
    /// Expenditure estimate the engine started from.
    var initialExpenditure: Double = 0
    /// Current expenditure estimate (kcal/day).
    var expenditure: Double = 0
    /// Retrospective trend weight today (kg).
    var trendKg: Double?
    /// Latest scale reading (kg).
    var latestScaleKg: Double?

    var isEmpty: Bool { days.isEmpty }

    /// Results of the last `count` days (oldest first), today included.
    func last(_ count: Int) -> ArraySlice<NutritionEngine.DayResult> { days.suffix(count) }

    /// Expenditure change over the last `daysBack` days (nil without enough history).
    func expenditureChange(days daysBack: Int = 7) -> Double? {
        guard days.count > daysBack else { return nil }
        return expenditure - days[days.count - 1 - daysBack].expenditure
    }

    /// Smoothed trend change over the last `daysBack` days (kg, nil without data).
    func trendChange(days daysBack: Int = 7) -> Double? {
        guard days.count > daysBack, let now = days.last?.smoothedTrendKg,
              let before = days[days.count - 1 - daysBack].smoothedTrendKg else { return nil }
        return now - before
    }

    /// Mean intake over the last `count` complete days (today excluded) and how many were logged.
    func averageIntake(lastDays count: Int = 7) -> (average: Double?, logged: Int) {
        let values = intake.dropLast().suffix(count).compactMap { $0 }
        guard !values.isEmpty else { return (nil, 0) }
        return (values.reduce(0, +) / Double(values.count), values.count)
    }

    /// Mean daily energy balance (intake − expenditure) over the last `count` complete days.
    func averageBalance(lastDays count: Int = 7) -> Double? {
        let pairs = zip(intake.dropLast().suffix(count), days.dropLast().suffix(count))
            .compactMap { kcal, day in kcal.map { $0 - day.expenditure } }
        guard !pairs.isEmpty else { return nil }
        return pairs.reduce(0, +) / Double(pairs.count)
    }
}

/// New targets proposed by a check-in.
struct CoachingProposal: Equatable {
    var calories: Double
    var carbs: Double
    var protein: Double
    var fat: Double
}

@MainActor
enum CoachingService {
    /// Correction rate (% of body weight per week) used in maintenance when the trend leaves the band.
    static let maintenanceCorrectionPercent = 0.15

    /// Smallest calorie target a check-in or a manual adjustment can propose.
    static var minimumCalories: Double { ProgramPreferences.current.floor.kcal }



    /// Calendar weekday (1 = Sunday … 7 = Saturday) of `date`.
    static func weekday(of date: Date = .now) -> Int {
        Calendar.current.component(.weekday, from: date)
    }

    /// Day of the next check-in (today when it is due).
    static func nextCheckInDate(profile: UserProfile, today: Date = .now) -> Date {
        Calendar.current.startOfDay(for: today).adding(days: daysUntilCheckIn(profile: profile, today: today))
    }

    /// Weekly change in kg for a rate in % of body weight (positive number).
    static func weeklyKg(ratePercent: Double, weightKg: Double) -> Double {
        ratePercent * weightKg / 100
    }

    // MARK: Snapshot

    static func snapshot(profile: UserProfile, context: ModelContext, today: Date = .now) -> CoachingSnapshot {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)

        var intakeByDay: [Date: Double] = [:]
        if let entries = try? context.fetch(FetchDescriptor<JournalEntry>()) {
            for entry in entries {
                let kcal = entry.per100.calories * entry.grams / 100
                intakeByDay[calendar.startOfDay(for: entry.day), default: 0] += kcal
            }
        }
        var weightsByDay: [Date: [Double]] = [:]
        if let weights = try? context.fetch(FetchDescriptor<WeightEntry>()) {
            for weight in weights {
                weightsByDay[calendar.startOfDay(for: weight.date), default: []].append(weight.kg)
            }
        }
        let exceptions = (try? context.fetch(FetchDescriptor<ExceptionPeriod>())) ?? []
        // Days imported from Apple Health count only when nothing was logged in Assiette that day.
        if let healthDays = try? context.fetch(FetchDescriptor<HealthDay>()) {
            for health in healthDays where health.kcal > 0 {
                let day = calendar.startOfDay(for: health.day)
                if intakeByDay[day] == nil { intakeByDay[day] = health.kcal }
            }
        }

        let initial = profile.initialExpenditure ?? GoalCalculator.targets(for: profile).tdee
        var snapshot = CoachingSnapshot(initialExpenditure: initial, expenditure: initial)
        let firstDay = (Array(intakeByDay.keys) + Array(weightsByDay.keys)).filter { $0 <= todayStart }.min()
        guard let firstDay else { return snapshot }

        var raw: [EngineDay] = []
        var day = firstDay
        while day <= todayStart {
            let weights = weightsByDay[day]
            raw.append(EngineDay(
                date: day,
                intakeKcal: intakeByDay[day],
                scaleWeightKg: weights.map { $0.reduce(0, +) / Double($0.count) },
                isPartial: day == todayStart, // today's log is not finished yet
                isExcluded: exceptions.contains { $0.contains(day) }
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }

        var anchor: EngineExpenditure.Anchor?
        if let kcal = profile.expenditureAnchorKcal, let date = profile.expenditureAnchorDate {
            let anchorDay = calendar.startOfDay(for: date)
            if let index = raw.firstIndex(where: { $0.date == anchorDay }) {
                anchor = .init(index: index, kcal: kcal)
            } else if anchorDay < firstDay {
                anchor = .init(index: 0, kcal: kcal)
            }
        }
        snapshot.days = NutritionEngine.run(days: raw, initialExpenditure: initial, anchor: anchor)
        snapshot.intake = raw.map(\.usableIntake)
        snapshot.expenditure = snapshot.days.last?.expenditure ?? initial
        snapshot.trendKg = snapshot.days.last?.smoothedTrendKg
        snapshot.latestScaleKg = raw.last(where: { $0.scaleWeightKg != nil })?.scaleWeightKg
        return snapshot
    }

    // MARK: Targets

    static func engineGoal(for profile: UserProfile, trendKg: Double?) -> EngineCoach.Goal {
        let rate = profile.effectiveRatePercent
        switch profile.goal {
        case .lose: return .lose(ratePercent: rate)
        case .gain: return .gain(ratePercent: rate)
        case .maintain:
            return .maintain(goalWeightKg: profile.targetWeightKg ?? trendKg ?? profile.weightKg,
                             correctionRatePercent: maintenanceCorrectionPercent)
        }
    }

    static func proposal(snapshot: CoachingSnapshot, profile: UserProfile,
                         preferences: ProgramPreferences = .current) -> CoachingProposal {
        let weight = snapshot.latestScaleKg ?? profile.weightKg
        var parameters = EngineParameters.calibrated
        parameters.minimumCalories = preferences.floor.kcal
        let calories = EngineCoach.calorieTarget(expenditure: snapshot.expenditure, latestScaleWeightKg: weight,
                                                 trendWeightKg: snapshot.trendKg ?? weight,
                                                 goal: engineGoal(for: profile, trendKg: snapshot.trendKg),
                                                 parameters: parameters)
        return proposal(calories: calories, weightKg: weight, goal: profile.goal, preferences: preferences)
    }

    /// Macros for a calorie target (collaborative adjustments re-split the macros the same way),
    /// following the program preferences (diet, protein level, training).
    static func proposal(calories: Double, weightKg: Double, goal: WeightGoal,
                         preferences: ProgramPreferences = .current) -> CoachingProposal {
        let macros = preferences.macros(calories: calories, weightKg: weightKg, goal: goal)
        return CoachingProposal(calories: calories.rounded(), carbs: macros.carbs.rounded(),
                                protein: macros.protein.rounded(), fat: macros.fat.rounded())
    }

    /// Daily calorie delta of the goal (negative for a loss), for explanations ("Dépense − 524 kcal").
    static func goalDelta(profile: UserProfile, snapshot: CoachingSnapshot) -> Double {
        let weight = snapshot.latestScaleKg ?? profile.weightKg
        let delta = EngineCoach.dailyDelta(ratePercent: profile.effectiveRatePercent, weightKg: weight)
        switch profile.goal {
        case .lose: return -delta
        case .gain: return delta
        case .maintain: return 0
        }
    }

    // MARK: Check-in schedule

    /// Days until the next check-in (0 = due today).
    static func daysUntilCheckIn(profile: UserProfile, today: Date = .now) -> Int {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        if isCheckInDue(profile: profile, today: today) { return 0 }
        let weekday = calendar.component(.weekday, from: todayStart)
        var days = (profile.checkInWeekday - weekday + 7) % 7
        if days == 0 { days = 7 }
        return days
    }

    static func isCheckInDue(profile: UserProfile, today: Date = .now) -> Bool {
        guard profile.hasCompletedOnboarding, !profile.manualTargets else { return false }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        let reference = calendar.startOfDay(for: profile.lastCheckInDate ?? profile.createdAt)
        let elapsed = calendar.dateComponents([.day], from: reference, to: todayStart).day ?? 0
        if elapsed >= 7 { return true }
        return elapsed >= 4 && calendar.component(.weekday, from: todayStart) == profile.checkInWeekday
    }

    // MARK: Apply

    /// Saves new targets. `kind` is "weekly" (check-in) or "program" (goal changed).
    static func apply(_ proposal: CoachingProposal, snapshot: CoachingSnapshot, profile: UserProfile,
                      context: ModelContext, kind: String = "weekly", today: Date = .now)
    {
        let day = Calendar.current.startOfDay(for: today)
        profile.calorieTarget = proposal.calories
        profile.carbsTarget = proposal.carbs
        profile.proteinTarget = proposal.protein
        profile.fatTarget = proposal.fat
        // The formula keeps driving the starting estimate until the first weekly check-in freezes it
        // (so profile edits before that, e.g. height or age, still refine it).
        if kind == "weekly" {
            if profile.initialExpenditure == nil { profile.initialExpenditure = snapshot.initialExpenditure }
            profile.lastCheckInDate = day
        }

        // Several program edits on the same day update one history row.
        let existing = (try? context.fetch(FetchDescriptor<CoachingCheckIn>()))?
            .first { $0.kindRaw == kind && Calendar.current.isDate($0.date, inSameDayAs: day) }
        let record = existing ?? CoachingCheckIn(date: day, kindRaw: kind)
        if existing == nil { context.insert(record) }
        record.expenditure = snapshot.expenditure
        record.trendKg = snapshot.trendKg
        record.scaleKg = snapshot.latestScaleKg
        record.averageIntake = snapshot.averageIntake().average
        record.goalRaw = profile.goalRaw
        record.ratePercent = profile.effectiveRatePercent
        record.calorieTarget = proposal.calories
        record.carbsTarget = proposal.carbs
        record.proteinTarget = proposal.protein
        record.fatTarget = proposal.fat
        try? context.save()
    }

    /// Recomputes the targets after a goal / rate change (coached mode only).
    static func refreshTargets(profile: UserProfile, context: ModelContext) {
        guard !profile.manualTargets else { return }
        let snapshot = snapshot(profile: profile, context: context)
        apply(proposal(snapshot: snapshot, profile: profile), snapshot: snapshot, profile: profile,
              context: context, kind: "program")
    }
}
