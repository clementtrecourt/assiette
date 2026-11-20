import SwiftData
import SwiftUI

// CONTRACT (used by RootView): DashboardView() — the "Accueil" tab root (owns its NavigationStack).

/// "Accueil" tab. Initial version: the former progress dashboard.
struct DashboardView: View {
    var body: some View {
        ProgressDashboardView()
    }
}
