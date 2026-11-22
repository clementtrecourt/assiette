import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Profil" tab: header (avatar, member since) and two groups of rows (Général, Réglages des
/// fonctions) opening the settings pages. Layout measured on the reference "More" screen.
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    ProfileHome(profile: profile)
                        .navigationDestination(for: ProfilePage.self) { page in
                            Group {
                                switch page {
                                case .foods:
                                    CustomFoodsListView(pickContext: nil)
                                case .about:
                                    ProfileAboutView()
                                case .dashboard, .journal:
                                    ProfileFeatureSettingsView(page: page)
                                default:
                                    ProfileSettingsForm(profile: profile, page: page)
                                }
                            }
                            .toolbar(.visible, for: .navigationBar)
                        }
                } else {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background.ignoresSafeArea())
                        .task { _ = UserProfile.current(in: modelContext) }
                }
            }
            .navigationTitle("Profil")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Settings pages of the Profil tab.
enum ProfilePage: Hashable {
    case account, dashboard, journal, program, foods, data, about

    var title: String {
        switch self {
        case .account: "Compte"
        case .dashboard: "Accueil"
        case .journal: "Journal"
        case .program: "Programme"
        case .foods: "Aliments et recettes"
        case .data: "Données"
        case .about: "À propos"
        }
    }
}

/// Profil root: raised header (PROFIL, avatar with initials, member since), then grouped rows.
private struct ProfileHome: View {
    let profile: UserProfile
    @AppStorage(ProfileSettingsForm.nameKey) private var displayName = ""
    @Environment(\.openURL) private var openURL

    private var initials: String {
        let words = displayName.split(separator: " ").prefix(2)
        if words.count >= 2 { return words.compactMap(\.first).map(String.init).joined().uppercased() }
        return String(displayName.prefix(2)).uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.bottom, 17)
                    // Full-bleed raised band (content keeps the 16 pt inset).
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.raised)
                ProfileGroupTitle("Général")
                ProfileGroup {
                    ProfileNavRow(title: "Compte", systemImage: "person.crop.circle", value: .account)
                    ProfileGroupDivider()
                    // Apple Santé import lives on the Données page.
                    ProfileNavRow(title: "Intégrations", systemImage: "arrow.triangle.2.circlepath", value: .data)
                    ProfileGroupDivider()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        ProfileRowLabel(title: "Langue", systemImage: "globe", accessory: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre les réglages iOS de l'app")
                }
                ProfileGroupTitle("Réglages des fonctions")
                ProfileGroup {
                    ProfileNavRow(title: "Accueil", systemImage: "square.grid.2x2.fill", value: .dashboard)
                    ProfileGroupDivider()
                    ProfileNavRow(title: "Journal", systemImage: "fork.knife", value: .journal)
                    ProfileGroupDivider()
                    ProfileNavRow(title: "Programme", systemImage: "circle.grid.3x3.circle", value: .program)
                    ProfileGroupDivider()
                    ProfileNavRow(title: "Aliments et recettes", systemImage: "takeoutbag.and.cup.and.straw.fill",
                                  value: .foods)
                    ProfileGroupDivider()
                    ProfileNavRow(title: "Données", systemImage: "externaldrive.fill", value: .data)
                    ProfileGroupDivider()
                    ProfileNavRow(title: "À propos", systemImage: "info.circle.fill", value: .about)
                }
                AttributionFooter(includeOpenFoodFacts: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            // Status bar strip in the header color (ShapeStyle backgrounds fill the safe area).
            Color.clear.frame(height: 0).background(Theme.raised)
        }
    }

    private var header: some View {
        // Measured on the reference "More" header: title, avatar 18 pt below, 17 pt bottom margin.
        VStack(alignment: .leading, spacing: 18) {
            Text("PROFIL")
                .font(Theme.screenTitle())
                .foregroundStyle(Theme.textPrimary)
                .frame(height: 34)
                // Reference: the title sits ~4 pt higher than the 18 pt avatar gap implies.
                .offset(y: -4)
                .accessibilityAddTraits(.isHeader)
            NavigationLink(value: ProfilePage.account) {
                HStack(spacing: 24) {
                    Group {
                        if initials.isEmpty {
                            Image(systemName: "person.fill")
                                .font(.system(size: 30, weight: .semibold))
                        } else {
                            Text(initials)
                                .font(Theme.screenTitle(26))
                        }
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 66, height: 66)
                    .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName.isEmpty ? "\(profile.sex.label), \(profile.age) ans" : displayName)
                            .font(Theme.font(18, .regular, relativeTo: .title3))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("Membre depuis le \(profile.createdAt.formatted(.dateTime.day().month(.wide).year()))")
                            .font(Theme.font(16, .regular, relativeTo: .callout))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct ProfileGroupTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(Theme.font(20, .bold, relativeTo: .title2))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rounded raised group of rows (radius 12, 16 pt side margins).
struct ProfileGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
    }
}

/// Separator starting under the row labels.
struct ProfileGroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.raised2)
            .frame(height: 1)
            .padding(.leading, 66)
    }
}

/// Row: 24 pt white icon, 17 pt label, trailing chevron (or external-link icon), 66 pt high.
struct ProfileRowLabel: View {
    let title: String
    let systemImage: String
    var accessory = "chevron.right"

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 66)
            Text(title)
                .font(Theme.font(17, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Image(systemName: accessory)
                .font(.system(size: accessory == "chevron.right" ? 15 : 18, weight: .semibold))
                // Reference: dim (~40 % white) accessory, 28 pt from the card edge.
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.trailing, 28)
        }
        .frame(minHeight: 66)
        .contentShape(Rectangle())
    }
}

struct ProfileNavRow: View {
    let title: String
    let systemImage: String
    let value: ProfilePage

    var body: some View {
        NavigationLink(value: value) {
            ProfileRowLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileSettingsForm: View {
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile
    let page: ProfilePage

    static let nameKey = "profile.displayName"
    @AppStorage(nameKey) private var displayName = ""

    @State private var showImporter = false
    @State private var pendingBackup: ProfileBackup?
    @State private var showImportChoice = false
    @State private var showEraseConfirm = false
    @State private var alertTitle = ""
    @State private var alertMessage: String?
    @State private var successTrigger = 0
    @State private var warningTrigger = 0

    @AppStorage(CoachingSettings.collaborativeKey) private var collaborative = false

    private static let currentYear = Calendar.current.component(.year, from: .now)
    private static let years: [Int] = Array((currentYear - 100)...(currentYear - 10)).reversed()

    /// Binding for personal info. Until the first weekly check-in the starting expenditure still
    /// comes from the formula (`initialExpenditure == nil`), so the coach refreshes the targets;
    /// afterwards the adaptive estimate no longer depends on these fields.
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<UserProfile, T>) -> Binding<T> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { newValue in
                profile[keyPath: keyPath] = newValue
                if profile.initialExpenditure == nil {
                    CoachingService.refreshTargets(profile: profile, context: modelContext)
                }
            }
        )
    }

    /// Plain binding (no recompute), for manual targets.
    private func plain<T>(_ keyPath: ReferenceWritableKeyPath<UserProfile, T>) -> Binding<T> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { profile[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        Form {
            switch page {
            case .account:
                summarySection
                    .profileListRow()
                nameSection
                    .profileListRow()
                personalSection
                    .profileListRow()
            case .program:
                programSection
                    .profileListRow()
            case .data:
                dataSection
                    .profileListRow()
            case .foods, .about, .dashboard, .journal:
                EmptyView()
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .font(Theme.body)
        .listSectionSpacing(.compact)
        .themedBackground()
        .tint(Theme.accent)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { ProfileKeyboard.dismiss() }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .confirmationDialog("Importer la sauvegarde", isPresented: $showImportChoice,
                            titleVisibility: .visible, presenting: pendingBackup) { backup in
            Button("Fusionner avec mes données") { runImport(backup, mode: .merge) }
            Button("Remplacer toutes mes données", role: .destructive) { runImport(backup, mode: .replace) }
            Button("Annuler", role: .cancel) { pendingBackup = nil }
        } message: { backup in
            Text("Contenu : \(backup.contentSummary).\n\nFusionner ajoute les éléments absents et conserve votre profil. Remplacer efface vos données actuelles.")
        }
        .confirmationDialog("Effacer toutes les données ?", isPresented: $showEraseConfirm,
                            titleVisibility: .visible) {
            Button("Tout effacer", role: .destructive) { eraseAll() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Journal, pesées, eau, aliments personnels, favoris, historique du programme et profil seront supprimés définitivement. Pensez à exporter une sauvegarde avant.")
        }
        .alert(alertTitle, isPresented: Binding(get: { alertMessage != nil },
                                                set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: successTrigger)
        .sensoryFeedback(.warning, trigger: warningTrigger)
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 52, height: 52)
                    .background(Theme.raised, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(profile.sex.label), \(profile.age) ans")
                        .font(Theme.title)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Formatters.number(profile.heightCm, maxFractionDigits: 0)) cm · \(Formatters.number(profile.weightKg, maxFractionDigits: 1)) kg · IMC \(Formatters.number(bmi, maxFractionDigits: 1))")
                        .font(Theme.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(profile.goal.label) · \(Formatters.kcal(profile.calorieTarget)) / jour")
                        .font(Theme.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var bmi: Double {
        let m = profile.heightCm / 100
        return m > 0 ? profile.weightKg / (m * m) : 0
    }

    private var nameSection: some View {
        Section {
            TextField("Prénom ou pseudo", text: $displayName)
                .textContentType(.givenName)
                .submitLabel(.done)
                .foregroundStyle(Theme.textPrimary)
        } header: {
            ProfileSectionHeader("Nom affiché")
        }
    }

    private var personalSection: some View {
        Section {
            Picker("Sexe", selection: binding(\.sex)) {
                ForEach(Sex.allCases) { Text($0.label).tag($0) }
            }
            Picker("Année de naissance", selection: binding(\.birthYear)) {
                ForEach(yearOptions, id: \.self) { Text(String($0)).tag($0) }
            }
            ProfileNumberField("Taille", value: binding(\.heightCm), unit: "cm", maxFractionDigits: 0)
            ProfileNumberField("Poids", value: binding(\.weightKg), unit: "kg", maxFractionDigits: 1)
            Picker("Activité", selection: binding(\.activity)) {
                ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            ProfileSectionHeader("Mes informations")
        } footer: {
            ProfileSectionFooter("\(profile.activity.detail). Enregistrez vos pesées avec le bouton + pour suivre votre évolution.")
        }
    }

    private var yearOptions: [Int] {
        Self.years.contains(profile.birthYear) ? Self.years : ([profile.birthYear] + Self.years).sorted(by: >)
    }

    private var mode: CoachingMode { CoachingMode.current(profile: profile, collaborative: collaborative) }

    private var programSummary: String {
        var parts = [CoachingFormat.goalShort(profile.goal)]
        if profile.goal != .maintain {
            parts.append("\(Formatters.number(profile.effectiveRatePercent, maxFractionDigits: 2)) %/sem.")
        }
        parts.append(mode.adjective)
        return parts.joined(separator: " · ")
    }

    /// Goal & program live in the Programme tab; here a shortcut to the editor, the current
    /// targets (read-only) and the fiber / water preferences.
    private var programSection: some View {
        Section {
            NavigationLink {
                CoachingGoalEditor(profile: profile, initialFocus: .target, isSheet: false)
            } label: {
                LabeledContent {
                    Text(programSummary)
                        .font(Theme.callout)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                } label: {
                    rowLabel("Objectif et programme", systemImage: "target")
                }
            }

            ProfileTargetRow(title: "Calories", value: Formatters.kcal(profile.calorieTarget),
                             color: Theme.calories)
            ForEach(Theme.macroOrder, id: \.self) { key in
                ProfileTargetRow(title: key.label, value: grams(macroTarget(key)), color: Theme.color(for: key))
            }

            ProfileMacroSplitView(protein: profile.proteinTarget, carbs: profile.carbsTarget, fat: profile.fatTarget)

            ProfileNumberField("Fibres", value: plain(\.fiberTarget), unit: "g", maxFractionDigits: 0)
            ProfileNumberField("Eau", value: plain(\.waterTargetMl), unit: "ml", maxFractionDigits: 0)
        } header: {
            ProfileSectionHeader("Objectifs quotidiens")
        } footer: {
            ProfileSectionFooter(targetsFooter)
        }
    }

    private func macroTarget(_ key: NutrientKey) -> Double {
        switch key {
        case .carbohydrates: return profile.carbsTarget
        case .protein: return profile.proteinTarget
        default: return profile.fatTarget
        }
    }

    private var targetsFooter: String {
        switch mode {
        case .manual:
            return "Objectifs manuels : ils ne changent pas automatiquement. Modifiez-les dans Objectif et programme."
        case .coached, .collaborative:
            let next = CoachingFormat.weekdayDay(CoachingService.nextCheckInDate(profile: profile))
            var text = "Mis à jour par le bilan hebdomadaire (prochain : \(next))."
            if profile.initialExpenditure == nil {
                let t = GoalCalculator.targets(for: profile)
                text += " Dépense de départ : \(Formatters.kcal(t.tdee)) (formule de Mifflin-St Jeor), affinée ensuite avec vos repas et vos pesées."
            }
            return text
        }
    }

    private func grams(_ v: Double) -> String { "\(Formatters.number(v, maxFractionDigits: 0)) g" }

    private var dataSection: some View {
        Section {
            NavigationLink {
                ProfileExportView()
            } label: {
                rowLabel("Exporter mes données", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                rowLabel("Importer une sauvegarde", systemImage: "square.and.arrow.down")
            }
            NavigationLink {
                HealthImportSettings()
            } label: {
                rowLabel("Apple Santé", systemImage: "heart")
            }
            Button(role: .destructive) {
                warningTrigger += 1
                showEraseConfirm = true
            } label: {
                rowLabel("Effacer toutes les données", systemImage: "trash", color: Theme.overTarget)
            }
        } header: {
            ProfileSectionHeader("Données")
        } footer: {
            ProfileSectionFooter("Vos données sont stockées uniquement sur cet appareil.")
        }
    }

    /// Settings row label: monochrome icon in a fixed column + body text.
    private func rowLabel(_ title: String, systemImage: String, color: Color? = nil) -> some View {
        Label {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(color ?? Theme.textBody)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(color ?? Theme.textSecondary)
        }
    }

    // MARK: - Actions

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let backup = try ProfileBackupService.readBackup(at: url)
                if backup.isEmpty {
                    alertTitle = "Sauvegarde vide"
                    alertMessage = "Ce fichier ne contient aucune donnée à importer."
                    return
                }
                pendingBackup = backup
                // Let the document picker finish dismissing before presenting the dialog.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showImportChoice = true
                }
            } catch {
                alertTitle = "Import impossible"
                alertMessage = error.localizedDescription
            }
        case .failure(let error):
            alertTitle = "Import impossible"
            alertMessage = error.localizedDescription
        }
    }

    private func runImport(_ backup: ProfileBackup, mode: ProfileImportMode) {
        pendingBackup = nil
        do {
            let result = try ProfileBackupService.importBackup(backup, mode: mode, context: modelContext)
            successTrigger += 1
            alertTitle = "Import terminé"
            alertMessage = result.summary
        } catch {
            alertTitle = "Import impossible"
            alertMessage = error.localizedDescription
        }
    }

    private func eraseAll() {
        do {
            try ProfileBackupService.eraseEverything(context: modelContext)
            successTrigger += 1
        } catch {
            alertTitle = "Erreur"
            alertMessage = error.localizedDescription
        }
    }
}

/// "Accueil" / "Journal" feature settings: the display toggles those screens already store
/// (same `@AppStorage` keys, so changes show up there immediately).
private struct ProfileFeatureSettingsView: View {
    let page: ProfilePage

    @AppStorage("dashboard.showRemaining") private var dashboardShowsRemaining = true
    @AppStorage("dashboard.balanceExpenditure") private var balanceAgainstExpenditure = true
    @AppStorage("today.headerShowsConsumed") private var journalShowsConsumed = false
    @AppStorage("today.hideFoodDetails") private var hideFoodDetails = false
    @AppStorage("today.hideEmptyHours") private var hideEmptyHours = false

    var body: some View {
        Form {
            switch page {
            case .dashboard:
                Section {
                    Toggle("Afficher le restant", isOn: $dashboardShowsRemaining)
                    Toggle("Comparer à la dépense", isOn: $balanceAgainstExpenditure)
                } header: {
                    ProfileSectionHeader("Affichage")
                } footer: {
                    ProfileSectionFooter("Le restant montre ce qu'il reste à manger plutôt que ce qui a été mangé. Le bilan énergétique est comparé à votre dépense estimée, ou sinon à votre objectif.")
                }
                .profileListRow()
            default:
                Section {
                    Toggle("Afficher le consommé", isOn: $journalShowsConsumed)
                    Toggle("Masquer les détails", isOn: $hideFoodDetails)
                    Toggle("Masquer les heures vides", isOn: $hideEmptyHours)
                } header: {
                    ProfileSectionHeader("Affichage")
                } footer: {
                    ProfileSectionFooter("Le bandeau du journal montre le consommé plutôt que le restant. Masquer les détails n'affiche que le nom des aliments.")
                }
                .profileListRow()
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.good)
        .listSectionSpacing(.compact)
        .themedBackground()
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
