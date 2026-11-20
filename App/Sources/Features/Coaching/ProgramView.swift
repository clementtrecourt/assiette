import SwiftData
import SwiftUI

// CONTRACT (used by RootView):
//   ProgramView()                       the "Programme" tab root (owns its NavigationStack)
//   CoachingCheckInView(profile:)       weekly check-in sheet (presented when appState.showingCheckIn),
//                                       in CoachingCheckInView.swift

/// "Programme" tab: check-in countdown, current program (week of daily targets), goal,
/// goal history, exception periods and check-in history.
struct ProgramView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    ProgramContent(profile: profile)
                } else {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background.ignoresSafeArea())
                        .task { _ = UserProfile.current(in: modelContext) }
                }
            }
            .navigationTitle("Programme")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Sheets presented by the Programme tab.
private enum ProgramSheet: Identifiable {
    case goal(CoachingGoalEditor.Focus?)
    case targets
    case exception(ExceptionPeriod?)

    var id: String {
        switch self {
        case .goal(let focus): return "goal-\(String(describing: focus))"
        case .targets: return "targets"
        case .exception(let period): return "exception-\(period?.id.uuidString ?? "new")"
        }
    }
}

/// One goal of the history: from the program change that set it to the next goal change.
private struct ProgramGoalSegment: Identifiable {
    var goal: WeightGoal
    var start: Date
    var end: Date?
    var startKg: Double?
    var endKg: Double?

    var id: String { "\(start.timeIntervalSince1970)-\(goal.rawValue)" }
    var isCurrent: Bool { end == nil }

    /// Whether the weight moved in the goal's direction (nil while running or without weights).
    var reached: Bool? {
        guard !isCurrent, let startKg, let endKg else { return nil }
        switch goal {
        case .lose: return endKg < startKg
        case .gain: return endKg > startKg
        case .maintain: return abs(endKg - startKg) <= EngineParameters.calibrated.maintenanceToleranceKg
        }
    }
}

private struct ProgramContent: View {
    let profile: UserProfile

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CoachingCheckIn.date, order: .reverse) private var checkIns: [CoachingCheckIn]
    @Query(sort: \ExceptionPeriod.start, order: .reverse) private var exceptions: [ExceptionPeriod]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @AppStorage(CoachingSettings.collaborativeKey) private var collaborative = false

    @State private var sheet: ProgramSheet?
    @State private var trendKg: Double?
    @State private var deleteTick = 0
    /// Global x of the hero header (List header inset), see the "En cours" section header.
    @State private var heroMinX: CGFloat = 16

    private static let visibleCheckIns = 5

    private var mode: CoachingMode { CoachingMode.current(profile: profile, collaborative: collaborative) }
    private var currentKg: Double { trendKg ?? weights.last?.kg ?? profile.weightKg }
    private var weeklyCheckIns: [CoachingCheckIn] { checkIns.filter(\.isWeekly) }

    var body: some View {
        List {
            Section {
                programCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                // Hero in the section header: headers are not clipped to the inset card shape,
                // so its background runs edge to edge and under the status bar.
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        header
                        countdown
                            .padding(.bottom, 20)
                    }
                    .background {
                        Theme.raised
                            .padding(.horizontal, -60)
                            .padding(.top, -600)
                    }
                    CoachingSectionTitle("En cours")
                        .padding(.leading, 4)
                        .padding(.top, 28)
                        .padding(.bottom, 8)
                }
                // Keeps the content on the 16 pt screen margin whatever inset the header gets.
                .padding(.horizontal, max(0, 16 - heroMinX))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { heroMinX = geo.frame(in: .global).minX }
                            .onChange(of: geo.frame(in: .global).minX) { _, x in heroMinX = x }
                    }
                }
                .textCase(nil)
                .listRowInsets(EdgeInsets())
            }

            Section {
                goalCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(goalSegments.reversed()) { segment in
                    goalHistoryRow(segment)
                }
                .programRow()
            } header: {
                CoachingSectionTitle("Historique des objectifs")
            }

            exceptionsSection

            checkInsSection

            Section {
                Button {
                    appState.showingCheckIn = true
                } label: {
                    Label("Faire le bilan maintenant", systemImage: "checklist")
                        .font(Theme.font(15, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.borderless)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text(footerText)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 6)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .themedBackground()
        .font(Theme.body)
        .task(id: reloadKey) { reloadTrend() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .goal(let focus):
                NavigationStack {
                    CoachingGoalEditor(profile: profile, initialFocus: focus, isSheet: true)
                }
            case .targets:
                CoachingTargetsEditor(profile: profile)
            case .exception(let period):
                CoachingExceptionEditor(period: period)
            }
        }
        .sensoryFeedback(.warning, trigger: deleteTick)
    }

    /// Changes when something the trend depends on changes (check-in, weigh-in, exceptions).
    private var reloadKey: String {
        let checkIn = profile.lastCheckInDate?.timeIntervalSince1970 ?? 0
        return "\(checkIn)|\(weights.count)|\(weights.last?.kg ?? 0)|\(exceptions.count)|\(profile.calorieTarget)"
    }

    private func reloadTrend() {
        trendKg = CoachingService.snapshot(profile: profile, context: modelContext).trendKg
    }

    // MARK: - Header & countdown

    private var header: some View {
        HStack(alignment: .center) {
            Text("PROGRAMME")
                .font(Theme.screenTitle())
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel("Programme, \(CoachingFormat.goalTitle(profile.goal)), \(mode.adjective)")
            Spacer()
            Menu {
                Button {
                    appState.showingCheckIn = true
                } label: {
                    Label("Faire le bilan maintenant", systemImage: "checklist")
                }
                Button {
                    sheet = .goal(.target)
                } label: {
                    Label("Nouveau programme", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    sheet = .exception(nil)
                } label: {
                    Label("Ajouter une exception", systemImage: "pause.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.raised2, in: Circle())
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityLabel("Options du programme")
        }
        .padding(.top, -4)
    }

    private var isDue: Bool { CoachingService.isCheckInDue(profile: profile) }
    private var daysLeft: Int { CoachingService.daysUntilCheckIn(profile: profile) }

    /// Days of the current check-in week already elapsed (also shown in manual mode).
    private var filledDays: Int {
        isDue ? 7 : max(0, min(7, 7 - daysLeft))
    }

    private var countdown: some View {
        VStack(spacing: 10) {
            CoachingCountdownRing(filledDays: filledDays, goalProgress: goalProgress) {
                countdownCenter
            }
            .contentShape(Circle())
            .onTapGesture {
                if isDue { appState.showingCheckIn = true }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 16) {
                legendItem(icon: "Glyph-objectif", color: Theme.good, text: goalLegend)
                if mode != .manual {
                    legendItem(icon: "Glyph-bilan", color: Theme.textPrimary,
                               text: "Bilan le \(CoachingFormat.weekdayName(profile.checkInWeekday))")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 276)
    }

    @ViewBuilder
    private var countdownCenter: some View {
        VStack(spacing: 3) {
            if mode == .manual {
                Text(CoachingFormat.kcalNumber(profile.calorieTarget))
                    .font(Theme.screenTitle(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                ringDetail("kcal / jour")
            } else if isDue {
                Text("BILAN")
                    .font(Theme.screenTitle(26))
                    .foregroundStyle(Theme.textPrimary)
                Button {
                    appState.showingCheckIn = true
                } label: {
                    Text("Ouvrir")
                        .font(Theme.font(12, .bold, relativeTo: .caption))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            } else {

                Text(daysLeft > 1 ? "\(daysLeft) JOURS" : "1 JOUR")
                    .font(Theme.screenTitle(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ringDetail("avant le bilan")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    private func ringDetail(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(16, .regular, relativeTo: .callout))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func legendItem(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(icon).resizable().frame(width: 22, height: 22).foregroundStyle(color)
            Text(text)
                .font(Theme.font(17, .regular, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Goal progress

    private var goalProgress: Double? {
        let current = currentKg
        switch profile.goal {
        case .maintain:
            let target = profile.targetWeightKg ?? current
            let gap = abs(current - target)
            let tolerance = EngineParameters.calibrated.maintenanceToleranceKg
            return gap <= tolerance ? 1 : max(0, 1 - (gap - tolerance) / 3)
        case .lose, .gain:
            guard let target = profile.targetWeightKg,
                  let start = goalSegments.last?.startKg else { return nil }
            let total = target - start
            guard abs(total) > 0.05 else { return 1 }
            return min(max((current - start) / total, 0), 1)
        }
    }

    private var goalLegend: String {
        guard let progress = goalProgress else { return "Pas de poids visé" }
        if profile.goal == .maintain {
            return progress >= 1 ? "Dans la zone de maintien" : "Hors zone de maintien"
        }
        return "Objectif \(Formatters.percent(progress))"
    }

    // MARK: - Program card

    private var programSince: Date {
        checkIns.first?.date ?? profile.lastCheckInDate ?? profile.createdAt
    }

    private var programTitle: String {
        switch mode {
        case .coached: return "Programme coaché"
        case .collaborative: return "Programme collaboratif"
        case .manual: return "Programme manuel"
        }
    }

    /// Days of the current week (0 = Monday) covered by an exception period.
    private var excludedDays: Set<Int> {
        let today = Date.now.startOfDay
        let monday = today.adding(days: -CoachingFormat.mondayIndex(of: today))
        var result = Set<Int>()
        for index in 0..<7 {
            let day = monday.adding(days: index)
            if exceptions.contains(where: { $0.contains(day) }) { result.insert(index) }
        }
        return result
    }

    private var programCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoachingCardHeader(title: programTitle,
                               subtitle: "depuis le \(CoachingFormat.day(programSince))")
            CoachingWeekColumns(calories: profile.calorieTarget, carbs: profile.carbsTarget,
                                protein: profile.proteinTarget, fat: profile.fatTarget,
                                todayIndex: CoachingFormat.mondayIndex(of: .now),
                                excludedDays: excludedDays)
                .padding(.top, 22)
            cardHairline
                .padding(.top, 22)
            VStack(alignment: .leading, spacing: 6) {
                    Button {
                        sheet = .goal(.target)
                    } label: {
                        CoachingChipLabel(title: "Nouveau programme", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                HStack(spacing: 6) {
                    Button {
                        sheet = .targets
                    } label: {
                        CoachingChipLabel(title: "Modifier", systemImage: "pencil")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        sheet = .exception(nil)
                    } label: {
                        CoachingChipLabel(title: "Exception", systemImage: "pause.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .themedCard()
    }

    private var cardHairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: Theme.hairline)
    }

    // MARK: - Goal card

    private var goalCardTitle: String {
        switch profile.goal {
        case .lose: return "Objectif de perte"
        case .maintain: return "Objectif de maintien"
        case .gain: return "Objectif de prise"
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoachingCardHeader(title: goalCardTitle,
                               subtitle: goalSegments.last.map { "depuis le \(CoachingFormat.day($0.start))" })
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(goalFigures.enumerated()), id: \.offset) { _, figure in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(figure.value)
                                .font(Theme.font(19, .bold, relativeTo: .title3))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(figure.unit)
                                .font(Theme.font(11, .medium, relativeTo: .caption2))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(figure.label)
                            .font(Theme.font(11, .regular, relativeTo: .caption2))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 10)
            cardHairline
                .padding(.top, 10)
            HStack(spacing: 6) {
                Button {
                    sheet = .goal(.target)
                } label: {
                    CoachingChipLabel(title: "Nouvel objectif", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Button {
                    sheet = .goal(profile.goal == .maintain ? .target : .rate)
                } label: {
                    CoachingChipLabel(title: "Modifier", systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 0)
            }
            .padding(.top, 9)
        }
        .padding(12)
        .themedCard()
    }

    private struct GoalFigure {
        var value: String
        var unit: String
        var label: String
    }

    private var goalFigures: [GoalFigure] {
        let target = profile.targetWeightKg.map { Formatters.number($0, maxFractionDigits: 1) } ?? "—"
        switch profile.goal {
        case .maintain:
            let reference = profile.targetWeightKg ?? currentKg
            return [
                GoalFigure(value: target, unit: profile.targetWeightKg == nil ? "" : "kg", label: "poids visé"),
                GoalFigure(value: Formatters.number(currentKg, maxFractionDigits: 1), unit: "kg", label: "tendance"),
                GoalFigure(value: CoachingFormat.signed(currentKg - reference, digits: 1), unit: "kg", label: "écart"),
            ]
        case .lose, .gain:
            let sign: Double = profile.goal == .lose ? -1 : 1
            let rate = profile.effectiveRatePercent
            let kg = CoachingService.weeklyKg(ratePercent: rate, weightKg: profile.weightKg)
            return [
                GoalFigure(value: target, unit: profile.targetWeightKg == nil ? "" : "kg", label: "poids visé"),
                GoalFigure(value: CoachingFormat.signed(sign * kg, digits: 2), unit: "kg", label: "par semaine"),
                GoalFigure(value: CoachingFormat.signed(sign * rate, digits: 2), unit: "%", label: "par semaine"),
            ]
        }
    }

    // MARK: - Goal history

    /// Goal segments, oldest first, derived from the "program" history rows (a new segment starts
    /// when the goal type changes). Without history, one segment since the profile creation.
    private var goalSegments: [ProgramGoalSegment] {
        let rows = checkIns.filter { !$0.isWeekly }.sorted { $0.date < $1.date }
        var segments: [ProgramGoalSegment] = []
        for row in rows where segments.last?.goal != row.goal {
            segments.append(ProgramGoalSegment(goal: row.goal, start: row.date, end: nil,
                                               startKg: row.trendKg ?? row.scaleKg, endKg: nil))
        }
        if segments.isEmpty || segments.last?.goal != profile.goal {
            let start = segments.isEmpty ? profile.createdAt.startOfDay : (rows.last?.date ?? .now.startOfDay)
            let startKg = segments.isEmpty ? (weights.first?.kg ?? profile.weightKg) : currentKg
            segments.append(ProgramGoalSegment(goal: profile.goal, start: start, end: nil,
                                               startKg: startKg, endKg: nil))
        }
        for index in segments.indices {
            if index + 1 < segments.count {
                segments[index].end = segments[index + 1].start
                segments[index].endKg = segments[index + 1].startKg
            } else {
                segments[index].endKg = currentKg
            }
        }
        return segments
    }

    private func goalHistoryRow(_ segment: ProgramGoalSegment) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(segmentDates(segment))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 4) {
                    if let startKg = segment.startKg {
                        Text(CoachingFormat.kg(startKg))
                        if !segment.isCurrent, let endKg = segment.endKg {
                            Text("→").foregroundStyle(Theme.textTertiary)
                            Text(CoachingFormat.kg(endKg))
                        }
                    } else {
                        Text("—")
                    }
                }
                .font(Theme.font(15, .bold, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Text(CoachingFormat.goalShort(segment.goal))
                if segment.isCurrent {
                    Image(systemName: "hourglass")
                } else if segment.reached == true {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.good)
                }
            }
            .font(Theme.font(12, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func segmentDates(_ segment: ProgramGoalSegment) -> String {
        guard let end = segment.end else { return "\(CoachingFormat.dayYear(segment.start)) → en cours" }
        let sameYear = Calendar.current.isDate(segment.start, equalTo: end, toGranularity: .year)
        let start = sameYear ? CoachingFormat.day(segment.start) : CoachingFormat.dayYear(segment.start)
        return "\(start) → \(CoachingFormat.dayYear(end))"
    }

    // MARK: - Exceptions

    private var exceptionsSection: some View {
        Section {
            ForEach(exceptions) { period in
                Button {
                    sheet = .exception(period)
                } label: {
                    exceptionRow(period)
                }
                .buttonStyle(.borderless)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(period)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
            .programRow()

            Button {
                sheet = .exception(nil)
            } label: {
                Label("Ajouter une exception", systemImage: "plus")
                    .font(Theme.font(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.borderless)
            .programRow()
        } header: {
            CoachingSectionTitle("Exceptions")
        } footer: {
            if exceptions.isEmpty {
                Text("Opération, maladie, voyage… Les jours d'une exception sont ignorés par l'estimation de la dépense.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func exceptionRow(_ period: ExceptionPeriod) -> some View {
        let today = Date.now.startOfDay
        let status: String
        if period.contains(today) {
            status = "Dépense figée"
        } else if period.start > today {
            status = "À venir"
        } else {
            status = "Terminée"
        }
        let sameYear = Calendar.current.isDate(period.start, equalTo: period.end, toGranularity: .year)
        let dates = period.start == period.end
            ? CoachingFormat.dayYear(period.start)
            : "\(sameYear ? CoachingFormat.day(period.start) : CoachingFormat.dayYear(period.start)) → \(CoachingFormat.dayYear(period.end))"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dates)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                Text(period.note.isEmpty ? "Sans note" : period.note)
                    .font(Theme.font(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(period.note.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Text(status)
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func delete(_ period: ExceptionPeriod) {
        modelContext.delete(period)
        try? modelContext.save()
        deleteTick += 1
    }

    // MARK: - Check-ins

    private var checkInsSection: some View {
        Section {
            if weeklyCheckIns.isEmpty {
                Text("Aucun bilan pour l'instant. Le premier aura lieu le \(CoachingFormat.weekdayDay(CoachingService.nextCheckInDate(profile: profile))).")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .programRow()
            } else {
                ForEach(weeklyCheckIns.prefix(Self.visibleCheckIns)) { checkIn in
                    ProgramCheckInRow(checkIn: checkIn, previous: previousTarget(before: checkIn))
                }
                .programRow()
                if weeklyCheckIns.count > Self.visibleCheckIns {
                    NavigationLink {
                        ProgramCheckInHistoryView(checkIns: checkIns)
                    } label: {
                        Text("Tout voir (\(weeklyCheckIns.count))")
                            .font(Theme.font(14, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .programRow()
                }
            }
        } header: {
            CoachingSectionTitle("Bilans")
        }
    }

    private func previousTarget(before checkIn: CoachingCheckIn) -> Double? {
        ProgramCheckInRow.previousTarget(before: checkIn, in: checkIns)
    }

    private var footerText: String {
        switch mode {
        case .coached:
            return "Chaque \(CoachingFormat.weekdayName(profile.checkInWeekday)), le bilan recalcule votre dépense à partir de vos repas et de vos pesées, puis ajuste vos objectifs."
        case .collaborative:
            return "Chaque \(CoachingFormat.weekdayName(profile.checkInWeekday)), le bilan propose de nouveaux objectifs que vous pouvez ajuster avant de les appliquer."
        case .manual:
            return "Mode manuel : vos objectifs ne changent pas automatiquement. Le bilan reste disponible pour voir votre dépense estimée."
        }
    }
}

/// One weekly check-in of the history ("lun. 16 nov." / "Dépense 2 435 · objectif 1 911" / "−79").
private struct ProgramCheckInRow: View {
    let checkIn: CoachingCheckIn
    /// Calorie target in force before this check-in.
    let previous: Double?

    /// Calorie target of the history row just before `checkIn` (`rows` sorted newest first).
    static func previousTarget(before checkIn: CoachingCheckIn, in rows: [CoachingCheckIn]) -> Double? {
        rows.first { $0.date < checkIn.date }?.calorieTarget
    }

    private var tag: String {
        guard let previous else { return "premier bilan" }
        let diff = checkIn.calorieTarget - previous
        return abs(diff) < 1 ? "inchangé" : "\(CoachingFormat.signed(diff)) kcal"
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(CoachingFormat.shortWeekdayDay(checkIn.date))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                Text("Dépense \(CoachingFormat.kcalNumber(checkIn.expenditure)) · objectif \(CoachingFormat.kcalNumber(checkIn.calorieTarget))")
                    .font(Theme.font(14, .medium, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Text(tag)
                .font(Theme.font(12, .medium, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// All weekly check-ins ("Tout voir").
private struct ProgramCheckInHistoryView: View {
    /// Every history row, newest first (program rows give the "previous target" of a check-in).
    let checkIns: [CoachingCheckIn]

    var body: some View {
        List {
            ForEach(checkIns.filter(\.isWeekly)) { checkIn in
                ProgramCheckInRow(checkIn: checkIn,
                                  previous: ProgramCheckInRow.previousTarget(before: checkIn, in: checkIns))
            }
            .programRow()
        }
        .listStyle(.insetGrouped)
        .themedBackground()
        .navigationTitle("Bilans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private extension View {
    /// Row of a Programme list group: raised background, hairline separators.
    func programRow() -> some View {
        listRowBackground(Theme.raised)
            .listRowSeparatorTint(Theme.separator)
    }
}
