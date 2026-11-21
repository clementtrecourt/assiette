import SwiftData
import SwiftUI

/// "Nouvel objectif" / "Modifier l'objectif": intro (steps 1 goal, 2 program), goal type (new
/// only), target weight ruler + weekly rate, summary; then chains into the program wizard.
/// Layout measured on the reference screenshots; the intro illustration is our own.
struct GoalFlowView: View {
    let profile: UserProfile
    let isNew: Bool
    var initialPage: Page = .intro

    enum Page: Int { case intro, type, target, summary, program }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var page: Page = .intro
    @State private var goal: WeightGoal?
    @State private var targetKg: Double = 70
    @State private var ratePercent: Double = 0.5
    @State private var snapshot: CoachingSnapshot?
    @State private var didLoad = false
    @State private var savedTick = 0

    private var steps: [Page] { isNew ? [.type, .target, .summary] : [.target, .summary] }
    private var currentKg: Double { snapshot?.trendKg ?? snapshot?.latestScaleKg ?? profile.weightKg }
    private var scaleKg: Double { snapshot?.latestScaleKg ?? profile.weightKg }
    private var chosenGoal: WeightGoal { goal ?? profile.goal }

    var body: some View {
        Group {
            switch page {
            case .intro: intro
            case .program: ProgramWizardView(profile: profile, entry: .new, skipIntro: true)
            default: stepScreen
            }
        }
        .background(Theme.raised.ignoresSafeArea())
        .animation(.quick, value: page)
        .sensoryFeedback(.success, trigger: savedTick)
        .task { load() }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        snapshot = CoachingService.snapshot(profile: profile, context: modelContext)
        goal = isNew ? nil : profile.goal
        let rate = profile.effectiveRatePercent
        ratePercent = rate > 0 ? rate : (profile.goal == .gain ? 0.15 : 0.5)
        targetKg = ((profile.targetWeightKg ?? currentKg) * 10).rounded() / 10
        page = initialPage
        if isNew && initialPage == .target && goal == nil { goal = profile.goal }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                GoalFlowIllustration(goal: isNew ? .lose : profile.goal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                    .ignoresSafeArea(edges: .top)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 56, height: 56)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 4)
                .accessibilityLabel("Fermer")
            }
            Text(isNew ? "NOUVEL OBJECTIF" : "MODIFIER L’OBJECTIF")
                .font(Theme.screenTitle(30))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .padding(.top, 30)
                .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 0) {
                introStep(1, title: isNew ? "Définir l’objectif" : "Modifier l’objectif",
                          detail: isNew ? "Choisissez le poids visé et le rythme d’évolution"
                                        : "Modifiez le poids visé et le rythme d’évolution",
                          active: true, isLast: false)
                introStep(2, title: "Ajuster le programme", detail: nil, active: false, isLast: true)
            }
            .padding(.horizontal, 30)
            Spacer(minLength: 0)
            bottomButton(isNew ? "Définir un nouvel objectif" : "Modifier les paramètres", enabled: true) {
                page = steps[0]
            }
        }
    }

    private func introStep(_ n: Int, title: String, detail: String?, active: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                Text("\(n)")
                    .font(Theme.font(18, .regular, relativeTo: .body))
                    .foregroundStyle(active ? Theme.onAccent : Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(active ? Theme.accent : Theme.raised2, in: Circle())
                if !isLast {
                    Rectangle().fill(Theme.raised2).frame(width: 2, height: 36)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.font(18, active ? .medium : .regular, relativeTo: .body))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                if let detail {
                    Text(detail)
                        .font(Theme.font(16, .regular, relativeTo: .callout))
                        .foregroundStyle(Theme.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 7)
        }
    }

    // MARK: Steps

    private var stepScreen: some View {
        VStack(spacing: 0) {
            GoalFlowHeader(title: isNew ? "Nouvel objectif" : "Modifier l’objectif",
                           progress: progress) { back() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch page {
                    case .type: typeStep
                    case .target: targetStep
                    default: summaryStep
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            if page == .summary {
                bottomButton("Terminer", enabled: true) { save() }
            } else {
                bottomButton("Suivant", enabled: page != .type || goal != nil) { next() }
            }
        }
    }

    private var progress: Double {
        guard let index = steps.firstIndex(of: page) else { return 1 }
        return Double(index + 1) / Double(steps.count)
    }

    private func back() {
        if let index = steps.firstIndex(of: page), index > 0 { page = steps[index - 1] } else { page = .intro }
    }

    private func next() {
        guard let index = steps.firstIndex(of: page), index + 1 < steps.count else { return }
        if page == .type {
            // Sensible defaults for the chosen direction.
            switch chosenGoal {
            case .lose:
                if targetKg >= currentKg { targetKg = ((currentKg - 2) * 2).rounded() / 2 }
                if ratePercent > 1.5 || ratePercent < 0.1 { ratePercent = 0.5 }
            case .gain:
                if targetKg <= currentKg { targetKg = ((currentKg + 2) * 2).rounded() / 2 }
                ratePercent = min(max(ratePercent, 0.05), 0.5)
            case .maintain:
                targetKg = (currentKg * 10).rounded() / 10
            }
        }
        page = steps[index + 1]
    }

    private func question(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(26, .bold, relativeTo: .title))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var typeStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            question("Quel est votre objectif ?")
            VStack(spacing: 14) {
                ForEach([WeightGoal.lose, .maintain, .gain], id: \.self) { option in
                    ProgramWizardOptionCard(symbol: Self.symbol(option), title: Self.title(option), detail: nil,
                                            isSelected: goal == option) { goal = option }
                }
            }
        }
    }

    static func symbol(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose: "arrow.down.circle.fill"
        case .maintain: "equal.circle.fill"
        case .gain: "arrow.up.circle.fill"
        }
    }

    static func title(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose: "Perdre du poids"
        case .maintain: "Maintenir mon poids"
        case .gain: "Prendre du poids"
        }
    }

    private var targetStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                GoalFlowStatCard(value: "\(CoachingFormat.kcalNumber(budget)) kcal", label: "budget quotidien initial",
                                 background: GoalFlowColors.green)
                GoalFlowStatCard(value: endDateText, label: "date de fin estimée", background: GoalFlowColors.header)
            }
            question(chosenGoal == .maintain ? "Quel poids voulez-vous maintenir ?" : "Quel est votre poids cible ?")
                .padding(.top, 40)
            Text("\(Formatters.number(targetKg, maxFractionDigits: 1)) kg")
                .font(Theme.font(26, .bold, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(Theme.textBody)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            GoalWeightRuler(value: $targetKg, currentKg: currentKg)
                .frame(height: 84)
                .padding(.horizontal, -16)
                .padding(.top, 12)
            if chosenGoal != .maintain {
                question("Quel rythme visez-vous ?")
                    .padding(.top, 40)
                GoalRateEditor(goal: chosenGoal, ratePercent: $ratePercent, weightKg: scaleKg)
                    .padding(.top, 26)
            }
        }
    }

    // MARK: Numbers

    private var budget: Double {
        guard let snapshot else { return profile.calorieTarget }
        var parameters = EngineParameters.calibrated
        parameters.minimumCalories = ProgramPreferences.current.floor.kcal
        let engineGoal: EngineCoach.Goal
        switch chosenGoal {
        case .lose: engineGoal = .lose(ratePercent: ratePercent)
        case .gain: engineGoal = .gain(ratePercent: ratePercent)
        case .maintain:
            engineGoal = .maintain(goalWeightKg: targetKg, correctionRatePercent: CoachingService.maintenanceCorrectionPercent)
        }
        return EngineCoach.calorieTarget(expenditure: snapshot.expenditure, latestScaleWeightKg: scaleKg,
                                         trendWeightKg: currentKg, goal: engineGoal, parameters: parameters)
    }

    private var endDate: Date? {
        guard chosenGoal != .maintain, ratePercent > 0 else { return nil }
        let gap = chosenGoal == .lose ? currentKg - targetKg : targetKg - currentKg
        guard gap > 0 else { return Calendar.current.startOfDay(for: .now) }
        let weeks = gap / (ratePercent / 100 * currentKg)
        return Calendar.current.startOfDay(for: .now).adding(days: Int((weeks * 7).rounded()))
    }

    private var endDateText: String {
        guard let endDate else { return "—" }
        return endDate.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func signedRate(_ rate: Double, goal: WeightGoal) -> String {
        let sign = goal == .lose ? "−" : "+"
        return "\(sign)\(Formatters.number(rate, maxFractionDigits: 2)) % PC par semaine"
    }

    // MARK: Summary

    private var summaryStep: some View {
        let g = chosenGoal
        let oldTarget = profile.targetWeightKg
        let goalChanged = isNew || g != profile.goal || oldTarget.map { abs($0 - targetKg) > 0.05 } ?? true
        let rateChanged = isNew || abs(profile.effectiveRatePercent - ratePercent) > 0.001
        return VStack(alignment: .leading, spacing: 20) {
            question(isNew ? "Résumé de l’objectif" : "Modifications de votre objectif")
                .padding(.bottom, 6)
            GoalFlowSummaryCard(
                title: g.label, value: "\(Formatters.number(currentKg, maxFractionDigits: 1)) kg  »  \(Formatters.number(targetKg, maxFractionDigits: 1)) kg",
                header: GoalFlowColors.green,
                text: isNew ? nil : (goalChanged ? "Avant : \(profile.goal.label), \(oldTarget.map { Formatters.number($0, maxFractionDigits: 1) + " kg" } ?? "sans poids cible")" : "Aucun changement"))
            if g != .maintain {
                GoalFlowSummaryCard(
                    title: "Rythme", value: signedRate(ratePercent, goal: g), header: GoalFlowColors.header,
                    text: isNew || rateChanged
                        ? "Nous ajusterons vos objectifs caloriques pour vous permettre de \(g == .lose ? "perdre" : "prendre") \(Formatters.number(ratePercent, maxFractionDigits: 2)) % de votre poids par semaine. Le nombre exact de kilos évolue avec votre poids."
                        : "Aucun changement")
            }
            GoalFlowSummaryCard(
                title: "Budget quotidien initial", value: "\(CoachingFormat.kcalNumber(budget)) kcal",
                header: GoalFlowColors.header,
                text: profile.manualTargets
                    ? "Vos objectifs sont en mode manuel : ce budget est indicatif et vos objectifs saisis ne changent pas."
                    : "Ce budget est estimé à partir de votre dépense actuelle. Votre dépense évolue avec votre alimentation et votre activité ; chaque semaine, le bilan ajuste votre programme.")
            if g != .maintain {
                GoalFlowSummaryCard(
                    title: "Date de fin estimée", value: endDateText, header: GoalFlowColors.header,
                    text: "Estimation optimiste du moment où vous atteindriez votre objectif si votre dépense restait parfaitement stable et que vous suiviez vos objectifs à 100 %.")
            }
        }
    }

    private func save() {
        let g = chosenGoal
        profile.goal = g
        if g != .maintain, ratePercent > 0 {
            profile.weeklyRatePercent = ratePercent
            profile.weeklyRateKg = CoachingService.weeklyKg(ratePercent: ratePercent, weightKg: scaleKg)
        }
        profile.targetWeightKg = targetKg
        if profile.manualTargets {
            try? modelContext.save()
        } else {
            CoachingService.refreshTargets(profile: profile, context: modelContext)
        }
        savedTick += 1
        page = .program
    }

    // MARK: Bottom button

    private func bottomButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(18, .medium, relativeTo: .body))
                .foregroundStyle(enabled ? Theme.onAccent : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(enabled ? Theme.accent : Theme.raised2.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

enum GoalFlowColors {
    static let green = Theme.hex(0x203529)
    static let header = Theme.hex(0x333333)
    static let band = Theme.hex(0x2C4035)
}

/// Back chevron, centered title, 4 pt progress bar (shared look with the program wizard).
struct GoalFlowHeader: View {
    let title: String
    let progress: Double
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Text(title)
                    .font(Theme.font(20, .regular, relativeTo: .title3))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 48)
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retour")
                    Spacer()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.raised2)
                    Rectangle().fill(Theme.textPrimary)
                        .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
            .animation(.quick, value: progress)
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }
}

struct GoalFlowStatCard: View {
    let value: String
    let label: String
    let background: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.font(21, .bold, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.textBody)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Summary card: colored header row (bold title, value right), bordered body text.
struct GoalFlowSummaryCard: View {
    let title: String
    let value: String
    let header: Color
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(Theme.font(19, .bold, relativeTo: .title3))
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                Text(value)
                    .font(Theme.font(19, .regular, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(header)
            if let text {
                Text(text)
                    .font(Theme.font(17, .regular, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(header, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal weight ruler: drag to change the value (0.1 kg steps), ticks every 0.5 kg, labels
/// every 5 kg, white-green center marker, green band between the current weight and the value.
struct GoalWeightRuler: View {
    @Binding var value: Double
    let currentKg: Double

    private static let pointsPerKg: CGFloat = 64
    @State private var dragStart: Double?

    var body: some View {
        Canvas { context, size in
            let center = size.width / 2
            let baseY = size.height
            let band = CGFloat(18) + 30
            func x(_ kg: Double) -> CGFloat { center + CGFloat(kg - value) * Self.pointsPerKg }
            // Band between the current weight and the target.
            let a = x(currentKg), b = center
            let bandRect = CGRect(x: min(a, b), y: baseY - band + 18, width: abs(a - b), height: band - 18)
            context.fill(Path(bandRect), with: .color(GoalFlowColors.band))
            let lowKg = value - Double(center / Self.pointsPerKg) - 1
            let highKg = value + Double(center / Self.pointsPerKg) + 1
            var tick = (lowKg * 2).rounded(.down) / 2
            while tick <= highKg {
                let px = x(tick)
                let isMajor = abs(tick.truncatingRemainder(dividingBy: 5)) < 0.01
                let h: CGFloat = isMajor ? 52 : 36
                var path = Path()
                path.move(to: CGPoint(x: px, y: baseY))
                path.addLine(to: CGPoint(x: px, y: baseY - h))
                context.stroke(path, with: .color(Theme.textTertiary.opacity(isMajor ? 0.9 : 0.6)), lineWidth: 1)
                if isMajor {
                    context.draw(Text(Formatters.number(tick, maxFractionDigits: 0))
                                    .font(Theme.font(12, .regular, relativeTo: .caption))
                                    .foregroundColor(Theme.textSecondary),
                                 at: CGPoint(x: px, y: baseY - h - 12))
                }
                tick += 0.5
            }
            // Current weight marker (thin green) and the center marker.
            var current = Path()
            current.move(to: CGPoint(x: a, y: baseY)); current.addLine(to: CGPoint(x: a, y: baseY - 44))
            context.stroke(current, with: .color(Theme.good), lineWidth: 2)
            var marker = Path()
            marker.move(to: CGPoint(x: center, y: baseY)); marker.addLine(to: CGPoint(x: center, y: 0))
            context.stroke(marker, with: .color(Theme.good), lineWidth: 2)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if dragStart == nil { dragStart = value }
                    let raw = (dragStart ?? value) - Double(drag.translation.width / Self.pointsPerKg)
                    value = min(max((raw * 10).rounded() / 10, 30), 250)
                }
                .onEnded { _ in dragStart = nil }
        )
        .sensoryFeedback(.selection, trigger: (value * 2).rounded())
        .accessibilityElement()
        .accessibilityLabel("Poids cible")
        .accessibilityValue("\(Formatters.number(value, maxFractionDigits: 1)) kilos")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = ((value + 0.5) * 10).rounded() / 10
            case .decrement: value = ((value - 0.5) * 10).rounded() / 10
            @unknown default: break
            }
        }
    }
}

/// Rate label pill, slider with the recommended range in green, kg / % BW per week and month.
struct GoalRateEditor: View {
    let goal: WeightGoal
    @Binding var ratePercent: Double
    let weightKg: Double

    @State private var kgWeekText = ""
    @State private var pctWeekText = ""
    @State private var kgMonthText = ""
    @State private var pctMonthText = ""
    @FocusState private var focused: Field?

    enum Field: Hashable { case kgWeek, pctWeek, kgMonth, pctMonth }

    private var range: ClosedRange<Double> { goal == .gain ? 0.05...0.75 : 0.1...1.5 }
    private var recommended: ClosedRange<Double> { goal == .gain ? 0.1...0.35 : 0.25...0.9 }

    private var label: String {
        if goal == .gain {
            switch ratePercent {
            case ..<0.1: return "Lent"
            case ..<0.35: return "Standard (recommandé)"
            default: return "Rapide"
            }
        }
        switch ratePercent {
        case ..<0.25: return "Lent"
        case ..<0.5: return "Modéré (recommandé)"
        case ..<0.9: return "Standard"
        default: return "Rapide"
        }
    }

    var body: some View {
        VStack(spacing: 26) {
            Text(label)
                .font(Theme.font(17, .bold, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(GoalFlowColors.green, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            slider
                .frame(height: 34)
                .padding(.horizontal, 10)
            VStack(spacing: 10) {
                row(sign: goal == .lose ? "−" : "+", kg: $kgWeekText, pct: $pctWeekText,
                    kgField: .kgWeek, pctField: .pctWeek, period: "par semaine")
                row(sign: goal == .lose ? "−" : "+", kg: $kgMonthText, pct: $pctMonthText,
                    kgField: .kgMonth, pctField: .pctMonth, period: "par mois")
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { refreshTexts(except: nil) }
        .onChange(of: ratePercent) { _, _ in refreshTexts(except: focused) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focused = nil }
            }
        }
    }

    private var slider: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised2).frame(height: 3)
                Capsule().fill(Theme.good)
                    .frame(width: x(recommended.upperBound, w) - x(recommended.lowerBound, w), height: 3)
                    .offset(x: x(recommended.lowerBound, w))
                Circle().fill(Theme.accent)
                    .frame(width: 32, height: 32)
                    .offset(x: x(ratePercent, w) - 16)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                focused = nil
                let fraction = min(max(drag.location.x / w, 0), 1)
                let v = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
                ratePercent = (v * 100).rounded() / 100
            })
        }
        .sensoryFeedback(.selection, trigger: (ratePercent * 20).rounded())
        .accessibilityElement()
        .accessibilityLabel("Rythme")
        .accessibilityValue("\(Formatters.number(ratePercent, maxFractionDigits: 2)) pour cent du poids par semaine")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: ratePercent = min(range.upperBound, ((ratePercent + 0.05) * 100).rounded() / 100)
            case .decrement: ratePercent = max(range.lowerBound, ((ratePercent - 0.05) * 100).rounded() / 100)
            @unknown default: break
            }
        }
    }

    /// Horizontal position of a rate on a slider `width` wide.
    private func x(_ v: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((min(max(v, range.lowerBound), range.upperBound) - range.lowerBound)
                / (range.upperBound - range.lowerBound)) * width
    }

    private func row(sign: String, kg: Binding<String>, pct: Binding<String>, kgField: Field, pctField: Field,
                     period: String) -> some View {
        HStack(spacing: 10) {
            Text(sign)
                .font(Theme.font(20, .regular, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 22)
            box(kg, unit: "kg", field: kgField)
            box(pct, unit: "% PC", field: pctField)
            Text(period)
                .font(Theme.font(17, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func box(_ text: Binding<String>, unit: String, field: Field) -> some View {
        HStack(spacing: 4) {
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .focused($focused, equals: field)
                .font(Theme.font(19, .regular, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .onChange(of: text.wrappedValue) { _, newValue in
                    guard focused == field else { return }
                    apply(newValue, field: field)
                }
            Text(unit)
                .font(Theme.font(17, .regular, relativeTo: .body))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .frame(width: 112)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(focused == field ? Theme.textPrimary : Theme.hex(0x3B3B3B), lineWidth: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = field }
    }

    private func apply(_ text: String, field: Field) {
        guard let v = CoachingFormat.parse(text), v > 0, weightKg > 0 else { return }
        let percent: Double
        switch field {
        case .kgWeek: percent = v / weightKg * 100
        case .pctWeek: percent = v
        case .kgMonth: percent = v / 4 / weightKg * 100
        case .pctMonth: percent = v / 4
        }
        ratePercent = min(max((percent * 100).rounded() / 100, range.lowerBound), range.upperBound)
    }

    private func refreshTexts(except field: Field?) {
        let kgWeek = ratePercent / 100 * weightKg
        if field != .kgWeek { kgWeekText = Formatters.number(kgWeek, maxFractionDigits: 2) }
        if field != .pctWeek { pctWeekText = Formatters.number(ratePercent, maxFractionDigits: 2) }
        if field != .kgMonth { kgMonthText = Formatters.number(kgWeek * 4, maxFractionDigits: 1) }
        if field != .pctMonth { pctMonthText = Formatters.number(ratePercent * 4, maxFractionDigits: 2) }
    }
}

/// Original flat illustration for the goal intro: night sky, layered hills in the macro colors
/// and a scale with a rising (or falling) arrow. Drawn with shapes, no external artwork.
struct GoalFlowIllustration: View {
    let goal: WeightGoal

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Theme.hex(0x0E1526)
                Circle().fill(Theme.calories.opacity(0.18)).frame(width: w * 0.9).position(x: w * 0.5, y: h * 0.38)
                Circle().fill(Theme.calories.opacity(0.28)).frame(width: w * 0.6).position(x: w * 0.5, y: h * 0.38)
                ForEach(0..<14, id: \.self) { i in
                    Circle().fill(Color.white.opacity(0.7))
                        .frame(width: i % 3 == 0 ? 3 : 2)
                        .position(x: w * CGFloat((i * 37) % 100) / 100, y: h * CGFloat(8 + (i * 23) % 40) / 100)
                }
                hill(w: w, h: h, top: 0.62, peak: 0.25, color: Theme.carbs.opacity(0.85))
                hill(w: w, h: h, top: 0.72, peak: 0.7, color: Theme.protein)
                hill(w: w, h: h, top: 0.84, peak: 0.45, color: Theme.fat)
                Image(systemName: goal == .gain ? "arrow.up.circle.fill" : goal == .maintain ? "equal.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(Theme.onAccent, Theme.accent)
                    .position(x: w * 0.5, y: h * 0.4)
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private func hill(w: CGFloat, h: CGFloat, top: CGFloat, peak: CGFloat, color: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h * (top + 0.08)))
            p.addQuadCurve(to: CGPoint(x: w, y: h * (top + 0.05)),
                           control: CGPoint(x: w * peak, y: h * (top - 0.12)))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
        .fill(color)
    }
}
