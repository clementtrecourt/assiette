import Charts
import SwiftUI

// Charts of the dashboard detail screens (Dépense, Poids tendance, Objectif, Bilan énergétique).

private extension View {
    /// Date x-axis with short French day labels.
    func progressDateAxis() -> some View {
        chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.separator)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Formatters.locale))
                    .font(Theme.font(10, .regular, relativeTo: .caption2))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// Value y-axis (trailing) with dark grid lines and tertiary labels.
    func progressValueAxis() -> some View {
        chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.separator)
                AxisValueLabel()
                    .font(Theme.font(10, .regular, relativeTo: .caption2))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Small legend item (colored line + text).
struct ProgressLegendItem: View {
    let color: Color
    let text: String
    var dashed = false
    var dot = false

    var body: some View {
        HStack(spacing: 5) {
            if dot {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            } else {
                Capsule()
                    .fill(color)
                    .frame(width: dashed ? 10 : 12, height: dashed ? 2 : 3)
            }
            Text(text)
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.textTertiary)
    }
}

/// Range selector chips (30 j / 90 j): selected = white fill + near-black text,
/// unselected = hairline outline + secondary text.
struct ProgressRangeChips: View {
    @Binding var rangeRaw: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ProgressRange.allCases) { range in
                chip(range)
            }
            Spacer(minLength: 0)
        }
        .sensoryFeedback(.selection, trigger: rangeRaw)
    }

    private func chip(_ range: ProgressRange) -> some View {
        let selected = range.rawValue == rangeRaw
        return Button {
            rangeRaw = range.rawValue
        } label: {
            Text(range.label)
                .font(Theme.font(13, selected ? .bold : .medium, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 30)
                .background(Capsule().fill(selected ? Theme.accent : Color.clear))
                .overlay(Capsule().strokeBorder(selected ? Theme.accent : Theme.separatorStrong,
                                                lineWidth: Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(range.longLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Weight trend

/// Smoothed trend weight (engine, RTS smoother) as a line, scale readings as dots,
/// optional dashed goal weight.
struct ProgressWeightTrendChart: View {
    let trend: [ProgressChartPoint]
    let scale: [ProgressChartPoint]
    let targetKg: Double?
    let startDate: Date
    let endDate: Date

    /// Values the y-domain is built from (the goal only when it is close to the data,
    /// so a distant goal does not flatten the curve).
    private var visibleTarget: Double? {
        guard let targetKg else { return nil }
        let values = trend.map(\.value) + scale.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return targetKg }
        return targetKg >= lo - 3 && targetKg <= hi + 3 ? targetKg : nil
    }

    private var yDomain: ClosedRange<Double> {
        var values = trend.map(\.value) + scale.map(\.value)
        if let visibleTarget { values.append(visibleTarget) }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 100
        let pad = max(0.5, (hi - lo) * 0.15)
        return (lo - pad).rounded(.down)...(hi + pad).rounded(.up)
    }

    var body: some View {
        let target = visibleTarget
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                if let target {
                    RuleMark(y: .value("Objectif", target))
                        .foregroundStyle(Theme.good.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                ForEach(scale) { point in
                    PointMark(x: .value("Date", point.date),
                              y: .value("Poids", point.value))
                        .foregroundStyle(Theme.weight.opacity(0.45))
                        .symbolSize(16)
                }
                ForEach(trend) { point in
                    LineMark(x: .value("Date", point.date),
                             y: .value("Poids", point.value),
                             series: .value("Série", "Tendance"))
                        .foregroundStyle(Theme.weight)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: startDate...endDate)
            .chartYScale(domain: yDomain)
            .progressDateAxis()
            .progressValueAxis()
            .frame(height: 220)

            HStack(spacing: 14) {
                ProgressLegendItem(color: Theme.weight, text: "Tendance")
                ProgressLegendItem(color: Theme.weight.opacity(0.45), text: "Pesées", dot: true)
                if target != nil {
                    ProgressLegendItem(color: Theme.good.opacity(0.7), text: "Poids visé", dashed: true)
                }
            }
        }
    }
}

// MARK: - Expenditure

/// Daily expenditure estimate as a line with a soft orange area.
struct ProgressExpenditureChart: View {
    let points: [ProgressChartPoint]
    let startDate: Date
    let endDate: Date

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 2500
        let pad = max(50, (hi - lo) * 0.2)
        return max(0, ((lo - pad) / 50).rounded(.down) * 50)...(((hi + pad) / 50).rounded(.up) * 50)
    }

    var body: some View {
        let domain = yDomain
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Jour", point.date),
                         yStart: .value("Base", domain.lowerBound),
                         yEnd: .value("Dépense", point.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.expenditure.opacity(0.28),
                                                             Theme.expenditure.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(x: .value("Jour", point.date),
                         y: .value("Dépense", point.value))
                    .foregroundStyle(Theme.expenditure)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: startDate...endDate)
        .chartYScale(domain: domain)
        .progressDateAxis()
        .progressValueAxis()
        .frame(height: 220)
    }
}

// MARK: - Energy balance

/// Daily intake bars against the dashed expenditure line.
struct ProgressEnergyBalanceChart: View {
    let points: [ProgressBalancePoint]
    let startDate: Date
    let endDate: Date

    private var yMax: Double {
        let intake = points.compactMap(\.intake).max() ?? 0
        let expenditure = points.map(\.expenditure).max() ?? 0
        return max(max(intake, expenditure) * 1.1, 500)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(points.filter { $0.intake != nil }) { point in
                    BarMark(x: .value("Jour", point.date, unit: .day),
                            y: .value("Apport", point.intake ?? 0))
                        .foregroundStyle(Theme.calories.opacity(point.isPartial ? 0.45 : 1))
                        .cornerRadius(2)
                }
                ForEach(points) { point in
                    // Middle of the day, to line up with the bars.
                    LineMark(x: .value("Jour", point.date.addingTimeInterval(12 * 3600)),
                             y: .value("Dépense", point.expenditure),
                             series: .value("Série", "Dépense"))
                        .foregroundStyle(Theme.expenditure)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartXScale(domain: startDate...endDate)
            .chartYScale(domain: 0...yMax)
            .progressDateAxis()
            .progressValueAxis()
            .frame(height: 220)

            HStack(spacing: 14) {
                ProgressLegendItem(color: Theme.calories, text: "Apport")
                ProgressLegendItem(color: Theme.expenditure, text: "Dépense", dashed: true)
            }
        }
    }
}
