import SwiftData
import SwiftUI

/// "Ajouter" screen: search the OpenNutrition database (French words are translated) and
/// the user's own foods; shortcuts, favorites and recent foods when the query is empty.
/// Must be placed inside a NavigationStack (the root of a tab or of a sheet).
struct FoodSearchView: View {
    let isSheet: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \FavoriteFood.createdAt, order: .reverse) private var favorites: [FavoriteFood]
    @Query(FoodSearchView.recentDescriptor) private var recentEntries: [JournalEntry]
    @Query(sort: \CustomFood.name) private var customFoods: [CustomFood]

    private let initialContext: LogContext
    @State private var context: LogContext
    @State private var query = ""
    @State private var filter: SearchKindFilter = .all
    /// Database results, already converted to `FoodItem` off the main thread.
    @State private var results: [FoodItem] = []
    @State private var searchedText = ""
    @State private var isSearching = false
    @State private var activeSheet: SearchSheet?
    @State private var dismissAfterSheet = false
    @State private var loggedCount = 0
    @FocusState private var isSearchFocused: Bool

    init(context: LogContext, isSheet: Bool) {
        self.initialContext = context
        self.isSheet = isSheet
        _context = State(initialValue: context)
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

    /// Distinct items of the latest journal entries (most recent first).
    /// De-duplicates on the stored key fields first so only the ~20 kept entries pay for
    /// `entry.item` (which JSON-decodes the nutrient snapshot).
    private var recentItems: [FoodItem] {
        var seen = Set<String>()
        var items: [FoodItem] = []
        for entry in recentEntries {
            // Same value as `entry.item.id` ("source:ref" or "source:name").
            let key = "\(entry.source.rawValue):\(entry.ref ?? entry.name)"
            guard seen.insert(key).inserted else { continue }
            items.append(entry.item)
            if items.count >= 20 { break }
        }
        return items
    }

    /// Custom foods whose name/brand contains every query word. Computed once per body pass.
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

    // MARK: Body

    var body: some View {
        let text = trimmedQuery
        let custom = matchingCustomFoods(for: text)
        resultsList(text: text, custom: custom)
            .overlay {
                if !text.isEmpty, !isSearching, searchedText == text,
                   results.isEmpty, custom.isEmpty {
                    noResultsView(text: text)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                searchHeader(showsChips: !text.isEmpty)
            }
            .navigationTitle(isSheet ? "Ajouter un aliment" : "Ajouter")
            .navigationBarTitleDisplayMode(isSheet ? .inline : .large)
            .toolbar { toolbarContent }
            .task(id: searchKey) { await runSearch(searchKey) }
            .onChange(of: initialContext) { _, newValue in context = newValue }
            .sheet(item: $activeSheet, onDismiss: sheetDismissed) { sheet in
                sheetContent(sheet)
            }
            .sensoryFeedback(.success, trigger: loggedCount)
    }

    private func resultsList(text: String, custom: [CustomFood]) -> some View {
        List {
            if !FoodDatabase.shared.isAvailable {
                databaseErrorSection
            }
            if text.isEmpty {
                emptyQueryContent
            } else {
                searchContent(text: text, custom: custom)
            }
            AttributionFooter()
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollDismissesKeyboard(.immediately)
        .themedBackground()
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SearchSheet) -> some View {
        switch sheet {
        case .scanner:
            BarcodeScanView(context: context, onLogged: {
                if isSheet { dismissAfterSheet = true }
            })
        case .quickAdd:
            QuickAddSheet(context: context, onLogged: {
                if isSheet { dismissAfterSheet = true }
            })
        case .add(let item):
            AddEntrySheet(item: item, context: context, onLogged: {
                loggedCount += 1
                if isSheet { dismissAfterSheet = true }
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
                activeSheet = .quickAdd
            } label: {
                SearchOutlineButtonLabel(title: "Ajout rapide", systemImage: "bolt")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Search header (destination line, field, chips)

    private func searchHeader(showsChips: Bool) -> some View {
        VStack(spacing: 0) {
            destinationLine
                .padding(.bottom, 8)
            searchField
                .padding(.horizontal, 16)
            if showsChips {
                filterChips
                    .padding(.top, 10)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    /// "Ajout à Déjeuner · aujourd'hui" (meal and day the food will be logged to).
    private var destinationLine: some View {
        HStack(spacing: 4) {
            Text("Ajout à")
                .foregroundStyle(Theme.textTertiary)
            Text(context.meal.label)
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.textBody)
            Text("· \(Formatters.dayTitle(context.day).lowercased())")
                .foregroundStyle(Theme.textTertiary)
        }
        .font(Theme.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField("Rechercher un aliment", text: $query,
                      prompt: Text("Rechercher un aliment").foregroundColor(Theme.textTertiary))
                .font(Theme.font(16, .medium, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(maxHeight: .infinity)
            if !query.isEmpty {
                clearButton
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
        }
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

    // MARK: Toolbar

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
            .listRowBackground(Theme.background)
            .listRowSeparatorTint(Theme.separator)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var emptyQueryContent: some View {
        shortcutsSection

        if !favorites.isEmpty {
            favoritesSection
        }

        let recents = recentItems
        if !recents.isEmpty {
            Section {
                sectionHeaderRow("Récents")
                ForEach(recents) { item in
                    foodRow(item)
                }
            }
            .listSectionSeparator(.hidden)
        }

        if favorites.isEmpty && recents.isEmpty {
            emptyHint
        }
    }

    private var shortcutsSection: some View {
        Section {
            Button {
                activeSheet = .scanner
            } label: {
                SearchShortcutLabel(title: "Scanner un code-barres", systemImage: "barcode.viewfinder")
            }
            .listRowSeparator(.hidden, edges: .top)
            Button {
                activeSheet = .quickAdd
            } label: {
                SearchShortcutLabel(title: "Ajout rapide", systemImage: "bolt")
            }
            NavigationLink {
                CustomFoodsListView(pickContext: context, onLogged: closeSheetAfterLogging)
            } label: {
                SearchShortcutLabel(title: "Mes aliments", systemImage: "person.crop.circle")
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.separator)
        .listSectionSeparator(.hidden)
    }

    private var favoritesSection: some View {
        Section {
            sectionHeaderRow("Favoris")
            ForEach(favorites) { favorite in
                foodRow(favorite.item)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(favorite)
                            try? modelContext.save()
                        } label: {
                            Label("Retirer", systemImage: "star.slash")
                        }
                    }
            }
        }
        .listSectionSeparator(.hidden)
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
            .listRowBackground(Theme.background)
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
    private func searchContent(text: String, custom: [CustomFood]) -> some View {
        if !custom.isEmpty {
            Section {
                sectionHeaderRow("Mes aliments")
                ForEach(custom) { food in
                    foodRow(food.item, highlight: text)
                }
            }
            .listSectionSeparator(.hidden)
        }

        if FoodDatabase.shared.isAvailable {
            Section {
                resultsHeaderRow
                ForEach(results) { item in
                    foodRow(item, highlight: text)
                }
            }
            .listSectionSeparator(.hidden)
        }
    }

    /// "OPENNUTRITION · 60 RÉSULTATS" line above the database results (hairline below).
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

    private func sectionHeaderRow(_ title: String) -> some View {
        SearchSectionHeader(title: title)
            .modifier(SearchHeaderRowStyle())
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

    private func foodRow(_ item: FoodItem, highlight: String? = nil) -> some View {
        HStack(spacing: 10) {
            FoodRowView(item: item, highlight: highlight)
            Button {
                activeSheet = .add(item)
            } label: {
                SearchAddCircle()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Ajouter au journal")
        }
        .background {
            // Hidden link: the whole row pushes the detail, without the disclosure chevron.
            // Wrapper so FoodDetailView's init (and its @Query) only runs when pushed,
            // not for every visible row on every keystroke.
            NavigationLink {
                SearchDetailDestination(item: item, context: context, onLogged: closeSheetAfterLogging)
            } label: {
                EmptyView()
            }
            .opacity(0)
        }
        .swipeActions(edge: .leading) {
            Button {
                activeSheet = .add(item)
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
            .tint(Theme.textQuaternary)
        }
        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.separator)
    }

    // MARK: Actions

    private func runSearch(_ key: SearchQueryKey) async {
        guard !key.text.isEmpty else {
            results = []
            searchedText = ""
            isSearching = false
            return
        }
        if !isSearching { isSearching = true }
        // Debounce typing (the task is cancelled on every keystroke); a filter change on
        // the text already searched runs immediately.
        if key.text != searchedText {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
        }
        var found: [FoodItem] = []
        if FoodDatabase.shared.isAvailable {
            let text = key.text
            let kinds = key.filter.kinds
            // Lexicon rewrite, SQLite query, ranking and Food → FoodItem conversion all run
            // off the main thread.
            found = await Task.detached(priority: .userInitiated) { () -> [FoodItem] in
                let rewritten = FrenchFoodLexicon.rewritingPhrases(text)
                return FoodDatabase.shared.search(rewritten, kinds: kinds, limit: 60).map { $0.item }
            }.value
        }
        if Task.isCancelled { return }
        results = found
        searchedText = key.text
        isSearching = false
    }

    /// When presented as a sheet, closes the whole search after logging from a pushed screen.
    private var closeSheetAfterLogging: (() -> Void)? {
        guard isSheet else { return nil }
        let dismissSearch = self.dismiss
        return { dismissSearch() }
    }

    private func sheetDismissed() {
        if dismissAfterSheet {
            dismissAfterSheet = false
            dismiss()
        }
    }
}

// MARK: - Private helpers

/// Defers building `FoodDetailView` until the row is actually pushed.
private struct SearchDetailDestination: View {
    let item: FoodItem
    let context: LogContext
    let onLogged: (() -> Void)?

    var body: some View {
        FoodDetailView(item: item, context: context, onLogged: onLogged)
    }
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
    case scanner
    case quickAdd
    case add(FoodItem)

    var id: String {
        switch self {
        case .scanner: "scanner"
        case .quickAdd: "quickAdd"
        case .add(let item): "add:\(item.id)"
        }
    }
}

private struct SearchShortcutLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Section title row: Theme.label, uppercase, textTertiary.
private struct SearchSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.label)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// List row style of the in-list section headers (no top hairline, hairline below).
private struct SearchHeaderRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Theme.background)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparatorTint(Theme.separator)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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

/// Trailing outlined "+" circle of a result row.
private struct SearchAddCircle: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 30, height: 30)
            .overlay {
                Circle().strokeBorder(Theme.textQuaternary, lineWidth: Theme.hairline)
            }
            .contentShape(Circle())
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
