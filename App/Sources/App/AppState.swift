import Foundation
import Observation

enum AppTab: Hashable {
    /// `add` is the central "+" tab: selecting it opens the shortcuts sheet (RootView reverts the
    /// selection). `today` is the Journal tab, `progress` the Accueil (dashboard) tab.
    case today, add, progress, program, profile
}

/// Where a food will be logged: which day, which meal and, optionally, at what time
/// (journal timeline slot). `time == nil` means "now" for today.
struct LogContext: Hashable, Sendable {
    var day: Date
    var meal: Meal
    var time: Date? = nil

    static var now: LogContext { LogContext(day: .now.startOfDay, meal: .suggested()) }

    /// Context for a timeline hour slot of `day` (e.g. 08:00).
    static func slot(day: Date, hour: Int) -> LogContext {
        let start = Calendar.current.startOfDay(for: day)
        let time = Calendar.current.date(byAdding: .hour, value: hour, to: start) ?? start
        return LogContext(day: start, meal: .suggested(for: time), time: time)
    }
}

/// How the add flow opens (tabs of the add sheet).
enum AddMode: String, Hashable, CaseIterable, Identifiable, Sendable {
    case scan, search, quick, recipes
    var id: String { rawValue }
}

/// A request to present the add sheet.
struct AddFlowRequest: Identifiable, Hashable {
    let id = UUID()
    var context: LogContext
    var mode: AddMode
}

/// App-wide UI state, injected with `.environment(appState)`.
/// Read it with `@Environment(AppState.self) private var appState`.
@Observable
final class AppState {
    var selectedTab: AppTab = .progress
    /// Day shown in the journal (start of day).
    var selectedDay: Date = .now.startOfDay

    /// Add sheet currently presented by RootView (nil = none).
    var addFlow: AddFlowRequest?
    /// Shortcuts sheet of the central "+" tab.
    var showingShortcuts = false
    /// Weekly check-in sheet.
    var showingCheckIn = false

    /// Context for adding food: the selected journal day + meal suggested by the clock.
    var addTabContext: LogContext { LogContext(day: selectedDay, meal: .suggested()) }

    /// Opens the add sheet. Without a context: the journal's selected day, now.
    func presentAdd(_ mode: AddMode, context: LogContext? = nil) {
        showingShortcuts = false
        addFlow = AddFlowRequest(context: context ?? addTabContext, mode: mode)
    }
}
