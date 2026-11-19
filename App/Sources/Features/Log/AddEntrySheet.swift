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
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Supprimer du journal", systemImage: "trash")
                                .foregroundStyle(Theme.overTarget)
                        }
                        .listRowBackground(Theme.card)
                    }
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(entry == nil ? "Ajouter" : "Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .disabled(grams == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { quantityFocused = false }
                        .fontWeight(.semibold)
                }
            }
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

    // MARK: - Sections

    private var primaryButton: some View {
        Button {
            save()
        } label: {
            Text(entry == nil ? "Ajouter au journal" : "Enregistrer")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .opacity(grams == nil ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(grams == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Theme.background.ignoresSafeArea(edges: .bottom)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 8) {
                    Label(item.kind?.label ?? item.source.label,
                          systemImage: item.kind?.systemImage ?? sourceSymbol)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.card, in: Capsule())
                        .foregroundStyle(Theme.textSecondary)
                    if !isQuickAdd {
                        Text("\(Formatters.kcal(item.per100.calories)) / 100 \(item.unitSymbol)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
                if !isQuickAdd, let label = item.servingLabel, let servingGrams {
                    Text("1 portion = \(label) (\(Formatters.number(servingGrams, maxFractionDigits: 0)) \(item.unitSymbol))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
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
                Picker("Unité", selection: $unit) {
                    Text(servingTitle).tag(AddEntryUnit.serving)
                    Text(item.unitSymbol).tag(AddEntryUnit.base)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            quantityRow
                .listRowBackground(Theme.card)

            chipsRow
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        } header: {
            Text("Quantité")
                .foregroundStyle(Theme.textSecondary)
        } footer: {
            if let equivalence {
                Text(equivalence)
                    .foregroundStyle(Theme.textSecondary)
            } else if quantity == nil {
                Text("Saisissez une quantité supérieure à 0.")
                    .foregroundStyle(Theme.overTarget)
            }
        }
    }

    private var quantityRow: some View {
        Stepper {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .focused($quantityFocused)
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
                Text(unitSuffix)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { quantityFocused = true }
        } onIncrement: {
            adjust(by: step)
        } onDecrement: {
            adjust(by: -step)
        }
        .padding(.vertical, 2)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
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
                Label("Repas", systemImage: "fork.knife")
            }
            DatePicker(selection: $day, displayedComponents: .date) {
                Label("Jour", systemImage: "calendar")
            }
        }
        .listRowBackground(Theme.card)
        .listRowSeparatorTint(Theme.separator)
    }

    private var previewSection: some View {
        Section {
            SearchMacroColumns(values: portion, targets: profiles.first?.targets)
                .listRowBackground(Theme.card)
        } header: {
            Text("Apport")
                .foregroundStyle(Theme.textSecondary)
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

/// Quick quantity pill: card fill, accent fill when it matches the current quantity.
private struct AddEntryChipLabel: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        Text(label)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
            .background(isSelected ? Theme.accent : Theme.card, in: Capsule())
    }
}
