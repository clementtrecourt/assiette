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

    private static let currentYear = Calendar.current.component(.year, from: .now)
    private static let years: [Int] = Array((currentYear - 100)...(currentYear - 10)).reversed()
    private static let baseRates: [Double] = [0.25, 0.5, 0.75, 1.0]

    private var computed: GoalCalculator.Targets { GoalCalculator.targets(for: profile) }

    /// Binding that recomputes the targets after each change.
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<UserProfile, T>) -> Binding<T> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { newValue in
                profile[keyPath: keyPath] = newValue
                GoalCalculator.apply(to: profile)
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
            goalSection
                .profileListRow()
            targetsSection
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
            Text("Journal, pesées, eau, aliments personnels, favoris et profil seront supprimés définitivement. Pensez à exporter une sauvegarde avant.")
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
            ProfileSectionFooter("\(profile.activity.detail). Enregistrez vos pesées dans l'onglet Progrès pour suivre votre évolution.")
        }
    }

    private var yearOptions: [Int] {
        Self.years.contains(profile.birthYear) ? Self.years : ([profile.birthYear] + Self.years).sorted(by: >)
    }

    private var rateOptions: [Double] {
        Self.baseRates.contains(profile.weeklyRateKg)
            ? Self.baseRates : (Self.baseRates + [profile.weeklyRateKg]).sorted()
    }

    private var goalSection: some View {
        Section {
            Picker("Objectif", selection: binding(\.goal)) {
                ForEach(WeightGoal.allCases) { Text($0.label).tag($0) }
            }
            if profile.goal != .maintain {
                Picker("Rythme", selection: binding(\.weeklyRateKg)) {
                    ForEach(rateOptions, id: \.self) { rate in
                        Text("\(Formatters.number(rate, maxFractionDigits: 2)) kg / semaine").tag(rate)
                    }
                }
                ProfileNumberField("Poids cible", value: plain(\.targetWeightKg), unit: "kg",
                                   maxFractionDigits: 1, placeholder: "Facultatif")
            }
        } header: {
            ProfileSectionHeader("Objectif")
        } footer: {
            if let text = goalFooter { ProfileSectionFooter(text) }
        }
    }

    private var goalFooter: String? {
        guard profile.goal != .maintain else { return nil }
        let delta = profile.weeklyRateKg * GoalCalculator.kcalPerKg / 7
        var text = "\(profile.goal == .lose ? "Déficit" : "Surplus") d'environ \(Formatters.kcal(delta)) par jour."
        if let target = profile.targetWeightKg, profile.weeklyRateKg > 0 {
            let diff = profile.goal == .lose ? profile.weightKg - target : target - profile.weightKg
            if diff > 0 {
                let weeks = Int((diff / profile.weeklyRateKg).rounded(.up))
                text += " Poids cible atteint dans environ \(weeks) semaine\(weeks > 1 ? "s" : "")."
            } else {
                text += " Poids cible déjà atteint."
            }
        }
        return text
    }

    private var targetsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { profile.manualTargets },
                set: { manual in
                    withAnimation {
                        profile.manualTargets = manual
                        if !manual { GoalCalculator.apply(to: profile) }
                    }
                }
            )) {
                Text("Objectifs personnalisés")
                    .foregroundStyle(Theme.textBody)
            }
            .tint(Theme.textSecondary)

            if profile.manualTargets {
                ProfileNumberField("Calories", value: plain(\.calorieTarget), unit: "kcal", maxFractionDigits: 0)
                ProfileNumberField("Protéines", value: plain(\.proteinTarget), unit: "g", maxFractionDigits: 0)
                ProfileNumberField("Glucides", value: plain(\.carbsTarget), unit: "g", maxFractionDigits: 0)
                ProfileNumberField("Lipides", value: plain(\.fatTarget), unit: "g", maxFractionDigits: 0)
                Button {
                    let t = computed
                    profile.calorieTarget = t.calories
                    profile.proteinTarget = t.protein
                    profile.carbsTarget = t.carbs
                    profile.fatTarget = t.fat
                    successTrigger += 1
                } label: {
                    Label("Reprendre les valeurs calculées", systemImage: "arrow.counterclockwise")
                        .font(Theme.font(15, .medium, relativeTo: .body))
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                ProfileTargetRow(title: "Calories", value: Formatters.kcal(profile.calorieTarget),
                                 color: Theme.calories)
                ProfileTargetRow(title: NutrientKey.protein.label, value: grams(profile.proteinTarget),
                                 color: Theme.protein)
                ProfileTargetRow(title: NutrientKey.carbohydrates.label, value: grams(profile.carbsTarget),
                                 color: Theme.carbs)
                ProfileTargetRow(title: NutrientKey.totalFat.label, value: grams(profile.fatTarget),
                                 color: Theme.fat)
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

    private var targetsFooter: String {
        let t = computed
        var text = "Métabolisme de base : \(Formatters.kcal(t.bmr)). Dépense estimée : \(Formatters.kcal(t.tdee)) (formule de Mifflin-St Jeor)."
        if profile.manualTargets {
            let macroKcal = profile.proteinTarget * 4 + profile.carbsTarget * 4 + profile.fatTarget * 9
            if abs(macroKcal - profile.calorieTarget) > 50 {
                text += " Vos macros totalisent \(Formatters.kcal(macroKcal))."
            }
        } else {
            text += " Recalculés automatiquement quand votre profil change."
        }
        return text
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
