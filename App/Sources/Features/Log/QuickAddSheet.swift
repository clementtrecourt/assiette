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
                Section {
                    TextField("Nom", text: $name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .calories }
                        .foregroundStyle(Theme.textPrimary)
                } header: {
                    Text("Description")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(Theme.calories)
                        TextField("0", text: $caloriesText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .calories)
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("kcal")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if macroCalories > 0 {
                        Button {
                            caloriesText = Formatters.number(macroCalories, maxFractionDigits: 0)
                                .filter { !$0.isWhitespace }
                        } label: {
                            Label("Calculer depuis les macros (≈ \(Formatters.kcal(macroCalories)))",
                                  systemImage: "function")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                } header: {
                    Text("Énergie")
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    if hasInvalidInput(caloriesText) {
                        Text("Valeur invalide.").foregroundStyle(Theme.overTarget)
                    } else {
                        Text("Obligatoire.").foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.separator)

                Section {
                    macroRow(.protein, text: $proteinText, field: .protein)
                    macroRow(.carbohydrates, text: $carbsText, field: .carbs)
                    macroRow(.totalFat, text: $fatText, field: .fat)
                } header: {
                    Text("Macronutriments (facultatif)")
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    macroFooter
                }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.separator)

                Section {
                    Picker(selection: $meal) {
                        ForEach(Meal.allCases) { meal in
                            Label(meal.label, systemImage: meal.systemImage).tag(meal)
                        }
                    } label: {
                        Label("Repas", systemImage: "fork.knife")
                    }
                    DatePicker(selection: $day, displayedComponents: .date) {
                        Label("Jour", systemImage: "calendar")
                    }
                }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.separator)
            }
            .listSectionSpacing(.compact)
            .themedBackground()
            .safeAreaInset(edge: .bottom) { primaryButton }
            .navigationTitle("Ajout rapide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focus = nil }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if focus == nil { focus = .calories }
            }
        }
    }

    @ViewBuilder
    private var macroFooter: some View {
        if let calories, macroCalories > 0, abs(macroCalories - calories) > max(30, calories * 0.25) {
            Label("Les macros correspondent à environ \(Formatters.kcal(macroCalories)), assez loin des calories saisies.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.fat)
        } else {
            Text("4 kcal par gramme de protéines ou de glucides, 9 kcal par gramme de lipides.")
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var primaryButton: some View {
        Button {
            save()
        } label: {
            Text("Ajouter au journal")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .opacity(canSave ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Theme.background.ignoresSafeArea(edges: .bottom)
        }
    }

    private func macroRow(_ key: NutrientKey, text: Binding<String>, field: QuickAddField) -> some View {
        HStack {
            Circle()
                .fill(Theme.color(for: key))
                .frame(width: 10, height: 10)
            Text(key.label)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focus, equals: field)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.color(for: key))
                .frame(maxWidth: 110)
            Text("g")
                .foregroundStyle(Theme.textSecondary)
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
