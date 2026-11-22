import SwiftUI

/// Action picked in the journal's "Plus" sheet, run by the journal once the sheet has closed.
enum TodayMoreAction: Equatable {
    case nutrients
    /// Copy the previous day (nil = whole day) into this day.
    case copy(Meal?)
    /// Save the day (nil) or one meal as a recipe.
    case recipe(Meal?)
    case clear
}

/// Journal "⋮" sheet, as on the reference: list of day actions then two display toggles
/// (hide food details, hide empty hours).
struct TodayMoreSheet: View {
    let isToday: Bool
    let hasEntries: Bool
    /// Meals logged this day (recipe options).
    let meals: [Meal]
    let onAction: (TodayMoreAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("today.hideFoodDetails") private var hideFoodDetails = false
    @AppStorage("today.hideEmptyHours") private var hideEmptyHours = false

    var body: some View {
        VStack(spacing: 0) {
            InsightSheetHeader(title: "Plus") { dismiss() }
            row("Nutriments du jour", icon: "doc.text.fill") { onAction(.nutrients) }
            separator
            Menu {
                Button("Toute la journée") { onAction(.copy(nil)) }
                ForEach(Meal.allCases) { meal in
                    Button(meal.label) { onAction(.copy(meal)) }
                }
            } label: {
                rowLabel(isToday ? "Copier depuis hier" : "Copier depuis la veille", icon: "doc.on.doc.fill")
            }
            separator
            Menu {
                if meals.count > 1 {
                    Button("Toute la journée") { onAction(.recipe(nil)) }
                }
                ForEach(meals) { meal in
                    Button(meal.label) { onAction(.recipe(meal)) }
                }
            } label: {
                rowLabel("Enregistrer comme recette", icon: "book.fill")
            }
            .disabled(!hasEntries)
            .opacity(hasEntries ? 1 : 0.4)
            separator
            row("Vider la journée", icon: "trash.fill") { onAction(.clear) }
                .disabled(!hasEntries)
                .opacity(hasEntries ? 1 : 0.4)
            separator
            toggleRow("Masquer les détails", icon: "chevron.up.circle.fill", isOn: $hideFoodDetails)
            separator
            toggleRow("Masquer les heures vides", icon: "hourglass", isOn: $hideEmptyHours)
            Spacer(minLength: 0)
        }
        .tint(Theme.textPrimary)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.raised)
        .presentationCornerRadius(22)
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.separatorStrong)
            .frame(height: Theme.hairline)
            .padding(.leading, 64)
    }

    private func rowLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30)
            Text(title)
                .font(Theme.font(16, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private func row(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30)
            Toggle(title, isOn: isOn.animation(.quick))
                .font(Theme.font(16, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.good)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }
}
