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

/// Local sheet destination (adding goes through `appState.presentAdd`). The id is captured at
/// creation so it never reads a model that may have been deleted while the sheet was open.
private struct TodaySheet: Identifiable {
    enum Kind {
        case edit(JournalEntry)
        case detail(FoodItem, LogContext)
        case add(FoodItem, LogContext)
    }

    let id: String
    let kind: Kind

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
    /// Full-bleed, separator-less List row on the app background.
    func todayListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.background)
    }

    /// Timeline List row: its background draws the vertical line through the hour pills
    /// (in the row background, so it does not move with swipe actions).
    func todayTimelineRow(top: Bool = true, bottom: Bool = true) -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(TodayTimelineLine(top: top, bottom: bottom))
    }
}

/// Pinned remaining header. Owns the "remaining ↔ consumed" toggle so tapping it re-renders
/// only the header, not the whole timeline list. Horizontal swipe changes the day.
private struct TodayPinnedHeader: View {
    let totals: NutrientValues
    let targets: TodayTargets
    let onShiftDay: (Int) -> Void

    @AppStorage("today.headerShowsConsumed") private var showsConsumed = false

    var body: some View {
        VStack(spacing: 8) {
            TodayMacroHeader(totals: totals, targets: targets, showsConsumed: showsConsumed)
            modeLine
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { showsConsumed.toggle() }
        }
        .gesture(daySwipe)
        .sensoryFeedback(.selection, trigger: showsConsumed)
    }

    /// "Restant" / "Mangé" caption + two page dots showing the current mode.
    private var modeLine: some View {
        HStack(spacing: 4) {
            Text(showsConsumed ? "Mangé" : "Restant")
                .font(Theme.label)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            dot(on: !showsConsumed)
            dot(on: showsConsumed)
        }
        .accessibilityHidden(true)
    }

    private func dot(on: Bool) -> some View {
        Capsule()
            .fill(on ? Theme.textSecondary : Theme.separatorStrong)
            .frame(width: on ? 12 : 5, height: 5)
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

/// Content of one journal day: title bar, pinned remaining header and the hourly timeline.
/// The query is built from `day` in the initializer, so a new day re-creates it.
struct TodayDayContent: View {
    let day: Date

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var entries: [JournalEntry]
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
    @State private var showsEarlyHours = false
    /// Current clock hour, refreshed at every hour change (current-hour pill).
    @State private var nowHour = Calendar.current.component(.hour, from: .now)

    /// Hour shown first by default (earlier hours appear if they have entries).
    private static let defaultFirstHour = 6

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
        _profiles = Query(sort: \UserProfile.createdAt)
    }

    private var targets: TodayTargets { TodayTargets(profile: profiles.first) }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var currentHour: Int? { isToday ? nowHour : nil }

    private func firstHour(_ buckets: TodayHourBuckets) -> Int {
        if showsEarlyHours { return 0 }
        var first = Self.defaultFirstHour
        if let earliest = buckets.earliestHour { first = min(first, earliest) }
        if let currentHour { first = min(first, currentHour) }
        return first
    }

    var body: some View {
        // Computed once per evaluation and passed down (NutrientValues decoding is memoized
        // in Core, so each entry's JSON is decoded at most once overall).
        let totals = NutrientValues.sum(entries.map(\.nutrients))
        let buckets = TodayHourBuckets(entries: entries)
        let targets = self.targets

        ScrollViewReader { proxy in
            timeline(buckets: buckets)
                .task(id: day) {
                    // Let the List lay out its rows before scrolling.
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled else { return }
                    scrollToInitialHour(proxy)
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            pinnedTop(totals: totals, targets: targets)
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
            await trackCurrentHour()
        }
        .task {
            await presentDemoSheetIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshNowHour() }
        }
        .onChange(of: day) { _, _ in
            showsEarlyHours = false
        }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.impact(weight: .light), trigger: impactTick)
    }

    // MARK: - Layout pieces

    /// Title bar + pinned header; the background extends under the status bar so the
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
            TodayHairline()
        }
        .background(Theme.background.ignoresSafeArea(edges: .top))
    }

    private func timeline(buckets: TodayHourBuckets) -> some View {
        let first = firstHour(buckets)
        let current = currentHour
        return List {
            if first > 0 {
                TodayEarlyHoursRow(firstHour: first) {
                    withAnimation(.snappy) { showsEarlyHours = true }
                }
                .todayListRow()
            }
            ForEach(first..<24, id: \.self) { hour in
                let hourEntries = buckets.entries(at: hour)
                TodayHourRow(hour: hour,
                             isNow: hour == current,
                             totals: hourEntries.isEmpty ? nil : buckets.totalsByHour[hour]) {
                    add(at: hour)
                }
                .id(Self.hourID(hour))
                .todayTimelineRow(top: hour != first, bottom: hour != 23 || !hourEntries.isEmpty)
                ForEach(hourEntries, id: \.persistentModelID) { entry in
                    entryRow(entry)
                }
            }
            nutrientsRow
            AttributionFooter(includeOpenFoodFacts: entries.contains { $0.sourceRaw == FoodSource.openFoodFacts.rawValue })
                .padding(.top, 12)
                .todayListRow()
            Color.clear
                .frame(height: 12)
                .todayListRow()
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .themedBackground()
    }

    private static func hourID(_ hour: Int) -> String { "today-hour-\(hour)" }

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
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { withAnimation(.snappy) { self.toast = nil } }
        }
    }

    @ViewBuilder
    private func sheetContent(_ destination: TodaySheet) -> some View {
        switch destination.kind {
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

    // MARK: - Entry rows

    private func entryRow(_ entry: JournalEntry) -> some View {
        Button {
            sheet = .edit(entry)
        } label: {
            TodayEntryCard(entry: entry)
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview,
                      RoundedRectangle(cornerRadius: TodayTimelineMetrics.cardRadius, style: .continuous))
        .contextMenu {
            entryContextMenu(entry)
        }
        .padding(.leading, TodayTimelineMetrics.leading)
        .padding(.trailing, TodayTimelineMetrics.cardTrailing)
        .padding(.bottom, 6)
        .todayTimelineRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(entry)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                duplicate(entry)
            } label: {
                Label("Dupliquer", systemImage: "plus.square.on.square")
            }
            // Not Theme.accent: the system draws the swipe label in white.
            .tint(Theme.textTertiary)
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
            duplicate(entry)
        } label: {
            Label("Dupliquer", systemImage: "plus.square.on.square")
        }
        if !isToday {
            Button {
                copyToToday(entry)
            } label: {
                Label("Copier vers aujourd'hui", systemImage: "calendar.badge.plus")
            }
        }
        Menu {
            let entryHour = Calendar.current.component(.hour, from: entry.createdAt)
            ForEach(0..<24, id: \.self) { hour in
                if hour != entryHour {
                    Button(TodayTimeFormat.hour(hour)) {
                        move(entry, toHour: hour)
                    }
                }
            }
        } label: {
            Label("Changer l'heure", systemImage: "clock.arrow.circlepath")
        }
        Divider()
        Button(role: .destructive) {
            delete(entry)
        } label: {
            Label("Supprimer", systemImage: "trash")
        }
    }

    // MARK: - Below the timeline

    private var nutrientsRow: some View {
        Button {
            showNutrients = true
        } label: {
            TodayNutrientsLinkLabel()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .todayListRow()
    }

    // MARK: - "…" day menu

    private var mealsPresent: [Meal] {
        Meal.allCases.filter { meal in entries.contains { $0.mealRaw == meal.rawValue } }
    }

    private var moreMenu: some View {
        Menu {
            copyMenu
            recipeMenu
            Button {
                showNutrients = true
            } label: {
                Label("Nutriments du jour", systemImage: "chart.bar.doc.horizontal")
            }
            Divider()
            Button(role: .destructive) {
                showClearDialog = true
            } label: {
                Label("Tout supprimer", systemImage: "trash")
            }
            .disabled(entries.isEmpty)
        } label: {
            TodayRoundIcon(systemName: "ellipsis")
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

    // MARK: - Day navigation & clock

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

    private func refreshNowHour() {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour != nowHour { nowHour = hour }
    }

    /// Keeps `nowHour` in sync with the clock: wakes up just after each hour change.
    private func trackCurrentHour() async {
        let calendar = Calendar.current
        while !Task.isCancelled {
            refreshNowHour()
            let now = Date.now
            let next = calendar.nextDate(after: now,
                                         matching: DateComponents(minute: 0, second: 0),
                                         matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
            let delay = max(next.timeIntervalSince(now), 1) + 0.5
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Today: the current hour (one hour of context above it); another day: its first entry.
    private func scrollToInitialHour(_ proxy: ScrollViewProxy) {
        let buckets = TodayHourBuckets(entries: entries)
        let first = firstHour(buckets)
        let target: Int
        if let currentHour {
            target = max(first, currentHour - 1)
        } else {
            target = max(first, buckets.earliestHour ?? first)
        }
        proxy.scrollTo(Self.hourID(target), anchor: .top)
    }

    // MARK: - Actions

    /// "+" of an hour slot. The current hour of today logs "now" (time nil) so the food lands
    /// after what is already logged in that hour; other slots log at hh:00.
    private func add(at hour: Int) {
        var context = LogContext.slot(day: day, hour: hour)
        if hour == currentHour {
            context.time = nil
        }
        appState.presentAdd(.search, context: context)
    }

    /// `date`'s time of day (h, min, s) on `targetDay`.
    private func sameTime(of date: Date, on targetDay: Date, hour: Int? = nil) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let start = calendar.startOfDay(for: targetDay)
        let h = hour ?? parts.hour ?? 0
        let m = parts.minute ?? 0
        let s = parts.second ?? 0
        return calendar.date(bySettingHour: h, minute: m, second: s, of: start)
            ?? start.addingTimeInterval(TimeInterval(h * 3600 + m * 60 + s))
    }

    private func delete(_ entry: JournalEntry) {
        withAnimation {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        impactTick += 1
    }

    /// Copy right after the original, in the same hour.
    private func duplicate(_ entry: JournalEntry) {
        let time = sameTime(of: entry.createdAt, on: day).addingTimeInterval(1)
        let copy = JournalEntry(item: entry.item, grams: entry.grams, day: day, meal: entry.meal, at: time)
        withAnimation {
            modelContext.insert(copy)
            try? modelContext.save()
        }
        successTick += 1
    }

    private func copyToToday(_ entry: JournalEntry) {
        let copy = JournalEntry(item: entry.item, grams: entry.grams, day: Date.now.startOfDay,
                                meal: Meal.suggested(), at: nil)
        modelContext.insert(copy)
        try? modelContext.save()
        successTick += 1
        showToast("Ajouté à aujourd'hui")
    }

    /// Moves an entry to another hour of its day (keeps the minutes); the meal follows the time.
    private func move(_ entry: JournalEntry, toHour hour: Int) {
        let time = sameTime(of: entry.createdAt, on: entry.day, hour: hour)
        withAnimation {
            entry.createdAt = time
            entry.meal = Meal.suggested(for: time)
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
                // Same time of day as the day before, so the copy lands in the same hour.
                modelContext.insert(JournalEntry(item: entry.item, grams: entry.grams, day: day,
                                                 meal: entry.meal, at: sameTime(of: entry.createdAt, on: day)))
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
        case "search": appState.presentAdd(.search, context: context)
        case "scan": appState.presentAdd(.scan, context: context)
        case "quickadd": appState.presentAdd(.quick, context: context)
        case "detail": sheet = .detail(DemoSupport.sampleItem, context)
        case "add": sheet = .add(DemoSupport.sampleItem, context)
        default: break
        }
    }
}
