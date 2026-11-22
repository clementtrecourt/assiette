import Charts
import SwiftUI

// Charts of the dashboard detail screens (Dépense, Poids tendance, Objectif, Bilan énergétique),
// drawn like the reference app: dashed grid, trailing y labels, French date labels, a band
// around the line, open circle markers (squares while the expenditure is holding).

private enum InsightAxis {
    static let labelFont = Theme.font(13, .regular, relativeTo: .caption)
    static let grid = StrokeStyle(lineWidth: 0.6, dash: [3, 3])
}

private extension View {
    /// Date x-axis: weekdays for a week, "28 oct." otherwise, every `strideDays` days.
    func insightDateAxis(range: InsightRange, averaging: InsightAveraging) -> some View {
        chartXAxis {
            if range == .week && averaging == .daily {
                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Theme.raised2)
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).locale(Formatters.locale), centered: false)
                        .font(InsightAxis.labelFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else if range.labelStrideDays > 0 && averaging != .monthly {
                AxisMarks(values: .stride(by: .day, count: range.labelStrideDays)) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Theme.raised2)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Formatters.locale))
                        .font(InsightAxis.labelFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Theme.raised2)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits).locale(Formatters.locale))
                        .font(InsightAxis.labelFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .chartBackground { proxy in
            // Reference: subtle 1 pt baseline along the bottom of the plot, above the date ticks.
            GeometryReader { geo in
                if let plot = proxy.plotFrame {
                    let frame = geo[plot]
                    Rectangle()
                        .fill(Theme.separatorStrong)
                        .frame(width: frame.width, height: 1)
                        .position(x: frame.midX, y: frame.maxY - 0.5)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Trailing value axis with dashed grid lines.
    func insightValueAxis(desiredCount: Int = 3) -> some View {
        chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: desiredCount)) { value in
                AxisGridLine(stroke: InsightAxis.grid)
                    .foregroundStyle(Theme.raised2)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Formatters.number(number, maxFractionDigits: 1))
                    }
                }
                .font(InsightAxis.labelFont)
                .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Domain padded around `values`, rounded to `step`.
private func insightDomain(_ values: [Double], minimumSpan: Double, pad: Double, step: Double) -> ClosedRange<Double> {
    let lo = values.min() ?? 0
    let hi = values.max() ?? 1
    let span = max(hi - lo, minimumSpan)
    let mid = (hi + lo) / 2
    let low = ((mid - span / 2 - span * pad) / step).rounded(.down) * step
    let high = ((mid + span / 2 + span * pad) / step).rounded(.up) * step
    return low...max(high, low + step)
}

// MARK: - Line with band (expenditure, trend weight)

struct InsightLineChart: View {
    enum Kind { case expenditure, weight }

    let points: [InsightPoint]
    let kind: Kind
    let range: InsightRange
    let averaging: InsightAveraging
    let startDate: Date
    let endDate: Date
    let fitToData: Bool
    var height: CGFloat = 270

    private var color: Color { kind == .expenditure ? Theme.expenditure : Theme.weight }
    private var bandColor: Color { kind == .expenditure ? Theme.expenditureBand : Theme.weightBand }
    /// Markers on every point only while they stay readable.
    private var showsMarkers: Bool { points.count <= 45 }

    private var yDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.low, $0.high] + ($0.scale.map { [$0] } ?? []) }
        switch kind {
        case .expenditure:
            return fitToData
                ? insightDomain(values, minimumSpan: 40, pad: 0.1, step: 10)
                : insightDomain(values, minimumSpan: 150, pad: 0.35, step: 50)
        case .weight:
            return fitToData
                ? insightDomain(values, minimumSpan: 0.4, pad: 0.1, step: 0.1)
                : insightDomain(values, minimumSpan: 2, pad: 0.3, step: 1)
        }
    }

    var body: some View {
        let domain = yDomain
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Jour", point.date),
                         yStart: .value("Bas", point.low),
                         yEnd: .value("Haut", point.high))
                    .foregroundStyle(bandColor)
                    .interpolationMethod(.monotone)
            }
            if kind == .weight && showsMarkers {
                ForEach(points.filter { $0.scale != nil }) { point in
                    PointMark(x: .value("Jour", point.date), y: .value("Balance", point.scale ?? point.value))
                        .foregroundStyle(Theme.weightDark)
                        .symbolSize(22)
                }
            }
            ForEach(points) { point in
                LineMark(x: .value("Jour", point.date),
                         y: .value("Valeur", point.value),
                         series: .value("Série", "Ligne"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if showsMarkers {
                ForEach(points) { point in
                    PointMark(x: .value("Jour", point.date), y: .value("Valeur", point.value))
                        .symbol {
                            InsightMarker(color: color, square: point.isHolding)
                        }
                }
            }
        }
        .chartXScale(domain: startDate...endDate.addingTimeInterval(range == .week ? 16 * 3600 : 0))
        .chartYScale(domain: domain)
        .chartPlotStyle { $0.clipped() }
        .insightDateAxis(range: range, averaging: averaging)
        .insightValueAxis(desiredCount: kind == .weight ? 5 : 3)
        .frame(height: height)
        .padding(.leading, 0)
        .padding(.trailing, 12)
        .animation(.quick, value: points)
        .animation(.quick, value: fitToData)
    }
}

/// Open circle (or square while holding) on the chart background.
private struct InsightMarker: View {
    let color: Color
    let square: Bool

    var body: some View {
        Group {
            if square {
                Rectangle().fill(Theme.raised)
                    .overlay(Rectangle().strokeBorder(color, lineWidth: 1.6))
            } else {
                Circle().fill(Theme.raised)
                    .overlay(Circle().strokeBorder(color, lineWidth: 1.6))
            }
        }
        .frame(width: 8, height: 8)
    }
}

// MARK: - Energy balance

/// Daily (or averaged) intake bars against the dotted expenditure or calorie target line.
struct InsightBalanceChart: View {
    let days: [InsightBalanceDay]
    let againstTargets: Bool
    let range: InsightRange
    let averaging: InsightAveraging
    let startDate: Date
    let endDate: Date
    let fitToData: Bool

    private var lineColor: Color { againstTargets ? Theme.targetLine : Theme.expenditure }

    private var unit: Calendar.Component {
        switch averaging {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }
    }

    var body: some View {
        let bars = InsightPoint.averaged(
            days.compactMap { day in day.intake.map { InsightPoint(date: day.date, value: $0, isHolding: day.isPartial) } },
            by: averaging)
        let lastLogged = days.last(where: { $0.intake != nil })?.date ?? startDate
        let line = InsightPoint.averaged(
            days.filter { $0.date <= lastLogged }.map {
                InsightPoint(date: $0.date, value: againstTargets ? $0.target : $0.expenditure)
            },
            by: averaging)
        let values = bars.map(\.value) + line.map(\.value)
        let top = max((values.max() ?? 2000) * 1.08, 500)
        let bottom = fitToData ? max(((values.min() ?? 0) * 0.8 / 100).rounded(.down) * 100, 0) : 0
        let halfUnit: TimeInterval = averaging == .daily ? 12 * 3600 : (averaging == .weekly ? 3.5 * 86400 : 15 * 86400)

        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Jour", bar.date, unit: unit),
                        yStart: .value("Base", bottom),
                        yEnd: .value("Calories", max(bar.value, bottom)),
                        width: .ratio(0.7))
                    .foregroundStyle(Theme.calories.opacity(bar.isHolding ? 0.45 : 1))
            }
            ForEach(line) { point in
                LineMark(x: .value("Jour", point.date.addingTimeInterval(halfUnit)),
                         y: .value("Référence", point.value),
                         series: .value("Série", "Référence"))
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [0.1, 4.6]))
            }
        }
        .chartXScale(domain: startDate...endDate.adding(days: 1))
        .chartYScale(domain: bottom...top)
        .chartPlotStyle { $0.clipped() }
        .insightDateAxis(range: range, averaging: averaging)
        .insightValueAxis(desiredCount: 2)
        .frame(height: 170)
        .padding(.trailing, 12)
        .animation(.quick, value: days)
        .animation(.quick, value: againstTargets)
    }
}

// MARK: - Goal waterfall

/// Distance to the goal weight: day 0, then a floating bar per step (light = moving away,
/// dark = getting closer), then the current status in grey.
struct InsightGoalChart: View {
    let steps: [DashboardInsights.GoalStep]
    let useTrend: Bool
    let fitToData: Bool

    private var awayColor: Color { useTrend ? Theme.weight : Theme.goalAway }
    private var towardsColor: Color { useTrend ? Theme.weightDark : Theme.goalTowards }

    private func color(_ kind: DashboardInsights.GoalStep.Kind) -> Color {
        switch kind {
        case .away: awayColor
        case .towards: towardsColor
        case .status: Theme.raised2
        }
    }

    /// Labels under the bars: day 0, every 4th step (as "Jour n"), and "Statut".
    private var labeled: [String] {
        guard steps.count > 1 else { return steps.map(\.label) }
        let every = max(1, (steps.count - 2) / 3)
        return steps.enumerated().compactMap { index, step in
            // Keep the last intermediate label clear of "Statut".
            index == 0 || index == steps.count - 1 || (index % every == 0 && index < steps.count - 1 - max(2, every / 2)) ? step.label : nil
        }
    }

    var body: some View {
        let values = steps.flatMap { [$0.start, $0.end] }
        let hi = max(((values.max() ?? 1) * 1.1).rounded(.up), 1)
        let lo = fitToData ? max(((steps.dropFirst().filter { $0.kind != .status }.flatMap { [$0.start, $0.end] }.min() ?? 0) * 0.8 * 2).rounded(.down) / 2, 0) : 0
        let shown = Set(labeled)

        Chart {
            ForEach(steps) { step in
                let thin = abs(step.end - step.start) < 0.03
                BarMark(x: .value("Étape", step.label),
                        yStart: .value("Avant", max(step.start, lo)),
                        yEnd: .value("Après", max(thin ? step.start + 0.03 : step.end, lo)),
                        width: .ratio(0.72))
                    .foregroundStyle(color(step.kind))
            }
        }
        .chartYScale(domain: lo...hi)
        .chartPlotStyle { $0.clipped() }
        .chartXAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame {
                    let frame = geo[plot]
                    ForEach(steps.filter { shown.contains($0.label) }) { step in
                        if let x = proxy.position(forX: step.label) {
                            Text(step.label == "Statut" ? "Statut" : "Jour \(step.label)")
                                .font(InsightAxis.labelFont)
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize()
                                .position(x: min(max(frame.minX + x, frame.minX + 22), frame.maxX - 20), y: frame.maxY + 14)
                        }
                    }
                }
            }
        }
        .insightValueAxis(desiredCount: 4)
        .padding(.bottom, 24)
        .frame(height: 324)
        .padding(.trailing, 12)
        .animation(.quick, value: steps)
        .animation(.quick, value: fitToData)
    }
}
