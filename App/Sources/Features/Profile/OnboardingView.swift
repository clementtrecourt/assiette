import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// First-launch setup, presented full screen until `UserProfile.hasCompletedOnboarding`.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    private enum Step: Int, CaseIterable {
        case welcome, sex, birthYear, height, weight, activity, goal, summary
    }

    @State private var step: Step = .welcome
    @State private var forward = true

    @State private var sex: Sex = .male
    @State private var birthYear: Int = 1995
    @State private var heightCm: Int = 175
    @State private var weightWhole: Int = 75
    @State private var weightTenth: Int = 0
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: WeightGoal = .maintain
    @State private var weeklyRateKg: Double = 0.5
    @State private var hasTargetWeight = false
    @State private var targetWeightKg: Double = 70

    @State private var customizeTargets = false
    @State private var calories: Double = 2000
    @State private var protein: Double = 120
    @State private var carbs: Double = 220
    @State private var fat: Double = 70
    @State private var fiber: Double = 30
    @State private var waterMl: Double = 2000

    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var finishTrigger = 0
    @State private var selectionTrigger = 0

    private static let currentYear = Calendar.current.component(.year, from: .now)
    private static let years: [Int] = Array((currentYear - 100)...(currentYear - 10)).reversed()
    private static let rates: [Double] = [0.25, 0.5, 0.75, 1.0]

    private var weightKg: Double { Double(weightWhole) + Double(weightTenth) / 10 }
    private var age: Int { max(0, Self.currentYear - birthYear) }

    private var computed: GoalCalculator.Targets {
        GoalCalculator.targets(sex: sex, weightKg: weightKg, heightCm: Double(heightCm), age: age,
                               activity: activity, goal: goal, weeklyRateKg: weeklyRateKg)
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
            }
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .sensoryFeedback(.selection, trigger: selectionTrigger)
        .sensoryFeedback(.success, trigger: finishTrigger)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            restore(result)
        }
        .alert("Erreur", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                go(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Retour")
            ProgressBar(value: Double(step.rawValue), total: Double(Step.allCases.count - 1),
                        color: Theme.accent, height: 4)
            Text("\(step.rawValue)/\(Step.allCases.count - 1)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityLabel("Étape \(step.rawValue) sur \(Step.allCases.count - 1)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                advance()
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(ProfilePrimaryButtonStyle())

            if step == .welcome {
                Button("Restaurer une sauvegarde") { showImporter = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Commencer"
        case .summary: return "Terminer"
        default: return "Continuer"
        }
    }

    private func go(to newStep: Step) {
        forward = newStep.rawValue > step.rawValue
        if newStep == .summary { refreshComputedTargets() }
        withAnimation(.snappy) { step = newStep }
    }

    private func advance() {
        ProfileKeyboard.dismiss()
        if step == .summary {
            finish()
        } else if let next = Step(rawValue: step.rawValue + 1) {
            go(to: next)
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .sex: sexStep
        case .birthYear: birthYearStep
        case .height: heightStep
        case .weight: weightStep
        case .activity: activityStep
        case .goal: goalStep
        case .summary: summaryStep
        }
    }

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 48)
                VStack(spacing: 8) {
                    Text("Bienvenue dans Assiette")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Suivez vos repas, vos calories et vos macronutriments, simplement et en privé.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 16) {
                    featureRow("magnifyingglass", "Plus de 300 000 aliments",
                               "Base de données ouverte OpenNutrition, disponible hors ligne.")
                    featureRow("barcode.viewfinder", "Scan de code-barres",
                               "Retrouvez un produit en un instant.")
                    featureRow("lock.shield", "Vos données restent sur l'appareil",
                               "Aucun compte, aucun serveur. Exportez quand vous voulez.")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                Text("Quelques questions pour calculer vos objectifs quotidiens.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
    }

    private func featureRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func stepTitle(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }

    private var sexStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepTitle("Vous êtes…", "Utilisé pour estimer votre métabolisme de base.")
                VStack(spacing: 12) {
                    ForEach(Sex.allCases) { option in
                        OnboardingChoiceRow(title: option.label, detail: nil,
                                            systemImage: "person.fill",
                                            isSelected: sex == option) {
                            sex = option
                            selectionTrigger += 1
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var birthYearStep: some View {
        VStack(spacing: 16) {
            stepTitle("Votre année de naissance", "\(age) ans")
            Picker("Année de naissance", selection: $birthYear) {
                ForEach(Self.years, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var heightStep: some View {
        VStack(spacing: 16) {
            stepTitle("Votre taille")
            Text("\(heightCm) cm")
                .font(.system(size: 48, weight: .bold, design: .default))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Picker("Taille", selection: $heightCm) {
                ForEach(120...220, id: \.self) { cm in
                    Text("\(cm) cm").tag(cm)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var weightStep: some View {
        VStack(spacing: 16) {
            stepTitle("Votre poids actuel", "Il sera enregistré comme première pesée.")
            Text("\(Formatters.number(weightKg, maxFractionDigits: 1)) kg")
                .font(.system(size: 48, weight: .bold, design: .default))
                .foregroundStyle(Theme.weight)
                .monospacedDigit()
            HStack(spacing: 0) {
                Picker("Kilogrammes", selection: $weightWhole) {
                    ForEach(30...250, id: \.self) { kg in
                        Text(String(kg)).tag(kg)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: 120)
                .clipped()
                Text(",").font(.title2.bold())
                Picker("Décimale", selection: $weightTenth) {
                    ForEach(0...9, id: \.self) { d in
                        Text(String(d)).tag(d)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: 80)
                .clipped()
                Text("kg").font(.title3).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var activityStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepTitle("Votre niveau d'activité", "En dehors du sport ponctuel, sur une semaine typique.")
                VStack(spacing: 12) {
                    ForEach(ActivityLevel.allCases) { option in
                        OnboardingChoiceRow(title: option.label, detail: option.detail,
                                            systemImage: activitySymbol(option),
                                            isSelected: activity == option) {
                            activity = option
                            selectionTrigger += 1
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 16)
        }
    }

    private func activitySymbol(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: return "chair.lounge"
        case .light: return "figure.walk"
        case .moderate: return "figure.run"
        case .active: return "figure.strengthtraining.traditional"
        case .veryActive: return "flame"
        }
    }

    private func goalSymbol(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose: return "arrow.down.right"
        case .maintain: return "equal"
        case .gain: return "arrow.up.right"
        }
    }

    private var goalStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                stepTitle("Votre objectif")
                VStack(spacing: 12) {
                    ForEach(WeightGoal.allCases) { option in
                        OnboardingChoiceRow(title: option.label, detail: nil,
                                            systemImage: goalSymbol(option),
                                            isSelected: goal == option) {
                            withAnimation(.snappy) { goal = option }
                            selectionTrigger += 1
                        }
                    }
                }
                .padding(.horizontal, 24)

                if goal != .maintain {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(goal == .lose ? "Perte par semaine" : "Prise par semaine")
                                .font(.headline)
                            Picker("Rythme", selection: $weeklyRateKg) {
                                ForEach(Self.rates, id: \.self) { rate in
                                    Text("\(Formatters.number(rate, maxFractionDigits: 2)) kg").tag(rate)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(rateHint)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Divider()
                        Toggle("Définir un poids cible", isOn: $hasTargetWeight.animation())
                            .font(.headline)
                        if hasTargetWeight {
                            Stepper(value: $targetWeightKg, in: 30...250, step: 0.5) {
                                Text("\(Formatters.number(targetWeightKg, maxFractionDigits: 1)) kg")
                                    .font(.title3.monospacedDigit())
                            }
                            if let weeks = weeksToTarget {
                                Text("Environ \(weeks) semaines à ce rythme.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding()
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 16)
        }
        .onChange(of: goal) {
            // Propose a sensible target weight in the chosen direction.
            if goal == .lose { targetWeightKg = max(30, (weightKg - 5).rounded()) }
            if goal == .gain { targetWeightKg = min(250, (weightKg + 5).rounded()) }
        }
    }

    private var rateHint: String {
        let delta = weeklyRateKg * GoalCalculator.kcalPerKg / 7
        let sign = goal == .lose ? "−" : "+"
        return "Environ \(sign)\(Formatters.kcal(delta)) par jour. Un rythme de 0,5 kg/semaine est recommandé."
    }

    private var weeksToTarget: Int? {
        guard hasTargetWeight, weeklyRateKg > 0 else { return nil }
        let diff = goal == .lose ? weightKg - targetWeightKg : targetWeightKg - weightKg
        guard diff > 0 else { return nil }
        return Int((diff / weeklyRateKg).rounded(.up))
    }

    private var summaryStep: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Text("Votre objectif quotidien")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Formatters.kcal(calories))
                        .font(.system(size: 44, weight: .bold, design: .default))
                        .foregroundStyle(Theme.calories)
                        .monospacedDigit()
                    Text("Métabolisme de base \(Formatters.kcal(computed.bmr)) · Dépense estimée \(Formatters.kcal(computed.tdee))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                ProfileMacroSplitView(protein: protein, carbs: carbs, fat: fat)
            }
            .listRowBackground(Theme.card)

            Section {
                Toggle("Ajuster moi-même", isOn: $customizeTargets)
                if customizeTargets {
                    ProfileNumberField("Calories", value: $calories, unit: "kcal", maxFractionDigits: 0)
                    ProfileNumberField("Protéines", value: $protein, unit: "g", maxFractionDigits: 0)
                    ProfileNumberField("Glucides", value: $carbs, unit: "g", maxFractionDigits: 0)
                    ProfileNumberField("Lipides", value: $fat, unit: "g", maxFractionDigits: 0)
                } else {
                    targetRow(.protein, protein)
                    targetRow(.carbohydrates, carbs)
                    targetRow(.totalFat, fat)
                }
                ProfileNumberField("Fibres", value: $fiber, unit: "g", maxFractionDigits: 0)
                ProfileNumberField("Eau", value: $waterMl, unit: "ml", maxFractionDigits: 0)
            } header: {
                Text("Objectifs")
                    .foregroundStyle(Theme.textSecondary)
            } footer: {
                Text(customizeTargets
                     ? "Vos objectifs ne seront plus recalculés automatiquement. Vous pourrez les modifier dans Profil."
                     : "Calculés avec la formule de Mifflin-St Jeor. Vous pourrez les modifier à tout moment dans Profil.")
                .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: customizeTargets) {
            if !customizeTargets { refreshComputedTargets() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { ProfileKeyboard.dismiss() }
            }
        }
    }

    private func targetRow(_ key: NutrientKey, _ grams: Double) -> some View {
        ProfileTargetRow(title: key.label,
                         value: "\(Formatters.number(grams, maxFractionDigits: 0)) g",
                         color: Theme.color(for: key))
    }

    private func refreshComputedTargets() {
        guard !customizeTargets else { return }
        let t = computed
        calories = t.calories
        protein = t.protein
        carbs = t.carbs
        fat = t.fat
        fiber = GoalCalculator.fiberTarget(calories: t.calories)
        waterMl = GoalCalculator.waterTarget(weightKg: weightKg)
    }

    // MARK: - Finish / restore

    private func finish() {
        let profile = UserProfile.current(in: modelContext)
        profile.sex = sex
        profile.birthYear = birthYear
        profile.heightCm = Double(heightCm)
        profile.weightKg = weightKg
        profile.activity = activity
        profile.goal = goal
        profile.weeklyRateKg = weeklyRateKg
        profile.targetWeightKg = (goal != .maintain && hasTargetWeight) ? targetWeightKg : nil
        profile.manualTargets = customizeTargets
        if customizeTargets {
            profile.calorieTarget = calories
            profile.proteinTarget = protein
            profile.carbsTarget = carbs
            profile.fatTarget = fat
        } else {
            GoalCalculator.apply(to: profile)
        }
        profile.fiberTarget = fiber
        profile.waterTargetMl = waterMl
        modelContext.insert(WeightEntry(date: .now, kg: weightKg))
        profile.hasCompletedOnboarding = true
        try? modelContext.save()
        finishTrigger += 1
    }

    private func restore(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let backup = try ProfileBackupService.readBackup(at: url)
                guard backup.profile != nil else {
                    try ProfileBackupService.importBackup(backup, mode: .replace, context: modelContext)
                    errorMessage = "Données restaurées, mais la sauvegarde ne contient pas de profil : terminez la configuration."
                    return
                }
                try ProfileBackupService.importBackup(backup, mode: .replace, context: modelContext)
                finishTrigger += 1
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

/// Selectable card used by the onboarding steps.
private struct OnboardingChoiceRow: View {
    let title: String
    let detail: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.white : Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Theme.accent : Theme.accent.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            }
            .padding(14)
            .background(isSelected ? Theme.accent.opacity(0.18) : Theme.card,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
