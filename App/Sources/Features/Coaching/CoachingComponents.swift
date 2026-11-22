import SwiftUI
import UIKit

// Building blocks shared by the Programme tab, the goal / targets / exception editors and the
// weekly check-in (Features/Coaching). Everything is prefixed `Coaching`.

/// Coaching settings that do not live in the SwiftData model.
enum CoachingSettings {
    /// `@AppStorage` key of the collaborative mode (the check-in proposes, the user adjusts with − / +).
    static let collaborativeKey = "coaching.collaborative"

    static var isCollaborative: Bool { UserDefaults.standard.bool(forKey: collaborativeKey) }
}

/// How targets evolve: coached (applied each week), collaborative (adjusted at the check-in), manual.
enum CoachingMode: String, CaseIterable, Identifiable, Hashable {
    case coached, collaborative, manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coached: return "Coaché"
        case .collaborative: return "Collaboratif"
        case .manual: return "Manuel"
        }
    }

    /// Lowercase form used in subtitles ("Perte de poids · coaché").
    var adjective: String {
        switch self {
        case .coached: return "coaché"
        case .collaborative: return "collaboratif"
        case .manual: return "manuel"
        }
    }

    var detail: String {
        switch self {
        case .coached: return "Le bilan hebdomadaire met à jour vos objectifs à partir de votre dépense réelle."
        case .collaborative: return "Le bilan propose de nouveaux objectifs, vous les ajustez avant de les appliquer."
        case .manual: return "Vous fixez vous-même les calories et les macros. Pas de bilan automatique."
        }
    }

    var systemImage: String {
        switch self {
        case .coached: return "wand.and.stars"
        case .collaborative: return "slider.horizontal.3"
        case .manual: return "pencil.and.list.clipboard"
        }
    }

    static func current(profile: UserProfile, collaborative: Bool) -> CoachingMode {
        if profile.manualTargets { return .manual }
        return collaborative ? .collaborative : .coached
    }
}

/// Text helpers for the coaching screens (French).
enum CoachingFormat {
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) in display order, Monday first.
    static let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]
    /// One-letter day labels, Monday first.
    static let dayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    private static let weekdayNames = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]

    /// "lundi" for a calendar weekday (1 = Sunday).
    static func weekdayName(_ weekday: Int) -> String {
        weekdayNames[(max(1, min(7, weekday)) - 1)]
    }

    /// Index 0 … 6 (Monday … Sunday) of `date` in the week.
    static func mondayIndex(of date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7
    }

    /// "Lundi" (first letter uppercased).
    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "9 nov."
    static func day(_ date: Date) -> String { Formatters.shortDate(date) }

    /// "9 nov. 2026"
    static func dayYear(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Formatters.locale))
    }

    /// "lun. 16 nov."
    static func shortWeekdayDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Formatters.locale))
    }

    /// "lundi 23 nov."
    static func weekdayDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Formatters.locale))
    }

    /// "Lundi 23 novembre"
    static func longDay(_ date: Date) -> String {
        capitalized(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Formatters.locale)))
    }

    /// Signed number with a real minus sign: "−0,19", "+50", "0".
    static func signed(_ value: Double, digits: Int = 0) -> String {
        let factor = pow(10, Double(digits))
        let rounded = (value * factor).rounded() / factor
        if rounded == 0 { return Formatters.number(0, maxFractionDigits: digits) }
        return (rounded < 0 ? "−" : "+") + Formatters.number(abs(rounded), maxFractionDigits: digits)
    }

    /// "72,5 kg"
    static func kg(_ value: Double) -> String { "\(Formatters.number(value, maxFractionDigits: 1)) kg" }

    /// "224 g"
    static func grams(_ value: Double) -> String { "\(Formatters.number(value, maxFractionDigits: 0)) g" }

    /// "1 911" (kcal without unit).
    static func kcalNumber(_ value: Double) -> String { Formatters.number(value, maxFractionDigits: 0) }

    /// Short goal name: "Perte", "Maintien", "Prise".
    static func goalShort(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose: return "Perte"
        case .maintain: return "Maintien"
        case .gain: return "Prise"
        }
    }

    /// "Perte de poids", "Maintien", "Prise de poids".
    static func goalTitle(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose: return "Perte de poids"
        case .maintain: return "Maintien"
        case .gain: return "Prise de poids"
        }
    }

    /// Text for a decimal field ("72,5"), no grouping.
    static func fieldText(_ value: Double?, digits: Int) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never)
            .locale(Formatters.locale))
    }

    /// Parses "72,5" or "72.5" (nil when empty or invalid).
    static func parse(_ text: String) -> Double? {
        let cleaned = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Section title of the Programme list ("Historique des objectifs").
struct CoachingSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Theme.font(20, .bold, relativeTo: .title3))
            .foregroundStyle(Theme.textPrimary)
            .textCase(nil)
            .padding(.leading, -4)
    }
}

/// Card title + small subtitle ("Programme coaché" / "depuis le 14 nov.").
struct CoachingCardHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.font(19, .regular, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.font(15, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small outlined button label used at the bottom of the program cards ("↻ Nouveau").
struct CoachingChipLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        // Reference: raised2 capsule, white 16 pt label, 40 pt high.
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(Theme.font(16, .regular, relativeTo: .callout))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Theme.raised2, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Colored change pill ("−79"): green when `isGood`, red otherwise, neutral when nil.
struct CoachingDeltaPill: View {
    let text: String
    var isGood: Bool?

    private var color: Color {
        switch isGood {
        case .some(true): return Theme.good
        case .some(false): return Theme.overTarget
        case .none: return Theme.textSecondary
        }
    }

    var body: some View {
        Text(text)
            .font(Theme.font(12, .bold, relativeTo: .caption))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Row of selectable chips (white fill + near-black text when selected).
struct CoachingChoiceChips<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    init(options: [Value], selection: Binding<Value>, label: @escaping (Value) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.textBody)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? Theme.accent : Theme.raised2)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Numeric text field row bound to a `String` and to the screen's `FocusState`
/// (so the screen can put the keyboard on it when it appears).
struct CoachingNumberRow<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    let unit: String
    let focus: FocusState<Field?>.Binding
    let field: Field
    let titleColor: Color
    let placeholder: String
    let onSubmit: () -> Void

    init(_ title: String, text: Binding<String>, unit: String, focus: FocusState<Field?>.Binding,
         field: Field, titleColor: Color = Theme.textBody, placeholder: String = "0",
         onSubmit: @escaping () -> Void = {})
    {
        self.title = title
        self._text = text
        self.unit = unit
        self.focus = focus
        self.field = field
        self.titleColor = titleColor
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused(focus, equals: field)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 60, maxWidth: 130)
                Text(unit)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
        } label: {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(titleColor)
        }
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = field }
    }
}

/// Check-in countdown: inner ring of 7 segments (one per day of the week, elapsed days filled
/// white), thin outer ring = progress towards the goal (`Theme.goodGradient`).
struct CoachingCountdownRing<Center: View>: View {
    let filledDays: Int
    let goalProgress: Double?
    let center: Center

    init(filledDays: Int, goalProgress: Double?, @ViewBuilder center: () -> Center) {
        self.filledDays = filledDays
        self.goalProgress = goalProgress
        self.center = center()
    }

    private static var size: CGFloat { 202 }
    private static var outerDiameter: CGFloat { 189 }
    private static var innerDiameter: CGFloat { 162 }
    private static var trackColor: Color { Theme.hex(0x333333) }

    var body: some View {
        let goal = CGFloat(min(max(goalProgress ?? 0, 0), 1))
        let elapsed = CGFloat(min(max(filledDays, 0), 7)) / 7
        // Measured on the reference: both tracks #333, 5 pt strokes, arcs start at 3 o'clock.
        ZStack {
            Circle().stroke(Self.trackColor, lineWidth: 5)
                .frame(width: Self.outerDiameter, height: Self.outerDiameter)
            Circle().trim(from: 0, to: goal)
                .stroke(Theme.good, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: Self.outerDiameter, height: Self.outerDiameter)
                .opacity(goal > 0 ? 1 : 0)
            Circle().stroke(Self.trackColor, lineWidth: 5)
                .frame(width: Self.innerDiameter, height: Self.innerDiameter)
            Circle().trim(from: 0, to: elapsed)
                .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: Self.innerDiameter, height: Self.innerDiameter)
                .opacity(elapsed > 0 ? 1 : 0)

            center
                .frame(width: Self.innerDiameter - 38)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.quick, value: filledDays)
    }
}

/// The week of the current program: one column per day (Monday first) with a kcal chip on top
/// and stacked G / P / L blocks whose heights follow the grams.
struct CoachingWeekColumns: View {
    let calories: Double
    let carbs: Double
    let protein: Double
    let fat: Double
    /// 0 = Monday … 6 = Sunday.
    let todayIndex: Int
    /// Days (0 = Monday) inside an exception period, drawn dimmed.
    var excludedDays: Set<Int> = []
    /// Weekly distribution (shifted days get their own values).
    var preferences: ProgramPreferences = .current
    /// Taller blocks and day letters under the columns (wizard summary).
    var isLarge = false

    private typealias Day = (calories: Double, protein: Double, carbs: Double, fat: Double)

    private var days: [Day] {
        (0..<7).map { preferences.dayTargets(weekday: $0, calories: calories, protein: protein,
                                             carbs: carbs, fat: fat) }
    }

    private static func grams(_ key: NutrientKey, of day: Day) -> Double {
        switch key {
        case .carbohydrates: return day.carbs
        case .protein: return day.protein
        case .totalFat: return day.fat
        default: return 0
        }
    }

    var body: some View {
        let days = self.days
        let maxGrams = days.map { max($0.carbs, $0.protein, $0.fat, 1) }.max() ?? 1
        HStack(alignment: .bottom, spacing: isLarge ? 9 : 7) {
            ForEach(0..<7, id: \.self) { index in
                column(index, day: days[index], maxGrams: maxGrams)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Measured on the reference: pill + blocks in 13 pt black text, 3 pt corners,
    /// block height = 36 pt + 73 pt × (grams / largest macro of the week).
    private func column(_ index: Int, day: Day, maxGrams: Double) -> some View {
        let isToday = index == todayIndex
        let scale: CGFloat = isLarge ? 1.1 : 1
        return VStack(spacing: 4) {
            Text(CoachingFormat.kcalNumber(day.calories))
                .font(Theme.font(13, .regular, relativeTo: .caption))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                // Reference: 37 × 23 pt capsule, narrower than the blocks, centered on the column.
                .frame(maxWidth: isLarge ? .infinity : 37)
                .frame(height: isLarge ? 26 : 23)
                .background(Theme.calories, in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            ForEach(Theme.macroOrder, id: \.self) { key in
                let value = Self.grams(key, of: day)
                Text("\(Formatters.number(value, maxFractionDigits: 0)) \(Theme.letter(for: key))")
                    .font(Theme.font(13, .regular, relativeTo: .caption))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: (36 + 73 * CGFloat(value / maxGrams)) * scale)
                    .background(Theme.color(for: key), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            if isLarge {
                Text(CoachingFormat.dayLetters[index])
                    .font(Theme.font(17, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 14)
            } else {
                Text(CoachingFormat.dayLetters[index])
                    .font(Theme.font(12, isToday ? .bold : .regular, relativeTo: .caption2))
                    .foregroundStyle(isToday ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.top, 4)
            }
        }
        .opacity(excludedDays.contains(index) ? 0.35 : 1)
    }

    private var accessibilityText: String {
        let parts = days.enumerated().map { index, day in
            let macros = Theme.macroOrder
                .map { "\($0.label) \(CoachingFormat.grams(Self.grams($0, of: day)))" }
                .joined(separator: ", ")
            return "\(CoachingFormat.dayLetters[index]) : \(Formatters.kcal(day.calories)), \(macros)"
        }
        return parts.joined(separator: " ; ")
    }
}
