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
                    Picker("Base", selection: $basis) {
                        Text("Par portion").tag(FoodDetailBasis.serving)
                        Text("Pour 100 \(item.unitSymbol)").tag(FoodDetailBasis.hundred)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                FoodDetailMacroSummary(values: values)
            } header: {
                Text(referenceDescription)
            }

            Section {
                NutritionTableView(values: values)
            } header: {
                Text("Valeurs nutritionnelles")
            }

            if showsDatasetAttribution {
                AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Aliment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : Theme.accent)
                }
                .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showAddSheet = true
            } label: {
                Label("Ajouter au journal", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
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

    // MARK: Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
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
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
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

/// Capsule badge used in the detail header.
private struct FoodDetailBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(Theme.accent)
    }
}

/// Calories + protein / carbs / fat with share of energy and a stacked energy bar.
private struct FoodDetailMacroSummary: View {
    let values: NutrientValues

    private var energyFromMacros: Double {
        values.protein * 4 + values.carbs * 4 + values.fat * 9
    }

    private func share(_ kcal: Double) -> Double {
        energyFromMacros > 0 ? kcal / energyFromMacros : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Formatters.number(values.calories, maxFractionDigits: 0))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.calories)
                Text("kcal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let ref = NutrientKey.calories.dailyReference {
                    Text("\(Formatters.percent(values.calories / ref)) des AR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if energyFromMacros > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(Theme.protein)
                            .frame(width: max(0, geo.size.width * share(values.protein * 4) - 2))
                        Rectangle().fill(Theme.carbs)
                            .frame(width: max(0, geo.size.width * share(values.carbs * 4) - 2))
                        Rectangle().fill(Theme.fat)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            }

            HStack(alignment: .top, spacing: 0) {
                column("Protéines", grams: values.protein, kcal: values.protein * 4, color: Theme.protein)
                column("Glucides", grams: values.carbs, kcal: values.carbs * 4, color: Theme.carbs)
                column("Lipides", grams: values.fat, kcal: values.fat * 9, color: Theme.fat)
            }
        }
        .padding(.vertical, 6)
    }

    private func column(_ title: String, grams: Double, kcal: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(Formatters.number(grams, maxFractionDigits: 1)) g")
                .font(.headline.monospacedDigit())
            Text(energyFromMacros > 0 ? Formatters.percent(share(kcal)) : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
