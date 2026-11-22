import SwiftData
import SwiftUI
import UIKit

/// Search mode of the add flow: search the OpenNutrition database (French words are
/// translated) and the user's own foods. With an empty query: Favoris (one tap logs),
/// "Souvent à 9 h" (foods usually logged around this hour) and Récents.
/// Tapping a row opens the quantity sheet (`AddEntrySheet`); the round "+" checks the row,
/// and "Ajouter (n)" logs every checked food with its usual quantity.
///
/// `FoodSearchView(context:isSheet:)` is the standalone version (place it inside a
/// NavigationStack: navigation title, "Fermer" and meal menu). `AddFlowView` embeds it with
/// `FoodSearchView(embeddedIn:onLogged:onQuickAdd:)` (no navigation bar).
struct FoodSearchView: View {
    @Environment(\.addFlowOpenItem) private var addFlowOpenItem
    let isSheet: Bool
    private let isEmbedded: Bool
    private let onLogged: (() -> Void)?
    private let onQuickAdd: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.slideCover) private var slideCover

    @Query(sort: \FavoriteFood.createdAt, order: .reverse) private var favorites: [FavoriteFood]
    @Query(FoodSearchView.recentDescriptor) private var recentEntries: [JournalEntry]
    /// Entries of the last 30 days, for "Souvent à 9 h".
    @Query private var monthEntries: [JournalEntry]
    @Query(sort: \CustomFood.name) private var customFoods: [CustomFood]

    private let initialContext: LogContext
    @State private var context: LogContext
    @State private var query = ""
    @State private var filter: SearchKindFilter = .all
    /// Database results, already converted to `FoodItem` off the main thread.
    @State private var results: [FoodItem] = []
    /// "Mes aliments" matches of `searchedText`, published together with `results` so the two
    /// sections never update at different times while typing.
    @State private var customResults: [CustomFood] = []
    @State private var searchedText = ""
    /// Bumped on every published result set (new text or filter): scrolls back to the top.
    @State private var resultsGeneration = 0
    @State private var isSearching = false
    @State private var activeSheet: SearchSheet?
    @State private var dismissAfterSheet = false
    @State private var refocusAfterSheet = false
    @State private var loggedCount = 0
    /// Checked foods (multi-select), in the order they were checked.
    @State private var selection: [SearchSelection] = []
    @FocusState private var isSearchFocused: Bool

    init(context: LogContext, isSheet: Bool) {
        self.init(context: context, isSheet: isSheet, isEmbedded: false, onLogged: nil, onQuickAdd: nil)
    }

    /// Embedded in the add sheet: no navigation bar; `onLogged` closes the sheet,
    /// `onQuickAdd` switches to the quick add mode.
    init(embeddedIn context: LogContext, onLogged: @escaping () -> Void, onQuickAdd: @escaping () -> Void) {
        self.init(context: context, isSheet: true, isEmbedded: true, onLogged: onLogged, onQuickAdd: onQuickAdd)
    }

    private init(context: LogContext, isSheet: Bool, isEmbedded: Bool,
                 onLogged: (() -> Void)?, onQuickAdd: (() -> Void)?) {
        self.initialContext = context
        self.isSheet = isSheet
        self.isEmbedded = isEmbedded
        self.onLogged = onLogged
        self.onQuickAdd = onQuickAdd
        _context = State(initialValue: context)
        let cutoff = Calendar.current.startOfDay(for: .now).addingTimeInterval(-30 * 86_400)
        _monthEntries = Query(filter: #Predicate<JournalEntry> { $0.createdAt >= cutoff },
                              sort: \JournalEntry.createdAt, order: .reverse)
    }

    private static var recentDescriptor: FetchDescriptor<JournalEntry> {
        var descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\JournalEntry.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 150
        return descriptor
    }

    // MARK: Derived data

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchKey: SearchQueryKey { SearchQueryKey(text: trimmedQuery, filter: filter) }

    /// Same value as `entry.item.id` ("source:ref" or "source:name"), without decoding the entry.
    private static func key(of entry: JournalEntry) -> String {
        "\(entry.source.rawValue):\(entry.ref ?? entry.name)"
    }

    /// Hour the user is adding food for (slot time, or now).
    private var contextHour: Int {
        Calendar.current.component(.hour, from: context.time ?? .now)
    }

    /// Latest logged quantity per item key (from the recent entries).
    private var lastLoggedGrams: [String: Double] {
        var grams: [String: Double] = [:]
        for entry in recentEntries {
            let key = FoodSearchView.key(of: entry)
            if grams[key] == nil { grams[key] = entry.grams }
        }
        return grams
    }

    /// Usual quantity of an item: remembered by the quantity sheet, else last logged, else one
    /// serving (or 100 g).
    private func usualGrams(for item: FoodItem, recent: [String: Double]) -> Double {
        if item.source == .quickAdd { return 100 }
        if let remembered = UserDefaults.standard.object(forKey: "lastGrams.\(item.id)") as? Double,
           remembered > 0 {
            return remembered
        }
        if let grams = recent[item.id], grams > 0 { return grams }
        return item.defaultGrams
    }

    /// Foods logged on at least 2 different days within ±1 h of `hour` in the last 30 days,
    /// most frequent first (max 5). Only the kept entries pay for `entry.item`.
    private func frequentItems(hour: Int) -> [FoodItem] {
        let calendar = Calendar.current
        var days: [String: Set<Date>] = [:]
        var latest: [String: JournalEntry] = [:]
        for entry in monthEntries {
            let entryHour = calendar.component(.hour, from: entry.createdAt)
            let difference = abs(entryHour - hour)
            guard min(difference, 24 - difference) <= 2 else { continue }
            let key = FoodSearchView.key(of: entry)
            days[key, default: []].insert(entry.day)
            if latest[key] == nil { latest[key] = entry }
        }
        let ranked = days
            .filter { $0.value.count >= 2 }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                return lhs.key < rhs.key
            }
        return ranked.prefix(5).compactMap { latest[$0.key]?.item }
    }

    /// Distinct items of the latest journal entries (most recent first), skipping `excluded` keys.
    private func recentItems(excluding excluded: Set<String>) -> [FoodItem] {
        var seen = excluded
        var items: [FoodItem] = []
        for entry in recentEntries {
            let key = FoodSearchView.key(of: entry)
            guard seen.insert(key).inserted else { continue }
            items.append(entry.item)
            if items.count >= 20 { break }
        }
        return items
    }

    /// OpenNutrition food id -> times logged (last 30 days, plus the latest entries): those
    /// foods are ranked first by the search when they match.
    private var loggedFoodCounts: [Int64: Int] {
        var counts: [Int64: Int] = [:]
        for entry in monthEntries where entry.source == .openNutrition {
            if let id = entry.ref.flatMap({ Int64($0) }) { counts[id, default: 0] += 1 }
        }
        for entry in recentEntries where entry.source == .openNutrition {
            if let id = entry.ref.flatMap({ Int64($0) }), counts[id] == nil { counts[id] = 1 }
        }
        return counts
    }

    /// Custom foods whose name/brand contains every query word (run with each search).
    private func matchingCustomFoods(for text: String) -> [CustomFood] {
        guard filter == .all, !text.isEmpty, !customFoods.isEmpty else { return [] }
        let words = FoodDatabase.tokens(of: text)
            .filter { !FrenchFoodLexicon.stopWords.contains($0) }
        guard !words.isEmpty else { return [] }
        var matches: [CustomFood] = []
        for food in customFoods {
            let haystack = FoodDatabase.tokens(of: food.name + " " + (food.brand ?? "")).joined(separator: " ")
            if words.allSatisfy({ haystack.contains($0) }) {
                matches.append(food)
                if matches.count >= 10 { break }
            }
        }
        return matches
    }

    private func isSelected(_ item: FoodItem) -> Bool {
        selection.contains { $0.id == item.id }
    }

    // MARK: Body

    var body: some View {
        let text = trimmedQuery
        let custom = customResults
        let recent = lastLoggedGrams
        Group {
            if isEmbedded {
                content(text: text, custom: custom, recent: recent)
            } else {
                content(text: text, custom: custom, recent: recent)
                    .navigationTitle(isSheet ? "Ajouter un aliment" : "Ajouter")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarContent }
            }
        }
        .task(id: searchKey) { await runSearch(searchKey) }
        .task {
            // Keyboard first: the field is focused as soon as the page is in place.
            await SlideCoverMotion.untilSettled(slideCover)
            isSearchFocused = true
        }
        .onChange(of: initialContext) { _, newValue in context = newValue }
        .onChange(of: customFoods.count) { _, _ in
            // A food created from this screen shows up without retyping.
            customResults = matchingCustomFoods(for: searchedText)
        }
        .slideCover(item: $activeSheet, onDismiss: sheetDismissed) { sheet in
            sheetContent(sheet)
        }
        .sensoryFeedback(.success, trigger: loggedCount)
        .sensoryFeedback(.selection, trigger: selection.count)
    }

    private func content(text: String, custom: [CustomFood], recent: [String: Double]) -> some View {
        resultsList(text: text, custom: custom, recent: recent)
            .overlay {
                if !text.isEmpty, !isSearching, searchedText == text,
                   results.isEmpty, custom.isEmpty {
                    noResultsView(text: text)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar(showsChips: !text.isEmpty)
            }
    }

    private func resultsList(text: String, custom: [CustomFood], recent: [String: Double]) -> some View {
        ScrollViewReader { proxy in
            List {
                // Scroll anchor: every new result set starts at the top.
                Color.clear
                    .frame(height: 0)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Theme.raised)
                    .listRowSeparator(.hidden)
                    .id(Self.listTopID)
                resultsListContent(text: text, custom: custom, recent: recent)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollDismissesKeyboard(.immediately)
            .scrollContentBackground(.hidden)
            .background(Theme.raised)
            .onChange(of: resultsGeneration) { _, _ in
                proxy.scrollTo(Self.listTopID, anchor: .top)
            }
        }
    }

    private static let listTopID = "search-top"

    @ViewBuilder
    private func resultsListContent(text: String, custom: [CustomFood], recent: [String: Double]) -> some View {
        if !FoodDatabase.shared.isAvailable {
            databaseErrorSection
        }
        if text.isEmpty {
            emptyQueryContent(recent: recent)
        } else {
            searchContent(text: text, custom: custom, recent: recent)
        }
        AttributionFooter()
            .listRowBackground(Theme.raised)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SearchSheet) -> some View {
        switch sheet {
        case .quickAdd:
            QuickAddSheet(context: context, onLogged: {
                if isSheet { dismissAfterSheet = true }
            })
        case .add(let item):
            AddEntrySheet(item: item, context: context, onLogged: {
                loggedCount += 1
                dismissAfterSheet = true
            })
        }
    }

    private func noResultsView(text: String) -> some View {
        ContentUnavailableView {
            Label("Aucun résultat", systemImage: "magnifyingglass")
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text("Aucun aliment ne correspond à « \(text) ». Essayez un autre mot, en français ou en anglais.")
                .font(Theme.callout)
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            Button {
                if let onQuickAdd {
                    onQuickAdd()
                } else {
                    isSearchFocused = false
                    activeSheet = .quickAdd
                }
            } label: {
                SearchOutlineButtonLabel(title: "Ajout rapide", systemImage: "bolt")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Bottom bar (chips, field, "Ajouter (n)")

    private func bottomBar(showsChips: Bool) -> some View {
        VStack(spacing: 10) {
            if showsChips {
                filterChips
            }
            HStack(spacing: 8) {
                searchField
                // Always shown, like the reference's "Log Foods"; logs the checked foods.
                addSelectionButton
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            Theme.raised.ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            // MF: white glyph, 1.7 pt stroke.
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            TextField("Rechercher un aliment", text: $query,
                      prompt: Text("Rechercher un aliment").foregroundColor(Theme.textTertiary))
                .font(Theme.font(16, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .focused($isSearchFocused)
                .submitLabel(selection.isEmpty ? .search : .done)
                .onSubmit(submit)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(maxHeight: .infinity)
            if !query.isEmpty {
                clearButton
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 49)
        .background(Theme.raised, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(isSearchFocused ? Theme.textPrimary : Theme.separatorStrong,
                              lineWidth: isSearchFocused ? 3 : 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = true }
    }

    private var addSelectionButton: some View {
        Button(action: logSelection) {
            Text(selection.isEmpty ? "Ajouter" : "Ajouter (\(selection.count))")
                .font(Theme.font(16, .medium, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 18)
                .frame(minWidth: 112)
                .frame(height: 49)
                .background(Theme.accent, in: Capsule())
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Ajouter \(selection.count) aliment\(selection.count > 1 ? "s" : "") au journal")
    }

    private var clearButton: some View {
        Button {
            query = ""
            isSearchFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textQuaternary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Effacer la recherche")
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SearchKindFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        SearchFilterPill(option: option, isSelected: filter == option)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    // MARK: Toolbar (standalone only)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSheet {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { dismiss() }
                    .font(Theme.font(15, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            mealMenu
        }
    }

    private var mealMenu: some View {
        Menu {
            Section(Formatters.dayTitle(context.day)) {
                Picker("Repas", selection: $context.meal) {
                    ForEach(Meal.allCases) { meal in
                        Label(meal.label, systemImage: meal.systemImage).tag(meal)
                    }
                }
            }
        } label: {
            Label(context.meal.label, systemImage: context.meal.systemImage)
                .labelStyle(.titleAndIcon)
                .font(Theme.font(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityLabel("Repas : \(context.meal.label)")
    }

    // MARK: Sections

    private var databaseErrorSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.overTarget)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Base d'aliments indisponible")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(FoodDatabase.shared.openError ?? "La base OpenNutrition n'a pas pu être ouverte. Vos aliments personnels restent disponibles.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.raised)
            .listRowSeparatorTint(Theme.separator)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private func emptyQueryContent(recent: [String: Double]) -> some View {
        if !favorites.isEmpty {
            favoritesSection(recent: recent)
        }

        let hour = contextHour
        let frequent = frequentItems(hour: hour)
        if !frequent.isEmpty {
            Section {
                sectionHeaderRow("Choix de \(String(format: "%02d", hour)):00")
                ForEach(frequent) { item in
                    foodRow(item, grams: usualGrams(for: item, recent: recent))
                }
            }
            .listSectionSeparator(.hidden)
        }

        let recents = recentItems(excluding: Set(frequent.map(\.id)))
        if !recents.isEmpty {
            Section {
                sectionHeaderRow("Derniers")
                ForEach(recents) { item in
                    foodRow(item, grams: usualGrams(for: item, recent: recent))
                }
            }
            .listSectionSeparator(.hidden)
        }

        if favorites.isEmpty && frequent.isEmpty && recents.isEmpty {
            emptyHint
        }
    }

    /// Horizontal row of big icon tiles; one tap logs the usual quantity.
    private func favoritesSection(recent: [String: Double]) -> some View {
        Section {
            // Tighter under "Favoris" (MF): tiles and captions sit right under the heading.
            sectionHeaderRow("Favoris", bottom: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(favorites) { favorite in
                        favoriteTile(favorite, recent: recent)
                    }
                }
                .padding(.horizontal, 6)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Theme.raised)
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
    }

    private func favoriteTile(_ favorite: FavoriteFood, recent: [String: Double]) -> some View {
        let item = favorite.item
        let grams = usualGrams(for: item, recent: recent)
        return Button {
            logFoods([SearchSelection(item: item, grams: grams)])
        } label: {
            SearchFavoriteTile(item: item)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajouter \(item.name), \(Formatters.number(grams, maxFractionDigits: 0)) \(item.unitSymbol)")
        .contextMenu {
            Button {
                open(item)
            } label: {
                Label("Choisir la quantité", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                modelContext.delete(favorite)
                try? modelContext.save()
            } label: {
                Label("Retirer des favoris", systemImage: "star.slash")
            }
        }
    }

    private var emptyHint: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                Text("Recherchez un aliment")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(databaseHint)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Theme.raised)
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
    }

    private var databaseHint: String {
        let count = FoodDatabase.shared.isAvailable ? FoodDatabase.shared.count : 0
        if count > 0 {
            return "Plus de \(Formatters.number(Double(count / 1000 * 1000), maxFractionDigits: 0)) aliments, en français ou en anglais : « poulet », « yaourt grec », « banana »…"
        }
        return "Tapez le nom d'un aliment, en français ou en anglais."
    }

    @ViewBuilder
    private func searchContent(text: String, custom: [CustomFood], recent: [String: Double]) -> some View {
        if !custom.isEmpty {
            Section {
                sectionHeaderRow("Mes aliments")
                ForEach(custom) { food in
                    let item = food.item
                    foodRow(item, grams: usualGrams(for: item, recent: recent), highlight: searchedText)
                }
            }
            .listSectionSeparator(.hidden)
        }

        if FoodDatabase.shared.isAvailable {
            Section {
                resultsHeaderRow
                ForEach(results) { item in
                    foodRow(item, grams: usualGrams(for: item, recent: recent), highlight: searchedText)
                }
            }
            .listSectionSeparator(.hidden)
        }
    }

    /// "OPENNUTRITION · 60 RÉSULTATS" line above the database results.
    private var resultsHeaderRow: some View {
        HStack(spacing: 6) {
            Text(resultsCountText)
                .font(Theme.label)
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .modifier(SearchHeaderRowStyle())
    }

    private var resultsCountText: String {
        guard !isSearching, !results.isEmpty else { return "OPENNUTRITION" }
        let count = results.count
        return "OPENNUTRITION · \(count) RÉSULTAT\(count > 1 ? "S" : "")"
    }

    private func sectionHeaderRow(_ title: String, bottom: CGFloat = 0) -> some View {
        SearchSectionHeader(title: title)
            .modifier(SearchHeaderRowStyle(bottom: bottom))
    }

    /// Icon tile, name, "🔥 kcal · G · P · L · quantity", trailing round "+" / check.
    private func foodRow(_ item: FoodItem, grams: Double, highlight: String? = nil) -> some View {
        let checked = isSelected(item)
        return HStack(spacing: 0) {
            Button {
                open(item)
            } label: {
                FoodRowView(item: item, grams: grams, highlight: highlight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button {
                toggle(item, grams: grams)
            } label: {
                SearchCheckCircle(isOn: checked)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(checked ? "Décocher \(item.name)" : "Cocher \(item.name)")
        }
        // MF: the row divider starts under the name, not under the icon.
        .alignmentGuide(.listRowSeparatorLeading) { _ in FoodRowView.textLeading }
        // 44 pt "+" target + 9 + 9 = 62 pt rows (MF 61-64); content 3 pt left of the headers.
        .listRowInsets(EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 10))
        .listRowBackground(checked ? Theme.raised2 : Theme.raised)
        // MF row divider: #424242 (sampled at 3x), brighter than the input hairline.
        .listRowSeparatorTint(Theme.hex(0x444444))
    }

    // MARK: Actions

    private func runSearch(_ key: SearchQueryKey) async {
        guard !key.text.isEmpty else {
            // Nothing to clear on first appearance: skip the extra render while sliding in.
            if !searchedText.isEmpty || !results.isEmpty || !customResults.isEmpty {
                publish(results: [], custom: [], for: "")
            }
            if isSearching { isSearching = false }
            return
        }
        if !isSearching { isSearching = true }
        // Debounce typing (the task is cancelled on every keystroke; a query takes ~20-60 ms);
        // a filter change on the text already searched runs immediately.
        if key.text != searchedText {
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
        }
        var found: [FoodItem] = []
        if FoodDatabase.shared.isAvailable {
            let text = key.text
            let kinds = key.filter.kinds
            let history = loggedFoodCounts
            // Phrase rewrite, SQLite queries, ranking and Food → FoodItem conversion all run
            // off the main thread.
            found = await Task.detached(priority: .userInitiated) { () -> [FoodItem] in
                FoodDatabase.shared.search(text, kinds: kinds, limit: 60, history: history).map { $0.item }
            }.value
        }
        if Task.isCancelled { return }
        publish(results: found, custom: matchingCustomFoods(for: key.text), for: key.text)
        isSearching = false
    }

    /// Replaces both result sections at once, without animation (no rows sliding around).
    private func publish(results found: [FoodItem], custom: [CustomFood], for text: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            results = found
            customResults = custom
            searchedText = text
            resultsGeneration &+= 1
        }
    }

    /// Opens the quantity sheet for one food.
    private func open(_ item: FoodItem) {
        refocusAfterSheet = isSearchFocused
        isSearchFocused = false
        if let addFlowOpenItem {
            addFlowOpenItem(item)
            return
        }
        activeSheet = .add(item)
    }

    private func toggle(_ item: FoodItem, grams: Double) {
        if let index = selection.firstIndex(where: { $0.id == item.id }) {
            selection.remove(at: index)
        } else {
            selection.append(SearchSelection(item: item, grams: grams))
        }
    }

    /// Return key: logs the checked foods, or opens the first result.
    private func submit() {
        if !selection.isEmpty {
            logSelection()
        } else if let first = results.first, !trimmedQuery.isEmpty {
            open(first)
        }
    }

    private func logSelection() {
        logFoods(selection)
    }

    /// Logs foods with the given quantities at the context time, then closes.
    private func logFoods(_ foods: [SearchSelection]) {
        guard !foods.isEmpty else { return }
        for food in foods {
            modelContext.insert(JournalEntry(item: food.item, grams: food.grams, day: context.day,
                                             meal: context.meal, at: context.time))
        }
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        selection = []
        isSearchFocused = false
        finishAfterLogging()
    }

    private func finishAfterLogging() {
        if let onLogged {
            onLogged()
        } else if isSheet {
            dismiss()
        }
    }

    private func sheetDismissed() {
        if dismissAfterSheet {
            dismissAfterSheet = false
            finishAfterLogging()
        } else if refocusAfterSheet {
            refocusAfterSheet = false
            isSearchFocused = true
        }
    }
}

// MARK: - Private helpers

/// One checked food and the quantity it will be logged with.
private struct SearchSelection: Identifiable {
    let item: FoodItem
    let grams: Double
    var id: String { item.id }
}

private struct SearchQueryKey: Equatable {
    let text: String
    let filter: SearchKindFilter
}

private enum SearchKindFilter: String, CaseIterable, Identifiable {
    case all, everyday, prepared, restaurant, grocery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Tous"
        case .everyday: "Aliments"
        case .prepared: "Plats"
        case .restaurant: "Restaurants"
        case .grocery: "Marques"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .everyday: FoodKind.everyday.systemImage
        case .prepared: FoodKind.prepared.systemImage
        case .restaurant: FoodKind.restaurant.systemImage
        case .grocery: FoodKind.grocery.systemImage
        }
    }

    var kinds: Set<FoodKind>? {
        switch self {
        case .all: nil
        case .everyday: [.everyday]
        case .prepared: [.prepared]
        case .restaurant: [.restaurant]
        case .grocery: [.grocery]
        }
    }
}

private enum SearchSheet: Identifiable {
    case quickAdd
    case add(FoodItem)

    var id: String {
        switch self {
        case .quickAdd: "quickAdd"
        case .add(let item): "add:\(item.id)"
        }
    }
}

/// Section title ("Favoris", "Souvent à 9 h", "Récents").
private struct SearchSectionHeader: View {
    let title: String

    var body: some View {
        // MF: ~16 pt medium (cap 11.3 pt), not 17.
        Text(title)
            .font(Theme.font(16, .medium, relativeTo: .headline))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// List row style of the in-list section headers (no hairlines). MF: the first food row
/// sits right under its heading (no bottom inset).
private struct SearchHeaderRowStyle: ViewModifier {
    var bottom: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Theme.raised)
            .listRowSeparator(.hidden)
    }
}

/// Big favorite tile: icon with a small white "+" badge, name below.
private struct SearchFavoriteTile: View {
    let item: FoodItem

    var body: some View {
        // MF: caption cap 13 pt under the "+" badge.
        VStack(spacing: 3) {
            FoodIconView(item: item, size: 40)
                .frame(width: 56, height: 44, alignment: .topLeading)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Theme.raised2, in: Circle())
                        // MF: the badge's left edge sits on the tile's centre line.
                        .offset(x: -2, y: 2)
                }
            Text(item.name)
                .font(Theme.font(12.5, .regular, relativeTo: .caption2))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 88)
        }
        .frame(width: 92)
        .contentShape(Rectangle())
    }
}

/// Filter chip: white fill + near-black text when selected, 1 pt outline otherwise.
private struct SearchFilterPill: View {
    let option: SearchKindFilter
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: option.systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(option.label)
                .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .foregroundStyle(isSelected ? Theme.onAccent : Theme.textSecondary)
        .background {
            if isSelected {
                Capsule().fill(Theme.accent)
            } else {
                Capsule().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
            }
        }
        .contentShape(Capsule())
    }
}

/// Trailing round "+" of a row; white with a check when the row is selected.
private struct SearchCheckCircle: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark" : "plus")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
            .frame(width: 28, height: 28)
            .background {
                Circle().fill(isOn ? Theme.accent : Theme.raised2)
            }
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.18), value: isOn)
    }
}

/// Secondary button look: outlined capsule, textPrimary.
private struct SearchOutlineButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(Theme.font(14, .medium, relativeTo: .subheadline))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .overlay {
                Capsule().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
            }
            .contentShape(Capsule())
    }
}
