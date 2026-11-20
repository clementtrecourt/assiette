import Foundation

/// One calendar day of input data for the engine. The engine expects a contiguous,
/// chronologically ordered array with exactly one value per calendar day
/// (use `EngineDay.contiguous(_:calendar:)` to fill the gaps).
struct EngineDay: Equatable, Sendable {
    /// Start of the day.
    var date: Date
    /// Total energy logged that day (kcal), or nil when the day was not logged.
    var intakeKcal: Double?
    /// Scale reading of that day (kg), or nil without a weigh-in.
    var scaleWeightKg: Double?
    /// The log is known to be incomplete: the intake is ignored, as for an unlogged day.
    var isPartial: Bool = false
    /// Exception period (surgery, illness, travel…): the intake is ignored, and the expenditure
    /// estimate is frozen until the energy-balance window no longer covers any such day.
    var isExcluded: Bool = false

    /// Intake usable by the expenditure estimate (nil for unlogged, partial, excluded or zero days).
    var usableIntake: Double? {
        guard !isPartial, !isExcluded, let kcal = intakeKcal, kcal > 0 else { return nil }
        return kcal
    }

    /// Sorts `days`, keeps the last value of duplicated dates and inserts empty days in the gaps.
    static func contiguous(_ days: [EngineDay], calendar: Calendar = .current) -> [EngineDay] {
        var byDay: [Date: EngineDay] = [:]
        for day in days {
            var copy = day
            copy.date = calendar.startOfDay(for: day.date)
            byDay[copy.date] = copy
        }
        guard let first = byDay.keys.min(), let last = byDay.keys.max() else { return [] }
        var result: [EngineDay] = []
        var current = first
        while current <= last {
            result.append(byDay[current] ?? EngineDay(date: current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }
}
