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
                ContentUnavailableView(
                    "Aucun aliment",
                    systemImage: "fork.knife",
                    description: Text("Ajoutez des aliments au journal pour voir le détail de vos nutriments.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        energyCard
                        NutritionTableView(values: totals, showDailyPercent: true)
                            .padding()
                            .background(Theme.cardBackground,
                                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        Text("Les pourcentages se basent sur les apports de référence pour un adulte. Les valeurs inconnues de certains aliments ne sont pas comptées.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        AttributionFooter(includeOpenFoodFacts: true)
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Nutriments")
        .navigationBarTitleDisplayMode(.inline)
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

    private var energyCard: some View {
        let macroKcal = parts.reduce(0) { $0 + $1.kcal }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TodayDayFormat.title(for: day))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Formatters.kcal(totals.calories))
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Objectif")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatters.kcal(targets.calories))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }

            if macroKcal > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts) { part in
                            Rectangle()
                                .fill(Theme.color(for: part.key))
                                .frame(width: max(0, (geo.size.width - 4) * part.kcal / macroKcal))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())

                HStack(alignment: .top) {
                    ForEach(parts) { part in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.color(for: part.key))
                                    .frame(width: 8, height: 8)
                                Text(part.key.label)
                                    .font(.caption.weight(.semibold))
                            }
                            Text(Formatters.amount(part.grams, of: part.key))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Text("\(Formatters.percent(part.kcal / macroKcal)) de l'énergie")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding()
        .background(Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
