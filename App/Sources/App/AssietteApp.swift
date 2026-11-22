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
            _ = database.search("pomme", limit: 1)
            _ = database.count
        }
    }

    /// Tab bar: opaque app background, hairline on top, selected item textPrimary, others
    /// textTertiary, DM Sans labels. UIKit appearance so the unselected color applies too.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.raised)
        appearance.shadowColor = UIColor(Theme.tabBarLine)
        // No highlight behind the selected tab (the reference only changes the colors).
        appearance.selectionIndicatorTintColor = .clear
        appearance.selectionIndicatorImage = UIImage()

        let normal = UIColor(Theme.textTertiary)
        let selected = UIColor(Theme.textPrimary)
        var normalAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: normal]
        var selectedAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: selected]
        // Reference tab bar: 12 pt regular labels; the selected tab only turns white (its stems
        // measure the same ~1 pt as the idle ones).
        if let regular = UIFont(name: "DMSans-Regular", size: 12) {
            normalAttributes[.font] = regular
            selectedAttributes[.font] = regular
        }
        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ]
        for item in itemAppearances {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = normalAttributes
            item.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 1)
            item.selected.titlePositionAdjustment = item.normal.titlePositionAdjustment
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = selectedAttributes
        }
        // Reference: label centre 42 pt below the top hairline (icons are lowered by RootTabIcon).
        let stackedTitleOffset = UIOffset(horizontal: 0, vertical: 1.5)
        appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = stackedTitleOffset
        appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = stackedTitleOffset
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().selectionIndicatorImage = UIImage()
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
                .modifier(HealthSyncModifier())
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
    @State private var updates = UpdateChecker()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !appState.dashboardDetailShown { AddSearchBar() }
                }
                .tabItem { Label { Text("Accueil") } icon: { Image(uiImage: RootTabIcon.image(appState.selectedTab == .progress ? "Glyph-accueil-active" : "Glyph-accueil")) } }
                .tag(AppTab.progress)

            TodayView()
                .safeAreaInset(edge: .bottom, spacing: 0) { AddSearchBar() }
                .tabItem { Label { Text("Journal") } icon: { Image(uiImage: RootTabIcon.image(appState.selectedTab == .today ? "Glyph-journal-active" : "Glyph-journal")) } }
                .tag(AppTab.today)

            Color.clear
                .tabItem { Image(uiImage: RootTabPlusImage.image).renderingMode(.original) }
                .tag(AppTab.add)

            ProgramView()
                .safeAreaInset(edge: .bottom, spacing: 0) { AddSearchBar() }
                .tabItem { Label { Text("Programme") } icon: { Image(uiImage: RootTabIcon.image(appState.selectedTab == .program ? "Glyph-programme-active" : "Glyph-programme")) } }
                .tag(AppTab.program)

            ProfileView()
                .tabItem { Label { Text("Profil") } icon: { Image(uiImage: RootTabIcon.image(appState.selectedTab == .profile ? "Glyph-profil-active" : "Glyph-profil")) } }
                .tag(AppTab.profile)
        }
        .tint(Theme.textPrimary)
        // Reference tab bar is ~7 pt taller (top hairline 90 pt above the screen bottom; items
        // keep their place under it): raises the bar's top edge and the floating search bar.
        .background(RootTabBarExtraHeight(extra: 7))
        .safeAreaInset(edge: .top, spacing: 0) {
            if let update = updates.available {
                UpdateBanner(update: update, onUpdate: openFeather, onDismiss: {
                    withAnimation { updates.dismiss() }
                })
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: updates.available)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !DemoSupport.isDemo else { return }
            Task { await updates.checkIfStale() }
        }
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
        .slideCover(item: $appState.addFlow) { request in
            AddFlowView(request: request)
        }
        .slideCover(isPresented: $appState.showingCheckIn) {
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
            if DemoSupport.isDemo {
                if DemoSupport.arguments.contains("-updateBanner") { updates.showDemo() }
            } else {
                await updates.checkIfStale()
            }
        }
        .slideCover(isPresented: needsOnboarding) {
            OnboardingView()
        }
    }

    /// Feather holds the signing certificate and the source: it re-signs and installs the new
    /// build. Without Feather, fall back to the release page.
    private func openFeather() {
        openURL(UpdateChecker.featherURL) { accepted in
            if !accepted { openURL(UpdateChecker.releasePage) }
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

/// Tab glyphs lowered 4 pt (8 pt transparent band on top), to sit where the reference's icons do.
private enum RootTabIcon {
    private static var cache: [String: UIImage] = [:]

    static func image(_ name: String) -> UIImage {
        if let cached = cache[name] { return cached }
        guard let base = UIImage(named: name) else { return UIImage() }
        let top: CGFloat = 8
        let size = CGSize(width: base.size.width, height: base.size.height + top)
        let padded = UIGraphicsImageRenderer(size: size).image { _ in
            base.draw(in: CGRect(origin: CGPoint(x: 0, y: top), size: base.size))
        }.withRenderingMode(.alwaysTemplate)
        cache[name] = padded
        return padded
    }
}

/// Makes the UIKit tab bar under SwiftUI's TabView `extra` pt taller: an additional bottom safe
/// area on the UITabBarController grows the bar (its items stay in the top 49 pt) and the tabs'
/// content, hence the floating search bar inset, ends that much higher.
private struct RootTabBarExtraHeight: UIViewControllerRepresentable {
    let extra: CGFloat

    func makeUIViewController(context: Context) -> Controller {
        Controller(extra: extra)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.extra = extra
        controller.apply()
    }

    final class Controller: UIViewController {
        var extra: CGFloat
        private weak var tabController: UITabBarController?

        init(extra: CGFloat) {
            self.extra = extra
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        func apply() {
            if tabController == nil {
                tabController = tabBarController ?? view.window?.rootViewController.flatMap(Self.findTabController(in:))
            }
            guard let tabController, tabController.additionalSafeAreaInsets.bottom != extra else { return }
            tabController.additionalSafeAreaInsets.bottom = extra
        }

        private static func findTabController(in controller: UIViewController) -> UITabBarController? {
            if let tabs = controller as? UITabBarController { return tabs }
            for child in controller.children {
                if let found = findTabController(in: child) { return found }
            }
            return nil
        }
    }
}

/// The white rounded "+" of the central tab (drawn once, rendered in original colors).
private enum RootTabPlusImage {
    static let image: UIImage = {
        // Reference: 41 pt white disc, centre 26.5 pt below the top hairline, thin 2 pt plus,
        // 15 pt wide. 3 pt transparent band on top lowers the disc slightly.
        let disc: CGFloat = 43, top: CGFloat = 3
        let size = CGSize(width: disc, height: disc + top)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(x: 0, y: top, width: disc, height: disc).insetBy(dx: 1, dy: 1)
            UIColor(Theme.accent).setFill()
            UIBezierPath(ovalIn: rect).fill()
            let c = disc / 2, cy = top + disc / 2
            let plus = UIBezierPath()
            plus.move(to: CGPoint(x: c, y: cy - 7.5)); plus.addLine(to: CGPoint(x: c, y: cy + 7.5))
            plus.move(to: CGPoint(x: c - 7.5, y: cy)); plus.addLine(to: CGPoint(x: c + 7.5, y: cy))
            plus.lineWidth = 2
            plus.lineCapStyle = .round
            UIColor(Theme.onAccent).setStroke()
            plus.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }()
}
