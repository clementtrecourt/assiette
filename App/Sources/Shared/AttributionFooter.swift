import SwiftUI

/// ODbL attribution required by the OpenNutrition license on every screen that displays
/// dataset data. Put it at the bottom of lists / detail screens showing OpenNutrition foods.
struct AttributionFooter: View {
    /// Also credit Open Food Facts (for products fetched from OFF).
    var includeOpenFoodFacts = false

    var body: some View {
        VStack(spacing: 3) {
            Link(destination: URL(string: "https://www.opennutrition.app")!) {
                Text("Données : OpenNutrition (ODbL)")
            }
            if includeOpenFoodFacts {
                Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                    Text("© Open Food Facts contributors (ODbL)")
                }
            }
        }
        .font(Theme.font(11, .regular, relativeTo: .caption2))
        .foregroundStyle(Theme.textTertiary)
        .tint(Theme.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
