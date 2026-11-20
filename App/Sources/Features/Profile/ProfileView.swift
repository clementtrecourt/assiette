import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// "Profil" tab: profile & goals, data export/import/reset, about.
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    ProfileSettingsForm(profile: profile)
                } else {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background.ignoresSafeArea())
                        .task { _ = UserProfile.current(in: modelContext) }
                }
            }
            .navigationTitle("Profil")
        }
    }
}

private struct ProfileSettingsForm: View {
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile

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
            summarySection
                .profileListRow()
            personalSection
                .profileListRow()
            programSection
                .profileListRow()
            foodsSection
                .profileListRow()
            dataSection
                .profileListRow()
            aboutSection
                .profileListRow()
        }
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

    private var foodsSection: some View {
        Section {
            NavigationLink {
                CustomFoodsListView(pickContext: nil)
            } label: {
                rowLabel("Mes aliments & recettes", systemImage: "takeoutbag.and.cup.and.straw")
            }
        }
    }

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

    private var aboutSection: some View {
        Section {
            NavigationLink {
                ProfileAboutView()
            } label: {
                LabeledContent {
                    Text(ProfileAboutView.appVersion)
                        .font(Theme.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                } label: {
                    rowLabel("À propos d'Assiette", systemImage: "info.circle")
                }
            }
        } footer: {
            AttributionFooter(includeOpenFoodFacts: true)
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
