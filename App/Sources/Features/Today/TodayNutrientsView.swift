import SwiftUI

/// Pushed screen: every nutrient summed over the day.
struct TodayNutrientsView: View {
    let day: Date
    let totals: NutrientValues
    let targets: TodayTargets
    let entryCount: Int

    var body: some View {
        Group {
            if entryCount == 0 {
                ThemedUnavailableView(
                    title: "Aucun aliment",
                    systemImage: "fork.knife",
                    description: "Ajoutez des aliments au journal pour voir le détail de vos nutriments."
                )
            } else {
                content
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle("Nutriments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                energySection
                    .padding(16)
                TodayHairline()
                sectionHeader("Détail du jour")
                NutritionTableView(values: totals, showDailyPercent: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                TodayHairline()
                Text("Les pourcentages se basent sur les apports de référence pour un adulte. Les valeurs inconnues de certains aliments ne sont pas comptées.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                AttributionFooter(includeOpenFoodFacts: true)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.label)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    // MARK: - Energy split

    private struct Part: Identifiable {
        let key: NutrientKey
        let grams: Double
        let kcal: Double
        var id: String { key.rawValue }
    }

    private var parts: [Part] {
        [
            Part(key: .protein, grams: totals.protein, kcal: totals.protein * 4),
            Part(key: .carbohydrates, grams: totals.carbs, kcal: totals.carbs * 4),
            Part(key: .totalFat, grams: totals.fat, kcal: totals.fat * 9),
        ]
    }

    private var energySection: some View {
        let macroKcal = parts.reduce(0) { $0 + $1.kcal }
        return VStack(alignment: .leading, spacing: 14) {
            energyHeadline
            if macroKcal > 0 {
                splitBar(macroKcal: macroKcal)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(parts) { part in
                        partColumn(part, macroKcal: macroKcal)
                    }
                }
            }
        }
    }

    private var energyHeadline: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(TodayDayFormat.title(for: day).uppercased())
                    .font(Theme.label)
                    .tracking(0.6)
                    .foregroundStyle(Theme.calories)
                Text(Formatters.kcal(totals.calories))
                    .font(Theme.font(28, .bold, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("OBJECTIF")
                    .font(Theme.label)
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                Text(Formatters.kcal(targets.calories))
                    .font(Theme.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textBody)
            }
        }
    }

    private func splitBar(macroKcal: Double) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(parts) { part in
                    Rectangle()
                        .fill(Theme.color(for: part.key))
                        .frame(width: max(0, (geo.size.width - 4) * part.kcal / macroKcal))
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }

    private func partColumn(_ part: Part, macroKcal: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(part.key.label.uppercased())
                .font(Theme.label)
                .tracking(0.6)
                .foregroundStyle(Theme.color(for: part.key))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(Formatters.amount(part.grams, of: part.key))
                .font(Theme.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("\(Formatters.percent(part.kcal / macroKcal)) de l'énergie")
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
