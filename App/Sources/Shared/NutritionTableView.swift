import SwiftUI

/// Nutrition facts table, grouped by `NutrientKey.Group`. A plain VStack (not a List), so it
/// can be embedded in a List row, a ScrollView or a card.
///
/// Energy, macronutrients and the most common sub-values (saturated fats, sugars, fiber,
/// sodium) are always visible; other known nutrients are behind "Voir tous les nutriments".
struct NutritionTableView: View {
    let values: NutrientValues
    var showDailyPercent: Bool = true

    @State private var showAll = false

    init(values: NutrientValues, showDailyPercent: Bool = true) {
        self.values = values
        self.showDailyPercent = showDailyPercent
    }

    /// Always displayed, in this order (shown as "—" when unknown for the headline ones).
    private struct PrimaryRow {
        let key: NutrientKey
        let indent: Bool
    }

    private struct ExtraGroup: Identifiable {
        let group: NutrientKey.Group
        let keys: [NutrientKey]
        var id: String { group.rawValue }
    }

    private static let primaryRows: [PrimaryRow] = [
        PrimaryRow(key: .calories, indent: false),
        PrimaryRow(key: .totalFat, indent: false),
        PrimaryRow(key: .saturatedFats, indent: true),
        PrimaryRow(key: .carbohydrates, indent: false),
        PrimaryRow(key: .totalSugars, indent: true),
        PrimaryRow(key: .dietaryFiber, indent: false),
        PrimaryRow(key: .protein, indent: false),
        PrimaryRow(key: .sodium, indent: false),
    ]

    private static let alwaysShownKeys: Set<NutrientKey> = [.calories, .protein, .carbohydrates, .totalFat]

    private var primaryKeys: Set<NutrientKey> { Set(Self.primaryRows.map(\.key)) }

    /// Known nutrients not in the primary block, grouped.
    private var extraGroups: [ExtraGroup] {
        let primary = primaryKeys
        let known = values.knownKeys.filter { !primary.contains($0) }
        return NutrientKey.Group.allCases.compactMap { group -> ExtraGroup? in
            let keys = known.filter { $0.group == group }
            return keys.isEmpty ? nil : ExtraGroup(group: group, keys: keys)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDailyPercent {
                HStack {
                    Spacer()
                    Text("% AR*")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.bottom, 4)
            }

            ForEach(Array(Self.primaryRows.enumerated()), id: \.offset) { index, row in
                if values[row.key] != nil || Self.alwaysShownKeys.contains(row.key) {
                    if index > 0 { NutritionTableHairline() }
                    nutrientRow(row.key, indent: row.indent, emphasized: !row.indent)
                }
            }

            let groups = extraGroups
            if !groups.isEmpty {
                NutritionTableHairline().padding(.top, 2)
                Button {
                    withAnimation(.snappy) { showAll.toggle() }
                } label: {
                    HStack {
                        Text(showAll ? "Masquer le détail" : "Voir tous les nutriments")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showAll ? 180 : 0))
                    }
                    .font(Theme.font(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAll {
                    ForEach(groups) { entry in
                        Text(entry.group.label.uppercased())
                            .font(Theme.label)
                            .tracking(0.6)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                        ForEach(Array(entry.keys.enumerated()), id: \.element) { index, key in
                            if index > 0 { NutritionTableHairline() }
                            nutrientRow(key, indent: false, emphasized: false)
                        }
                    }
                    .transition(.opacity)
                }
            }

            if showDailyPercent {
                Text("* % des apports de référence pour un adulte (2 000 kcal).")
                    .font(Theme.font(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func nutrientRow(_ key: NutrientKey, indent: Bool, emphasized: Bool) -> some View {
        let amount = values[key]
        HStack(alignment: .center, spacing: 8) {
            if key.group == .macros || key == .calories {
                Circle()
                    .fill(Theme.color(for: key))
                    .frame(width: 6, height: 6)
            }
            Text(indent ? "dont \(key.label.lowercased())" : key.label)
                .font(emphasized ? Theme.font(14, .medium, relativeTo: .subheadline) : Theme.callout)
                .foregroundStyle(indent ? Theme.textTertiary : Theme.textBody)
                .padding(.leading, indent ? 14 : 0)
            Spacer(minLength: 8)
            amountLabel(key, amount)
            if showDailyPercent {
                Text(percentText(key, amount))
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// Value in primary text, unit in secondary text ("12,3" + "g").
    @ViewBuilder
    private func amountLabel(_ key: NutrientKey, _ amount: Double?) -> some View {
        if let amount {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(amountNumber(amount, of: key))
                    .font(Theme.font(14, .medium, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(key.unit)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        } else {
            Text("—")
                .font(Theme.callout)
                .foregroundStyle(Theme.textQuaternary)
        }
    }

    /// Number part of `Formatters.amount` (same precision rules), without the unit.
    private func amountNumber(_ amount: Double, of key: NutrientKey) -> String {
        let full = Formatters.amount(amount, of: key)
        let suffix = " \(key.unit)"
        guard !key.unit.isEmpty, full.hasSuffix(suffix) else { return full }
        return String(full.dropLast(suffix.count))
    }

    private func percentText(_ key: NutrientKey, _ amount: Double?) -> String {
        guard let amount, let ref = key.dailyReference, ref > 0 else { return "" }
        return Formatters.percent(amount / ref)
    }
}

/// Hairline (Theme.separator), as everywhere in the "Minimal pro" design.
private struct NutritionTableHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
    }
}
