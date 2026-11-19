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
    @State private var results: [Food] = []
    @State private var searchedText = ""
    @State private var isSearching = false
    @State private var activeSheet: SearchSheet?
    @State private var dismissAfterSheet = false
    @State private var loggedCount = 0

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
    private var recentItems: [FoodItem] {
        var seen = Set<String>()
        var items: [FoodItem] = []
        for entry in recentEntries {
            let item = entry.item
            guard seen.insert(item.id).inserted else { continue }
            items.append(item)
            if items.count >= 20 { break }
        }
        return items
    }

    /// Custom foods whose name/brand contains every query word.
    private var matchingCustomFoods: [CustomFood] {
        guard filter == .all else { return [] }
        let words = FoodDatabase.tokens(of: trimmedQuery)
            .filter { !FrenchFoodLexicon.stopWords.contains($0) }
        guard !words.isEmpty else { return [] }
        return customFoods.filter { food in
            let haystack = FoodDatabase.tokens(of: food.name + " " + (food.brand ?? "")).joined(separator: " ")
            return words.allSatisfy { haystack.contains($0) }
        }
        .prefix(10)
        .map { $0 }
    }

    // MARK: Body

    var body: some View {
        List {
            if !FoodDatabase.shared.isAvailable {
                databaseErrorSection
            }
            if trimmedQuery.isEmpty {
                emptyQueryContent
            } else {
                searchContent
            }
            AttributionFooter()
                .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .themedBackground()
        .navigationTitle(isSheet ? "Ajouter un aliment" : "Ajouter")
        .navigationBarTitleDisplayMode(isSheet ? .inline : .large)
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Rechercher un aliment")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .overlay {
            if !trimmedQuery.isEmpty, !isSearching, searchedText == trimmedQuery,
               results.isEmpty, matchingCustomFoods.isEmpty {
                ContentUnavailableView {
                    Label("Aucun résultat", systemImage: "magnifyingglass")
                } description: {
                    Text("Aucun aliment ne correspond à « \(trimmedQuery) ». Essayez un autre mot, en français ou en anglais.")
                } actions: {
                    Button("Ajout rapide") { activeSheet = .quickAdd }
                        .buttonStyle(.bordered)
                }
            }
        }
        .toolbar { toolbarContent }
        .task(id: searchKey) { await runSearch(searchKey) }
        .onChange(of: initialContext) { _, newValue in context = newValue }
        .sheet(item: $activeSheet, onDismiss: sheetDismissed) { sheet in
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
        .sensoryFeedback(.success, trigger: loggedCount)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSheet {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") { dismiss() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
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
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityLabel("Repas : \(context.meal.label)")
        }
    }

    // MARK: Sections

    private var databaseErrorSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Base d'aliments indisponible")
                        .font(.subheadline.weight(.semibold))
                    Text(FoodDatabase.shared.openError ?? "La base OpenNutrition n'a pas pu être ouverte. Vos aliments personnels restent disponibles.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.overTarget)
            }
            .listRowBackground(Theme.card)
        }
    }

    @ViewBuilder
    private var emptyQueryContent: some View {
        Section {
            Button {
                activeSheet = .scanner
            } label: {
                SearchShortcutLabel(title: "Scanner un code-barres", systemImage: "barcode.viewfinder", color: Theme.accent)
            }
            Button {
                activeSheet = .quickAdd
            } label: {
                SearchShortcutLabel(title: "Ajout rapide", systemImage: "bolt.fill", color: Theme.calories)
            }
            NavigationLink {
                CustomFoodsListView(pickContext: context, onLogged: closeSheetAfterLogging)
            } label: {
                SearchShortcutLabel(title: "Mes aliments", systemImage: "person.crop.circle", color: Theme.fiber)
            }
        } footer: {
            Text("Ajout à : \(context.meal.label) · \(Formatters.dayTitle(context.day).lowercased())")
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.card)
        .listRowSeparatorTint(Theme.separator)

        if !favorites.isEmpty {
            Section {
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
            } header: {
                SearchSectionHeader(title: "Favoris")
            }
        }

        let recents = recentItems
        if !recents.isEmpty {
            Section {
                ForEach(recents) { item in
                    foodRow(item)
                }
            } header: {
                SearchSectionHeader(title: "Récents")
            }
        }

        if favorites.isEmpty && recents.isEmpty {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Recherchez un aliment")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(databaseHint)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var databaseHint: String {
        let count = FoodDatabase.shared.isAvailable ? FoodDatabase.shared.count : 0
        if count > 0 {
            return "Plus de \(Formatters.number(Double(count / 1000 * 1000), maxFractionDigits: 0)) aliments, en français ou en anglais : « poulet », « yaourt grec », « banana »…"
        }
        return "Tapez le nom d'un aliment, en français ou en anglais."
    }

    @ViewBuilder
    private var searchContent: some View {
        Section {
            filterChips
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }

        let custom = matchingCustomFoods
        if !custom.isEmpty {
            Section {
                ForEach(custom) { food in
                    foodRow(food.item)
                }
            } header: {
                SearchSectionHeader(title: "Mes aliments")
            }
        }

        if FoodDatabase.shared.isAvailable {
            Section {
                ForEach(results) { food in
                    foodRow(food.item)
                }
            } header: {
                HStack(spacing: 6) {
                    Text("OpenNutrition")
                    if isSearching {
                        ProgressView().controlSize(.mini)
                    } else if !results.isEmpty {
                        Text("· \(results.count) résultat\(results.count > 1 ? "s" : "")")
                    }
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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

    private func foodRow(_ item: FoodItem) -> some View {
        NavigationLink {
            FoodDetailView(item: item, context: context, onLogged: closeSheetAfterLogging)
        } label: {
            HStack(spacing: 8) {
                FoodRowView(item: item)
                Button {
                    activeSheet = .add(item)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Ajouter au journal")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                activeSheet = .add(item)
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
            .tint(Theme.accent)
        }
        .listRowBackground(Theme.card)
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
        isSearching = true
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        var found: [Food] = []
        if FoodDatabase.shared.isAvailable {
            let text = FrenchFoodLexicon.rewritingPhrases(key.text)
            found = await FoodDatabase.shared.searchAsync(text, kinds: key.filter.kinds, limit: 60)
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
    let color: Color

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.background)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// Section title in the secondary text color.
private struct SearchSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Filter pill: accent fill when selected, card fill otherwise.
private struct SearchFilterPill: View {
    let option: SearchKindFilter
    let isSelected: Bool

    var body: some View {
        Label(option.label, systemImage: option.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
            .background(isSelected ? Theme.accent : Theme.card, in: Capsule())
    }
}
