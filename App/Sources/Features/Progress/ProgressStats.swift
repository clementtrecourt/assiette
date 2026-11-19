import Foundation
import SwiftData

/// Range shown by the progress dashboard.
enum ProgressRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { "\(rawValue) j" }

    var longLabel: String {
        switch self {
        case .week: "7 derniers jours"
        case .month: "30 derniers jours"
        case .quarter: "90 derniers jours"
        }
    }

    /// First day (start of day) included in the range ending today.
    func startDate(today: Date) -> Date {
        today.startOfDay.adding(days: -(days - 1)).startOfDay
    }
}

/// Aggregated nutrition for one day of the journal.
struct ProgressDayStat: Identifiable, Hashable {
    let day: Date
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var entryCount: Int = 0

    var id: Date { day }
    var isLogged: Bool { entryCount > 0 }

    mutating func accumulate(calories: Double, protein: Double, carbs: Double, fat: Double) {
        self.calories += calories
        self.protein += protein
        self.carbs += carbs
        self.fat += fat
        entryCount += 1
    }
}

/// One weighing with its 7-day moving average.
struct ProgressWeightPoint: Identifiable {
    let id: PersistentIdentifier
    let date: Date
    let kg: Double
    let average: Double
}

/// Pure aggregation helpers for the progress dashboard.
enum ProgressStats {
    /// One stat per day from `start` (inclusive), `days` days long. Days without entries have zeros.
    static func dailyStats(entries: [JournalEntry], from start: Date, days: Int) -> [ProgressDayStat] {
        var byDay: [Date: ProgressDayStat] = [:]
        byDay.reserveCapacity(days)
        for entry in entries {
            let day = entry.day.startOfDay
            // Read the (memoized) per-100 g bag once and scale only the 4 values needed,
            // instead of building a full scaled NutrientValues per entry.
            let per100 = entry.per100
            let factor = entry.grams / 100
            byDay[day, default: ProgressDayStat(day: day)].accumulate(
                calories: per100.calories * factor, protein: per100.protein * factor,
                carbs: per100.carbs * factor, fat: per100.fat * factor)
        }
        let first = start.startOfDay
        return (0..<max(days, 0)).map { offset in
            let day = first.adding(days: offset).startOfDay
            return byDay[day] ?? ProgressDayStat(day: day)
        }
    }

    /// Weighings (sorted ascending by date) with a trailing 7-day moving average.
    static func weightPoints(_ weights: [WeightEntry]) -> [ProgressWeightPoint] {
        var result: [ProgressWeightPoint] = []
        result.reserveCapacity(weights.count)
        var windowStart = 0
        var windowSum = 0.0
        for (index, entry) in weights.enumerated() {
            windowSum += entry.kg
            let limit = entry.date.addingTimeInterval(-7 * 24 * 3600)
            while windowStart < index && weights[windowStart].date <= limit {
                windowSum -= weights[windowStart].kg
                windowStart += 1
            }
            let count = Double(index - windowStart + 1)
            result.append(ProgressWeightPoint(id: entry.persistentModelID, date: entry.date,
                                              kg: entry.kg, average: windowSum / count))
        }
        return result
    }

    /// Number of consecutive days with at least one entry, ending today (or yesterday if
    /// nothing has been logged yet today). Uses `loggedDays` inside the range; older days are
    /// read in batches of `day` values only (newest first) instead of one count query per day.
    static func streak(loggedDays: Set<Date>, rangeStart: Date, today: Date,
                       context: ModelContext) -> Int {
        let rangeStart = rangeStart.startOfDay
        var olderDays: [Date] = []      // distinct start-of-days before rangeStart, newest first
        var olderExhausted = false
        var olderOffset = 0
        let batchSize = 512

        func loadMoreOlderDays() {
            guard !olderExhausted else { return }
            let limit = rangeStart
            var descriptor = FetchDescriptor<JournalEntry>(
                predicate: #Predicate<JournalEntry> { entry in
                    entry.day < limit
                },
                sortBy: [SortDescriptor(\JournalEntry.day, order: .reverse)]
            )
            descriptor.propertiesToFetch = [\JournalEntry.day]
            descriptor.fetchOffset = olderOffset
            descriptor.fetchLimit = batchSize
            let batch = (try? context.fetch(descriptor)) ?? []
            olderOffset += batch.count
            if batch.count < batchSize { olderExhausted = true }
            for entry in batch {
                let day = entry.day.startOfDay
                if olderDays.last != day { olderDays.append(day) }
            }
        }

        var olderIndex = 0
        func isOlderDayLogged(_ day: Date) -> Bool {
            while true {
                while olderIndex < olderDays.count, olderDays[olderIndex] > day {
                    olderIndex += 1
                }
                if olderIndex < olderDays.count { return olderDays[olderIndex] == day }
                if olderExhausted { return false }
                loadMoreOlderDays()
            }
        }

        func isLogged(_ day: Date) -> Bool {
            day >= rangeStart ? loggedDays.contains(day) : isOlderDayLogged(day)
        }

        var day = today.startOfDay
        if !isLogged(day) { day = day.adding(days: -1).startOfDay }
        var count = 0
        while count < 3650, isLogged(day) {
            count += 1
            day = day.adding(days: -1).startOfDay
        }
        return count
    }

    /// Signed kg string: "+1,2 kg", "−0,8 kg", "0 kg".
    static func signedKg(_ delta: Double) -> String {
        let rounded = (delta * 10).rounded() / 10
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "")
        return "\(sign)\(Formatters.number(abs(rounded), maxFractionDigits: 1)) kg"
    }

    static func kg(_ value: Double) -> String {
        "\(Formatters.number(value, maxFractionDigits: 1)) kg"
    }
}

/// Keeps `UserProfile.weightKg` in sync with the most recent weighing.
enum ProgressWeightSync {
    static func syncProfileWeight(in context: ModelContext) {
        // Persist pending inserts/deletes first so the fetch below sees them.
        try? context.save()
        var descriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\WeightEntry.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let latest = try? context.fetch(descriptor).first,
           let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first,
           abs(profile.weightKg - latest.kg) > 0.0001 {
            profile.weightKg = latest.kg
            GoalCalculator.apply(to: profile)
        }
        try? context.save()
    }

    /// Parses a French or English decimal ("72,5" / "72.5"). Returns nil when out of range.
    static func parseKg(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard let value = Double(cleaned), value >= 20, value <= 400 else { return nil }
        return value
    }
}
