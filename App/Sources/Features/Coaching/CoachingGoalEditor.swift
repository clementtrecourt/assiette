import SwiftData
import SwiftUI

/// Goal & program editor: goal type, weekly rate (% of body weight, kg/week shown), goal weight,
/// check-in weekday and coaching mode (coached / collaborative / manual with typed targets).
/// No NavigationStack of its own: wrap it in one when presented in a sheet (`isSheet: true`),
/// push it as is from a navigation stack (Profile).
struct CoachingGoalEditor: View {
    enum Focus: Hashable {
        case target, rate, calories, carbs, protein, fat
    }

    let profile: UserProfile
    let initialFocus: Focus?
    let isSheet: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CoachingSettings.collaborativeKey) private var collaborative = false

    @State private var goal: WeightGoal
    @State private var presetRate: Double?
    @State private var rateText: String
    @State private var targetText: String
    @State private var weekday: Int
    @State private var mode: CoachingMode
    @State private var caloriesText: String
    @State private var carbsText: String
    @State private var proteinText: String
    @State private var fatText: String
    @FocusState private var focus: Focus?

    static let presetRates: [Double] = [0.25, 0.5, 0.75, 1.0]

    init(profile: UserProfile, initialFocus: Focus? = .target, isSheet: Bool = true) {
        self.profile = profile
        self.initialFocus = initialFocus
        self.isSheet = isSheet
        _goal = State(initialValue: profile.goal)
        let rate = profile.effectiveRatePercent > 0 ? (profile.effectiveRatePercent * 100).rounded() / 100 : 0.5
        let preset = Self.presetRates.first { abs($0 - rate) < 0.001 }
        _presetRate = State(initialValue: preset)
        _rateText = State(initialValue: CoachingFormat.fieldText(rate, digits: 2))
        _targetText = State(initialValue: CoachingFormat.fieldText(profile.targetWeightKg, digits: 1))
        _weekday = State(initialValue: profile.checkInWeekday)
        _mode = State(initialValue: CoachingMode.current(profile: profile,
                                                         collaborative: CoachingSettings.isCollaborative))
        _caloriesText = State(initialValue: CoachingFormat.fieldText(profile.calorieTarget, digits: 0))
        _carbsText = State(initialValue: CoachingFormat.fieldText(profile.carbsTarget, digits: 0))
        _proteinText = State(initialValue: CoachingFormat.fieldText(profile.proteinTarget, digits: 0))
        _fatText = State(initialValue: CoachingFormat.fieldText(profile.fatTarget, digits: 0))
    }

    // MARK: Derived values

    /// Rate in % of body weight per week (preset chip or typed value).
    private var ratePercent: Double? {
        if let presetRate { return presetRate }
        return CoachingFormat.parse(rateText)
    }

    private var targetWeight: Double? { CoachingFormat.parse(targetText) }
    private var weightKg: Double { profile.weightKg }

    private var isValid: Bool {
        if goal != .maintain {
            guard let rate = ratePercent, rate > 0, rate <= 2 else { return false }
        }
        if let target = targetWeight, target < 25 || target > 400 { return false }
        if mode == .manual {
            guard let kcal = CoachingFormat.parse(caloriesText), kcal >= 500 else { return false }
        }
        return true
    }

    var body: some View {
        Form {
            goalSection
            if goal != .maintain {
                rateSection
            }
            targetSection
            checkInSection
            modeSection
            if mode == .manual {
                manualSection
            }
        }
        .font(Theme.body)
        .listSectionSpacing(.compact)
        .themedBackground()
        .tint(Theme.accent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Objectif et programme")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }
                    .disabled(!isValid)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Enregistrer") { save() }
                    .font(Theme.font(16, .bold, relativeTo: .body))
                    .disabled(!isValid)
            }
        }
        .task {
            // Keyboard first: the goal weight (or the field the caller asked for) is ready to type.
            guard let initialFocus else { return }
            try? await Task.sleep(for: .milliseconds(450))
            if initialFocus == .rate && presetRate != nil {
                focus = .target
            } else {
                focus = initialFocus
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .manual { focus = .calories }
        }
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: Sections

    private var goalSection: some View {
        Section {
            CoachingChoiceChips(options: WeightGoal.allCases, selection: $goal) { option in
                switch option {
                case .lose: return "Perdre"
                case .maintain: return "Maintenir"
                case .gain: return "Prendre"
                }
            }
            .listRowBackground(Theme.background)
        } header: {
            ProfileSectionHeader("Objectif")
        }
    }

    private var rateSection: some View {
        Section {
            CoachingChoiceChips(options: Self.presetRates.map { Optional($0) } + [nil],
                                selection: $presetRate) { rate in
                guard let rate else { return "Autre" }
                return "\(Formatters.number(rate, maxFractionDigits: 2)) %"
            }
            .listRowBackground(Theme.background)
            .onChange(of: presetRate) { _, newValue in
                if let newValue {
                    rateText = CoachingFormat.fieldText(newValue, digits: 2)
                } else {
                    focus = .rate
                }
            }

            if presetRate == nil {
                CoachingNumberRow("Rythme", text: $rateText, unit: "% / sem.", focus: $focus, field: .rate,
                                  onSubmit: save)
                    .listRowBackground(Theme.background)
            }

            LabeledContent {
                Text(rateSummary)
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            } label: {
                Text(goal == .lose ? "Perte" : "Prise")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.background)
        } header: {
            ProfileSectionHeader("Rythme (% du poids par semaine)")
        } footer: {
            ProfileSectionFooter(rateFooter)
        }
    }

    private var rateSummary: String {
        guard let rate = ratePercent else { return "—" }
        let kg = CoachingService.weeklyKg(ratePercent: rate, weightKg: weightKg)
        return "\(Formatters.number(kg, maxFractionDigits: 2)) kg / sem."
    }

    private var rateFooter: String {
        guard let rate = ratePercent, rate > 0 else { return "Entrez un rythme entre 0,1 et 2 %." }
        let delta = EngineCoach.dailyDelta(ratePercent: rate, weightKg: weightKg)
        let sign = goal == .lose ? "−" : "+"
        var text = "Environ \(sign)\(Formatters.kcal(delta)) par jour par rapport à votre dépense."
        if goal == .lose && rate > 1 {
            text += " Au-delà de 1 %/semaine, la perte devient difficile à tenir."
        } else if goal == .gain && rate > 0.5 {
            text += " Pour prendre surtout du muscle, 0,25 à 0,5 %/semaine suffit."
        }
        return text
    }

    private var targetSection: some View {
        Section {
            CoachingNumberRow(goal == .maintain ? "Poids à maintenir" : "Poids visé", text: $targetText,
                              unit: "kg", focus: $focus, field: .target,
                              placeholder: goal == .maintain ? CoachingFormat.fieldText(weightKg, digits: 1) : "Facultatif",
                              onSubmit: save)
                .listRowBackground(Theme.background)
        } footer: {
            if let text = targetFooter { ProfileSectionFooter(text) }
        }
    }

    private var targetFooter: String? {
        let tolerance = Formatters.number(EngineParameters.calibrated.maintenanceToleranceKg, maxFractionDigits: 1)
        guard let target = targetWeight else {
            return goal == .maintain
                ? "Sans valeur, le programme maintient votre poids tendance actuel (± \(tolerance) kg)."
                : nil
        }
        switch goal {
        case .maintain:
            return "Le programme corrige vos apports si votre tendance s'écarte de plus de \(tolerance) kg de \(CoachingFormat.kg(target))."
        case .lose, .gain:
            let diff = goal == .lose ? weightKg - target : target - weightKg
            guard diff > 0 else {
                return goal == .lose
                    ? "Ce poids est supérieur ou égal à votre poids actuel."
                    : "Ce poids est inférieur ou égal à votre poids actuel."
            }
            guard let rate = ratePercent, rate > 0 else { return nil }
            let kgPerWeek = CoachingService.weeklyKg(ratePercent: rate, weightKg: weightKg)
            let weeks = Int((diff / kgPerWeek).rounded(.up))
            let date = Date.now.adding(days: weeks * 7)
            return "\(CoachingFormat.kg(diff)) à \(goal == .lose ? "perdre" : "prendre"), environ \(weeks) semaine\(weeks > 1 ? "s" : "") (vers le \(CoachingFormat.dayYear(date)))."
        }
    }

    private var checkInSection: some View {
        Section {
            Picker(selection: $weekday) {
                ForEach(CoachingFormat.mondayFirstWeekdays, id: \.self) { day in
                    Text(CoachingFormat.capitalized(CoachingFormat.weekdayName(day))).tag(day)
                }
            } label: {
                Text("Jour du bilan")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.background)
        } footer: {
            ProfileSectionFooter("Pesez-vous de préférence le matin, plusieurs fois par semaine : le bilan s'appuie sur votre poids tendance.")
        }
    }

    private var modeSection: some View {
        Section {
            ForEach(CoachingMode.allCases) { option in
                Button {
                    withAnimation(.quick) { mode = option }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(mode == option ? Theme.onAccent : Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(mode == option ? Theme.accent : Theme.raised2,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(Theme.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Text(option.detail)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(mode == option ? Theme.textPrimary : Theme.textQuaternary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
            .listRowBackground(Theme.background)
            .listRowSeparatorTint(Theme.separator)
        } header: {
            ProfileSectionHeader("Mode")
        }
    }

    private var manualSection: some View {
        Section {
            CoachingNumberRow("Calories", text: $caloriesText, unit: "kcal", focus: $focus, field: .calories,
                              titleColor: Theme.calories, onSubmit: save)
            ForEach(Theme.macroOrder, id: \.self) { key in
                CoachingNumberRow(key.label, text: macroText(key), unit: "g", focus: $focus,
                                  field: macroField(key), titleColor: Theme.color(for: key), onSubmit: save)
            }
            Button {
                fillProposedTargets()
            } label: {
                Label("Reprendre les valeurs proposées", systemImage: "arrow.counterclockwise")
                    .font(Theme.font(15, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.borderless)
        } header: {
            ProfileSectionHeader("Objectifs manuels")
        } footer: {
            ProfileSectionFooter(manualFooter)
        }
        .listRowBackground(Theme.background)
        .listRowSeparatorTint(Theme.separator)
    }

    private func macroText(_ key: NutrientKey) -> Binding<String> {
        switch key {
        case .carbohydrates: return $carbsText
        case .protein: return $proteinText
        default: return $fatText
        }
    }

    private func macroField(_ key: NutrientKey) -> Focus {
        switch key {
        case .carbohydrates: return .carbs
        case .protein: return .protein
        default: return .fat
        }
    }

    private var manualFooter: String {
        let carbs = CoachingFormat.parse(carbsText) ?? 0
        let protein = CoachingFormat.parse(proteinText) ?? 0
        let fat = CoachingFormat.parse(fatText) ?? 0
        let macroKcal = carbs * 4 + protein * 4 + fat * 9
        var text = "Vos objectifs restent fixes. Le bilan reste disponible pour suivre votre dépense."
        if let kcal = CoachingFormat.parse(caloriesText), abs(macroKcal - kcal) > 50 {
            text += " Vos macros totalisent \(Formatters.kcal(macroKcal))."
        }
        return text
    }

    private func fillProposedTargets() {
        let snapshot = CoachingService.snapshot(profile: profile, context: modelContext)
        let weight = snapshot.latestScaleKg ?? profile.weightKg
        let rate = ratePercent ?? profile.effectiveRatePercent
        // A program change starts maintenance at the expenditure (see CoachingService.engineGoal).
        let engineGoal = CoachingService.engineGoal(goal, ratePercent: rate, maintainedKg: nil,
                                                    trendKg: snapshot.trendKg ?? weight)
        let calories = EngineCoach.calorieTarget(expenditure: snapshot.expenditure, latestScaleWeightKg: weight,
                                                 trendWeightKg: snapshot.trendKg ?? weight, goal: engineGoal)
        let proposal = CoachingService.proposal(calories: calories, weightKg: weight, goal: goal)
        caloriesText = CoachingFormat.fieldText(proposal.calories, digits: 0)
        carbsText = CoachingFormat.fieldText(proposal.carbs, digits: 0)
        proteinText = CoachingFormat.fieldText(proposal.protein, digits: 0)
        fatText = CoachingFormat.fieldText(proposal.fat, digits: 0)
    }

    // MARK: Save

    private func save() {
        guard isValid else { return }
        let oldGoal = profile.goal
        let oldRate = profile.effectiveRatePercent
        let oldTarget = profile.targetWeightKg
        let wasManual = profile.manualTargets

        // Maintenance keeps the last rate so switching back to a loss / gain restores it.
        let rate = ratePercent ?? oldRate
        profile.goal = goal
        if rate > 0 {
            profile.weeklyRatePercent = rate
            profile.weeklyRateKg = CoachingService.weeklyKg(ratePercent: rate, weightKg: weightKg)
        }
        profile.targetWeightKg = targetWeight
        profile.checkInWeekday = weekday
        collaborative = mode == .collaborative

        let goalChanged = oldGoal != goal || abs(oldRate - rate) > 0.0001 || oldTarget != targetWeight

        switch mode {
        case .manual:
            profile.manualTargets = true
            let proposal = CoachingProposal(
                calories: (CoachingFormat.parse(caloriesText) ?? profile.calorieTarget).rounded(),
                carbs: (CoachingFormat.parse(carbsText) ?? profile.carbsTarget).rounded(),
                protein: (CoachingFormat.parse(proteinText) ?? profile.proteinTarget).rounded(),
                fat: (CoachingFormat.parse(fatText) ?? profile.fatTarget).rounded())
            let targetsChanged = proposal.calories != profile.calorieTarget || proposal.carbs != profile.carbsTarget
                || proposal.protein != profile.proteinTarget || proposal.fat != profile.fatTarget
            if goalChanged || targetsChanged || !wasManual {
                // Recorded as a program change (goal history), targets as typed.
                let snapshot = CoachingService.snapshot(profile: profile, context: modelContext)
                CoachingService.apply(proposal, snapshot: snapshot, profile: profile, context: modelContext,
                                      kind: "program")
            } else {
                try? modelContext.save()
            }
        case .coached, .collaborative:
            profile.manualTargets = false
            if goalChanged || wasManual {
                CoachingService.refreshTargets(profile: profile, context: modelContext)
            } else {
                try? modelContext.save()
            }
        }
        dismiss()
    }
}

/// "Modifier" on the program card: adjust today's calorie and G / P / L targets by hand.
/// The calorie field has the keyboard on appear; macros follow the calories until one is edited.
struct CoachingTargetsEditor: View {
    enum Field: Hashable { case calories, carbs, protein, fat }

    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var caloriesText: String
    @State private var carbsText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var autoSplit = true
    @FocusState private var focus: Field?

    init(profile: UserProfile) {
        self.profile = profile
        _caloriesText = State(initialValue: CoachingFormat.fieldText(profile.calorieTarget, digits: 0))
        _carbsText = State(initialValue: CoachingFormat.fieldText(profile.carbsTarget, digits: 0))
        _proteinText = State(initialValue: CoachingFormat.fieldText(profile.proteinTarget, digits: 0))
        _fatText = State(initialValue: CoachingFormat.fieldText(profile.fatTarget, digits: 0))
    }

    private var calories: Double? { CoachingFormat.parse(caloriesText) }
    private var isValid: Bool { (calories ?? 0) >= 500 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CoachingNumberRow("Calories", text: $caloriesText, unit: "kcal", focus: $focus,
                                      field: .calories, titleColor: Theme.calories, onSubmit: save)
                } footer: {
                    ProfileSectionFooter("Actuellement \(Formatters.kcal(profile.calorieTarget)) par jour.")
                }
                .listRowBackground(Theme.background)

                Section {
                    CoachingNumberRow(NutrientKey.carbohydrates.label, text: $carbsText, unit: "g", focus: $focus,
                                      field: .carbs, titleColor: Theme.carbs, onSubmit: save)
                    CoachingNumberRow(NutrientKey.protein.label, text: $proteinText, unit: "g", focus: $focus,
                                      field: .protein, titleColor: Theme.protein, onSubmit: save)
                    CoachingNumberRow(NutrientKey.totalFat.label, text: $fatText, unit: "g", focus: $focus,
                                      field: .fat, titleColor: Theme.fat, onSubmit: save)
                    if !autoSplit {
                        Button {
                            autoSplit = true
                            resplit()
                        } label: {
                            Label("Répartir automatiquement", systemImage: "arrow.counterclockwise")
                                .font(Theme.font(15, .medium, relativeTo: .body))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    ProfileSectionHeader("Macros")
                } footer: {
                    ProfileSectionFooter(footer)
                }
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.separator)
            }
            .font(Theme.body)
            .listSectionSpacing(.compact)
            .themedBackground()
            .navigationTitle("Modifier le programme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Enregistrer") { save() }
                        .font(Theme.font(16, .bold, relativeTo: .body))
                        .disabled(!isValid)
                }
            }
            .onChange(of: caloriesText) {
                if autoSplit { resplit() }
            }
            .onChange(of: carbsText) { stopAutoSplit(.carbs) }
            .onChange(of: proteinText) { stopAutoSplit(.protein) }
            .onChange(of: fatText) { stopAutoSplit(.fat) }
            .task {
                try? await Task.sleep(for: .milliseconds(450))
                focus = .calories
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }

    private var footer: String {
        let macroKcal = (CoachingFormat.parse(carbsText) ?? 0) * 4 + (CoachingFormat.parse(proteinText) ?? 0) * 4
            + (CoachingFormat.parse(fatText) ?? 0) * 9
        var text = autoSplit
            ? "Les macros suivent les calories (protéines selon votre poids, lipides 25 %)."
            : "Macros saisies à la main."
        if let calories, abs(macroKcal - calories) > 50 {
            text += " Elles totalisent \(Formatters.kcal(macroKcal))."
        }
        if !profile.manualTargets {
            text += " Le prochain bilan recalculera le programme."
        }
        return text
    }

    /// A macro typed by the user (focused field) stops the automatic split.
    private func stopAutoSplit(_ field: Field) {
        if focus == field { autoSplit = false }
    }

    private func resplit() {
        guard let calories else { return }
        let proposal = CoachingService.proposal(calories: calories, weightKg: profile.weightKg, goal: profile.goal)
        carbsText = CoachingFormat.fieldText(proposal.carbs, digits: 0)
        proteinText = CoachingFormat.fieldText(proposal.protein, digits: 0)
        fatText = CoachingFormat.fieldText(proposal.fat, digits: 0)
    }

    private func save() {
        guard let calories, isValid else { return }
        let proposal = CoachingProposal(
            calories: calories.rounded(),
            carbs: (CoachingFormat.parse(carbsText) ?? profile.carbsTarget).rounded(),
            protein: (CoachingFormat.parse(proteinText) ?? profile.proteinTarget).rounded(),
            fat: (CoachingFormat.parse(fatText) ?? profile.fatTarget).rounded())
        let snapshot = CoachingService.snapshot(profile: profile, context: modelContext)
        CoachingService.apply(proposal, snapshot: snapshot, profile: profile, context: modelContext, kind: "program")
        dismiss()
    }
}
