import SwiftData
import SwiftUI
import UIKit

private enum QuickAddField: Hashable {
    case calories, carbs, protein, fat, name

    /// Keyboard "next" order: kcal → G → P → L → name.
    var next: QuickAddField? {
        switch self {
        case .calories: .carbs
        case .carbs: .protein
        case .protein: .fat
        case .fat: .name
        case .name: nil
        }
    }

    var title: String {
        switch self {
        case .calories: "Énergie"
        case .carbs: "Glucides"
        case .protein: "Protéines"
        case .fat: "Lipides"
        case .name: "Nom"
        }
    }

    static func field(for key: NutrientKey) -> QuickAddField {
        switch key {
        case .carbohydrates: .carbs
        case .protein: .protein
        default: .fat
        }
    }
}

/// Log calories (and optionally G / P / L) typed by hand, at the context time.
/// The energy field is focused on appear. `QuickAddSheet(context:onLogged:)` is the standalone
/// sheet (own NavigationStack); `AddFlowView` embeds it with `isEmbedded: true`.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let context: LogContext
    private let onLogged: (() -> Void)?
    private let isEmbedded: Bool

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var carbsText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    /// Confirmation of the last "Ajouter et continuer".
    @State private var lastAdded: String?
    @FocusState private var focus: QuickAddField?

    init(context: LogContext, onLogged: (() -> Void)? = nil) {
        self.init(context: context, isEmbedded: false, onLogged: onLogged)
    }

    init(context: LogContext, isEmbedded: Bool, onLogged: (() -> Void)? = nil) {
        self.context = context
        self.isEmbedded = isEmbedded
        self.onLogged = onLogged
    }

    // MARK: - Parsing

    private static func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private var calories: Double? { QuickAddSheet.parse(caloriesText) }
    private var carbs: Double? { QuickAddSheet.parse(carbsText) }
    private var protein: Double? { QuickAddSheet.parse(proteinText) }
    private var fat: Double? { QuickAddSheet.parse(fatText) }

    /// Energy from the macros (4 / 4 / 9 kcal per g).
    private var macroCalories: Double {
        (carbs ?? 0) * 4 + (protein ?? 0) * 4 + (fat ?? 0) * 9
    }

    /// Typed energy, or the macro sum when the energy is left empty.
    private var energy: Double? {
        if let calories { return calories }
        return macroCalories > 0 ? macroCalories : nil
    }

    private func isInvalid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && QuickAddSheet.parse(text) == nil
    }

    private var canSave: Bool {
        energy != nil
            && !isInvalid(caloriesText)
            && !isInvalid(carbsText)
            && !isInvalid(proteinText)
            && !isInvalid(fatText)
    }

    private var timeLabel: String { AddTime.label(AddTime.effectiveTime(of: context)) }

    private func text(for key: NutrientKey) -> Binding<String> {
        switch key {
        case .carbohydrates: $carbsText
        case .protein: $proteinText
        default: $fatText
        }
    }

    // MARK: - Body

    var body: some View {
        if isEmbedded {
            form
        } else {
            NavigationStack {
                form
                    .navigationTitle("Ajout rapide")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuler") { dismiss() }
                                .tint(Theme.textSecondary)
                        }
                    }
            }
            .presentationBackground(Theme.background)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let lastAdded {
                    confirmation(lastAdded)
                        .padding(.bottom, 12)
                }
                fieldLabel("Énergie", color: Theme.textBody)
                energyRow
                macroSumNote
                    .padding(.top, 7)
                HStack(spacing: 8) {
                    ForEach(Theme.macroOrder, id: \.self) { key in
                        macroField(key)
                    }
                }
                .padding(.top, 16)
                nameField
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.never)
        .background(Theme.raised.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .task {
            // Keyboard first: energy field focused as soon as the screen appears.
            try? await Task.sleep(for: .milliseconds(50))
            if focus == nil { focus = .calories }
        }
    }

    // MARK: - Fields

    private func fieldLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(Theme.font(17, .regular, relativeTo: .body))
            .foregroundStyle(Theme.textPrimary)
            .padding(.bottom, 10)
    }

    private var energyRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("0", text: $caloriesText,
                          prompt: Text(macroCalories > 0 ? Formatters.number(macroCalories, maxFractionDigits: 0) : "0")
                            .foregroundColor(Theme.textQuaternary))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .calories)
                    .font(Theme.font(30, .bold, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .modifier(QuickAddFieldBox(isFocused: focus == .calories, isInvalid: isInvalid(caloriesText)))
            .contentShape(Rectangle())
            .onTapGesture { focus = .calories }

            Text("kcal")
                .font(Theme.font(15, .medium, relativeTo: .body))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 88, height: 50)
                .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// "Somme des macros : 316 kcal", warning color when far from the typed energy.
    @ViewBuilder
    private var macroSumNote: some View {
        let sum = Formatters.kcal(macroCalories)
        if let calories, macroCalories > 0, abs(macroCalories - calories) > max(30, calories * 0.15) {
            Label("Somme des macros : \(sum), loin de l'énergie saisie", systemImage: "exclamationmark.triangle")
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.fat)
        } else if calories == nil, macroCalories > 0 {
            Text("Somme des macros : \(sum) (utilisée comme énergie)")
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        } else {
            Text("Somme des macros : \(sum)")
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func macroField(_ key: NutrientKey) -> some View {
        let field = QuickAddField.field(for: key)
        let binding = text(for: key)
        return VStack(alignment: .leading, spacing: 0) {
            fieldLabel(key.label, color: Theme.textBody)
            HStack(spacing: 4) {
                TextField("0", text: binding,
                          prompt: Text("0").foregroundColor(Theme.textQuaternary))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: field)
                    .font(Theme.font(18, .bold, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
                Text("g")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .modifier(QuickAddFieldBox(isFocused: focus == field, isInvalid: isInvalid(binding.wrappedValue)))
            .contentShape(Rectangle())
            .onTapGesture { focus = field }
        }
        .frame(maxWidth: .infinity)
    }

    private var nameField: some View {
        TextField("Nom (facultatif)", text: $name,
                  prompt: Text("Nom (facultatif)").foregroundColor(Theme.textTertiary))
            .focused($focus, equals: .name)
            .submitLabel(.done)
            .onSubmit { save(continuing: false) }
            .font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 50)
            .modifier(QuickAddFieldBox(isFocused: focus == .name, isInvalid: false))
    }

    private func confirmation(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(Theme.font(13, .medium, relativeTo: .footnote))
            .foregroundStyle(Theme.good)
            .transition(.opacity)
    }

    // MARK: - Bottom bar (kept above the keyboard)

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let current = focus, let next = current.next {
                HStack {
                    Spacer()
                    Button {
                        focus = next
                    } label: {
                        HStack(spacing: 4) {
                            Text("Suivant : \(next.title)")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(Theme.font(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .overlay {
                            Capsule().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 8) {
                Button {
                    save(continuing: true)
                } label: {
                    Text("Ajouter et continuer")
                        .font(Theme.font(17, .regular, relativeTo: .body))
                        .foregroundStyle(canSave ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                Button {
                    save(continuing: false)
                } label: {
                    Text("Ajouter à \(timeLabel)")
                        .font(Theme.font(17, .medium, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundStyle(canSave ? Theme.onAccent : Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(canSave ? Theme.accent : Theme.separatorStrong,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Theme.raised.ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.hairline)
        }
        .animation(.snappy(duration: 0.2), value: focus)
    }

    // MARK: - Save

    private func save(continuing: Bool) {
        guard canSave, let energy else {
            focus = .calories
            return
        }
        var values = NutrientValues([.calories: energy])
        if let carbs { values[.carbohydrates] = carbs }
        if let protein { values[.protein] = protein }
        if let fat { values[.totalFat] = fat }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = FoodItem(
            source: .quickAdd,
            ref: nil,
            name: trimmed.isEmpty ? "Ajout rapide" : trimmed,
            brand: nil,
            kind: nil,
            servingLabel: nil,
            servingGrams: nil,
            packageGrams: nil,
            isLiquid: false,
            ean: nil,
            per100: values
        )
        // Quick adds store absolute values with grams = 100 (per100 == logged amounts).
        modelContext.insert(JournalEntry(item: item, grams: 100, day: context.day, meal: context.meal,
                                         at: context.time))
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if continuing {
            withAnimation(.snappy) {
                lastAdded = "\(item.name) ajouté : \(Formatters.kcal(energy)) à \(timeLabel)"
            }
            name = ""
            caloriesText = ""
            carbsText = ""
            proteinText = ""
            fatText = ""
            focus = .calories
        } else if isEmbedded {
            if let onLogged { onLogged() } else { dismiss() }
        } else {
            onLogged?()
            dismiss()
        }
    }
}

/// Input surface (raised2) with a 1 px border: brighter while focused, red when invalid.
private struct QuickAddFieldBox: ViewModifier {
    let isFocused: Bool
    let isInvalid: Bool

    func body(content: Content) -> some View {
        content
            .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isInvalid ? Theme.overTarget : (isFocused ? Theme.textPrimary : Color.clear),
                                  lineWidth: isFocused ? 2 : Theme.hairline)
            }
    }
}
