import SwiftData
import SwiftUI

// MARK: - Pinned macro header

/// Pinned header: 4 equal columns Kcal / Prot. / Gluc. / Lip. with the remaining (or consumed)
/// value, a thin progress bar and the target.
struct TodayMacroHeader: View {
    let totals: NutrientValues
    let targets: TodayTargets
    let showsConsumed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TodayMacroHeaderColumn(label: "Kcal", consumed: totals.calories,
                                   target: targets.calories, color: Theme.calories,
                                   unit: "kcal", showsConsumed: showsConsumed)
            TodayMacroHeaderColumn(label: "Prot.", consumed: totals.protein,
                                   target: targets.protein, color: Theme.protein,
                                   unit: "g", showsConsumed: showsConsumed)
            TodayMacroHeaderColumn(label: "Gluc.", consumed: totals.carbs,
                                   target: targets.carbs, color: Theme.carbs,
                                   unit: "g", showsConsumed: showsConsumed)
            TodayMacroHeaderColumn(label: "Lip.", consumed: totals.fat,
                                   target: targets.fat, color: Theme.fat,
                                   unit: "g", showsConsumed: showsConsumed)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 0.5)
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

    private var remaining: Double { target - consumed }
    private var displayed: Double { showsConsumed ? consumed : remaining }
    private var isNegative: Bool { !showsConsumed && remaining.rounded() < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(showsConsumed ? "\(label) · mangé" : label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(Formatters.number(displayed, maxFractionDigits: 0))
                .font(.system(size: 22, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundStyle(isNegative ? Theme.overTarget : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            ProgressBar(value: consumed, total: target, color: color, height: 4)
            Text("sur \(Formatters.number(target, maxFractionDigits: 0))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
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
    static let gutterWidth: CGFloat = 64
    static let timeWidth: CGFloat = 34
    static let lineColumnWidth: CGFloat = 18
    static let contentLeading: CGFloat = 68
    static let trailing: CGFloat = 16
    static let groupGap: CGFloat = 14
    /// Center of the dot in a group header row (gap + top padding + half a caption line).
    static let headerDotY: CGFloat = 30
}

// MARK: - Timeline building blocks

/// Left gutter: time label, vertical line and an optional dot.
struct TodayTimelineGutter: View {
    var time: String?
    var dotColor: Color?
    var dotY: CGFloat
    var lineAbove: Bool
    var lineBelow: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            timeLabel
            lineColumn
        }
        .padding(.leading, 8)
        .frame(width: TodayTimelineMetrics.gutterWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    private var timeLabel: some View {
        Text(time ?? "")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: TodayTimelineMetrics.timeWidth, alignment: .trailing)
            .padding(.top, max(dotY - 7, 0))
    }

    private var lineColumn: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(lineAbove ? Theme.separator : Color.clear)
                    .frame(width: 2, height: dotY)
                Rectangle()
                    .fill(lineBelow ? Theme.separator : Color.clear)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                    .padding(3)
                    .background(Circle().fill(Theme.background))
                    .offset(y: dotY - 7.5)
            }
        }
        .frame(width: TodayTimelineMetrics.lineColumnWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// One list row of the timeline: content shifted right of the gutter.
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
                TodayTimelineGutter(time: time, dotColor: dotColor, dotY: dotY,
                                    lineAbove: lineAbove, lineBelow: lineBelow)
            }
    }
}

/// Top of a group card: small secondary meal label.
struct TodayGroupHeaderContent: View {
    let group: TodayTimelineGroup

    var body: some View {
        Text(group.mealLabel)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 3)
            .background(Theme.card,
                        in: UnevenRoundedRectangle(topLeadingRadius: Theme.cornerRadius,
                                                   topTrailingRadius: Theme.cornerRadius,
                                                   style: .continuous))
            .padding(.top, TodayTimelineMetrics.groupGap)
    }
}

/// "Name  qty        kcal" inside a group card.
struct TodayTimelineEntryContent: View {
    let entry: JournalEntry
    let showsDivider: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if entry.source == .quickAdd {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(entry.name)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            Text(quantity)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Formatters.number(entry.nutrients.calories, maxFractionDigits: 0))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
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

/// Bottom of a group card: P/G/L dots + total kcal.
struct TodayGroupFooterContent: View {
    let totals: NutrientValues

    var body: some View {
        HStack(spacing: 8) {
            TodayMacroDots(values: totals)
            Spacer(minLength: 8)
            Text(Formatters.kcal(totals.calories))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .background(Theme.card,
                    in: UnevenRoundedRectangle(bottomLeadingRadius: Theme.cornerRadius,
                                               bottomTrailingRadius: Theme.cornerRadius,
                                               style: .continuous))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 0.5)
                .padding(.horizontal, 12)
        }
    }
}

/// "● 12  ● 30  ● 5" for protein / carbs / fat (grams).
struct TodayMacroDots: View {
    let values: NutrientValues

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NutrientKey.macros) { key in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.color(for: key))
                        .frame(width: 6, height: 6)
                    Text(Formatters.number(values.value(key), maxFractionDigits: 0))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        NutrientKey.macros
            .map { "\($0.label) \(Formatters.number(values.value($0), maxFractionDigits: 0)) g" }
            .joined(separator: ", ")
    }
}

/// Last timeline item: accent dot + dashed "Maintenant : + Ajouter" card.
struct TodayNowRow: View {
    let isToday: Bool
    let hasGroups: Bool
    let onAdd: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            TodayTimelineRow(time: isToday ? TodayTimeFormat.short(context.date) : nil,
                             dotColor: Theme.accent,
                             dotY: TodayTimelineMetrics.groupGap + 22,
                             lineAbove: hasGroups,
                             lineBelow: false) {
                button
            }
        }
    }

    private var button: some View {
        Button(action: onAdd) {
            Text(isToday ? "Maintenant : + Ajouter" : "+ Ajouter")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, TodayTimelineMetrics.groupGap)
        .accessibilityLabel("Ajouter un aliment")
    }
}

/// Friendly message when nothing is logged on the day.
struct TodayEmptyState: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
            Text(isToday ? "Votre journée commence ici" : "Rien de noté ce jour-là")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Touchez « + » pour rechercher un aliment, scanner un code-barres ou faire un ajout rapide.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }
}

// MARK: - Below the timeline

struct TodayWaterCard: View {
    let totalMl: Double
    let targetMl: Double
    let canUndo: Bool
    let onAdd: (Double) -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Theme.water)
                Text("Eau")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(liters(totalMl)) / \(liters(targetMl)) L")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Spacer(minLength: 4)
                undoButton
                addButton(250)
                addButton(500)
            }
            TodayWaterBar(fraction: targetMl > 0 ? totalMl / targetMl : 0)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(canUndo ? Theme.textSecondary : Theme.textSecondary.opacity(0.35))
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
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.water)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.water.opacity(0.16), in: Capsule())
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
                Capsule().fill(Theme.separator)
                Capsule()
                    .fill(Theme.water)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(.snappy, value: fraction)
    }
}

/// Compact row linking to the day's micronutrients.
struct TodayNutrientsLinkLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(Theme.accent)
            Text("Nutriments du jour")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Floating add button

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
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.accent))
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Ajouter")
    }
}
