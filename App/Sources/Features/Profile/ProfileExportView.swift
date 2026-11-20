import SwiftData
import SwiftUI

/// Pushed screen that writes the export files to the temp directory and offers them via ShareLink.
struct ProfileExportView: View {
    @Environment(\.modelContext) private var modelContext

    private struct Files {
        var csv: URL
        var json: URL
        var entryCount: Int
        var summary: String
    }

    @State private var files: Files?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let files {
                Section {
                    ShareLink(item: files.csv) {
                        exportRow(title: "Journal (CSV)", detail: files.csv.lastPathComponent,
                                  systemImage: "tablecells")
                    }
                    .disabled(files.entryCount == 0)
                } header: {
                    ProfileSectionHeader("Tableur")
                } footer: {
                    ProfileSectionFooter(files.entryCount == 0
                         ? "Votre journal est vide."
                         : "\(ProfileBackup.plural(files.entryCount, "entrée", "entrées")), séparateur point-virgule, compatible Excel et Numbers. Colonnes : date, repas, aliment, marque, quantité, kcal, protéines, glucides, lipides, fibres.")
                }
                .profileListRow()

                Section {
                    ShareLink(item: files.json) {
                        exportRow(title: "Sauvegarde complète (JSON)", detail: files.json.lastPathComponent,
                                  systemImage: "externaldrive")
                    }
                } header: {
                    ProfileSectionHeader("Sauvegarde")
                } footer: {
                    ProfileSectionFooter("Contenu : \(files.summary). Restaurez-la depuis Profil › Importer une sauvegarde, ou lors de la configuration initiale.")
                }
                .profileListRow()
            } else if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(Theme.body)
                        .foregroundStyle(Theme.overTarget)
                    Button("Réessayer") { generate() }
                        .font(Theme.font(15, .medium, relativeTo: .body))
                        .foregroundStyle(Theme.textPrimary)
                }
                .profileListRow()
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView {
                            Text("Préparation des fichiers…")
                                .font(Theme.callout)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .tint(Theme.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical)
                }
                .profileListRow()
            }
        }
        .listSectionSpacing(.compact)
        .themedBackground()
        .navigationTitle("Exporter")
        .navigationBarTitleDisplayMode(.inline)
        .task { generate() }
        .refreshable { generate() }
    }

    private func exportRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Theme.hairline))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 4)
    }

    private func generate() {
        do {
            let result = try ProfileBackupService.writeExportFiles(context: modelContext)
            files = Files(csv: result.csv, json: result.json, entryCount: result.entryCount,
                          summary: result.backup.contentSummary)
            errorMessage = nil
        } catch {
            files = nil
            errorMessage = "Impossible de préparer l'export : \(error.localizedDescription)"
        }
    }
}

/// About screen: version, dataset, licenses and links.
struct ProfileAboutView: View {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        if let build, build != version { return "\(version) (\(build))" }
        return version
    }

    private let database = FoodDatabase.shared
    @State private var showsFluentLicense = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 60, height: 60)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Assiette")
                        .font(Theme.title)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Version \(Self.appVersion)")
                        .font(Theme.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    Text("Suivi nutritionnel personnel, hors ligne et sans compte.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .profileListRow()

            Section {
                if database.isAvailable {
                    aboutValueRow("Jeu de données", database.datasetVersion)
                    aboutValueRow("Aliments", Formatters.number(Double(database.count), maxFractionDigits: 0))
                } else {
                    Label(database.openError ?? "Base d'aliments indisponible.",
                          systemImage: "exclamationmark.triangle")
                        .font(Theme.body)
                        .foregroundStyle(Theme.overTarget)
                }
            } header: {
                ProfileSectionHeader("Base de données")
            }
            .profileListRow()

            Section {
                Text("Les données nutritionnelles proviennent d'OpenNutrition, mises à disposition sous la licence Open Database License (ODbL) v1.0. Vous êtes libre de partager, modifier et utiliser cette base, à condition de citer la source, de partager à l'identique les bases dérivées et de les garder ouvertes.")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textBody)
                Text("Les produits récupérés en ligne par code-barres proviennent d'Open Food Facts (© contributeurs Open Food Facts), également sous licence ODbL ; les images et contenus éventuels sont sous licence CC BY-SA.")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textBody)
                Text("Les illustrations des aliments proviennent d'OpenNutrition et de Fluent Emoji (© Microsoft Corporation), sous licence MIT.")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textBody)
                Link(destination: URL(string: "https://www.opennutrition.app")!) {
                    Label("opennutrition.app", systemImage: "safari")
                }
                Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                    Label("openfoodfacts.org", systemImage: "safari")
                }
                Link(destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!) {
                    Label("Texte de la licence ODbL", systemImage: "doc.text")
                }
                Button {
                    showsFluentLicense = true
                } label: {
                    Label("Licence Fluent Emoji (MIT)", systemImage: "doc.text")
                }
            } header: {
                ProfileSectionHeader("Sources & licences")
            }
            .profileListRow()
            .font(Theme.body)
            .tint(Theme.textPrimary)

            Section {
                Text("Les objectifs sont des estimations (formule de Mifflin-St Jeor) et ne remplacent pas l'avis d'un professionnel de santé.")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textSecondary)
            } header: {
                ProfileSectionHeader("Avertissement")
            }
            .profileListRow()

            Section {
                AttributionFooter(includeOpenFoodFacts: true)
                    .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(.compact)
        .themedBackground()
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsFluentLicense) {
            ProfileAboutLicenseSheet(title: "Fluent Emoji",
                                     resource: "FluentEmoji-LICENSE",
                                     sourceURL: URL(string: "https://github.com/microsoft/fluentui-emoji"))
        }
    }

    private func aboutValueRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(Theme.callout)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        } label: {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
        }
    }
}

/// License text bundled as `<resource>.txt` (e.g. FluentEmoji-LICENSE.txt), shown from About.
private struct ProfileAboutLicenseSheet: View {
    let title: String
    let resource: String
    let sourceURL: URL?

    @Environment(\.dismiss) private var dismiss

    private var text: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Texte de la licence introuvable dans l'application."
        }
        return content
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textBody)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let sourceURL {
                        Link(destination: sourceURL) {
                            Label(sourceURL.host ?? sourceURL.absoluteString, systemImage: "safari")
                        }
                        .font(Theme.body)
                        .tint(Theme.textPrimary)
                    }
                }
                .padding(16)
            }
            .themedBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
