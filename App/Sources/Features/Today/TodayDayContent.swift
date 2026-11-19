import SwiftData
import SwiftUI

/// Daily targets read from the profile, with sensible defaults when no profile exists yet.
struct TodayTargets {
    var calories: Double = 2000
    var protein: Double = 120
    var carbs: Double = 220
    var fat: Double = 70
    var fiber: Double = 30
    var water: Double = 2000

    init(profile: UserProfile?) {
        guard let profile else { return }
        calories = profile.calorieTarget
        protein = profile.proteinTarget
        carbs = profile.carbsTarget
        fat = profile.fatTarget
        fiber = profile.fiberTarget
        water = profile.waterTargetMl
    }
}

/// Sheet destination. The id is captured at creation so it never reads a model that may
/// have been deleted while the sheet was open.
private struct TodaySheet: Identifiable {
    enum Kind {
        case search(LogContext)
        case quickAdd(LogContext)
        case edit(JournalEntry)
    }

    let id: String
    let kind: Kind

    static func search(_ context: LogContext) -> TodaySheet {
        TodaySheet(id: "search-\(context.meal.rawValue)-\(context.day.timeIntervalSince1970)", kind: .search(context))
    }

    static func quickAdd(_ context: LogContext) -> TodaySheet {
        TodaySheet(id: "quick-\(context.meal.rawValue)-\(context.day.timeIntervalSince1970)", kind: .quickAdd(context))
    }

    static func edit(_ entry: JournalEntry) -> TodaySheet {
        TodaySheet(id: "edit-\(entry.id.uuidString)", kind: .edit(entry))
    }
}

/// Content of one journal day. The queries are built from `day` in the initializer,
/// so a new day re-creates them.
struct TodayDayContent: View {
    let day: Date

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query private var entries: [JournalEntry]
    @Query private var waterEntries: [WaterEntry]
    @Query private var profiles: [UserProfile]

    @State private var sheet: TodaySheet?
    @State private var mealToClear: Meal?
    @State private var showClearDialog = false
    @State private var recipeMeal: Meal?
    @State private var recipeName = ""
    @State private var showRecipeAlert = false
    @State private var toast: String?
    @State private var successTick = 0
    @State private var impactTick = 0

    init(day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        let end = start.adding(days: 1)
        self.day = start
        _entries = Query(
            filter: #Predicate<JournalEntry> { entry in
                entry.day >= start && entry.day < end
            },
            sort: \JournalEntry.createdAt
        )
        _waterEntries = Query(
            filter: #Predicate<WaterEntry> { water in
                water.day >= start && water.day < end
            },
            sort: \WaterEntry.createdAt
        )
        _profiles = Query(sort: \UserProfile.createdAt)
    }

    private var targets: TodayTargets { TodayTargets(profile: profiles.first) }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        let totals = NutrientValues.sum(entries.map(\.nutrients))
        let byMeal = Dictionary(grouping: entries, by: \.mealRaw)
        let currentTargets = targets

        List {
            Section {
                TodaySummaryCard(totals: totals, targets: currentTargets, isEmpty: entries.isEmpty)
                    .contentShape(Rectangle())
                    .simultaneousGesture(daySwipe)
            }

            Section {
                TodayWaterCard(
                    totalMl: waterEntries.reduce(0) { $0 + $1.ml },
                    targetMl: currentTargets.water,
                    canUndo: !waterEntries.isEmpty,
                    onAdd: addWater,
                    onUndo: undoWater
                )
            }

            ForEach(Meal.allCases) { meal in
                mealSection(meal, entries: byMeal[meal.rawValue] ?? [])
            }

            Section {
                NavigationLink {
                    TodayNutrientsView(day: day, totals: totals, targets: currentTargets, entryCount: entries.count)
                } label: {
                    Label("Nutriments du jour", systemImage: "chart.bar.doc.horizontal")
                }
            } footer: {
                AttributionFooter(includeOpenFoodFacts: entries.contains { $0.sourceRaw == FoodSource.openFoodFacts.rawValue })
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addMenu
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination.kind {
            case .search(let context):
                NavigationStack {
                    FoodSearchView(context: context, isSheet: true)
                }
            case .quickAdd(let context):
                QuickAddSheet(context: context)
            case .edit(let entry):
                AddEntrySheet(editing: entry)
            }
        }
        .confirmationDialog(
            "Supprimer tous les aliments de ce repas ?",
            isPresented: $showClearDialog,
            titleVisibility: .visible,
            presenting: mealToClear
        ) { meal in
            Button("Tout supprimer (\(meal.label))", role: .destructive) {
                clear(meal)
            }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Enregistrer comme recette", isPresented: $showRecipeAlert) {
            TextField("Nom de la recette", text: $recipeName)
            Button("Annuler", role: .cancel) { recipeMeal = nil }
            Button("Enregistrer") {
                if let meal = recipeMeal { saveRecipe(from: meal, name: recipeName) }
                recipeMeal = nil
            }
        } message: {
            Text("Les aliments de ce repas seront regroupés en une recette réutilisable dans « Mes aliments ».")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { withAnimation(.snappy) { self.toast = nil } }
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { toast = nil }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.impact(weight: .light), trigger: impactTick)
    }

    // MARK: - Toolbar

    private var addMenu: some View {
        Menu {
            Section("Ajouter à…") {
                ForEach(Meal.allCases) { meal in
                    Button {
                        sheet = .search(LogContext(day: day, meal: meal))
                    } label: {
                        Label(meal.label, systemImage: meal.systemImage)
                    }
                }
            }
            Button {
                sheet = .quickAdd(LogContext(day: day, meal: Meal.suggested()))
            } label: {
                Label("Ajout rapide", systemImage: "bolt")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("Ajouter un aliment")
        } primaryAction: {
            sheet = .search(LogContext(day: day, meal: Meal.suggested()))
        }
    }

    // MARK: - Swipe between days

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                shiftDay(dx < 0 ? 1 : -1)
            }
    }

    private func shiftDay(_ delta: Int) {
        withAnimation(.snappy) {
            appState.selectedDay = day.adding(days: delta).startOfDay
        }
    }

    // MARK: - Meal sections

    private func mealSection(_ meal: Meal, entries mealEntries: [JournalEntry]) -> some View {
        Section {
            ForEach(mealEntries, id: \.persistentModelID) { entry in
                entryRow(entry, meal: meal)
            }
            Button {
                sheet = .search(LogContext(day: day, meal: meal))
            } label: {
                Label(mealEntries.isEmpty ? "Ajouter un aliment" : "Ajouter", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            mealHeader(meal, entries: mealEntries)
        }
    }

    private func mealHeader(_ meal: Meal, entries mealEntries: [JournalEntry]) -> some View {
        let values = NutrientValues.sum(mealEntries.map(\.nutrients))
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: meal.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(meal.label)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if !mealEntries.isEmpty {
                Text(Formatters.kcal(values.calories))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            mealMenu(meal, isEmpty: mealEntries.isEmpty)
        }
        .textCase(nil)
        .padding(.top, 4)
    }

    private func mealMenu(_ meal: Meal, isEmpty: Bool) -> some View {
        Menu {
            Button {
                sheet = .search(LogContext(day: day, meal: meal))
            } label: {
                Label("Ajouter un aliment", systemImage: "magnifyingglass")
            }
            Button {
                sheet = .quickAdd(LogContext(day: day, meal: meal))
            } label: {
                Label("Ajout rapide", systemImage: "bolt")
            }
            Button {
                copyFromPreviousDay(meal)
            } label: {
                Label(isToday ? "Copier depuis hier" : "Copier depuis la veille",
                      systemImage: "arrow.uturn.backward.circle")
            }
            Button {
                recipeMeal = meal
                recipeName = "\(meal.label) du \(Formatters.shortDate(day))"
                showRecipeAlert = true
            } label: {
                Label("Enregistrer comme recette", systemImage: "book")
            }
            .disabled(isEmpty)
            Divider()
            Button(role: .destructive) {
                mealToClear = meal
                showClearDialog = true
            } label: {
                Label("Tout supprimer", systemImage: "trash")
            }
            .disabled(isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
                .accessibilityLabel("Options du repas \(meal.label)")
        }
    }

    private func entryRow(_ entry: JournalEntry, meal: Meal) -> some View {
        Button {
            sheet = .edit(entry)
        } label: {
            TodayEntryRow(entry: entry)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                duplicate(entry, to: day)
            } label: {
                Label("Dupliquer", systemImage: "plus.square.on.square")
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            Button {
                sheet = .edit(entry)
            } label: {
                Label("Modifier", systemImage: "pencil")
            }
            Button {
                duplicate(entry, to: day)
            } label: {
                Label("Dupliquer", systemImage: "plus.square.on.square")
            }
            if !isToday {
                Button {
                    duplicate(entry, to: Date.now.startOfDay)
                    showToast("Ajouté à aujourd'hui")
                } label: {
                    Label("Copier vers aujourd'hui", systemImage: "calendar.badge.plus")
                }
            }
            Menu {
                ForEach(Meal.allCases.filter { $0 != meal }) { target in
                    Button {
                        move(entry, to: target)
                    } label: {
                        Label(target.label, systemImage: target.systemImage)
                    }
                }
            } label: {
                Label("Déplacer vers", systemImage: "arrow.right.circle")
            }
            Divider()
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func delete(_ entry: JournalEntry) {
        withAnimation {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        impactTick += 1
    }

    private func duplicate(_ entry: JournalEntry, to targetDay: Date) {
        let copy = JournalEntry(item: entry.item, grams: entry.grams, day: targetDay, meal: entry.meal)
        withAnimation {
            modelContext.insert(copy)
            try? modelContext.save()
        }
        successTick += 1
    }

    private func move(_ entry: JournalEntry, to meal: Meal) {
        withAnimation {
            entry.meal = meal
            try? modelContext.save()
        }
        impactTick += 1
    }

    private func clear(_ meal: Meal) {
        let raw = meal.rawValue
        withAnimation {
            for entry in entries where entry.mealRaw == raw {
                modelContext.delete(entry)
            }
            try? modelContext.save()
        }
        mealToClear = nil
        impactTick += 1
    }

    private func copyFromPreviousDay(_ meal: Meal) {
        let start = day.adding(days: -1).startOfDay
        let end = day
        let raw = meal.rawValue
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> { entry in
                entry.day >= start && entry.day < end && entry.mealRaw == raw
            },
            sortBy: [SortDescriptor(\JournalEntry.createdAt)]
        )
        let previous = (try? modelContext.fetch(descriptor)) ?? []
        guard !previous.isEmpty else {
            showToast("Aucun aliment pour « \(meal.label) » la veille")
            return
        }
        withAnimation {
            for entry in previous {
                modelContext.insert(JournalEntry(item: entry.item, grams: entry.grams, day: day, meal: meal))
            }
            try? modelContext.save()
        }
        successTick += 1
        showToast(previous.count == 1 ? "1 aliment copié" : "\(previous.count) aliments copiés")
    }

    private func saveRecipe(from meal: Meal, name: String) {
        let raw = meal.rawValue
        let mealEntries = entries.filter { $0.mealRaw == raw }
        let ingredients = mealEntries.map {
            RecipeIngredient(name: $0.name, grams: $0.grams, per100: $0.per100)
        }
        let totalGrams = ingredients.reduce(0) { $0 + $1.grams }
        guard !ingredients.isEmpty, totalGrams > 0 else { return }
        let sum = NutrientValues.sum(mealEntries.map(\.nutrients))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "\(meal.label) du \(Formatters.shortDate(day))" : trimmed

        let recipe = CustomFood(name: finalName, per100: sum.scaled(by: 100 / totalGrams))
        recipe.ingredients = ingredients
        recipe.totalGrams = totalGrams
        recipe.servingGrams = totalGrams
        recipe.servingLabel = "1 portion"
        modelContext.insert(recipe)
        try? modelContext.save()
        successTick += 1
        showToast("Recette « \(finalName) » enregistrée")
    }

    private func addWater(_ ml: Double) {
        withAnimation(.snappy) {
            modelContext.insert(WaterEntry(day: day, ml: ml))
            try? modelContext.save()
        }
        impactTick += 1
    }

    private func undoWater() {
        guard let last = waterEntries.last else { return }
        withAnimation(.snappy) {
            modelContext.delete(last)
            try? modelContext.save()
        }
        impactTick += 1
    }

    private func showToast(_ message: String) {
        withAnimation(.snappy) { toast = message }
    }
}
