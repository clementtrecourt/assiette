import BackgroundTasks
import CryptoKit
import Security
import SwiftData
import SwiftUI

// Weekly report shared with the Sunday T3 job (openGym plan + nutrition review).
// The app PUTs the last 28 days to tools/nutrition-sync/receiver.py after each edit, when it
// comes to the foreground and from a background refresh, so the job finds fresh data even when
// the phone has not been opened that day. The job reads it with tools/nutrition-sync/weekly_summary.py.

private struct DailyMacros: Encodable {
    var kcal, proteinG, carbsG, fatG: Double?
    init(_ values: NutrientValues) {
        kcal = values[.calories]
        proteinG = values[.protein]
        carbsG = values[.carbohydrates]
        fatG = values[.totalFat]
    }

    init(_ health: HealthDay) {
        kcal = health.kcal
        proteinG = health.protein
        carbsG = health.carbs
        fatG = health.fat
    }
}

private struct NutritionDay: Encodable {
    var date, status: String
    /// "assiette" (journal) or "health" (Apple Health import, used only when nothing was logged here).
    var source: String?
    var intake, targets: DailyMacros?
    var weightKg, trendKg, expenditureKcal: Double?
}

private struct NutritionGoal: Encodable {
    var kind: String
    var weeklyRatePercent: Double
    var targetWeightKg: Double?
}

private struct NutritionReport: Encodable {
    let version = 1
    var revision: Int
    var generatedAt: Date
    var timeZone: String
    var goal: NutritionGoal
    var days: [NutritionDay]

    @MainActor static func build(_ context: ModelContext, revision: Int) throws -> Self {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let profile = try context.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])).first else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let exceptions = try context.fetch(FetchDescriptor<ExceptionPeriod>())
        let healthDays = try context.fetch(FetchDescriptor<HealthDay>())
        let changes = try context.fetch(FetchDescriptor<CoachingCheckIn>(sortBy: [SortDescriptor(\.date)]))
        let meals = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.day) }
        let health = Dictionary(healthDays.filter { $0.kcal > 0 }.map { (calendar.startOfDay(for: $0.day), $0) }) { a, _ in a }
        let readings = Dictionary(grouping: weights) { calendar.startOfDay(for: $0.date) }
        let engine = CoachingService.snapshot(profile: profile, context: context, today: today)
        let results = Dictionary(engine.days.map { ($0.date, $0) }) { a, _ in a }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let overrides = WeekdayCalorieTargets.current
        let preferences = ProgramPreferences.current
        let days = (0..<28).reversed().map { offset -> NutritionDay in
            let day = today.adding(days: -offset)
            let end = day.adding(days: 1)
            // Same rule as the engine: an Apple Health day counts only when nothing was logged in Assiette.
            var source: String?
            var intake: DailyMacros?
            if let logged = meals[day] {
                source = "assiette"
                intake = DailyMacros(NutrientValues.sum(logged.map(\.nutrients)))
            } else if let imported = health[day] {
                source = "health"
                intake = DailyMacros(imported)
            }
            let status = exceptions.contains { $0.contains(day) } ? "excluded"
                : offset == 0 ? "in_progress" : intake == nil ? "missing" : "logged"
            var targets: DailyMacros?
            if offset == 0 {
                targets = DailyMacros(profile.targets(on: day))
            } else if let change = changes.last(where: { $0.date < end }) {
                targets = DailyMacros(change.targets(on: day, preferences: preferences, overrides: overrides))
            } else if overrides.calories(on: day) != nil {
                targets = DailyMacros(profile.targets(on: day))
            }
            return NutritionDay(date: formatter.string(from: day), status: status, source: source, intake: intake,
                                targets: targets,
                                weightKg: readings[day].map { $0.map(\.kg).reduce(0, +) / Double($0.count) },
                                trendKg: results[day]?.smoothedTrendKg, expenditureKcal: results[day]?.expenditure)
        }
        let goal = NutritionGoal(kind: profile.goal.rawValue, weeklyRatePercent: profile.effectiveRatePercent,
                                 targetWeightKg: profile.targetWeightKg)
        return Self(revision: revision, generatedAt: now, timeZone: calendar.timeZone.identifier, goal: goal, days: days)
    }
}

private enum SyncCredential {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: "app.assiette.nutrition-sync",
                                       kSecAttrAccount as String: "writer"]
    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Readable after the first unlock so a background refresh can send while the phone is locked.
    static func save(_ token: String) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        return result == errSecSuccess
    }
}

/// A private LAN receiver can be paired by its certificate SHA-256 fingerprint.
private final class NutritionTransport: NSObject, URLSessionTaskDelegate {
    let fingerprint: String?
    init(fingerprint: String?) { self.fingerprint = fingerprint }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let fingerprint, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        else { completionHandler(.performDefaultHandling, nil); return }
        guard let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first
        else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Builds and sends one report. Shared by the foreground loop and the background refresh.
enum NutritionSync {
    static let enabledKey = "nutritionSync.enabled"
    static let urlKey = "nutritionSync.url"
    static let archiveKey = "nutritionSync.fullArchive"
    static let ackKey = "nutritionSync.pendingAck"
    static let ackStatusKey = "nutritionSync.pendingAckStatus"
    static let syncNow = Notification.Name("assiette.syncNow")
    @MainActor private static var sending = false
    static let lastKey = "nutritionSync.last"
    static let statusKey = "nutritionSync.status"
    static let revisionKey = "nutritionSync.revision"
    /// Also listed under BGTaskSchedulerPermittedIdentifiers in App/Info.plist.
    static let refreshTaskID = "app.assiette.nutrition-sync.refresh"

    struct Destination: Equatable {
        var url: URL
        var token: String
        var archive: Bool
    }

    static func pairingURL(_ address: String) -> URL? {
        guard let url = URL(string: address), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil,
              url.path == "/api/nutrition/snapshot" else { return nil }
        if let pin = url.fragment, !pin.isEmpty {
            guard pin.count == 64, pin.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        }
        return url
    }

    struct Reply: Decodable {
        /// Queued on the server by tools/nutrition-sync/archive.py.
        struct Command: Decodable {
            var id: Int
            var type: String
            var weekday: Int?
            var kcal: Int?
            /// Full replacement; nil when it does not decode, so it is reported invalid, never half-applied.
            var backup: ProfileBackup?

            private enum CodingKeys: String, CodingKey { case id, type, weekday, kcal, backup }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(Int.self, forKey: .id)
                type = try c.decodeIfPresent(String.self, forKey: .type) ?? "weekday"
                weekday = try c.decodeIfPresent(Int.self, forKey: .weekday)
                kcal = try c.decodeIfPresent(Int.self, forKey: .kcal)
                backup = try? c.decodeIfPresent(ProfileBackup.self, forKey: .backup)
            }
        }
        var command: Command?
    }

    enum Outcome: String { case applied, conflict, invalid }

    /// Applies one server command. A replacement only goes through when the phone still holds
    /// exactly the data it just sent (`sent`): anything logged since then wins over the server.
    @MainActor
    static func apply(_ command: Reply.Command, sent: Data, exportedAt: Date, context: ModelContext,
                      encoder: JSONEncoder) throws -> Outcome {
        switch command.type {
        case "weekday":
            guard let day = command.weekday, WeekdayCalorieTargets.set(command.kcal, forISOWeekday: day) else {
                return .invalid
            }
            return .applied
        case "replace":
            guard let replacement = command.backup, replacement.version == 1, replacement.app == "Assiette" else {
                return .invalid
            }
            var current = try ProfileBackupService.makeBackup(context: context)
            current.exportedAt = exportedAt
            guard try encoder.encode(current) == sent else { return .conflict }
            try ProfileBackupService.importBackup(replacement, mode: .replace, context: context)
            return .applied
        default:
            return .invalid
        }
    }

    /// Deterministic bytes, so the phone can tell whether its data changed since an upload.
    static func archiveEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    struct ReceiverError: LocalizedError {
        var status: Int
        var errorDescription: String? {
            switch status {
            case 401: return "Clé d’écriture refusée."
            case 404: return "Point de synchronisation introuvable. Vérifiez la version du récepteur."
            case 413: return "L’archive dépasse la taille acceptée par le serveur."
            default: return "Le serveur a répondu HTTP \(status)."
            }
        }
    }

    static var destination: Destination? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey), !DemoSupport.isDemo,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let url = pairingURL(defaults.string(forKey: urlKey) ?? ""),
              let token = SyncCredential.read() else { return nil }
        return Destination(url: url, token: token, archive: defaults.bool(forKey: archiveKey))
    }

    @MainActor private static func nextRevision() -> Int {
        let defaults = UserDefaults.standard
        let revision = max(defaults.integer(forKey: revisionKey) + 1, Int(Date().timeIntervalSince1970 * 1000))
        defaults.set(revision, forKey: revisionKey)
        return revision
    }

    @MainActor static func send(_ context: ModelContext, to destination: Destination) async throws {
        guard !sending else { throw URLError(.resourceUnavailable) }
        sending = true
        defer { sending = false }
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let session = URLSession(configuration: .ephemeral,
                                 delegate: NutritionTransport(fingerprint: destination.url.fragment), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var parts = URLComponents(url: destination.url, resolvingAgainstBaseURL: false)!
        parts.fragment = nil
        guard let reportURL = parts.url else { throw URLError(.badURL) }
        parts.path = "/api/nutrition/archive"
        guard let archiveURL = parts.url else { throw URLError(.badURL) }

        func request(_ url: URL) -> URLRequest {
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "PUT"
            request.setValue("Bearer " + destination.token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return request
        }

        // Stops as soon as sync is turned off or re-paired, so nothing reaches a server the user left.
        func put(_ request: URLRequest, _ body: Data, expecting code: Int) async throws -> Data {
            try Task.checkCancellation()
            guard NutritionSync.destination == destination else { throw CancellationError() }
            let (data, response) = try await session.upload(for: request, from: body)
            try Task.checkCancellation()
            guard NutritionSync.destination == destination else { throw CancellationError() }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == code else { throw ReceiverError(status: status) }
            return data
        }

        let report = try NutritionReport.build(context, revision: nextRevision())
        _ = try await put(request(reportURL), encoder.encode(report), expecting: 204)
        if destination.archive {
            let stable = archiveEncoder()
            let replyDecoder = JSONDecoder()
            replyDecoder.dateDecodingStrategy = .iso8601
            while true {
                let ack = defaults.integer(forKey: ackKey)
                var upload = request(archiveURL)
                if ack > 0 {
                    upload.setValue(String(ack), forHTTPHeaderField: "X-Assiette-Ack")
                    upload.setValue(defaults.string(forKey: ackStatusKey) ?? Outcome.applied.rawValue,
                                    forHTTPHeaderField: "X-Assiette-Ack-Status")
                }
                upload.setValue(String(nextRevision()), forHTTPHeaderField: "X-Assiette-Revision")
                let archive = try ProfileBackupService.makeBackup(context: context)
                let sent = try stable.encode(archive)
                let data = try await put(upload, sent, expecting: 200)
                guard let command = try replyDecoder.decode(Reply.self, from: data).command else {
                    defaults.removeObject(forKey: ackKey)
                    defaults.removeObject(forKey: ackStatusKey)
                    break
                }
                guard command.id > 0, command.id != ack else { throw URLError(.cannotParseResponse) }
                let outcome = try apply(command, sent: sent, exportedAt: archive.exportedAt,
                                        context: context, encoder: stable)
                defaults.set(command.id, forKey: ackKey)
                defaults.set(outcome.rawValue, forKey: ackStatusKey)
            }
        }
        defaults.set(Date().timeIntervalSince1970, forKey: lastKey)
        defaults.set(destination.archive ? "Archive complète synchronisée" : "Bilan synchronisé", forKey: statusKey)
    }

    /// Asks iOS for a background run in a couple of hours (iOS picks the actual time).
    static func scheduleRefresh() {
        guard destination != nil else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Background refresh: reschedules itself, then sends with a context on the app's store.
    @MainActor static func backgroundRefresh() async {
        scheduleRefresh()
        guard let destination else { return }
        do {
            let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration())
            try await send(ModelContext(container), to: destination)
        } catch {
            UserDefaults.standard.set("En attente · \(error.localizedDescription)", forKey: statusKey)
        }
    }
}

struct NutritionSyncSettings: View {
    @AppStorage(NutritionSync.enabledKey) private var enabled = false
    @AppStorage(NutritionSync.urlKey) private var address = ""
    @AppStorage(NutritionSync.archiveKey) private var archive = false
    @AppStorage(NutritionSync.lastKey) private var last = 0.0
    @AppStorage(NutritionSync.statusKey) private var status = ""
    @State private var token = ""
    var body: some View {
        Form {
            Section("Serveur personnel") {
                Text("Utilisez l’adresse HTTPS et la clé d’écriture d’appairage du serveur. Le bilan hebdomadaire contient les totaux, les objectifs et les pesées des 28 derniers jours.")
                TextField("URL HTTPS du relevé", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(enabled)
                    .onChange(of: address) { _, _ in
                        token = ""
                        archive = false
                        UserDefaults.standard.removeObject(forKey: NutritionSync.ackKey)
                        UserDefaults.standard.removeObject(forKey: NutritionSync.ackStatusKey)
                    }
                SecureField("Clé d’écriture", text: $token).disabled(enabled)
                Toggle("Synchroniser", isOn: Binding(get: { enabled }, set: { active in
                    if active && !SyncCredential.save(token) { status = "Clé impossible à enregistrer."; return }
                    enabled = active
                    status = active ? "En attente" : ""
                    NutritionSync.scheduleRefresh()
                })).disabled(!enabled && (NutritionSync.pairingURL(address) == nil || token.isEmpty))
            }
            Section {
                Toggle("Synchroniser toutes mes données", isOn: $archive).disabled(!enabled)
            } footer: {
                Text("En plus du bilan, envoie tout l’historique : journal, pesées, totaux importés de Santé, eau, recettes, favoris, profil et programme. Les agents du serveur (Claude, Codex) peuvent tout lire et tout modifier : leurs changements s’appliquent au prochain envoi, sauf si vous avez modifié quelque chose sur l’iPhone entre-temps. Le serveur garde les versions précédentes. Désactiver arrête les envois et les modifications sans effacer la copie déjà reçue.")
            }
            Section {
                Button("Synchroniser maintenant") {
                    status = "En attente"
                    NotificationCenter.default.post(name: NutritionSync.syncNow, object: nil)
                }.disabled(!enabled)
                if !status.isEmpty { Text(status) }
                if last > 0 { Text("Dernier envoi réussi : \(Date(timeIntervalSince1970: last).formatted())") }
            }
        }
        .navigationTitle("Synchronisation serveur")
        .onAppear { token = SyncCredential.read() ?? "" }
    }
}

/// Foreground sync: sends after every save (debounced) and every hour while the app is open,
/// and schedules a background refresh whenever the app leaves the foreground.
@MainActor
struct NutritionSyncModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @AppStorage(NutritionSync.enabledKey) private var enabled = false
    @AppStorage(NutritionSync.statusKey) private var status = ""
    @State private var generation = 0
    @AppStorage(NutritionSync.archiveKey) private var archive = false
    @AppStorage(WeekdayCalorieTargets.storageKey) private var weekdayData = Data()
    @AppStorage(ProgramPreferences.storageKey) private var programData = Data()
    @AppStorage("profile.displayName") private var displayName = ""
    @AppStorage(CoachingSettings.collaborativeKey) private var collaborative = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in generation &+= 1 }
            .onReceive(NotificationCenter.default.publisher(for: NutritionSync.syncNow)) { _ in generation &+= 1 }
            .onChange(of: weekdayData) { _, _ in generation &+= 1 }
            .onChange(of: programData) { _, _ in generation &+= 1 }
            .onChange(of: displayName) { _, _ in generation &+= 1 }
            .onChange(of: collaborative) { _, _ in generation &+= 1 }
            .onChange(of: phase) { _, newPhase in
                if newPhase == .background { NutritionSync.scheduleRefresh() }
            }
            .task(id: "\(enabled)-\(archive)-\(phase == .active)-\(generation)") {
                guard enabled, phase == .active, let destination = NutritionSync.destination else { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                    while !Task.isCancelled {
                        do {
                            try await NutritionSync.send(context, to: destination)
                            try await Task.sleep(for: .seconds(3600))
                        } catch {
                            try Task.checkCancellation()
                            status = "En attente · \(error.localizedDescription)"
                            try await Task.sleep(for: .seconds(60))
                        }
                    }
                } catch { /* A new edit or foreground transition schedules a fresh report. */ }
            }
    }
}
