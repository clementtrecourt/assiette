import SwiftUI

/// Compact row describing a loggable food: name, brand / kind line, kcal per serving
/// (or per 100 g / 100 ml) and a P/G/L mini summary. Usable in any List.
struct FoodRowView: View {
    let item: FoodItem

    init(item: FoodItem) {
        self.item = item
    }

    /// Nutrients for the reference quantity (one serving if known, else 100 g/ml).
    private var reference: NutrientValues {
        if let grams = item.servingGrams, grams > 0 { return item.per100.forGrams(grams) }
        return item.per100
    }

    private var referenceLabel: String {
        if let grams = item.servingGrams, grams > 0 {
            let g = "\(Formatters.number(grams, maxFractionDigits: 0)) \(item.unitSymbol)"
            if let label = item.servingLabel { return "\(label) · \(g)" }
            return "portion · \(g)"
        }
        return "100 \(item.unitSymbol)"
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let brand = item.brand, !brand.isEmpty {
            parts.append(brand)
        } else if let kind = item.kind {
            parts.append(kind.label)
        } else if item.source != .openNutrition {
            parts.append(item.source.label)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var iconName: String {
        switch item.source {
        case .custom: "person.crop.circle"
        case .openFoodFacts: "barcode"
        case .quickAdd: "bolt.fill"
        case .openNutrition: item.kind?.systemImage ?? "leaf"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                macroLine
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.number(reference.calories, maxFractionDigits: 0))
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.primary)
                + Text(" kcal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(referenceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var macroLine: some View {
        HStack(spacing: 8) {
            macro("P", reference.protein, Theme.protein)
            macro("G", reference.carbs, Theme.carbs)
            macro("L", reference.fat, Theme.fat)
        }
        .font(.caption2.monospacedDigit())
    }

    private func macro(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(letter) \(Formatters.number(grams, maxFractionDigits: grams < 10 ? 1 : 0)) g")
                .foregroundStyle(.secondary)
        }
    }
}
