import Foundation

// Data behind the dashboard detail screens (Dépense, Poids tendance, Objectif, Bilan
// énergétique), laid out like the reference app: range chips (1S … Tout) + chart averaging
// (J / S / M), headline (Moyenne / Différence), change table (3 … 90 jours), value tiles and
// a day-by-day history grouped by month.

/// Range chips under the detail charts.
enum InsightRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, half = 182, year = 365, all = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week: "1S"
        case .month: "1M"
        case .quarter: "3M"
        case .half: "6M"
        case .year: "1A"
        case .all: "Tout"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .week: "1 semaine"
        case .month: "1 mois"
        case .quarter: "3 mois"
        case .half: "6 mois"
        case .year: "1 an"
        case .all: "Tout l'historique"
        }
    }

    /// First day shown. `.week` is the current calendar week (Monday → Sunday, as the reference
    /// shows lun. … dim.); `.all` starts at the first day of history.
    func startDate(today: Date, firstDay: Date?) -> Date {
        let today = today.startOfDay
        switch self {
        case .all:
            return min(firstDay?.startOfDay ?? today, today)
        case .week:
            return InsightCalendar.monday(of: today)
        default:
            return today.adding(days: -(rawValue - 1)).startOfDay
        }
    }

    /// Last day of the x-axis (Sunday of the current week for `.week`, else today).
    func endDate(today: Date) -> Date {
        self == .week ? InsightCalendar.monday(of: today).adding(days: 6).startOfDay : today.startOfDay
    }

    /// Days between two x-axis labels.
    var labelStrideDays: Int {
        switch self {
        case .week: 1
        case .month: 5
        case .quarter: 13
        case .half: 30
        case .year: 61
        case .all: 0
        }
    }
}

/// "D – Daily / W – Weekly / M – Monthly" chart averaging.
enum InsightAveraging: String, CaseIterable, Identifiable {
    case daily = "J", weekly = "S", monthly = "M"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "J – Quotidienne"
        case .weekly: "S – Hebdomadaire"
        case .monthly: "M – Mensuelle"
        }
    }
}

enum InsightCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Formatters.locale
        calendar.firstWeekday = 2
        return calendar
    }

    static func monday(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start.startOfDay ?? date.startOfDay
    }

    static func days(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start.startOfDay, to: end.startOfDay).day ?? 0
    }

    /// "16 – 22 nov. 2026", "24 oct. – 22 nov. 2026", "28 déc. 2025 – 3 janv. 2026".
    static func rangeLabel(_ start: Date, _ end: Date, endIsToday: Bool = false) -> String {
        let locale = Formatters.locale
        let endText = endIsToday
            ? "Aujourd'hui"
            : end.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        let sameYear = Calendar.current.component(.year, from: start) == Calendar.current.component(.year, from: end)
        let sameMonth = sameYear && Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end)
        let startText: String
        if endIsToday || !sameYear {
            startText = start.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        } else if sameMonth {
            startText = start.formatted(.dateTime.day().locale(locale))
        } else {
            startText = start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        }
        return "\(startText) – \(endText)"
    }

    /// "ven. 20 nov."
    static func rowDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Formatters.locale))
    }

    /// "novembre 2026"
    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(Formatters.locale))
    }
}

/// One plotted value (a day, or a week / month average). `low`…`high` is the band around it.
struct InsightPoint: Identifiable, Hashable {
    var date: Date
    var value: Double
    var low: Double
    var high: Double
    /// Expenditure only: the estimate did not update ("holding"), drawn as a square marker.
    var isHolding = false
    /// Scale weight of that day (weight chart dots).
    var scale: Double?
    var id: Date { date }

    init(date: Date, value: Double, low: Double? = nil, high: Double? = nil, isHolding: Bool = false,
         scale: Double? = nil)
    {
        self.date = date
        self.value = value
        self.low = low ?? value
        self.high = high ?? value
        self.isHolding = isHolding
        self.scale = scale
    }

    /// Averages `points` per week or month (date = first day of the period).
    static func averaged(_ points: [InsightPoint], by averaging: InsightAveraging) -> [InsightPoint] {
        guard averaging != .daily else { return points }
        let calendar = InsightCalendar.calendar
        let component: Calendar.Component = averaging == .weekly ? .weekOfYear : .month
        var groups: [Date: [InsightPoint]] = [:]
        for point in points {
            let key = calendar.dateInterval(of: component, for: point.date)?.start ?? point.date
            groups[key, default: []].append(point)
        }
        return groups.map { date, group in
            let count = Double(group.count)
            let scales = group.compactMap(\.scale)
            return InsightPoint(date: date,
                                value: group.map(\.value).reduce(0, +) / count,
                                low: group.map(\.low).reduce(0, +) / count,
                                high: group.map(\.high).reduce(0, +) / count,
                                isHolding: group.allSatisfy(\.isHolding),
                                scale: scales.isEmpty ? nil : scales.reduce(0, +) / Double(scales.count))
        }
        .sorted { $0.date < $1.date }
    }
}

/// One row of the "Évolution sur…" tables: change over `days`, with the values for the sparkline.
struct InsightChange: Identifiable {
    var days: Int
    var delta: Double
    var series: [Double]
    var id: Int { days }

    static let windows = [3, 7, 14, 30, 90]

    /// Changes of a daily series (oldest first, last = today) over 3 … 90 days.
    static func table(_ values: [Double]) -> [InsightChange] {
        windows.compactMap { days in
            guard values.count > 1 else { return nil }
            let slice = Array(values.suffix(days + 1))
            guard let first = slice.first, let last = slice.last else { return nil }
            return InsightChange(days: days, delta: last - first, series: slice)
        }
    }
}

/// Bars of the energy balance chart (intake vs expenditure or vs calorie target).
struct InsightBalanceDay: Identifiable, Hashable {
    var date: Date
    /// Logged intake; nil when nothing was logged.
    var intake: Double?
    var expenditure: Double
    var target: Double
    /// Today: the log is not finished, not counted in averages.
    var isPartial: Bool
    var id: Date { date }
}

/// History rows of one month.
struct InsightMonthGroup<Item>: Identifiable {
    var month: Date
    var items: [Item]
    var id: Date { month }
}

enum DashboardInsights {
    // MARK: Expenditure

    /// Daily expenditure with its "flux range" (how far recent raw energy-balance measurements
    /// pull from the estimate) and holding days.
    static func expenditurePoints(_ snapshot: CoachingSnapshot) -> [InsightPoint] {
        var points: [InsightPoint] = []
        var recent: [Double] = []
        var holdingRun = 0
        for day in snapshot.days {
            if let raw = day.energyBalance {
                recent.append(raw - day.expenditure)
                if recent.count > 14 { recent.removeFirst() }
            }
            holdingRun = day.isHolding ? holdingRun + 1 : 0
            let spread: Double
            if recent.count >= 2 {
                let mean = recent.reduce(0, +) / Double(recent.count)
                let variance = recent.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(recent.count - 1)
                spread = variance.squareRoot()
            } else {
                spread = 150
            }
            // Narrow band (≈ ±10–40 kcal) widening while the estimate is holding.
            let half = min(max(spread * 0.08, 8), 45) + Double(min(holdingRun, 14)) * 3
            points.append(InsightPoint(date: day.date, value: day.expenditure,
                                       low: day.expenditure - half, high: day.expenditure + half,
                                       isHolding: day.isHolding))
        }
        return points
    }

    // MARK: Weight

    /// Daily trend weight with the noise range (distance to the scale readings, decaying on
    /// days without a weigh-in) and the scale weight of the day.
    static func weightPoints(_ snapshot: CoachingSnapshot, scale: [ProgressChartPoint]) -> [InsightPoint] {
        let scaleByDay = Dictionary(scale.map { ($0.date.startOfDay, $0.value) }, uniquingKeysWith: { a, _ in a })
        var half = 0.15
        return snapshot.days.compactMap { day in
            guard let trend = day.smoothedTrendKg else { return nil }
            let reading = scaleByDay[day.date.startOfDay]
            if let reading {
                half = max(abs(reading - trend), 0.08)
            } else {
                half = max(half * 0.85, 0.08)
            }
            return InsightPoint(date: day.date, value: trend, low: trend - half, high: trend + half, scale: reading)
        }
    }

    /// Typical weekly change of the trend over the last three weeks, weighted toward recent
    /// days (weighted least-squares slope × 7). Nil with less than a week of trend.
    static func weeklyWeightChange(_ snapshot: CoachingSnapshot) -> Double? {
        let values = snapshot.days.suffix(21).compactMap(\.smoothedTrendKg)
        guard values.count >= 7 else { return nil }
        let n = values.count
        let weights = (0..<n).map { Double($0 + 1) }
        let xs = (0..<n).map(Double.init)
        let sw = weights.reduce(0, +)
        let mx = zip(weights, xs).map { $0 * $1 }.reduce(0, +) / sw
        let my = zip(weights, values).map { $0 * $1 }.reduce(0, +) / sw
        var num = 0.0, den = 0.0
        for i in 0..<n {
            num += weights[i] * (xs[i] - mx) * (values[i] - my)
            den += weights[i] * (xs[i] - mx) * (xs[i] - mx)
        }
        guard den > 0 else { return nil }
        return num / den * 7
    }

    /// kcal per kg used to turn a weekly weight change into a daily energy balance.
    static let energyDensity = 7700.0

    // MARK: Goal

    /// One bar of the goal "waterfall": distance to the goal weight moving from `start` to `end`.
    struct GoalStep: Identifiable, Hashable {
        enum Kind { case away, towards, status }
        var index: Int
        var label: String
        var start: Double
        var end: Double
        var kind: Kind
        var id: Int { index }
    }

    /// Day 0 = distance at the start of the goal, then one step per weigh-in day (scale) or per
    /// week (trend), then the current status.
    static func goalSteps(progress: DashboardGoalProgress, snapshot: CoachingSnapshot,
                          scale: [ProgressChartPoint], useTrend: Bool, today: Date) -> [GoalStep]
    {
        let start = progress.startDate.startOfDay
        let target = progress.targetKg
        var samples: [(day: Int, kg: Double)] = []
        if useTrend {
            let trend = snapshot.days.filter { $0.date >= start }
            for (offset, day) in trend.enumerated() where offset % 7 == 0 || offset == trend.count - 1 {
                if let kg = day.smoothedTrendKg { samples.append((offset, kg)) }
            }
        } else {
            for point in scale where point.date >= start {
                samples.append((InsightCalendar.days(from: start, to: point.date), point.value))
            }
        }
        guard let first = samples.first else { return [] }
        var steps = [GoalStep(index: 0, label: "0", start: 0, end: abs(first.kg - target), kind: .away)]
        var previous = abs(first.kg - target)
        for sample in samples.dropFirst() {
            let distance = abs(sample.kg - target)
            steps.append(GoalStep(index: steps.count, label: "\(sample.day)", start: previous, end: distance,
                                  kind: distance > previous ? .away : .towards))
            previous = distance
        }
        steps.append(GoalStep(index: steps.count, label: "Statut", start: 0, end: previous, kind: .status))
        return steps
    }

    // MARK: Energy balance

    /// Days of the energy-balance chart from `start` to today.
    static func balanceDays(snapshot: CoachingSnapshot, from start: Date, today: Date, todayIntake: Double,
                            target: (Date) -> Double) -> [InsightBalanceDay]
    {
        let todayStart = today.startOfDay
        return snapshot.days.indices.compactMap { index in
            let day = snapshot.days[index]
            guard day.date >= start else { return nil }
            let isToday = day.date.startOfDay == todayStart
            let intake: Double? = isToday
                ? (todayIntake > 0 ? todayIntake : nil)
                : (index < snapshot.intake.count ? snapshot.intake[index] : nil)
            return InsightBalanceDay(date: day.date, intake: intake, expenditure: day.expenditure,
                                     target: target(day.date), isPartial: isToday)
        }
    }

    /// Mean of `value(day)` over the logged, complete days of the last `count` days (today included
    /// in the window but never counted, its log is not finished).
    static func average(_ days: [InsightBalanceDay], lastDays count: Int, today: Date,
                        value: (InsightBalanceDay) -> Double) -> Double?
    {
        let first = today.startOfDay.adding(days: -(count - 1)).startOfDay
        let values = days.filter { $0.date >= first && !$0.isPartial && $0.intake != nil }.map(value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: History

    /// Rows grouped by month, newest first.
    static func groupedByMonth<T>(_ items: [T], date: (T) -> Date) -> [InsightMonthGroup<T>] {
        let calendar = Calendar.current
        var groups: [Date: [T]] = [:]
        for item in items {
            let day = date(item)
            let key = calendar.dateInterval(of: .month, for: day)?.start ?? day
            groups[key, default: []].append(item)
        }
        var result: [InsightMonthGroup<T>] = []
        for key in groups.keys.sorted(by: >) {
            let sorted = (groups[key] ?? []).sorted { date($0) > date($1) }
            result.append(InsightMonthGroup(month: key, items: sorted))
        }
        return result
    }
}
