import SwiftData
import SwiftUI

private enum CustomFoodsSegment: String, CaseIterable, Identifiable {
    case foods, recipes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .foods: "Aliments"
        case .recipes: "Recettes"
        }
    }
}

private enum CustomFoodsSheet: Identifiable {
    case newFood
    case newRecipe
    case edit(CustomFood)
    case log(FoodItem)

    var id: String {
        switch self {
        case .newFood: "new-food"
        case .newRecipe: "new-recipe"
        case .edit(let food): "edit-\(food.id.uuidString)"
        case .log(let item): "log-\(item.id)"
        }
    }
}

/// "Mes aliments & recettes": user-created foods and recipes. Pushed view (no NavigationStack).
/// When `pickContext` is non-nil, tapping an item logs it (AddEntrySheet) and a pencil edits it.
struct CustomFoodsListView: View {
    let pickContext: LogContext?
    /// Called after the log sheet closed following a successful log (picking mode).
    let onLogged: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomFood.createdAt, order: .reverse) private var allFoods: [CustomFood]

    @State private var segment: CustomFoodsSegment = .foods
    @State private var searchText = ""
    @State private var sheet: CustomFoodsSheet?
    @State private var loggedTick = 0
    @State private var deleteTick = 0
    @State private var didLog = false

    init(pickContext: LogContext?, onLogged: (() -> Void)? = nil) {
        self.pickContext = pickContext
        self.onLogged = onLogged
    }

    private var isPicking: Bool { pickContext != nil }

    private var segmentFoods: [CustomFood] {
        allFoods
            .filter { segment == .recipes ? $0.isRecipe : !$0.isRecipe }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredFoods: [CustomFood] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return segmentFoods }
        return segmentFoods.filter { CustomFoodsText.matches(query, name: $0.name, brand: $0.brand) }
    }

    var body: some View {
        let foods = filteredFoods
        List {
            Section {
                Picker("Type", selection: $segment) {
                    ForEach(CustomFoodsSegment.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if foods.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(foods) { food in
                        row(for: food)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(food)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if isPicking {
                                    Button {
                                        sheet = .edit(food)
                                    } label: {
                                        Label("Modifier", systemImage: "pencil")
                                    }
                                    .tint(Theme.accent)
                                }
                            }
                            .contextMenu {
                                contextMenu(for: food)
                            }
                    }
                } header: {
                    Text(countLabel(foods.count))
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    if let pickContext {
                        Text("Touchez un élément pour l'ajouter à « \(pickContext.meal.label) ». Le crayon permet de le modifier.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedBackground()
        .navigationTitle("Mes aliments")
        .searchable(text: $searchText, prompt: segment == .recipes ? "Rechercher une recette" : "Rechercher un aliment")
        .autocorrectionDisabled()
        .animation(.default, value: segment)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        sheet = .newFood
                    } label: {
                        Label("Nouvel aliment", systemImage: "carrot")
                    }
                    Button {
                        sheet = .newRecipe
                    } label: {
                        Label("Nouvelle recette", systemImage: "frying.pan")
                    }
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheet, onDismiss: {
            if didLog {
                didLog = false
                onLogged?()
            }
        }) { item in
            sheetContent(item)
        }
        .sensoryFeedback(.success, trigger: loggedTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteTick)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for food: CustomFood) -> some View {
        if isPicking {
            HStack(spacing: 8) {
                Button {
                    sheet = .log(food.item)
                } label: {
                    CustomFoodsListRow(food: food)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Button {
                    sheet = .edit(food)
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Modifier")
            }
        } else {
            Button {
                sheet = .edit(food)
            } label: {
                CustomFoodsListRow(food: food)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func contextMenu(for food: CustomFood) -> some View {
        if isPicking {
            Button {
                sheet = .log(food.item)
            } label: {
                Label("Ajouter au journal", systemImage: "plus.circle")
            }
        }
        Button {
            sheet = .edit(food)
        } label: {
            Label("Modifier", systemImage: "pencil")
        }
        Button {
            duplicate(food)
        } label: {
            Label("Dupliquer", systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive) {
            delete(food)
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if segment == .recipes {
            ContentUnavailableView {
                Label("Aucune recette", systemImage: "frying.pan")
            } description: {
                Text("Composez vos plats à partir d'ingrédients pour les ajouter en une fois au journal.")
            } actions: {
                Button("Nouvelle recette") { sheet = .newRecipe }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        } else {
            ContentUnavailableView {
                Label("Aucun aliment", systemImage: "carrot")
            } description: {
                Text("Créez vos propres aliments à partir de leur étiquette nutritionnelle.")
            } actions: {
                Button("Nouvel aliment") { sheet = .newFood }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }

    private func countLabel(_ count: Int) -> String {
        switch segment {
        case .foods: count == 1 ? "1 aliment" : "\(count) aliments"
        case .recipes: count == 1 ? "1 recette" : "\(count) recettes"
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ item: CustomFoodsSheet) -> some View {
        switch item {
        case .newFood:
            CustomFoodEditor(food: nil)
        case .newRecipe:
            RecipeEditor(recipe: nil)
        case .edit(let food):
            if food.isRecipe {
                RecipeEditor(recipe: food)
            } else {
                CustomFoodEditor(food: food)
            }
        case .log(let foodItem):
            AddEntrySheet(item: foodItem, context: pickContext ?? LogContext.now, onLogged: {
                loggedTick += 1
                didLog = true
            })
        }
    }

    // MARK: - Actions

    private func delete(_ food: CustomFood) {
        withAnimation {
            modelContext.delete(food)
            try? modelContext.save()
        }
        deleteTick += 1
    }

    private func duplicate(_ food: CustomFood) {
        let copy = CustomFood(name: "\(food.name) (copie)", brand: food.brand, per100: food.per100)
        copy.ean = nil
        copy.isLiquid = food.isLiquid
        copy.servingLabel = food.servingLabel
        copy.servingGrams = food.servingGrams
        copy.ingredientsData = food.ingredientsData
        copy.totalGrams = food.totalGrams
        withAnimation {
            modelContext.insert(copy)
            try? modelContext.save()
        }
    }
}

// MARK: - Row

private struct CustomFoodsListRow: View {
    let food: CustomFood

    private var unit: String { food.isLiquid ? "ml" : "g" }

    private var servingGrams: Double? {
        guard let grams = food.servingGrams, grams > 0 else { return nil }
        return grams
    }

    /// Values for one serving when known, else per 100 g.
    private var shownValues: NutrientValues {
        if let servingGrams { return food.per100.forGrams(servingGrams) }
        return food.per100
    }

    private var subtitle: String {
        var parts: [String] = []
        if let brand = food.brand, !brand.isEmpty { parts.append(brand) }
        if food.isRecipe {
            let count = food.ingredients.count
            parts.append(count == 1 ? "1 ingrédient" : "\(count) ingrédients")
        }
        if let servingGrams {
            let label = food.servingLabel ?? "1 portion"
            parts.append("\(label) (\(Formatters.number(servingGrams, maxFractionDigits: 0)) \(unit))")
        } else {
            parts.append("pour 100 \(unit)")
        }
        return parts.joined(separator: " · ")
    }

    private var iconName: String {
        if food.isRecipe { return "frying.pan" }
        return food.isLiquid ? "drop" : "carrot"
    }

    var body: some View {
        let values = shownValues
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    macroDot("P", values.protein, color: Theme.protein)
                    macroDot("G", values.carbs, color: Theme.carbs)
                    macroDot("L", values.fat, color: Theme.fat)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Formatters.number(values.calories, maxFractionDigits: 0))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func macroDot(_ letter: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(letter) \(Formatters.number(value, maxFractionDigits: value < 10 ? 1 : 0)) g")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
