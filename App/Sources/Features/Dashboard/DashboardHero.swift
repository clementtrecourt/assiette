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
        HStack(alignment: .center, spacing: 4) {
            leadingSide
                .frame(maxWidth: .infinity)
            DashboardCalorieRing(progress: progress, isOver: isOver) {
                center
            }
            DashboardHeroSide(caption: "Objectif", value: target, color: Theme.textPrimary)
                .frame(maxWidth: .infinity)
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
        return VStack(spacing: 3) {
            DashboardCapsLabel(text: caption)
            Text(Formatters.number(value, maxFractionDigits: 0))
                .font(Theme.font(32, .bold, relativeTo: .largeTitle))
                .tracking(-1.2)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text("sur \(Formatters.kcal(target))")
                .font(Theme.font(12, .regular, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 96)
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
            DashboardCapsLabel(text: caption)
            Text(Formatters.number(value, maxFractionDigits: 0))
                .font(Theme.font(20, .bold, relativeTo: .title3))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("kcal")
                .font(Theme.font(12, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Ring

/// 140 pt ring: thin gradient arc on a track, inner ring of fine ticks, white dot at the arc end.
struct DashboardCalorieRing<Center: View>: View {
    let progress: Double
    let isOver: Bool
    let center: Center

    private let size: CGFloat = 140
    private let lineWidth: CGFloat = 6
    /// Arc radius = size / 2 − arcInset.
    private let arcInset: CGFloat = 6
    /// Tick ring radius = size / 2 − tickInset.
    private let tickInset: CGFloat = 18
    private let tickCount = 64

    init(progress: Double, isOver: Bool, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.isOver = isOver
        self.center = center()
    }

    private var arcStyle: AnyShapeStyle {
        if isOver { return AnyShapeStyle(Theme.overTarget) }
        return AnyShapeStyle(LinearGradient(colors: Theme.caloriesGradient,
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        let tickRadius = size / 2 - tickInset
        let tickGap = max(2 * CGFloat.pi * tickRadius / CGFloat(tickCount) - 0.9, 0.5)
        ZStack {
            Circle()
                .stroke(Theme.track, style: StrokeStyle(lineWidth: 3, dash: [0.9, tickGap]))
                .padding(tickInset)
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
                .padding(arcInset)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(arcStyle, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(arcInset)
            if clamped > 0 {
                DashboardRingDot(progress: clamped, inset: arcInset, radius: 6)
                    .fill(Theme.background)
                DashboardRingDot(progress: clamped, inset: arcInset, radius: 3.6)
                    .fill(Theme.textPrimary)
            }
            center
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: clamped)
    }
}

/// Small disc sitting on the ring at `progress` (animatable, so it follows the arc).
private struct DashboardRingDot: Shape {
    var progress: Double
    let inset: CGFloat
    let radius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let ringRadius = min(rect.width, rect.height) / 2 - inset
        let angle = -Double.pi / 2 + 2 * Double.pi * progress
        let x = rect.midX + ringRadius * CGFloat(cos(angle))
        let y = rect.midY + ringRadius * CGFloat(sin(angle))
        return Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
}

// MARK: - Macro bars

/// G / P / L columns: colored dot + label, 5 pt bar, "80 / 156 g" (or remaining grams).
struct DashboardMacroBars: View {
    let totals: NutrientValues
    let targets: DashboardTargets
    let showRemaining: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
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
            main = Text(Formatters.number(shown, maxFractionDigits: 0)).foregroundColor(Theme.textBody)
        }
        let rest = Text(" / \(Formatters.number(target, maxFractionDigits: 0)) g").foregroundColor(Theme.textTertiary)
        let status = isOver
            ? "\(Formatters.number(eaten - target, maxFractionDigits: 0)) g en trop"
            : (showRemaining ? "\(Formatters.number(target - eaten, maxFractionDigits: 0)) g restants"
                             : "\(Formatters.number(eaten, maxFractionDigits: 0)) g mangés")

        return VStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(key.label.uppercased())
                    .font(Theme.font(11, .bold, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            DashboardBar(fraction: fraction, color: isOver ? Theme.overTarget : color, height: 5)
            (main + rest)
                .font(Theme.font(12, .medium, relativeTo: .caption))
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
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
        )
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(Theme.font(13, selected ? .bold : .medium, relativeTo: .subheadline))
                .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 18)
                .frame(minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.accent : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
