import Foundation
import Observation

enum AppTab: Hashable {
    case today, add, progress, profile
}

/// Where a food will be logged: which day and which meal.
struct LogContext: Hashable, Sendable {
    var day: Date
    var meal: Meal

    static var now: LogContext { LogContext(day: .now.startOfDay, meal: .suggested()) }
}

/// App-wide UI state, injected with `.environment(appState)`.
/// Read it with `@Environment(AppState.self) private var appState`.
@Observable
final class AppState {
    var selectedTab: AppTab = .today
    /// Day shown in the journal (start of day).
    var selectedDay: Date = .now.startOfDay

    /// Context used by the "Ajouter" tab: the selected journal day + meal suggested by the clock.
    var addTabContext: LogContext { LogContext(day: selectedDay, meal: .suggested()) }
}
