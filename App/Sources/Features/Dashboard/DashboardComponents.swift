import SwiftUI

// Building blocks of the dashboard: section headers, 2-column cards and their small visuals
// (sparkline, intake bars, meter, 30-day dot grid). Drawn with Path, no Charts, so a dozen
// cards stay cheap to render.

enum DashboardGrid {
    static let spacing: CGFloat = 10
    static let columns = [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)]
}

/// Section title ("Tendances") with an optional trailing action ("Tout voir").
struct DashboardSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.font(18, .bold, relativeTo: .title3))
                .tracking(-0.3)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension DashboardSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// "Tout voir" link style of section headers.
struct DashboardSeeAllLabel: View {
    var body: some View {
        Text("Tout voir")
            .font(Theme.font(13, .medium, relativeTo: .subheadline))
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}

/// Dashboard tile: title, period, small visual, hairline, value + unit + chevron.
struct DashboardCard<Visual: View>: View {
    let title: String
    let subtitle: String
    let value: String
    let unit: String
    let valueColor: Color
    let visualHeight: CGFloat
    let accessory: String
    let visual: Visual

    init(title: String, subtitle: String, value: String, unit: String = "",
         valueColor: Color = Theme.textPrimary, visualHeight: CGFloat = 38,
         accessory: String = "chevron.right", @ViewBuilder visual: () -> Visual)
    {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.unit = unit
        self.valueColor = valueColor
        self.visualHeight = visualHeight
        self.accessory = accessory
        self.visual = visual()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.font(17, .medium, relativeTo: .headline))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Text(subtitle)
                .font(Theme.font(12, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .padding(.top, 1)
            visual
                .frame(maxWidth: .infinity)
                .frame(height: visualHeight)
                .padding(.top, 10)
                .padding(.bottom, 9)
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.hairline)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.font(20, .bold, relativeTo: .title3))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.font(12, .medium, relativeTo: .caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: accessory)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit.isEmpty ? "\(title), \(subtitle), \(value)" : "\(title), \(subtitle), \(value) \(unit)")
    }
}

/// Placeholder inside a card visual when there is nothing to draw yet.
struct DashboardNoData: View {
    var text = "Pas encore de données"

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.textQuaternary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sparkline

/// Tiny line chart scaled to its frame.
struct DashboardSparkline: View {
    enum Style { case area, line, dots }

    let values: [Double]
    let color: Color
    var style: Style = .line
    /// Smallest value span mapped to the full height (avoids blowing up tiny changes).
    var minimumSpan: Double = 0

    var body: some View {
        if values.isEmpty {
            DashboardNoData()
        } else {
            GeometryReader { geo in
                let points = Self.points(values, in: geo.size, minimumSpan: minimumSpan)
                ZStack {
                    if style == .area, points.count > 1 {
                        Self.areaPath(points, height: geo.size.height)
                            .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    if points.count > 1 {
                        Self.linePath(points)
                            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(dotIndices(count: points.count), id: \.self) { index in
                        Circle()
                            .fill(Theme.raised)
                            .overlay(Circle().stroke(color, lineWidth: 1.4))
                            .frame(width: 5, height: 5)
                            .position(points[index])
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func dotIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count == 1 { return [0] }
        switch style {
        case .dots: return Array(0..<count)
        case .area: return [0, count - 1]
        case .line: return [count - 1]
        }
    }

    static func points(_ values: [Double], in size: CGSize, minimumSpan: Double) -> [CGPoint] {
        guard let rawLo = values.min(), let rawHi = values.max() else { return [] }
        let span = max(rawHi - rawLo, minimumSpan)
        let mid = (rawHi + rawLo) / 2
        let lo = span > rawHi - rawLo ? mid - span / 2 : rawLo
        let inset: CGFloat = 3
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        return values.enumerated().map { index, value in
            let x = values.count > 1
                ? inset + width * CGFloat(index) / CGFloat(values.count - 1)
                : size.width / 2
            let y = span > 0
                ? inset + height * CGFloat(1 - (value - lo) / span)
                : size.height / 2
            return CGPoint(x: x, y: y)
        }
    }

    static func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    static func areaPath(_ points: [CGPoint], height: CGFloat) -> Path {
        var path = linePath(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Intake bars vs expenditure

/// Daily intake bars with the expenditure as a dashed orange line (Bilan énergétique card).
struct DashboardBalanceBars: View {
    let points: [ProgressBalancePoint]
    private let spacing: CGFloat = 3

    var body: some View {
        if points.isEmpty {
            DashboardNoData()
        } else {
            GeometryReader { geo in
                let size = geo.size
                let maxValue = max((points.compactMap(\.intake) + points.map(\.expenditure)).max() ?? 1, 1) * 1.08
                let count = CGFloat(points.count)
                let barWidth = max((size.width - spacing * (count - 1)) / count, 1)
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(points) { point in
                            bar(point, maxValue: maxValue, height: size.height)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                    expenditureLine(maxValue: maxValue, size: size, barWidth: barWidth)
                        .stroke(Theme.expenditure.opacity(0.85),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3]))
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func bar(_ point: ProgressBalancePoint, maxValue: Double, height: CGFloat) -> some View {
        let value = point.intake ?? 0
        let barHeight = value > 0 ? max(CGFloat(value / maxValue) * height, 2) : 2
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(value > 0 ? Theme.calories.opacity(point.isPartial ? 0.45 : 1) : Theme.track)
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
    }

    private func expenditureLine(maxValue: Double, size: CGSize, barWidth: CGFloat) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let x: CGFloat
            if points.count == 1 {
                x = size.width / 2
            } else if index == 0 {
                x = 0
            } else if index == points.count - 1 {
                x = size.width
            } else {
                x = CGFloat(index) * (barWidth + spacing) + barWidth / 2
            }
            let y = size.height - CGFloat(point.expenditure / maxValue) * size.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if points.count == 1, let first = points.first {
            let y = size.height - CGFloat(first.expenditure / maxValue) * size.height
            path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        return path
    }
}

// MARK: - Meter

/// Horizontal meter: fill, optional target tick and optional recommended zone (tinted track).
struct DashboardMeter: View {
    /// Filled share of the width (0…1).
    let fraction: Double
    let color: Color
    /// Target tick position (0…1 of the width).
    var tick: Double?
    /// Recommended zone from this position to the end (0…1).
    var zoneStart: Double?
    var zoneColor: Color = Theme.good
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                ZStack(alignment: .trailing) {
                    Theme.track
                    if let zoneStart {
                        zoneColor.opacity(0.22)
                            .frame(width: width * CGFloat(1 - min(max(zoneStart, 0), 1)))
                    }
                }
                .frame(height: height)
                .clipShape(Capsule())
                if filled > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(width * CGFloat(filled), height), height: height)
                }
                if let tick {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.textTertiary)
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: width * CGFloat(min(max(tick, 0), 1)) - 0.75)
                }
            }
            .frame(width: width, height: geo.size.height)
        }
        .frame(height: height + 6)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

/// Thin capsule bar (hero macro bars).
struct DashboardBar: View {
    let fraction: Double
    let color: Color
    var fromTrailing = false
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let filled = min(max(fraction, 0), 1)
            ZStack(alignment: fromTrailing ? .trailing : .leading) {
                Rectangle().fill(Theme.track)
                if filled > 0 {
                    Rectangle()
                        .fill(color)
                        .frame(width: max(geo.size.width * CGFloat(filled), height))
                }
            }
        }
        .frame(height: height)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Regularity grid

/// Square dots, `columns` per row (10 × 3 for 30 days), oldest first.
struct DashboardDotGrid: View {
    let filled: [Bool]
    let color: Color
    var columns = 10

    var body: some View {
        let rows = stride(from: 0, to: filled.count, by: columns).map {
            Array(filled[$0..<min($0 + columns, filled.count)])
        }
        VStack(spacing: 3) {
            ForEach(0..<rows.count, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(column < rows[row].count
                                ? (rows[row][column] ? color : Theme.track)
                                : Color.clear)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
