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

/// Four-column Kcal / Prot. / Gluc. / Lip. summary (journal header style).
struct CustomFoodsMacroSummary: View {
    let values: NutrientValues

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            column("Kcal", Formatters.number(values.calories, maxFractionDigits: 0), unit: nil, color: Theme.calories)
            column("Prot.", grams(values.protein), unit: "g", color: Theme.protein)
            column("Gluc.", grams(values.carbs), unit: "g", color: Theme.carbs)
            column("Lip.", grams(values.fat), unit: "g", color: Theme.fat)
        }
        .padding(.vertical, 4)
    }

    private func grams(_ value: Double) -> String {
        Formatters.number(value, maxFractionDigits: value < 10 ? 1 : 0)
    }

    private func column(_ label: String, _ value: String, unit: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Capsule()
                .fill(color)
                .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Full-width accent button, radius 12.
struct CustomFoodsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
