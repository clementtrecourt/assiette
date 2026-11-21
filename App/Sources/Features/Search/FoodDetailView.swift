import SwiftData
import SwiftUI

/// Detail of a food: header, per-serving / per-100 g toggle, macro summary (kcal + G / P / L
/// with the share of energy), full nutrition table, favorite toggle and "Ajouter au journal".
/// Pushed view (no NavigationStack).
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if hasServing {
                    basisPicker
                        .padding(.top, 16)
                }

                FoodDetailSectionTitle(title: referenceDescription)
                    .padding(.top, 14)

                SearchMacroColumns(values: values, targets: profiles.first?.targets)
                    .padding(.vertical, 14)
                    .themedCard()

                FoodDetailSectionTitle(title: "Valeurs nutritionnelles")
                    .padding(.top, 18)

                NutritionTableView(values: values)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .themedCard()

                if showsDatasetAttribution {
                    AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Aliment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteButton
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // What is left for the day stays in view while reading the food.
            DayRemainingView(day: context.day, layout: .row)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .background(Theme.background)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addButton
        }
        .slideCover(isPresented: $showAddSheet, onDismiss: {
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                FoodIconView(item: item, size: 56)
                VStack(alignment: .leading, spacing: 3) {
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
                Spacer(minLength: 0)
            }
            badges
            headerFacts
        }
        .padding(.top, 8)
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

    @ViewBuilder
    private var headerFacts: some View {
        let hasPackage = (item.packageGrams ?? 0) > 0
        let hasEan = !(item.ean ?? "").isEmpty
        if hasServing || hasPackage || hasEan {
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
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private var sourceIcon: String {
        switch item.source {
        case .custom: "person.crop.circle"
        case .openFoodFacts: "barcode.viewfinder"
        case .quickAdd: "bolt"
        case .openNutrition: "leaf"
        }
    }

    /// "Par portion" / "Pour 100 g" segmented chips (white fill when selected, raised2 otherwise).
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
        .buttonStyle(.plain)
        .accessibilityAddTraits(basis == value ? AccessibilityTraits.isSelected : [])
    }

    private var favoriteButton: some View {
        Button {
            toggleFavorite()
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? Theme.protein : Theme.textPrimary)
        }
        .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Ajouter au journal", systemImage: "plus")
                .font(Theme.font(15, .bold, relativeTo: .headline))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

/// Basis chip: white fill + near-black text when selected, raised2 otherwise.
private struct FoodDetailChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textBody)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isSelected ? Theme.accent : Theme.raised2,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Section title: Theme.label, uppercase, textTertiary.
private struct FoodDetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.label)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// Macro summary: big kcal, then G / P / L (always in that order) with a small pill showing
/// the share of the food's energy from each macro, and a caption with the share of the daily
/// target when a profile exists (`targets`).
struct SearchMacroColumns: View {
    let values: NutrientValues
    let targets: NutrientValues?

    /// Energy used for the % pills: kcal, or the macro sum when kcal is unknown.
    private var energy: Double {
        if values.calories > 0 { return values.calories }
        return values.carbs * 4 + values.protein * 4 + values.fat * 9
    }

    private func energyShare(_ key: NutrientKey) -> String {
        guard energy > 0 else { return "– %" }
        let perGram: Double = key == .totalFat ? 9 : 4
        return Formatters.percent(min(values.value(key) * perGram / energy, 1))
    }

    private func targetCaption(_ key: NutrientKey) -> String? {
        guard let targets, let target = targets[key], target > 0 else { return nil }
        return "\(Formatters.percent(values.value(key) / target)) obj."
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 2) {
                Text(Formatters.number(values.calories, maxFractionDigits: 0))
                    .font(Theme.font(32, .bold, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(targetCaption(.calories).map { "kcal · \($0)" } ?? "kcal")
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            ForEach(Theme.macroOrder, id: \.self) { key in
                VStack(spacing: 2) {
                    Text(energyShare(key))
                        .font(Theme.font(11, .bold, relativeTo: .caption2))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color(for: key))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.color(for: key).opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(.bottom, 4)
                    Text(Formatters.number(values.value(key), maxFractionDigits: 1))
                        .font(Theme.font(19, .bold, relativeTo: .title3))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(key.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let caption = targetCaption(key) {
                        Text(caption)
                            .font(Theme.font(10, .regular, relativeTo: .caption2))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textQuaternary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.snappy, value: values)
    }
}
