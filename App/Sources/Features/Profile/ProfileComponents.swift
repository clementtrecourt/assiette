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
                    .frame(minWidth: 60, maxWidth: 120)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
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

/// Horizontal bar showing the share of energy from protein / carbs / fat.
struct ProfileMacroSplitView: View {
    var protein: Double
    var carbs: Double
    var fat: Double

    private struct Part: Identifiable {
        var key: NutrientKey
        var kcal: Double
        var id: NutrientKey { key }
    }

    private var parts: [Part] {
        [Part(key: .protein, kcal: protein * 4),
         Part(key: .carbohydrates, kcal: carbs * 4),
         Part(key: .totalFat, kcal: fat * 9)]
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
            .frame(height: 10)

            HStack {
                ForEach(parts) { part in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.color(for: part.key)).frame(width: 8, height: 8)
                        Text("\(part.key.shortLabel) \(Formatters.percent(fraction(part.kcal)))")
                    }
                    if part.key != .totalFat { Spacer(minLength: 4) }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func fraction(_ kcal: Double) -> Double {
        totalKcal > 0 ? kcal / totalKcal : 0
    }
}

/// Dismisses the keyboard (used by the keyboard toolbar "OK" button).
@MainActor
enum ProfileKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
