import SwiftData
import SwiftUI

// CONTRACT (used by RootView, the journal and the dashboard) — keep these signatures:
//   AddFlowView(request: AddFlowRequest)   the add sheet (modes Scanner / Rechercher / Rapide / Recettes)
//   AddShortcutsSheet()                     the "+" tab sheet
//   AddSearchBar()                          floating "Rechercher un aliment" bar above the tab bar
// Open the flow with `appState.presentAdd(.search, context: ...)`.

/// The add sheet. Initial version: routes each mode to the existing screens.
struct AddFlowView: View {
    let request: AddFlowRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch request.mode {
        case .search:
            NavigationStack { FoodSearchView(context: request.context, isSheet: true) }
        case .scan:
            BarcodeScanView(context: request.context, onLogged: { dismiss() })
        case .quick:
            QuickAddSheet(context: request.context, onLogged: { dismiss() })
        case .recipes:
            NavigationStack { CustomFoodsListView(pickContext: request.context, onLogged: { dismiss() }) }
        }
    }
}

/// Sheet of the central "+" tab: the ways to add food, then weight and water.
struct AddShortcutsSheet: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                ForEach(AddMode.allCases) { mode in
                    Button(mode.rawValue) { appState.presentAdd(mode) }
                }
            }
        }
        .padding()
        .presentationDetents([.height(320)])
    }
}

/// Floating search bar shown above the tab bar on the main tabs.
struct AddSearchBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.presentAdd(.search)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                Text("Rechercher un aliment")
                Spacer()
                Image(systemName: "barcode.viewfinder")
            }
            .font(Theme.callout)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
