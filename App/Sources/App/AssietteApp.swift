import SwiftData
import SwiftUI

@main
struct AssietteApp: App {
    @State private var appState = AppState()

    /// Unit tests run inside the app: keep their launches on a throwaway in-memory store.
    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
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

/// Dark tab bar shared by every tab.
private extension View {
    func rootTabBarStyle() -> some View {
        toolbarBackground(Theme.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

/// Tabs: Journal · Progrès · Profil. Adding food goes through the Journal floating "+" button.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var didSetUpDemo = false

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            TodayView()
                .rootTabBarStyle()
                .tabItem { Label("Journal", systemImage: "book.closed") }
                .tag(AppTab.today)

            ProgressDashboardView()
                .rootTabBarStyle()
                .tabItem { Label("Progrès", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)

            ProfileView()
                .rootTabBarStyle()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.accent)
        .onChange(of: appState.selectedTab) { _, newValue in
            // The former "Ajouter" tab no longer exists: adding lives in the journal.
            if newValue == .add {
                appState.selectedTab = .today
            }
        }
        .task {
            guard !didSetUpDemo else { return }
            didSetUpDemo = true
            await DemoSupport.seedIfNeeded(modelContext)
            if let tab = DemoSupport.startTab {
                appState.selectedTab = tab
            }
        }
        .fullScreenCover(isPresented: needsOnboarding) {
            OnboardingView()
        }
    }

    private var needsOnboarding: Binding<Bool> {
        Binding(
            get: { !(profiles.first?.hasCompletedOnboarding ?? false) },
            set: { _ in }
        )
    }
}
