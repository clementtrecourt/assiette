import SwiftData
import SwiftUI

// MARK: - Hairline

/// 1 pt horizontal rule (`Theme.separator` by default).
struct TodayHairline: View {
    var color: Color = Theme.separator

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: Theme.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Round icon button label

/// 32 pt `raised2` circle with an SF Symbol (title bar buttons).
struct TodayRoundIcon: View {
    let systemName: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textBody)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.raised2))
            .contentShape(Circle())
    }
}

// MARK: - Pinned macro header

/// Pinned header: 4 equal columns kcal / G / P / L (DESIGN.md macro order), each with the
/// remaining (or consumed) value and a 3 pt bar in the macro color.
struct TodayMacroHeader: View {
    let totals: NutrientValues
    let targets: TodayTargets
    let showsConsumed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TodayMacroHeaderColumn(key: .calories, consumed: totals.calories,
                                   target: targets.calories, showsConsumed: showsConsumed)
            ForEach(Theme.macroOrder) { key in
                TodayMacroHeaderColumn(key: key, consumed: totals.value(key),
                                       target: Self.target(for: key, in: targets),
                                       showsConsumed: showsConsumed)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityHint(showsConsumed ? "Touchez pour afficher le restant" : "Touchez pour afficher le consommé")
    }

    static func target(for key: NutrientKey, in targets: TodayTargets) -> Double {
        switch key {
        case .calories: targets.calories
        case .carbohydrates: targets.carbs
        case .protein: targets.protein
        case .totalFat: targets.fat
        default: 0
        }
    }
}

/// One header column: "G 165" (or "1 251 kcal") + a 3 pt bar. Remaining mode: the bar shows the
/// remaining share, anchored on the trailing edge; consumed mode: the eaten share from the left.
struct TodayMacroHeaderColumn: View {
    let key: NutrientKey
    let consumed: Double
    let target: Double
    let showsConsumed: Bool

    private var isCalories: Bool { key == .calories }
    private var color: Color { Theme.color(for: key) }
    private var remaining: Double { target - consumed }
    private var displayed: Double { showsConsumed ? consumed : remaining }
    private var isNegative: Bool { !showsConsumed && remaining.rounded() < 0 }

    private var fraction: Double {
        guard target > 0 else { return 0 }
        let value = showsConsumed ? consumed / target : remaining / target
        return min(max(value, 0), 1)
    }

    private var barColor: Color {
        if showsConsumed, target > 0, consumed > target * 1.05 { return Theme.overTarget }
        return color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            valueLine
            TodayMacroBar(fraction: fraction, fromTrailing: !showsConsumed, color: barColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var valueLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if isCalories {
                Image(systemName: "flame.fill").font(.caption2)
            } else {
                Text(Theme.letter(for: key))
                    .font(Theme.font(12, .bold, relativeTo: .caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(Formatters.number(displayed, maxFractionDigits: 0))
                .font(Theme.font(17, .bold, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(isNegative ? Theme.overTarget : Theme.textPrimary)
                .contentTransition(.numericText())
            Text(showsConsumed ? (isCalories ? "kcal" : "g") : "rest.")
                .font(Theme.font(11, .medium, relativeTo: .caption2))
                .foregroundStyle(Theme.textTertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var accessibilityText: String {
        let unit = isCalories ? "kcal" : "g"
        let name = isCalories ? "Calories" : key.label
        let c = Formatters.number(consumed, maxFractionDigits: 0)
        let t = Formatters.number(target, maxFractionDigits: 0)
        let r = Formatters.number(remaining, maxFractionDigits: 0)
        return "\(name) : \(c) sur \(t) \(unit), reste \(r)"
    }
}

/// 3 pt track + fill; `fromTrailing` anchors the fill on the right (remaining share).
private struct TodayMacroBar: View {
    let fraction: Double
    let fromTrailing: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: fromTrailing ? .trailing : .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 3)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Time helpers

enum TodayTimeFormat {
    /// "7:45", "12:05".
    static func short(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(hour):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }

    /// Timeline pill label: "07:00", "13:00".
    static func hour(_ hour: Int) -> String {
        (hour < 10 ? "0\(hour)" : "\(hour)") + ":00"
    }
}

enum TodayTimelineMetrics {
    static let leading: CGFloat = 16
    /// Space between the screen's trailing edge and the hour pills.
    static let pillTrailing: CGFloat = 12
    static let pillWidth: CGFloat = 52
    static let pillHeight: CGFloat = 24
    /// Distance from the trailing edge to the vertical line (center of the pills).
    static let lineCenterTrailing: CGFloat = pillTrailing + pillWidth / 2
    /// Food cards stop before the pill column.
    static let cardTrailing: CGFloat = pillTrailing + pillWidth + 8
    static let hourRowHeight: CGFloat = 50
    static let addSize: CGFloat = 24
    static let cardIconSize: CGFloat = 38
    static let cardRadius: CGFloat = 13
}

// MARK: - Timeline model

/// Entries of one day grouped by the hour of `createdAt` (Calendar.current), with totals.
/// Built once per body evaluation.
struct TodayHourBuckets {
    private(set) var entriesByHour: [Int: [JournalEntry]] = [:]
    private(set) var totalsByHour: [Int: NutrientValues] = [:]
    private(set) var earliestHour: Int?

    init(entries: [JournalEntry]) {
        let calendar = Calendar.current
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.createdAt)
            entriesByHour[hour, default: []].append(entry)
        }
        for (hour, list) in entriesByHour {
            let sorted = list.sorted { $0.createdAt < $1.createdAt }
            entriesByHour[hour] = sorted
            totalsByHour[hour] = NutrientValues.sum(sorted.map(\.nutrients))
        }
        earliestHour = entriesByHour.keys.min()
    }

    func entries(at hour: Int) -> [JournalEntry] { entriesByHour[hour] ?? [] }
}

// MARK: - Timeline rows

/// Row background drawing the vertical line through the pills. `top`/`bottom` draw the upper /
/// lower half, so the line can start and end on a pill's center.
struct TodayTimelineLine: View {
    var top = true
    var bottom = true

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Rectangle().fill(top ? Theme.separatorStrong : Color.clear)
                Rectangle().fill(bottom ? Theme.separatorStrong : Color.clear)
            }
            .frame(width: 1)
            .padding(.trailing, TodayTimelineMetrics.lineCenterTrailing - 0.5)
        }
        .background(Theme.background)
        .accessibilityHidden(true)
    }
}

/// Hour slot: per-hour totals chips (when the hour has entries), round "+" and the hour pill.
struct TodayHourRow: View {
    let hour: Int
    let isNow: Bool
    let totals: NutrientValues?
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let totals {
                TodayHourChips(totals: totals)
                    .layoutPriority(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                addButton
                TodayHourPill(hour: hour, isNow: isNow)
            }
        }
        .padding(.leading, TodayTimelineMetrics.leading)
        .padding(.trailing, TodayTimelineMetrics.pillTrailing)
        .frame(height: TodayTimelineMetrics.hourRowHeight)
        .accessibilityElement(children: .contain)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: TodayTimelineMetrics.addSize, height: TodayTimelineMetrics.addSize)
                .background(Circle().fill(Theme.raised2))
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajouter un aliment à \(TodayTimeFormat.hour(hour))")
    }
}

/// "07:00" capsule on the line; the current hour has a calories-blue outline and a dot.
struct TodayHourPill: View {
    let hour: Int
    let isNow: Bool

    var body: some View {
        HStack(spacing: 3) {
            if isNow {
                Circle()
                    .fill(Theme.calories)
                    .frame(width: 5, height: 5)
            }
            Text(TodayTimeFormat.hour(hour))
                .font(Theme.font(11, .medium, relativeTo: .caption2))
                .monospacedDigit()
                .foregroundStyle(isNow ? Theme.textPrimary : Theme.textBody)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: TodayTimelineMetrics.pillWidth, height: TodayTimelineMetrics.pillHeight)
        .background(Capsule().fill(Theme.raised2))
        .overlay {
            if isNow {
                Capsule().strokeBorder(Theme.calories, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isNow ? "\(TodayTimeFormat.hour(hour)), heure actuelle" : TodayTimeFormat.hour(hour))
    }
}

/// Per-hour totals: flame + kcal, then G / P / L in small round badges.
struct TodayHourChips: View {
    let totals: NutrientValues

    var body: some View {
        HStack(spacing: 9) {
            chip(value: totals.calories) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.flame)
            }
            ForEach(Theme.macroOrder) { key in
                chip(value: totals.value(key)) {
                    Text(Theme.letter(for: key))
                        .font(Theme.font(9, .bold, relativeTo: .caption2))
                        .foregroundStyle(Theme.textBody)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func chip<Badge: View>(value: Double, @ViewBuilder badge: () -> Badge) -> some View {
        HStack(spacing: 4) {
            badge()
                .frame(width: 17, height: 17)
                .background(Circle().fill(Theme.raised2))
            Text(Formatters.number(value, maxFractionDigits: 0))
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
        }
    }

    private var accessibilityText: String {
        let macros = Theme.macroOrder
            .map { "\($0.label) \(Formatters.number(totals.value($0), maxFractionDigits: 0)) g" }
            .joined(separator: ", ")
        return "\(Formatters.kcal(totals.calories)), \(macros)"
    }
}

/// Food card: icon tile, name, "kcal · G · P · L · quantity", round edit button (visual: the
/// whole card opens the edit sheet).
struct TodayEntryCard: View {
    let entry: JournalEntry

    var body: some View {
        let nutrients = entry.nutrients
        HStack(spacing: 9) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(Theme.font(13, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                detailText(nutrients)
                    .font(Theme.font(11, .regular, relativeTo: .caption))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textBody)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.raised2))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TodayTimelineMetrics.cardRadius, style: .continuous)
                .fill(Theme.raised)
        )
        .contentShape(RoundedRectangle(cornerRadius: TodayTimelineMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(entry.quantityDescription), \(Formatters.kcal(nutrients.calories))")
        .accessibilityHint("Modifier")
    }

    private var icon: some View {
        // openNutrition entries resolve their icon from the bundled database (ref = food id).
        FoodIconView(icon: nil,
                     foodId: entry.source == .openNutrition ? entry.ref.flatMap { Int64($0) } : nil,
                     kind: entry.kindRaw.flatMap { FoodKind(rawValue: $0) },
                     size: TodayTimelineMetrics.cardIconSize,
                     placeholder: FoodIconView.placeholderSymbol(for: entry.source),
                     name: entry.name)
    }

    private func detailText(_ nutrients: NutrientValues) -> Text {
        let kcal = Text(Formatters.number(nutrients.calories, maxFractionDigits: 0))
            .fontWeight(.semibold)
            .foregroundStyle(Theme.textBody)
        var rest = Theme.macroOrder
            .map { "\(Formatters.number(nutrients.value($0), maxFractionDigits: 0)) \(Theme.letter(for: $0))" }
        if entry.source != .quickAdd {
            rest.append(entry.quantityDescription)
        }
        let tail = Text(" · " + rest.joined(separator: " · "))
            .foregroundStyle(Theme.textTertiary)
        return kcal + tail
    }
}

/// Small row above the timeline revealing the night hours (00:00 to the first shown hour).
struct TodayEarlyHoursRow: View {
    let firstHour: Int
    let onShow: () -> Void

    var body: some View {
        Button(action: onShow) {
            HStack(spacing: 6) {
                Image(systemName: "moon")
                    .font(.system(size: 11, weight: .semibold))
                Text("Afficher \(TodayTimeFormat.hour(0)) – \(TodayTimeFormat.hour(max(firstHour - 1, 0)))")
                    .font(Theme.font(12, .medium, relativeTo: .caption))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, TodayTimelineMetrics.leading)
            .padding(.trailing, TodayTimelineMetrics.cardTrailing)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Below the timeline

/// Row linking to the day's micronutrients.
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
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .themedCard(radius: TodayTimelineMetrics.cardRadius)
        .contentShape(Rectangle())
    }
}
