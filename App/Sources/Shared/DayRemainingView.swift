import SwiftData
import SwiftUI

/// What is left for a day (kcal, G, P, L): value + 4 pt bar holding the remaining share of the
/// target (MacroFactor's "left" header). Shown above every screen that adds or edits a food.
///
/// `pending` previews the food being added (or the edited entry's new values, `replacing` being
/// its current ones): the values already count it, and the part of the bar it uses is drawn in
/// a lighter tint, so the effect of the quantity typed is visible before logging.
struct DayRemainingView: View {
    enum Layout {
        /// 2 × 2 (kcal, G / P, L), next to the add sheet buttons.
        case grid
        /// One row of 4, full width.
        case row
    }

    @Query private var entries: [JournalEntry]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private let day: Date
    private let pending: NutrientValues?
    private let replacing: NutrientValues?
    private let layout: Layout

    /// - Parameters:
    ///   - pending: nutrients of the food being added / the edited entry's new quantity.
    ///   - replacing: current nutrients of the edited entry (already in the day's total), when it
    ///     belongs to `day`.
    init(day: Date, pending: NutrientValues? = nil, replacing: NutrientValues? = nil, layout: Layout = .grid) {
        let start = Calendar.current.startOfDay(for: day)
        self.day = start
        self.pending = pending
        self.replacing = replacing
        self.layout = layout
        _entries = Query(filter: #Predicate<JournalEntry> { $0.day == start })
    }

    private struct Cell {
        let key: NutrientKey
        let target: Double
        /// Left before the pending food.
        let before: Double
        /// Left once the pending food is counted.
        let after: Double
    }

    var body: some View {
        let cells = makeCells()
        Group {
            switch layout {
            case .grid:
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        cellView(cells[0])
                        cellView(cells[1])
                    }
                    GridRow {
                        cellView(cells[2])
                        cellView(cells[3])
                    }
                }
            case .row:
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cells, id: \.key) { cellView($0) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(cells))
    }

    /// kcal, G, P, L (the grid reads kcal G / P L).
    private func makeCells() -> [Cell] {
        let eaten = NutrientValues.sum(entries.map { $0.nutrients })
        let targets = profiles.first?.targets(on: day)
        return ([NutrientKey.calories] + Theme.macroOrder).map { key in
            let target = targets?.value(key) ?? 0
            let before = target - eaten.value(key)
            let after = before + (replacing?.value(key) ?? 0) - (pending?.value(key) ?? 0)
            return Cell(key: key, target: target, before: before, after: after)
        }
    }

    private func cellView(_ cell: Cell) -> some View {
        let unit = cell.key == .calories ? " rest." : " \(Theme.letter(for: cell.key)) rest."
        let color = Theme.color(for: cell.key)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(cell.target > 0 ? Formatters.number(cell.after, maxFractionDigits: 0) : "—")
                    .foregroundStyle(cell.after < 0 ? Theme.overTarget : Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(unit)
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(Theme.font(14, .regular, relativeTo: .footnote))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    Rectangle().fill(Theme.track)
                    // What the pending food uses, then what is still left after it.
                    Rectangle()
                        .fill(color.opacity(0.35))
                        .frame(width: geo.size.width * fraction(max(cell.before, cell.after), of: cell.target))
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * fraction(min(cell.before, cell.after), of: cell.target))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: cell.after)
    }

    private func fraction(_ remaining: Double, of target: Double) -> Double {
        target > 0 ? min(max(remaining / target, 0), 1) : 0
    }

    private func accessibilityText(_ cells: [Cell]) -> String {
        guard cells.contains(where: { $0.target > 0 }) else { return "Restant du jour" }
        let parts = cells.map { cell -> String in
            let unit = cell.key == .calories ? "kcal" : "g"
            return "\(cell.key.label) \(Formatters.number(cell.after, maxFractionDigits: 0)) \(unit)"
        }
        let prefix = pending == nil ? "Restant du jour" : "Restant du jour avec cet aliment"
        return "\(prefix) : " + parts.joined(separator: ", ")
    }
}

/// Nutrients of the food currently open in `AddEntrySheet` (embedded in the add flow), so the
/// add sheet header can preview what will be left. nil when no quantity screen is open.
struct AddEntryPendingKey: PreferenceKey {
    static let defaultValue: AddEntryPending? = nil

    static func reduce(value: inout AddEntryPending?, nextValue: () -> AddEntryPending?) {
        value = nextValue() ?? value
    }
}

struct AddEntryPending: Equatable, Sendable {
    var day: Date
    var nutrients: NutrientValues
}
