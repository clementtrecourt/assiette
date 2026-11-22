import SwiftData
import SwiftUI
import UIKit

private enum QuickAddField: Hashable {
    case calories, carbs, protein, fat, alcohol, name

    /// Keyboard "next" order: kcal → G → P → L → alcohol → name.
    var next: QuickAddField? {
        switch self {
        case .calories: .carbs
        case .carbs: .protein
        case .protein: .fat
        case .fat: .alcohol
        case .alcohol: .name
        case .name: nil
        }
    }

    var title: String {
        switch self {
        case .calories: "Énergie"
        case .carbs: "Glucides"
        case .protein: "Protéines"
        case .fat: "Lipides"
        case .alcohol: "Alcool"
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
    @Environment(\.slideCover) private var slideCover
    @Environment(\.modelContext) private var modelContext

    private let context: LogContext
    private let onLogged: (() -> Void)?
    private let isEmbedded: Bool

    @State private var name = ""
    @State private var caloriesText = ""
    @State private var energyInKJ = false
    @State private var carbsText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var alcoholText = ""
    /// Confirmation of the last "Ajouter et continuer".
    @State private var lastAdded: String?
    @FocusState private var focus: QuickAddField?

    init(context: LogContext, onLogged: (() -> Void)? = nil) {
        self.init(context: context, isEmbedded: false, onLogged: onLogged)
    }

    /// `estimate`: values from a meal photo (IA tab), prefilled for review.
    init(context: LogContext, isEmbedded: Bool, estimate: PhotoEstimate? = nil, onLogged: (() -> Void)? = nil) {
        self.context = context
        self.isEmbedded = isEmbedded
        self.onLogged = onLogged
        if let estimate {
            _name = State(initialValue: estimate.name)
            _caloriesText = State(initialValue: Formatters.number(estimate.kcal, maxFractionDigits: 0))
            _carbsText = State(initialValue: Formatters.number(estimate.carbsG, maxFractionDigits: 0))
            _proteinText = State(initialValue: Formatters.number(estimate.proteinG, maxFractionDigits: 0))
            _fatText = State(initialValue: Formatters.number(estimate.fatG, maxFractionDigits: 0))
        }
    }

    // MARK: - Parsing

    private static func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Energy typed in kcal, or in kJ (converted) when the unit menu says so.
    private var calories: Double? {
        QuickAddSheet.parse(caloriesText).map { energyInKJ ? $0 / QuickAddSheet.kJPerKcal : $0 }
    }
    private static let kJPerKcal = 4.184
    private var carbs: Double? { QuickAddSheet.parse(carbsText) }
    private var protein: Double? { QuickAddSheet.parse(proteinText) }
    private var fat: Double? { QuickAddSheet.parse(fatText) }
    private var alcohol: Double? { QuickAddSheet.parse(alcoholText) }

    /// Energy from the macros (4 / 4 / 9 kcal per g, alcohol 7).
    private var macroCalories: Double {
        (carbs ?? 0) * 4 + (protein ?? 0) * 4 + (fat ?? 0) * 9 + (alcohol ?? 0) * 7
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
            && !isInvalid(alcoholText)
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
        ScrollViewReader { proxy in
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
                    // MF: 16 pt gutters between the three macro fields.
                    HStack(spacing: 16) {
                        ForEach(Theme.macroOrder, id: \.self) { key in
                            macroField(key)
                        }
                    }
                    // MF: macro labels cap 35 pt under the macro-sum caption.
                    .padding(.top, 15)
                    // Label + field scroll as one block so "Alcool" never sits alone above the buttons.
                    VStack(alignment: .leading, spacing: 0) {
                        fieldLabel("Alcool", color: Theme.textBody)
                        alcoholField
                    }
                    .padding(.top, 16)
                    .id(QuickAddField.alcohol)
                    VStack(alignment: .leading, spacing: 0) {
                        fieldLabel("Nom", color: Theme.textBody)
                        nameField
                    }
                    .padding(.top, 16)
                    .id(QuickAddField.name)
                }
                .padding(.horizontal, 16)
                // MF (aligned pair): "Énergie" cap 21 pt under the tab track.
                .padding(.top, 16)
                // Room so the last block scrolls fully above the action buttons, with air.
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.never)
            .background(Theme.raised.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .task(id: focus) {
                // Alcohol / name sit low: bring the focused one above the buttons, again once
                // the keyboard has finished changing height (decimal pad -> text keyboard).
                guard let field = focus, field == .alcohol || field == .name else { return }
                withAnimation(.quick) { proxy.scrollTo(field, anchor: .bottom) }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, focus == field else { return }
                withAnimation(.quick) { proxy.scrollTo(field, anchor: .bottom) }
            }
        }
        .task {
            // Keyboard first: energy field focused as soon as the page is in place.
            await SlideCoverMotion.untilSettled(slideCover)
            if focus == nil { focus = .calories }
        }
    }

    // MARK: - Fields

    private func fieldLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(Theme.font(17, .regular, relativeTo: .body))
            .foregroundStyle(Theme.textPrimary)
            // MF: label cap 24 pt above its 48 pt field.
            .padding(.bottom, 7)
    }

    private var energyRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("", text: $caloriesText,
                          prompt: Text(macroCalories > 0
                                       ? Formatters.number(energyInKJ ? macroCalories * QuickAddSheet.kJPerKcal : macroCalories,
                                                           maxFractionDigits: 0)
                                       : "")
                            .foregroundColor(Theme.textQuaternary))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .calories)
                    .font(Theme.font(20, .regular, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            // Like MF: while focused, the energy entry is just a caret on the sheet background
            // (no fill, no outline); boxed again once focus moves on. Same 48 pt tap target.
            .modifier(QuickAddFieldBox(isFocused: focus == .calories, isInvalid: isInvalid(caloriesText),
                                       isBare: focus == .calories))
            .contentShape(Rectangle())
            .onTapGesture { focus = .calories }

            Menu {
                Picker("Unité", selection: $energyInKJ) {
                    Text("kcal").tag(false)
                    Text("kJ").tag(true)
                }
            } label: {
                HStack {
                    Text(energyInKJ ? "kJ" : "kcal")
                        .font(Theme.font(17, .regular, relativeTo: .body))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .frame(width: 112, height: 48)
                .background(QuickAddFieldBox.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityLabel("Unité d'énergie : \(energyInKJ ? "kilojoules" : "kilocalories")")
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
                TextField("", text: binding)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: field)
                    .font(Theme.font(20, .regular, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
                Text("g")
                    .font(Theme.font(17, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .modifier(QuickAddFieldBox(isFocused: focus == field, isInvalid: isInvalid(binding.wrappedValue)))
            .contentShape(Rectangle())
            .onTapGesture { focus = field }
        }
        .frame(maxWidth: .infinity)
    }

    /// Full-width alcohol field (g), counted 7 kcal/g in the macro sum.
    private var alcoholField: some View {
        HStack(spacing: 4) {
            TextField("", text: $alcoholText)
                .keyboardType(.decimalPad)
                .focused($focus, equals: .alcohol)
                .font(Theme.font(20, .regular, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
            Text("g")
                .font(Theme.font(17, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .modifier(QuickAddFieldBox(isFocused: focus == .alcohol, isInvalid: isInvalid(alcoholText)))
        .contentShape(Rectangle())
        .onTapGesture { focus = .alcohol }
        .accessibilityLabel("Alcool, en grammes")
    }

    private var nameField: some View {
        TextField("Nom", text: $name, prompt: Text(""))
            .focused($focus, equals: .name)
            .submitLabel(.done)
            .onSubmit { save(continuing: false) }
            .font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 48)
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
            VStack(spacing: 8) {
                Button {
                    save(continuing: true)
                } label: {
                    // MF: 18 pt labels ("Quick Add" 87 pt wide).
                    Text("Ajout rapide")
                        .font(Theme.font(18, .regular, relativeTo: .body))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                // Always lit like the reference; an empty form just focuses the energy field.

                Button {
                    save(continuing: false)
                } label: {
                    Text("Ajouter au journal")
                        .font(Theme.font(18, .medium, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundStyle(Theme.onAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                // Always lit like the reference; an empty form just focuses the energy field.
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Theme.raised.ignoresSafeArea(.container, edges: .bottom)
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
        if let alcohol, alcohol > 0 { values[.alcohol] = alcohol }

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
            withAnimation(.quick) {
                lastAdded = "\(item.name) ajouté : \(Formatters.kcal(energy)) à \(timeLabel)"
            }
            name = ""
            caloriesText = ""
            carbsText = ""
            proteinText = ""
            fatText = ""
            alcoholText = ""
            focus = .calories
        } else if isEmbedded {
            if let onLogged { onLogged() } else { dismiss() }
        } else {
            onLogged?()
            dismiss()
        }
    }
}

/// Input surface (MF #2E2E2E on the #1F1F1F sheet) with a 1 px border: brighter while focused,
/// red when invalid. `isBare` drops the surface and focus outline (MF focused energy entry).
private struct QuickAddFieldBox: ViewModifier {
    static let fill = Theme.hex(0x2E2E2E)

    let isFocused: Bool
    let isInvalid: Bool
    /// No fill and no focus outline (focused energy entry); an invalid value still shows red.
    var isBare = false

    func body(content: Content) -> some View {
        content
            .background(isBare ? Color.clear : QuickAddFieldBox.fill,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused && !isBare ? 2 : Theme.hairline)
            }
    }

    private var borderColor: Color {
        if isInvalid { return Theme.overTarget }
        return isFocused && !isBare ? Theme.textPrimary : Color.clear
    }
}
