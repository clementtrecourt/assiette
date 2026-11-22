import SwiftData
import SwiftUI

// CONTRACT (used by RootView): DashboardView() — the "Accueil" tab root (owns its NavigationStack).

/// "Accueil" tab: calorie ring, G/P/L bars, then Tendances, Nutrition du jour, Mesures and
/// Régularité cards. The floating search bar is added below by RootView.
struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState
    @State private var today = Date.now.startOfDay
    @State private var path: [DashboardRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            DashboardContent(today: today)
                .id(today)
                .navigationTitle("Accueil")
                .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: path.isEmpty) { _, isEmpty in
            // Detail screens hide the floating search bar (RootView), as on the reference.
            appState.dashboardDetailShown = !isEmpty
        }
        .task {
            if let route = DemoSupport.startRoute, path.isEmpty {
                try? await Task.sleep(for: .seconds(1.5)) // let the demo data and snapshot settle
                path = [route]
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Roll over to the new day when the app comes back after midnight.
            guard phase == .active else { return }
            let now = Date.now.startOfDay
            if now != today { today = now }
        }
    }
}

/// Dashboard content for `today`. The journal query is built in `init` so only the last
/// 30 days are fetched (today's totals + the regularity grid).
private struct DashboardContent: View {
    let today: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query private var recentEntries: [JournalEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \CoachingCheckIn.date) private var checkIns: [CoachingCheckIn]

    @AppStorage("dashboard.showRemaining") private var showRemaining = true
    @AppStorage("dashboard.balanceExpenditure") private var balanceAgainstExpenditure = false
    /// Page of the header carousel (0 ring, 1 week, 2 energy balance).
    @State private var heroPage: Int? = DemoSupport.heroPage ?? 0
    @State private var weekSelection = Date.now.startOfDay
    @AppStorage(HealthImport.lastSyncKey) private var healthSync = 0.0
    /// Starts from the last computed snapshot, so the cards are filled from the first frame.
    @State private var snapshot = DashboardSnapshotCache.last
    @State private var showingAddWeight = false
    /// Opening animation of the ring and the trend cards (replayed each time Accueil shows,
    /// except when coming back from a detail screen).
    @State private var revealed = false
    @State private var returningFromDetail = false
    @State private var lastOpening = Date.distantPast
    @Environment(\.scenePhase) private var scenePhase

    private static let regularityDays = 30

    init(today: Date) {
        self.today = today
        let start = today.adding(days: -(Self.regularityDays - 1)).startOfDay
        _recentEntries = Query(filter: #Predicate<JournalEntry> { entry in
            entry.day >= start
        })
    }

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        let todayEntries = recentEntries.filter { $0.day.startOfDay == today }
        let totals = NutrientValues.sum(todayEntries.map(\.nutrients))
        let targets = DashboardTargets(profile: profile, day: today)
        let goal = DashboardGoalProgress.compute(profile: profile, checkIns: checkIns,
                                                 weights: weights, snapshot: snapshot)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    // Spacing measured on the reference: title → ring 18 pt, arc end → macro
                    // labels ≈ 26 pt, values → toggle 33 pt, toggle → end of the header 15 pt.
                    // Carousel of three pages (reference: Daily Nutrition, Weekly Nutrition,
                    // Energy Balance), swiped horizontally; the toggle under it follows the page.
                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                dailyPage(totals: totals, targets: targets)
                                    .padding(.horizontal, 16)
                                    .containerRelativeFrame(.horizontal)
                                    .id(0)
                                weekPage
                                    .padding(.horizontal, 16)
                                    .containerRelativeFrame(.horizontal)
                                    .id(1)
                                balancePage(todayKcal: totals.calories)
                                    .padding(.horizontal, 16)
                                    .containerRelativeFrame(.horizontal)
                                    .id(2)
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $heroPage)
                        Group {
                            if (heroPage ?? 0) == 2 {
                                DashboardPageToggle(first: "Objectif", second: "Dépense",
                                                    secondSelected: $balanceAgainstExpenditure)
                            } else {
                                DashboardModePicker(showRemaining: $showRemaining)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 33)
                    }
                    .padding(.horizontal, -16)
                    .padding(.top, 8)
                    .padding(.bottom, 15)
                }
                .padding(.horizontal, 16)
                .background(Theme.raised.ignoresSafeArea(edges: .top))
                .padding(.horizontal, -16)

                DashboardPageDots(count: 3, current: heroPage ?? 0)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                trendsSection(goal: goal, todayKcal: totals.calories)
                    .padding(.top, 20)
                nutritionSection(totals: totals, targets: targets)
                    .padding(.top, 28)
                measuresSection
                    .padding(.top, 28)
                regularitySection
                    .padding(.top, 28)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            // Status bar strip in the header color (ShapeStyle backgrounds fill the safe area).
            Color.clear.frame(height: 0).background(Theme.raised)
        }
        .navigationDestination(for: DashboardRoute.self) { route in
            destination(route, goal: goal, totals: totals, targets: targets,
                        entryCount: todayEntries.count)
                .onAppear { returningFromDetail = true }
        }
        .sheet(isPresented: $showingAddWeight) {
            ProgressAddWeightSheet(initialKg: weights.last?.kg ?? profile?.weightKg)
        }
        .onAppear {
            // Synchronous, before the first frame is shown: the cards have their data when
            // the opening animation starts.
            if snapshot.isEmpty { refreshSnapshot() }
            if returningFromDetail {
                returningFromDetail = false
            } else {
                playOpening()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && appState.selectedTab == .progress && !appState.dashboardDetailShown {
                playOpening()
            }
        }
        .task(id: snapshotKey) {
            refreshSnapshot()
        }
        .sensoryFeedback(.selection, trigger: showRemaining)
    }

    // MARK: Carousel pages

    private func dailyPage(totals: NutrientValues, targets: DashboardTargets) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition du jour")
                .font(Theme.title)
            DashboardHero(consumed: totals.calories, target: targets.calories,
                          showRemaining: showRemaining, revealed: revealed)
                .padding(.top, 18)
            DashboardMacroBars(totals: totals, targets: targets, showRemaining: showRemaining)
                .padding(.horizontal, 4)
                .padding(.top, -3)
        }
    }

    /// Monday → Sunday of the current week, with each day's totals and targets.
    private var weekDays: [DashboardWeekDay] {
        let monday = today.adding(days: -CoachingFormat.mondayIndex(of: today))
        var byDay: [Date: [JournalEntry]] = [:]
        for entry in recentEntries where entry.day >= monday {
            byDay[entry.day.startOfDay, default: []].append(entry)
        }
        return (0..<7).map { offset in
            let day = monday.adding(days: offset).startOfDay
            return DashboardWeekDay(date: day,
                                    totals: NutrientValues.sum((byDay[day] ?? []).map(\.nutrients)),
                                    targets: DashboardTargets(profile: profile, day: day),
                                    isFuture: day > today)
        }
    }

    private var weekPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nutrition de la semaine")
                .font(Theme.title)
            DashboardWeekPage(days: weekDays, showRemaining: showRemaining, selected: $weekSelection)
        }
    }

    private func balancePage(todayKcal: Double) -> some View {
        let start = today.adding(days: -20).startOfDay
        let days = DashboardInsights.balanceDays(snapshot: snapshot, from: start, today: today,
                                                 todayIntake: todayKcal, target: calorieTargetLookup)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Bilan énergétique")
                .font(Theme.title)
            DashboardBalancePage(days: days, againstExpenditure: balanceAgainstExpenditure)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("ACCUEIL")
                .font(Theme.screenTitle())
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Picker("Affichage", selection: $showRemaining) {
                    Text("Mangé").tag(false)
                    Text("Restant").tag(true)
                }
            } label: {
                Image("Glyph-reglage")
                    .frame(width: 40, height: 40)
                    .background(Theme.raised2, in: Circle())
            }
            .accessibilityLabel("Affichage de la nutrition")
        }
        .padding(.top, 4)
        .padding(.bottom, 4)

    }

    // MARK: Tendances

    private func trendsSection(goal: DashboardGoalProgress?, todayKcal: Double) -> some View {
        let lastWeek = Array(snapshot.last(7))
        let expenditures = lastWeek.map(\.expenditure)
        let trend = lastWeek.compactMap(\.smoothedTrendKg)
        let balance = DashboardData.balancePoints(snapshot: snapshot, count: 7, today: today,
                                                  todayIntake: todayKcal)
        let averageBalance = snapshot.averageBalance(lastDays: 7)

        return VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Analyses et tendances")
            LazyVGrid(columns: DashboardGrid.columns, spacing: DashboardGrid.spacing) {
                NavigationLink(value: DashboardRoute.expenditure) {
                    DashboardCard(title: "Dépense", subtitle: "7 derniers jours",
                                  value: DashboardFormat.kcalNumber(snapshot.isEmpty ? nil : snapshot.expenditure),
                                  unit: "kcal") {
                        DashboardSparkline(values: expenditures, color: Theme.expenditure,
                                           style: .markers, holding: lastWeek.map(\.isHolding),
                                           minimumSpan: 60, revealed: revealed)
                    }
                }
                NavigationLink(value: DashboardRoute.weightTrend) {
                    DashboardCard(title: "Poids tendance", subtitle: "7 derniers jours",
                                  value: snapshot.trendKg.map { Formatters.number($0, maxFractionDigits: 1) } ?? "–",
                                  unit: "kg") {
                        DashboardSparkline(values: trend, color: Theme.weight, style: .markers, minimumSpan: 0.6,
                                           revealed: revealed)
                    }
                }
                NavigationLink(value: DashboardRoute.goal) {
                    goalCard(goal)
                }
                NavigationLink(value: DashboardRoute.energyBalance) {
                    DashboardCard(title: "Bilan énergétique", subtitle: "7 derniers jours",
                                  value: averageBalance.map { Formatters.number(abs($0), maxFractionDigits: 0) } ?? "–",
                                  unit: averageBalance.map { $0 < 0 ? "kcal déficit" : "kcal surplus" } ?? "") {
                        DashboardBalanceBars(points: balance)
                    }
                }
            }
            .buttonStyle(DashboardCardButtonStyle())
        }
    }

    private func goalCard(_ goal: DashboardGoalProgress?) -> some View {
        let subtitle: String
        if let goal {
            let days = max(InsightCalendar.days(from: goal.startDate, to: today), 0)
            subtitle = days == 0 ? "aujourd'hui" : (days == 1 ? "dernier jour" : "\(days) derniers jours")
        } else if profile?.goal == .maintain {
            subtitle = "maintien"
        } else {
            subtitle = "aucun poids visé"
        }
        return DashboardCard(title: "Objectif", subtitle: subtitle,
                             value: goal.map { Formatters.number($0.fraction * 100, maxFractionDigits: 0) } ?? "–",
                             unit: goal == nil ? "" : "%") {
            DashboardMeter(fraction: goal?.fraction ?? 0, color: Theme.good)
        }
    }

    // MARK: Nutrition du jour

    private func nutritionSection(totals: NutrientValues, targets: DashboardTargets) -> some View {
        let keys: [NutrientKey] = [.calories] + Theme.macroOrder + [.dietaryFiber, .potassium]
        return VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Nutrition du jour") {
                NavigationLink(value: DashboardRoute.nutrients) {
                    DashboardSeeAllLabel()
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: DashboardGrid.columns, spacing: DashboardGrid.spacing) {
                ForEach(keys, id: \.self) { key in
                    NavigationLink(value: DashboardRoute.nutrients) {
                        DashboardNutrientCard(key: key, amount: totals[key],
                                              target: targets.value(for: key))
                    }
                }
            }
            .buttonStyle(DashboardCardButtonStyle())
        }
    }

    // MARK: Mesures

    private var measuresSection: some View {
        let lastWeighIns = weights.suffix(7).map(\.kg)
        let latest = weights.last
        return VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Mesures") {
                NavigationLink(value: DashboardRoute.weights) {
                    DashboardSeeAllLabel()
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: DashboardGrid.columns, spacing: DashboardGrid.spacing) {
                NavigationLink(value: DashboardRoute.weights) {
                    DashboardCard(title: "Pesées",
                                  subtitle: weights.count >= 7 ? "7 dernières" : (weights.isEmpty ? "aucune pesée" : "dernières pesées"),
                                  value: latest.map { Formatters.number($0.kg, maxFractionDigits: 1) } ?? "–",
                                  unit: latest == nil ? "" : "kg") {
                        DashboardSparkline(values: lastWeighIns, color: Theme.weight, style: .dots, minimumSpan: 0.6)
                    }
                }
                Button {
                    showingAddWeight = true
                } label: {
                    DashboardCard(title: "Nouvelle pesée",
                                  subtitle: latest.map { "dernière : \(Formatters.dayTitle($0.date).lowercased())" } ?? "à jeun, le matin",
                                  value: "Ajouter", accessory: "plus") {
                        Image(systemName: "scalemass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.weight)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised2))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityLabel("Ajouter une pesée")
            }
            .buttonStyle(DashboardCardButtonStyle())
        }
    }

    // MARK: Régularité

    private var regularitySection: some View {
        let count = Self.regularityDays
        let weighInDays = Set(weights.map { $0.date.startOfDay })
        let loggedDays = Set(recentEntries.map { $0.day.startOfDay })
        let weighIns = DashboardData.presence(of: weighInDays, count: count, today: today)
        let logged = DashboardData.presence(of: loggedDays, count: count, today: today)

        return VStack(alignment: .leading, spacing: 12) {
            DashboardSectionHeader(title: "Régularité")
            LazyVGrid(columns: DashboardGrid.columns, spacing: DashboardGrid.spacing) {
                NavigationLink(value: DashboardRoute.weights) {
                    DashboardCard(title: "Pesées", subtitle: "30 derniers jours",
                                  value: "\(weighIns.filter { $0 }.count)", unit: "/ \(count)",
                                  visualHeight: 48) {
                        DashboardDotGrid(filled: weighIns, color: Theme.weight)
                    }
                }
                Button {
                    appState.selectedDay = today
                    appState.selectedTab = .today
                } label: {
                    DashboardCard(title: "Journal", subtitle: "30 derniers jours",
                                  value: "\(logged.filter { $0 }.count)", unit: "/ \(count)",
                                  visualHeight: 48) {
                        DashboardDotGrid(filled: logged, color: Theme.calories)
                    }
                }
            }
            .buttonStyle(DashboardCardButtonStyle())
        }
    }

    // MARK: Navigation

    @ViewBuilder
    private func destination(_ route: DashboardRoute, goal: DashboardGoalProgress?, totals: NutrientValues,
                             targets: DashboardTargets, entryCount: Int) -> some View
    {
        switch route {
        case .expenditure:
            DashboardExpenditureDetail(snapshot: snapshot, today: today)
        case .weightTrend:
            DashboardWeightTrendDetail(snapshot: snapshot, targetKg: profile?.targetWeightKg, today: today)
        case .goal:
            DashboardGoalDetail(progress: goal, snapshot: snapshot, weights: weights,
                                goal: profile?.goal ?? .maintain, weeklyRateKg: weeklyRateKg, today: today)
        case .energyBalance:
            DashboardEnergyBalanceDetail(snapshot: snapshot, todayIntake: totals.calories, today: today,
                                         target: calorieTargetLookup)
        case .nutrients:
            DashboardNutrientsView(totals: totals, targets: targets, entryCount: entryCount)
        case .weights:
            ProgressWeightHistoryView()
        }
    }

    /// Planned weekly change of the current goal (kg, positive).
    private var weeklyRateKg: Double {
        guard let profile, profile.goal != .maintain else { return 0 }
        return CoachingService.weeklyKg(ratePercent: profile.effectiveRatePercent,
                                        weightKg: snapshot.trendKg ?? profile.weightKg)
    }

    /// Calorie target of a past day: the check-in in effect that day when the targets changed
    /// since, else today's program (weekly distribution applied).
    private var calorieTargetLookup: (Date) -> Double {
        let checkIns = self.checkIns
        let profile = self.profile
        let lastChange = checkIns.last?.date.startOfDay
        return { day in
            let start = day.startOfDay
            if let lastChange, start < lastChange,
               let inEffect = checkIns.last(where: { $0.date.startOfDay <= start }), inEffect.calorieTarget > 0 {
                return inEffect.calorieTarget
            }
            return profile?.targets(on: day).calories ?? DashboardTargets(profile: nil).calories
        }
    }

    // MARK: Snapshot

    /// Changes whenever the engine inputs visible here change (entries, weigh-ins, program).
    private var snapshotKey: String {
        let grams = recentEntries.reduce(0) { $0 + $1.grams }
        let lastKg = weights.last?.kg ?? 0
        return [
            "\(today.timeIntervalSinceReferenceDate)",
            "\(recentEntries.count)", "\(grams)",
            "\(weights.count)", "\(lastKg)",
            "\(checkIns.count)",
            "\(profile?.calorieTarget ?? 0)", "\(profile?.initialExpenditure ?? 0)",
            "\(profile?.expenditureAnchorKcal ?? 0)", "\(healthSync)",
        ].joined(separator: "|")
    }

    /// Empties the ring and the trend lines at once, then lets them fill 0.27 s later
    /// (delay measured on the reference between the page appearing and the ring starting).
    private func playOpening() {
        // Launch fires both onAppear and scene activation: play once.
        guard Date.now.timeIntervalSince(lastOpening) > 1 else { return }
        lastOpening = .now
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { revealed = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(270))
            revealed = true
        }
    }

    private func refreshSnapshot() {
        let fresh = profile.map { CoachingService.snapshot(profile: $0, context: modelContext) } ?? CoachingSnapshot()
        DashboardSnapshotCache.last = fresh
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { snapshot = fresh }
    }
}

/// Last engine snapshot shown by Accueil (the content view is re-created at midnight and
/// when the tab reloads; starting from it avoids an empty first frame).
enum DashboardSnapshotCache {
    static var last = CoachingSnapshot()
}

// MARK: - Nutrient card

/// "Nutrition du jour" tile: meter with a target tick (the target sits at 80 % of the width),
/// % of target for energy and macros, amount + recommended zone for fibre and potassium.
private struct DashboardNutrientCard: View {
    let key: NutrientKey
    let amount: Double?
    let target: Double

    /// Width of the meter = 125 % of the target, so the tick sits at 80 %.
    private static let scale = 1.25

    private var usesZone: Bool { key == .dietaryFiber || key == .potassium }

    private var color: Color {
        switch key {
        case .dietaryFiber: Theme.good
        case .potassium: Theme.textSecondary
        default: Theme.color(for: key)
        }
    }

    var body: some View {
        let value = amount ?? 0
        let ratio = target > 0 ? value / target : 0
        let isOver = !usesZone && ratio > 1.05
        let tick = 1 / Self.scale
        let valueText: String
        let unit: String
        if usesZone {
            valueText = amount.map { Formatters.number($0, maxFractionDigits: $0 < 10 ? 1 : 0) } ?? "–"
            unit = amount == nil ? "" : key.unit
        } else {
            valueText = Formatters.number(ratio * 100, maxFractionDigits: 0)
            unit = "%"
        }
        return DashboardCard(title: key.label, subtitle: "aujourd'hui", value: valueText, unit: unit,
                             valueColor: isOver ? Theme.overTarget : Theme.textPrimary,
                             visualHeight: 22) {
            DashboardMeter(fraction: min(ratio, Self.scale) / Self.scale,
                           color: isOver ? Theme.overTarget : color,
                           tick: target > 0 ? tick : nil,
                           zoneStart: usesZone ? tick : nil)
        }
    }
}
