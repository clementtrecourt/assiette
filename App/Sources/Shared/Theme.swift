import SwiftUI

/// Design tokens — see DESIGN.md. The app is always dark (MacroFactor-like "Graphite" palette
/// on a near-black background).
enum Theme {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }

    // Surfaces
    static let background = hex(0x0A0A0A)
    static let card = hex(0x2C2C2E)
    static let cardBackground = card
    static let separator = hex(0x3A3A3C)
    static let textPrimary = hex(0xF2F2F7)
    static let textSecondary = hex(0x98989F)

    // Accent & semantic
    static let accent = hex(0x0A84FF)
    static let overTarget = hex(0xFF453A)

    // Nutrients
    static let calories = hex(0xE5E5EA)
    static let protein = hex(0xFF6482)
    static let carbs = hex(0x5EB1FF)
    static let fat = hex(0xFFC94D)
    static let fiber = hex(0x4CD38A)
    static let water = hex(0x40C8E0)
    static let weight = hex(0xBF5AF2)

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

    static let cornerRadius: CGFloat = 12
}

extension View {
    /// Dark app background behind List/Form/ScrollView content.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
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
                Capsule().fill(Theme.card)
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
