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
        detailList
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

    private var detailList: some View {
        List {
            headerSection

            if hasServing {
                basisPicker
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    .modifier(FoodDetailRowStyle())
            }

            FoodDetailSectionTitle(title: referenceDescription)
                .modifier(FoodDetailRowStyle())

            summaryRow

            FoodDetailSectionTitle(title: "Valeurs nutritionnelles")
                .padding(.top, 12)
                .modifier(FoodDetailRowStyle())

            NutritionTableView(values: values)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                .modifier(FoodDetailRowStyle())

            if showsDatasetAttribution {
                AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
                    .modifier(FoodDetailRowStyle())
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .themedBackground()
    }

    /// 4-column summary between two full-width hairlines (same look as the journal header).
    private var summaryRow: some View {
        SearchMacroColumns(values: values, targets: profiles.first?.targets)
            .padding(.horizontal, 6)
            .overlay(alignment: .top) { FoodDetailHairline() }
            .overlay(alignment: .bottom) { FoodDetailHairline() }
            .listRowInsets(EdgeInsets())
            .modifier(FoodDetailRowStyle())
    }

    /// "Par portion" / "Pour 100 g" chips (white fill when selected, outline otherwise).
    private var basisPicker: some View {
        HStack(spacing: 6) {
            basisChip(.serving, title: "Par portion")
            basisChip(.hundred, title: "Pour 100 \(item.unitSymbol)")
            Spacer(minLength: 0)
        }
        .sensoryFeedback(.selection, trigger: basis)
    }

    private func basisChip(_ value: FoodDetailBasis, title: String) -> some View {
        Button {
            basis = value
        } label: {
            FoodDetailChip(title: title, isSelected: basis == value)
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(basis == value ? AccessibilityTraits.isSelected : [])
    }

    private var favoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Theme.carbs : Theme.textPrimary)
        }
        .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Ajouter au journal", systemImage: "plus")
                .font(Theme.headline)
                .foregroundStyle(Theme.onAccent)
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
        .overlay(alignment: .top) { FoodDetailHairline() }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                FoodIconView(item: item, size: 64)
                headerTitles
            }
            badges
            headerFacts
        }
        .padding(.top, 8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
        .modifier(FoodDetailRowStyle())
    }

    private var headerTitles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let brand = item.brand, !brand.isEmpty {
                Text(brand)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if item.kind != nil || item.source != .openNutrition || item.isLiquid {
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
        .font(Theme.caption)
        .foregroundStyle(Theme.textTertiary)
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

/// Outlined pill badge used in the detail header.
private struct FoodDetailBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(Theme.font(12, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .overlay {
                Capsule().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
            }
    }
}

/// Basis chip: white fill + near-black text when selected, 1 pt outline otherwise.
private struct FoodDetailChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
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

/// Section title row: Theme.label, uppercase, textTertiary.
private struct FoodDetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.label)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Full-width hairline (Theme.separator).
private struct FoodDetailHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
    }
}

/// Plain list row on the app background, without system separators (hairlines are drawn
/// explicitly where the design wants them).
private struct FoodDetailRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Theme.background)
            .listRowSeparator(.hidden)
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
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(SearchMacroColumns.keys.enumerated()), id: \.element) { index, key in
                SearchMacroColumn(
                    key: key,
                    amount: values.value(key),
                    fraction: fraction(for: key),
                    caption: caption(for: key),
                    showsDivider: index > 0
                )
            }
        }
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

/// One column: tiny uppercase label in the macro color, big number (textPrimary), 2 pt bar,
/// caption in textTertiary; a vertical hairline on its leading edge (except the first).
private struct SearchMacroColumn: View {
    let key: NutrientKey
    let amount: Double
    let fraction: Double
    let caption: String
    let showsDivider: Bool

    private var title: String {
        key == .calories ? "Kcal" : key.shortLabel
    }

    private var number: String {
        Formatters.number(amount, maxFractionDigits: key == .calories || amount >= 10 ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Theme.label)
                .tracking(0.6)
                .foregroundStyle(Theme.color(for: key))
                .lineLimit(1)
            valueLine
                .padding(.top, 6)
            SearchThinBar(fraction: fraction, color: Theme.color(for: key))
                .padding(.top, 8)
            Text(caption)
                .font(Theme.font(11, .regular, relativeTo: .caption2))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if showsDivider {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: Theme.hairline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var valueLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(number)
                .font(Theme.numberLarge)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if key != .calories {
                Text("g")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// 2 pt bar (macro color on separatorStrong), as in the journal header.
private struct SearchThinBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separatorStrong)
                Capsule()
                    .fill(fraction > 1.05 ? Theme.overTarget : color)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: 2)
        .animation(.snappy, value: fraction)
    }
}
