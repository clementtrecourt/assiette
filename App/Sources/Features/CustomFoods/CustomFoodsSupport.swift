import SwiftUI

/// Number parsing / formatting for editable text fields (French decimal comma accepted).
enum CustomFoodsNumber {
    /// Parses "12,5", "12.5", "1 234,5". Returns nil for empty or invalid text.
    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// Text suitable for an editable field: no grouping separator, French decimal comma.
    static func text(_ value: Double, maxFractionDigits: Int = 2) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...maxFractionDigits))
                .grouping(.never)
                .locale(Formatters.locale)
        )
    }
}

/// Small text helpers shared by the custom foods screens.
enum CustomFoodsText {
    /// Lowercased, accent-folded.
    static func fold(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// True when every word of `query` appears in the name or brand (accent-insensitive).
    static func matches(_ query: String, name: String, brand: String?) -> Bool {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = fold(name + " " + (brand ?? ""))
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Trimmed text, or nil when blank.
    static func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Four-column Kcal / Prot. / Gluc. / Lip. summary (journal header style): tiny uppercase label in
/// the macro color, big number, 2 pt bar (share of energy), caption; columns split by hairlines.
struct CustomFoodsMacroSummary: View {
    let values: NutrientValues

    var body: some View {
        let kcal = values.calories
        HStack(alignment: .top, spacing: 0) {
            column("Kcal", Formatters.number(kcal, maxFractionDigits: 0), unit: nil,
                   color: Theme.calories, share: kcal > 0 ? 1 : 0, caption: "kcal")
            column("Prot.", grams(values.protein), unit: "g", color: Theme.protein,
                   share: share(values.protein * 4, of: kcal), caption: percent(values.protein * 4, of: kcal))
                .overlay(alignment: .leading) { rule }
            column("Gluc.", grams(values.carbs), unit: "g", color: Theme.carbs,
                   share: share(values.carbs * 4, of: kcal), caption: percent(values.carbs * 4, of: kcal))
                .overlay(alignment: .leading) { rule }
            column("Lip.", grams(values.fat), unit: "g", color: Theme.fat,
                   share: share(values.fat * 9, of: kcal), caption: percent(values.fat * 9, of: kcal))
                .overlay(alignment: .leading) { rule }
        }
    }

    /// Vertical hairline between columns.
    private var rule: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: Theme.hairline)
    }

    private func grams(_ value: Double) -> String {
        Formatters.number(value, maxFractionDigits: value < 10 ? 1 : 0)
    }

    private func share(_ macroKcal: Double, of kcal: Double) -> Double {
        guard kcal > 0 else { return 0 }
        return min(max(macroKcal / kcal, 0), 1)
    }

    private func percent(_ macroKcal: Double, of kcal: Double) -> String {
        guard kcal > 0 else { return "—" }
        return "\(Formatters.number(macroKcal / kcal * 100, maxFractionDigits: 0)) %"
    }

    private func column(_ label: String, _ value: String, unit: String?, color: Color,
                        share: Double, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(Theme.label)
                .tracking(0.6)
                .foregroundStyle(color)
                .lineLimit(1)
            valueLine(value, unit: unit)
                .padding(.top, 5)
            ProgressBar(value: share, total: 1, color: color, height: 2)
                .padding(.top, 7)
                .padding(.bottom, 5)
            Text(caption)
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueLine(_ value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value)
                .font(Theme.numberLarge)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let unit {
                Text(unit)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Full-width primary button: white fill (`Theme.accent`), near-black label, radius 8.
struct CustomFoodsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(isEnabled ? Theme.accent.opacity(configuration.isPressed ? 0.75 : 1) : Theme.separatorStrong)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// Compact (content-sized) primary button, used in empty states.
struct CustomFoodsCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// Selectable chip: selected = white fill + near-black text; unselected = 1 px outline + secondary text.
struct CustomFoodsChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Capsule().fill(isSelected ? Theme.accent : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Theme.separatorStrong, lineWidth: Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// Section header: tiny uppercase label in `textTertiary`, optional trailing value.
struct CustomFoodsSectionHeader: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .monospacedDigit()
            }
        }
        .font(Theme.label)
        .tracking(0.7)
        .foregroundStyle(Theme.textTertiary)
        .textCase(nil)
    }
}

/// Section footer text (caption, `textTertiary` unless a color is given).
struct CustomFoodsFooterText: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = Theme.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(color)
    }
}

/// "+" in a small dashed square + label, like the journal "Ajouter" row.
struct CustomFoodsAddLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.separatorStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                )
            Text(title)
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// Hairline list rows on the app background.
    func customFoodsRow() -> some View {
        listRowBackground(Theme.background)
            .listRowSeparatorTint(Theme.separator)
            .listSectionSeparatorTint(Theme.separator)
    }

    /// Raised input: `Theme.raised` fill, 1 px `separatorStrong` border, radius 8.
    func customFoodsInputField(minHeight: CGFloat = 38) -> some View {
        font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
            )
    }
}
