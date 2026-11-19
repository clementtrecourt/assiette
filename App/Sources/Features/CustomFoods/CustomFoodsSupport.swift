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

/// Four-column kcal / protein / carbs / fat summary.
struct CustomFoodsMacroSummary: View {
    let values: NutrientValues

    var body: some View {
        HStack(spacing: 0) {
            column(Formatters.number(values.calories, maxFractionDigits: 0), label: "kcal", color: Theme.calories)
            column(grams(values.protein), label: "Protéines", color: Theme.protein)
            column(grams(values.carbs), label: "Glucides", color: Theme.carbs)
            column(grams(values.fat), label: "Lipides", color: Theme.fat)
        }
        .padding(.vertical, 4)
    }

    private func grams(_ value: Double) -> String {
        "\(Formatters.number(value, maxFractionDigits: value < 10 ? 1 : 0)) g"
    }

    private func column(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
