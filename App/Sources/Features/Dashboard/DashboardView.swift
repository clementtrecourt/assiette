import SwiftData
import SwiftUI

// CONTRACT (used by RootView): DashboardView() — the "Accueil" tab root (owns its NavigationStack).

/// "Accueil" tab: calorie ring, G/P/L bars, then Tendances, Nutrition du jour, Mesures and
/// Régularité cards. The floating search bar is added below by RootView.
struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date.now.startOfDay

    var body: some View {
        NavigationStack {
            DashboardContent(today: today)
                .id(today)
                .navigationTitle("Accueil")
                .toolbar(.hidden, for: .navigationBar)
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
    @AppStorage(HealthImport.lastSyncKey) private var healthSync = 0.0
    @State private var snapshot = CoachingSnapshot()
    @State private var showingAddWeight = false

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
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Nutrition du jour")
                            .font(Theme.title)
                        Spacer(minLength: 10)
                        DashboardHero(consumed: totals.calories, target: targets.calories,
                                      showRemaining: showRemaining)
                        Spacer(minLength: 14)
                        DashboardMacroBars(totals: totals, targets: targets, showRemaining: showRemaining)
                        Spacer(minLength: 16)
                        DashboardModePicker(showRemaining: $showRemaining)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 14)
                    .frame(minHeight: 382)
                }
                .padding(.horizontal, 16)
                .background(Theme.raised.ignoresSafeArea(edges: .top))
                .padding(.horizontal, -16)

                trendsSection(goal: goal, todayKcal: totals.calories)
                    .padding(.top, 30)
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
        }
        .sheet(isPresented: $showingAddWeight) {
            ProgressAddWeightSheet(initialKg: weights.last?.kg ?? profile?.weightKg)
        }
        .task(id: snapshotKey) {
            refreshSnapshot()
        }
        .sensoryFeedback(.selection, trigger: showRemaining)
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
                    .frame(width: 44, height: 44)
                    .background(Theme.raised2, in: Circle())
            }
            .accessibilityLabel("Affichage de la nutrition")
        }
        .padding(.top, 6)
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
            DashboardSectionHeader(title: "Tendances")
            LazyVGrid(columns: DashboardGrid.columns, spacing: DashboardGrid.spacing) {
                NavigationLink(value: DashboardRoute.expenditure) {
                    DashboardCard(title: "Dépense", subtitle: "7 derniers jours",
                                  value: DashboardFormat.kcalNumber(snapshot.isEmpty ? nil : snapshot.expenditure),
                                  unit: "kcal") {
                        DashboardSparkline(values: expenditures, color: Theme.expenditure,
                                           style: .area, minimumSpan: 60)
                    }
                }
                NavigationLink(value: DashboardRoute.weightTrend) {
                    DashboardCard(title: "Poids tendance", subtitle: "7 derniers jours",
                                  value: snapshot.trendKg.map { Formatters.number($0, maxFractionDigits: 1) } ?? "–",
                                  unit: "kg") {
                        DashboardSparkline(values: trend, color: Theme.weight, style: .line, minimumSpan: 0.6)
                    }
                }
                NavigationLink(value: DashboardRoute.goal) {
                    goalCard(goal)
                }
                NavigationLink(value: DashboardRoute.energyBalance) {
                    DashboardCard(title: "Bilan énergétique", subtitle: "7 derniers jours",
                                  value: averageBalance.map { DashboardFormat.signed($0) } ?? "–",
                                  unit: "kcal/j") {
                        DashboardBalanceBars(points: balance)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func goalCard(_ goal: DashboardGoalProgress?) -> some View {
        let subtitle: String
        if let goal {
            subtitle = DashboardFormat.since(goal.startDate, today: today)
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
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
                                goal: profile?.goal ?? .maintain, today: today)
        case .energyBalance:
            DashboardEnergyBalanceDetail(snapshot: snapshot, todayIntake: totals.calories, today: today)
        case .nutrients:
            DashboardNutrientsView(totals: totals, targets: targets, entryCount: entryCount)
        case .weights:
            ProgressWeightHistoryView()
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

    private func refreshSnapshot() {
        guard let profile else {
            snapshot = CoachingSnapshot()
            return
        }
        snapshot = CoachingService.snapshot(profile: profile, context: modelContext)
    }
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
