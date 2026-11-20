import SwiftUI

/// Top banner shown when CI has published a newer build. Tapping opens Feather, which
/// re-signs and installs it (Bibliothèque → Mettre à jour); the cross hides it for this build.
struct UpdateBanner: View {
    let update: UpdateChecker.Available
    var onUpdate: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onUpdate) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.calories)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nouvelle version \(update.version)")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Touchez pour l'installer avec Feather")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Masquer")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: Theme.hairline)
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}
