import Foundation
import SwiftData

/// Range of the detail charts pushed from the dashboard.
enum ProgressRange: Int, CaseIterable, Identifiable {
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { "\(rawValue) j" }

    var longLabel: String {
        switch self {
        case .month: "30 derniers jours"
        case .quarter: "90 derniers jours"
        }
    }

    /// First day (start of day) included in the range ending today.
    func startDate(today: Date) -> Date {
        today.startOfDay.adding(days: -(days - 1)).startOfDay
    }
}

/// One dated value of a chart (one per calendar day).
struct ProgressChartPoint: Identifiable, Hashable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// One day of the energy balance chart: logged intake vs estimated expenditure.
struct ProgressBalancePoint: Identifiable, Hashable {
    var date: Date
    /// Logged intake (kcal), nil when the day was not logged.
    var intake: Double?
    var expenditure: Double
    /// Today: the log is not finished yet (drawn lighter, not counted in averages).
    var isPartial: Bool = false
    var id: Date { date }
}

/// Small pure helpers shared by the dashboard and the weight screens.
enum ProgressStats {
    /// Mean scale weight per calendar day (weights sorted ascending), from `start` on.
    static func dailyScaleWeights(_ weights: [WeightEntry], from start: Date = .distantPast) -> [ProgressChartPoint] {
        var byDay: [Date: (sum: Double, count: Int)] = [:]
        for entry in weights where entry.date >= start {
            let day = entry.date.startOfDay
            let current = byDay[day] ?? (sum: 0, count: 0)
            byDay[day] = (sum: current.sum + entry.kg, count: current.count + 1)
        }
        return byDay
            .map { ProgressChartPoint(date: $0.key, value: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
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
/// Targets are not recomputed here: they only change at check-ins and program edits
/// (`CoachingService`).
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
