import Charts
import SwiftData
import SwiftUI
import UIKit

/// Weekly check-in ("Bilan de la semaine"): recalculated expenditure and its change, summary of the
/// week, proposed program (old → new), − / + adjustment in collaborative mode, Plus tard / Appliquer.
/// CONTRACT: `CoachingCheckInView(profile:)`, presented by RootView when `appState.showingCheckIn`.
struct CoachingCheckInView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CoachingSettings.collaborativeKey) private var collaborative = false

    @State private var snapshot: CoachingSnapshot?
    @State private var base: CoachingProposal?
    /// Collaborative adjustment of the proposed calories (kcal, steps of 50).
    @State private var adjustment: Double = 0
    @State private var stepTick = 0

    private static let step: Double = 50

    private var canAdjust: Bool { collaborative || profile.manualTargets }
    private var weightKg: Double { snapshot?.latestScaleKg ?? profile.weightKg }

    /// Proposal with the collaborative adjustment (macros re-split for the adjusted calories).
    private var proposal: CoachingProposal? {
        guard let base else { return nil }
        guard adjustment != 0 else { return base }
        let calories = max(CoachingService.minimumCalories, base.calories + adjustment)
        return CoachingService.proposal(calories: calories, weightKg: weightKg, goal: profile.goal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let snapshot, let proposal {
                    expenditureCard(snapshot)
                    weekCard(snapshot)
                    programCard(snapshot, proposal: proposal)
                } else {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .task { load() }
        .sensoryFeedback(.selection, trigger: stepTick)
        .presentationBackground(Theme.background)
    }

    private func load() {
        guard snapshot == nil else { return }
        let snapshot = CoachingService.snapshot(profile: profile, context: modelContext)
        self.snapshot = snapshot
        base = CoachingService.proposal(snapshot: snapshot, profile: profile)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bilan de la semaine")
                    .font(Theme.font(26, .bold, relativeTo: .title))
                    .foregroundStyle(Theme.textPrimary)
                Text(CoachingFormat.longDay(.now))
                    .font(Theme.font(13, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Expenditure

    private struct ExpenditurePoint: Identifiable {
        var date: Date
        var kcal: Double
        var id: Date { date }
    }

    private func expenditureCard(_ snapshot: CoachingSnapshot) -> some View {
        let points = snapshot.last(28).map { ExpenditurePoint(date: $0.date, kcal: $0.expenditure) }
        let change = snapshot.expenditureChange(days: 7)
        let loggedDays = snapshot.intake.compactMap { $0 }.count
        return VStack(alignment: .leading, spacing: 0) {
            CoachingCardHeader(title: "Dépense estimée")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CoachingFormat.kcalNumber(snapshot.expenditure))
                    .font(Theme.font(30, .bold, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("kcal / jour")
                    .font(Theme.font(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if let change, abs(change) >= 1 {
                    CoachingDeltaPill(text: CoachingFormat.signed(change), isGood: change > 0)
                        .accessibilityLabel("\(CoachingFormat.signed(change)) kcal en 7 jours")
                }
            }
            .padding(.top, 4)

            if points.count >= 2 {
                expenditureChart(points)
                    .padding(.top, 6)
                Text(change == nil ? "Depuis le début" : "28 derniers jours · variation sur 7 jours")
                    .font(Theme.font(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }

            if loggedDays < 7 {
                Text("Moins de 7 jours de repas saisis : l'estimation repose encore surtout sur la formule initiale (Mifflin-St Jeor et niveau d'activité). Elle s'affinera semaine après semaine.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .themedCard()
    }

    private func expenditureChart(_ points: [ExpenditurePoint]) -> some View {
        let values = points.map(\.kcal)
        let low = (values.min() ?? 0) - 40
        let high = (values.max() ?? 0) + 40
        return Chart(points) { point in
            LineMark(x: .value("Jour", point.date), y: .value("Dépense", point.kcal))
                .foregroundStyle(Theme.expenditure)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: low...high)
        .frame(height: 56)
        .accessibilityHidden(true)
    }

    // MARK: - Week

    private func weekCard(_ snapshot: CoachingSnapshot) -> some View {
        let intake = snapshot.averageIntake(lastDays: 7)
        return VStack(alignment: .leading, spacing: 0) {
            CoachingCardHeader(title: "Cette semaine")
                .padding(.bottom, 4)
            row("Poids lissé") {
                HStack(spacing: 6) {
                    Text(snapshot.trendKg.map(CoachingFormat.kg) ?? "—")
                    if let change = snapshot.trendChange(days: 7) {
                        Text(CoachingFormat.signed(change, digits: 2))
                            .foregroundStyle(isTrendGood(change) ? Theme.good : Theme.textSecondary)
                    }
                }
            }
            row("Rythme réel / visé") {
                HStack(spacing: 5) {
                    Text(realRateText(snapshot))
                    Text("/").foregroundStyle(Theme.textTertiary)
                    Text(targetRateText)
                }
            }
            row("Apport moyen") {
                Text(intake.average.map(Formatters.kcal) ?? "—")
            }
            row("Jours saisis", showsDivider: true) {
                Text("\(intake.logged)/7")
                    .foregroundStyle(intake.logged >= 5 ? Theme.textPrimary : Theme.textSecondary)
            }
        }
        .padding(12)
        .themedCard()
    }

    private func isTrendGood(_ change: Double) -> Bool {
        switch profile.goal {
        case .lose: return change < 0
        case .gain: return change > 0
        case .maintain: return abs(change) < 0.2
        }
    }

    private func realRateText(_ snapshot: CoachingSnapshot) -> String {
        guard let change = snapshot.trendChange(days: 7), let trend = snapshot.trendKg, trend > 0 else { return "—" }
        return "\(CoachingFormat.signed(change / trend * 100, digits: 2)) %"
    }

    private var targetRateText: String {
        let rate = profile.effectiveRatePercent
        switch profile.goal {
        case .lose: return "\(CoachingFormat.signed(-rate, digits: 2)) %"
        case .gain: return "\(CoachingFormat.signed(rate, digits: 2)) %"
        case .maintain: return "0 %"
        }
    }

    // MARK: - New program

    private func programCard(_ snapshot: CoachingSnapshot, proposal: CoachingProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CoachingCardHeader(title: "Nouveau programme")
                .padding(.bottom, 4)
            row("Calories", color: Theme.calories) {
                change(old: profile.calorieTarget, new: proposal.calories, unit: "kcal")
            }
            ForEach(Theme.macroOrder, id: \.self) { key in
                row(key.label, color: Theme.color(for: key)) {
                    change(old: oldGrams(key), new: newGrams(key, proposal), unit: "g")
                }
            }
            HStack(alignment: .center, spacing: 10) {
                Text(explanation(snapshot, proposal: proposal))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if canAdjust {
                    stepper
                }
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { divider }

            if profile.manualTargets {
                Text("Mode manuel : appliquer remplacera vos objectifs actuels, qui resteront fixes ensuite.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .themedCard()
    }

    private func oldGrams(_ key: NutrientKey) -> Double {
        switch key {
        case .carbohydrates: return profile.carbsTarget
        case .protein: return profile.proteinTarget
        default: return profile.fatTarget
        }
    }

    private func newGrams(_ key: NutrientKey, _ proposal: CoachingProposal) -> Double {
        switch key {
        case .carbohydrates: return proposal.carbs
        case .protein: return proposal.protein
        default: return proposal.fat
        }
    }

    /// "1 911 → 1 832 kcal", or just "156 g" when unchanged.
    @ViewBuilder
    private func change(old: Double, new: Double, unit: String) -> some View {
        if abs(old.rounded() - new.rounded()) < 1 {
            Text("\(CoachingFormat.kcalNumber(new)) \(unit)")
        } else {
            HStack(spacing: 5) {
                Text(CoachingFormat.kcalNumber(old))
                    .foregroundStyle(Theme.textSecondary)
                Text("→").foregroundStyle(Theme.textTertiary)
                Text("\(CoachingFormat.kcalNumber(new)) \(unit)")
                    .contentTransition(.numericText())
            }
        }
    }

    private func explanation(_ snapshot: CoachingSnapshot, proposal: CoachingProposal) -> String {
        let base = self.base?.calories ?? proposal.calories
        var text: String
        switch profile.goal {
        case .lose, .gain:
            let delta = CoachingService.goalDelta(profile: profile, snapshot: snapshot)
            let rate = profile.goal == .lose ? -profile.effectiveRatePercent : profile.effectiveRatePercent
            text = "Dépense \(delta < 0 ? "−" : "+") \(Formatters.kcal(abs(delta))) (\(CoachingFormat.signed(rate, digits: 2)) %/sem.)"
        case .maintain:
            let diff = base - snapshot.expenditure
            let goalKg = profile.targetWeightKg ?? snapshot.trendKg ?? profile.weightKg
            if abs(diff) < 1 {
                text = "Dépense estimée : maintien autour de \(CoachingFormat.kg(goalKg))."
            } else {
                text = "Dépense \(diff < 0 ? "−" : "+") \(Formatters.kcal(abs(diff))) pour revenir vers \(CoachingFormat.kg(goalKg))."
            }
        }
        if base <= CoachingService.minimumCalories && adjustment <= 0 {
            text += " Plancher de \(Formatters.kcal(CoachingService.minimumCalories))."
        }
        if adjustment != 0 {
            text += " Ajusté de \(CoachingFormat.signed(adjustment)) kcal."
        }
        return text
    }

    private var stepper: some View {
        HStack(spacing: 8) {
            stepButton(systemImage: "minus", delta: -Self.step)
                .disabled((base?.calories ?? 0) + adjustment - Self.step < CoachingService.minimumCalories)
            stepButton(systemImage: "plus", delta: Self.step)
        }
    }

    private func stepButton(systemImage: String, delta: Double) -> some View {
        Button {
            withAnimation(.snappy) { adjustment += delta }
            stepTick += 1
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Retirer 50 kcal" : "Ajouter 50 kcal")
    }

    // MARK: - Rows

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: Theme.hairline)
    }

    private func row<Value: View>(_ title: String, color: Color = Theme.textBody, showsDivider: Bool = true,
                                  @ViewBuilder value: () -> Value) -> some View
    {
        HStack {
            Text(title)
                .font(Theme.callout)
                .foregroundStyle(color)
            Spacer(minLength: 8)
            value()
                .font(Theme.font(14, .bold, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            if showsDivider { divider }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Text("Plus tard")
                    .font(Theme.font(15, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.textBody)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                applyProposal()
            } label: {
                Text("Appliquer")
                    .font(Theme.font(15, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(proposal == nil)
            .opacity(proposal == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: Theme.hairline)
        }
    }

    private func applyProposal() {
        guard let snapshot, let proposal else { return }
        CoachingService.apply(proposal, snapshot: snapshot, profile: profile, context: modelContext, kind: "weekly")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
