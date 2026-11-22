import HealthKit
import SwiftData
import SwiftUI

/// Reads past data from Apple Health: weigh-ins and daily nutrition totals written by MacroFactor
/// or any other app. The trend weight and the expenditure estimate then start from the whole
/// history instead of from the first day logged in Assiette. Read-only: nothing is written to Health.
@MainActor
enum HealthImport {
    static let enabledKey = "health.enabled"
    static let lastSyncKey = "health.lastSync"
    static let statusKey = "health.status"
    private static let weightAnchorKey = "health.weightAnchor"
    /// How far back the daily nutrition totals are read.
    private static let historyYears = 5

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let store = HKHealthStore()
    private static let massType = HKQuantityType(.bodyMass)
    private static let nutritionTypes: [(type: HKQuantityType, unit: HKUnit)] = [
        (HKQuantityType(.dietaryEnergyConsumed), .kilocalorie()),
        (HKQuantityType(.dietaryProtein), .gram()),
        (HKQuantityType(.dietaryCarbohydrates), .gram()),
        (HKQuantityType(.dietaryFatTotal), .gram()),
    ]

    struct Summary {
        var newWeights: Int
        var nutritionDays: Int
    }

    /// Shows the Health permission sheet (only once: iOS never tells whether reading was allowed).
    static func requestAccess() async throws {
        var types: Set<HKObjectType> = [massType]
        for item in nutritionTypes { types.insert(item.type) }
        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// Imports the new weigh-ins and replaces the daily nutrition totals.
    @discardableResult
    static func sync(context: ModelContext) async throws -> Summary {
        let weights = try await importWeights(context: context)
        let days = try await importNutrition(context: context)
        try context.save()
        // Only now that the weigh-ins are saved can the next sync start after them.
        if let anchor = weights.anchor,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        {
            UserDefaults.standard.set(data, forKey: weightAnchorKey)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        return Summary(newWeights: weights.added, nutritionDays: days)
    }

    /// Stops syncing. Already imported data stays.
    static func disconnect() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: enabledKey)
        defaults.removeObject(forKey: statusKey)
        defaults.removeObject(forKey: lastSyncKey)
        resetWeightAnchor()
    }

    /// The next sync reads every weigh-in again (already known ones are skipped).
    static func resetWeightAnchor() {
        UserDefaults.standard.removeObject(forKey: weightAnchorKey)
    }

    // MARK: Weigh-ins

    /// Adds the Health weigh-ins not seen yet. A reading equal (to 10 g) to one already saved the
    /// same day is skipped, so manual entries and backups are not duplicated. Weigh-ins deleted in
    /// Assiette are not imported again (the query only returns samples newer than the anchor).
    private static func importWeights(context: ModelContext) async throws -> (added: Int, anchor: HKQueryAnchor?) {
        let saved = UserDefaults.standard.data(forKey: weightAnchorKey).flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let query = HKAnchoredObjectQueryDescriptor(predicates: [.quantitySample(type: massType)], anchor: saved)
        let result = try await query.result(for: store)

        let calendar = Calendar.current
        func key(_ date: Date, _ kg: Double) -> String {
            "\(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate)|\(Int((kg * 100).rounded()))"
        }
        var known = Set(try context.fetch(FetchDescriptor<WeightEntry>()).map { key($0.date, $0.kg) })
        let ownBundle = Bundle.main.bundleIdentifier
        var added = 0
        for sample in result.addedSamples where sample.sourceRevision.source.bundleIdentifier != ownBundle {
            let kg = (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 100).rounded() / 100
            guard kg >= 20, kg <= 400, known.insert(key(sample.startDate, kg)).inserted else { continue }
            context.insert(WeightEntry(date: sample.startDate, kg: kg))
            added += 1
        }
        return (added, result.newAnchor)
    }

    // MARK: Nutrition

    /// Replaces the `HealthDay` rows with Health's daily sums (Health merges overlapping sources).
    /// Returns the number of days with calories.
    private static func importNutrition(context: ModelContext) async throws -> Int {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now).adding(days: 1)
        guard let start = calendar.date(byAdding: .year, value: -historyYears, to: end) else { return 0 }
        let range = HKQuery.predicateForSamples(withStart: start, end: end)

        var totals: [Date: [Double?]] = [:]
        for (index, item) in nutritionTypes.enumerated() {
            let query = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: item.type, predicate: range),
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            let collection = try await query.result(for: store)
            for statistics in collection.statistics() {
                guard let sum = statistics.sumQuantity() else { continue }
                let day = calendar.startOfDay(for: statistics.startDate)
                totals[day, default: Array(repeating: nil, count: nutritionTypes.count)][index] = sum.doubleValue(for: item.unit)
            }
        }

        var existing: [Date: HealthDay] = [:]
        for row in try context.fetch(FetchDescriptor<HealthDay>()) {
            if existing[row.day] != nil { context.delete(row) } else { existing[row.day] = row }
        }
        var count = 0
        for (day, values) in totals {
            guard let kcal = values[0], kcal > 0 else { continue }
            let row = existing.removeValue(forKey: day) ?? {
                let created = HealthDay(day: day, kcal: kcal)
                context.insert(created)
                return created
            }()
            row.kcal = kcal.rounded()
            row.protein = values[1].map { $0.rounded() }
            row.carbs = values[2].map { $0.rounded() }
            row.fat = values[3].map { $0.rounded() }
            count += 1
        }
        for stale in existing.values { context.delete(stale) }
        return count
    }
}

/// Syncs Apple Health each time the app comes to the foreground, once connected.
struct HealthSyncModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @AppStorage(HealthImport.enabledKey) private var enabled = false
    @AppStorage(HealthImport.statusKey) private var status = ""

    func body(content: Content) -> some View {
        content.task(id: enabled && phase == .active) {
            guard enabled, phase == .active, !DemoSupport.isDemo, HealthImport.isAvailable else { return }
            do {
                try await HealthImport.sync(context: context)
                status = ""
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

/// Profil › Données › Apple Santé.
struct HealthImportSettings: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var healthDays: [HealthDay]
    @Query private var weights: [WeightEntry]
    @AppStorage(HealthImport.enabledKey) private var enabled = false
    @AppStorage(HealthImport.lastSyncKey) private var lastSync = 0.0
    @AppStorage(HealthImport.statusKey) private var status = ""

    @State private var syncing = false
    @State private var lastSummary: HealthImport.Summary?
    @State private var engineExpenditure: Double?
    @State private var anchorKcal: Double?

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Form {
            Section {
                Text("Assiette lit vos pesées et vos totaux nutritionnels quotidiens enregistrés dans Santé, par exemple par MacroFactor. Ils servent à la tendance de poids et au calcul de la dépense. Un jour noté dans Assiette remplace celui de Santé. Rien n’est écrit dans Santé.")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textSecondary)
                if !HealthImport.isAvailable {
                    Text("Santé n’est pas disponible sur cet appareil.")
                } else if enabled {
                    Button(syncing ? "Synchronisation…" : "Synchroniser maintenant") { Task { await sync() } }
                        .disabled(syncing)
                    Button("Déconnecter", role: .destructive) { HealthImport.disconnect() }
                } else {
                    Button("Connecter Apple Santé") { Task { await connect() } }
                        .disabled(syncing)
                }
            } header: {
                ProfileSectionHeader("Apple Santé")
            } footer: {
                ProfileSectionFooter(statusText)
            }

            if enabled || !healthDays.isEmpty {
                Section {
                    LabeledContent("Jours de repas importés", value: "\(healthDays.count)")
                    if let range = importedRange { LabeledContent("Période", value: range) }
                    LabeledContent("Pesées dans Assiette", value: "\(weights.count)")
                } header: {
                    ProfileSectionHeader("Données importées")
                }
            }

            if let profile {
                expenditureSection(profile)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Apple Santé")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(healthDays.count)|\(weights.count)|\(profile?.expenditureAnchorKcal ?? 0)") {
            refreshEstimate()
        }
    }

    // MARK: Expenditure anchor

    @ViewBuilder
    private func expenditureSection(_ profile: UserProfile) -> some View {
        Section {
            LabeledContent("Estimation d’Assiette", value: engineExpenditure.map { Formatters.kcal($0) } ?? "–")
            ProfileNumberField("Dépense MacroFactor", value: $anchorKcal, unit: "kcal", maxFractionDigits: 0,
                               placeholder: "2400")
            Button("Repartir de cette dépense aujourd’hui") { applyAnchor(profile) }
                .disabled(!(1000...6000).contains(anchorKcal ?? 0))
            if let kcal = profile.expenditureAnchorKcal, let date = profile.expenditureAnchorDate {
                LabeledContent("Recalée le \(date.formatted(.dateTime.day().month()))", value: Formatters.kcal(kcal))
                Button("Annuler le recalage", role: .destructive) {
                    profile.expenditureAnchorKcal = nil
                    profile.expenditureAnchorDate = nil
                    try? context.save()
                }
            }
        } header: {
            ProfileSectionHeader("Dépense")
        } footer: {
            ProfileSectionFooter("Santé ne contient pas la dépense calculée par MacroFactor. Assiette la recalcule avec le même principe à partir de l’historique, avec un écart possible d’une centaine de kcal. Pour garder exactement celle de MacroFactor, saisissez la valeur affichée aujourd’hui dans MacroFactor : Assiette repart de ce chiffre et l’ajuste ensuite avec vos repas et vos pesées.")
        }
    }

    private func applyAnchor(_ profile: UserProfile) {
        guard let kcal = anchorKcal else { return }
        profile.expenditureAnchorKcal = kcal.rounded()
        profile.expenditureAnchorDate = Calendar.current.startOfDay(for: .now)
        try? context.save()
        anchorKcal = nil
        refreshEstimate()
    }

    private func refreshEstimate() {
        guard let profile else { return }
        let snapshot = CoachingService.snapshot(profile: profile, context: context)
        engineExpenditure = snapshot.isEmpty ? nil : snapshot.expenditure
    }

    // MARK: Sync

    private var importedRange: String? {
        let days = healthDays.map(\.day)
        guard let first = days.min(), let last = days.max() else { return nil }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    private var statusText: String {
        if !status.isEmpty { return "Erreur : \(status)" }
        guard enabled else { return "La synchronisation se refait à chaque ouverture de l’app." }
        var text = lastSync > 0
            ? "Dernière synchronisation : \(Date(timeIntervalSince1970: lastSync).formatted(date: .abbreviated, time: .shortened))."
            : "Pas encore synchronisé."
        if let lastSummary {
            text += " \(lastSummary.newWeights) nouvelle\(lastSummary.newWeights > 1 ? "s" : "") pesée\(lastSummary.newWeights > 1 ? "s" : ""), \(lastSummary.nutritionDays) jour\(lastSummary.nutritionDays > 1 ? "s" : "") de repas."
            if lastSummary.newWeights == 0, lastSummary.nutritionDays == 0 {
                text += " Si rien n’arrive, autorisez la lecture dans Réglages › Santé › Accès aux données et appareils › Assiette."
            }
        }
        return text
    }

    private func connect() async {
        syncing = true
        defer { syncing = false }
        do {
            try await HealthImport.requestAccess()
            enabled = true
            status = ""
        } catch {
            status = error.localizedDescription
            return
        }
        await runSync()
    }

    private func sync() async {
        syncing = true
        defer { syncing = false }
        await runSync()
    }

    private func runSync() async {
        do {
            lastSummary = try await HealthImport.sync(context: context)
            status = ""
        } catch {
            status = error.localizedDescription
        }
        refreshEstimate()
    }
}
