import SwiftData
import SwiftUI

// MARK: - Summary card

/// Calorie ring + macro bars for the day.
struct TodaySummaryCard: View {
    let totals: NutrientValues
    let targets: TodayTargets
    var isEmpty: Bool = false

    private var consumed: Double { totals.calories }
    private var remaining: Double { targets.calories - consumed }
    private var progress: Double { targets.calories > 0 ? consumed / targets.calories : 0 }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                ring
                VStack(alignment: .leading, spacing: 10) {
                    stat(title: "Consommé", value: Formatters.kcal(consumed),
                         systemImage: "fork.knife", color: Theme.calories)
                    stat(title: "Objectif", value: Formatters.kcal(targets.calories),
                         systemImage: "target", color: .secondary)
                    stat(title: remaining >= 0 ? "Restant" : "Dépassement",
                         value: Formatters.kcal(abs(remaining)),
                         systemImage: remaining >= 0 ? "flame" : "exclamationmark.triangle",
                         color: remaining >= 0 ? Theme.fiber : .red)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                TodayMacroColumn(key: .protein, value: totals.protein, target: targets.protein)
                TodayMacroColumn(key: .carbohydrates, value: totals.carbs, target: targets.carbs)
                TodayMacroColumn(key: .totalFat, value: totals.fat, target: targets.fat)
                TodayMacroColumn(key: .dietaryFiber, value: totals.value(.dietaryFiber), target: targets.fiber)
            }

            if isEmpty {
                Label("Rien de noté pour l'instant. Touchez « + » pour ajouter un aliment.",
                      systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var ring: some View {
        ZStack {
            RingView(progress: progress, color: Theme.calories, lineWidth: 12)
            VStack(spacing: 0) {
                Text(Formatters.number(abs(remaining), maxFractionDigits: 0))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(remaining >= 0 ? "kcal restantes" : "kcal en trop")
                    .font(.caption2)
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: 118, height: 118)
        .animation(.snappy, value: consumed)
    }

    private func stat(title: String, value: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }
}

/// One macro: label, progress bar and "x / y g".
struct TodayMacroColumn: View {
    let key: NutrientKey
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key.shortLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.color(for: key))
                .lineLimit(1)
            ProgressBar(value: value, total: target, color: Theme.color(for: key))
            Text("\(Formatters.number(value, maxFractionDigits: 0)) / \(Formatters.number(target, maxFractionDigits: 0)) g")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.label) : \(Formatters.number(value, maxFractionDigits: 0)) sur \(Formatters.number(target, maxFractionDigits: 0)) grammes")
    }
}

// MARK: - Water card

struct TodayWaterCard: View {
    let totalMl: Double
    let targetMl: Double
    let canUndo: Bool
    let onAdd: (Double) -> Void
    let onUndo: () -> Void

    private var dropCount: Int {
        guard targetMl > 0 else { return 8 }
        return min(max(Int((targetMl / 250).rounded(.up)), 1), 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Theme.water)
                Text("Eau")
                    .font(.headline)
                Spacer()
                Text("\(liters(totalMl)) / \(liters(targetMl)) L")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(totalMl >= targetMl && targetMl > 0 ? Theme.water : Color.secondary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 4) {
                ForEach(0..<dropCount, id: \.self) { index in
                    let threshold = targetMl / Double(dropCount) * Double(index + 1)
                    Image(systemName: "drop.fill")
                        .font(.title3)
                        .foregroundStyle(totalMl + 0.5 >= threshold ? Theme.water : Theme.water.opacity(0.18))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(totalMl + 0.5 >= threshold ? 1 : 0.85)
                }
            }
            .animation(.snappy, value: totalMl)
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                Button {
                    onAdd(250)
                } label: {
                    Label("250 ml", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.water)

                Button {
                    onAdd(500)
                } label: {
                    Label("500 ml", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.water)

                Spacer()

                Button {
                    onUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!canUndo)
                .accessibilityLabel("Annuler le dernier ajout d'eau")
            }
        }
        .padding(.vertical, 6)
    }

    private func liters(_ ml: Double) -> String {
        Formatters.number(ml / 1000, maxFractionDigits: 2)
    }
}

// MARK: - Entry row

struct TodayEntryRow: View {
    let entry: JournalEntry

    var body: some View {
        let values = entry.nutrients
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if entry.source == .quickAdd {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.calories)
                    }
                    Text(entry.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                TodayMacroLine(values: values)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Formatters.number(values.calories, maxFractionDigits: 0))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Modifier la quantité")
    }

    private var detailLine: String {
        if let brand = entry.brand, !brand.isEmpty, entry.source != .quickAdd {
            return "\(entry.quantityDescription) · \(brand)"
        }
        return entry.quantityDescription
    }
}

/// "● 12 g ● 30 g ● 5 g" for protein / carbs / fat.
struct TodayMacroLine: View {
    let values: NutrientValues

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NutrientKey.macros) { key in
                HStack(spacing: 3) {
                    Circle()
                        .fill(Theme.color(for: key))
                        .frame(width: 6, height: 6)
                    Text("\(String(key.shortLabel.prefix(1))) \(Formatters.number(values.value(key), maxFractionDigits: 0)) g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
