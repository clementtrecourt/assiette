import SwiftUI

/// Calorie hero: "Mangé" | ring with the remaining (or eaten) kcal | "Objectif".
struct DashboardHero: View {
    let consumed: Double
    let target: Double
    let showRemaining: Bool

    private var isOver: Bool { target > 0 && consumed > target }
    private var excess: Double { max(consumed - target, 0) }
    private var remaining: Double { max(target - consumed, 0) }

    /// Ring fill: remaining share in "Restant" mode, eaten share in "Mangé" mode, full when over.
    private var progress: Double {
        guard target > 0 else { return 0 }
        if isOver { return 1 }
        return showRemaining ? remaining / target : consumed / target
    }

    var body: some View {
        // Reference: the three captions (Mangé / Restant / Objectif) sit on one line, so the
        // sides are 7.5 pt lower than the ring's centre.
        HStack(alignment: .center, spacing: 4) {
            leadingSide
                .frame(maxWidth: .infinity)
                .offset(y: 7.5)
            DashboardCalorieRing(progress: progress, isOver: isOver) {
                center
            }
            DashboardHeroSide(caption: "Objectif", value: target, color: Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .offset(y: 7.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var leadingSide: some View {
        if showRemaining {
            DashboardHeroSide(caption: "Mangé", value: consumed, color: Theme.textPrimary)
        } else if isOver {
            DashboardHeroSide(caption: "En trop", value: excess, color: Theme.overTarget)
        } else {
            DashboardHeroSide(caption: "Restant", value: remaining, color: Theme.textPrimary)
        }
    }

    private var center: some View {
        let caption: String
        let value: Double
        let color: Color
        if showRemaining {
            caption = isOver ? "En trop" : "Restant"
            value = isOver ? excess : remaining
            color = isOver ? Theme.overTarget : Theme.textPrimary
        } else {
            caption = "Mangé"
            value = consumed
            color = isOver ? Theme.overTarget : Theme.textPrimary
        }
        return VStack(spacing: 0) {
            Text(Formatters.number(value, maxFractionDigits: 0))
                .font(Theme.font(36, .bold, relativeTo: .largeTitle))
                .tracking(-1)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(caption)
                .font(Theme.font(16, .regular, relativeTo: .callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 124)
    }

    private var accessibilityText: String {
        let eaten = "Mangé \(Formatters.kcal(consumed))"
        let goal = "objectif \(Formatters.kcal(target))"
        let rest = isOver ? "\(Formatters.kcal(excess)) en trop" : "\(Formatters.kcal(remaining)) restantes"
        return "\(eaten), \(goal), \(rest)"
    }
}

/// Tiny uppercase caption ("RESTANT", "MANGÉ", "OBJECTIF").
struct DashboardCapsLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.font(10, .bold, relativeTo: .caption2))
            .tracking(0.9)
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
    }
}

private struct DashboardHeroSide: View {
    let caption: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(Formatters.number(value, maxFractionDigits: 0))
                .font(Theme.font(22, .bold, relativeTo: .title3))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(Theme.font(16, .regular, relativeTo: .callout))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Ring

/// The foreground and track use the same 270-degree arc, open at the bottom.
struct DashboardCalorieRing<Center: View>: View {
    let progress: Double
    let isOver: Bool
    @ViewBuilder let center: () -> Center

    var body: some View {
        let fraction = CGFloat(min(max(progress, 0), 1))
        let stroke = StrokeStyle(lineWidth: 5, lineCap: .round)
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.track, style: stroke)
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0.75 * (1 - fraction), to: 0.75)
                .stroke(isOver ? Theme.overTarget : Theme.calories, style: stroke)
                .rotationEffect(.degrees(135))
                .opacity(fraction > 0 ? 1 : 0)
            center()
        }
        .padding(4)
        .frame(width: 178, height: 178)
        // No implicit animation: the ring is drawn filled when Accueil opens (as on the
        // reference); the Mangé / Restant toggle animates it with `withAnimation`.
    }
}

// MARK: - Macro bars

/// G / P / L columns: colored dot + label, 5 pt bar, "80 / 156 g" (or remaining grams).
struct DashboardMacroBars: View {
    let totals: NutrientValues
    let targets: DashboardTargets
    let showRemaining: Bool

    var body: some View {
        // Reference: 92 pt bars, 37 pt apart.
        HStack(alignment: .top, spacing: 36) {
            ForEach(Theme.macroOrder, id: \.self) { key in
                column(key)
            }
        }
    }

    private func column(_ key: NutrientKey) -> some View {
        let eaten = totals.value(key)
        let target = targets.value(for: key)
        let isOver = target > 0 && eaten > target
        let color = Theme.color(for: key)
        let fraction: Double
        if isOver {
            fraction = 1
        } else if target > 0 {
            fraction = showRemaining ? (target - eaten) / target : eaten / target
        } else {
            fraction = 0
        }
        let main: Text
        if isOver {
            let shown = showRemaining
                ? "+" + Formatters.number(eaten - target, maxFractionDigits: 0)
                : Formatters.number(eaten, maxFractionDigits: 0)
            main = Text(shown).foregroundColor(Theme.overTarget)
        } else {
            let shown = showRemaining ? target - eaten : eaten
            main = Text(Formatters.number(shown, maxFractionDigits: 0)).foregroundColor(Theme.textPrimary)
        }
        let rest = Text(" / \(Formatters.number(target, maxFractionDigits: 0))g").foregroundColor(Theme.textPrimary)
        let status = isOver
            ? "\(Formatters.number(eaten - target, maxFractionDigits: 0)) g en trop"
            : (showRemaining ? "\(Formatters.number(target - eaten, maxFractionDigits: 0)) g restants"
                             : "\(Formatters.number(eaten, maxFractionDigits: 0)) g mangés")

        // Reference: label → bar 14 pt, bar → values 14 pt (centres).
        return VStack(spacing: 1) {
            Text(key.label)
                .font(Theme.font(16, .regular, relativeTo: .callout))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            DashboardBar(fraction: fraction, color: isOver ? Theme.overTarget : color,
                         fromTrailing: showRemaining)
            (main + rest)
                .font(Theme.font(16, .regular, relativeTo: .callout))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.label) : \(status), objectif \(Formatters.number(target, maxFractionDigits: 0)) g")
    }
}

// MARK: - Mode picker

/// "Mangé / Restant" segmented control (selected = white fill, near-black text).
struct DashboardModePicker: View {
    @Binding var showRemaining: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("Mangé", selected: !showRemaining) { showRemaining = false }
            segment("Restant", selected: showRemaining) { showRemaining = true }
        }
        .padding(2)
        .background(Theme.raised2, in: Capsule())
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.quick) { action() }
        } label: {
            // Reference: 40 pt tall, ~100 pt segments, 15 pt regular text (white when idle).
            Text(title)
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                .frame(width: 100, height: 36)
                .background(
                    Capsule()
                        .fill(selected ? Theme.accent : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
