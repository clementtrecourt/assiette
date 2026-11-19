import SwiftData
import SwiftUI
import UIKit

private struct AddEntryChip: Hashable {
    let label: String
    let value: Double
}

private enum AddEntryUnit: Hashable {
    /// Number of servings.
    case serving
    /// Grams (or ml for liquids).
    case base
}

/// Log a food (new entry) or edit an existing journal entry.
struct AddEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private let item: FoodItem
    private let entry: JournalEntry?
    private let onLogged: (() -> Void)?

    @State private var unit: AddEntryUnit
    @State private var quantityText: String
    @State private var meal: Meal
    @State private var day: Date
    @State private var showDeleteConfirm = false
    @FocusState private var quantityFocused: Bool

    init(item: FoodItem, context: LogContext, onLogged: (() -> Void)? = nil) {
        self.item = item
        self.entry = nil
        self.onLogged = onLogged
        let remembered = UserDefaults.standard.object(forKey: AddEntrySheet.defaultsKey(for: item)) as? Double
        let grams: Double
        if let remembered, remembered > 0, item.source != .quickAdd {
            grams = remembered
        } else {
            grams = AddEntrySheet.servingGrams(of: item) ?? item.defaultGrams
        }
        let initial = AddEntrySheet.initialQuantity(grams: grams, item: item)
        _unit = State(initialValue: initial.unit)
        _quantityText = State(initialValue: initial.text)
        _meal = State(initialValue: context.meal)
        _day = State(initialValue: context.day.startOfDay)
    }

    init(editing entry: JournalEntry) {
        let item = entry.item
        self.item = item
        self.entry = entry
        self.onLogged = nil
        let initial = AddEntrySheet.initialQuantity(grams: entry.grams, item: item)
        _unit = State(initialValue: initial.unit)
        _quantityText = State(initialValue: initial.text)
        _meal = State(initialValue: entry.meal)
        _day = State(initialValue: entry.day)
    }

    // MARK: - Helpers (static, usable from init)

    private static func defaultsKey(for item: FoodItem) -> String { "lastGrams.\(item.id)" }

    /// Grams of one serving; quick adds use 100 g = one "portion" (per100 holds absolute values).
    private static func servingGrams(of item: FoodItem) -> Double? {
        if item.source == .quickAdd { return 100 }
        guard let grams = item.servingGrams, grams > 0 else { return nil }
        return grams
    }

    private static func initialQuantity(grams: Double, item: FoodItem) -> (unit: AddEntryUnit, text: String) {
        if let serving = servingGrams(of: item) {
            let count = grams / serving
            let isNice = abs(count * 4 - (count * 4).rounded()) < 0.01
            if item.source == .quickAdd || isNice {
                return (.serving, format(count))
            }
        }
        return (.base, format(grams))
    }

    private static func format(_ value: Double) -> String {
        // No grouping separator so the field stays easy to edit and parse.
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Formatters.locale))
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return value
    }

    // MARK: - Derived values

    private var servingGrams: Double? { AddEntrySheet.servingGrams(of: item) }
    private var isQuickAdd: Bool { item.source == .quickAdd }
    private var quantity: Double? { AddEntrySheet.parse(quantityText) }

    private var grams: Double? {
        guard let quantity else { return nil }
        if unit == .serving, let servingGrams { return quantity * servingGrams }
        return quantity
    }

    private var portion: NutrientValues { item.per100.forGrams(grams ?? 0) }

    private var servingTitle: String {
        isQuickAdd ? "Portion" : "Portions"
    }

    private var unitSuffix: String {
        switch unit {
        case .serving:
            let n = quantity ?? 0
            return n > 1 ? "portions" : "portion"
        case .base:
            return item.unitSymbol
        }
    }

    private var step: Double {
        switch unit {
        case .serving: return 0.5
        case .base: return (quantity ?? 0) >= 200 ? 25 : 10
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                quantitySection
                whenSection
                previewSection

                if entry != nil {
                    deleteSection
                }

                if item.source == .openNutrition || item.source == .openFoodFacts {
                    Section {
                    } footer: {
                        AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
                    }
                }
            }
            .listSectionSpacing(.compact)
            .themedBackground()
            .safeAreaInset(edge: .bottom) { primaryButton }
            .navigationTitle(entry == nil ? "Ajouter" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: unit) { oldValue, newValue in
                convertQuantity(from: oldValue, to: newValue)
            }
            .confirmationDialog(
                "Supprimer cet aliment du journal ?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { deleteEntry() }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Annuler") { dismiss() }
                .tint(Theme.textSecondary)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(entry == nil ? "Ajouter" : "Enregistrer") { save() }
                .font(Theme.font(17, .bold, relativeTo: .body))
                .tint(Theme.textPrimary)
                .disabled(grams == nil)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("OK") { quantityFocused = false }
                .font(Theme.font(17, .bold, relativeTo: .body))
                .tint(Theme.textPrimary)
        }
    }

    // MARK: - Sections

    private var primaryButton: some View {
        let enabled = grams != nil
        return Button {
            save()
        } label: {
            Text(entry == nil ? "Ajouter au journal" : "Enregistrer")
                .font(Theme.font(16, .bold, relativeTo: .headline))
                .foregroundStyle(enabled ? Theme.onAccent : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? Theme.accent : Theme.separatorStrong,
                            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Theme.background.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.hairline)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    FoodIconView(item: item, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(Theme.title)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let brand = item.brand, !brand.isEmpty {
                            Text(brand)
                                .font(Theme.callout)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                headerMetaRow
                if !isQuickAdd, let label = item.servingLabel, let servingGrams {
                    Text("1 portion = \(label) (\(Formatters.number(servingGrams, maxFractionDigits: 0)) \(item.unitSymbol))")
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    private var headerMetaRow: some View {
        HStack(spacing: 10) {
            Label(item.kind?.label ?? item.source.label,
                  systemImage: item.kind?.systemImage ?? sourceSymbol)
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay {
                    Capsule().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
                }
            if !isQuickAdd {
                HStack(spacing: 3) {
                    KcalLabel(kcal: item.per100.calories)
                    Text("/ 100 \(item.unitSymbol)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var sourceSymbol: String {
        switch item.source {
        case .openNutrition: return "leaf"
        case .custom: return "person.crop.circle"
        case .openFoodFacts: return "barcode"
        case .quickAdd: return "bolt"
        }
    }

    private var quantitySection: some View {
        Section {
            if servingGrams != nil, !isQuickAdd {
                unitToggle
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
            }

            quantityRow
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))

            chipsRow
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 2, trailing: 0))
        } header: {
            AddEntrySectionHeader(title: "Quantité")
        } footer: {
            quantityFooter
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var quantityFooter: some View {
        if let equivalence {
            Text(equivalence)
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        } else if quantity == nil {
            Text("Saisissez une quantité supérieure à 0.")
                .font(Theme.caption)
                .foregroundStyle(Theme.overTarget)
        }
    }

    /// Portions / g switch: selected segment = white fill + near-black text.
    private var unitToggle: some View {
        HStack(spacing: 4) {
            AddEntrySegment(title: servingTitle, isSelected: unit == .serving) {
                unit = .serving
            }
            AddEntrySegment(title: item.unitSymbol, isSelected: unit == .base) {
                unit = .base
            }
        }
        .padding(3)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unité")
    }

    private var quantityRow: some View {
        HStack(alignment: .center, spacing: 10) {
            quantityField
            AddEntryStepButton(systemImage: "minus", label: "Diminuer") {
                adjust(by: -step)
            }
            AddEntryStepButton(systemImage: "plus", label: "Augmenter") {
                adjust(by: step)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(quantityFocused ? Theme.textTertiary : Theme.separatorStrong,
                              lineWidth: Theme.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            if direction == .increment {
                adjust(by: step)
            } else if direction == .decrement {
                adjust(by: -step)
            }
        }
    }

    private var quantityField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("0", text: $quantityText)
                .keyboardType(.decimalPad)
                .focused($quantityFocused)
                .font(Theme.font(34, .bold, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.textPrimary)
                .fixedSize()
            Text(unitSuffix)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { quantityFocused = true }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        quantityText = AddEntrySheet.format(chip.value)
                        quantityFocused = false
                    } label: {
                        AddEntryChipLabel(label: chip.label, isSelected: isSelected(chip.value))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var chips: [AddEntryChip] {
        switch unit {
        case .serving:
            return [
                AddEntryChip(label: "½", value: 0.5),
                AddEntryChip(label: "1", value: 1),
                AddEntryChip(label: "1½", value: 1.5),
                AddEntryChip(label: "2", value: 2),
                AddEntryChip(label: "3", value: 3),
            ]
        case .base:
            let symbol = item.unitSymbol
            let values: [Double] = [50, 100, 150, 200, 250]
            return values.map { value in
                AddEntryChip(label: "\(Formatters.number(value, maxFractionDigits: 0)) \(symbol)", value: value)
            }
        }
    }

    private func isSelected(_ value: Double) -> Bool {
        guard let quantity else { return false }
        return abs(quantity - value) < 0.001
    }

    private var equivalence: String? {
        guard !isQuickAdd, let grams, let servingGrams else { return nil }
        switch unit {
        case .serving:
            return "= \(Formatters.number(grams, maxFractionDigits: 0)) \(item.unitSymbol)"
        case .base:
            let n = grams / servingGrams
            return "≈ \(Formatters.number(n, maxFractionDigits: 2)) \(n > 1 ? "portions" : "portion")"
        }
    }

    private var whenSection: some View {
        Section {
            Picker(selection: $meal) {
                ForEach(Meal.allCases) { meal in
                    Label(meal.label, systemImage: meal.systemImage).tag(meal)
                }
            } label: {
                AddEntryFieldLabel(title: "Repas", systemImage: "fork.knife")
            }
            .tint(Theme.textSecondary)
            DatePicker(selection: $day, displayedComponents: .date) {
                AddEntryFieldLabel(title: "Jour", systemImage: "calendar")
            }
            .tint(Theme.calories)
        } header: {
            AddEntrySectionHeader(title: "Quand")
        }
        .font(Theme.body)
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.separator)
    }

    private var previewSection: some View {
        Section {
            AddEntryMacroPreview(values: portion, targets: profiles.first?.targets)
                .listRowBackground(Theme.background)
                .listRowInsets(EdgeInsets())
        } header: {
            AddEntrySectionHeader(title: "Apport")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Supprimer du journal", systemImage: "trash")
                    .font(Theme.body)
                    .foregroundStyle(Theme.overTarget)
            }
            .listRowBackground(Theme.background)
        }
    }

    // MARK: - Actions

    private func adjust(by delta: Double) {
        let current = quantity ?? 0
        let stepValue = abs(delta)
        var next: Double
        if delta > 0 {
            next = ((current / stepValue).rounded(.down) + 1) * stepValue
        } else {
            next = ((current / stepValue).rounded(.up) - 1) * stepValue
        }
        next = max(stepValue, next)
        quantityText = AddEntrySheet.format(next)
    }

    private func convertQuantity(from old: AddEntryUnit, to new: AddEntryUnit) {
        guard old != new, let servingGrams, let current = quantity else { return }
        switch (old, new) {
        case (.serving, .base):
            quantityText = AddEntrySheet.format((current * servingGrams).rounded())
        case (.base, .serving):
            let servings = current / servingGrams
            let quarters = (servings * 4).rounded() / 4
            quantityText = AddEntrySheet.format(quarters > 0 ? quarters : servings)
        default:
            break
        }
    }

    private func save() {
        guard let grams else { return }
        if let entry {
            entry.grams = grams
            entry.meal = meal
            entry.day = day.startOfDay
        } else {
            modelContext.insert(JournalEntry(item: item, grams: grams, day: day, meal: meal))
        }
        try? modelContext.save()
        if !isQuickAdd {
            UserDefaults.standard.set(grams, forKey: AddEntrySheet.defaultsKey(for: item))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onLogged?()
        dismiss()
    }

    private func deleteEntry() {
        guard let entry else { return }
        modelContext.delete(entry)
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}

/// Quick quantity pill: outlined, white fill + near-black text when it matches the current quantity.
private struct AddEntryChipLabel: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        Text(label)
            .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background(isSelected ? Theme.accent : Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? Theme.accent : Theme.separatorStrong, lineWidth: Theme.hairline)
            }
            .contentShape(Capsule())
    }
}

/// One segment of the Portions / g switch.
private struct AddEntrySegment: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(isSelected ? Theme.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.cornerRadius - 3, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Outlined circular − / + button next to the quantity field.
private struct AddEntryStepButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .overlay {
                    Circle().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

/// Form row label with a muted monochrome icon.
private struct AddEntryFieldLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

/// Section header per DESIGN.md: small uppercase DM Sans in textTertiary.
private struct AddEntrySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// Nutrition of the portion, laid out like the journal's pinned header:
/// 4 columns separated by hairlines, tiny colored label, big number, 2 pt bar, caption.
private struct AddEntryMacroPreview: View {
    let values: NutrientValues
    let targets: NutrientValues?

    private static let keys: [NutrientKey] = [.calories, .protein, .carbohydrates, .totalFat]

    private var energyFromMacros: Double {
        values.protein * 4 + values.carbs * 4 + values.fat * 9
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(AddEntryMacroPreview.keys.enumerated()), id: \.offset) { index, key in
                AddEntryMacroColumn(
                    key: key,
                    amount: values.value(key),
                    fraction: fraction(for: key),
                    caption: caption(for: key),
                    showsLeadingHairline: index > 0
                )
            }
        }
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
    }

    private func targetValue(for key: NutrientKey) -> Double? {
        guard let targets, let target = targets[key], target > 0 else { return nil }
        return target
    }

    private func fraction(for key: NutrientKey) -> Double {
        if let target = targetValue(for: key) {
            return values.value(key) / target
        }
        if key == .calories {
            guard let ref = NutrientKey.calories.dailyReference, ref > 0 else { return 0 }
            return values.calories / ref
        }
        guard energyFromMacros > 0 else { return 0 }
        let perGram: Double = key == .totalFat ? 9 : 4
        return values.value(key) * perGram / energyFromMacros
    }

    private func caption(for key: NutrientKey) -> String {
        if let target = targetValue(for: key) {
            return "sur \(Formatters.number(target, maxFractionDigits: 0))"
        }
        let percent = Formatters.percent(fraction(for: key))
        if key == .calories { return "\(percent) AR" }
        return energyFromMacros > 0 ? "\(percent) énergie" : "—"
    }
}

private struct AddEntryMacroColumn: View {
    let key: NutrientKey
    let amount: Double
    let fraction: Double
    let caption: String
    let showsLeadingHairline: Bool

    private var title: String {
        key == .calories ? "Kcal" : key.shortLabel
    }

    private var number: String {
        Formatters.number(amount, maxFractionDigits: key == .calories || amount >= 10 ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.font(10, .bold, relativeTo: .caption2))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(Theme.color(for: key))
                .lineLimit(1)
            valueLine
                .padding(.top, 6)
            AddEntryThinBar(fraction: fraction, color: Theme.color(for: key))
                .padding(.top, 8)
            Text(caption)
                .font(Theme.font(11, .regular, relativeTo: .caption2))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if showsLeadingHairline {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: Theme.hairline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var valueLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(number)
                .font(Theme.numberLarge)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if key != .calories {
                Text("g")
                    .font(Theme.font(11, .medium, relativeTo: .caption2))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// 2 pt bar: macro color on separatorStrong (red when over target).
private struct AddEntryThinBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separatorStrong)
                Capsule()
                    .fill(fraction > 1.05 ? Theme.overTarget : color)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: 2)
    }
}
