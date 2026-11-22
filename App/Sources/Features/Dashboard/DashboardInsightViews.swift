import SwiftUI
import UIKit

// Building blocks of the dashboard detail screens, measured on the reference recording
// (2026-11-22): raised top area (headline over the chart, range chips + averaging button),
// legend card, "Analyses et données" cards (change table, value tiles), data sources and a
// day-by-day history grouped by month.

// MARK: - Scaffold

/// Detail screen: raised navigation bar with a centered title and a "learn" button, raised top
/// area (`top`) then the rest of the page on the dark background.
struct InsightScaffold<Top: View, Content: View>: View {
    let title: String
    let explanation: String
    let top: Top
    let content: Content

    @State private var showingExplanation = false
    @Environment(\.dismiss) private var dismiss

    /// MF (aligned pair): the bar's chevron and title sit 5 pt lower than UIKit's.
    private static var barItemOffset: CGFloat { 5 }

    init(title: String, explanation: String, @ViewBuilder top: () -> Top, @ViewBuilder content: () -> Content) {
        self.title = title
        self.explanation = explanation
        self.top = top()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                top
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.raised)
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        // MF: no hairline under the bar. Transparent system bar (no shadow in any state) over a
        // raised strip painted across the status bar + bar area, above the scrolling content.
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            Color.clear.frame(height: 0).background(Theme.raised)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Custom chevron (MF size and height); the edge swipe back stays enabled.
        .navigationBarBackButtonHidden(true)
        .background(InsightSwipeBackEnabler())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    // MF: 8 × 14 pt chevron, 3 pt stroke, ~20 pt from the screen edge.
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.leading, 3)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: Self.barItemOffset)
                .accessibilityLabel("Retour")
            }
            ToolbarItem(placement: .principal) {
                InsightNavigationTitle(title: title)
                    .offset(y: Self.barItemOffset)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingExplanation = true
                } label: {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .offset(y: Self.barItemOffset)
                .accessibilityLabel("Comprendre cet écran")
            }
        }
        .sheet(isPresented: $showingExplanation) {
            InsightExplanationSheet(title: title, text: explanation)
        }
    }
}

/// Keeps the edge swipe back working on a screen whose system back button is hidden: while the
/// screen is shown, the navigation controller's pop gesture asks this controller instead of
/// UIKit (which refuses to begin without a back button); the previous delegate is restored after.
private struct InsightSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var popGesture: UIGestureRecognizer?
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            if gesture.delegate !== self {
                previousDelegate = gesture.delegate
                gesture.delegate = self
            }
            popGesture = gesture
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let popGesture, popGesture.delegate === self {
                popGesture.delegate = previousDelegate
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

/// Navigation bar title of the detail screens (reference: 18 pt regular, not the system semibold).
struct InsightNavigationTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.font(18, .regular, relativeTo: .headline))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct InsightExplanationSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InsightSheetHeader(title: title) { dismiss() }
            Text(text)
                .font(Theme.font(15, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textBody)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.raised)
        .presentationCornerRadius(22)
    }
}

/// Sheet title bar: round close button on the left, centered bold title, hairline below.
struct InsightSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.font(17, .bold, relativeTo: .headline))
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
                Spacer()
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separatorStrong).frame(height: Theme.hairline)
        }
    }
}

// MARK: - Top tabs

/// Two tabs with an icon (Poids balance / Poids tendance, Dépense / Objectifs caloriques) and a
/// sliding white underline over a grey track.
struct InsightTabs: View {
    struct Tab: Hashable {
        var title: String
        var systemImage: String
    }

    let tabs: [Tab]
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { index in
                    Button {
                        withAnimation(.quick) { selection = index }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tabs[index].systemImage)
                                .font(.system(size: 15, weight: .semibold))
                            Text(tabs[index].title)
                                .font(Theme.font(16, .medium, relativeTo: .headline))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(selection == index ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
                }
            }
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(max(tabs.count, 1))
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.raised2).frame(height: 2)
                    Rectangle()
                        .fill(Theme.textPrimary)
                        .frame(width: width, height: 3)
                        .offset(x: width * CGFloat(selection))
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 3)
        }
        .background(Theme.raised)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Headline

/// One column of the headline: grey caption, big value + unit.
struct InsightHeadlineValue: View {
    let caption: String
    let value: String
    var unit: String = ""
    var numeric: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(Theme.font(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Reference: ~30 pt medium, a touch lighter than the screen titles.
                Text(value)
                    .font(Theme.font(30, .medium, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: numeric))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.font(14, .regular, relativeTo: .subheadline))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Headline over the chart: one or two values, the date range below, round zoom button on the right.
struct InsightHeadline: View {
    let primary: InsightHeadlineValue
    var secondary: InsightHeadlineValue?
    let dates: String
    @Binding var fitToData: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Reference: the date range sits right under the values (tight line).
            VStack(alignment: .leading, spacing: -2) {
                HStack(alignment: .top, spacing: 0) {
                    primary
                        .frame(width: secondary == nil ? nil : 155, alignment: .leading)
                    if let secondary {
                        secondary
                    }
                }
                Text(dates)
                    .font(Theme.font(16, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            InsightZoomButton(fitToData: $fitToData)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .animation(.quick, value: dates)
    }
}

/// Grey disc (white when active) that fits the y-axis to the data.
struct InsightZoomButton: View {
    @Binding var fitToData: Bool

    var body: some View {
        Button {
            withAnimation(.quick) { fitToData.toggle() }
        } label: {
            Image(systemName: fitToData ? "arrow.down.and.line.horizontal.and.arrow.up"
                                        : "arrow.up.and.line.horizontal.and.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(fitToData ? Theme.onAccent : Theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(fitToData ? Theme.accent : Theme.tile))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fitToData ? "Échelle complète" : "Ajuster l'échelle aux données")
        .sensoryFeedback(.selection, trigger: fitToData)
    }
}

// MARK: - Range bar

/// Range chips in a dark capsule (selected = white capsule) and the averaging button ("J ⌄").
struct InsightRangeBar: View {
    @Binding var range: InsightRange
    @Binding var averaging: InsightAveraging
    @State private var showingAveraging = false
    @Namespace private var chip

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(InsightRange.allCases) { item in
                    Button {
                        withAnimation(.quick) { range = item }
                    } label: {
                        Text(item.label)
                            .font(Theme.font(15, .regular, relativeTo: .subheadline))
                            .foregroundStyle(range == item ? Theme.onAccent : Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background {
                                if range == item {
                                    Capsule().fill(Theme.accent)
                                        .matchedGeometryEffect(id: "selected", in: chip)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityAddTraits(range == item ? .isSelected : [])
                }
            }
            .background(Capsule().fill(Theme.tile))

            Button {
                showingAveraging = true
            } label: {
                HStack(spacing: 8) {
                    Text(averaging.rawValue)
                        .font(Theme.font(15, .regular, relativeTo: .subheadline))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 66, height: 40)
                .background(Capsule().fill(Theme.tile))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Moyenne du graphique : \(averaging.title)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        // Reference: raised band ends 21 pt under the selector.
        .padding(.bottom, 18)
        .sensoryFeedback(.selection, trigger: range)
        .sheet(isPresented: $showingAveraging) {
            InsightAveragingSheet(averaging: $averaging)
        }
    }
}

private struct InsightAveragingSheet: View {
    @Binding var averaging: InsightAveraging
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            InsightSheetHeader(title: "Moyenne du graphique") { dismiss() }
            ForEach(InsightAveraging.allCases) { option in
                Button {
                    withAnimation(.quick) { averaging = option }
                    dismiss()
                } label: {
                    HStack {
                        Text(option.title)
                            .font(Theme.font(16, .regular, relativeTo: .body))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        ZStack {
                            Circle()
                                .strokeBorder(averaging == option ? Theme.textPrimary : Theme.textTertiary, lineWidth: 1.5)
                            if averaging == option {
                                Circle().fill(Theme.textPrimary)
                                Circle().fill(Theme.onAccent).frame(width: 7, height: 7)
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(averaging == option ? .isSelected : [])
                if option != InsightAveraging.allCases.last {
                    Rectangle().fill(Theme.separatorStrong).frame(height: Theme.hairline)
                        .padding(.leading, 16)
                }
            }
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(270)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.raised)
        .presentationCornerRadius(22)
    }
}

// MARK: - Legend

struct InsightLegendItem: Hashable {
    var mark: InsightLegendMarkID
    var text: String
}

/// Hashable wrapper so legend items can be listed with `ForEach`.
struct InsightLegendMarkID: Hashable {
    var kind: Int
    var color: Color
    static func band(_ c: Color) -> Self { .init(kind: 0, color: c) }
    static func lineDot(_ c: Color) -> Self { .init(kind: 1, color: c) }
    static func holding(_ c: Color) -> Self { .init(kind: 2, color: c) }
    static func dot(_ c: Color) -> Self { .init(kind: 3, color: c) }
    static func line(_ c: Color) -> Self { .init(kind: 4, color: c) }
    static func bars(_ c: Color) -> Self { .init(kind: 5, color: c) }
    static func dashed(_ c: Color) -> Self { .init(kind: 6, color: c) }
    static func square(_ c: Color) -> Self { .init(kind: 7, color: c) }
}

/// Legend card under the chart (items centered, wrapping on two lines when needed).
struct InsightLegend: View {
    let items: [InsightLegendItem]

    var body: some View {
        // One line when it fits, otherwise two (2 + rest), never truncated.
        ViewThatFits(in: .horizontal) {
            rows([items])
            rows([Array(items.prefix(2)), Array(items.dropFirst(2))])
        }
        .frame(maxWidth: .infinity)
        // Reference: 54 pt card for one row, filled, no outline.
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom))
        )
        .accessibilityElement(children: .combine)
        // Reference: the "Analyses et données" heading cap sits 43 pt under the legend card.
        .padding(.bottom, 8)
    }

    private func rows(_ rows: [[InsightLegendItem]]) -> some View {
        VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(rows[row], id: \.self) { item in
                        HStack(spacing: 8) {
                            marker(item.mark)
                            Text(item.text)
                                .font(Theme.font(14, .regular, relativeTo: .subheadline))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func marker(_ mark: InsightLegendMarkID) -> some View {
        switch mark.kind {
        case 0:
            InsightMountainShape()
                .fill(mark.color)
                .frame(width: 15, height: 11)
        case 1:
            ZStack {
                Capsule().fill(mark.color).frame(width: 16, height: 2)
                Circle().strokeBorder(mark.color, lineWidth: 2).frame(width: 9, height: 9)
                    .background(Circle().fill(Theme.raised))
            }
        case 2:
            Rectangle().strokeBorder(mark.color, lineWidth: 1.6).frame(width: 9, height: 9)
        case 3:
            Circle().fill(mark.color).frame(width: 8, height: 8)
        case 4:
            Capsule().fill(mark.color).frame(width: 34, height: 3)
        case 5:
            HStack(alignment: .bottom, spacing: 2) {
                Rectangle().fill(mark.color).frame(width: 3, height: 7)
                Rectangle().fill(mark.color).frame(width: 3, height: 13)
                Rectangle().fill(mark.color).frame(width: 3, height: 9)
            }
        case 6:
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in Rectangle().fill(mark.color).frame(width: 5, height: 2.5) }
            }
        default:
            Rectangle().fill(mark.color).frame(width: 10, height: 10)
        }
    }
}

/// Two small peaks (the "range" legend icon).
private struct InsightMountainShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Sections

struct InsightSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.font(20, .semibold, relativeTo: .title3))
            .tracking(-0.3)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Card with a title ("Évolution de la dépense") then rows.
struct InsightCard<Content: View>: View {
    var title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(Theme.font(18, .regular, relativeTo: .headline))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 8)
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }
}

/// Direction shown after a change: arrow + "Hausse" / "Baisse" / "Stable".
enum InsightTrendWord {
    static func icon(_ delta: Double, threshold: Double) -> String {
        if delta > threshold { return "chart.line.uptrend.xyaxis" }
        if delta < -threshold { return "chart.line.downtrend.xyaxis" }
        return "arrow.right"
    }

    static func word(_ delta: Double, threshold: Double) -> String {
        if delta > threshold { return "Hausse" }
        if delta < -threshold { return "Baisse" }
        return "Stable"
    }
}

/// "3 jours ⟋ −50 kcal ↘ Baisse" rows.
struct InsightChangesRows: View {
    let changes: [InsightChange]
    let color: Color
    let format: (Double) -> String
    /// Below this absolute change the direction reads "Stable".
    var threshold: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(changes) { change in
                HStack(spacing: 0) {
                    Text("\(change.days) jours")
                        .font(Theme.font(14, .regular, relativeTo: .subheadline))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 76, alignment: .leading)
                    InsightMiniSpark(values: change.series, color: color)
                        .frame(width: 42, height: 22)
                    Text(format(change.delta))
                        .font(Theme.font(15, .regular, relativeTo: .subheadline))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Image(systemName: InsightTrendWord.icon(change.delta, threshold: threshold))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                        Text(InsightTrendWord.word(change.delta, threshold: threshold))
                            .font(Theme.font(14, .regular, relativeTo: .subheadline))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(width: 104, alignment: .leading)
                }
                .frame(height: 45)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// "3 jours  −1697 kcal  ▼ Déficit" rows (energy balance).
struct InsightBalanceRows: View {
    struct Row: Identifiable {
        var days: Int
        var value: Double?
        var id: Int { days }
    }

    let rows: [Row]
    let color: Color
    let positiveWord: String
    let negativeWord: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    Text("\(row.days) jours")
                        .font(Theme.font(14, .regular, relativeTo: .subheadline))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 88, alignment: .leading)
                    Text(row.value.map { "\(DashboardFormat.signed($0)) kcal" } ?? "–")
                        .font(Theme.font(15, .regular, relativeTo: .subheadline))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let value = row.value {
                        InsightBalanceStatus(value: value, color: color, positiveWord: positiveWord,
                                             negativeWord: negativeWord, compact: true)
                            .frame(width: 128, alignment: .leading)
                    }
                }
                .frame(height: 45)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// ▼ Déficit / ▲ Surplus.
struct InsightBalanceStatus: View {
    let value: Double
    let color: Color
    let positiveWord: String
    let negativeWord: String
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: value < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(color)
            Text(value < 0 ? negativeWord : positiveWord)
                .font(Theme.font(compact ? 14 : 16, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }
}

/// Value tile + title + explanation rows ("Dépense actuelle", "Stratégie actuelle", …).
struct InsightTile: Identifiable {
    var value: String
    var unit: String
    var title: String
    var text: String
    var id: String { title }
}

struct InsightTilesCard: View {
    let tiles: [InsightTile]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(tiles) { tile in
                HStack(alignment: .top, spacing: 15) {
                    VStack(spacing: 2) {
                        Text(tile.value)
                            .font(Theme.font(tile.value.count > 7 ? 20 : 24, .bold, relativeTo: .title2))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !tile.unit.isEmpty {
                            Text(tile.unit)
                                .font(Theme.font(14, .regular, relativeTo: .subheadline))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: 125, height: 100)
                    .background(Theme.tile)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tile.title)
                            .font(Theme.font(18, .regular, relativeTo: .headline))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tile.text)
                            .font(Theme.font(14, .regular, relativeTo: .subheadline))
                            .foregroundStyle(Theme.textTertiary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }
}

/// "Poids balance — Gérer les données ›" row.
struct InsightDataSourceRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.font(16, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.font(14, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textQuaternary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
        .themedCard()
        .contentShape(Rectangle())
    }
}

/// History grouped by month: bold month title, then a card of rows (value + date, status).
struct InsightHistory<Item: Identifiable, Trailing: View>: View {
    let groups: [InsightMonthGroup<Item>]
    let value: (Item) -> String
    let date: (Item) -> Date
    let trailing: (Item) -> Trailing

    init(groups: [InsightMonthGroup<Item>], value: @escaping (Item) -> String,
         date: @escaping (Item) -> Date, @ViewBuilder trailing: @escaping (Item) -> Trailing)
    {
        self.groups = groups
        self.value = value
        self.date = date
        self.trailing = trailing
    }

    var body: some View {
        ForEach(groups) { group in
            InsightSectionTitle(title: InsightCalendar.monthTitle(group.month))
            LazyVStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle().fill(Theme.separatorStrong).frame(height: Theme.hairline)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(value(item))
                                .font(Theme.font(17, .regular, relativeTo: .body))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            Text(InsightCalendar.rowDate(date(item)))
                                .font(Theme.font(14, .regular, relativeTo: .subheadline))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        trailing(item)
                    }
                    .frame(minHeight: 74)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .themedCard()
        }
    }
}

// MARK: - Mini sparkline

/// Line + soft area of a change row (42 × 22 pt).
struct InsightMiniSpark: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let points = DashboardSparkline.points(values, in: geo.size, minimumSpan: 0)
            ZStack {
                if points.count > 1 {
                    DashboardSparkline.areaPath(points, height: geo.size.height)
                        .fill(color.opacity(0.35))
                    DashboardSparkline.linePath(points)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
