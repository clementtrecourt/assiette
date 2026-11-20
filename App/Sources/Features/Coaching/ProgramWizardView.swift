import SwiftData
import SwiftUI

/// "Modifier le programme": one question per screen (diet, calorie floor, training, weekly
/// distribution, protein), then a summary of the resulting week. Nothing is saved before
/// "Terminer". Presented full screen from the Programme tab.
struct ProgramWizardView: View {
    let profile: UserProfile
    var initialStep = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var preferences = ProgramPreferences.current
    @State private var step = 0
    @State private var snapshot: CoachingSnapshot?
    @State private var finishTick = 0

    private static let stepCount = 6
    private var isSummary: Bool { step == Self.stepCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.opacity)
            }
            .scrollIndicators(.hidden)
            nextButton
        }
        .background(Theme.raised.ignoresSafeArea())
        .animation(.snappy, value: step)
        .sensoryFeedback(.selection, trigger: preferences)
        .sensoryFeedback(.success, trigger: finishTick)
        .onAppear { if initialStep > 0, step == 0 { step = min(initialStep, Self.stepCount - 1) } }
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
                Text("Modifier le programme")
                    .font(Theme.font(20, .regular, relativeTo: .title3))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 48)
                HStack {
                    Button {
                        if step == 0 { dismiss() } else { step -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step == 0 ? "Fermer" : "Étape précédente")
                    Spacer()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.raised2)
                    Rectangle()
                        .fill(Theme.textPrimary)
                        .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(Self.stepCount))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
            .accessibilityElement()
            .accessibilityLabel("Étape \(step + 1) sur \(Self.stepCount)")
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            question("Quel régime préférez-vous ?")
            options(ProgramDiet.allCases, selection: $preferences.diet) { ($0.symbol, $0.title, $0.detail) }
        case 1:
            question("Quel plancher calorique préférez-vous ?")
            options(CalorieFloor.allCases, selection: $preferences.floor) { ($0.symbol, $0.title, $0.detail) }
        case 2:
            question("Quel entraînement ferez-vous pendant ce programme ?")
            options(ProgramTraining.allCases, selection: $preferences.training) { ($0.symbol, $0.title, nil) }
        case 3:
            question("Comment répartir vos calories sur la semaine ?")
            options(CalorieDistribution.allCases, selection: $preferences.distribution) {
                ($0.symbol, $0.title, $0.detail)
            }
            if preferences.distribution == .shift {
                shiftSettings
                    .padding(.top, 24)
            }
        case 4:
            question("Quel apport en protéines préférez-vous ?")
            options(ProteinLevel.allCases, selection: $preferences.protein) { ($0.symbol, $0.title, $0.detail) }
        default:
            summary
        }
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

    private var proposal: CoachingProposal {
        if profile.manualTargets {
            let m = preferences.macros(calories: profile.calorieTarget, weightKg: profile.weightKg, goal: profile.goal)
            return CoachingProposal(calories: profile.calorieTarget, carbs: m.carbs.rounded(),
                                    protein: m.protein.rounded(), fat: m.fat.rounded())
        }
        guard let snapshot else {
            return CoachingProposal(calories: profile.calorieTarget, carbs: profile.carbsTarget,
                                    protein: profile.proteinTarget, fat: profile.fatTarget)
        }
        return CoachingService.proposal(snapshot: snapshot, profile: profile, preferences: preferences)
    }

    private var summary: some View {
        let p = proposal
        let weight = snapshot?.latestScaleKg ?? profile.weightKg
        let perKg = weight > 0 ? p.protein / weight : 0
        return VStack(alignment: .leading, spacing: 0) {
            question("Votre programme est prêt")
            CoachingWeekColumns(calories: p.calories, carbs: p.carbs, protein: p.protein, fat: p.fat,
                                todayIndex: CoachingFormat.mondayIndex(of: .now),
                                preferences: preferences, isLarge: true)
            Text("Comment votre programme a-t-il été conçu ?")
                .font(Theme.font(20, .regular, relativeTo: .title3))
                .foregroundStyle(Theme.textBody)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 40)
                .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 0) {
                if profile.manualTargets {
                    summaryStep(1, title: "Objectif manuel", value: CoachingFormat.kcalNumber(p.calories) + " kcal",
                                color: Theme.good,
                                text: "Vous avez saisi vous-même votre objectif calorique ; il reste inchangé.")
                } else {
                    let expenditure = snapshot?.expenditure ?? profile.calorieTarget
                    summaryStep(1, title: "Dépense estimée",
                                value: CoachingFormat.kcalNumber(expenditure) + " kcal", color: Theme.calories,
                                text: "D'après votre historique de nutrition et de poids, votre dépense quotidienne est d'environ \(CoachingFormat.kcalNumber(expenditure)) kcal.")
                    summaryStep(2, title: "Objectif moyen",
                                value: CoachingFormat.kcalNumber(p.calories) + " kcal", color: Theme.good,
                                text: averageText(p.calories))
                }
                summaryStep(profile.manualTargets ? 2 : 3, title: "Macros",
                            value: "\(CoachingFormat.grams(p.carbs)) G · \(CoachingFormat.grams(p.protein)) P · \(CoachingFormat.grams(p.fat)) L",
                            color: Theme.textPrimary,
                            text: "\(Formatters.number(perKg, maxFractionDigits: 1)) g de protéines par kg (\(preferences.protein.title.lowercased()), \(preferences.training.title.lowercased())). Régime \(preferences.diet.title.lowercased()) : le reste est réparti entre glucides et lipides.",
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
            if isSummary { finish() } else { step += 1 }
        } label: {
            Text(isSummary ? "Terminer" : "Suivant")
                .font(Theme.font(18, .medium, relativeTo: .body))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.raised.ignoresSafeArea(edges: .bottom))
    }

    private func finish() {
        preferences.save()
        if profile.manualTargets {
            let p = proposal
            profile.carbsTarget = p.carbs
            profile.proteinTarget = p.protein
            profile.fatTarget = p.fat
            try? modelContext.save()
        } else {
            CoachingService.refreshTargets(profile: profile, context: modelContext)
        }
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
            .frame(minHeight: 86)
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
