import SwiftUI

/// Compact row describing a loggable food: name, "brand · serving" line, kcal per serving
/// (or per 100 g / 100 ml) right-aligned and a P/G/L dots line (same style as the journal
/// timeline rows). Usable in any List.
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
            if let label = item.servingLabel, !label.isEmpty { return "\(label) (\(g))" }
            return "1 portion (\(g))"
        }
        return "100 \(item.unitSymbol)"
    }

    private var origin: String? {
        if let brand = item.brand, !brand.isEmpty { return brand }
        if let kind = item.kind { return kind.label }
        if item.source != .openNutrition { return item.source.label }
        return nil
    }

    private var subtitle: String {
        if let origin { return "\(origin) · \(referenceLabel)" }
        return referenceLabel
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                macroLine
            }

            Spacer(minLength: 4)

            calorieLabel
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var calorieLabel: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Formatters.number(reference.calories, maxFractionDigits: 0))
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var macroLine: some View {
        HStack(spacing: 10) {
            ForEach(NutrientKey.macros) { key in
                FoodRowMacro(key: key, grams: reference.value(key))
            }
        }
        .padding(.top, 1)
    }
}

/// "● P 12 g" — one macro with its color dot.
private struct FoodRowMacro: View {
    let key: NutrientKey
    let grams: Double

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Theme.color(for: key))
                .frame(width: 6, height: 6)
            Text("\(String(key.shortLabel.prefix(1))) \(Formatters.number(grams, maxFractionDigits: grams < 10 ? 1 : 0)) g")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
