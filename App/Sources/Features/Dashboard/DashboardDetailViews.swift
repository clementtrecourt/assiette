import SwiftData
import SwiftUI

// Screens pushed from the dashboard cards (no NavigationStack: they live in DashboardView's).

/// Shared scroll layout of the detail screens.
private struct DashboardDetailScaffold<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Big value of a detail screen: caps caption, number + unit, detail line.
private struct DashboardDetailHeadline: View {
    let caption: String
    let value: String
    var unit: String = ""
    var valueColor: Color = Theme.textPrimary
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardCapsLabel(text: caption)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.font(34, .bold, relativeTo: .largeTitle))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.font(15, .medium, relativeTo: .body))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let detail {
                Text(detail)
                    .font(Theme.callout)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Card wrapper for a chart or a list of stats.
private struct DashboardDetailCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }
}

/// "Label ……… value" row inside a detail card, with an optional hairline above.
private struct DashboardStatRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    var divider = true

    var body: some View {
        VStack(spacing: 0) {
            if divider {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.hairline)
            }
            HStack {
                Text(label)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textBody)
                Spacer(minLength: 8)
                Text(value)
                    .font(Theme.headline)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 11)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardExplanation: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Chart placeholder when the range holds too little data.
private struct DashboardChartPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.callout)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 160)
    }
}

// MARK: - Dépense

struct DashboardExpenditureDetail: View {
    let snapshot: CoachingSnapshot
    let today: Date

    @AppStorage("dashboard.detailRangeDays") private var rangeRaw = ProgressRange.month.rawValue

    var body: some View {
        let range = ProgressRange(rawValue: rangeRaw) ?? .month
        let start = range.startDate(today: today)
        let points = snapshot.days
            .filter { $0.date >= start }
            .map { ProgressChartPoint(date: $0.date, value: $0.expenditure) }
        let weekChange = snapshot.expenditureChange(days: 7)

        DashboardDetailScaffold(title: "Dépense") {
            ProgressRangeChips(rangeRaw: $rangeRaw)
            DashboardDetailHeadline(
                caption: "Dépense estimée",
                value: DashboardFormat.kcalNumber(snapshot.isEmpty ? nil : snapshot.expenditure),
                unit: "kcal/j",
                detail: weekChange.map { "\(DashboardFormat.signed($0)) kcal en 7 jours" }
            )
            DashboardDetailCard {
                if points.count < 2 {
                    DashboardChartPlaceholder(text: "Enregistrez vos repas et votre poids quelques jours pour voir l'évolution de votre dépense.")
                } else {
                    ProgressExpenditureChart(points: points, startDate: start,
                                             endDate: today.adding(days: 1).startOfDay)
                }
            }
            if let first = points.first, let last = points.last, points.count >= 2 {
                DashboardDetailCard {
                    DashboardStatRow(label: "Début de période", value: Formatters.kcal(first.value), divider: false)
                    DashboardStatRow(label: "Aujourd'hui", value: Formatters.kcal(last.value))
                    DashboardStatRow(label: "Évolution", value: "\(DashboardFormat.signed(last.value - first.value)) kcal")
                }
            }
            DashboardExplanation(text: "Estimation de l'énergie que vous dépensez chaque jour, calculée à partir de vos apports enregistrés et de l'évolution de votre poids tendance. Elle s'ajuste un peu chaque jour.")
        }
    }
}

// MARK: - Poids tendance

struct DashboardWeightTrendDetail: View {
    let snapshot: CoachingSnapshot
    let targetKg: Double?
    let today: Date

    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @AppStorage("dashboard.detailRangeDays") private var rangeRaw = ProgressRange.month.rawValue
    @State private var showingAdd = false

    var body: some View {
        let range = ProgressRange(rawValue: rangeRaw) ?? .month
        let start = range.startDate(today: today)
        let trend = snapshot.days
            .filter { $0.date >= start }
            .compactMap { day in day.smoothedTrendKg.map { ProgressChartPoint(date: day.date, value: $0) } }
        let scale = ProgressStats.dailyScaleWeights(weights, from: start)
        let rangeChange: Double? = trend.count >= 2 ? trend[trend.count - 1].value - trend[0].value : nil

        DashboardDetailScaffold(title: "Poids tendance") {
            ProgressRangeChips(rangeRaw: $rangeRaw)
            DashboardDetailHeadline(
                caption: "Tendance actuelle",
                value: snapshot.trendKg.map { Formatters.number($0, maxFractionDigits: 1) } ?? "–",
                unit: "kg",
                detail: rangeChange.map { "\(ProgressStats.signedKg($0)) sur les \(range.longLabel.lowercased())" }
            )
            DashboardDetailCard {
                if trend.isEmpty && scale.isEmpty {
                    DashboardChartPlaceholder(text: "Aucune pesée sur les \(range.longLabel.lowercased()).")
                } else {
                    ProgressWeightTrendChart(trend: trend, scale: scale, targetKg: targetKg,
                                             startDate: start, endDate: today.adding(days: 1).startOfDay)
                }
            }
            DashboardDetailCard {
                DashboardStatRow(label: "Dernière pesée",
                                 value: weights.last.map { ProgressStats.kg($0.kg) } ?? "–", divider: false)
                DashboardStatRow(label: "Évolution sur 7 jours",
                                 value: snapshot.trendChange(days: 7).map { ProgressStats.signedKg($0) } ?? "–")
                if let targetKg {
                    DashboardStatRow(label: "Poids visé", value: ProgressStats.kg(targetKg))
                }
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.hairline)
                NavigationLink(value: DashboardRoute.weights) {
                    HStack {
                        Text("Toutes les pesées")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textBody)
                        Spacer()
                        Text("\(weights.count)")
                            .font(Theme.callout)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textQuaternary)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            DashboardExplanation(text: "La tendance lisse les variations d'un jour à l'autre (eau, sel, digestion) pour montrer l'évolution réelle de votre poids. Elle est révisée à chaque nouvelle pesée.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Ajouter une pesée", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            ProgressAddWeightSheet(initialKg: weights.last?.kg)
        }
    }
}

// MARK: - Objectif

struct DashboardGoalDetail: View {
    let progress: DashboardGoalProgress?
    let snapshot: CoachingSnapshot
    let weights: [WeightEntry]
    let goal: WeightGoal
    let today: Date

    @Environment(AppState.self) private var appState

    var body: some View {
        DashboardDetailScaffold(title: "Objectif") {
            if let progress {
                content(progress)
            } else {
                DashboardDetailCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goal == .maintain ? "Objectif de maintien" : "Aucun poids visé")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(goal == .maintain
                             ? "En maintien, votre programme garde votre poids tendance stable. La progression s'affiche quand vous visez une perte ou une prise de poids."
                             : "Indiquez un poids visé dans votre programme pour suivre votre progression.")
                            .font(Theme.callout)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button {
                appState.selectedTab = .program
            } label: {
                Text("Ouvrir le programme")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func content(_ progress: DashboardGoalProgress) -> some View {
        let start = progress.startDate.startOfDay
        let trend = snapshot.days
            .filter { $0.date >= start }
            .compactMap { day in day.smoothedTrendKg.map { ProgressChartPoint(date: day.date, value: $0) } }
        let scale = ProgressStats.dailyScaleWeights(weights, from: start)
        let percent = Formatters.number(progress.fraction * 100, maxFractionDigits: 0)

        DashboardDetailHeadline(
            caption: "Progression",
            value: percent,
            unit: "%",
            valueColor: progress.isReached ? Theme.good : Theme.textPrimary,
            detail: progress.isReached
                ? "Poids visé atteint"
                : "\(ProgressStats.kg(progress.remainingKg)) avant \(ProgressStats.kg(progress.targetKg))"
        )
        DashboardMeter(fraction: progress.fraction, color: Theme.good, height: 8)
        DashboardDetailCard {
            DashboardStatRow(label: "Départ (\(Formatters.shortDate(progress.startDate)))",
                             value: ProgressStats.kg(progress.startKg), divider: false)
            DashboardStatRow(label: "Poids tendance", value: ProgressStats.kg(progress.currentKg))
            DashboardStatRow(label: "Poids visé", value: ProgressStats.kg(progress.targetKg))
            DashboardStatRow(label: "Déjà parcouru", value: ProgressStats.signedKg(progress.currentKg - progress.startKg))
            DashboardStatRow(label: "Durée", value: DashboardFormat.since(progress.startDate, today: today))
        }
        if trend.count >= 2 {
            DashboardDetailCard {
                ProgressWeightTrendChart(trend: trend, scale: scale, targetKg: progress.targetKg,
                                         startDate: start, endDate: today.adding(days: 1).startOfDay)
            }
        }
        DashboardExplanation(text: "La progression est mesurée sur le poids tendance, depuis le début de l'objectif actuel.")
    }
}

// MARK: - Bilan énergétique

struct DashboardEnergyBalanceDetail: View {
    let snapshot: CoachingSnapshot
    let todayIntake: Double
    let today: Date

    @AppStorage("dashboard.detailRangeDays") private var rangeRaw = ProgressRange.month.rawValue

    var body: some View {
        let range = ProgressRange(rawValue: rangeRaw) ?? .month
        let start = range.startDate(today: today)
        let points = DashboardData.balancePoints(snapshot: snapshot, count: range.days, today: today,
                                                 todayIntake: todayIntake)
        let balance = snapshot.averageBalance(lastDays: range.days)
        let intake = snapshot.averageIntake(lastDays: range.days)
        let past = points.filter { !$0.isPartial }
        let averageExpenditure = past.isEmpty ? nil : past.map(\.expenditure).reduce(0, +) / Double(past.count)

        DashboardDetailScaffold(title: "Bilan énergétique") {
            ProgressRangeChips(rangeRaw: $rangeRaw)
            DashboardDetailHeadline(
                caption: balance.map { $0 < 0 ? "Déficit moyen" : "Surplus moyen" } ?? "Bilan moyen",
                value: balance.map { DashboardFormat.signed($0) } ?? "–",
                unit: "kcal/j",
                detail: intake.logged > 0
                    ? "sur \(intake.logged) jour\(intake.logged > 1 ? "s" : "") suivi\(intake.logged > 1 ? "s" : "")"
                    : "Aucun jour complet suivi"
            )
            DashboardDetailCard {
                if points.isEmpty {
                    DashboardChartPlaceholder(text: "Enregistrez vos repas pour comparer vos apports à votre dépense.")
                } else {
                    ProgressEnergyBalanceChart(points: points, startDate: start,
                                               endDate: today.adding(days: 1).startOfDay)
                }
            }
            DashboardDetailCard {
                DashboardStatRow(label: "Apport moyen",
                                 value: intake.average.map { Formatters.kcal($0) } ?? "–", divider: false)
                DashboardStatRow(label: "Dépense moyenne",
                                 value: averageExpenditure.map { Formatters.kcal($0) } ?? "–")
                DashboardStatRow(label: "Jours suivis", value: "\(intake.logged) / \(max(range.days - 1, 1))")
            }
            DashboardExplanation(text: "Apports enregistrés comparés à la dépense estimée. Aujourd'hui (journée en cours), les jours non suivis et les périodes d'exception ne comptent pas dans les moyennes.")
        }
    }
}

// MARK: - Nutrition du jour

/// Today's targets (energy, G, P, L, fibre) then every nutrient summed over the day.
struct DashboardNutrientsView: View {
    let totals: NutrientValues
    let targets: DashboardTargets
    let entryCount: Int

    var body: some View {
        DashboardDetailScaffold(title: "Nutrition du jour") {
            if entryCount == 0 {
                ThemedUnavailableView(title: "Aucun aliment",
                                      systemImage: "fork.knife",
                                      description: "Ajoutez des aliments au journal pour voir le détail de vos nutriments.")
                    .frame(minHeight: 320)
            } else {
                DashboardDetailCard {
                    VStack(spacing: 14) {
                        ForEach([NutrientKey.calories] + Theme.macroOrder + [NutrientKey.dietaryFiber], id: \.self) { key in
                            targetRow(key)
                        }
                    }
                }
                DashboardDetailCard {
                    NutritionTableView(values: totals, showDailyPercent: true)
                }
                DashboardExplanation(text: "Les pourcentages du détail se basent sur les apports de référence pour un adulte. Les valeurs inconnues de certains aliments ne sont pas comptées.")
                AttributionFooter(includeOpenFoodFacts: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func targetRow(_ key: NutrientKey) -> some View {
        let value = totals.value(key)
        let target = targets.value(for: key)
        let color = key == .dietaryFiber ? Theme.good : Theme.color(for: key)
        let unit = key == .calories ? "kcal" : key.unit
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(key.label)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text("\(Formatters.number(value, maxFractionDigits: 0)) / \(Formatters.number(target, maxFractionDigits: 0)) \(unit)")
                    .font(Theme.callout)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                Text(target > 0 ? Formatters.percent(value / target) : "–")
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            ProgressBar(value: value, total: target, color: color, height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}
