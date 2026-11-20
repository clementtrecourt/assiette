import SwiftData
import SwiftUI
import UIKit

@main
struct AssietteApp: App {
    @State private var appState = AppState()

    /// Unit tests run inside the app: keep their launches on a throwaway in-memory store.
    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        Theme.registerFonts()
        Self.configureTabBarAppearance()
        Self.configureNavigationBarAppearance()
        if !Self.isRunningTests {
            Self.prewarmFoodDatabase()
        }
    }

    /// Opens the bundled SQLite file, pages in the FTS index, builds the French lexicon
    /// tables and caches the food count (thread-safe) in the background, so the first search (and the
    /// search sheet's hint text, which reads `count`) do not pay for it on the main thread.
    private static func prewarmFoodDatabase() {
        Task.detached(priority: .utility) {
            let database = FoodDatabase.shared
            guard database.isAvailable else { return }
            // "a" is a stop word (no SQL would run): use a real word that also goes
            // through the lexicon ("pomme" → apple).
            _ = database.search(FrenchFoodLexicon.rewritingPhrases("pomme"), limit: 1)
            _ = database.count
        }
    }

    /// Tab bar: opaque app background, hairline on top, selected item textPrimary, others
    /// textTertiary, DM Sans labels. UIKit appearance so the unselected color applies too.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.shadowColor = UIColor(Theme.separator)

        let normal = UIColor(Theme.textTertiary)
        let selected = UIColor(Theme.textPrimary)
        var normalAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: normal]
        var selectedAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: selected]
        if let font = UIFont(name: "DMSans-Medium", size: 10) {
            normalAttributes[.font] = font
            selectedAttributes[.font] = font
        }
        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ]
        for item in itemAppearances {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = normalAttributes
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = selectedAttributes
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    /// Navigation bars: DM Sans for inline and large titles and for toolbar text buttons
    /// (UIKit appearance, since SwiftUI's `navigationTitle` and toolbar buttons otherwise use SF).
    /// Background stays the system default (transparent at scroll edge, blurred when scrolled).
    private static func configureNavigationBarAppearance() {
        let title = UIColor(Theme.textPrimary)
        var titleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: title]
        var largeTitleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: title]
        if let font = UIFont(name: "DMSans-Bold", size: 17) {
            titleAttributes[.font] = UIFontMetrics(forTextStyle: .headline).scaledFont(for: font)
        }
        if let font = UIFont(name: "DMSans-Bold", size: 34) {
            largeTitleAttributes[.font] = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: font)
        }
        var buttonAttributes: [NSAttributedString.Key: Any] = [:]
        if let font = UIFont(name: "DMSans-Medium", size: 17) {
            buttonAttributes[.font] = UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
        }

        func styled(_ appearance: UINavigationBarAppearance) -> UINavigationBarAppearance {
            appearance.titleTextAttributes = titleAttributes
            appearance.largeTitleTextAttributes = largeTitleAttributes
            for buttons in [appearance.buttonAppearance, appearance.doneButtonAppearance] {
                buttons.normal.titleTextAttributes = buttonAttributes
                buttons.highlighted.titleTextAttributes = buttonAttributes
                buttons.disabled.titleTextAttributes = buttonAttributes
            }
            return appearance
        }

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = styled(standard)
        navigationBar.compactAppearance = styled(UINavigationBarAppearance(barAppearance: standard))
        navigationBar.scrollEdgeAppearance = styled(scrollEdge)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(\.locale, Formatters.locale)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(for: AppSchema.models, inMemory: Self.isRunningTests)
    }
}

/// Tabs: Accueil · Journal · + · Programme · Profil. The central "+" tab never stays selected:
/// it opens the shortcuts sheet. The main tabs show the floating search bar above the tab bar.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var didSetUpDemo = false
    @State private var lastRealTab: AppTab = .progress
    @State private var checkInPrompted = false

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .safeAreaInset(edge: .bottom, spacing: 0) { AddSearchBar() }
                .tabItem { Label("Accueil", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.progress)

            TodayView()
                .safeAreaInset(edge: .bottom, spacing: 0) { AddSearchBar() }
                .tabItem { Label("Journal", systemImage: "list.bullet.rectangle.portrait") }
                .tag(AppTab.today)

            Color.clear
                .tabItem { Image(uiImage: RootTabPlusImage.image).renderingMode(.original) }
                .tag(AppTab.add)

            ProgramView()
                .safeAreaInset(edge: .bottom, spacing: 0) { AddSearchBar() }
                .tabItem { Label("Programme", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.program)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.textPrimary)
        .onChange(of: appState.selectedTab) { _, newValue in
            if newValue == .add {
                appState.selectedTab = lastRealTab
                appState.showingShortcuts = true
            } else {
                lastRealTab = newValue
            }
        }
        .sheet(isPresented: $appState.showingShortcuts) {
            AddShortcutsSheet()
        }
        .sheet(item: $appState.addFlow) { request in
            AddFlowView(request: request)
        }
        .sheet(isPresented: $appState.showingCheckIn) {
            if let profile = profiles.first {
                CoachingCheckInView(profile: profile)
            }
        }
        .task {
            guard !didSetUpDemo else { return }
            didSetUpDemo = true
            await DemoSupport.seedIfNeeded(modelContext)
            if let tab = DemoSupport.startTab {
                appState.selectedTab = tab
            }
            promptCheckInIfDue()
        }
        .fullScreenCover(isPresented: needsOnboarding) {
            OnboardingView()
        }
    }

    /// Opens the weekly check-in once per launch when it is due.
    private func promptCheckInIfDue() {
        guard !checkInPrompted, let profile = profiles.first,
              CoachingService.isCheckInDue(profile: profile) else { return }
        checkInPrompted = true
        appState.showingCheckIn = true
    }

    private var needsOnboarding: Binding<Bool> {
        Binding(
            get: { !(profiles.first?.hasCompletedOnboarding ?? false) },
            set: { _ in }
        )
    }
}

/// The white rounded "+" of the central tab (drawn once, rendered in original colors).
private enum RootTabPlusImage {
    static let image: UIImage = {
        let size = CGSize(width: 40, height: 40)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            UIColor(Theme.accent).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            let plus = UIBezierPath()
            plus.move(to: CGPoint(x: 20, y: 12)); plus.addLine(to: CGPoint(x: 20, y: 28))
            plus.move(to: CGPoint(x: 12, y: 20)); plus.addLine(to: CGPoint(x: 28, y: 20))
            plus.lineWidth = 3
            plus.lineCapStyle = .round
            UIColor(Theme.onAccent).setStroke()
            plus.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }()
}
