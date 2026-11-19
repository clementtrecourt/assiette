import SwiftUI

/// Compact row describing a loggable food ("Minimal pro" search row): 32 pt icon tile, name
/// (optionally with the typed words in bold `textPrimary`), then "🔥 105 kcal • portion".
/// kcal are given per serving (or per 100 g / 100 ml). Usable in any List.
struct FoodRowView: View {
    let item: FoodItem
    /// Typed query whose words are emphasized in the name (nil / empty: plain name).
    private let highlight: String?

    init(item: FoodItem) {
        self.item = item
        self.highlight = nil
    }

    init(item: FoodItem, highlight: String?) {
        self.item = item
        self.highlight = highlight
    }

    private static let nameFont = Theme.font(15, .medium, relativeTo: .subheadline)
    private static let nameBoldFont = Theme.font(15, .bold, relativeTo: .subheadline)

    /// Nutrients for the reference quantity (one serving if known, else 100 g/ml).
    private var reference: NutrientValues {
        if let grams = item.servingGrams, grams > 0 { return item.per100.forGrams(grams) }
        return item.per100
    }

    private var referenceLabel: String {
        if let grams = item.servingGrams, grams > 0 {
            let g = "\(Formatters.number(grams, maxFractionDigits: 0)) \(item.unitSymbol)"
            if let label = item.servingLabel, !label.isEmpty { return "\(label), \(g)" }
            return "1 portion, \(g)"
        }
        return "100 \(item.unitSymbol)"
    }

    private var origin: String? {
        if let brand = item.brand, !brand.isEmpty { return brand }
        if item.source != .openNutrition { return item.source.label }
        return nil
    }

    private var subtitle: String {
        if let origin { return "\(referenceLabel) · \(origin)" }
        return referenceLabel
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FoodIconView(item: item, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(nameText)
                    .lineLimit(2)
                detailLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detailLine: some View {
        HStack(spacing: 5) {
            KcalLabel(kcal: reference.calories,
                      font: Theme.font(12, .medium, relativeTo: .caption),
                      color: Theme.textBody)
            Text("•")
                .font(Theme.caption)
                .foregroundStyle(Theme.textQuaternary)
            Text(subtitle)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    /// Name in `textBody`, every occurrence of the typed words in bold `textPrimary`.
    private var nameText: AttributedString {
        FoodRowView.highlighted(item.name, query: highlight)
    }

    static func highlighted(_ name: String, query: String?) -> AttributedString {
        var text = AttributedString(name)
        text.font = nameFont
        text.foregroundColor = Theme.textBody
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
