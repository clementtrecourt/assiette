import SwiftData
import SwiftUI

@main
struct AssietteApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(\.locale, Formatters.locale)
        }
        .modelContainer(for: AppSchema.models)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            TodayView()
                .tabItem { Label("Journal", systemImage: "book.closed") }
                .tag(AppTab.today)

            NavigationStack {
                FoodSearchView(context: appState.addTabContext, isSheet: false)
            }
            .tabItem { Label("Ajouter", systemImage: "plus.circle") }
            .tag(AppTab.add)

            ProgressDashboardView()
                .tabItem { Label("Progrès", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
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
