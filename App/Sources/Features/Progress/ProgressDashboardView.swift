import SwiftData
import SwiftUI

/// "Progrès" tab: weight, calories, macros and streak over 7 / 30 / 90 days.
struct ProgressDashboardView: View {
    @AppStorage("progress.rangeDays") private var rangeRaw: Int = ProgressRange.month.rawValue

    private var range: ProgressRange { ProgressRange(rawValue: rangeRaw) ?? .month }

    var body: some View {
        NavigationStack {
            ProgressRangeContent(range: range, rangeRaw: $rangeRaw)
                .id(range)
                .navigationTitle("Progrès")
        }
        .sensoryFeedback(.selection, trigger: rangeRaw)
    }
}

/// Dashboard content for a given range. The journal query is built in `init` so that only
/// entries within the range are fetched.
struct ProgressRangeContent: View {
    let range: ProgressRange
    @Binding var rangeRaw: Int

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [JournalEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var profiles: [UserProfile]

    @State private var showingAddWeight = false
    @State private var streak = 0

    private let today: Date
    private let startDate: Date

    init(range: ProgressRange, rangeRaw: Binding<Int>) {
        self.range = range
        _rangeRaw = rangeRaw
        let today = Date.now.startOfDay
        let start = range.startDate(today: today)
        self.today = today
        self.startDate = start
        _entries = Query(filter: #Predicate<JournalEntry> { entry in
            entry.day >= start
        }, sort: \JournalEntry.day)
    }

    private var profile: UserProfile? { profiles.first }
    /// Exclusive end of the chart x-domain (so today's bar is fully visible).
    private var endDate: Date { today.adding(days: 1).startOfDay }

    var body: some View {
        let stats = ProgressStats.dailyStats(entries: entries, from: startDate, days: range.days)
        let logged = stats.filter(\.isLogged)
        let allPoints = ProgressStats.weightPoints(weights)
        let rangePoints = allPoints.filter { $0.date >= startDate }

        List {
            Section {
                Picker("Période", selection: $rangeRaw) {
                    ForEach(ProgressRange.allCases) { r in
                        Text(r.label).tag(r.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                overviewGrid(stats: stats, logged: logged, points: rangePoints)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            weightSection(points: rangePoints)
                .listRowBackground(Theme.card)
            caloriesSection(stats: stats, logged: logged)
                .listRowBackground(Theme.card)
            macrosSection(stats: stats, logged: logged)
                .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .themedBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddWeight = true
                } label: {
                    Label("Ajouter une pesée", systemImage: "scalemass")
                }
            }
        }
        .sheet(isPresented: $showingAddWeight) {
            ProgressAddWeightSheet(initialKg: weights.last?.kg ?? profile?.weightKg)
        }
        .task(id: streakKey) {
            let days = Set(entries.map { $0.day.startOfDay })
            streak = ProgressStats.streak(loggedDays: days, rangeStart: startDate,
                                          today: today, context: modelContext)
        }
    }

    private var streakKey: String {
        "\(entries.count)-\(today.timeIntervalSinceReferenceDate)"
    }

    // MARK: Overview

    private static let overviewColumns = [GridItem(.flexible(), spacing: 10),
                                          GridItem(.flexible(), spacing: 10)]

    private func overviewGrid(stats: [ProgressDayStat], logged: [ProgressDayStat],
                              points: [ProgressWeightPoint]) -> some View {
        let average = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.calories } / Double(logged.count)
        let target = profile?.calorieTarget ?? 0
        let averageDetail: String = target > 0 ? "objectif \(Formatters.kcal(target))" : "par jour suivi"
        let trend = points.last.map { ProgressStats.kg($0.average) } ?? "–"
        let delta = weightDelta(points).map { ProgressStats.signedKg($0) } ?? "–"
        return LazyVGrid(columns: Self.overviewColumns, spacing: 10) {
            ProgressOverviewTile(title: "Série", color: Theme.fat,
                                 value: "\(streak)",
                                 detail: streak > 1 ? "jours d'affilée" : "jour d'affilée")
            ProgressOverviewTile(title: "Jours suivis", color: Theme.accent,
                                 value: "\(logged.count)/\(stats.count)",
                                 detail: range.longLabel.lowercased())
            ProgressOverviewTile(title: "Kcal moyennes", color: Theme.calories,
                                 value: logged.isEmpty ? "–" : Formatters.number(average, maxFractionDigits: 0),
                                 detail: averageDetail)
            ProgressOverviewTile(title: "Poids tendance", color: Theme.weight,
                                 value: trend,
                                 detail: "évolution \(delta)")
        }
    }

    // MARK: Weight

    @ViewBuilder
    private func weightSection(points: [ProgressWeightPoint]) -> some View {
        let current = weights.last
        let target = profile?.targetWeightKg
        Section {
            if weights.isEmpty {
                ContentUnavailableView {
                    Label("Aucune pesée", systemImage: "scalemass")
                } description: {
                    Text("Enregistrez votre poids régulièrement pour voir la tendance.")
                } actions: {
                    Button("Ajouter une pesée") { showingAddWeight = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            } else {
                HStack(spacing: 0) {
                    ProgressWeightStat(title: "Actuel",
                                       value: current.map { ProgressStats.kg($0.kg) } ?? "–",
                                       valueColor: Theme.textPrimary)
                    ProgressWeightStat(title: "Début période",
                                       value: points.first.map { ProgressStats.kg($0.kg) } ?? "–",
                                       valueColor: Theme.textPrimary)
                    ProgressWeightStat(title: "Évolution",
                                       value: weightDelta(points).map { ProgressStats.signedKg($0) } ?? "–",
                                       valueColor: deltaColor(weightDelta(points)))
                }
                .padding(.vertical, 4)

                if points.isEmpty {
                    Text("Aucune pesée sur les \(range.longLabel.lowercased()).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ProgressWeightChart(points: points, targetKg: target,
                                        startDate: startDate, endDate: endDate)
                }

                if let target, let current {
                    let remaining = abs(current.kg - target)
                    let remainingText: String = remaining < 0.05
                        ? "Atteint"
                        : ProgressStats.kg(remaining) + (remaining >= 2 ? " restants" : " restant")
                    Label {
                        HStack {
                            Text("Objectif \(ProgressStats.kg(target))")
                            Spacer()
                            Text(remainingText)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "target")
                            .foregroundStyle(Theme.weight)
                    }
                }

                ForEach(recentWeights, id: \.persistentModelID) { entry in
                    ProgressWeightRow(entry: entry, previousKg: previousKg(before: entry))
                }
                .onDelete(perform: deleteRecentWeights)

                NavigationLink {
                    ProgressWeightHistoryView()
                } label: {
                    Label("Toutes les pesées (\(weights.count))", systemImage: "list.bullet")
                        .foregroundStyle(Theme.textPrimary)
                }

                Button {
                    showingAddWeight = true
                } label: {
                    Label("Ajouter une pesée", systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Label("Poids", systemImage: "scalemass")
        }
    }

    /// Five most recent weighings, newest first.
    private var recentWeights: [WeightEntry] { Array(weights.suffix(5).reversed()) }

    private func previousKg(before entry: WeightEntry) -> Double? {
        guard let index = weights.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }),
              index > 0 else { return nil }
        return weights[index - 1].kg
    }

    private func weightDelta(_ points: [ProgressWeightPoint]) -> Double? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.kg - first.kg
    }

    private func deltaColor(_ delta: Double?) -> Color {
        guard let delta, abs(delta) >= 0.05, let goal = profile?.goal else { return Theme.textPrimary }
        switch goal {
        case .lose: return delta < 0 ? Theme.fiber : Theme.fat
        case .gain: return delta > 0 ? Theme.fiber : Theme.fat
        case .maintain: return abs(delta) <= 1 ? Theme.fiber : Theme.fat
        }
    }

    private func deleteRecentWeights(at offsets: IndexSet) {
        let recent = recentWeights
        for index in offsets where index < recent.count {
            modelContext.delete(recent[index])
        }
        ProgressWeightSync.syncProfileWeight(in: modelContext)
    }

    // MARK: Calories

    @ViewBuilder
    private func caloriesSection(stats: [ProgressDayStat], logged: [ProgressDayStat]) -> some View {
        Section {
            if logged.isEmpty {
                ContentUnavailableView("Aucun repas enregistré",
                                       systemImage: "fork.knife",
                                       description: Text("Les calories des \(range.longLabel.lowercased()) apparaîtront ici."))
            } else {
                ProgressCaloriesChart(stats: stats, target: profile?.calorieTarget ?? 0,
                                      startDate: startDate, endDate: endDate)
                if let target = profile?.calorieTarget, target > 0 {
                    let onTarget = logged.filter { abs($0.calories - target) <= target * 0.1 }.count
                    LabeledContent {
                        Text("\(onTarget)/\(logged.count)")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                    } label: {
                        Text("Jours dans l'objectif (± 10 %)")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        } header: {
            Label("Calories", systemImage: "flame")
        } footer: {
            if !logged.isEmpty {
                Text("Touchez ou faites glisser sur le graphique pour voir un jour précis.")
            }
        }
    }

    // MARK: Macros

    @ViewBuilder
    private func macrosSection(stats: [ProgressDayStat], logged: [ProgressDayStat]) -> some View {
        if !logged.isEmpty {
            let n = Double(logged.count)
            let protein = logged.reduce(0) { $0 + $1.protein } / n
            let carbs = logged.reduce(0) { $0 + $1.carbs } / n
            let fat = logged.reduce(0) { $0 + $1.fat } / n
            let energy = protein * 4 + carbs * 4 + fat * 9
            let share: (Double) -> Double = { energy > 0 ? $0 / energy : 0 }

            Section {
                ProgressMacroAverageRow(label: NutrientKey.protein.label, color: Theme.protein,
                                        grams: protein, target: profile?.proteinTarget ?? 0,
                                        energyShare: share(protein * 4))
                ProgressMacroAverageRow(label: NutrientKey.carbohydrates.label, color: Theme.carbs,
                                        grams: carbs, target: profile?.carbsTarget ?? 0,
                                        energyShare: share(carbs * 4))
                ProgressMacroAverageRow(label: NutrientKey.totalFat.label, color: Theme.fat,
                                        grams: fat, target: profile?.fatTarget ?? 0,
                                        energyShare: share(fat * 9))
                ProgressMacrosChart(stats: stats, startDate: startDate, endDate: endDate)
            } header: {
                Label("Macronutriments", systemImage: "chart.bar.fill")
            } footer: {
                Text("Moyennes par jour suivi. Pourcentages de l'énergie apportée par les protéines, glucides et lipides.")
            }
        }
    }
}

// MARK: - Small components

/// KPI tile: small secondary label with a colored dot, big monospaced number, caption.
struct ProgressOverviewTile: View {
    let title: String
    let color: Color
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}

struct ProgressWeightStat: View {
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
