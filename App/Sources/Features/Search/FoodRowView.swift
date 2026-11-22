import SwiftUI

/// Food row of the add flow: 38 pt icon, one-line name (typed words in bold, brand muted), then
/// "148🔥  18G  2P  7L  •  32 g" for the quantity that would be logged (journal card format).
/// Usable in any List or stack. Macros are listed G / P / L (`Theme.macroOrder`).
struct FoodRowView: View {
    let item: FoodItem
    /// Typed query whose words are emphasized in the name (nil / empty: plain name).
    private let highlight: String?
    /// Quantity shown and used for the values; nil = one serving if known, else 100 g / ml.
    private let grams: Double?

    init(item: FoodItem) {
        self.init(item: item, grams: nil, highlight: nil)
    }

    init(item: FoodItem, highlight: String?) {
        self.init(item: item, grams: nil, highlight: highlight)
    }

    init(item: FoodItem, grams: Double?, highlight: String? = nil) {
        self.item = item
        self.grams = grams
        self.highlight = highlight
    }

    private static let nameFont = Theme.font(15, .regular, relativeTo: .subheadline)
    private static let nameBoldFont = Theme.font(15, .bold, relativeTo: .subheadline)
    private static let brandFont = Theme.font(15, .regular, relativeTo: .subheadline)
    private static let detailFont = Theme.font(14, .regular, relativeTo: .caption)

    /// Grams used for the detail line.
    private var shownGrams: Double {
        if let grams, grams > 0 { return grams }
        if item.source == .quickAdd { return 100 }
        if let serving = item.servingGrams, serving > 0 { return serving }
        return 100
    }

    private var values: NutrientValues { item.per100.forGrams(shownGrams) }

    private var quantityLabel: String {
        if item.source == .quickAdd { return "Ajout rapide" }
        return "\(Formatters.number(shownGrams, maxFractionDigits: 0)) \(item.unitSymbol)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FoodIconView(item: item, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                // One line like MF: name then brand, tail-truncated together.
                Text(nameText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                detailLine
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "148🔥  18G  2P  7L  •  32 g" in one light grey, like the journal cards.
    private var detailLine: some View {
        let v = values
        let kcal = Text(Formatters.number(v.calories, maxFractionDigits: 0))
            + Text(Image(systemName: "flame.fill")).font(.system(size: 10, weight: .semibold))
        let macros = Theme.macroOrder
            .map { "\(Formatters.number(v.value($0), maxFractionDigits: 0))\(Theme.letter(for: $0))" }
            .joined(separator: "  ")
        return (kcal + Text("  " + macros + "  •  " + quantityLabel))
            .font(FoodRowView.detailFont)
            .monospacedDigit()
            .foregroundStyle(Theme.textBody)
    }

    /// Name in `textBody` (typed words bold `textPrimary`), then the brand in `textTertiary`.
    private var nameText: AttributedString {
        var text = FoodRowView.highlighted(item.name, query: highlight)
        if let brand = item.brand, !brand.isEmpty {
            var suffix = AttributedString(" · \(brand)")
            suffix.font = FoodRowView.brandFont
            suffix.foregroundColor = Theme.textTertiary
            text.append(suffix)
        }
        return text
    }

    static func highlighted(_ name: String, query: String?) -> AttributedString {
        var text = AttributedString(name)
        text.font = nameFont
        text.foregroundColor = Theme.textPrimary
        guard let query, !query.isEmpty else { return text }
        let words = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for word in words {
            var searchRange = name.startIndex..<name.endIndex
            while let found = name.range(of: word, options: options, range: searchRange) {
                if let attributed = Range<AttributedString.Index>(found, in: text) {
                    text[attributed].font = nameBoldFont
                    text[attributed].foregroundColor = Theme.textPrimary
                }
                guard found.upperBound < name.endIndex else { break }
                searchRange = found.upperBound..<name.endIndex
            }
        }
        return text
    }
}
