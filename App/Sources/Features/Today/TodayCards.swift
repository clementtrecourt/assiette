import SwiftData
import SwiftUI

// MARK: - Hairline

/// 1 pt horizontal rule (`Theme.separator` by default), DESIGN.md "hairlines instead of cards".
struct TodayHairline: View {
    var color: Color = Theme.separator

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: Theme.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Pinned macro header

/// Pinned header: 4 equal columns Kcal / Prot. / Gluc. / Lip. separated by hairlines, with the
/// remaining (or consumed) value, a 2 pt progress bar and the target.
struct TodayMacroHeader: View {
    let totals: NutrientValues
    let targets: TodayTargets
    let showsConsumed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TodayMacroHeaderColumn(label: "Kcal", consumed: totals.calories,
                                   target: targets.calories, color: Theme.calories,
                                   unit: "kcal", showsConsumed: showsConsumed)
            TodayMacroHeaderColumn(label: "Prot.", consumed: totals.protein,
                                   target: targets.protein, color: Theme.protein,
                                   unit: "g", showsConsumed: showsConsumed, leadingRule: true)
            TodayMacroHeaderColumn(label: "Gluc.", consumed: totals.carbs,
                                   target: targets.carbs, color: Theme.carbs,
                                   unit: "g", showsConsumed: showsConsumed, leadingRule: true)
            TodayMacroHeaderColumn(label: "Lip.", consumed: totals.fat,
                                   target: targets.fat, color: Theme.fat,
                                   unit: "g", showsConsumed: showsConsumed, leadingRule: true)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .overlay(alignment: .top) {
            TodayHairline()
        }
        .overlay(alignment: .bottom) {
            TodayHairline()
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(showsConsumed ? "Touchez pour afficher le restant" : "Touchez pour afficher le consommé")
    }
}

struct TodayMacroHeaderColumn: View {
    let label: String
    let consumed: Double
    let target: Double
    let color: Color
    let unit: String
    let showsConsumed: Bool
    /// Vertical hairline on the leading edge (columns 2–4).
    var leadingRule: Bool = false

    private var remaining: Double { target - consumed }
    private var displayed: Double { showsConsumed ? consumed : remaining }
    private var isNegative: Bool { !showsConsumed && remaining.rounded() < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            labelText
            valueText
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .padding(.top, 6)
            ProgressBar(value: consumed, total: target, color: color, height: 2)
                .padding(.top, 8)
            targetText
                .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if leadingRule {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: Theme.hairline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var labelText: some View {
        Text((showsConsumed ? "\(label) · mangé" : label).uppercased())
            .font(Theme.label)
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var valueText: Text {
        let number = Text(Formatters.number(displayed, maxFractionDigits: 0))
            .font(Theme.numberLarge)
            .foregroundStyle(isNegative ? Theme.overTarget : Theme.textPrimary)
        guard unit != "kcal" else { return number }
        let suffix = Text(unit)
            .font(Theme.font(12, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.textTertiary)
        return number + suffix
    }

    private var targetText: some View {
        Text("sur \(Formatters.number(target, maxFractionDigits: 0))")
            .font(Theme.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var accessibilityText: String {
        let c = Formatters.number(consumed, maxFractionDigits: 0)
        let t = Formatters.number(target, maxFractionDigits: 0)
        let r = Formatters.number(remaining, maxFractionDigits: 0)
        return "\(label) : \(c) sur \(t) \(unit), reste \(r)"
    }
}

// MARK: - Timeline model

/// Entries logged within 30 minutes of the previous one form one group.
struct TodayTimelineGroup: Identifiable {
    let id: String
    let start: Date
    let entries: [JournalEntry]

    var totals: NutrientValues { NutrientValues.sum(entries.map(\.nutrients)) }

    /// Distinct meals of the group, e.g. "Déjeuner" or "Déjeuner · Collation".
    var mealLabel: String {
        var meals: [Meal] = []
        for entry in entries where !meals.contains(entry.meal) {
            meals.append(entry.meal)
        }
        return meals.map(\.label).joined(separator: " · ")
    }

    static func make(from entries: [JournalEntry], gap: TimeInterval = 30 * 60) -> [TodayTimelineGroup] {
        let sorted = entries.sorted { $0.createdAt < $1.createdAt }
        var groups: [TodayTimelineGroup] = []
        var current: [JournalEntry] = []
        var previous: Date?
        for entry in sorted {
            if let previous, entry.createdAt.timeIntervalSince(previous) > gap, !current.isEmpty {
                groups.append(makeGroup(current))
                current = []
            }
            current.append(entry)
            previous = entry.createdAt
        }
        if !current.isEmpty {
            groups.append(makeGroup(current))
        }
        return groups
    }

    private static func makeGroup(_ entries: [JournalEntry]) -> TodayTimelineGroup {
        TodayTimelineGroup(id: entries[0].id.uuidString, start: entries[0].createdAt, entries: entries)
    }
}

enum TodayTimeFormat {
    /// "7:45", "12:05".
    static func short(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(hour):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }
}

enum TodayTimelineMetrics {
    /// Leading margin of the time column.
    static let timeLeading: CGFloat = 16
    /// Fixed time column (DESIGN.md: 36 pt).
    static let timeWidth: CGFloat = 36
    static let gutterWidth: CGFloat = timeLeading + timeWidth
    /// Kept for source compatibility (the timeline no longer draws a vertical line).
    static let lineColumnWidth: CGFloat = 0
    static let contentLeading: CGFloat = gutterWidth + 8
    static let trailing: CGFloat = 16
    static let groupGap: CGFloat = 14
    /// Top offset of the time label in rows that show one.
    static let headerDotY: CGFloat = 14
    /// Icon side in timeline rows.
    static let iconSize: CGFloat = 24
    /// Spacing between the icon and the name.
    static let iconSpacing: CGFloat = 10
}

// MARK: - Timeline building blocks

/// Left gutter: fixed time column. `dotColor`, `lineAbove` and `lineBelow` are kept for
/// source compatibility; the "Minimal pro" timeline has no vertical line nor dots.
struct TodayTimelineGutter: View {
    var time: String?
    var dotColor: Color?
    var dotY: CGFloat
    var lineAbove: Bool
    var lineBelow: Bool

    var body: some View {
        Text(time ?? "")
            .font(Theme.font(12, .medium, relativeTo: .caption))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: TodayTimelineMetrics.timeWidth, alignment: .leading)
            .padding(.top, dotY)
            .padding(.leading, TodayTimelineMetrics.timeLeading)
            .frame(width: TodayTimelineMetrics.gutterWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
    }
}

/// One list row of the timeline: content shifted right of the time column.
struct TodayTimelineRow<Content: View>: View {
    let time: String?
    let dotColor: Color?
    let dotY: CGFloat
    let lineAbove: Bool
    let lineBelow: Bool
    let content: Content

    init(time: String? = nil, dotColor: Color? = nil, dotY: CGFloat = 0,
         lineAbove: Bool = true, lineBelow: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.time = time
        self.dotColor = dotColor
        self.dotY = dotY
        self.lineAbove = lineAbove
        self.lineBelow = lineBelow
        self.content = content()
    }

    var body: some View {
        content
            .padding(.leading, TodayTimelineMetrics.contentLeading)
            .padding(.trailing, TodayTimelineMetrics.trailing)
            .background(alignment: .topLeading) {
                if time != nil {
                    TodayTimelineGutter(time: time, dotColor: dotColor, dotY: dotY,
                                        lineAbove: lineAbove, lineBelow: lineBelow)
                }
            }
    }
}

/// Top of a group: time in the fixed column + tiny uppercase meal label, hairline above
/// every group but the first. Full-width row (not wrapped in `TodayTimelineRow`).
struct TodayGroupHeaderContent: View {
    let group: TodayTimelineGroup
    var time: String? = nil
    var showsRule: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(time ?? "")
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: TodayTimelineMetrics.contentLeading - TodayTimelineMetrics.timeLeading,
                       alignment: .leading)
            Text(group.mealLabel.uppercased())
                .font(Theme.label)
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, TodayTimelineMetrics.timeLeading)
        .padding(.trailing, TodayTimelineMetrics.trailing)
        .padding(.top, TodayTimelineMetrics.groupGap)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsRule {
                TodayHairline()
                    .padding(.horizontal, TodayTimelineMetrics.timeLeading)
            }
        }
    }
}

/// "icon  Name  qty        kcal" timeline row (no card, faint rule between rows).
struct TodayTimelineEntryContent: View {
    let entry: JournalEntry
    let showsDivider: Bool

    private var nameText: some View {
        Text(entry.name)
            .font(Theme.font(14, .medium, relativeTo: .subheadline))
            .foregroundStyle(Theme.textBody)
            .lineLimit(1)
    }

    private var quantityText: some View {
        Text(quantity)
            .font(Theme.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
    }

    private var kcalText: some View {
        Text(Formatters.number(entry.nutrients.calories, maxFractionDigits: 0))
            .font(Theme.font(14, .medium, relativeTo: .subheadline))
            .monospacedDigit()
            .foregroundStyle(Theme.textBody)
            .layoutPriority(2)
    }

    private var icon: some View {
        // openNutrition entries resolve their icon from the bundled database (ref = food id).
        FoodIconView(icon: nil,
                     foodId: entry.source == .openNutrition ? entry.ref.flatMap { Int64($0) } : nil,
                     kind: entry.kindRaw.flatMap { FoodKind(rawValue: $0) },
                     size: TodayTimelineMetrics.iconSize,
                     placeholder: FoodIconView.placeholderSymbol(for: entry.source))
    }

    var body: some View {
        HStack(alignment: .center, spacing: TodayTimelineMetrics.iconSpacing) {
            icon
            // Name and quantity on one line when they fit, otherwise quantity goes below.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    nameText
                    quantityText
                }
                VStack(alignment: .leading, spacing: 1) {
                    nameText
                    quantityText
                }
            }
            Spacer(minLength: 8)
            kcalText
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .overlay(alignment: .top) {
            if showsDivider {
                TodayHairline(color: Theme.separator.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(entry.quantityDescription), \(Formatters.kcal(entry.nutrients.calories))")
        .accessibilityHint("Modifier la quantité")
    }

    private var quantity: String {
        entry.source == .quickAdd ? "" : entry.quantityDescription
    }
}

/// Bottom of a group: colored P/G/L + group kcal, aligned with the entry names.
struct TodayGroupFooterContent: View {
    let totals: NutrientValues

    private var totalText: Text {
        let value = Text(Formatters.number(totals.calories, maxFractionDigits: 0))
            .font(Theme.font(12, .bold, relativeTo: .caption))
            .foregroundStyle(Theme.textSecondary)
        let unit = Text(" kcal")
            .font(Theme.caption)
            .foregroundStyle(Theme.textTertiary)
        return value + unit
    }

    var body: some View {
        HStack(spacing: 8) {
            TodayMacroDots(values: totals)
            Spacer(minLength: 8)
            totalText
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.leading, TodayTimelineMetrics.iconSize + TodayTimelineMetrics.iconSpacing)
        .padding(.top, 3)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }
}

/// "P 12  G 30  L 5": macro letter in its color, grams in textTertiary.
struct TodayMacroDots: View {
    let values: NutrientValues

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NutrientKey.macros) { key in
                HStack(spacing: 3) {
                    Text(Self.letter(for: key))
                        .font(Theme.font(12, .bold, relativeTo: .caption))
                        .foregroundStyle(Theme.color(for: key))
                    Text(Formatters.number(values.value(key), maxFractionDigits: 0))
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    static func letter(for key: NutrientKey) -> String {
        switch key {
        case .protein: "P"
        case .carbohydrates: "G"
        case .totalFat: "L"
        default: String(key.label.prefix(1))
        }
    }

    private var accessibilityText: String {
        NutrientKey.macros
            .map { "\($0.label) \(Formatters.number(values.value($0), maxFractionDigits: 0)) g" }
            .joined(separator: ", ")
    }
}

/// Last timeline item: current time + dashed "Maintenant · + Ajouter" row.
struct TodayNowRow: View {
    let isToday: Bool
    let hasGroups: Bool
    let onAdd: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            row(time: isToday ? TodayTimeFormat.short(context.date) : "")
        }
    }

    private func row(time: String) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(time)
                .font(Theme.font(12, .bold, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: TodayTimelineMetrics.contentLeading - TodayTimelineMetrics.timeLeading,
                       alignment: .leading)
                .accessibilityHidden(true)
            button
        }
        .padding(.leading, TodayTimelineMetrics.timeLeading)
        .padding(.trailing, TodayTimelineMetrics.trailing)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if hasGroups {
                TodayHairline()
                    .padding(.horizontal, TodayTimelineMetrics.timeLeading)
            }
        }
    }

    private var buttonLabel: some View {
        HStack(spacing: 8) {
            if isToday {
                Text("Maintenant")
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.textQuaternary)
            }
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Ajouter")
                .font(Theme.font(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .font(Theme.font(14, .medium, relativeTo: .subheadline))
        .lineLimit(1)
    }

    private var button: some View {
        Button(action: onAdd) {
            buttonLabel
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.separatorStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajouter un aliment")
    }
}

/// Friendly message when nothing is logged on the day.
struct TodayEmptyState: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(isToday ? "Votre journée commence ici" : "Rien de noté ce jour-là")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Touchez « + » pour rechercher un aliment, scanner un code-barres ou faire un ajout rapide.")
                .font(Theme.callout)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }
}

// MARK: - Below the timeline

/// Water as a hairline row: drop + "Eau 0,75 / 2 L" + undo + outlined "+250" "+500", 2 pt bar.
struct TodayWaterCard: View {
    let totalMl: Double
    let targetMl: Double
    let canUndo: Bool
    let onAdd: (Double) -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                titleLabel
                Spacer(minLength: 4)
                undoButton
                addButton(250)
                addButton(500)
            }
            TodayWaterBar(fraction: targetMl > 0 ? totalMl / targetMl : 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            TodayHairline()
        }
    }

    private var titleLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.water)
            Text("Eau")
                .font(Theme.font(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.textBody)
            Text("\(liters(totalMl)) / \(liters(targetMl)) L")
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(canUndo ? Theme.textSecondary : Theme.textQuaternary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!canUndo)
        .accessibilityLabel("Annuler le dernier ajout d'eau")
    }

    private func addButton(_ ml: Double) -> some View {
        Button {
            onAdd(ml)
        } label: {
            Text("+\(Formatters.number(ml, maxFractionDigits: 0))")
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay {
                    Capsule().strokeBorder(Theme.separatorStrong, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Ajouter \(Formatters.number(ml, maxFractionDigits: 0)) ml d'eau")
    }

    private func liters(_ ml: Double) -> String {
        Formatters.number(ml / 1000, maxFractionDigits: 2)
    }
}

/// Water bar (never turns red: drinking more than the target is fine).
private struct TodayWaterBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separatorStrong)
                Capsule()
                    .fill(Theme.water)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 2)
        .animation(.snappy, value: fraction)
    }
}

/// Hairline row linking to the day's micronutrients.
struct TodayNutrientsLinkLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("Nutriments du jour")
                .font(Theme.font(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.textBody)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) {
            TodayHairline()
        }
        .overlay(alignment: .bottom) {
            TodayHairline()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Floating add button

/// White circle with a near-black "+" (DESIGN.md FAB).
struct TodayAddButton: View {
    let onSearch: () -> Void
    let onScan: () -> Void
    let onQuickAdd: () -> Void

    var body: some View {
        Menu {
            Button(action: onSearch) {
                Label("Rechercher", systemImage: "magnifyingglass")
            }
            Button(action: onScan) {
                Label("Scanner un code-barres", systemImage: "barcode.viewfinder")
            }
            Button(action: onQuickAdd) {
                Label("Ajout rapide", systemImage: "bolt")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.accent))
                .shadow(color: Color.black.opacity(0.6), radius: 12, x: 0, y: 6)
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Ajouter")
    }
}
