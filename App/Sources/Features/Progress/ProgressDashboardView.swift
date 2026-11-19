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
                ProgressRangeChips(rangeRaw: $rangeRaw)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                    .listRowSeparator(.hidden)

                overviewGrid(stats: stats, logged: logged, points: rangePoints)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Theme.background)

            weightSection(points: rangePoints)
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.separator)
            caloriesSection(stats: stats, logged: logged)
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.separator)
            macrosSection(stats: stats, logged: logged)
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.separator)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(28))
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

    private func overviewGrid(stats: [ProgressDayStat], logged: [ProgressDayStat],
                              points: [ProgressWeightPoint]) -> some View {
        let average = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.calories } / Double(logged.count)
        let target = profile?.calorieTarget ?? 0
        let averageDetail: String = target > 0 ? "objectif \(Formatters.kcal(target))" : "par jour suivi"
        let trend = points.last.map { ProgressStats.kg($0.average) } ?? "–"
        let delta = weightDelta(points).map { ProgressStats.signedKg($0) } ?? "–"
        let streakTile = ProgressOverviewTile(title: "Série", color: Theme.textTertiary,
                                              value: "\(streak)",
                                              detail: streak > 1 ? "jours d'affilée" : "jour d'affilée")
        let daysTile = ProgressOverviewTile(title: "Jours suivis", color: Theme.textTertiary,
                                            value: "\(logged.count)/\(stats.count)",
                                            detail: range.longLabel.lowercased())
        let kcalTile = ProgressOverviewTile(title: "Kcal moyennes", color: Theme.calories,
                                            value: logged.isEmpty ? "–" : Formatters.number(average, maxFractionDigits: 0),
                                            detail: averageDetail)
        let weightTile = ProgressOverviewTile(title: "Poids tendance", color: Theme.weight,
                                              value: trend,
                                              detail: "évolution \(delta)")
        // 2×2 grid separated by hairlines (no cards).
        return VStack(spacing: 0) {
            ProgressHairline()
            ProgressOverviewRow(leading: streakTile, trailing: daysTile)
            ProgressHairline()
            ProgressOverviewRow(leading: kcalTile, trailing: weightTile)
            ProgressHairline()
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
                        .font(Theme.title)
                        .foregroundStyle(Theme.textPrimary)
                } description: {
                    Text("Enregistrez votre poids régulièrement pour voir la tendance.")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.textSecondary)
                } actions: {
                    Button {
                        showingAddWeight = true
                    } label: {
                        Text("Ajouter une pesée")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }
                    .buttonStyle(.plain)
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
                        .font(Theme.callout)
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
                                .font(Theme.body)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textBody)
                            Spacer()
                            Text(remainingText)
                                .font(Theme.callout)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
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
                        .font(Theme.body)
                        .foregroundStyle(Theme.textBody)
                }

                Button {
                    showingAddWeight = true
                } label: {
                    Label("Ajouter une pesée", systemImage: "plus.circle.fill")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        } header: {
            ProgressSectionHeader(title: "Poids")
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
                ThemedUnavailableView(title: "Aucun repas enregistré",
                                      systemImage: "fork.knife",
                                      description: "Les calories des \(range.longLabel.lowercased()) apparaîtront ici.")
            } else {
                ProgressCaloriesChart(stats: stats, target: profile?.calorieTarget ?? 0,
                                      startDate: startDate, endDate: endDate)
                if let target = profile?.calorieTarget, target > 0 {
                    let onTarget = logged.filter { abs($0.calories - target) <= target * 0.1 }.count
                    LabeledContent {
                        Text("\(onTarget)/\(logged.count)")
                            .font(Theme.headline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    } label: {
                        Text("Jours dans l'objectif (± 10 %)")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textBody)
                    }
                }
            }
        } header: {
            ProgressSectionHeader(title: "Calories")
        } footer: {
            if !logged.isEmpty {
                ProgressSectionFooter(text: "Touchez ou faites glisser sur le graphique pour voir un jour précis.")
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
                ProgressSectionHeader(title: "Macronutriments")
            } footer: {
                ProgressSectionFooter(text: "Moyennes par jour suivi. Pourcentages de l'énergie apportée par les protéines, glucides et lipides.")
            }
        }
    }
}

// MARK: - Small components

/// Section header: small uppercase label in textTertiary (DESIGN.md).
struct ProgressSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// Section footer: caption in textTertiary.
struct ProgressSectionFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// 1 px horizontal hairline.
struct ProgressHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
    }
}

/// Range selector as chips: selected = white fill + near-black text,
/// unselected = 1 px separatorStrong outline + textSecondary.
struct ProgressRangeChips: View {
    @Binding var rangeRaw: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ProgressRange.allCases) { r in
                chip(r)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ r: ProgressRange) -> some View {
        let selected = r.rawValue == rangeRaw
        return Button {
            rangeRaw = r.rawValue
        } label: {
            Text(r.label)
                .font(Theme.font(13, selected ? .bold : .medium, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 30)
                .background(Capsule().fill(selected ? Theme.accent : Color.clear))
                .overlay(Capsule().strokeBorder(selected ? Theme.accent : Theme.separatorStrong,
                                                lineWidth: Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.longLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One row of the 2×2 KPI grid: two tiles split by a vertical hairline.
struct ProgressOverviewRow: View {
    let leading: ProgressOverviewTile
    let trailing: ProgressOverviewTile

    var body: some View {
        HStack(spacing: 0) {
            leading
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(width: Theme.hairline)
                }
            trailing
                .padding(.leading, 16)
        }
    }
}

/// KPI tile (no card): tiny uppercase label (in `color`), big monospaced number, caption.
struct ProgressOverviewTile: View {
    let title: String
    let color: Color
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.label)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(Theme.numberLarge)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.trailing, 12)
    }
}

struct ProgressWeightStat: View {
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(Theme.label)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(Theme.headline)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
