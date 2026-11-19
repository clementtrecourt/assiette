import SwiftData
import SwiftUI

/// Journal tab: day bar "‹ Aujourd'hui ›" + the content of the selected day
/// (pinned macro header, timeline log, floating add button).
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @State private var showDatePicker = false

    var body: some View {
        NavigationStack {
            TodayDayContent(day: appState.selectedDay)
                .navigationTitle("Journal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        daySwitcher
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Aujourd'hui") {
                            go(to: Date.now.startOfDay)
                        }
                        .opacity(isToday ? 0 : 1)
                        .disabled(isToday)
                        .accessibilityHidden(isToday)
                    }
                }
                .sheet(isPresented: $showDatePicker) {
                    datePickerSheet
                }
                .sensoryFeedback(.selection, trigger: appState.selectedDay)
        }
    }

    // MARK: - Day switcher

    private var isToday: Bool {
        Calendar.current.isDateInToday(appState.selectedDay)
    }

    private var daySwitcher: some View {
        HStack(spacing: 0) {
            Button {
                go(to: appState.selectedDay.adding(days: -1))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Jour précédent")

            Button {
                showDatePicker = true
            } label: {
                VStack(spacing: 0) {
                    Text(TodayDayFormat.title(for: appState.selectedDay))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle = TodayDayFormat.subtitle(for: appState.selectedDay) {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 150)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choisir une date")

            Button {
                go(to: appState.selectedDay.adding(days: 1))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Jour suivant")
        }
    }

    private var datePickerSheet: some View {
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
                .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Choisir un jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Aujourd'hui") {
                        go(to: Date.now.startOfDay)
                        showDatePicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { showDatePicker = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
        .tint(Theme.accent)
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

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
