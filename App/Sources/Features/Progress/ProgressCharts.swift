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
                    .foregroundStyle(Theme.separator)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Value y-axis (trailing) with dark grid lines and secondary labels.
    func progressValueAxis() -> some View {
        chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.separator)
                AxisValueLabel()
                    .foregroundStyle(Theme.textSecondary)
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
        .foregroundStyle(Theme.textSecondary)
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
                        .foregroundStyle(Theme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                ForEach(points) { point in
                    PointMark(x: .value("Date", point.date),
                              y: .value("Poids", point.kg))
                        .foregroundStyle(Theme.weight.opacity(0.4))
                        .symbolSize(18)
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
            .progressValueAxis()
            .frame(height: 200)

            HStack(spacing: 12) {
                ProgressLegendItem(color: Theme.weight.opacity(0.4), text: "Pesées")
                ProgressLegendItem(color: Theme.weight, text: "Tendance 7 j")
                if targetKg != nil {
                    ProgressLegendItem(color: Theme.textSecondary, text: "Objectif", dashed: true)
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
        let day = Calendar.current.startOfDay(for: selectedDate)
        return stats.first { $0.day == day }
    }

    private var yMax: Double {
        let maxValue = max(stats.map(\.calories).max() ?? 0, target)
        return max(maxValue * 1.1, 100)
    }

    private func barColor(_ stat: ProgressDayStat) -> Color {
        if target > 0 && stat.calories > target * 1.1 { return Theme.overTarget }
        return Theme.calories
    }

    var body: some View {
        // Resolved once per evaluation (it was recomputed for every bar, O(n²) while dragging).
        let selected = selectedStat
        return VStack(alignment: .leading, spacing: 10) {
            header(selected: selected)

            Chart {
                ForEach(stats) { stat in
                    BarMark(x: .value("Jour", stat.day, unit: .day),
                            y: .value("Calories", stat.calories))
                        .foregroundStyle(barColor(stat))
                        .cornerRadius(3)
                        .opacity(selected == nil || selected?.day == stat.day ? 1 : 0.35)
                }
                if target > 0 {
                    RuleMark(y: .value("Objectif", target))
                        .foregroundStyle(Theme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: startDate...endDate)
            .chartYScale(domain: 0...yMax)
            .chartXSelection(value: $selectedDate)
            .progressDateAxis()
            .progressValueAxis()
            .frame(height: 190)

            HStack(spacing: 12) {
                ProgressLegendItem(color: Theme.calories, text: "Consommé")
                if target > 0 {
                    ProgressLegendItem(color: Theme.textSecondary, text: "Objectif", dashed: true)
                }
                ProgressLegendItem(color: Theme.overTarget, text: "> 110 %")
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func header(selected: ProgressDayStat?) -> some View {
        if let stat = selected {
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.dayTitle(stat.day))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(stat.isLogged ? Formatters.kcal(stat.calories) : "Aucune saisie")
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Moyenne par jour suivi")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Formatters.kcal(average))
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    if target > 0 {
                        Text("/ \(Formatters.kcal(target))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
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
        VStack(alignment: .leading, spacing: 8) {
            chart
            HStack(spacing: 12) {
                ProgressLegendItem(color: Theme.protein, text: progressMacroProteinLabel)
                ProgressLegendItem(color: Theme.carbs, text: progressMacroCarbsLabel)
                ProgressLegendItem(color: Theme.fat, text: progressMacroFatLabel)
            }
        }
        .padding(.vertical, 6)
    }

    private var chart: some View {
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
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.separator)
                AxisValueLabel {
                    if let grams = value.as(Double.self) {
                        Text("\(Formatters.number(grams, maxFractionDigits: 0)) g")
                    }
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .progressDateAxis()
        .frame(height: 200)
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
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Formatters.number(grams, maxFractionDigits: 0)) g")
                    .font(.body.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                if target > 0 {
                    Text("/ \(Formatters.number(target, maxFractionDigits: 0)) g")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(Formatters.percent(energyShare))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            ProgressBar(value: grams, total: target, color: color)
        }
        .padding(.vertical, 2)
    }
}
