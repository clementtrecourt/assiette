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
        case scan(LogContext)
        case quickAdd(LogContext)
        case edit(JournalEntry)
        case detail(FoodItem, LogContext)
        case add(FoodItem, LogContext)
    }

    let id: String
    let kind: Kind

    static func search(_ context: LogContext) -> TodaySheet {
        TodaySheet(id: "search-\(context.meal.rawValue)-\(context.day.timeIntervalSince1970)", kind: .search(context))
    }

    static func scan(_ context: LogContext) -> TodaySheet {
        TodaySheet(id: "scan-\(context.meal.rawValue)-\(context.day.timeIntervalSince1970)", kind: .scan(context))
    }

    static func quickAdd(_ context: LogContext) -> TodaySheet {
        TodaySheet(id: "quick-\(context.meal.rawValue)-\(context.day.timeIntervalSince1970)", kind: .quickAdd(context))
    }

    static func edit(_ entry: JournalEntry) -> TodaySheet {
        TodaySheet(id: "edit-\(entry.id.uuidString)", kind: .edit(entry))
    }

    static func detail(_ item: FoodItem, _ context: LogContext) -> TodaySheet {
        TodaySheet(id: "detail-\(item.id)", kind: .detail(item, context))
    }

    static func add(_ item: FoodItem, _ context: LogContext) -> TodaySheet {
        TodaySheet(id: "add-\(item.id)", kind: .add(item, context))
    }
}

private extension View {
    /// Full-bleed, separator-less List row on the app background (hairlines are drawn by the rows).
    func todayListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowSeparatorTint(Theme.separator)
            .listRowBackground(Theme.background)
    }
}

/// Pinned macro header. Owns the "remaining ↔ consumed" toggle so tapping it re-renders only
/// the header, not the whole timeline list.
private struct TodayPinnedHeader: View {
    let totals: NutrientValues
    let targets: TodayTargets
    let onShiftDay: (Int) -> Void

    @AppStorage("today.headerShowsConsumed") private var showsConsumed = false

    var body: some View {
        TodayMacroHeader(totals: totals, targets: targets, showsConsumed: showsConsumed)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy) { showsConsumed.toggle() }
            }
            .gesture(daySwipe)
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                onShiftDay(dx < 0 ? 1 : -1)
            }
    }
}

/// Content of one journal day: pinned macro header, timeline log, water, micronutrients.
/// The queries are built from `day` in the initializer, so a new day re-creates them.
struct TodayDayContent: View {
    let day: Date

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query private var entries: [JournalEntry]
    @Query private var waterEntries: [WaterEntry]
    @Query private var profiles: [UserProfile]

    @State private var sheet: TodaySheet?
    @State private var showClearDialog = false
    @State private var recipeMeal: Meal?
    @State private var recipeName = ""
    @State private var showRecipeAlert = false
    @State private var showNutrients = false
    @State private var toast: String?
    @State private var successTick = 0
    @State private var impactTick = 0
    @State private var didRunDemoSheet = false
    @State private var showDatePicker = false

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

    private var addContext: LogContext { LogContext(day: day, meal: Meal.suggested()) }

    var body: some View {
        // Computed once per evaluation and passed down (NutrientValues decoding is memoized
        // in Core, so each entry's JSON is decoded at most once overall).
        let totals = NutrientValues.sum(entries.map(\.nutrients))
        let groups = TodayTimelineGroup.make(from: entries)
        let targets = self.targets

        logList(groups: groups)
            .safeAreaInset(edge: .top, spacing: 0) {
                pinnedTop(totals: totals, targets: targets)
            }
            .overlay(alignment: .bottomTrailing) {
                fab
            }
            .overlay(alignment: .bottom) {
                toastView
            }
            .navigationDestination(isPresented: $showNutrients) {
                TodayNutrientsView(day: day, totals: totals, targets: targets, entryCount: entries.count)
            }
            .sheet(item: $sheet) { destination in
                sheetContent(destination)
            }
            .sheet(isPresented: $showDatePicker) {
                TodayDatePickerSheet()
            }
            .confirmationDialog(
                "Supprimer tous les aliments de ce jour ?",
                isPresented: $showClearDialog,
                titleVisibility: .visible
            ) {
                Button("Tout supprimer", role: .destructive) { clearDay() }
                Button("Annuler", role: .cancel) {}
            }
            .alert("Enregistrer comme recette", isPresented: $showRecipeAlert) {
                TextField("Nom de la recette", text: $recipeName)
                Button("Annuler", role: .cancel) { recipeMeal = nil }
                Button("Enregistrer") {
                    saveRecipe(meal: recipeMeal, name: recipeName)
                    recipeMeal = nil
                }
            } message: {
                Text("Les aliments seront regroupés en une recette réutilisable dans « Mes aliments ».")
            }
            .task(id: toast) {
                guard toast != nil else { return }
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { toast = nil }
            }
            .task {
                await presentDemoSheetIfNeeded()
            }
            .sensoryFeedback(.success, trigger: successTick)
            .sensoryFeedback(.impact(weight: .light), trigger: impactTick)
    }

    // MARK: - Layout pieces

    /// Title bar + pinned macro header; the background extends under the status bar so the
    /// scrolling timeline never shows through.
    private func pinnedTop(totals: NutrientValues, targets: TodayTargets) -> some View {
        VStack(spacing: 0) {
            TodayTitleBar(day: day,
                          onShiftDay: shiftDay,
                          onPickDate: { showDatePicker = true },
                          onToday: goToToday) {
                moreMenu
            }
            TodayPinnedHeader(totals: totals, targets: targets, onShiftDay: shiftDay)
        }
        .background(Theme.background.ignoresSafeArea(edges: .top))
    }

    private func logList(groups: [TodayTimelineGroup]) -> some View {
        List {
            timelineRows(groups)
            TodayNowRow(isToday: isToday, hasGroups: !groups.isEmpty) {
                sheet = .search(addContext)
            }
            .todayListRow()
            waterRow
            nutrientsRow
            AttributionFooter(includeOpenFoodFacts: entries.contains { $0.sourceRaw == FoodSource.openFoodFacts.rawValue })
                .padding(.top, 12)
                .todayListRow()
            Color.clear
                .frame(height: 88)
                .todayListRow()
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .themedBackground()
    }

    private var fab: some View {
        TodayAddButton(
            onSearch: { sheet = .search(addContext) },
            onScan: { sheet = .scan(addContext) },
            onQuickAdd: { sheet = .quickAdd(addContext) }
        )
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(Theme.font(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.raised, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.separatorStrong, lineWidth: 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { withAnimation(.snappy) { self.toast = nil } }
        }
    }

    @ViewBuilder
    private func sheetContent(_ destination: TodaySheet) -> some View {
        switch destination.kind {
        case .search(let context):
            NavigationStack {
                FoodSearchView(context: context, isSheet: true)
            }
        case .scan(let context):
            BarcodeScanView(context: context)
        case .quickAdd(let context):
            QuickAddSheet(context: context)
        case .edit(let entry):
            AddEntrySheet(editing: entry)
        case .detail(let item, let context):
            NavigationStack {
                FoodDetailView(item: item, context: context)
            }
        case .add(let item, let context):
            AddEntrySheet(item: item, context: context)
        }
    }

    // MARK: - Timeline rows

    @ViewBuilder
    private func timelineRows(_ groups: [TodayTimelineGroup]) -> some View {
        if groups.isEmpty {
            TodayEmptyState(isToday: isToday)
                .todayListRow()
        } else {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                groupHeaderRow(group, isFirst: index == 0)
                ForEach(Array(group.entries.enumerated()), id: \.element.persistentModelID) { entryIndex, entry in
                    entryRow(entry, showsDivider: entryIndex > 0)
                }
                groupFooterRow(group)
            }
        }
    }

    private func groupHeaderRow(_ group: TodayTimelineGroup, isFirst: Bool) -> some View {
        TodayGroupHeaderContent(group: group,
                                time: TodayTimeFormat.short(group.start),
                                showsRule: !isFirst)
            .todayListRow()
    }

    private func groupFooterRow(_ group: TodayTimelineGroup) -> some View {
        TodayTimelineRow {
            TodayGroupFooterContent(totals: group.totals)
        }
        .todayListRow()
    }

    private func entryRow(_ entry: JournalEntry, showsDivider: Bool) -> some View {
        TodayTimelineRow {
            Button {
                sheet = .edit(entry)
            } label: {
                TodayTimelineEntryContent(entry: entry, showsDivider: showsDivider)
            }
            .buttonStyle(.plain)
        }
        .todayListRow()
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
            // Not Theme.accent: the system draws the swipe label in white.
            .tint(Theme.textTertiary)
        }
        .contextMenu {
            entryContextMenu(entry)
        }
    }

    @ViewBuilder
    private func entryContextMenu(_ entry: JournalEntry) -> some View {
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
            ForEach(Meal.allCases.filter { $0 != entry.meal }) { target in
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

    // MARK: - Below the timeline

    private var waterRow: some View {
        TodayWaterCard(
            totalMl: waterEntries.reduce(0) { $0 + $1.ml },
            targetMl: targets.water,
            canUndo: !waterEntries.isEmpty,
            onAdd: addWater,
            onUndo: undoWater
        )
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .todayListRow()
    }

    private var nutrientsRow: some View {
        Button {
            showNutrients = true
        } label: {
            TodayNutrientsLinkLabel()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .todayListRow()
    }

    // MARK: - Toolbar "…" menu

    private var mealsPresent: [Meal] {
        Meal.allCases.filter { meal in entries.contains { $0.mealRaw == meal.rawValue } }
    }

    private var moreMenu: some View {
        Menu {
            copyMenu
            recipeMenu
            Divider()
            Button(role: .destructive) {
                showClearDialog = true
            } label: {
                Label("Tout supprimer", systemImage: "trash")
            }
            .disabled(entries.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .accessibilityLabel("Options du jour")
        }
    }

    private var copyMenu: some View {
        Menu {
            Button {
                copyFromPreviousDay(meal: nil)
            } label: {
                Label("Toute la journée", systemImage: "calendar")
            }
            ForEach(Meal.allCases) { meal in
                Button {
                    copyFromPreviousDay(meal: meal)
                } label: {
                    Label(meal.label, systemImage: meal.systemImage)
                }
            }
        } label: {
            Label(isToday ? "Copier depuis hier" : "Copier depuis la veille",
                  systemImage: "arrow.uturn.backward.circle")
        }
    }

    private var recipeMenu: some View {
        Menu {
            if mealsPresent.count > 1 {
                Button {
                    askRecipe(meal: nil)
                } label: {
                    Label("Toute la journée", systemImage: "calendar")
                }
            }
            ForEach(mealsPresent) { meal in
                Button {
                    askRecipe(meal: meal)
                } label: {
                    Label(meal.label, systemImage: meal.systemImage)
                }
            }
        } label: {
            Label("Enregistrer comme recette", systemImage: "book")
        }
        .disabled(entries.isEmpty)
    }

    // MARK: - Swipe between days

    private func goToToday() {
        let today = Date.now.startOfDay
        guard today != appState.selectedDay else { return }
        withAnimation(.snappy) {
            appState.selectedDay = today
        }
    }

    private func shiftDay(_ delta: Int) {
        withAnimation(.snappy) {
            appState.selectedDay = day.adding(days: delta).startOfDay
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

    private func clearDay() {
        withAnimation {
            for entry in entries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
        }
        impactTick += 1
    }

    private func copyFromPreviousDay(meal: Meal?) {
        let start = day.adding(days: -1).startOfDay
        let end = day
        let descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate<JournalEntry> { entry in
                entry.day >= start && entry.day < end
            },
            sortBy: [SortDescriptor(\JournalEntry.createdAt)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let previous = meal.map { target in all.filter { $0.mealRaw == target.rawValue } } ?? all
        guard !previous.isEmpty else {
            if let meal {
                showToast("Aucun aliment pour « \(meal.label) » la veille")
            } else {
                showToast("Aucun aliment la veille")
            }
            return
        }
        withAnimation {
            for entry in previous {
                modelContext.insert(JournalEntry(item: entry.item, grams: entry.grams, day: day, meal: entry.meal))
            }
            try? modelContext.save()
        }
        successTick += 1
        showToast(previous.count == 1 ? "1 aliment copié" : "\(previous.count) aliments copiés")
    }

    private func defaultRecipeName(meal: Meal?) -> String {
        let label = meal?.label ?? "Journée"
        return "\(label) du \(Formatters.shortDate(day))"
    }

    private func askRecipe(meal: Meal?) {
        recipeMeal = meal
        recipeName = defaultRecipeName(meal: meal)
        showRecipeAlert = true
    }

    private func saveRecipe(meal: Meal?, name: String) {
        let selected = meal.map { target in entries.filter { $0.mealRaw == target.rawValue } } ?? entries
        let ingredients = selected.map {
            RecipeIngredient(name: $0.name, grams: $0.grams, per100: $0.per100)
        }
        let totalGrams = ingredients.reduce(0) { $0 + $1.grams }
        guard !ingredients.isEmpty, totalGrams > 0 else { return }
        let sum = NutrientValues.sum(selected.map(\.nutrients))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? defaultRecipeName(meal: meal) : trimmed

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

    // MARK: - CI demo mode

    /// Presents the sheet requested with `-startSheet` once, for CI screenshots.
    private func presentDemoSheetIfNeeded() async {
        guard !didRunDemoSheet else { return }
        didRunDemoSheet = true
        guard let name = DemoSupport.startSheet else { return }
        try? await Task.sleep(for: .milliseconds(500))
        let context = LogContext(day: appState.selectedDay, meal: Meal.suggested())
        switch name {
        case "search": sheet = .search(context)
        case "scan": sheet = .scan(context)
        case "quickadd": sheet = .quickAdd(context)
        case "detail": sheet = .detail(DemoSupport.sampleItem, context)
        case "add": sheet = .add(DemoSupport.sampleItem, context)
        default: break
        }
    }
}
