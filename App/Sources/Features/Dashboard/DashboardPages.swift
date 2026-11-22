import SwiftUI

// Pages 2 and 3 of the Accueil header carousel (reference: "Weekly Nutrition" and
// "Energy Balance"), next to the calorie ring page. Drawn with shapes, no Charts.

/// Consumed totals and targets of one day of the current week.
struct DashboardWeekDay: Identifiable {
    var date: Date
    var totals: NutrientValues
    var targets: DashboardTargets
    var isFuture: Bool
    var id: Date { date }
}

/// "Nutrition de la semaine": Monday → Sunday columns, one row per kcal / G / P / L, each cell a
/// small tile holding a vertical bar (consumed or remaining share of the target). The selected
/// day is outlined; its values are written in the right column.
struct DashboardWeekPage: View {
    let days: [DashboardWeekDay]
    let showRemaining: Bool
    @Binding var selected: Date

    private static let keys: [NutrientKey] = [.calories] + Theme.macroOrder
    /// Reference: 54 pt row pitch, 22 × 35 pt cells, hairlines between the rows.
    private static let rowHeight: CGFloat = 54
    private static let cellSize = CGSize(width: 22, height: 35)
    /// Weekday letter row, then the margin kept inside the selection outline below it.
    private static let letterHeight: CGFloat = 26
    private static let outlineBottom: CGFloat = 6

    @Environment(\.displayScale) private var displayScale

    private var selectedDay: DashboardWeekDay? {
        days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) } ?? days.last { !$0.isFuture }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(days) { day in
                    column(day)
                }
            }
            .frame(maxWidth: .infinity)
            .background(alignment: .top) { rowSeparators }
            values
                .frame(width: 86, alignment: .leading)
        }
    }

    private func column(_ day: DashboardWeekDay) -> some View {
        let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDay?.date ?? selected)
        return Button {
            guard !day.isFuture else { return }
            withAnimation(.quick) { selected = day.date }
        } label: {
            VStack(spacing: 0) {
                ForEach(Self.keys, id: \.self) { key in
                    cell(day, key: key)
                        .frame(height: Self.rowHeight)
                }
                Text(CoachingFormat.dayLetters[CoachingFormat.mondayIndex(of: day.date)])
                    .font(Theme.font(14, isSelected ? .bold : .regular, relativeTo: .caption))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(height: Self.letterHeight)
            }
            .padding(.bottom, Self.outlineBottom)
            .frame(maxWidth: .infinity)
            .overlay {
                // Reference: ~39 pt wide outline around the whole column, letter included,
                // starting 6 pt above the first cell row and ending 1 pt above the column end.
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.textPrimary, lineWidth: 1.5)
                        .frame(width: 39)
                        .padding(.top, -6)
                        .padding(.bottom, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Formatters.dayTitle(day.date))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cell(_ day: DashboardWeekDay, key: NutrientKey) -> some View {
        let target = day.targets.value(for: key)
        let eaten = day.totals.value(key)
        let shown = showRemaining ? max(target - eaten, 0) : eaten
        let fraction = target > 0 ? min(shown / target, 1) : 0
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Theme.tile)
            .frame(width: Self.cellSize.width, height: Self.cellSize.height)
            .overlay(alignment: .bottom) {
                if day.isFuture || (eaten <= 0 && !showRemaining) {
                    Capsule()
                        .fill(Theme.textQuaternary)
                        .frame(width: 8, height: 2)
                        .frame(maxHeight: .infinity)
                } else {
                    GeometryReader { geo in
                        let inner = geo.size.height - 8
                        let height = max(inner * fraction, 2)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            // White cap on top of the bar, then the macro color.
                            Rectangle().fill(Theme.textPrimary).frame(height: 2)
                            Rectangle().fill(Theme.color(for: key)).frame(height: max(height - 2, 0))
                        }
                        .frame(width: 6)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                    }
                }
            }
    }

    /// 1 px lines between the macro rows, across the day columns.
    private var rowSeparators: some View {
        let line = 1 / max(displayScale, 1)
        return VStack(spacing: 0) {
            ForEach(1..<Self.keys.count, id: \.self) { _ in
                Color.clear
                    .frame(height: Self.rowHeight)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.separator).frame(height: line)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private var values: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.keys, id: \.self) { key in
                valueRow(key)
                    .frame(height: Self.rowHeight, alignment: .leading)
            }
        }
    }

    private func valueRow(_ key: NutrientKey) -> some View {
        let target = selectedDay?.targets.value(for: key) ?? 0
        let eaten = selectedDay?.totals.value(key) ?? 0
        let shown = showRemaining ? target - eaten : eaten
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Text(Formatters.number(shown, maxFractionDigits: 0))
                if key == .calories {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text(" \(Theme.letter(for: key))")
                }
            }
            .font(Theme.font(18.5, .regular, relativeTo: .body))
            .monospacedDigit()
            .foregroundStyle(shown < 0 ? Theme.overTarget : Theme.textPrimary)
            Text("sur \(Formatters.number(target, maxFractionDigits: 0))")
                .font(Theme.font(14, .regular, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// "Bilan énergétique": daily intake bars (blue) of the last weeks with the calorie target
/// (yellow) or the expenditure (orange) as a dotted line, then both averages.
struct DashboardBalancePage: View {
    let days: [InsightBalanceDay]
    let againstExpenditure: Bool

    /// Reference: chart baseline ~55 pt above the averages, page as tall as the week page
    /// (the bottom padding keeps the toggle where the week page puts it).
    private static let chartHeight: CGFloat = 119

    private var lineColor: Color { againstExpenditure ? Theme.expenditure : Theme.targetLine }
    private func lineValue(_ day: InsightBalanceDay) -> Double {
        againstExpenditure ? day.expenditure : day.target
    }

    private var averageIntake: Double? {
        let logged = days.filter { !$0.isPartial }.compactMap(\.intake)
        guard !logged.isEmpty else { return nil }
        return logged.reduce(0, +) / Double(logged.count)
    }

    private var averageLine: Double? {
        let complete = days.filter { !$0.isPartial && $0.intake != nil }
        guard !complete.isEmpty else { return nil }
        return complete.map(lineValue).reduce(0, +) / Double(complete.count)
    }

    var body: some View {
        VStack(spacing: 55) {
            chart
                .frame(height: Self.chartHeight)
            HStack(alignment: .top, spacing: 0) {
                figure(averageIntake, legend: "Nutrition") {
                    // Reference glyph: three narrow square-ended bars.
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach([9, 15, 12] as [CGFloat], id: \.self) { height in
                            Rectangle().frame(width: 3, height: height)
                        }
                    }
                    .foregroundStyle(Theme.calories)
                    .frame(height: 17, alignment: .bottom)
                }
                Text("–")
                    .font(Theme.font(20, .regular, relativeTo: .title3))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 2)
                figure(averageLine, legend: againstExpenditure ? "Dépense" : "Objectif") {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(lineColor)
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func figure<Icon: View>(_ value: Double?, legend: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 6) {
            Text(value.map { Formatters.number($0, maxFractionDigits: 0) } ?? "–")
                .font(Theme.font(20, .regular, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                icon()
                    .font(.system(size: 17, weight: .semibold))
                Text(legend)
                    .font(Theme.font(15, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var chart: some View {
        GeometryReader { geo in
            let values = days.map { $0.intake ?? 0 } + days.map(lineValue)
            let top = max(values.max() ?? 1, 1) * 1.3
            let count = max(days.count, 1)
            let slot = geo.size.width / CGFloat(count)
            let barWidth = max(min(slot * 0.4, 5), 2)
            let y: (Double) -> CGFloat = { geo.size.height * (1 - CGFloat($0 / top)) }
            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    if let intake = day.intake, intake > 0 {
                        Rectangle()
                            .fill(Theme.calories.opacity(day.isPartial ? 0.45 : 1))
                            .frame(width: barWidth, height: max(geo.size.height - y(intake), 1))
                            .position(x: slot * (CGFloat(index) + 0.5),
                                      y: (y(intake) + geo.size.height) / 2)
                    }
                }
                Path { path in
                    for (index, day) in days.enumerated() {
                        let point = CGPoint(x: slot * (CGFloat(index) + 0.5), y: y(lineValue(day)))
                        if index == 0 {
                            path.move(to: CGPoint(x: 0, y: point.y))
                            path.addLine(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    if let last = days.last {
                        path.addLine(to: CGPoint(x: geo.size.width, y: y(lineValue(last))))
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 5]))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Apports quotidiens et \(againstExpenditure ? "dépense" : "objectif") sur \(days.count) jours")
    }
}

/// Two-option capsule toggle under a carousel page (same look as Mangé / Restant).
struct DashboardPageToggle: View {
    let first: String
    let second: String
    @Binding var secondSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(first, selected: !secondSelected) { secondSelected = false }
            segment(second, selected: secondSelected) { secondSelected = true }
        }
        // Selected capsule nearly fills the 40 pt track (reference: 1 pt inset).
        .padding(1)
        .background(Theme.raised2, in: Capsule())
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.quick) { action() }
        } label: {
            Text(title)
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                .frame(width: 100, height: 38)
                .background(Capsule().fill(selected ? Theme.accent : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Page dots under the carousel: current page white, others grey.
struct DashboardPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.textPrimary : Theme.textQuaternary)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) sur \(count)")
    }
}
