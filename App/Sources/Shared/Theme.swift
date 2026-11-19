import SwiftUI

enum Theme {
    static let accent = Color("AccentColor")
    static let calories = Color.orange
    static let protein = Color(red: 0.89, green: 0.27, blue: 0.36)
    static let carbs = Color(red: 0.20, green: 0.60, blue: 0.86)
    static let fat = Color(red: 0.96, green: 0.70, blue: 0.16)
    static let fiber = Color(red: 0.36, green: 0.70, blue: 0.36)
    static let water = Color(red: 0.25, green: 0.65, blue: 0.95)
    static let weight = Color.purple

    static func color(for key: NutrientKey) -> Color {
        switch key {
        case .calories: calories
        case .protein: protein
        case .carbohydrates: carbs
        case .totalFat: fat
        case .dietaryFiber: fiber
        case .water: water
        default: .secondary
        }
    }

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 16
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
                Capsule().fill(color.opacity(0.18))
                Capsule()
                    .fill(value > total * 1.05 && total > 0 ? Color.red : color)
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
                .stroke(progress > 1.05 ? Color.red : color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.snappy, value: progress)
    }
}
