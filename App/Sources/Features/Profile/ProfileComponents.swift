import SwiftUI
import UIKit

/// Decimal text field row ("Poids  72,5 kg") accepting both "," and "." as separator.
struct ProfileNumberField: View {
    private let title: String
    @Binding private var value: Double?
    private let unit: String
    private let maxFractionDigits: Int
    private let placeholder: String

    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Double?>, unit: String, maxFractionDigits: Int = 1,
         placeholder: String = "")
    {
        self.title = title
        self._value = value
        self.unit = unit
        self.maxFractionDigits = maxFractionDigits
        self.placeholder = placeholder
    }

    init(_ title: String, value: Binding<Double>, unit: String, maxFractionDigits: Int = 1,
         placeholder: String = "")
    {
        let optional = Binding<Double?>(
            get: { value.wrappedValue },
            set: { newValue in
                if let newValue { value.wrappedValue = newValue }
            }
        )
        self.init(title, value: optional, unit: unit, maxFractionDigits: maxFractionDigits,
                  placeholder: placeholder)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(placeholder, text: $text)
                    .keyboardType(maxFractionDigits > 0 ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 60, maxWidth: 120)
                Text(unit)
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
        } label: {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
        }
        .onAppear { text = Self.format(value, digits: maxFractionDigits) }
        .onChange(of: text) {
            let parsed = Self.parse(text)
            if parsed != value { value = parsed }
        }
        .onChange(of: value) {
            if !focused { text = Self.format(value, digits: maxFractionDigits) }
        }
        .onChange(of: focused) {
            if !focused { text = Self.format(value, digits: maxFractionDigits) }
        }
    }

    static func format(_ value: Double?, digits: Int) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never)
            .locale(Formatters.locale))
    }

    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let v = Double(cleaned), v.isFinite, v >= 0 else { return nil }
        return v
    }
}

/// Horizontal bar showing the share of energy from carbs / protein / fat.
struct ProfileMacroSplitView: View {
    var protein: Double
    var carbs: Double
    var fat: Double

    private struct Part: Identifiable {
        var key: NutrientKey
        var kcal: Double
        var id: NutrientKey { key }
    }

    /// Always carbs / protein / fat (`Theme.macroOrder`).
    private var parts: [Part] {
        Theme.macroOrder.map { key in
            switch key {
            case .carbohydrates: return Part(key: key, kcal: carbs * 4)
            case .protein: return Part(key: key, kcal: protein * 4)
            default: return Part(key: key, kcal: fat * 9)
            }
        }
    }

    private var totalKcal: Double { parts.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(Theme.color(for: part.key))
                            .frame(width: max(0, geo.size.width - 4) * fraction(part.kcal))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)

            HStack {
                ForEach(parts) { part in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.color(for: part.key)).frame(width: 6, height: 6)
                        Text("\(part.key.shortLabel) \(Formatters.percent(fraction(part.kcal)))")
                            .monospacedDigit()
                    }
                    if part.key != Theme.macroOrder.last { Spacer(minLength: 4) }
                }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func fraction(_ kcal: Double) -> Double {
        totalKcal > 0 ? kcal / totalKcal : 0
    }
}

/// Full-width primary button: white fill (`Theme.accent`), near-black label (`Theme.onAccent`), radius 8.
struct ProfilePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .bold, relativeTo: .headline))
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(isEnabled ? Theme.accent.opacity(configuration.isPressed ? 0.75 : 1) : Theme.separatorStrong)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

/// "● Protéines ....... 120 g" target row with the nutrient color dot.
struct ProfileTargetRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.font(15, .medium, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Section header for Profile lists: tiny uppercase label in `textTertiary` (DESIGN.md).
struct ProfileSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Theme.label)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// Section footer text for Profile lists.
struct ProfileSectionFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.textTertiary)
    }
}

extension View {
    /// Hairline list row: page background + `Theme.separator` separators.
    func profileListRow() -> some View {
        listRowBackground(Theme.background)
            .listRowSeparatorTint(Theme.separator)
    }
}

/// Dismisses the keyboard (used by the keyboard toolbar "OK" button).
@MainActor
enum ProfileKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
