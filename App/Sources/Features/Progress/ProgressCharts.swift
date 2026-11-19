import Charts
import SwiftUI

private let progressMacroProteinLabel = "Protéines"
private let progressMacroCarbsLabel = "Glucides"
private let progressMacroFatLabel = "Lipides"

private extension View {
    /// Date x-axis with short French day labels.
    func progressDateAxis() -> some View {
        chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}

/// Small legend item (colored dot/line + text).
private struct ProgressLegendItem: View {
    let color: Color
    let text: String
    var dashed = false

    var body: some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: dashed ? 10 : 12, height: dashed ? 2 : 4)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Weight

struct ProgressWeightChart: View {
    let points: [ProgressWeightPoint]
    let targetKg: Double?
    let startDate: Date
    let endDate: Date

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.kg) + points.map(\.average)
        if let targetKg { values.append(targetKg) }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 100
        let pad = max(0.5, (hi - lo) * 0.15)
        return (lo - pad).rounded(.down)...(hi + pad).rounded(.up)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                if let targetKg {
                    RuleMark(y: .value("Objectif", targetKg))
                        .foregroundStyle(Color.green.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date),
                             y: .value("Poids", point.kg),
                             series: .value("Série", "Pesées"))
                        .foregroundStyle(Theme.weight.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Date", point.date),
                              y: .value("Poids", point.kg))
                        .foregroundStyle(Theme.weight.opacity(0.6))
                        .symbolSize(22)
                }
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date),
                             y: .value("Poids", point.average),
                             series: .value("Série", "Moyenne"))
                        .foregroundStyle(Theme.weight)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: startDate...endDate)
            .chartYScale(domain: yDomain)
            .progressDateAxis()
            .frame(height: 200)

            HStack(spacing: 12) {
                ProgressLegendItem(color: Theme.weight.opacity(0.6), text: "Pesées")
                ProgressLegendItem(color: Theme.weight, text: "Moyenne 7 j")
                if targetKg != nil {
                    ProgressLegendItem(color: .green, text: "Objectif", dashed: true)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Calories

struct ProgressCaloriesChart: View {
    let stats: [ProgressDayStat]
    let target: Double
    let startDate: Date
    let endDate: Date

    @State private var selectedDate: Date?

    private var logged: [ProgressDayStat] { stats.filter(\.isLogged) }

    private var average: Double {
        let days = logged
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.calories } / Double(days.count)
    }

    private var selectedStat: ProgressDayStat? {
        guard let selectedDate else { return nil }
        return stats.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDate) }
    }

    private var yMax: Double {
        let maxValue = max(stats.map(\.calories).max() ?? 0, target)
        return max(maxValue * 1.1, 100)
    }

    private func barColor(_ stat: ProgressDayStat) -> Color {
        if target > 0 && stat.calories > target * 1.1 { return .red.opacity(0.85) }
        return Theme.calories
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Chart {
                ForEach(stats) { stat in
                    BarMark(x: .value("Jour", stat.day, unit: .day),
                            y: .value("Calories", stat.calories))
                        .foregroundStyle(barColor(stat))
                        .cornerRadius(3)
                        .opacity(selectedStat == nil || selectedStat?.day == stat.day ? 1 : 0.35)
                }
                if target > 0 {
                    RuleMark(y: .value("Objectif", target))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: startDate...endDate)
            .chartYScale(domain: 0...yMax)
            .chartXSelection(value: $selectedDate)
            .progressDateAxis()
            .frame(height: 190)

            HStack(spacing: 12) {
                ProgressLegendItem(color: Theme.calories, text: "Consommé")
                if target > 0 {
                    ProgressLegendItem(color: .secondary, text: "Objectif", dashed: true)
                }
                ProgressLegendItem(color: .red.opacity(0.85), text: "> 110 %")
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var header: some View {
        if let stat = selectedStat {
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.dayTitle(stat.day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(stat.isLogged ? Formatters.kcal(stat.calories) : "Aucune saisie")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Moyenne par jour suivi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formatters.kcal(average))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    if target > 0 {
                        Text("/ \(Formatters.kcal(target))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Macros

struct ProgressMacrosChart: View {
    let stats: [ProgressDayStat]
    let startDate: Date
    let endDate: Date

    var body: some View {
        Chart {
            ForEach(stats.filter(\.isLogged)) { stat in
                BarMark(x: .value("Jour", stat.day, unit: .day),
                        y: .value("Grammes", stat.protein))
                    .foregroundStyle(by: .value("Macro", progressMacroProteinLabel))
                BarMark(x: .value("Jour", stat.day, unit: .day),
                        y: .value("Grammes", stat.carbs))
                    .foregroundStyle(by: .value("Macro", progressMacroCarbsLabel))
                BarMark(x: .value("Jour", stat.day, unit: .day),
                        y: .value("Grammes", stat.fat))
                    .foregroundStyle(by: .value("Macro", progressMacroFatLabel))
            }
        }
        .chartForegroundStyleScale([
            progressMacroProteinLabel: Theme.protein,
            progressMacroCarbsLabel: Theme.carbs,
            progressMacroFatLabel: Theme.fat,
        ])
        .chartXScale(domain: startDate...endDate)
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let grams = value.as(Double.self) {
                        Text("\(Formatters.number(grams, maxFractionDigits: 0)) g")
                    }
                }
            }
        }
        .progressDateAxis()
        .frame(height: 200)
        .padding(.vertical, 6)
    }
}

/// Average grams of one macro with its target and share of energy.
struct ProgressMacroAverageRow: View {
    let label: String
    let color: Color
    let grams: Double
    let target: Double
    let energyShare: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                Spacer()
                Text("\(Formatters.number(grams, maxFractionDigits: 0)) g")
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)
                if target > 0 {
                    Text("/ \(Formatters.number(target, maxFractionDigits: 0)) g")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(Formatters.percent(energyShare))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            ProgressBar(value: grams, total: target, color: color)
        }
        .padding(.vertical, 2)
    }
}
