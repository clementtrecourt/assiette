import SwiftData
import SwiftUI

/// Journal tab: "Journal" title + date line with day navigation, then the content of the
/// selected day (pinned remaining header, hourly timeline). The floating search bar is added
/// below this view by RootView.
/// The title bar is drawn by `TodayDayContent` (it also hosts the day's "…" menu), so the
/// system navigation bar is hidden on this root screen; pushed screens show theirs.
struct TodayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            TodayDayContent(day: appState.selectedDay)
                .navigationTitle("Journal")
                .toolbar(.hidden, for: .navigationBar)
                .sensoryFeedback(.selection, trigger: appState.selectedDay)
        }
    }
}

/// "Journal" title + small date line (tap → date picker), "Aujourd'hui" shortcut when another
/// day is shown, round day chevrons, calendar button and a trailing accessory (the "…" menu).
struct TodayTitleBar<Accessory: View>: View {
    let day: Date
    let onShiftDay: (Int) -> Void
    let onPickDate: () -> Void
    let onToday: () -> Void
    let accessory: Accessory

    @AppStorage("today.headerShowsConsumed") private var showsConsumed = false

    init(day: Date,
         onShiftDay: @escaping (Int) -> Void,
         onPickDate: @escaping () -> Void,
         onToday: @escaping () -> Void,
         @ViewBuilder accessory: () -> Accessory) {
        self.day = day
        self.onShiftDay = onShiftDay
        self.onPickDate = onPickDate
        self.onToday = onToday
        self.accessory = accessory()
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            titleButton
                .layoutPriority(1)
            Spacer(minLength: 4)
            if !isToday {
                todayButton
            }
            roundButton("calendar", label: "Choisir une date", action: onPickDate)
            roundButton("slider.horizontal.3",
                        label: showsConsumed ? "Afficher le restant" : "Afficher le consommé") {
                withAnimation(.snappy) { showsConsumed.toggle() }
            }
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var titleButton: some View {
        Button(action: onPickDate) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? "AUJOURD’HUI" : "JOURNAL")
                    .font(Theme.screenTitle())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !isToday {
                    Text(TodayDayFormat.dateLine(for: day))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Journal, \(TodayDayFormat.dateLine(for: day))")
        .accessibilityHint("Choisir une date")
        .accessibilityAction(named: "Jour précédent") { onShiftDay(-1) }
        .accessibilityAction(named: "Jour suivant") { onShiftDay(1) }
    }

    private var todayButton: some View {
        Button(action: onToday) {
            Text("Aujourd'hui")
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Capsule().fill(Theme.raised2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TodayRoundIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Graphical date picker bound to the journal's selected day.
struct TodayDatePickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Jour",
                    selection: Binding(
                        get: { appState.selectedDay },
                        set: { newValue in go(to: newValue) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                // White would hide the selected day's (white) number: use the calories blue.
                .tint(Theme.calories)
                .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .background(Theme.raised.ignoresSafeArea())
            .navigationTitle("Choisir un jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.raised, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Aujourd'hui") {
                        go(to: Date.now.startOfDay)
                        dismiss()
                    }
                    .font(Theme.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .font(Theme.headline)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.raised)
        .tint(Theme.textPrimary)
    }

    private func go(to date: Date) {
        let target = date.startOfDay
        guard target != appState.selectedDay else { return }
        withAnimation(.snappy) {
            appState.selectedDay = target
        }
    }
}

/// Day title helpers for the journal.
enum TodayDayFormat {
    /// "Aujourd'hui", "Hier", "Demain" or "Lundi 19 novembre".
    static func title(for day: Date) -> String {
        capitalizedFirst(Formatters.dayTitle(day))
    }

    /// Full date under relative titles ("Mercredi 19 novembre"), year for other years.
    static func subtitle(for day: Date) -> String? {
        let cal = Calendar.current
        if cal.isDateInToday(day) || cal.isDateInYesterday(day) || cal.isDateInTomorrow(day) {
            return capitalizedFirst(
                day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Formatters.locale))
            )
        }
        if cal.component(.year, from: day) != cal.component(.year, from: .now) {
            return day.formatted(.dateTime.year().locale(Formatters.locale))
        }
        return nil
    }

    /// Small line under the "Journal" title: "Aujourd'hui · jeu. 19 nov.",
    /// "Lundi 17 novembre", "Lundi 17 novembre 2025".
    static func dateLine(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) || cal.isDateInYesterday(day) || cal.isDateInTomorrow(day) {
            let short = day.formatted(
                .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Formatters.locale)
            )
            return "\(title(for: day)) · \(short)"
        }
        guard let subtitle = subtitle(for: day) else { return title(for: day) }
        return "\(title(for: day)) \(subtitle)"
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
