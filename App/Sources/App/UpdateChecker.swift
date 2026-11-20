import Foundation
import Observation

/// Looks for a newer CI build in the AltStore-format source that CI publishes next to each
/// release (`source.json`). Feather watches the same source and does the signing and install;
/// the app only tells the user a build is waiting and opens Feather.
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable, Sendable {
        let version: String
        let build: Int
        let notes: String?
    }

    nonisolated static let sourceURL = URL(string: "https://github.com/clementtrecourt/assiette/releases/download/latest/source.json")!
    nonisolated static let releasePage = URL(string: "https://github.com/clementtrecourt/assiette/releases/tag/latest")!
    nonisolated static let featherURL = URL(string: "feather://")!
    nonisolated static let bundleIdentifier = "app.assiette.ios"

    private static let dismissedKey = "update.dismissedBuild"
    private static let minimumInterval: TimeInterval = 3600

    private(set) var available: Available?
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Build number of the running app. CI sets it to the workflow run number; local and
    /// simulator builds keep 1 and never prompt.
    static var localBuild: Int? {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) }
    }

    /// Checks again only if the last check is older than an hour (called on every foreground).
    func checkIfStale() async {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.minimumInterval { return }
        await check()
    }

    func check() async {
        lastCheck = .now
        guard let local = Self.localBuild, local > 1 else { return }
        let request = URLRequest(url: Self.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let remote = Self.latest(in: data) else { return }
        let dismissed = defaults.integer(forKey: Self.dismissedKey)
        available = remote.build > local && remote.build != dismissed ? remote : nil
    }

    /// Hides the banner until a newer build than this one is published.
    func dismiss() {
        if let available { defaults.set(available.build, forKey: Self.dismissedKey) }
        available = nil
    }

    /// Demo mode (screenshots): show the banner without touching the network.
    func showDemo() {
        available = Available(version: "0.1.99", build: 99, notes: "Exemple de mise à jour")
    }

    /// Newest version of Assiette listed in an AltStore source document.
    nonisolated static func latest(in data: Data, bundleIdentifier: String = UpdateChecker.bundleIdentifier) -> Available? {
        guard let source = try? JSONDecoder().decode(Source.self, from: data),
              let app = source.apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
        let entries = app.versions ?? []
        let candidates = entries.compactMap { entry -> Available? in
            guard let build = entry.buildVersion.flatMap({ Int($0) })
                ?? entry.version.split(separator: ".").last.flatMap({ Int($0) }) else { return nil }
            return Available(version: entry.version, build: build, notes: entry.localizedDescription)
        }
        return candidates.max { $0.build < $1.build }
    }

    private struct Source: Decodable {
        let apps: [App]
    }

    private struct App: Decodable {
        let bundleIdentifier: String
        let versions: [Version]?
    }

    private struct Version: Decodable {
        let version: String
        let buildVersion: String?
        let localizedDescription: String?
    }
}
