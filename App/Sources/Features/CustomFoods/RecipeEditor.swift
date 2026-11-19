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
                ingredientsSection
                weightSection
                if !ingredients.isEmpty {
                    totalsSection
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Supprimer la recette", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                Section {
                    AttributionFooter()
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle(isEditing ? "Modifier la recette" : "Nouvelle recette")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty && ingredients.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focused = nil }
                }
            }
            .sheet(isPresented: $showPicker) {
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
            HStack {
                Text("Nombre de portions")
                Spacer()
                TextField("1", text: $servingsText)
                    .focused($focused, equals: .servings)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 60)
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
        } header: {
            Text("Recette")
        } footer: {
            if showValidation && trimmedName.isEmpty {
                Text("Le nom est obligatoire.").foregroundStyle(.red)
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            if ingredients.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "basket")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Aucun ingrédient")
                        .font(.subheadline.weight(.medium))
                    Text("Ajoutez les ingrédients et leur quantité crue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Label("Ajouter un ingrédient", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text("Ingrédients")
                Spacer()
                if !ingredients.isEmpty {
                    Text("\(Formatters.number(rawGrams, maxFractionDigits: 0)) g")
                }
            }
        } footer: {
            if showValidation && ingredients.isEmpty {
                Text("Ajoutez au moins un ingrédient.").foregroundStyle(.red)
            } else if !ingredients.isEmpty {
                Text("Touchez un ingrédient pour modifier sa quantité, balayez pour le supprimer.")
            }
        }
    }

    private var weightSection: some View {
        Section {
            HStack {
                Text("Poids total cuit")
                Spacer()
                TextField(Formatters.number(rawGrams, maxFractionDigits: 0), text: $cookedWeightText)
                    .focused($focused, equals: .cookedWeight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
                Text("g")
                    .foregroundStyle(.secondary)
            }
            if cookedWeight != nil {
                Button("Utiliser la somme des ingrédients") {
                    cookedWeightText = ""
                }
            }
        } header: {
            Text("Cuisson")
        } footer: {
            Text("Facultatif. La cuisson fait varier le poids (évaporation, absorption d'eau) : pesez le plat fini pour des valeurs pour 100 g exactes. Par défaut : somme des ingrédients.")
        }
    }

    private var totalsSection: some View {
        let sum = totals
        let total = totalGrams
        let perServingGrams = total / servings
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Par portion · \(CustomFoodsText.nilIfBlank(servingLabel) ?? "1 portion") (\(Formatters.number(perServingGrams, maxFractionDigits: 0)) g)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CustomFoodsMacroSummary(values: sum.scaled(by: 1 / servings))
            }
            if total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pour 100 g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CustomFoodsMacroSummary(values: sum.scaled(by: 100 / total))
                }
            }
            LabeledContent("Recette entière") {
                Text("\(Formatters.kcal(sum.calories)) · \(Formatters.number(total, maxFractionDigits: 0)) g")
                    .monospacedDigit()
            }
        } header: {
            Text("Valeurs nutritionnelles")
        }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(Formatters.number(ingredient.grams, maxFractionDigits: 1)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Formatters.kcal(values.calories))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
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
                    Section(trimmedQuery.isEmpty ? "Mes aliments & recettes" : "Mes aliments") {
                        ForEach(custom) { item in
                            resultButton(item)
                        }
                    }
                }

                if !trimmedQuery.isEmpty {
                    if !FoodDatabase.shared.isAvailable {
                        Section {
                            Label(FoodDatabase.shared.openError ?? "Base d'aliments indisponible.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    } else if !results.isEmpty {
                        Section("OpenNutrition") {
                            ForEach(results) { item in
                                resultButton(item)
                            }
                        }
                    } else if !isSearching && custom.isEmpty {
                        ContentUnavailableView.search(text: trimmedQuery)
                            .listRowBackground(Color.clear)
                    }
                } else if custom.isEmpty {
                    ContentUnavailableView(
                        "Rechercher un ingrédient",
                        systemImage: "magnifyingglass",
                        description: Text("Tapez le nom d'un aliment, par exemple « riz basmati » ou « poulet ».")
                    )
                    .listRowBackground(Color.clear)
                }

                Section {
                    AttributionFooter()
                }
                .listRowBackground(Color.clear)
            }
            .overlay(alignment: .top) {
                if isSearching && results.isEmpty {
                    ProgressView()
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
        HStack(spacing: 12) {
            Image(systemName: item.source == .custom ? "person.crop.circle" : (item.kind?.systemImage ?? "leaf"))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Formatters.number(item.per100.calories, maxFractionDigits: 0))
                    .font(.callout.weight(.semibold).monospacedDigit())
                Text("kcal/100 \(item.unitSymbol)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
                    .font(.headline)
                HStack {
                    Text("Quantité")
                    Spacer()
                    TextField("100", text: $gramsText)
                        .focused($fieldFocused)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                    Text(unitSymbol)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Button(chip.label) {
                                gramsText = CustomFoodsNumber.text(chip.grams, maxFractionDigits: 1)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Quantité crue / telle qu'utilisée dans la recette.")
            }

            Section("Apport") {
                CustomFoodsMacroSummary(values: per100.forGrams(grams ?? 0))
            }

            Section {
                Button {
                    confirm()
                } label: {
                    Text(confirmTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(grams == nil)
            }
        }
        .navigationTitle("Quantité")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { confirm() }
                    .fontWeight(.semibold)
                    .disabled(grams == nil)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private func confirm() {
        guard let grams else { return }
        onConfirm(grams)
    }
}
