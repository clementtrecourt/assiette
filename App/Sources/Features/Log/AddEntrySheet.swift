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
    /// Ounces (by weight; fluid ounces for liquids).
    case ounce
    /// Pounds (solids only).
    case pound
}

/// Keys of the in-sheet numeric keypad.
private enum AddEntryKey: Hashable {
    case digit(Int)
    case comma
    case delete
    /// Fraction bar ("1/2") and space ("1 1/2").
    case slash
    case space
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
    /// Embedded in the add flow panel: back chevron instead of a sheet (nil = sheet).
    private var onBack: (() -> Void)?
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
    /// Custom food opened by "Modifier" (nil = new custom food prefilled from `item`).
    @State private var editedCustomFood: CustomFood?
    @State private var caretOn = false
    @State private var favoriteToggles = 0

    init(item: FoodItem, context: LogContext, onLogged: (() -> Void)? = nil, onBack: (() -> Void)? = nil) {
        self.item = item
        self.entry = nil
        self.onLogged = onLogged
        self.onBack = onBack
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

    /// "150", "1,5", "1/2", "1 1/2" (whole part + fraction).
    static func parse(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        var total = 0.0
        for part in normalized.split(separator: " ") {
            if part.contains("/") {
                let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
                guard pieces.count == 2, let a = Double(pieces[0]), let b = Double(pieces[1]), b > 0 else { return nil }
                total += a / b
            } else {
                guard let value = Double(part) else { return nil }
                total += value
            }
        }
        guard total.isFinite, total > 0 else { return nil }
        return total
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
        units.append(.ounce)
        // A pound of a liquid has no clean volume equivalent: liquids get fl oz only.
        if !item.isLiquid { units.append(.pound) }
        return units
    }

    /// 1 oz = 28.3495 g (1 fl oz = 29.5735 ml for liquids), 1 lb = 453.592 g.
    private func gramsPerUnit(_ unit: AddEntryUnit) -> Double? {
        switch unit {
        case .base: return 1
        case .serving: return servingGrams
        case .package: return packageGrams
        case .ounce: return item.isLiquid ? 29.5735 : 28.3495
        case .pound: return item.isLiquid ? nil : 453.592
        }
    }

    private var grams: Double? {
        guard let quantity, let perUnit = gramsPerUnit(unit) else { return nil }
        return quantity * perUnit
    }

    private var portion: NutrientValues { item.per100.forGrams(grams ?? 0) }

    /// Day the entry will be logged on (an edited entry moves with its date and time).
    private var entryDay: Date { entry != nil ? Calendar.current.startOfDay(for: time) : day }

    /// Nutrients of the quantity typed, previewed in what is left (nil while it is invalid).
    private var pendingPortion: NutrientValues? { grams == nil ? nil : portion }

    /// Current nutrients of the edited entry, already counted in its day's total.
    private var replacedNutrients: NutrientValues? {
        guard let entry, pendingPortion != nil,
              Calendar.current.isDate(entry.day, inSameDayAs: entryDay) else { return nil }
        return entry.nutrients
    }

    private func unitWord(_ unit: AddEntryUnit, count: Double) -> String {
        switch unit {
        case .base: return item.unitSymbol
        case .serving: return count > 1 ? "portions" : "portion"
        case .package: return count > 1 ? "emballages" : "emballage"
        case .ounce, .pound: return unitTitle(unit)
        }
    }

    private func unitTitle(_ unit: AddEntryUnit) -> String {
        switch unit {
        case .base: return item.unitSymbol
        case .serving: return "portion"
        case .package: return "emballage"
        case .ounce: return item.isLiquid ? "fl oz" : "oz"
        case .pound: return "lb"
        }
    }

    private var step: Double {
        switch unit {
        case .serving: return 0.5
        case .package, .pound: return 0.25
        case .ounce: return 1
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
        case .serving, .package, .ounce, .pound:
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

    private func close() {
        if let onBack { onBack() } else { dismiss() }
    }

    var body: some View {
        if onBack != nil {
            VStack(spacing: 0) {
                embeddedHeader
                scrollContent
            }
            .background(Theme.raised)
            .confirmationDialog(
                "Supprimer cet aliment du journal ?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { deleteEntry() }
                Button("Annuler", role: .cancel) {}
            }
            .slideCover(isPresented: $showCustomEditor) {
                CustomFoodEditor(food: editedCustomFood, prefill: editedCustomFood == nil ? item : nil)
            }
            .sensoryFeedback(.selection, trigger: favoriteToggles)
            .onAppear { caretOn = true }
            // The add sheet header previews what will be left with this quantity.
            .preference(key: AddEntryPendingKey.self,
                        value: pendingPortion.map { AddEntryPending(day: entryDay, nutrients: $0) })
        } else {
            sheetBody
        }
    }

    /// Sheet header (reference: add sheet): close button and what is left for the day,
    /// including the quantity typed, so the remaining kcal and macros stay in view.
    private var sheetTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50, height: 50)
                    .background(Theme.raised2, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
            DayRemainingView(day: entryDay, pending: pendingPortion, replacing: replacedNutrients)
                .id(entryDay)
                .frame(maxWidth: .infinity)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Theme.raised)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(entry == nil ? "Ajouter" : "Modifier")
    }

    /// Back chevron + centered food name (reference layout inside the add panel).
    private var embeddedHeader: some View {
        ZStack {
            Text(item.name)
                .font(Theme.font(18, .regular, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 52)
            HStack {
                Button { close() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retour")
                Spacer()
            }
            .padding(.leading, 6)
        }
        .padding(.vertical, 2)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AddEntryMacroSummary(per100: item.per100, portion: portion)
                    .padding(.top, 4)
                if !isQuickAdd {
                    // MF: tiles right under the macro labels.
                    actionsRow
                }
                AddEntryHairline()
                    .padding(.top, 12)
                dayShare
                    .padding(.top, 12)
                whenRow
                    .padding(.top, 14)
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
    }

    private var sheetBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    AddEntryMacroSummary(per100: item.per100, portion: portion)
                        .padding(.top, 10)
                    if !isQuickAdd {
                        actionsRow
                    }
                    AddEntryHairline()
                        .padding(.top, 12)
                    dayShare
                        .padding(.top, 12)
                    whenRow
                        .padding(.top, 14)
                    if showsDatasetAttribution {
                        AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) { sheetTopBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { entryPanel }
            .background(Theme.raised.ignoresSafeArea())
            .navigationTitle(entry == nil ? "Ajouter" : "Modifier")
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "Supprimer cet aliment du journal ?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { deleteEntry() }
                Button("Annuler", role: .cancel) {}
            }
            .slideCover(isPresented: $showCustomEditor) {
                CustomFoodEditor(food: editedCustomFood, prefill: editedCustomFood == nil ? item : nil)
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

    /// Five tiles spread over the full width (reference: Edit, Share, Favorite, Delete, Duplicate).
    private var actionsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            actionTile("Modifier", systemImage: "pencil", action: openEditor)
                .accessibilityLabel(item.source == .custom ? "Modifier l'aliment"
                                                           : "Créer un aliment personnalisé à partir de celui-ci")
            ShareLink(item: shareText) {
                actionTileLabel("Partager", systemImage: "square.and.arrow.up", tint: Theme.textPrimary)
            }
            .buttonStyle(.plain)
            actionTile("Favori", systemImage: isFavorite ? "heart.fill" : "heart",
                       tint: isFavorite ? Theme.protein : Theme.textPrimary, action: toggleFavorite)
                .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
            actionTile("Supprimer", systemImage: "trash.fill") { showDeleteConfirm = true }
                .disabled(entry == nil)
                .opacity(entry == nil ? 0.35 : 1)
            actionTile("Dupliquer", systemImage: "square.on.square.fill", action: duplicate)
        }
    }

    private func actionTile(_ title: String, systemImage: String, tint: Color = Theme.textPrimary,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionTileLabel(title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func actionTileLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.hex(0x2E2E2E), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(Theme.font(15, .regular, relativeTo: .footnote))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// Plain-text summary shared from the "Partager" tile.
    private var shareText: String {
        let v = item.per100
        let macros = Theme.macroOrder
            .map { "\(Formatters.number(v.value($0), maxFractionDigits: 1)) g \($0.label.lowercased())" }
            .joined(separator: ", ")
        return "\(item.name) — pour 100 \(item.unitSymbol) : \(Formatters.kcal(v.calories)), \(macros)"
    }

    private var dayShare: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Impact sur les objectifs")
                .font(Theme.font(18, .bold, relativeTo: .title3))
                .foregroundStyle(Theme.textBody)
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
            let targets = profile.targets(on: entry?.day ?? day)
            switch key {
            case .calories, .carbohydrates, .protein, .totalFat: target = targets.value(key)
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

    /// Reference panel: #313133 background, white-bordered field, unit chips, 4-column keypad
    /// whose last row holds the two actions.
    private var entryPanel: some View {
        VStack(spacing: 8) {
            quantityField
            unitRow
            AddEntryKeypad(onKey: press, onClear: clearQuantity) {
                actionKeys
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(AddEntryPanel.background.ignoresSafeArea(edges: .bottom))
    }

    private var quantityField: some View {
        HStack(spacing: 8) {
            HStack(alignment: .center, spacing: 1) {
                Text(quantityText.isEmpty ? " " : quantityText)
                    .font(Theme.font(15, .regular, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, replacesOnType ? 2 : 0)
                    .background {
                        if replacesOnType && !quantityText.isEmpty {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.calories.opacity(0.35))
                        }
                    }
                if !replacesOnType || quantityText.isEmpty {
                    Rectangle()
                        .fill(Theme.textPrimary)
                        .frame(width: 2, height: 19)
                        .opacity(caretOn ? 1 : 0.1)
                        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: caretOn)
                }
            }
            Spacer(minLength: 4)
            Text(quantityDetail)
                .font(Theme.font(15, .regular, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(quantity == nil ? Theme.overTarget : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(AddEntryPanel.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.textPrimary, lineWidth: 2)
        }
        // MF: field inset 4 pt more than the keypad on each side.
        .padding(.horizontal, 10)
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

    /// Reference strip: cycle arrows, base unit, divider, then portion / package / oz / lb.
    private var unitRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: cycleUnit) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(availableUnits.count < 2)
                .accessibilityLabel("Changer d'unité")
                if availableUnits.count > 1 {
                    ForEach(availableUnits, id: \.self) { candidate in
                        unitButton(candidate)
                        if candidate == .base {
                            Rectangle()
                                .fill(Theme.textTertiary.opacity(0.5))
                                .frame(width: 1.5, height: 44)
                                .padding(.horizontal, 2)
                        }
                    }
                }
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 6)
        }
    }

    private func unitButton(_ candidate: AddEntryUnit) -> some View {
        Button {
            select(candidate)
        } label: {
            AddEntryChipLabel(label: unitTitle(candidate), isSelected: unit == candidate)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(unit == candidate ? .isSelected : [])
    }

    private func cycleUnit() {
        guard availableUnits.count > 1, let index = availableUnits.firstIndex(of: unit) else { return }
        select(availableUnits[(index + 1) % availableUnits.count])
    }

    /// Last keypad row actions: secondary (dark) and primary (white).
    @ViewBuilder
    private var actionKeys: some View {
        let enabled = grams != nil
        if entry != nil {
            Button {
                showDeleteConfirm = true
            } label: {
                Text("Supprimer").foregroundStyle(Theme.overTarget)
            }
            .buttonStyle(AddEntryActionButtonStyle(isPrimary: false))
            Button("Enregistrer") { save(andContinue: false) }
                .buttonStyle(AddEntryActionButtonStyle(isPrimary: true))
                .disabled(!enabled)
        } else {
            Button("Continuer") { save(andContinue: true) }
                .buttonStyle(AddEntryActionButtonStyle(isPrimary: false))
                .disabled(!enabled)
                .accessibilityLabel("Ajouter et continuer")
            Button("Ajouter") { save(andContinue: false) }
                .buttonStyle(AddEntryActionButtonStyle(isPrimary: true))
                .disabled(!enabled)
        }
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
        case .slash:
            if replacesOnType || quantityText.isEmpty {
                quantityText = "1/"
            } else if !(quantityText.split(separator: " ").last ?? "").contains("/"), !quantityText.hasSuffix(" ") {
                quantityText.append("/")
            }
        case .space:
            if !replacesOnType, !quantityText.isEmpty, !quantityText.contains(" "), !quantityText.contains("/") {
                quantityText.append(" ")
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
            case .ounce:
                let tenths = (converted * 10).rounded() / 10
                quantityText = AddEntrySheet.format(tenths > 0 ? tenths : converted)
            case .pound:
                let hundredths = (converted * 100).rounded() / 100
                quantityText = AddEntrySheet.format(hundredths > 0 ? hundredths : converted)
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
        if !andContinue, let onLogged {
            onLogged()
            // Embedded in the add flow, `onLogged` closes the whole page: going back to the
            // search first would refocus its field (keyboard up) while the page slides out.
            if onBack != nil { return }
        }
        close()
    }

    /// "Modifier": edits the custom food itself, otherwise creates one prefilled from this food.
    private func openEditor() {
        editedCustomFood = nil
        if item.source == .custom, let ref = item.ref, let id = UUID(uuidString: ref) {
            let descriptor = FetchDescriptor<CustomFood>(predicate: #Predicate { $0.id == id })
            if let food = try? modelContext.fetch(descriptor).first, !food.isRecipe {
                editedCustomFood = food
            }
        }
        showCustomEditor = true
    }

    /// "Dupliquer": copies the journal entry (same day, time and meal); for a food not yet
    /// logged, creates a custom food prefilled from it.
    private func duplicate() {
        guard let entry else {
            editedCustomFood = nil
            showCustomEditor = true
            return
        }
        modelContext.insert(JournalEntry(item: entry.item, grams: entry.grams, day: entry.day,
                                         meal: entry.meal, at: entry.createdAt))
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let onLogged { onLogged() } else { close() }
    }

    private func deleteEntry() {
        guard let entry else { return }
        modelContext.delete(entry)
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        close()
    }
}

// MARK: - Components

/// Reference colors of the quantity panel.
enum AddEntryPanel {
    static let background = Theme.hex(0x313133)
    static let field = Theme.hex(0x3F3F41)
    static let chip = Theme.hex(0x232323)
    /// Sampled on the reference keypad.
    static let digitKey = Theme.hex(0x636264)
    static let sideKey = Theme.hex(0x424143)
    /// Labels under the big figures (measured on the reference).
    static let label = Theme.hex(0x787878)

    /// Filled pill behind the macro energy share (dark tone of the macro color).
    static func pill(_ key: NutrientKey) -> Color {
        switch key {
        case .protein: Theme.hex(0x7E2C10)
        case .totalFat: Theme.hex(0x826100)
        default: Theme.hex(0x0E5B36)
        }
    }
}

/// Big kcal + G / P / L for the current quantity, each macro with a filled pill showing the
/// share of the food's energy it provides.
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
            VStack(spacing: 0) {
                Text(Formatters.number(portion.calories, maxFractionDigits: 0))
                    .font(Theme.font(35, .bold, relativeTo: .largeTitle))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Calories")
                    .font(Theme.font(14, .regular, relativeTo: .callout))
                    .foregroundStyle(AddEntryPanel.label)
                    .padding(.top, -6)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            ForEach(Theme.macroOrder, id: \.self) { key in
                VStack(spacing: 0) {
                    Text(energyShare(key))
                        .font(Theme.font(13, .regular, relativeTo: .subheadline))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        // Compact MF pill.
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(AddEntryPanel.pill(key), in: Capsule())
                        .padding(.bottom, 8)
                    Text(Formatters.number(portion.value(key), maxFractionDigits: 1))
                        .font(Theme.font(20, .bold, relativeTo: .title2))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(key.label)
                        .font(Theme.font(14, .regular, relativeTo: .callout))
                        .foregroundStyle(AddEntryPanel.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, -4)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.quick, value: portion)
    }
}

/// Ring: share of the day's target that the current quantity represents.
private struct AddEntryDayRing: View {
    let fraction: Double
    let color: Color
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Theme.track, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(fraction > 1.05 ? Theme.overTarget : color,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Formatters.percent(fraction))
                    .font(Theme.font(15, .regular, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
            }
            .frame(width: 54, height: 54)
            .animation(.quick, value: fraction)
            Text(title)
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Formatters.percent(fraction)) de l'objectif du jour")
    }
}

/// 4 × 4 keypad (reference): digits in light keys, "/", space and ⌫ in the darker right column,
/// last row "," · 0 · two action keys (long press on ⌫ clears).
private struct AddEntryKeypad<Actions: View>: View {
    let onKey: (AddEntryKey) -> Void
    let onClear: () -> Void
    @ViewBuilder let actions: Actions

    private static var rows: [[AddEntryKey]] {
        [
            [.digit(1), .digit(2), .digit(3), .slash],
            [.digit(4), .digit(5), .digit(6), .space],
            [.digit(7), .digit(8), .digit(9), .delete],
        ]
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(Self.rows[row], id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
            HStack(spacing: 6) {
                keyButton(.comma)
                keyButton(.digit(0))
                actions
            }
        }
    }

    private static func isSide(_ key: AddEntryKey) -> Bool {
        switch key {
        case .slash, .space, .delete: true
        default: false
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
                case .slash:
                    Text("/")
                case .space:
                    Image(systemName: "space")
                        .font(.system(size: 18, weight: .semibold))
                case .delete:
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .font(Theme.font(22, .regular, relativeTo: .title2))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Self.isSide(key) ? AddEntryPanel.sideKey : AddEntryPanel.digitKey,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(AddEntryKeyButtonStyle())

        switch key {
        case .delete:
            button
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onClear() })
                .accessibilityLabel("Effacer")
        case .comma:
            button.accessibilityLabel("Virgule")
        case .slash:
            button.accessibilityLabel("Fraction")
        case .space:
            button.accessibilityLabel("Espace")
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

/// Action key in the keypad's last row: white (primary) or dark side-key gray (secondary).
private struct AddEntryActionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, .medium, relativeTo: .body))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isPrimary ? Theme.onAccent : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isPrimary ? Theme.accent : AddEntryPanel.sideKey,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.55))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Unit chip: dark capsule; the current unit is white with black text (reference).
private struct AddEntryChipLabel: View {
    let label: String
    let isSelected: Bool
    var isOutlined: Bool = false

    var body: some View {
        Text(label)
            .font(Theme.font(14, isSelected ? .medium : .regular, relativeTo: .body))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, 18)
            .frame(minWidth: 60)
            .frame(height: 44)
            .background(isSelected ? Theme.accent : AddEntryPanel.chip, in: Capsule())
            .overlay {
                if isOutlined && !isSelected {
                    Capsule().strokeBorder(Theme.textPrimary, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
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
