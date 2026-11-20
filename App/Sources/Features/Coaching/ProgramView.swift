import SwiftData
import SwiftUI

// CONTRACT (used by RootView):
//   ProgramView()                       the "Programme" tab root (owns its NavigationStack)
//   CoachingCheckInView(profile:)       weekly check-in sheet (presented when appState.showingCheckIn)

/// "Programme" tab. Initial version: current targets and check-in countdown.
struct ProgramView: View {
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            List {
                if let profile = profiles.first {
                    Text("Bilan dans \(CoachingService.daysUntilCheckIn(profile: profile)) jours")
                    Text(Formatters.kcal(profile.calorieTarget))
                    Button("Faire le bilan") { appState.showingCheckIn = true }
                }
            }
            .themedBackground()
            .navigationTitle("Programme")
        }
    }
}

/// Weekly check-in. Initial version: shows the proposal and applies it.
struct CoachingCheckInView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: CoachingSnapshot?

    var body: some View {
        NavigationStack {
            List {
                if let snapshot {
                    let proposal = CoachingService.proposal(snapshot: snapshot, profile: profile)
                    LabeledContent("Dépense", value: Formatters.kcal(snapshot.expenditure))
                    LabeledContent("Nouvel objectif", value: Formatters.kcal(proposal.calories))
                    Button("Appliquer") {
                        CoachingService.apply(proposal, snapshot: snapshot, profile: profile, context: modelContext)
                        dismiss()
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Bilan de la semaine")
            .task { snapshot = CoachingService.snapshot(profile: profile, context: modelContext) }
        }
    }
}
