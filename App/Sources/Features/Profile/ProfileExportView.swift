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
                    Text("Tableur")
                } footer: {
                    Text(files.entryCount == 0
                         ? "Votre journal est vide."
                         : "\(ProfileBackup.plural(files.entryCount, "entrée", "entrées")), séparateur point-virgule, compatible Excel et Numbers. Colonnes : date, repas, aliment, marque, quantité, kcal, protéines, glucides, lipides, fibres.")
                }
                .listRowBackground(Theme.card)

                Section {
                    ShareLink(item: files.json) {
                        exportRow(title: "Sauvegarde complète (JSON)", detail: files.json.lastPathComponent,
                                  systemImage: "externaldrive")
                    }
                } header: {
                    Text("Sauvegarde")
                } footer: {
                    Text("Contenu : \(files.summary). Restaurez-la depuis Profil › Importer une sauvegarde, ou lors de la configuration initiale.")
                }
                .listRowBackground(Theme.card)
            } else if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.overTarget)
                    Button("Réessayer") { generate() }
                        .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.card)
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Préparation des fichiers…")
                        Spacer()
                    }
                    .padding(.vertical)
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedBackground()
        .navigationTitle("Exporter")
        .navigationBarTitleDisplayMode(.inline)
        .task { generate() }
        .refreshable { await generate() }
    }

    private func exportRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(Theme.accent)
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

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.accent)
                    Text("Assiette")
                        .font(.title2.bold())
                    Text("Version \(Self.appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Suivi nutritionnel personnel, hors ligne et sans compte.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Theme.card)

            Section("Base de données") {
                if database.isAvailable {
                    LabeledContent("Jeu de données", value: database.datasetVersion)
                    LabeledContent("Aliments", value: Formatters.number(Double(database.count), maxFractionDigits: 0))
                } else {
                    Label(database.openError ?? "Base d'aliments indisponible.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.fat)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Text("Les données nutritionnelles proviennent d'OpenNutrition, mises à disposition sous la licence Open Database License (ODbL) v1.0. Vous êtes libre de partager, modifier et utiliser cette base, à condition de citer la source, de partager à l'identique les bases dérivées et de les garder ouvertes.")
                    .font(.footnote)
                Text("Les produits récupérés en ligne par code-barres proviennent d'Open Food Facts (© contributeurs Open Food Facts), également sous licence ODbL ; les images et contenus éventuels sont sous licence CC BY-SA.")
                    .font(.footnote)
                Link(destination: URL(string: "https://www.opennutrition.app")!) {
                    Label("opennutrition.app", systemImage: "safari")
                }
                Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                    Label("openfoodfacts.org", systemImage: "safari")
                }
                Link(destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!) {
                    Label("Texte de la licence ODbL", systemImage: "doc.text")
                }
            } header: {
                Text("Sources & licences")
            }
            .listRowBackground(Theme.card)
            .tint(Theme.accent)

            Section {
                Text("Les objectifs sont des estimations (formule de Mifflin-St Jeor) et ne remplacent pas l'avis d'un professionnel de santé.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } header: {
                Text("Avertissement")
            }
            .listRowBackground(Theme.card)

            Section {
                AttributionFooter(includeOpenFoodFacts: true)
                    .listRowBackground(Color.clear)
            }
        }
        .themedBackground()
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
