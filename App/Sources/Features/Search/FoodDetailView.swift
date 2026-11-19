import SwiftData
import SwiftUI

/// Detail of a food: header, per-serving / per-100 g toggle, macro summary, full nutrition
/// table, favorite toggle and "Ajouter au journal". Pushed view (no NavigationStack).
struct FoodDetailView: View {
    let item: FoodItem
    let context: LogContext
    /// Called after the add sheet closed following a successful log (e.g. to close a search sheet).
    let onLogged: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query private var favoriteMatches: [FavoriteFood]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var basis: FoodDetailBasis
    @State private var showAddSheet = false
    @State private var favoriteToggles = 0
    @State private var loggedCount = 0
    @State private var didLog = false

    init(item: FoodItem, context: LogContext, onLogged: (() -> Void)? = nil) {
        self.item = item
        self.context = context
        self.onLogged = onLogged
        let key = item.id
        _favoriteMatches = Query(filter: #Predicate<FavoriteFood> { $0.key == key })
        _basis = State(initialValue: (item.servingGrams ?? 0) > 0 ? .serving : .hundred)
    }

    private var isFavorite: Bool { !favoriteMatches.isEmpty }
    private var hasServing: Bool { (item.servingGrams ?? 0) > 0 }

    private var referenceGrams: Double {
        if basis == .serving, let g = item.servingGrams, g > 0 { return g }
        return 100
    }

    private var values: NutrientValues { item.per100.forGrams(referenceGrams) }

    private var referenceDescription: String {
        let g = "\(Formatters.number(referenceGrams, maxFractionDigits: 0)) \(item.unitSymbol)"
        if basis == .serving, hasServing {
            if let label = item.servingLabel { return "Pour \(label) (\(g))" }
            return "Pour 1 portion (\(g))"
        }
        return "Pour \(g)"
    }

    private var showsDatasetAttribution: Bool {
        item.source == .openNutrition || item.source == .openFoodFacts
    }

    var body: some View {
        List {
            headerSection

            if hasServing {
                Section {
                    basisPicker
                }
            }

            Section {
                SearchMacroColumns(values: values, targets: profiles.first?.targets)
                    .listRowBackground(Theme.card)
            } header: {
                Text(referenceDescription)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section {
                NutritionTableView(values: values)
                    .listRowBackground(Theme.card)
            } header: {
                Text("Valeurs nutritionnelles")
                    .foregroundStyle(Theme.textSecondary)
            }

            if showsDatasetAttribution {
                AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .themedBackground()
        .navigationTitle("Aliment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteButton
            }
        }
        .safeAreaInset(edge: .bottom) {
            addButton
        }
        .sheet(isPresented: $showAddSheet, onDismiss: {
            if didLog {
                didLog = false
                onLogged?()
            }
        }) {
            AddEntrySheet(item: item, context: context, onLogged: {
                loggedCount += 1
                didLog = true
            })
        }
        .sensoryFeedback(.selection, trigger: favoriteToggles)
        .sensoryFeedback(.success, trigger: loggedCount)
    }

    private var basisPicker: some View {
        Picker("Base", selection: $basis) {
            Text("Par portion").tag(FoodDetailBasis.serving)
            Text("Pour 100 \(item.unitSymbol)").tag(FoodDetailBasis.hundred)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var favoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Theme.fat : Theme.accent)
        }
        .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Ajouter au journal", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            Theme.background.ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    FoodIconView(item: item, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let brand = item.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                badges
                headerFacts
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if let kind = item.kind {
                FoodDetailBadge(text: kind.label, systemImage: kind.systemImage)
            }
            if item.source != .openNutrition {
                FoodDetailBadge(text: item.source.label, systemImage: sourceIcon)
            }
            if item.isLiquid {
                FoodDetailBadge(text: "Liquide", systemImage: "drop")
            }
        }
    }

    private var headerFacts: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasServing, let grams = item.servingGrams {
                Label {
                    Text("Portion : \(item.servingLabel ?? "1 portion") (\(Formatters.number(grams, maxFractionDigits: 0)) \(item.unitSymbol))")
                } icon: {
                    Image(systemName: "scalemass")
                }
            }
            if let pkg = item.packageGrams, pkg > 0 {
                Label {
                    Text("Emballage : \(Formatters.number(pkg, maxFractionDigits: 0)) \(item.unitSymbol)")
                } icon: {
                    Image(systemName: "shippingbox")
                }
            }
            if let ean = item.ean, !ean.isEmpty {
                Label {
                    Text(ean).monospacedDigit()
                } icon: {
                    Image(systemName: "barcode")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    private var sourceIcon: String {
        switch item.source {
        case .custom: "person.crop.circle"
        case .openFoodFacts: "barcode.viewfinder"
        case .quickAdd: "bolt"
        case .openNutrition: "leaf"
        }
    }

    // MARK: Actions

    private func toggleFavorite() {
        if favoriteMatches.isEmpty {
            modelContext.insert(FavoriteFood(item: item))
        } else {
            for favorite in favoriteMatches { modelContext.delete(favorite) }
        }
        try? modelContext.save()
        favoriteToggles += 1
    }
}

/// Which quantity the detail screen displays values for.
private enum FoodDetailBasis: Hashable {
    case serving, hundred
}

/// Pill badge used in the detail header.
private struct FoodDetailBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.card, in: Capsule())
            .foregroundStyle(Theme.textSecondary)
    }
}

/// 4-column summary (Kcal / Prot. / Gluc. / Lip.), same spirit as the journal header:
/// big colored numbers and thin bars showing the share of the daily targets when a profile
/// exists (`targets`), otherwise the share of energy (kcal column: % of the 2 000 kcal reference).
/// Shared by FoodDetailView and AddEntrySheet.
struct SearchMacroColumns: View {
    let values: NutrientValues
    let targets: NutrientValues?

    private static let keys: [NutrientKey] = [.calories, .protein, .carbohydrates, .totalFat]

    private var energyFromMacros: Double {
        values.protein * 4 + values.carbs * 4 + values.fat * 9
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(SearchMacroColumns.keys) { key in
                SearchMacroColumn(
                    key: key,
                    amount: values.value(key),
                    fraction: fraction(for: key),
                    caption: caption(for: key)
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func targetValue(for key: NutrientKey) -> Double? {
        guard let targets, let target = targets[key], target > 0 else { return nil }
        return target
    }

    private func fraction(for key: NutrientKey) -> Double {
        if let target = targetValue(for: key) {
            return values.value(key) / target
        }
        if key == .calories {
            guard let ref = NutrientKey.calories.dailyReference, ref > 0 else { return 0 }
            return values.calories / ref
        }
        guard energyFromMacros > 0 else { return 0 }
        let perGram: Double = key == .totalFat ? 9 : 4
        return values.value(key) * perGram / energyFromMacros
    }

    private func caption(for key: NutrientKey) -> String {
        let percent = Formatters.percent(fraction(for: key))
        if targetValue(for: key) != nil { return "\(percent) obj." }
        if key == .calories { return "\(percent) AR" }
        return energyFromMacros > 0 ? "\(percent) énergie" : "—"
    }
}

private struct SearchMacroColumn: View {
    let key: NutrientKey
    let amount: Double
    let fraction: Double
    let caption: String

    private var title: String {
        key == .calories ? "Kcal" : key.shortLabel
    }

    private var number: String {
        Formatters.number(amount, maxFractionDigits: key == .calories || amount >= 10 ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(number)
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(Theme.color(for: key))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if key != .calories {
                    Text("g")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            SearchThinBar(fraction: fraction, color: Theme.color(for: key))
            Text(caption)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 3 pt bar drawn on a card (track = hairline color so it stays visible on `Theme.card`).
private struct SearchThinBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separator)
                Capsule()
                    .fill(fraction > 1.05 ? Theme.overTarget : color)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: 3)
        .animation(.snappy, value: fraction)
    }
}
