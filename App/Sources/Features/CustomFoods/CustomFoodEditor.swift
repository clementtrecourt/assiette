import SwiftData
import SwiftUI
import UIKit

/// Whether the typed nutrition values are per 100 g/ml or per serving.
private enum CustomFoodBasis: String, CaseIterable, Identifiable {
    case per100, perServing
    var id: String { rawValue }
}

private enum CustomFoodField: Hashable {
    case name, brand, barcode, servingLabel, servingGrams, salt
    case nutrient(NutrientKey)
}

/// Create or edit a user food. Sheet content with its own NavigationStack.
struct CustomFoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let food: CustomFood?
    /// Values not editable here (e.g. vitamins from Open Food Facts) are preserved.
    private let baseValues: NutrientValues

    @State private var name: String
    @State private var brand: String
    @State private var barcode: String
    @State private var isLiquid: Bool
    @State private var servingLabel: String
    @State private var servingGramsText: String
    @State private var basis: CustomFoodBasis = .per100
    @State private var texts: [NutrientKey: String]
    @State private var saltText: String
    @State private var showExtras: Bool
    @State private var showDeleteConfirm = false
    @State private var showValidation = false
    @FocusState private var focused: CustomFoodField?

    private static let mainKeys: [NutrientKey] = [.calories, .protein, .carbohydrates, .totalFat]
    private static let extraKeys: [NutrientKey] = [
        .dietaryFiber, .totalSugars, .addedSugars, .saturatedFats, .monounsaturatedFats,
        .polyunsaturatedFats, .transFats, .cholesterol, .potassium, .calcium, .iron,
        .vitaminC, .caffeine, .alcohol,
    ]

    init(food: CustomFood?, prefill: FoodItem? = nil, barcode: String? = nil) {
        self.food = food
        let values: NutrientValues
        if let food {
            values = food.per100
            _name = State(initialValue: food.name)
            _brand = State(initialValue: food.brand ?? "")
            _barcode = State(initialValue: barcode ?? food.ean ?? "")
            _isLiquid = State(initialValue: food.isLiquid)
            _servingLabel = State(initialValue: food.servingLabel ?? "")
            _servingGramsText = State(initialValue: food.servingGrams.map { CustomFoodsNumber.text($0, maxFractionDigits: 1) } ?? "")
        } else if let prefill {
            values = prefill.per100
            _name = State(initialValue: prefill.name)
            _brand = State(initialValue: prefill.brand ?? "")
            _barcode = State(initialValue: barcode ?? prefill.ean ?? "")
            _isLiquid = State(initialValue: prefill.isLiquid)
            _servingLabel = State(initialValue: prefill.servingLabel ?? "")
            _servingGramsText = State(initialValue: prefill.servingGrams.map { CustomFoodsNumber.text($0, maxFractionDigits: 1) } ?? "")
        } else {
            values = NutrientValues()
            _name = State(initialValue: "")
            _brand = State(initialValue: "")
            _barcode = State(initialValue: barcode ?? "")
            _isLiquid = State(initialValue: false)
            _servingLabel = State(initialValue: "")
            _servingGramsText = State(initialValue: "")
        }
        self.baseValues = values

        var initialTexts: [NutrientKey: String] = [:]
        for key in CustomFoodEditor.mainKeys + CustomFoodEditor.extraKeys {
            if let v = values[key] {
                initialTexts[key] = CustomFoodsNumber.text(v, maxFractionDigits: 2)
            }
        }
        _texts = State(initialValue: initialTexts)
        // Sodium (mg) → salt (g): salt = sodium × 2.5 / 1000.
        _saltText = State(initialValue: values[.sodium].map { CustomFoodsNumber.text($0 / 400, maxFractionDigits: 2) } ?? "")
        let hasExtras = CustomFoodEditor.extraKeys.contains { values[$0] != nil } || values[.sodium] != nil
        _showExtras = State(initialValue: hasExtras)
    }

    // MARK: - Derived

    private var isEditing: Bool { food != nil }
    private var unit: String { isLiquid ? "ml" : "g" }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var servingGrams: Double? {
        guard let v = CustomFoodsNumber.parse(servingGramsText), v > 0 else { return nil }
        return v
    }

    private var caloriesValue: Double? { CustomFoodsNumber.parse(texts[.calories] ?? "") }

    private var basisNeedsServing: Bool { basis == .perServing && servingGrams == nil }

    private var canSave: Bool {
        !trimmedName.isEmpty && caloriesValue != nil && !basisNeedsServing
    }

    /// Per 100 g/ml values built from the form.
    private var computedPer100: NutrientValues {
        var values = baseValues
        let factor: Double
        if basis == .perServing, let servingGrams {
            factor = 100 / servingGrams
        } else {
            factor = 1
        }
        for key in CustomFoodEditor.mainKeys + CustomFoodEditor.extraKeys {
            if let v = CustomFoodsNumber.parse(texts[key] ?? ""), v >= 0 {
                values[key] = v * factor
            } else {
                values[key] = nil
            }
        }
        if let salt = CustomFoodsNumber.parse(saltText), salt >= 0 {
            values[.sodium] = salt * 400 * factor
        } else {
            values[.sodium] = nil
        }
        return values
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                    .customFoodsRow()
                servingSection
                    .customFoodsRow()
                nutritionSection
                    .customFoodsRow()
                extrasSection
                    .customFoodsRow()
                previewSection
                    .customFoodsRow()
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Supprimer l'aliment", systemImage: "trash")
                                .font(Theme.headline)
                                .foregroundStyle(Theme.overTarget)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .customFoodsRow()
                }
            }
            .themedBackground()
            .tint(Theme.textPrimary)
            .font(Theme.body)
            .navigationTitle(isEditing ? "Modifier l'aliment" : "Nouvel aliment")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .font(Theme.headline)
                        .disabled(trimmedName.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focused = nil }
                }
            }
            .onChange(of: basis) { oldValue, newValue in
                convertTexts(from: oldValue, to: newValue)
            }
            .confirmationDialog("Supprimer cet aliment ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { deleteFood() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les entrées déjà enregistrées dans le journal sont conservées.")
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            VStack(spacing: 8) {
                TextField("Nom (obligatoire)", text: $name)
                    .focused($focused, equals: .name)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .onSubmit { focused = .brand }
                    .customFoodsInputField(minHeight: 40)
                TextField("Marque (facultatif)", text: $brand)
                    .focused($focused, equals: .brand)
                    .textInputAutocapitalization(.words)
                    .customFoodsInputField(minHeight: 40)
                barcodeField
            }
            .padding(.vertical, 4)
            Toggle(isOn: $isLiquid) {
                Label {
                    Text("Liquide (valeurs en ml)")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textBody)
                } icon: {
                    Image(systemName: "drop")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .tint(Theme.textSecondary)
        } header: {
            CustomFoodsSectionHeader("Aliment")
        } footer: {
            if showValidation && trimmedName.isEmpty {
                CustomFoodsFooterText("Le nom est obligatoire.", color: Theme.overTarget)
            }
        }
    }

    private var barcodeField: some View {
        HStack(spacing: 8) {
            Image(systemName: "barcode")
                .foregroundStyle(Theme.textTertiary)
            TextField("Code-barres (facultatif)", text: $barcode)
                .focused($focused, equals: .barcode)
                .keyboardType(.numberPad)
                .monospacedDigit()
        }
        .customFoodsInputField(minHeight: 40)
    }

    private var servingSection: some View {
        Section {
            TextField("Libellé (ex. 1 pot, 1 tranche)", text: $servingLabel)
                .focused($focused, equals: .servingLabel)
                .customFoodsInputField(minHeight: 40)
                .padding(.vertical, 4)
            HStack(spacing: 8) {
                Text("Quantité")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textBody)
                Spacer()
                TextField("—", text: $servingGramsText)
                    .focused($focused, equals: .servingGrams)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .customFoodsInputField()
                    .frame(maxWidth: 110)
                Text(unit)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 32, alignment: .leading)
            }
        } header: {
            CustomFoodsSectionHeader("Portion")
        } footer: {
            CustomFoodsFooterText("Facultatif. Permet d'ajouter l'aliment au journal en nombre de portions.")
        }
    }

    private var nutritionSection: some View {
        Section {
            basisChips

            ForEach(CustomFoodEditor.mainKeys, id: \.self) { key in
                nutrientRow(key, color: Theme.color(for: key))
            }
        } header: {
            CustomFoodsSectionHeader("Valeurs nutritionnelles")
        } footer: {
            if basisNeedsServing {
                CustomFoodsFooterText("Indiquez la quantité d'une portion pour saisir les valeurs par portion.", color: Theme.overTarget)
            } else if showValidation && caloriesValue == nil {
                CustomFoodsFooterText("Les calories sont obligatoires.", color: Theme.overTarget)
            } else if basis == .perServing, let servingGrams {
                CustomFoodsFooterText("Valeurs pour une portion de \(Formatters.number(servingGrams)) \(unit), converties automatiquement pour 100 \(unit).")
            } else {
                CustomFoodsFooterText("Calories obligatoires. Laissez vide une valeur inconnue.")
            }
        }
    }

    private var basisChips: some View {
        HStack(spacing: 6) {
            CustomFoodsChip(title: "Pour 100 \(unit)", isSelected: basis == .per100) {
                basis = .per100
            }
            CustomFoodsChip(title: "Par portion", isSelected: basis == .perServing) {
                basis = .perServing
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var extrasSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showExtras) {
                ForEach(CustomFoodEditor.extraKeys, id: \.self) { key in
                    nutrientRow(key, color: key == .dietaryFiber ? Theme.fiber : nil)
                }
                saltRow
            } label: {
                Label {
                    Text("Plus de nutriments")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .tint(Theme.textTertiary)
        } footer: {
            if showExtras {
                CustomFoodsFooterText("Le sel est converti en sodium (1 g de sel = 400 mg de sodium).")
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if caloriesValue != nil, !basisNeedsServing {
            let per100 = computedPer100
            Section {
                summaryBlock("Pour 100 \(unit)", values: per100)
                if let servingGrams {
                    summaryBlock(servingTitle(servingGrams), values: per100.forGrams(servingGrams))
                }
                if let warning = energyWarning(per100) {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.fat)
                }
            } header: {
                CustomFoodsSectionHeader("Aperçu")
            }
        }
    }

    // MARK: - Rows

    /// Caption line + 4-column summary, edge to edge between hairlines.
    private func summaryBlock(_ title: String, values: NutrientValues) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
            CustomFoodsMacroSummary(values: values)
                .padding(.horizontal, -8)
        }
        .padding(.vertical, 4)
    }

    private func nutrientRow(_ key: NutrientKey, color: Color?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color ?? Theme.textQuaternary)
                .frame(width: color == nil ? 4 : 7, height: color == nil ? 4 : 7)
                .frame(width: 8)
            Text(key.label)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            TextField("—", text: textBinding(for: key))
                .focused($focused, equals: .nutrient(key))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .customFoodsInputField(minHeight: 34)
                .frame(maxWidth: 100)
            Text(key.unit)
                .font(Theme.callout)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private var saltRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.textQuaternary)
                .frame(width: 4, height: 4)
                .frame(width: 8)
            Text("Sel")
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
            Spacer(minLength: 8)
            TextField("—", text: $saltText)
                .focused($focused, equals: .salt)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .customFoodsInputField(minHeight: 34)
                .frame(maxWidth: 100)
            Text("g")
                .font(Theme.callout)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private func textBinding(for key: NutrientKey) -> Binding<String> {
        Binding(
            get: { texts[key] ?? "" },
            set: { texts[key] = $0 }
        )
    }

    private func servingTitle(_ grams: Double) -> String {
        let label = CustomFoodsText.nilIfBlank(servingLabel) ?? "1 portion"
        return "\(label) (\(Formatters.number(grams)) \(unit))"
    }

    /// Flags obviously inconsistent labels: energy from macros far from the typed kcal.
    private func energyWarning(_ values: NutrientValues) -> String? {
        guard values[.protein] != nil, values[.carbohydrates] != nil, values[.totalFat] != nil else { return nil }
        let fromMacros = values.protein * 4 + values.carbs * 4 + values.fat * 9 + values.value(.alcohol) * 7
        let kcal = values.calories
        guard max(kcal, fromMacros) > 40 else { return nil }
        if abs(kcal - fromMacros) / max(kcal, fromMacros) > 0.25 {
            return "Les macronutriments correspondent à environ \(Formatters.kcal(fromMacros)) pour 100 \(unit). Vérifiez les valeurs."
        }
        if values.protein + values.carbs + values.fat > 101 {
            return "La somme des macronutriments dépasse 100 \(unit)."
        }
        return nil
    }

    // MARK: - Actions

    /// Keeps the meaning of already typed values when switching between per 100 and per serving.
    private func convertTexts(from old: CustomFoodBasis, to new: CustomFoodBasis) {
        guard old != new, let servingGrams else { return }
        let factor = new == .perServing ? servingGrams / 100 : 100 / servingGrams
        for (key, text) in texts {
            if let v = CustomFoodsNumber.parse(text) {
                texts[key] = CustomFoodsNumber.text(v * factor, maxFractionDigits: 2)
            }
        }
        if let salt = CustomFoodsNumber.parse(saltText) {
            saltText = CustomFoodsNumber.text(salt * factor, maxFractionDigits: 2)
        }
    }

    private func save() {
        guard canSave else {
            showValidation = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let values = computedPer100
        let target: CustomFood
        if let food {
            target = food
            target.name = trimmedName
            target.brand = CustomFoodsText.nilIfBlank(brand)
            target.per100 = values
        } else {
            target = CustomFood(name: trimmedName, brand: CustomFoodsText.nilIfBlank(brand), per100: values)
            modelContext.insert(target)
        }
        let digits = barcode.filter(\.isNumber)
        target.ean = digits.isEmpty ? nil : digits
        target.isLiquid = isLiquid
        target.servingGrams = servingGrams
        target.servingLabel = servingGrams == nil ? nil : (CustomFoodsText.nilIfBlank(servingLabel) ?? "1 portion")
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deleteFood() {
        guard let food else { return }
        modelContext.delete(food)
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        dismiss()
    }
}
