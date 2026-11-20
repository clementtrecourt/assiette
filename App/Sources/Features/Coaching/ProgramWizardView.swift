import SwiftData
import SwiftUI

enum ProgramWizardEntry: String, Identifiable {
    case new, edit
    var id: Self { self }
}

struct ProgramWizardView: View {
    let profile: UserProfile
    let entry: ProgramWizardEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var preferences: ProgramPreferences
    @State private var split: ProgramPreferences.MacroSplit
    private enum Page { case intro, style, diet, floor, training, distribution, protein, targets, split, summary }

    @State private var page: Page
    @State private var mode: CoachingMode
    @State private var manual: CoachingProposal
    private let hasIntro: Bool

    init(profile: UserProfile, entry: ProgramWizardEntry, skipIntro: Bool = false, showSummary: Bool = false) {
        self.profile = profile
        self.entry = entry
        hasIntro = entry == .new && !skipIntro
        _page = State(initialValue: showSummary ? .summary : (hasIntro ? .intro : .style))
        _mode = State(initialValue: entry == .new ? .coached :
            CoachingMode.current(profile: profile, collaborative: CoachingSettings.isCollaborative))
        let draft: ProgramPreferences = entry == .new ? ProgramPreferences() : .current
        _preferences = State(initialValue: draft)
        _split = State(initialValue: draft.collaborativeSplit ?? .init(protein: 25, fat: 30))
        _manual = State(initialValue: CoachingProposal(calories: profile.calorieTarget, carbs: profile.carbsTarget,
                                                       protein: profile.proteinTarget, fat: profile.fatTarget))
    }
    @State private var snapshot: CoachingSnapshot?
    @State private var finishTick = 0

    private var pages: [Page] {
        switch mode {
        case .manual: [.style, .targets, .distribution, .summary]
        case .collaborative: [.style, .floor, .distribution, .split, .summary]
        case .coached: [.style, .diet, .floor, .training, .distribution, .protein, .summary]
        }
    }
    private var step: Int { pages.firstIndex(of: page) ?? 0 }
    private var isSummary: Bool { page == .summary }

    var body: some View {
        VStack(spacing: 0) {
            if page != .intro { header }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, page == .intro ? 0 : 16)
                .padding(.top, page == .intro ? 0 : 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            .id(page)
            .scrollIndicators(.hidden)
            nextButton
        }
        .background(Theme.raised.ignoresSafeArea())
        .animation(.snappy, value: page)
        .sensoryFeedback(.selection, trigger: preferences)
        .sensoryFeedback(.success, trigger: finishTick)
        .task {
            if snapshot == nil {
                snapshot = CoachingService.snapshot(profile: profile, context: modelContext)
            }
        }
    }

    // MARK: Header (back, title, progress)

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Text(entry == .new ? "Nouveau programme" : "Modifier le programme")
                    .font(Theme.font(20, .regular, relativeTo: .title3))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 48)
                HStack {
                    Button {
                        if step > 0 { page = pages[step - 1] }
                        else if hasIntro { page = .intro }
                        else { dismiss() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step == 0 && !hasIntro ? "Fermer" : "Étape précédente")
                    Spacer()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.raised2)
                    Rectangle()
                        .fill(Theme.textPrimary)
                        .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(pages.count))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
            .accessibilityElement()
            .accessibilityLabel("Étape \(step + 1) sur \(pages.count)")
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch page {
        case .intro:
            introduction
        case .style:
            question("Quel style de programme préférez-vous ?")
            options(CoachingMode.allCases, selection: $mode) { ($0.systemImage, $0.label, $0.detail) }
        case .split:
            question("Comment répartir vos macros ?")
            targetField("Protéines (%)", value: $split.protein)
            targetField("Lipides (%)", value: $split.fat)
            if split.isValid {
                Text("Glucides · \(Formatters.number(split.carbs, maxFractionDigits: 1)) %")
            } else {
                Text("Le total des protéines et des lipides doit être compris entre 0 et 100 %.")
            }
        case .targets:
            question("Quels objectifs souhaitez-vous fixer ?")
            targetField("Calories (kcal)", value: $manual.calories)
            targetField("Protéines (g)", value: $manual.protein)
            targetField("Lipides (g)", value: $manual.fat)
            targetField("Glucides (g)", value: $manual.carbs)
        case .diet:
            question("Quel régime préférez-vous ?")
            options(ProgramDiet.allCases, selection: $preferences.diet) { ($0.symbol, $0.title, $0.detail) }
        case .floor:
            question("Quel plancher calorique préférez-vous ?")
            options(CalorieFloor.allCases, selection: $preferences.floor) { ($0.symbol, $0.title, $0.detail) }
        case .training:
            question("Quel entraînement ferez-vous pendant ce programme ?")
            options(ProgramTraining.allCases, selection: $preferences.training) { ($0.symbol, $0.title, nil) }
        case .distribution:
            question("Comment répartir vos calories sur la semaine ?")
            options(CalorieDistribution.allCases, selection: $preferences.distribution) {
                ($0.symbol, $0.title, $0.detail)
            }
            if preferences.distribution == .shift {
                shiftSettings
                    .padding(.top, 24)
            }
        case .protein:
            question("Quel apport en protéines préférez-vous ?")
            options(ProteinLevel.allCases, selection: $preferences.protein) { ($0.symbol, $0.title, $0.detail) }
        case .summary:
            summary
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image("ProgramRover")
                .resizable()
                .aspectRatio(1.1, contentMode: .fit)
                .accessibilityHidden(true)
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title2)
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 52, height: 52)
                            .background(Theme.accent, in: Circle())
                    }
                    .accessibilityLabel("Fermer")
                    .padding(16)
                }
            Text("NOUVEAU PROGRAMME")
                .font(Theme.screenTitle(30))
                .padding(.horizontal, 16)
            HStack(alignment: .top, spacing: 16) {
                Text("1").frame(width: 36, height: 36)
                    .foregroundStyle(Theme.onAccent).background(Theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Définir mes préférences").font(.headline)
                    Text("Ces choix déterminent vos objectifs de calories et de macros.")
                        .foregroundStyle(Theme.textBody)
                }
            }
            .padding(.horizontal, 28)
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private func targetField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
        .padding()
        .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 10)
    }

    private func question(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(25, .bold, relativeTo: .title))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 24)
            .accessibilityAddTraits(.isHeader)
    }

    private func options<Option: Identifiable & Hashable>(
        _ all: [Option], selection: Binding<Option>,
        describe: @escaping (Option) -> (symbol: String, title: String, detail: String?)
    ) -> some View {
        VStack(spacing: 14) {
            ForEach(all) { option in
                let info = describe(option)
                ProgramWizardOptionCard(symbol: info.symbol, title: info.title, detail: info.detail,
                                        isSelected: selection.wrappedValue == option) {
                    selection.wrappedValue = option
                }
            }
        }
    }

    /// High days (L … D) and the extra share given to them.
    private var shiftSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Jours plus élevés")
                .font(Theme.font(17, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    let on = preferences.highDays.contains(index)
                    Button {
                        if on { preferences.highDays.remove(index) } else { preferences.highDays.insert(index) }
                    } label: {
                        Text(CoachingFormat.dayLetters[index])
                            .font(Theme.font(17, .regular, relativeTo: .body))
                            .foregroundStyle(on ? Theme.onAccent : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(on ? Theme.accent : Theme.raised2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CoachingFormat.weekdayName(index == 6 ? 1 : index + 2))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("Supplément ces jours-là")
                .font(Theme.font(17, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 8)
            HStack(spacing: 8) {
                ForEach(ProgramPreferences.shiftChoices, id: \.self) { value in
                    let on = preferences.shiftPercent == value
                    Button {
                        preferences.shiftPercent = value
                    } label: {
                        Text("+\(Int(value)) %")
                            .font(Theme.font(17, .regular, relativeTo: .body))
                            .foregroundStyle(on ? Theme.onAccent : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(on ? Theme.accent : Theme.raised2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if preferences.highDays.isEmpty || preferences.highDays.count == 7 {
                Text("Choisissez entre 1 et 6 jours, sinon la semaine reste uniforme.")
                    .font(Theme.font(15, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Summary

    private var effectivePreferences: ProgramPreferences {
        var draft = preferences
        draft.collaborativeSplit = mode == .collaborative ? split : nil
        return draft
    }

    private var proposal: CoachingProposal {
        if mode == .manual { return manual }
        guard let snapshot else {
            return CoachingProposal(calories: profile.calorieTarget, carbs: profile.carbsTarget,
                                    protein: profile.proteinTarget, fat: profile.fatTarget)
        }
        return CoachingService.proposal(snapshot: snapshot, profile: profile, preferences: effectivePreferences)
    }

    private var summary: some View {
        let p = proposal
        let weight = snapshot?.latestScaleKg ?? profile.weightKg
        let perKg = weight > 0 ? p.protein / weight : 0
        return VStack(alignment: .leading, spacing: 0) {
            question("Votre programme est prêt")
            CoachingWeekColumns(calories: p.calories, carbs: p.carbs, protein: p.protein, fat: p.fat,
                                todayIndex: CoachingFormat.mondayIndex(of: .now),
                                preferences: effectivePreferences, isLarge: true)
            Text("Comment votre programme a-t-il été conçu ?")
                .font(Theme.font(20, .regular, relativeTo: .title3))
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 40)
                .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 0) {
                if mode == .manual {
                    summaryStep(1, title: "Objectif manuel", value: CoachingFormat.kcalNumber(p.calories) + " kcal",
                                color: Theme.good,
                                text: "Vous avez saisi votre objectif calorique quotidien.")
                } else {
                    let expenditure = snapshot?.expenditure ?? profile.calorieTarget
                    summaryStep(1, title: "Dépense estimée",
                                value: CoachingFormat.kcalNumber(expenditure) + " kcal", color: Theme.calories,
                                text: "D'après votre historique de nutrition et de poids, votre dépense quotidienne est d'environ \(CoachingFormat.kcalNumber(expenditure)) kcal.")
                    summaryStep(2, title: "Objectif moyen",
                                value: CoachingFormat.kcalNumber(p.calories) + " kcal", color: Theme.good,
                                text: averageText(p.calories))
                }
                summaryStep(mode == .manual ? 2 : 3, title: "Macros",
                            value: "\(CoachingFormat.grams(p.carbs)) G · \(CoachingFormat.grams(p.protein)) P · \(CoachingFormat.grams(p.fat)) L",
                            color: Theme.textPrimary,
                            text: mode == .collaborative ? "Votre répartition est appliquée au budget calorique proposé." :
                                  mode == .manual ? "Ces quantités correspondent à votre saisie." : "\(Formatters.number(perKg, maxFractionDigits: 1)) g de protéines par kg (\(preferences.protein.title.lowercased()), \(preferences.training.title.lowercased())). Régime \(preferences.diet.title.lowercased()) : le reste est réparti entre glucides et lipides.",
                            isLast: true)
            }
        }
    }

    private func averageText(_ calories: Double) -> String {
        let floor = CoachingFormat.kcalNumber(preferences.floor.kcal)
        let base: String
        switch profile.goal {
        case .lose: base = "Pour votre objectif de perte de poids, l'objectif moyen est de \(CoachingFormat.kcalNumber(calories)) kcal par jour"
        case .gain: base = "Pour votre objectif de prise de poids, l'objectif moyen est de \(CoachingFormat.kcalNumber(calories)) kcal par jour"
        case .maintain: base = "Pour maintenir votre poids, l'objectif moyen est de \(CoachingFormat.kcalNumber(calories)) kcal par jour"
        }
        return base + ", jamais sous \(floor) kcal."
    }

    private func summaryStep(_ number: Int, title: String, value: String, color: Color, text: String,
                             isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 0) {
                Text("\(number)")
                    .font(Theme.font(18, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Theme.separatorStrong)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.font(18, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.textBody)
                Text(value)
                    .font(Theme.font(18, .regular, relativeTo: .body))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(text)
                    .font(Theme.font(16, .regular, relativeTo: .callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .padding(.bottom, isLast ? 0 : 36)
        }
        .padding(.leading, 4)
    }

    // MARK: Bottom button

    private var nextButton: some View {
        Button {
            if page == .intro { page = .style }
            else if isSummary { finish() }
            else { page = pages[step + 1] }
        } label: {
            Text(page == .intro ? "Définir mes préférences" : (isSummary ? "Terminer" : "Suivant"))
                .font(Theme.font(18, .medium, relativeTo: .body))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .disabled((page == .split && !split.isValid) || (isSummary && snapshot == nil) || (page == .targets &&
                   (manual.calories < 500 || manual.protein < 0 || manual.carbs < 0 || manual.fat < 0)))
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.raised.ignoresSafeArea(edges: .bottom))
    }

    private func finish() {
        guard let snapshot else { return }
        let targets = proposal
        effectivePreferences.save()
        UserDefaults.standard.set(mode == .collaborative, forKey: CoachingSettings.collaborativeKey)
        profile.manualTargets = mode == .manual
        CoachingService.apply(targets, snapshot: snapshot, profile: profile, context: modelContext, kind: "program")
        finishTick += 1
        dismiss()
    }
}

/// Outlined option card: icon, title, optional detail, radio. Selected = 3 pt white border.
struct ProgramWizardOptionCard: View {
    let symbol: String
    let title: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Theme.font(17, .regular, relativeTo: .body))
                        .foregroundStyle(Theme.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(Theme.font(15, .regular, relativeTo: .subheadline))
                            .foregroundStyle(Theme.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                radio
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 16)
            .frame(minHeight: 96)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Theme.textPrimary : Theme.raised2,
                                  lineWidth: isSelected ? 3 : 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var radio: some View {
        ZStack {
            if isSelected {
                Circle().fill(Theme.accent)
                Circle().fill(Theme.onAccent).frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(Theme.hex(0x555555), lineWidth: 3)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
