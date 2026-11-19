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
                    .listRowBackground(Theme.card)
                servingSection
                    .listRowBackground(Theme.card)
                nutritionSection
                    .listRowBackground(Theme.card)
                extrasSection
                    .listRowBackground(Theme.card)
                previewSection
                    .listRowBackground(Theme.card)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Supprimer l'aliment", systemImage: "trash")
                                .foregroundStyle(Theme.overTarget)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .themedBackground()
            .tint(Theme.accent)
            .navigationTitle(isEditing ? "Modifier l'aliment" : "Nouvel aliment")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
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
            TextField("Nom (obligatoire)", text: $name)
                .focused($focused, equals: .name)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .onSubmit { focused = .brand }
            TextField("Marque (facultatif)", text: $brand)
                .focused($focused, equals: .brand)
                .textInputAutocapitalization(.words)
            HStack {
                Image(systemName: "barcode")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Code-barres (facultatif)", text: $barcode)
                    .focused($focused, equals: .barcode)
                    .keyboardType(.numberPad)
                    .font(.body.monospacedDigit())
            }
            Toggle(isOn: $isLiquid) {
                Label("Liquide (valeurs en ml)", systemImage: "drop")
            }
        } header: {
            Text("Aliment")
        } footer: {
            if showValidation && trimmedName.isEmpty {
                Text("Le nom est obligatoire.").foregroundStyle(Theme.overTarget)
            }
        }
    }

    private var servingSection: some View {
        Section {
            TextField("Libellé (ex. 1 pot, 1 tranche)", text: $servingLabel)
                .focused($focused, equals: .servingLabel)
            HStack {
                Text("Quantité")
                Spacer()
                TextField("—", text: $servingGramsText)
                    .focused($focused, equals: .servingGrams)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(unit)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, alignment: .leading)
            }
        } header: {
            Text("Portion")
        } footer: {
            Text("Facultatif. Permet d'ajouter l'aliment au journal en nombre de portions.")
        }
    }

    private var nutritionSection: some View {
        Section {
            Picker("Valeurs", selection: $basis) {
                Text("Pour 100 \(unit)").tag(CustomFoodBasis.per100)
                Text("Par portion").tag(CustomFoodBasis.perServing)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            ForEach(CustomFoodEditor.mainKeys, id: \.self) { key in
                nutrientRow(key, color: Theme.color(for: key))
            }
        } header: {
            Text("Valeurs nutritionnelles")
        } footer: {
            if basisNeedsServing {
                Text("Indiquez la quantité d'une portion pour saisir les valeurs par portion.")
                    .foregroundStyle(Theme.overTarget)
            } else if showValidation && caloriesValue == nil {
                Text("Les calories sont obligatoires.").foregroundStyle(Theme.overTarget)
            } else if basis == .perServing, let servingGrams {
                Text("Valeurs pour une portion de \(Formatters.number(servingGrams)) \(unit), converties automatiquement pour 100 \(unit).")
            } else {
                Text("Calories obligatoires. Laissez vide une valeur inconnue.")
            }
        }
    }

    private var extrasSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showExtras) {
                ForEach(CustomFoodEditor.extraKeys, id: \.self) { key in
                    nutrientRow(key, color: key == .dietaryFiber ? Theme.fiber : nil)
                }
                saltRow
            } label: {
                Label("Plus de nutriments", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(Theme.textPrimary)
            }
        } footer: {
            if showExtras {
                Text("Le sel est converti en sodium (1 g de sel = 400 mg de sodium).")
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if caloriesValue != nil, !basisNeedsServing {
            let per100 = computedPer100
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pour 100 \(unit)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    CustomFoodsMacroSummary(values: per100)
                }
                if let servingGrams {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(servingTitle(servingGrams))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        CustomFoodsMacroSummary(values: per100.forGrams(servingGrams))
                    }
                }
                if let warning = energyWarning(per100) {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.fat)
                }
            } header: {
                Text("Aperçu")
            }
        }
    }

    // MARK: - Rows

    private func nutrientRow(_ key: NutrientKey, color: Color?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color ?? Color.clear)
                .frame(width: 8, height: 8)
            Text(key.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            TextField("—", text: textBinding(for: key))
                .focused($focused, equals: .nutrient(key))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(maxWidth: 100)
            Text(key.unit)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private var saltRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.clear)
                .frame(width: 8, height: 8)
            Text("Sel")
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            TextField("—", text: $saltText)
                .focused($focused, equals: .salt)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text("g")
                .foregroundStyle(Theme.textSecondary)
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
