import SwiftData
import SwiftUI
import UIKit

/// Unit the quantity is typed in.
private enum AddEntryUnit: Hashable {
    /// Grams (or ml for liquids).
    case base
    /// Number of servings (quick adds: 1 portion = the quick add itself).
    case serving
    /// Number of packages (when the food knows its package size).
    case package
}

private struct AddEntryChip: Hashable {
    let label: String
    let value: Double
}

/// Keys of the in-sheet numeric keypad.
private enum AddEntryKey: Hashable {
    case digit(Int)
    case comma
    case delete
}

/// Food detail + quantity entry: log a food (new entry) or edit an existing journal entry.
/// The quantity is typed on an in-sheet numeric keypad (no system keyboard, ready instantly).
struct AddEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var favoriteMatches: [FavoriteFood]

    private let item: FoodItem
    private let entry: JournalEntry?
    private let onLogged: (() -> Void)?
    /// Time slot of the log context (journal hour), nil = default time.
    private let contextTime: Date?

    @State private var unit: AddEntryUnit
    @State private var quantityText: String
    /// True while the displayed quantity is "selected": the next digit replaces it.
    @State private var replacesOnType = true
    @State private var meal: Meal
    /// Day of a new entry.
    @State private var day: Date
    /// Time of the edited entry (createdAt).
    @State private var time: Date
    @State private var showDeleteConfirm = false
    @State private var showCustomEditor = false
    @State private var caretOn = false
    @State private var favoriteToggles = 0

    init(item: FoodItem, context: LogContext, onLogged: (() -> Void)? = nil) {
        self.item = item
        self.entry = nil
        self.onLogged = onLogged
        self.contextTime = context.time
        let key = item.id
        _favoriteMatches = Query(filter: #Predicate<FavoriteFood> { $0.key == key })
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
        _time = State(initialValue: context.time ?? JournalEntry.defaultTime(on: context.day))
    }

    init(editing entry: JournalEntry) {
        let item = entry.item
        self.item = item
        self.entry = entry
        self.onLogged = nil
        self.contextTime = nil
        let key = item.id
        _favoriteMatches = Query(filter: #Predicate<FavoriteFood> { $0.key == key })
        let initial = AddEntrySheet.initialQuantity(grams: entry.grams, item: item)
        _unit = State(initialValue: initial.unit)
        _quantityText = State(initialValue: initial.text)
        _meal = State(initialValue: entry.meal)
        _day = State(initialValue: entry.day)
        _time = State(initialValue: entry.createdAt)
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
        // No grouping separator so the value stays easy to edit and parse.
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Formatters.locale))
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return value
    }

    /// `time`'s hour and minute on `day`.
    private static func moving(_ time: Date, to day: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0,
                             second: parts.second ?? 0, of: day) ?? time
    }

    // MARK: - Derived values

    private var servingGrams: Double? { AddEntrySheet.servingGrams(of: item) }
    private var isQuickAdd: Bool { item.source == .quickAdd }
    private var isFavorite: Bool { !favoriteMatches.isEmpty }
    private var quantity: Double? { AddEntrySheet.parse(quantityText) }

    private var packageGrams: Double? {
        guard !isQuickAdd, let grams = item.packageGrams, grams > 0 else { return nil }
        if let servingGrams, abs(servingGrams - grams) < 0.5 { return nil }
        return grams
    }

    private var availableUnits: [AddEntryUnit] {
        if isQuickAdd { return [.serving] }
        var units: [AddEntryUnit] = [.base]
        if servingGrams != nil { units.append(.serving) }
        if packageGrams != nil { units.append(.package) }
        return units
    }

    private func gramsPerUnit(_ unit: AddEntryUnit) -> Double? {
        switch unit {
        case .base: return 1
        case .serving: return servingGrams
        case .package: return packageGrams
        }
    }

    private var grams: Double? {
        guard let quantity, let perUnit = gramsPerUnit(unit) else { return nil }
        return quantity * perUnit
    }

    private var portion: NutrientValues { item.per100.forGrams(grams ?? 0) }

    private func unitWord(_ unit: AddEntryUnit, count: Double) -> String {
        switch unit {
        case .base: return item.unitSymbol
        case .serving: return count > 1 ? "portions" : "portion"
        case .package: return count > 1 ? "emballages" : "emballage"
        }
    }

    private func unitTitle(_ unit: AddEntryUnit) -> String {
        switch unit {
        case .base: return item.unitSymbol
        case .serving: return "portion"
        case .package: return "emballage"
        }
    }

    private var step: Double {
        switch unit {
        case .serving: return 0.5
        case .package: return 0.25
        case .base: return (quantity ?? 0) >= 200 ? 25 : 10
        }
    }

    /// "portions · 500 ml", "g · ≈ 1,5 portion".
    private var quantityDetail: String {
        guard let quantity, let grams else { return "Saisissez une quantité" }
        let word = unitWord(unit, count: quantity)
        if isQuickAdd { return word }
        let gramsText = "\(Formatters.number(grams, maxFractionDigits: 0)) \(item.unitSymbol)"
        switch unit {
        case .base:
            guard let servingGrams else { return word }
            let n = grams / servingGrams
            return "\(word) · ≈ \(Formatters.number(n, maxFractionDigits: 2)) \(n > 1 ? "portions" : "portion")"
        case .serving, .package:
            return "\(word) · \(gramsText)"
        }
    }

    /// "Marque · 1 portion = 100 ml".
    private var subtitle: String {
        var parts: [String] = []
        if let brand = item.brand, !brand.isEmpty {
            parts.append(brand)
        } else if isQuickAdd {
            parts.append(FoodSource.quickAdd.label)
        } else if let kind = item.kind {
            parts.append(kind.label)
        } else if item.source != .openNutrition {
            parts.append(item.source.label)
        }
        if !isQuickAdd, let servingGrams {
            let label = item.servingLabel ?? "1 portion"
            parts.append("\(label) = \(Formatters.number(servingGrams, maxFractionDigits: 0)) \(item.unitSymbol)")
        } else if !isQuickAdd {
            parts.append("\(Formatters.number(item.per100.calories, maxFractionDigits: 0)) kcal / 100 \(item.unitSymbol)")
        }
        return parts.joined(separator: " · ")
    }

    private var showsDatasetAttribution: Bool {
        item.source == .openNutrition || item.source == .openFoodFacts
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    AddEntryMacroSummary(per100: item.per100, portion: portion)
                        .padding(.top, 14)
                    if !isQuickAdd {
                        actionsRow
                            .padding(.top, 12)
                    }
                    AddEntryHairline()
                        .padding(.top, 14)
                    dayShare
                        .padding(.top, 12)
                    AddEntryHairline()
                        .padding(.top, 14)
                    whenRow
                    if showsDatasetAttribution {
                        AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { entryPanel }
            .background(Theme.raised.ignoresSafeArea())
            .navigationTitle(entry == nil ? "Ajouter" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.raised, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Fermer")
                }
            }
            .confirmationDialog(
                "Supprimer cet aliment du journal ?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { deleteEntry() }
                Button("Annuler", role: .cancel) {}
            }
            .sheet(isPresented: $showCustomEditor) {
                CustomFoodEditor(food: nil, prefill: item)
            }
            .sensoryFeedback(.selection, trigger: favoriteToggles)
            .onAppear { caretOn = true }
        }
        .presentationBackground(Theme.raised)
    }

    // MARK: - Top (scrollable)

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            FoodIconView(item: item, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Theme.font(17, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button(action: toggleFavorite) {
                Label("Favori", systemImage: isFavorite ? "heart.fill" : "heart")
                    .labelStyle(AddEntryOutlineLabelStyle(iconColor: isFavorite ? Theme.protein : Theme.textSecondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")

            if item.source != .custom {
                Button {
                    showCustomEditor = true
                } label: {
                    Label("Créer un aliment perso", systemImage: "square.on.square")
                        .labelStyle(AddEntryOutlineLabelStyle(iconColor: Theme.textSecondary))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var dayShare: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Part de la journée")
                .font(Theme.font(13, .bold, relativeTo: .subheadline))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 0) {
                AddEntryDayRing(fraction: share(of: .calories), color: Theme.calories, title: "Calories")
                ForEach(Theme.macroOrder, id: \.self) { key in
                    AddEntryDayRing(fraction: share(of: key), color: Theme.color(for: key), title: key.label)
                }
            }
        }
    }

    private func share(of key: NutrientKey) -> Double {
        var target: Double?
        if let profile = profiles.first {
            switch key {
            case .calories: target = profile.calorieTarget
            case .carbohydrates: target = profile.carbsTarget
            case .protein: target = profile.proteinTarget
            case .totalFat: target = profile.fatTarget
            default: target = nil
            }
        }
        if (target ?? 0) <= 0 { target = key.dailyReference }
        guard let target, target > 0 else { return 0 }
        return portion.value(key) / target
    }

    private var whenRow: some View {
        HStack(spacing: 10) {
            Picker(selection: $meal) {
                ForEach(Meal.allCases) { meal in
                    Label(meal.label, systemImage: meal.systemImage).tag(meal)
                }
            } label: {
                Text("Repas")
            }
            .pickerStyle(.menu)
            .tint(Theme.textBody)
            .labelsHidden()

            Spacer(minLength: 0)

            if entry != nil {
                DatePicker("Heure", selection: $time, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(Theme.calories)
                    .accessibilityLabel("Date et heure")
            } else {
                DatePicker("Jour", selection: $day, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.calories)
                    .accessibilityLabel("Jour")
            }
        }
        .font(Theme.callout)
        .padding(.vertical, 8)
    }

    // MARK: - Bottom panel (quantity + keypad + actions)

    private var entryPanel: some View {
        VStack(spacing: 8) {
            quantityField
            unitRow
            AddEntryKeypad(onKey: press, onClear: clearQuantity)
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.raised.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { AddEntryHairline() }
    }

    private var quantityField: some View {
        HStack(spacing: 8) {
            HStack(alignment: .center, spacing: 1) {
                Text(quantityText.isEmpty ? " " : quantityText)
                    .font(Theme.font(24, .bold, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, replacesOnType ? 3 : 0)
                    .background {
                        if replacesOnType && !quantityText.isEmpty {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.calories.opacity(0.32))
                        }
                    }
                if !replacesOnType || quantityText.isEmpty {
                    Rectangle()
                        .fill(Theme.textPrimary)
                        .frame(width: 2, height: 24)
                        .opacity(caretOn ? 1 : 0.1)
                        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: caretOn)
                }
            }
            Spacer(minLength: 4)
            Text(quantityDetail)
                .font(Theme.callout)
                .monospacedDigit()
                .foregroundStyle(quantity == nil ? Theme.overTarget : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            AddEntryStepButton(systemImage: "minus", label: "Diminuer") { adjust(by: -step) }
            AddEntryStepButton(systemImage: "plus", label: "Augmenter") { adjust(by: step) }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textBody, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quantité")
        .accessibilityValue("\(quantityText) \(quantityDetail)")
        .accessibilityAdjustableAction { direction in
            if direction == .increment {
                adjust(by: step)
            } else if direction == .decrement {
                adjust(by: -step)
            }
        }
    }

    private var unitRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if availableUnits.count > 1 {
                    ForEach(availableUnits, id: \.self) { candidate in
                        Button {
                            select(candidate)
                        } label: {
                            AddEntryChipLabel(label: unitTitle(candidate), isSelected: unit == candidate)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(unit == candidate ? .isSelected : [])
                    }
                    Rectangle()
                        .fill(Theme.separatorStrong)
                        .frame(width: Theme.hairline, height: 20)
                        .padding(.horizontal, 3)
                }
                ForEach(chips, id: \.self) { chip in
                    Button {
                        quantityText = AddEntrySheet.format(chip.value)
                        replacesOnType = true
                    } label: {
                        AddEntryChipLabel(label: chip.label, isSelected: false, isOutlined: isSelected(chip.value))
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
        case .package:
            return [
                AddEntryChip(label: "¼", value: 0.25),
                AddEntryChip(label: "½", value: 0.5),
                AddEntryChip(label: "1", value: 1),
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

    private var actionButtons: some View {
        let enabled = grams != nil
        return HStack(spacing: 8) {
            if entry != nil {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Text("Supprimer")
                        .foregroundStyle(Theme.overTarget)
                }
                .buttonStyle(AddEntryActionButtonStyle(isPrimary: false))

                Button("Enregistrer") { save(andContinue: false) }
                    .buttonStyle(AddEntryActionButtonStyle(isPrimary: true))
                    .disabled(!enabled)
            } else {
                Button("Ajouter et continuer") { save(andContinue: true) }
                    .buttonStyle(AddEntryActionButtonStyle(isPrimary: false))
                    .disabled(!enabled)

                Button("Ajouter") { save(andContinue: false) }
                    .buttonStyle(AddEntryActionButtonStyle(isPrimary: true))
                    .disabled(!enabled)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Input

    private func press(_ key: AddEntryKey) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        switch key {
        case .delete:
            if replacesOnType {
                quantityText = ""
            } else if !quantityText.isEmpty {
                quantityText.removeLast()
            }
        case .comma:
            if replacesOnType || quantityText.isEmpty {
                quantityText = "0,"
            } else if !quantityText.contains(",") {
                quantityText.append(",")
            }
        case .digit(let digit):
            let character = String(digit)
            if replacesOnType || quantityText == "0" {
                quantityText = character
            } else if let comma = quantityText.firstIndex(of: ",") {
                let decimals = quantityText.distance(from: comma, to: quantityText.endIndex) - 1
                if decimals < 2 { quantityText.append(character) }
            } else if quantityText.count < 5 {
                quantityText.append(character)
            }
        }
        replacesOnType = false
    }

    private func clearQuantity() {
        quantityText = ""
        replacesOnType = false
    }

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
        replacesOnType = true
    }

    /// Switches unit, converting the current quantity so the grams stay the same.
    private func select(_ newUnit: AddEntryUnit) {
        guard newUnit != unit else { return }
        if let currentGrams = grams, let perUnit = gramsPerUnit(newUnit), perUnit > 0 {
            let converted = currentGrams / perUnit
            switch newUnit {
            case .base:
                quantityText = AddEntrySheet.format(converted.rounded())
            case .serving, .package:
                let quarters = (converted * 4).rounded() / 4
                quantityText = AddEntrySheet.format(quarters > 0 ? quarters : converted)
            }
        }
        unit = newUnit
        replacesOnType = true
    }

    // MARK: - Actions

    private func toggleFavorite() {
        if favoriteMatches.isEmpty {
            modelContext.insert(FavoriteFood(item: item))
        } else {
            for favorite in favoriteMatches { modelContext.delete(favorite) }
        }
        try? modelContext.save()
        favoriteToggles += 1
    }

    /// Logs (or updates) the entry. "Ajouter et continuer" only closes this sheet, without
    /// `onLogged`, so the caller (search) stays open to add more.
    private func save(andContinue: Bool) {
        guard let grams else { return }
        if let entry {
            entry.grams = grams
            entry.meal = meal
            entry.createdAt = time
            entry.day = time.startOfDay
        } else {
            let at = contextTime.map { AddEntrySheet.moving($0, to: day) }
            modelContext.insert(JournalEntry(item: item, grams: grams, day: day, meal: meal, at: at))
        }
        try? modelContext.save()
        if !isQuickAdd {
            UserDefaults.standard.set(grams, forKey: AddEntrySheet.defaultsKey(for: item))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if !andContinue { onLogged?() }
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

// MARK: - Components

/// Big kcal + G / P / L for the current quantity, each macro with a pill showing the share of
/// the food's energy it provides.
private struct AddEntryMacroSummary: View {
    let per100: NutrientValues
    let portion: NutrientValues

    /// Energy used for the % pills: the food's kcal, or the macro sum when kcal is unknown.
    private var energy: Double {
        if per100.calories > 0 { return per100.calories }
        return per100.carbs * 4 + per100.protein * 4 + per100.fat * 9
    }

    private func energyShare(_ key: NutrientKey) -> String {
        guard energy > 0 else { return "– %" }
        let perGram: Double = key == .totalFat ? 9 : 4
        return Formatters.percent(min(per100.value(key) * perGram / energy, 1))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 2) {
                Text(Formatters.number(portion.calories, maxFractionDigits: 0))
                    .font(Theme.font(34, .bold, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kcal")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .accessibilityElement(children: .combine)

            ForEach(Theme.macroOrder, id: \.self) { key in
                VStack(spacing: 2) {
                    Text(energyShare(key))
                        .font(Theme.font(11, .bold, relativeTo: .caption2))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color(for: key))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.color(for: key).opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(.bottom, 4)
                    Text(Formatters.number(portion.value(key), maxFractionDigits: 1))
                        .font(Theme.font(20, .bold, relativeTo: .title3))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(key.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.snappy, value: portion)
    }
}

/// Small ring: share of the day's target that the current quantity represents.
private struct AddEntryDayRing: View {
    let fraction: Double
    let color: Color
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Theme.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(fraction > 1.05 ? Theme.overTarget : color,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Formatters.percent(fraction))
                    .font(Theme.font(11, .bold, relativeTo: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 5)
            }
            .frame(width: 48, height: 48)
            .animation(.snappy, value: fraction)
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Formatters.percent(fraction)) de l'objectif du jour")
    }
}

/// 4 × 3 numeric keypad: 1–9, ",", 0, ⌫ (long press on ⌫ clears).
private struct AddEntryKeypad: View {
    let onKey: (AddEntryKey) -> Void
    let onClear: () -> Void

    private static let rows: [[AddEntryKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.comma, .digit(0), .delete],
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<AddEntryKeypad.rows.count, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(AddEntryKeypad.rows[row], id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: AddEntryKey) -> some View {
        let button = Button {
            onKey(key)
        } label: {
            Group {
                switch key {
                case .digit(let digit):
                    Text(String(digit))
                case .comma:
                    Text(",")
                case .delete:
                    Image(systemName: "delete.left")
                        .font(.system(size: 18, weight: .medium))
                }
            }
            .font(Theme.font(21, .medium, relativeTo: .title3))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(AddEntryKeyButtonStyle())

        switch key {
        case .delete:
            button
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onClear() })
                .accessibilityLabel("Effacer")
        case .comma:
            button.accessibilityLabel("Virgule")
        case .digit:
            button
        }
    }
}

private struct AddEntryKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Bottom action: white fill (primary) or raised2 (secondary).
private struct AddEntryActionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, .bold, relativeTo: .headline))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var foreground: Color {
        if !isEnabled { return Theme.textQuaternary }
        return isPrimary ? Theme.onAccent : Theme.textBody
    }

    private var background: Color {
        if isPrimary && isEnabled { return Theme.accent }
        return Theme.raised2
    }
}

/// Unit / quick-value chip: white fill + near-black text when selected, raised2 otherwise.
private struct AddEntryChipLabel: View {
    let label: String
    let isSelected: Bool
    var isOutlined: Bool = false

    var body: some View {
        Text(label)
            .font(Theme.font(13, isSelected ? .bold : .medium, relativeTo: .subheadline))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textBody)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(isSelected ? Theme.accent : Theme.raised2,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                if isOutlined {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.textTertiary, lineWidth: Theme.hairline)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Outlined small button label ("♡ Favori", "Créer un aliment perso").
private struct AddEntryOutlineLabelStyle: LabelStyle {
    let iconColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
            configuration.title
                .font(Theme.font(13, .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Round − / + button inside the quantity field.
private struct AddEntryStepButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Theme.raised2, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct AddEntryHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
    }
}
