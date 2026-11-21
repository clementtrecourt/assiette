import SwiftData
import SwiftUI
import UIKit

private enum RecipeEditorField: Hashable {
    case name, servings, servingLabel, cookedWeight
}

/// Create or edit a recipe (a `CustomFood` with ingredients). Own NavigationStack.
struct RecipeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let recipe: CustomFood?

    @State private var name: String
    @State private var servingsText: String
    @State private var servingLabel: String
    @State private var cookedWeightText: String
    @State private var ingredients: [RecipeIngredient]
    @State private var showPicker = false
    @State private var editingIngredient: RecipeIngredient?
    @State private var showDeleteConfirm = false
    @State private var showValidation = false
    @State private var addedTick = 0
    @FocusState private var focused: RecipeEditorField?

    init(recipe: CustomFood?) {
        self.recipe = recipe
        if let recipe {
            let items = recipe.ingredients
            let raw = items.reduce(0) { $0 + $1.grams }
            let total = recipe.totalGrams ?? raw
            var servings = 1.0
            if let serving = recipe.servingGrams, serving > 0, total > 0 {
                servings = max(1, (total / serving * 10).rounded() / 10)
            }
            _name = State(initialValue: recipe.name)
            _servingsText = State(initialValue: CustomFoodsNumber.text(servings, maxFractionDigits: 1))
            _servingLabel = State(initialValue: recipe.servingLabel ?? "1 portion")
            let cookedDiffers = recipe.totalGrams.map { abs($0 - raw) > 0.5 } ?? false
            _cookedWeightText = State(initialValue: cookedDiffers ? CustomFoodsNumber.text(total, maxFractionDigits: 0) : "")
            _ingredients = State(initialValue: items)
        } else {
            _name = State(initialValue: "")
            _servingsText = State(initialValue: "1")
            _servingLabel = State(initialValue: "1 portion")
            _cookedWeightText = State(initialValue: "")
            _ingredients = State(initialValue: [])
        }
    }

    // MARK: - Derived

    private var isEditing: Bool { recipe != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var rawGrams: Double { ingredients.reduce(0) { $0 + $1.grams } }

    private var cookedWeight: Double? {
        guard let v = CustomFoodsNumber.parse(cookedWeightText), v > 0 else { return nil }
        return v
    }

    private var totalGrams: Double { cookedWeight ?? rawGrams }

    private var servings: Double {
        guard let v = CustomFoodsNumber.parse(servingsText), v > 0 else { return 1 }
        return v
    }

    private var totals: NutrientValues {
        NutrientValues.sum(ingredients.map { $0.per100.forGrams($0.grams) })
    }

    private var canSave: Bool { !trimmedName.isEmpty && !ingredients.isEmpty && totalGrams > 0 }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                infoSection
                    .customFoodsRow()
                ingredientsSection
                    .customFoodsRow()
                weightSection
                    .customFoodsRow()
                if !ingredients.isEmpty {
                    totalsSection
                        .customFoodsRow()
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Supprimer la recette", systemImage: "trash")
                                .font(Theme.headline)
                                .foregroundStyle(Theme.overTarget)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .customFoodsRow()
                }
                Section {
                    AttributionFooter()
                }
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
            }
            .themedBackground()
            .tint(Theme.textPrimary)
            .font(Theme.body)
            .navigationTitle(isEditing ? "Modifier la recette" : "Nouvelle recette")
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
                        .disabled(trimmedName.isEmpty && ingredients.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focused = nil }
                }
            }
            .slideCover(isPresented: $showPicker) {
                RecipeIngredientPicker(excludedID: recipe?.id) { ingredient in
                    withAnimation { ingredients.append(ingredient) }
                    addedTick += 1
                }
            }
            .sheet(item: $editingIngredient) { ingredient in
                NavigationStack {
                    RecipeIngredientAmountView(
                        name: ingredient.name,
                        per100: ingredient.per100,
                        servingGrams: nil,
                        servingLabel: nil,
                        unitSymbol: "g",
                        initialGrams: ingredient.grams,
                        confirmTitle: "Enregistrer",
                        showsCancel: true
                    ) { grams in
                        if let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) {
                            ingredients[index].grams = grams
                        }
                        editingIngredient = nil
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sensoryFeedback(.success, trigger: addedTick)
            .confirmationDialog("Supprimer cette recette ?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { deleteRecipe() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les entrées déjà enregistrées dans le journal sont conservées.")
            }
        }
    }

    // MARK: - Sections

    private var infoSection: some View {
        Section {
            TextField("Nom de la recette (obligatoire)", text: $name)
                .focused($focused, equals: .name)
                .textInputAutocapitalization(.sentences)
                .customFoodsInputField(minHeight: 40)
                .padding(.vertical, 4)
            HStack(spacing: 8) {
                Text("Nombre de portions")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textBody)
                Spacer()
                TextField("1", text: $servingsText)
                    .focused($focused, equals: .servings)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .customFoodsInputField(minHeight: 34)
                    .frame(maxWidth: 64)
                Stepper("Nombre de portions", onIncrement: {
                    servingsText = CustomFoodsNumber.text((servings + 1).rounded(.down), maxFractionDigits: 1)
                }, onDecrement: {
                    let next = max(1, (servings - 1).rounded(.up))
                    servingsText = CustomFoodsNumber.text(next, maxFractionDigits: 1)
                })
                .labelsHidden()
            }
            TextField("Libellé d'une portion (ex. 1 part, 1 bol)", text: $servingLabel)
                .focused($focused, equals: .servingLabel)
                .customFoodsInputField(minHeight: 40)
                .padding(.vertical, 4)
        } header: {
            CustomFoodsSectionHeader("Recette")
        } footer: {
            if showValidation && trimmedName.isEmpty {
                CustomFoodsFooterText("Le nom est obligatoire.", color: Theme.overTarget)
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            if ingredients.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "basket")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Aucun ingrédient")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Ajoutez les ingrédients et leur quantité crue.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(ingredients) { ingredient in
                    Button {
                        editingIngredient = ingredient
                    } label: {
                        RecipeIngredientRow(ingredient: ingredient)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    withAnimation { ingredients.remove(atOffsets: offsets) }
                }
                .onMove { source, destination in
                    ingredients.move(fromOffsets: source, toOffset: destination)
                }
            }
            Button {
                focused = nil
                showPicker = true
            } label: {
                CustomFoodsAddLabel(title: "Ajouter un ingrédient")
            }
            .buttonStyle(.plain)
        } header: {
            CustomFoodsSectionHeader(
                "Ingrédients",
                trailing: ingredients.isEmpty ? nil : "\(Formatters.number(rawGrams, maxFractionDigits: 0)) g"
            )
        } footer: {
            if showValidation && ingredients.isEmpty {
                CustomFoodsFooterText("Ajoutez au moins un ingrédient.", color: Theme.overTarget)
            } else if !ingredients.isEmpty {
                CustomFoodsFooterText("Touchez un ingrédient pour modifier sa quantité, balayez pour le supprimer.")
            }
        }
    }

    private var weightSection: some View {
        Section {
            HStack(spacing: 8) {
                Text("Poids total cuit")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textBody)
                Spacer()
                TextField(Formatters.number(rawGrams, maxFractionDigits: 0), text: $cookedWeightText)
                    .focused($focused, equals: .cookedWeight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .customFoodsInputField(minHeight: 34)
                    .frame(maxWidth: 110)
                Text("g")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
            if cookedWeight != nil {
                Button("Utiliser la somme des ingrédients") {
                    cookedWeightText = ""
                }
                .font(Theme.callout)
                .foregroundStyle(Theme.textPrimary)
            }
        } header: {
            CustomFoodsSectionHeader("Cuisson")
        } footer: {
            CustomFoodsFooterText("Facultatif. La cuisson fait varier le poids (évaporation, absorption d'eau) : pesez le plat fini pour des valeurs pour 100 g exactes. Par défaut : somme des ingrédients.")
        }
    }

    private var totalsSection: some View {
        let sum = totals
        let total = totalGrams
        let perServingGrams = total / servings
        return Section {
            summaryBlock(
                "Par portion · \(CustomFoodsText.nilIfBlank(servingLabel) ?? "1 portion") (\(Formatters.number(perServingGrams, maxFractionDigits: 0)) g)",
                values: sum.scaled(by: 1 / servings)
            )
            if total > 0 {
                summaryBlock("Pour 100 g", values: sum.scaled(by: 100 / total))
            }
            HStack {
                Text("Recette entière")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                KcalLabel(kcal: sum.calories, font: Theme.font(14, .medium, relativeTo: .callout), color: Theme.textPrimary)
                Text("· \(Formatters.number(total, maxFractionDigits: 0)) g")
                    .font(Theme.callout)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        } header: {
            CustomFoodsSectionHeader("Valeurs nutritionnelles")
        }
    }

    /// Caption line + 4-column summary, edge to edge between hairlines.
    private func summaryBlock(_ title: String, values: NutrientValues) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            CustomFoodsMacroSummary(values: values)
                .padding(.horizontal, -8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func save() {
        guard canSave else {
            showValidation = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let total = totalGrams
        let per100 = totals.scaled(by: 100 / total)
        let target: CustomFood
        if let recipe {
            target = recipe
            target.name = trimmedName
            target.per100 = per100
        } else {
            target = CustomFood(name: trimmedName, per100: per100)
            modelContext.insert(target)
        }
        target.ingredients = ingredients
        target.totalGrams = total
        target.servingGrams = total / servings
        target.servingLabel = CustomFoodsText.nilIfBlank(servingLabel) ?? "1 portion"
        target.isLiquid = false
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deleteRecipe() {
        guard let recipe else { return }
        modelContext.delete(recipe)
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        dismiss()
    }
}

// MARK: - Ingredient row

private struct RecipeIngredientRow: View {
    let ingredient: RecipeIngredient

    var body: some View {
        let values = ingredient.per100.forGrams(ingredient.grams)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(2)
                HStack(spacing: 9) {
                    Text("\(Formatters.number(ingredient.grams, maxFractionDigits: 1)) g")
                        .foregroundStyle(Theme.textTertiary)
                    macroValue("P", values.protein, Theme.protein)
                    macroValue("G", values.carbs, Theme.carbs)
                    macroValue("L", values.fat, Theme.fat)
                }
                .font(Theme.caption)
                .monospacedDigit()
            }
            Spacer(minLength: 8)
            KcalLabel(kcal: values.calories, font: Theme.font(14, .medium, relativeTo: .callout), color: Theme.textBody)
        }
        .padding(.vertical, 2)
    }

    private func macroValue(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text(letter)
                .font(Theme.font(12, .bold, relativeTo: .caption))
                .foregroundStyle(color)
            Text(Formatters.number(grams, maxFractionDigits: grams < 10 ? 1 : 0))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Ingredient picker (self-contained search sheet)

private struct RecipeIngredientPicker: View {
    let excludedID: UUID?
    let onAdd: (RecipeIngredient) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomFood.createdAt, order: .reverse) private var customFoods: [CustomFood]

    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false
    @State private var selected: FoodItem?

    init(excludedID: UUID?, onAdd: @escaping (RecipeIngredient) -> Void) {
        self.excludedID = excludedID
        self.onAdd = onAdd
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matchingCustom: [FoodItem] {
        let q = trimmedQuery
        let available = customFoods.filter { $0.id != excludedID }
        let filtered = q.isEmpty ? available : available.filter { CustomFoodsText.matches(q, name: $0.name, brand: $0.brand) }
        return filtered.prefix(q.isEmpty ? 30 : 10).map(\.item)
    }

    var body: some View {
        NavigationStack {
            List {
                let custom = matchingCustom
                if !custom.isEmpty {
                    Section {
                        ForEach(custom) { item in
                            resultButton(item)
                        }
                    } header: {
                        CustomFoodsSectionHeader(trimmedQuery.isEmpty ? "Mes aliments & recettes" : "Mes aliments")
                    }
                    .customFoodsRow()
                }

                if !trimmedQuery.isEmpty {
                    if !FoodDatabase.shared.isAvailable {
                        Section {
                            Label(FoodDatabase.shared.openError ?? "Base d'aliments indisponible.", systemImage: "exclamationmark.triangle")
                                .font(Theme.callout)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .customFoodsRow()
                    } else if !results.isEmpty {
                        Section {
                            ForEach(results) { item in
                                resultButton(item)
                            }
                        } header: {
                            CustomFoodsSectionHeader("OpenNutrition", trailing: results.count == 1 ? "1 résultat" : "\(results.count) résultats")
                        }
                        .customFoodsRow()
                    } else if !isSearching && custom.isEmpty {
                        ThemedUnavailableView.search(text: trimmedQuery)
                            .listRowBackground(Theme.background)
                            .listRowSeparator(.hidden)
                    }
                } else if custom.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("Rechercher un ingrédient")
                                .font(Theme.title)
                                .foregroundStyle(Theme.textPrimary)
                        } icon: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.textTertiary)
                        }
                    } description: {
                        Text("Tapez le nom d'un aliment, par exemple « riz basmati » ou « poulet ».")
                            .font(Theme.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
                }

                Section {
                    AttributionFooter()
                }
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .themedBackground()
            .tint(Theme.textPrimary)
            .overlay(alignment: .top) {
                if isSearching && results.isEmpty {
                    ProgressView()
                        .tint(Theme.textSecondary)
                        .padding(.top, 24)
                }
            }
            .navigationTitle("Ajouter un ingrédient")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Aliment, plat, marque…")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .task(id: trimmedQuery) {
                await runSearch(trimmedQuery)
            }
            .navigationDestination(item: $selected) { item in
                RecipeIngredientAmountView(
                    name: item.name,
                    per100: item.per100,
                    servingGrams: item.servingGrams,
                    servingLabel: item.servingLabel,
                    unitSymbol: item.unitSymbol,
                    initialGrams: item.servingGrams ?? 100,
                    confirmTitle: "Ajouter",
                    showsCancel: false
                ) { grams in
                    onAdd(RecipeIngredient(name: ingredientName(item), grams: grams, per100: item.per100))
                    dismiss()
                }
            }
        }
    }

    private func resultButton(_ item: FoodItem) -> some View {
        Button {
            selected = item
        } label: {
            RecipePickerRow(item: item)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func ingredientName(_ item: FoodItem) -> String {
        if let brand = item.brand, !brand.isEmpty, !item.name.localizedCaseInsensitiveContains(brand) {
            return "\(item.name) (\(brand))"
        }
        return item.name
    }

    private func runSearch(_ text: String) async {
        guard !text.isEmpty, FoodDatabase.shared.isAvailable else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        // Debounce: a newer query cancels this task.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let foods = await FoodDatabase.shared.searchAsync(text, limit: 40)
        guard !Task.isCancelled else { return }
        results = foods.map(\.item)
        isSearching = false
    }
}

private struct RecipePickerRow: View {
    let item: FoodItem

    private var subtitle: String {
        var parts: [String] = []
        if let brand = item.brand, !brand.isEmpty { parts.append(brand) }
        if item.source == .custom {
            parts.append(FoodSource.custom.label)
        } else if let kind = item.kind {
            parts.append(kind.label)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            FoodIconView(item: item, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(2)
                detailLine
            }
            Spacer(minLength: 8)
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline))
        }
        .padding(.vertical, 2)
    }

    private var detailLine: some View {
        HStack(spacing: 4) {
            KcalLabel(kcal: item.per100.calories, color: Theme.textBody)
            Text("/ 100 \(item.unitSymbol)")
                .foregroundStyle(Theme.textTertiary)
            if !subtitle.isEmpty {
                Text("·")
                    .foregroundStyle(Theme.textQuaternary)
                Text(subtitle)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .font(Theme.caption)
        .lineLimit(1)
    }
}

// MARK: - Amount entry

private struct RecipeAmountChip: Hashable, Identifiable {
    let label: String
    let grams: Double
    var id: String { "\(label)|\(grams)" }
}

private struct RecipeIngredientAmountView: View {
    let name: String
    let per100: NutrientValues
    let servingGrams: Double?
    let servingLabel: String?
    let unitSymbol: String
    let confirmTitle: String
    let showsCancel: Bool
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var gramsText: String
    @FocusState private var fieldFocused: Bool

    init(name: String, per100: NutrientValues, servingGrams: Double?, servingLabel: String?,
         unitSymbol: String, initialGrams: Double, confirmTitle: String, showsCancel: Bool,
         onConfirm: @escaping (Double) -> Void) {
        self.name = name
        self.per100 = per100
        self.servingGrams = servingGrams
        self.servingLabel = servingLabel
        self.unitSymbol = unitSymbol
        self.confirmTitle = confirmTitle
        self.showsCancel = showsCancel
        self.onConfirm = onConfirm
        _gramsText = State(initialValue: CustomFoodsNumber.text(initialGrams, maxFractionDigits: 1))
    }

    private var grams: Double? {
        guard let v = CustomFoodsNumber.parse(gramsText), v > 0 else { return nil }
        return v
    }

    private var chips: [RecipeAmountChip] {
        var out: [RecipeAmountChip] = []
        if let servingGrams, servingGrams > 0 {
            let label = servingLabel ?? "1 portion"
            out.append(RecipeAmountChip(label: label, grams: servingGrams))
        }
        for g in [50.0, 100, 150, 200, 250] {
            if let servingGrams, abs(servingGrams - g) < 0.001 { continue }
            out.append(RecipeAmountChip(label: "\(Formatters.number(g, maxFractionDigits: 0)) \(unitSymbol)", grams: g))
        }
        return out
    }

    var body: some View {
        Form {
            Section {
                Text(name)
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Text("Quantité")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textBody)
                    Spacer()
                    TextField("100", text: $gramsText)
                        .focused($fieldFocused)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .customFoodsInputField()
                        .frame(maxWidth: 110)
                    Text(unitSymbol)
                        .font(Theme.callout)
                        .foregroundStyle(Theme.textTertiary)
                }
                chipsRow
            } footer: {
                CustomFoodsFooterText("Quantité crue / telle qu'utilisée dans la recette.")
            }
            .customFoodsRow()

            Section {
                CustomFoodsMacroSummary(values: per100.forGrams(grams ?? 0))
                    .padding(.horizontal, -8)
            } header: {
                CustomFoodsSectionHeader("Apport")
            }
            .customFoodsRow()

            Section {
                Button {
                    confirm()
                } label: {
                    Text(confirmTitle)
                }
                .buttonStyle(CustomFoodsPrimaryButtonStyle())
                .disabled(grams == nil)
            }
            .listRowBackground(Theme.background)
            .listRowInsets(EdgeInsets())
        }
        .themedBackground()
        .tint(Theme.textPrimary)
        .navigationTitle("Quantité")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { confirm() }
                    .font(Theme.headline)
                    .disabled(grams == nil)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    CustomFoodsChip(title: chip.label, isSelected: isSelected(chip)) {
                        gramsText = CustomFoodsNumber.text(chip.grams, maxFractionDigits: 1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func isSelected(_ chip: RecipeAmountChip) -> Bool {
        guard let grams else { return false }
        return abs(grams - chip.grams) < 0.05
    }

    private func confirm() {
        guard let grams else { return }
        onConfirm(grams)
    }
}
