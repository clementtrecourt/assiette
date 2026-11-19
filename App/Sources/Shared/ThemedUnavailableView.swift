import SwiftUI

/// `ContentUnavailableView` in the app's typography and colors (DM Sans, textPrimary title,
/// textSecondary description). The system convenience inits (string / `.search`) render in SF.
struct ThemedUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text(description)
                .font(Theme.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Themed replacement for `ContentUnavailableView.search(text:)`.
    static func search(text: String) -> ThemedUnavailableView {
        ThemedUnavailableView(
            title: "Aucun résultat pour « \(text) »",
            systemImage: "magnifyingglass",
            description: "Vérifiez l'orthographe ou essayez une autre recherche."
        )
    }
}
