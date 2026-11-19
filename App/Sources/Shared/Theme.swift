import SwiftUI

import CoreText

/// Design tokens — see DESIGN.md. "Minimal pro" (proposal v5 #05): OpenNutrition-inspired,
/// monochrome zinc UI on near-black, hairlines instead of cards, DM Sans; only the macro
/// colors carry color. The app is always dark.
enum Theme {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }

    // Surfaces
    static let background = hex(0x050505)
    /// Slightly raised surface (sheets, rare cards, input fields).
    static let raised = hex(0x0F0F11)
    static let card = raised
    static let cardBackground = raised
    /// Hairline separators (1 px).
    static let separator = hex(0x1F1F23)
    /// Stronger hairline (inputs, chips, dashed "add" rows).
    static let separatorStrong = hex(0x2C2C31)

    // Text
    static let textPrimary = hex(0xFAFAFA)
    static let textBody = hex(0xD4D4D8)
    static let textSecondary = hex(0xA1A1AA)
    static let textTertiary = hex(0x71717A)
    static let textQuaternary = hex(0x52525B)

    // Accent & semantic — monochrome accent: white controls with near-black content.
    static let accent = textPrimary
    /// Foreground on top of `accent` fills (buttons, FAB, selected chips).
    static let onAccent = hex(0x050505)
    static let overTarget = hex(0xE45A5A)
    /// Small flame before kcal values (OpenNutrition style).
    static let flame = hex(0xF97316)

    // Nutrients (OpenNutrition dark palette)
    static let calories = hex(0x4EC2B8)
    static let protein = hex(0xA1B0E8)
    static let carbs = hex(0xF3BC52)
    static let fat = hex(0xE08B92)
    static let fiber = hex(0x7FCF9A)
    static let water = hex(0x6CC4E8)
    static let weight = hex(0xC4B5FD)

    static func color(for key: NutrientKey) -> Color {
        switch key {
        case .calories: calories
        case .protein: protein
        case .carbohydrates: carbs
        case .totalFat: fat
        case .dietaryFiber: fiber
        case .water: water
        default: textSecondary
        }
    }

    static let cornerRadius: CGFloat = 8
    static let hairline: CGFloat = 1

    // MARK: Typography (DM Sans, bundled in Resources/Fonts, registered at launch)

    enum Weight { case regular, medium, bold }

    /// DM Sans at a fixed size, scaling with Dynamic Type relative to `style`.
    static func font(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .regular: name = "DMSans-Regular"
        case .medium: name = "DMSans-Medium"
        case .bold: name = "DMSans-Bold"
        }
        return Font.custom(name, size: size, relativeTo: style)
    }

    /// Big remaining numbers in the journal header.
    static let numberLarge = font(22, .bold, relativeTo: .title2)
    static let title = font(20, .bold, relativeTo: .title3)
    static let headline = font(15, .medium, relativeTo: .headline)
    static let body = font(15, .regular, relativeTo: .body)
    static let callout = font(14, .regular, relativeTo: .callout)
    static let caption = font(12, .regular, relativeTo: .caption)
    static let label = font(11, .medium, relativeTo: .caption2)

    /// Registers the bundled DM Sans fonts. Call once at launch.
    static func registerFonts() {
        for name in ["DMSans-Regular", "DMSans-Medium", "DMSans-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Small orange flame + kcal value, as on OpenNutrition ("🔥 105 kcal").
struct KcalLabel: View {
    var kcal: Double
    var font: Font = Theme.caption
    var color: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.flame)
            Text("\(Formatters.number(kcal, maxFractionDigits: 0)) kcal")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

extension View {
    /// Dark app background behind List/Form/ScrollView content.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Default app typography and colors for a screen.
    func themedText() -> some View {
        font(Theme.body).foregroundStyle(Theme.textPrimary)
    }
}

/// Small horizontal progress bar used across the app.
struct ProgressBar: View {
    var value: Double
    var total: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separatorStrong)
                Capsule()
                    .fill(value > total * 1.05 && total > 0 ? Theme.overTarget : color)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: height)
        .animation(.snappy, value: value)
    }
}

/// Circular progress ring.
struct RingView: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(progress > 1.05 ? Theme.overTarget : color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.snappy, value: progress)
    }
}
