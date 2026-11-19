import SwiftData
import SwiftUI
import UIKit

private enum QuickAddField: Hashable {
    case name, calories, protein, carbs, fat
}

/// Log calories (and optionally macros) typed by hand.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let context: LogContext
    private let onLogged: (() -> Void)?

    @State private var name = "Ajout rapide"
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var meal: Meal
    @State private var day: Date
    @FocusState private var focus: QuickAddField?

    init(context: LogContext, onLogged: (() -> Void)? = nil) {
        self.context = context
        self.onLogged = onLogged
        _meal = State(initialValue: context.meal)
        _day = State(initialValue: context.day.startOfDay)
    }

    // MARK: - Parsing

    private static func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private var calories: Double? { QuickAddSheet.parse(caloriesText) }
    private var protein: Double? { QuickAddSheet.parse(proteinText) }
    private var carbs: Double? { QuickAddSheet.parse(carbsText) }
    private var fat: Double? { QuickAddSheet.parse(fatText) }

    /// Energy estimated from the macros (4 / 4 / 9 kcal per g).
    private var macroCalories: Double {
        (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
    }

    private func hasInvalidInput(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && QuickAddSheet.parse(text) == nil
    }

    private var canSave: Bool {
        calories != nil
            && !hasInvalidInput(proteinText)
            && !hasInvalidInput(carbsText)
            && !hasInvalidInput(fatText)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                descriptionSection
                energySection
                macrosSection
                whenSection
            }
            .listSectionSpacing(.compact)
            .themedBackground()
            .safeAreaInset(edge: .bottom) { primaryButton }
            .navigationTitle("Ajout rapide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                if focus == nil { focus = .calories }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Annuler") { dismiss() }
                .tint(Theme.textSecondary)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Ajouter") { save() }
                .font(Theme.font(17, .bold, relativeTo: .body))
                .tint(Theme.textPrimary)
                .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("OK") { focus = nil }
                .font(Theme.font(17, .bold, relativeTo: .body))
                .tint(Theme.textPrimary)
        }
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            TextField("Nom", text: $name)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .calories }
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .modifier(QuickAddFieldBox(isFocused: focus == .name))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        } header: {
            QuickAddSectionHeader(title: "Description")
        }
    }

    private var energySection: some View {
        Section {
            caloriesField
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            if macroCalories > 0 {
                computeFromMacrosButton
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 2, trailing: 0))
            }
        } header: {
            QuickAddSectionHeader(title: "Énergie")
        } footer: {
            energyFooter
        }
        .listRowSeparator(.hidden)
    }

    private var caloriesField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.flame)
            TextField("0", text: $caloriesText)
                .keyboardType(.decimalPad)
                .focused($focus, equals: .calories)
                .font(Theme.font(34, .bold, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
            Text("kcal")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(QuickAddFieldBox(isFocused: focus == .calories))
        .contentShape(Rectangle())
        .onTapGesture { focus = .calories }
    }

    private var computeFromMacrosButton: some View {
        Button {
            caloriesText = Formatters.number(macroCalories, maxFractionDigits: 0)
                .filter { !$0.isWhitespace }
        } label: {
            Label {
                Text("Calculer depuis les macros (≈ \(Formatters.kcal(macroCalories)))")
                    .font(Theme.callout)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: "function")
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var energyFooter: some View {
        if hasInvalidInput(caloriesText) {
            Text("Valeur invalide.")
                .font(Theme.caption)
                .foregroundStyle(Theme.overTarget)
        } else {
            Text("Obligatoire.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var macrosSection: some View {
        Section {
            macroRow(.protein, text: $proteinText, field: .protein)
            macroRow(.carbohydrates, text: $carbsText, field: .carbs)
            macroRow(.totalFat, text: $fatText, field: .fat)
        } header: {
            QuickAddSectionHeader(title: "Macronutriments (facultatif)")
        } footer: {
            macroFooter
        }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.separator)
    }

    private var whenSection: some View {
        Section {
            Picker(selection: $meal) {
                ForEach(Meal.allCases) { meal in
                    Label(meal.label, systemImage: meal.systemImage).tag(meal)
                }
            } label: {
                QuickAddFieldLabel(title: "Repas", systemImage: "fork.knife")
            }
            .tint(Theme.textSecondary)
            DatePicker(selection: $day, displayedComponents: .date) {
                QuickAddFieldLabel(title: "Jour", systemImage: "calendar")
            }
            .tint(Theme.calories)
        } header: {
            QuickAddSectionHeader(title: "Quand")
        }
        .font(Theme.body)
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.separator)
    }

    @ViewBuilder
    private var macroFooter: some View {
        if let calories, macroCalories > 0, abs(macroCalories - calories) > max(30, calories * 0.25) {
            Label("Les macros correspondent à environ \(Formatters.kcal(macroCalories)), assez loin des calories saisies.",
                  systemImage: "exclamationmark.triangle")
                .font(Theme.caption)
                .foregroundStyle(Theme.fat)
        } else {
            Text("4 kcal par gramme de protéines ou de glucides, 9 kcal par gramme de lipides.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var primaryButton: some View {
        Button {
            save()
        } label: {
            Text("Ajouter au journal")
                .font(Theme.font(16, .bold, relativeTo: .headline))
                .foregroundStyle(canSave ? Theme.onAccent : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSave ? Theme.accent : Theme.separatorStrong,
                            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Theme.background.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.hairline)
        }
    }

    private func macroRow(_ key: NutrientKey, text: Binding<String>, field: QuickAddField) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.color(for: key))
                .frame(width: 8, height: 8)
            Text(key.label)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focus, equals: field)
                .font(Theme.font(17, .bold, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(Theme.color(for: key))
                .tint(Theme.textPrimary)
                .frame(maxWidth: 110)
            Text("g")
                .font(Theme.callout)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Save

    private func save() {
        guard let calories else { return }
        var values = NutrientValues([.calories: calories])
        if let protein { values[.protein] = protein }
        if let carbs { values[.carbohydrates] = carbs }
        if let fat { values[.totalFat] = fat }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = FoodItem(
            source: .quickAdd,
            ref: nil,
            name: trimmed.isEmpty ? "Ajout rapide" : trimmed,
            brand: nil,
            kind: nil,
            servingLabel: nil,
            servingGrams: nil,
            packageGrams: nil,
            isLiquid: false,
            ean: nil,
            per100: values
        )
        modelContext.insert(JournalEntry(item: item, grams: 100, day: day, meal: meal))
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged?()
        dismiss()
    }
}

/// Raised input surface with a 1 px border (brighter while focused).
private struct QuickAddFieldBox: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? Theme.textTertiary : Theme.separatorStrong, lineWidth: Theme.hairline)
            }
    }
}

/// Section header per DESIGN.md: small uppercase DM Sans in textTertiary.
private struct QuickAddSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// Form row label with a muted monochrome icon.
private struct QuickAddFieldLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
