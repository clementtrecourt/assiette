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
                segmentChips
            }
            .listRowBackground(Theme.background)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            if foods.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
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
                                    .tint(Theme.textTertiary)
                                }
                            }
                            .contextMenu {
                                contextMenu(for: food)
                            }
                    }
                } header: {
                    CustomFoodsSectionHeader(countLabel(foods.count))
                } footer: {
                    if let pickContext {
                        CustomFoodsFooterText("Touchez un élément pour l'ajouter à « \(pickContext.meal.label) ». Le crayon permet de le modifier.")
                    }
                }
                .customFoodsRow()
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .tint(Theme.textPrimary)
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
        .slideCover(item: $sheet, onDismiss: {
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
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textBody)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline))
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
            ThemedUnavailableView.search(text: query)
        } else if segment == .recipes {
            ContentUnavailableView {
                emptyTitle("Aucune recette", systemImage: "frying.pan")
            } description: {
                emptyDescription("Composez vos plats à partir d'ingrédients pour les ajouter en une fois au journal.")
            } actions: {
                Button("Nouvelle recette") { sheet = .newRecipe }
                    .buttonStyle(CustomFoodsCompactButtonStyle())
            }
        } else {
            ContentUnavailableView {
                emptyTitle("Aucun aliment", systemImage: "carrot")
            } description: {
                emptyDescription("Créez vos propres aliments à partir de leur étiquette nutritionnelle.")
            } actions: {
                Button("Nouvel aliment") { sheet = .newFood }
                    .buttonStyle(CustomFoodsCompactButtonStyle())
            }
        }
    }

    private var segmentChips: some View {
        HStack(spacing: 6) {
            ForEach(CustomFoodsSegment.allCases) { item in
                CustomFoodsChip(title: item.label, isSelected: segment == item) {
                    segment = item
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func emptyTitle(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func emptyDescription(_ text: String) -> some View {
        Text(text)
            .font(Theme.callout)
            .foregroundStyle(Theme.textSecondary)
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

    var body: some View {
        let values = shownValues
        HStack(spacing: 12) {
            FoodIconView(item: food.item, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    KcalLabel(kcal: values.calories, color: Theme.textBody)
                    Text("·")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textQuaternary)
                    Text(subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 9) {
                    macroValue("P", values.protein, color: Theme.protein)
                    macroValue("G", values.carbs, color: Theme.carbs)
                    macroValue("L", values.fat, color: Theme.fat)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private func macroValue(_ letter: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(letter)
                .font(Theme.font(11, .bold, relativeTo: .caption2))
                .foregroundStyle(color)
            Text("\(Formatters.number(value, maxFractionDigits: value < 10 ? 1 : 0)) g")
                .font(Theme.font(11, .regular, relativeTo: .caption2))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
