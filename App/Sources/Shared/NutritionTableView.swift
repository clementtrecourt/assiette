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
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }

            ForEach(Array(Self.primaryRows.enumerated()), id: \.offset) { index, row in
                if values[row.key] != nil || Self.alwaysShownKeys.contains(row.key) {
                    if index > 0 { Divider() }
                    nutrientRow(row.key, indent: row.indent, emphasized: !row.indent)
                }
            }

            let groups = extraGroups
            if !groups.isEmpty {
                Divider().padding(.top, 2)
                Button {
                    withAnimation(.snappy) { showAll.toggle() }
                } label: {
                    HStack {
                        Text(showAll ? "Masquer le détail" : "Voir tous les nutriments")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showAll ? 180 : 0))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAll {
                    ForEach(groups) { entry in
                        Text(entry.group.label.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        ForEach(Array(entry.keys.enumerated()), id: \.element) { index, key in
                            if index > 0 { Divider() }
                            nutrientRow(key, indent: false, emphasized: false)
                        }
                    }
                    .transition(.opacity)
                }
            }

            if showDailyPercent {
                Text("* % des apports de référence pour un adulte (2 000 kcal).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
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
                    .frame(width: 7, height: 7)
            }
            Text(indent ? "dont \(key.label.lowercased())" : key.label)
                .font(emphasized ? .subheadline.weight(.medium) : .subheadline)
                .foregroundStyle(indent ? .secondary : .primary)
                .padding(.leading, indent ? 15 : 0)
            Spacer(minLength: 8)
            Text(amount.map { Formatters.amount($0, of: key) } ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(amount == nil ? .secondary : .primary)
            if showDailyPercent {
                Text(percentText(key, amount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func percentText(_ key: NutrientKey, _ amount: Double?) -> String {
        guard let amount, let ref = key.dailyReference, ref > 0 else { return "" }
        return Formatters.percent(amount / ref)
    }
}
