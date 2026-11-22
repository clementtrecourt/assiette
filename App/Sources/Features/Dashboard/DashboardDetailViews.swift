import SwiftData
import SwiftUI

// Screens pushed from the dashboard cards (no NavigationStack: they live in DashboardView's).
// Dépense, Poids tendance, Objectif and Bilan énergétique follow the reference layout
// (see DashboardInsightViews.swift); Nutrition du jour keeps a simple list.

/// Shared scroll layout of the simple detail screens.
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
        .toolbarBackground(Theme.raised, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .principal) {
                InsightNavigationTitle(title: title)
            }
        }
    }
}

/// Card wrapper for a list of values.
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
    var height: CGFloat = 220

    var body: some View {
        Text(text)
            .font(Theme.callout)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// Range + averaging stored per screen, so each chart reopens as it was left.
private struct InsightSettings: DynamicProperty {
    @AppStorage private var rangeRaw: Int
    @AppStorage private var averagingRaw: String

    init(_ screen: String, defaultRange: InsightRange) {
        _rangeRaw = AppStorage(wrappedValue: defaultRange.rawValue, "insight.\(screen).range")
        _averagingRaw = AppStorage(wrappedValue: InsightAveraging.daily.rawValue, "insight.\(screen).averaging")
    }

    var range: Binding<InsightRange> {
        Binding(get: { InsightRange(rawValue: rangeRaw) ?? .month }, set: { rangeRaw = $0.rawValue })
    }

    var averaging: Binding<InsightAveraging> {
        Binding(get: { InsightAveraging(rawValue: averagingRaw) ?? .daily }, set: { averagingRaw = $0.rawValue })
    }
}

private extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}

private enum InsightText {
    static func kcal(_ value: Double) -> String { "\(DashboardFormat.signed(value)) kcal" }
    static func kg(_ value: Double) -> String { "\(DashboardFormat.signed(value, maxFractionDigits: 1)) kg" }
    static func kgValue(_ value: Double?) -> String { value.map { Formatters.number($0, maxFractionDigits: 1) } ?? "–" }
}

// MARK: - Dépense

struct DashboardExpenditureDetail: View {
    let snapshot: CoachingSnapshot
    let today: Date

    @Environment(AppState.self) private var appState
    private var settings = InsightSettings("expenditure", defaultRange: .month)
    @State private var fitToData = false

    init(snapshot: CoachingSnapshot, today: Date) {
        self.snapshot = snapshot
        self.today = today
    }

    var body: some View {
        let range = settings.range.wrappedValue
        let averaging = settings.averaging.wrappedValue
        let all = DashboardInsights.expenditurePoints(snapshot)
        let start = range.startDate(today: today, firstDay: snapshot.days.first?.date)
        let daily = all.filter { $0.date >= start }
        let points = InsightPoint.averaged(daily, by: averaging)
        let average = daily.map(\.value).mean
        let difference = daily.count >= 2 ? daily[daily.count - 1].value - daily[0].value : nil
        let holding = snapshot.days.last?.isHolding ?? true

        InsightScaffold(title: "Dépense", explanation: Self.explanation) {
            InsightHeadline(
                primary: InsightHeadlineValue(caption: "Moyenne", value: DashboardFormat.kcalNumber(average),
                                              unit: "kcal", numeric: average ?? 0),
                secondary: InsightHeadlineValue(caption: "Différence",
                                                value: difference.map { DashboardFormat.signed($0) } ?? "–",
                                                unit: "kcal", numeric: difference ?? 0),
                dates: InsightCalendar.rangeLabel(start, today),
                fitToData: $fitToData)
            if points.isEmpty {
                DashboardChartPlaceholder(text: "Enregistrez vos repas et votre poids quelques jours pour voir l'évolution de votre dépense.", height: 300)
            } else {
                InsightLineChart(points: points, kind: .expenditure, range: range, averaging: averaging,
                                 startDate: start, endDate: range.endDate(today: today), fitToData: fitToData,
                                 height: 300)
                    .padding(.top, 8)
            }
            InsightRangeBar(range: settings.range, averaging: settings.averaging)
        } content: {
            InsightLegend(items: [
                InsightLegendItem(mark: .band(Theme.expenditure), text: "Plage de flux"),
                InsightLegendItem(mark: .lineDot(Theme.expenditure), text: "Dépense"),
                InsightLegendItem(mark: .holding(Theme.expenditure), text: "En attente"),
            ])
            InsightSectionTitle(title: "Analyses et données")
            InsightCard(title: "Évolution de la dépense") {
                InsightChangesRows(changes: InsightChange.table(all.map(\.value)), color: Theme.expenditure,
                                   format: InsightText.kcal, threshold: 0.5)
            }
            InsightTilesCard(tiles: [
                InsightTile(value: DashboardFormat.kcalNumber(snapshot.isEmpty ? nil : snapshot.expenditure),
                            unit: "kcal", title: "Dépense actuelle",
                            text: "La dernière estimation de votre dépense énergétique quotidienne, d'après votre poids tendance et vos données nutritionnelles."),
                InsightTile(value: holding ? "En attente" : "Active", unit: "", title: "Stratégie actuelle",
                            text: holding
                                ? "Le mode attente protège votre estimation contre un manque de données. Sa mise à jour demande au moins 3 jours de nutrition et 1 jour de pesée par période de 7 jours."
                                : "Votre estimation se met à jour chaque jour à partir de vos apports enregistrés et de l'évolution de votre poids tendance."),
            ])
            .padding(.top, 12)
            InsightSectionTitle(title: "Sources de données")
            VStack(spacing: 10) {
                NavigationLink(value: DashboardRoute.weights) {
                    InsightDataSourceRow(systemImage: "scalemass.fill", title: "Poids balance", subtitle: "Gérer les données")
                }
                Button {
                    appState.selectedDay = today
                    appState.selectedTab = .today
                } label: {
                    InsightDataSourceRow(systemImage: "fork.knife", title: "Nutrition", subtitle: "Ouvrir le journal")
                }
            }
            .buttonStyle(.plain)
            InsightHistory(groups: DashboardInsights.groupedByMonth(Self.history(all, from: start), date: \.date),
                           value: { "\(Formatters.number($0.value, maxFractionDigits: 0)) kcal" },
                           date: \.date) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.isHolding ? "square" : InsightTrendWord.icon(row.low, threshold: 0.5))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.expenditure)
                    Text(row.isHolding ? "En attente" : InsightTrendWord.word(row.low, threshold: 0.5))
                        .font(Theme.font(15, .regular, relativeTo: .subheadline))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    /// Days of the range, newest first, with the change since the previous day in `low`.
    private static func history(_ points: [InsightPoint], from start: Date) -> [InsightPoint] {
        var rows: [InsightPoint] = []
        for index in points.indices where points[index].date >= start {
            let delta = index > 0 ? points[index].value - points[index - 1].value : 0
            rows.append(InsightPoint(date: points[index].date, value: points[index].value, low: delta, high: delta,
                                     isHolding: points[index].isHolding))
        }
        return rows
    }

    private static let explanation = "La dépense est l'énergie que vous dépensez chaque jour. Elle est estimée à partir de vos apports enregistrés et de l'évolution de votre poids tendance, et s'ajuste un peu chaque jour.\n\nLa plage de flux montre à quel point les mesures récentes tirent l'estimation. Un carré signale un jour « en attente » : faute de données suffisantes (au moins 3 jours de nutrition et 1 pesée sur 7 jours), l'estimation garde sa dernière valeur."
}

// MARK: - Poids tendance

struct DashboardWeightTrendDetail: View {
    let snapshot: CoachingSnapshot
    let targetKg: Double?
    let today: Date

    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    private var settings = InsightSettings("weight", defaultRange: .quarter)
    @State private var fitToData = true
    @State private var showingAdd = false

    init(snapshot: CoachingSnapshot, targetKg: Double?, today: Date) {
        self.snapshot = snapshot
        self.targetKg = targetKg
        self.today = today
    }

    var body: some View {
        let range = settings.range.wrappedValue
        let averaging = settings.averaging.wrappedValue
        let scale = ProgressStats.dailyScaleWeights(weights)
        let all = DashboardInsights.weightPoints(snapshot, scale: scale)
        let start = range.startDate(today: today, firstDay: snapshot.days.first?.date)
        let daily = all.filter { $0.date >= start }
        let points = InsightPoint.averaged(daily, by: averaging)
        let average = daily.map(\.value).mean
        let difference = daily.count >= 2 ? daily[daily.count - 1].value - daily[0].value : nil
        let weekly = DashboardInsights.weeklyWeightChange(snapshot)
        let balance = weekly.map { $0 * DashboardInsights.energyDensity / 7 }
        let projection = weekly.flatMap { rate in snapshot.trendKg.map { $0 + rate / 7 * 30 } }
        let isGain = (weekly ?? 0) > 0

        InsightScaffold(title: "Poids tendance", explanation: Self.explanation) {
            InsightHeadline(
                primary: InsightHeadlineValue(caption: "Moyenne", value: InsightText.kgValue(average),
                                              unit: "kg", numeric: average ?? 0),
                secondary: InsightHeadlineValue(caption: "Différence",
                                                value: difference.map { DashboardFormat.signed($0, maxFractionDigits: 1) } ?? "–",
                                                unit: "kg", numeric: difference ?? 0),
                dates: InsightCalendar.rangeLabel(start, today),
                fitToData: $fitToData)
            if points.isEmpty {
                DashboardChartPlaceholder(text: "Aucune pesée sur cette période.", height: 400)
            } else {
                InsightLineChart(points: points, kind: .weight, range: range, averaging: averaging,
                                 startDate: start, endDate: range.endDate(today: today), fitToData: fitToData,
                                 height: 400)
                    .padding(.top, 8)
            }
            InsightRangeBar(range: settings.range, averaging: settings.averaging)
        } content: {
            InsightLegend(items: [
                InsightLegendItem(mark: .band(Theme.weight), text: "Plage de bruit"),
                InsightLegendItem(mark: .lineDot(Theme.weight), text: "Poids tendance"),
                InsightLegendItem(mark: .dot(Theme.weightDark), text: "Poids balance"),
            ])
            InsightSectionTitle(title: "Analyses et données")
            InsightCard(title: "Évolution du poids") {
                InsightChangesRows(changes: InsightChange.table(all.map(\.value)), color: Theme.weight,
                                   format: InsightText.kg)
            }
            InsightTilesCard(tiles: [
                InsightTile(value: InsightText.kgValue(snapshot.trendKg), unit: "kg", title: "Poids actuel",
                            text: "Notre estimation de votre poids réel, une fois lissées les variations d'un jour à l'autre."),
                InsightTile(value: weekly.map { DashboardFormat.signed($0, maxFractionDigits: 2) } ?? "–",
                            unit: "kg par semaine", title: "Variation hebdomadaire",
                            text: "Votre rythme habituel de \(isGain ? "prise" : "perte") de poids sur les trois dernières semaines, pondéré vers les pesées récentes."),
                InsightTile(value: balance.map { DashboardFormat.signed($0) } ?? "–", unit: "kcal par jour",
                            title: isGain ? "Surplus énergétique" : "Déficit énergétique",
                            text: "Notre estimation de votre \(isGain ? "surplus" : "déficit") calorique quotidien moyen, d'après votre rythme de \(isGain ? "prise" : "perte") de poids sur les trois dernières semaines."),
                InsightTile(value: InsightText.kgValue(projection), unit: "kg", title: "Projection à 30 jours",
                            text: "Votre poids dans 30 jours si votre rythme récent se maintient. Un changement d'apports ou de dépense peut nettement modifier cette projection."),
            ])
            .padding(.top, 12)
            InsightSectionTitle(title: "Sources de données")
            NavigationLink(value: DashboardRoute.weights) {
                InsightDataSourceRow(systemImage: "scalemass.fill", title: "Poids balance", subtitle: "Gérer les données")
            }
            .buttonStyle(.plain)
            InsightHistory(groups: DashboardInsights.groupedByMonth(Self.history(all, from: start), date: \.date),
                           value: { "\(Formatters.number($0.value, maxFractionDigits: 1)) kg" },
                           date: \.date) { row in
                HStack(spacing: 8) {
                    Image(systemName: InsightTrendWord.icon(row.low, threshold: 0.05))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.weight)
                    Text(InsightTrendWord.word(row.low, threshold: 0.05))
                        .font(Theme.font(15, .regular, relativeTo: .subheadline))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityLabel("Ajouter une pesée")
            }
        }
        .sheet(isPresented: $showingAdd) {
            ProgressAddWeightSheet(initialKg: weights.last?.kg)
        }
    }

    /// Weigh-in days of the range, newest first: trend that day, change since the previous weigh-in in `low`.
    private static func history(_ points: [InsightPoint], from start: Date) -> [InsightPoint] {
        var rows: [InsightPoint] = []
        var previous: Double?
        for point in points where point.scale != nil {
            if point.date >= start {
                let delta = previous.map { point.value - $0 } ?? 0
                rows.append(InsightPoint(date: point.date, value: point.value, low: delta, high: delta))
            }
            previous = point.value
        }
        return rows
    }

    private static let explanation = "Le poids tendance lisse les variations d'un jour à l'autre (eau, sel, digestion) pour montrer l'évolution réelle de votre poids. Il est révisé à chaque nouvelle pesée.\n\nLa plage de bruit montre l'écart entre vos pesées et la tendance. Les points sont vos pesées sur la balance."
}

// MARK: - Objectif

struct DashboardGoalDetail: View {
    let progress: DashboardGoalProgress?
    let snapshot: CoachingSnapshot
    let weights: [WeightEntry]
    let goal: WeightGoal
    /// Planned weekly change (kg, positive), for the optimistic ETA.
    let weeklyRateKg: Double
    let today: Date

    @Environment(AppState.self) private var appState
    @State private var tab = 0
    @State private var fitToData = false

    var body: some View {
        if let progress {
            content(progress)
        } else {
            DashboardDetailScaffold(title: "Objectif") {
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
    }

    @ViewBuilder
    private func content(_ progress: DashboardGoalProgress) -> some View {
        let useTrend = tab == 1
        let scale = ProgressStats.dailyScaleWeights(weights)
        let steps = DashboardInsights.goalSteps(progress: progress, snapshot: snapshot, scale: scale,
                                                useTrend: useTrend, today: today)
        let currentKg = useTrend ? progress.currentKg : (weights.last?.kg ?? progress.currentKg)
        let distance = abs(currentKg - progress.targetKg)
        let duration = max(InsightCalendar.days(from: progress.startDate, to: today), 0)
        let eta: Date? = weeklyRateKg > 0.01 ? today.adding(days: Int((distance / weeklyRateKg * 7).rounded())) : nil
        let awayColor = useTrend ? Theme.weight : Theme.goalAway
        let towardsColor = useTrend ? Theme.weightDark : Theme.goalTowards

        InsightScaffold(title: "Objectif", explanation: Self.explanation) {
            InsightTabs(tabs: [.init(title: "Poids balance", systemImage: "chart.xyaxis.line"),
                               .init(title: "Poids tendance", systemImage: "chart.line.downtrend.xyaxis")],
                        selection: $tab)
            InsightHeadline(
                primary: InsightHeadlineValue(caption: "Distance", value: Formatters.number(distance, maxFractionDigits: 1),
                                              unit: "kg", numeric: distance),
                dates: InsightCalendar.rangeLabel(progress.startDate, today, endIsToday: true),
                fitToData: $fitToData)
            if steps.isEmpty {
                DashboardChartPlaceholder(text: "Aucune pesée depuis le début de l'objectif.", height: 300)
            } else {
                InsightGoalChart(steps: steps, useTrend: useTrend, fitToData: fitToData)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        } content: {
            InsightLegend(items: [
                InsightLegendItem(mark: .square(awayColor), text: "S'éloigne"),
                InsightLegendItem(mark: .square(towardsColor), text: "Se rapproche"),
            ])
            InsightSectionTitle(title: "Analyses et données")
            InsightTilesCard(tiles: [
                InsightTile(value: Formatters.number(progress.targetKg, maxFractionDigits: 1), unit: "kg",
                            title: "Poids visé", text: "Le poids choisi lors de la création de l'objectif."),
                InsightTile(value: "\(duration)", unit: duration > 1 ? "jours" : "jour", title: "Durée",
                            text: "Le nombre de jours passés à poursuivre votre objectif actuel."),
                InsightTile(value: eta.map { distance < 0.05 ? "Atteint" : $0.formatted(.dateTime.day().month(.abbreviated).locale(Formatters.locale)) } ?? "–",
                            unit: eta.map { distance < 0.05 ? "" : $0.formatted(.dateTime.year().locale(Formatters.locale)) } ?? "",
                            title: "Date estimée",
                            text: "Estimation optimiste de la date où vous atteindriez votre objectif en suivant le rythme prévu, d'après votre \(useTrend ? "poids tendance" : "poids balance")."),
            ])
        }
        .animation(.quick, value: tab)
    }

    private static let explanation = "La distance est l'écart entre votre poids et votre poids visé.\n\nLe graphique part de la distance au début de l'objectif (jour 0). Chaque barre montre comment elle a changé : claire quand vous vous en éloignez, foncée quand vous vous en rapprochez. La dernière barre grise est la distance actuelle. « Poids balance » suit chaque pesée, « Poids tendance » la tendance lissée semaine par semaine."
}

// MARK: - Bilan énergétique

struct DashboardEnergyBalanceDetail: View {
    let snapshot: CoachingSnapshot
    let todayIntake: Double
    let today: Date
    /// Calorie target of a day (the program in effect that day).
    let target: (Date) -> Double

    private var settings = InsightSettings("balance", defaultRange: .week)
    @State private var tab = 0
    @State private var fitToData = false

    init(snapshot: CoachingSnapshot, todayIntake: Double, today: Date, target: @escaping (Date) -> Double) {
        self.snapshot = snapshot
        self.todayIntake = todayIntake
        self.today = today
        self.target = target
    }

    var body: some View {
        let againstTargets = tab == 1
        let range = settings.range.wrappedValue
        let averaging = settings.averaging.wrappedValue
        let all = DashboardInsights.balanceDays(snapshot: snapshot, from: .distantPast, today: today,
                                                todayIntake: todayIntake, target: target)
        let start = range.startDate(today: today, firstDay: snapshot.days.first?.date)
        let shown = all.filter { $0.date >= start }
        let difference: (InsightBalanceDay) -> Double = { day in
            (day.intake ?? 0) - (againstTargets ? day.target : day.expenditure)
        }
        let complete = shown.filter { !$0.isPartial && $0.intake != nil }
        let average = complete.map(difference).mean
        let rows = InsightChange.windows.map { days in
            InsightBalanceRows.Row(days: days, value: DashboardInsights.average(all, lastDays: days, today: today, value: difference))
        }
        let color = againstTargets ? Theme.targetLine : Theme.expenditure
        let positive = againstTargets ? "Au-dessus" : "Surplus"
        let negative = againstTargets ? "En dessous" : "Déficit"

        InsightScaffold(title: "Bilan énergétique", explanation: Self.explanation) {
            InsightTabs(tabs: [.init(title: "Dépense", systemImage: "flame.fill"),
                               .init(title: "Objectifs caloriques", systemImage: "smallcircle.filled.circle")],
                        selection: $tab)
            InsightHeadline(
                primary: InsightHeadlineValue(
                    caption: againstTargets ? "Moyenne" : ((average ?? 0) > 0 ? "Surplus" : "Déficit"),
                    value: average.map { DashboardFormat.signed($0) } ?? "–", unit: "kcal", numeric: average ?? 0),
                dates: InsightCalendar.rangeLabel(start, today),
                fitToData: $fitToData)
            if shown.allSatisfy({ $0.intake == nil }) {
                DashboardChartPlaceholder(text: "Enregistrez vos repas pour comparer vos apports à \(againstTargets ? "vos objectifs" : "votre dépense").", height: 170)
            } else {
                InsightBalanceChart(days: shown, againstTargets: againstTargets, range: range, averaging: averaging,
                                    startDate: start, endDate: range.endDate(today: today), fitToData: fitToData)
                    .padding(.top, 12)
            }
            InsightRangeBar(range: settings.range, averaging: settings.averaging)
        } content: {
            InsightLegend(items: [
                InsightLegendItem(mark: .bars(Theme.calories), text: "Calories"),
                InsightLegendItem(mark: .dashed(color), text: againstTargets ? "Objectifs" : "Dépense"),
            ])
            InsightSectionTitle(title: "Analyses et données")
            InsightCard(title: againstTargets ? "Par rapport aux objectifs" : "Par rapport à la dépense") {
                InsightBalanceRows(rows: rows, color: color, positiveWord: positive, negativeWord: negative)
            }
            InsightHistory(groups: DashboardInsights.groupedByMonth(complete, date: \.date),
                           value: { InsightText.kcal(difference($0)) },
                           date: \.date) { day in
                InsightBalanceStatus(value: difference(day), color: color, positiveWord: positive, negativeWord: negative)
            }
        }
        .animation(.quick, value: tab)
    }

    private static let explanation = "Vos apports enregistrés comparés à votre dépense estimée (onglet Dépense) ou à vos objectifs caloriques (onglet Objectifs caloriques).\n\nLes moyennes ne comptent que les jours enregistrés et terminés : aujourd'hui, les jours vides et les périodes d'exception sont ignorés."
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
