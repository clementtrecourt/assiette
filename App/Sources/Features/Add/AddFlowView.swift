import SwiftData
import SwiftUI
import UIKit

// CONTRACT (used by RootView, the journal and the dashboard) — keep these signatures:
//   AddFlowView(request: AddFlowRequest)   the add sheet (modes Scanner / Rechercher / IA / Rapide / Recettes)
//   AddShortcutsSheet()                     the "+" tab sheet
//   AddSearchBar()                          floating "Rechercher un aliment" bar above the tab bar
// Open the flow with `appState.presentAdd(.search, context: ...)`.

// MARK: - Shared helpers

/// "09:00" labels of the add flow (24 h, French).
enum AddTime {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Formatters.locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func label(_ date: Date) -> String { formatter.string(from: date) }

    /// Time an entry of `context` will be logged at (its slot time, or now).
    static func effectiveTime(of context: LogContext) -> Date {
        context.time ?? JournalEntry.defaultTime(on: context.day)
    }
}

extension AddMode {
    /// Tab title in the add sheet and the shortcuts sheet.
    var addFlowTitle: String {
        switch self {
        case .scan: "Scanner"
        case .search: "Rechercher"
        case .ai: "IA"
        case .quick: "Rapide"
        case .recipes: "Recettes"
        }
    }

    var addFlowSymbol: String {
        switch self {
        case .scan: "barcode.viewfinder"
        case .search: "magnifyingglass"
        case .ai: "sparkles"
        case .quick: "bolt"
        case .recipes: "book.closed"
        }
    }
}

// MARK: - Add sheet

/// The add sheet: header (close, time chip, what is left for the day), mode tabs, then the
/// content of the selected mode. Logging closes the sheet.
struct AddFlowView: View {
    let request: AddFlowRequest
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode
    @State private var context: LogContext
    /// Food opened from search: its quantity screen replaces the tabs inside the panel.
    @State private var openedItem: FoodItem?
    /// Nutrients of the quantity typed on that screen, previewed in the header.
    @State private var pending: AddEntryPending?

    init(request: AddFlowRequest) {
        self.request = request
        _mode = State(initialValue: request.mode)
        _context = State(initialValue: request.context)
    }

    /// Full-screen cover: the header sits on the dark backdrop, the modes live in a raised
    /// panel with rounded top corners and a grabber (drag it down to close).
    var body: some View {
        VStack(spacing: 0) {
            AddFlowHeader(context: $context, pending: pending, onClose: { dismiss() })
            VStack(spacing: 0) {
              if let openedItem {
                Capsule()
                    .fill(Theme.raised2)
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                AddEntrySheet(item: openedItem, context: context, onLogged: { close() },
                              onBack: { withAnimation(.quick) { self.openedItem = nil } })
                    .id(openedItem.id)
                    .transition(.move(edge: .trailing))
              } else {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Theme.raised2)
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .accessibilityHidden(true)
                    AddFlowModeTabs(selection: $mode)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            let t = value.translation
                            if t.height > 90, abs(t.height) > abs(t.width) * 2 { dismiss() }
                        }
                )
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.addFlowOpenItem) { item in
                        withAnimation(.quick) { openedItem = item }
                    }
              }
            }
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                    .fill(Theme.raised)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onPreferenceChange(AddEntryPendingKey.self) { value in
            pending = value
        }
        .onAppear {
            // CI screenshot: quantity screen inside the panel.
            if DemoSupport.startSheet == "addflow-entry", openedItem == nil { openedItem = DemoSupport.sampleItem }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .scan:
            BarcodeScanView(context: context, onLogged: { close() }, embedded: true)
        case .search:
            FoodSearchView(embeddedIn: context,
                           onLogged: { close() },
                           onQuickAdd: { mode = .quick })
        case .ai:
            AIEstimateView(context: context, onLogged: { close() })
        case .quick:
            QuickAddSheet(context: context, isEmbedded: true, onLogged: { close() })
        case .recipes:
            NavigationStack {
                CustomFoodsListView(pickContext: context, onLogged: { close() })
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func close() {
        dismiss()
    }
}

/// Close button, time chip and the remaining-of-the-day mini bars.
private struct AddFlowHeader: View {
    @Binding var context: LogContext
    /// Food being added on the quantity screen (previewed in what is left).
    var pending: AddEntryPending?
    let onClose: () -> Void

    @State private var showingTime = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.raised2, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")

            Button {
                showingTime = true
            } label: {
                Text(AddTime.label(AddTime.effectiveTime(of: context)))
                    .font(Theme.font(17, .regular, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                .background(Theme.raised2, in: Capsule())
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Heure : \(AddTime.label(AddTime.effectiveTime(of: context)))")
            .popover(isPresented: $showingTime) {
                AddFlowTimePicker(context: $context, onDone: { showingTime = false })
                    .presentationCompactAdaptation(.popover)
            }

            DayRemainingView(day: pending?.day ?? context.day, pending: pending?.nutrients)
                .frame(maxWidth: .infinity)
                .padding(.leading, 2)

            // Meal of the entries (reference: the dim fork-and-knife pill on the right).
            Menu {
                Picker("Repas", selection: $context.meal) {
                    ForEach(Meal.allCases) { meal in
                        Label(meal.label, systemImage: meal.systemImage).tag(meal)
                    }
                }
            } label: {
                Image(systemName: "fork.knife")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 66, height: 50)
                    .background(Theme.raised2.opacity(0.55), in: Capsule())
                    .contentShape(Capsule())
            }
            .accessibilityLabel("Repas : \(context.meal.label)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}

/// Compact time picker shown from the time chip.
private struct AddFlowTimePicker: View {
    @Binding var context: LogContext
    let onDone: () -> Void

    private var time: Binding<Date> {
        Binding(
            get: { AddTime.effectiveTime(of: context) },
            set: { newValue in
                let calendar = Calendar.current
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                let day = calendar.startOfDay(for: context.day)
                let time = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0,
                                         second: 0, of: day) ?? newValue
                context.time = time
                context.meal = Meal.suggested(for: time)
            }
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            DatePicker("Heure", selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(width: 230, height: 150)
                .clipped()
            HStack {
                Button("Maintenant") {
                    let now = Date.now
                    if Calendar.current.isDate(context.day, inSameDayAs: now) {
                        context.time = nil
                        context.meal = Meal.suggested(for: now)
                    } else {
                        time.wrappedValue = now
                    }
                    onDone()
                }
                .font(Theme.font(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("OK", action: onDone)
                    .font(Theme.font(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 254)
        .background(Theme.raised)
    }
}

/// Horizontally scrollable mode tabs with an underline on the selected one.
private struct AddFlowModeTabs: View {
    @Binding var selection: AddMode

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(AddMode.allCases) { mode in
                        tab(mode)
                            .id(mode)
                    }
                }
                .padding(.horizontal, 4)
            }
            .background(alignment: .bottom) {
                // Full-width 4 pt track under the tabs; the selected tab draws white over it.
                Rectangle()
                    .fill(Theme.raised2)
                    .frame(height: 4)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, mode in
                withAnimation(.quick) { proxy.scrollTo(mode, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tab(_ mode: AddMode) -> some View {
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: mode.addFlowSymbol)
                        .font(.system(size: 14, weight: .regular))
                    Text(mode.addFlowTitle)
                        .font(Theme.font(15, .regular, relativeTo: .body))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
                Rectangle()
                    .fill(isSelected ? Theme.textPrimary : Color.clear)
                    .frame(height: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shortcuts sheet ("+" tab)

private enum AddShortcutsDestination: String, Identifiable {
    case weight, water
    var id: String { rawValue }
}

/// Sheet of the central "+" tab: the four ways to add food, then weight and water.
struct AddShortcutsSheet: View {
    @Environment(AppState.self) private var appState
    @Query(AddShortcutsSheet.latestWeightDescriptor) private var latestWeights: [WeightEntry]
    @Query private var todayWater: [WaterEntry]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var nested: AddShortcutsDestination?
    /// Add mode to open once this sheet has finished closing (one sheet at a time).
    @State private var pendingMode: AddMode?
    @State private var contentHeight: CGFloat = 300

    init() {
        let today = Calendar.current.startOfDay(for: .now)
        _todayWater = Query(filter: #Predicate<WaterEntry> { $0.day == today })
    }

    private static var latestWeightDescriptor: FetchDescriptor<WeightEntry> {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\WeightEntry.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            actions
            row(title: "Pesée", subtitle: weightSubtitle, systemImage: "scalemass.fill", color: Theme.weight) {
                nested = .weight
            }
            row(title: "Eau", subtitle: waterSubtitle, systemImage: "drop.fill", color: Theme.water) {
                nested = .water
            }
        }
        .padding(.bottom, 6)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { contentHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in contentHeight = newValue }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(contentHeight + 24)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.raised)
        .presentationCornerRadius(22)
        .sheet(item: $nested, onDismiss: {
            // The shortcut did its job: close the launcher too.
            appState.showingShortcuts = false
        }) { destination in
            switch destination {
            case .weight:
                ProgressAddWeightSheet(initialKg: latestWeights.first?.kg ?? profiles.first?.weightKg)
            case .water:
                AddWaterSheet()
            }
        }
        .onDisappear {
            if let mode = pendingMode {
                pendingMode = nil
                appState.presentAdd(mode)
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("Raccourcis")
                .font(Theme.font(16, .bold, relativeTo: .headline))
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Button {
                    appState.showingShortcuts = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.raised2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: Theme.hairline)
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            ForEach(AddMode.allCases) { mode in
                Button {
                    open(mode)
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: mode.addFlowSymbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 50, height: 50)
                            .background(Theme.raised2, in: Circle())
                        Text(mode.addFlowTitle)
                            .font(Theme.font(12, .medium, relativeTo: .caption))
                            .foregroundStyle(Theme.textBody)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private func row(title: String, subtitle: String, systemImage: String, color: Color,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(subtitle)
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: Theme.hairline)
        }
    }

    private var weightSubtitle: String {
        guard let latest = latestWeights.first else { return "Aucune pesée" }
        let kg = "\(Formatters.number(latest.kg, maxFractionDigits: 1)) kg"
        let calendar = Calendar.current
        if calendar.isDateInToday(latest.date) || calendar.isDateInYesterday(latest.date) {
            return "\(kg) · \(Formatters.dayTitle(latest.date).lowercased())"
        }
        return "\(kg) · \(Formatters.shortDate(latest.date))"
    }

    private var waterSubtitle: String {
        let total = todayWater.reduce(0) { $0 + $1.ml }
        let target = profiles.first?.waterTargetMl ?? 2000
        return "\(Formatters.number(total / 1000, maxFractionDigits: 1)) / \(Formatters.number(target / 1000, maxFractionDigits: 1)) L"
    }

    /// Closes this sheet, then opens the add sheet once it is gone (see `onDisappear`).
    private func open(_ mode: AddMode) {
        pendingMode = mode
        appState.showingShortcuts = false
    }
}

// MARK: - Water sheet

/// Small sheet to log water for today: +250 / +500 ml, or a typed amount (keyboard up).
struct AddWaterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var todayWater: [WaterEntry]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var amountText = ""
    @FocusState private var amountFocused: Bool

    private let day: Date

    init(day: Date = .now) {
        let start = Calendar.current.startOfDay(for: day)
        self.day = start
        _todayWater = Query(filter: #Predicate<WaterEntry> { $0.day == start })
    }

    private var total: Double { todayWater.reduce(0) { $0 + $1.ml } }
    private var target: Double { profiles.first?.waterTargetMl ?? 2000 }

    private var amount: Double? {
        let cleaned = amountText
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0, value <= 5000 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                summary
                HStack(spacing: 10) {
                    quickButton(250)
                    quickButton(500)
                }
                customRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Eau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .tint(Theme.textSecondary)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                amountFocused = true
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Formatters.number(total / 1000, maxFractionDigits: 2)) L")
                    .font(Theme.font(28, .bold, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("sur \(Formatters.number(target / 1000, maxFractionDigits: 1)) L aujourd'hui")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
            ProgressBar(value: total, total: target, color: Theme.water, height: 4)
        }
    }

    private func quickButton(_ ml: Double) -> some View {
        Button {
            addWater(ml)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.water)
                Text("+\(Formatters.number(ml, maxFractionDigits: 0)) ml")
                    .font(Theme.font(15, .bold, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var customRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Autre quantité", text: $amountText,
                          prompt: Text("Autre quantité").foregroundColor(Theme.textTertiary))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(Theme.font(17, .bold, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
                Text("ml")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(amountFocused ? Theme.textTertiary : Theme.separatorStrong, lineWidth: Theme.hairline)
            }
            .contentShape(Rectangle())
            .onTapGesture { amountFocused = true }

            Button {
                if let amount { addWater(amount) }
            } label: {
                Text("Ajouter")
                    .font(Theme.font(15, .bold, relativeTo: .body))
                    .foregroundStyle(amount != nil ? Theme.onAccent : Theme.textTertiary)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(amount != nil ? Theme.accent : Theme.raised2,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(amount == nil)
        }
    }

    private func addWater(_ ml: Double) {
        modelContext.insert(WaterEntry(day: day, ml: ml))
        try? modelContext.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Floating search bar

/// Floating search bar shown above the tab bar on the main tabs. The field part opens the add
/// sheet in search mode (keyboard up), the barcode icon opens the scanner directly.
struct AddSearchBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            Button {
                appState.presentAdd(.search)
            } label: {
                HStack(spacing: 14) {
                    Image("Glyph-loupe")
                        .resizable().frame(width: 20, height: 20)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Rechercher un aliment")
                        .font(Theme.font(16, .regular, relativeTo: .body))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 18)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rechercher un aliment")

            Button {
                appState.presentAdd(.scan)
            } label: {
                Image("Glyph-scan")
                    .resizable().frame(width: 20, height: 20)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 56)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scanner un code-barres")
        }
        .frame(height: 48)
        .background(Theme.searchField, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background {
            // Fades the scrolling content into the background behind the bar.
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                           startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
        }
    }
}

private struct AddFlowOpenItemKey: EnvironmentKey {
    static let defaultValue: ((FoodItem) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set inside the add flow: opens a food's quantity screen in the panel instead of a sheet.
    var addFlowOpenItem: ((FoodItem) -> Void)? {
        get { self[AddFlowOpenItemKey.self] }
        set { self[AddFlowOpenItemKey.self] = newValue }
    }
}
