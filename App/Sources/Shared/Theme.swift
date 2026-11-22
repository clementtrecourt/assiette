import SwiftUI

import CoreText

/// Design tokens — see DESIGN.md ("Coaching" design, 2026-11-20, mockups in
/// design/coaching-v1/maquettes.html). Dark grey background, slightly lighter cards, DM Sans,
/// macro color coding: calories blue, carbs green, protein coral, fat yellow.
/// Macros are ALWAYS listed in the order carbs / protein / fat (`Theme.macroOrder`).
enum Theme {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }

    // Surfaces
    static let background = hex(0x141414)
    /// Cards, sheets, input fields.
    static let raised = hex(0x1F1F1F)
    /// Controls on top of a card (round buttons, chips, keypad keys, icon tiles).
    static let raised2 = hex(0x383838)
    /// Value tiles of the insight cards, range chip group, "status" bar of the goal chart.
    static let tile = hex(0x2E2E2E)
    static let card = raised
    static let cardBackground = raised
    /// Card fill: subtle top-to-bottom gradient + `cardBorder` hairline (see `.themedCard()`).
    static let cardTop = hex(0x1F1F1F)
    static let cardBottom = hex(0x1F1F1F)
    static let cardBorder = Color.white.opacity(0.045)
    /// Hairline separators (1 px).
    static let separator = hex(0x2A2A2E)
    /// Stronger hairline (inputs, chips, ring and bar tracks).
    static let separatorStrong = hex(0x383838)
    /// Track behind progress rings and bars.
    static let track = hex(0x383838)

    // Text
    static let textPrimary = hex(0xFFFFFF)
    static let textBody = hex(0xD4D4D8)
    static let textSecondary = hex(0xA1A1AA)
    static let textTertiary = hex(0xA6A6A6)
    static let textQuaternary = hex(0x52525B)

    // Accent & semantic — white controls with near-black content.
    static let accent = textPrimary
    /// Foreground on top of `accent` fills (buttons, "+" tab, selected chips).
    static let onAccent = hex(0x141414)
    static let overTarget = hex(0xE45A5A)
    static let good = hex(0x5DBA87)
    /// Small flame before kcal values; also the expenditure color.
    static let flame = hex(0xF97316)
    /// Expenditure line and markers (measured on the reference recording).
    static let expenditure = hex(0xFF7954)
    /// "Flux range" band around the expenditure line.
    static let expenditureBand = hex(0x56423D)

    // Nutrients
    static let calories = hex(0x689FFA)
    static let carbs = hex(0x5DBA87)
    static let protein = hex(0xFF8660)
    static let fat = hex(0xFFD15E)
    static let fiber = hex(0x7FCF9A)
    static let water = hex(0x6CC4E8)
    /// Trend weight (line, scale dots, "away" bars of the goal chart).
    static let weight = hex(0xAA80F7)
    /// Darker weight shade: "towards" bars of the goal chart.
    static let weightDark = hex(0x4A298B)
    /// "Noise range" band between scale and trend weight.
    static let weightBand = hex(0x2B2338)
    /// Goal chart on scale weight: away (light) / towards (dark) greens.
    static let goalAway = hex(0x53B17C)
    static let goalTowards = hex(0x00482B)
    /// Calorie target line (energy balance, "Objectifs caloriques").
    static let targetLine = hex(0xFFD15E)

    /// Ring gradients (light → dark), used by the calorie ring and the check-in countdown.
    static let caloriesGradient = [hex(0x9CC2FF), hex(0x4F86EC)]
    static let goodGradient = [hex(0x8BE0B0), hex(0x43A877)]

    /// Display order of the macros everywhere in the app: carbs, protein, fat.
    static let macroOrder: [NutrientKey] = [.carbohydrates, .protein, .totalFat]

    /// One-letter macro abbreviation (French): G, P, L.
    static func letter(for key: NutrientKey) -> String {
        switch key {
        case .carbohydrates: "G"
        case .protein: "P"
        case .totalFat: "L"
        default: ""
        }
    }

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
    /// Cards (dashboard tiles, food cards, program cards).
    static let cardRadius: CGFloat = 10
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

    /// Screen titles (ACCUEIL, AUJOURD'HUI, PROGRAMME): Archivo Expanded ExtraBold, uppercase.
    static func screenTitle(_ size: CGFloat = 24) -> Font {
        Font.custom("ArchivoExpanded-ExtraBold", size: size, relativeTo: .largeTitle)
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
        for name in ["DMSans-Regular", "DMSans-Medium", "DMSans-Bold", "ArchivoExpanded-ExtraBold"] {
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

extension Animation {
    /// The app's standard motion: quick and without bounce (plain `.snappy` lasts 0.5 s).
    static let quick = Animation.snappy(duration: 0.24)
}

extension View {
    /// Card surface: gradient fill, near-invisible border, `Theme.cardRadius` corners.
    func themedCard(radius: CGFloat = Theme.cardRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }

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
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(value > total * 1.05 && total > 0 ? Theme.overTarget : color)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: height)
        .animation(.quick, value: value)
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
        .animation(.quick, value: progress)
    }
}
