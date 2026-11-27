import SwiftData
import XCTest
@testable import Assiette

final class NutritionSyncTests: XCTestCase {
    private let pin = String(repeating: "ab", count: 32)

    func testPairingURLNeedsHTTPSSnapshotPathAndLowercaseHexPin() {
        XCTAssertNotNil(NutritionSync.pairingURL("https://192.168.1.10:8341/api/nutrition/snapshot#\(pin)"))
        XCTAssertNotNil(NutritionSync.pairingURL("https://nutrition.example/api/nutrition/snapshot"))
        XCTAssertNil(NutritionSync.pairingURL("http://192.168.1.10:8341/api/nutrition/snapshot#\(pin)"))
        XCTAssertNil(NutritionSync.pairingURL("https://192.168.1.10:8341/api/nutrition/archive#\(pin)"))
        XCTAssertNil(NutritionSync.pairingURL("https://192.168.1.10:8341/api/nutrition/snapshot#\(pin.uppercased())"))
        XCTAssertNil(NutritionSync.pairingURL("https://192.168.1.10:8341/api/nutrition/snapshot#abc"))
        XCTAssertNil(NutritionSync.pairingURL("https://u:p@192.168.1.10:8341/api/nutrition/snapshot"))
    }

    /// tools/nutrition-sync/archive.py validates exactly these keys and shapes.
    @MainActor
    func testArchiveHasTheShapeTheReceiverAccepts() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let health = HealthDay(day: .now, kcal: 1850)
        health.protein = 120
        context.insert(health)
        try context.save()

        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: WeekdayCalorieTargets.storageKey)
        defer { defaults.set(saved, forKey: WeekdayCalorieTargets.storageKey) }
        defaults.removeObject(forKey: WeekdayCalorieTargets.storageKey)
        WeekdayCalorieTargets.set(1500, forISOWeekday: 1)
        WeekdayCalorieTargets.set(2000, forISOWeekday: 2)

        let data = try ProfileBackupService.encode(ProfileBackupService.makeBackup(context: context))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["app"] as? String, "Assiette")
        let stamp = try XCTUnwrap(json["exportedAt"] as? String)
        XCTAssertTrue(stamp.contains("T") && stamp.hasSuffix("Z"))
        for key in ["entries", "weights", "water", "customFoods", "favorites", "exceptions", "checkIns", "healthDays"] {
            XCTAssertNotNil(json[key] as? [Any], key)
        }
        XCTAssertNotNil(json["programPreferences"] as? [String: Any])
        XCTAssertEqual(json["weekdayCalorieTargets"] as? [String: Int], ["1": 1500, "2": 2000])

        let decoded = try ProfileBackupService.decode(data)
        XCTAssertEqual(decoded.weekdayCalorieTargets, [1: 1500, 2: 2000])
        XCTAssertEqual(decoded.healthDays.map(\.kcal), [1850])
        XCTAssertEqual(decoded.healthDays.first?.protein, 120)
    }

    private func command(_ json: String) throws -> NutritionSync.Reply.Command {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try XCTUnwrap(decoder.decode(NutritionSync.Reply.self, from: Data(json.utf8)).command)
    }

    /// A server replacement applies only to the exact data the phone just uploaded.
    @MainActor
    func testReplaceAppliesOnlyWhenNothingChangedSinceTheUpload() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = UserDefaults.standard
        let keys = [WeekdayCalorieTargets.storageKey, ProgramPreferences.storageKey, "profile.displayName"]
            + ProfileBackup.settingKeys
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        let bread = FoodItem(source: .quickAdd, ref: nil, name: "Pain", per100: NutrientValues([.calories: 250]))
        context.insert(JournalEntry(item: bread, grams: 100, day: .now, meal: .lunch))
        try context.save()
        let encoder = NutritionSync.archiveEncoder()
        let uploaded = try ProfileBackupService.makeBackup(context: context)
        let sent = try encoder.encode(uploaded)

        let replace = try command("""
            {"command":{"id":7,"type":"replace","backup":{"version":1,"app":"Assiette",
            "exportedAt":"2026-11-27T10:00:00Z","entries":[],"weights":[{"date":"2026-11-27T07:00:00Z","kg":74.2}],
            "water":[],"customFoods":[],"favorites":[],"exceptions":[],"checkIns":[],"healthDays":[],
            "programPreferences":{},"weekdayCalorieTargets":{"3":1700},"settings":{"today.hideEmptyHours":true}}}}
            """)
        XCTAssertNotNil(replace.backup)

        // Something logged after the upload: the phone keeps its data.
        context.insert(JournalEntry(item: bread, grams: 50, day: .now, meal: .dinner))
        try context.save()
        XCTAssertEqual(try NutritionSync.apply(replace, sent: sent, exportedAt: uploaded.exportedAt,
                                               context: context, encoder: encoder), .conflict)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 2)

        let current = try ProfileBackupService.makeBackup(context: context)
        XCTAssertEqual(try NutritionSync.apply(replace, sent: encoder.encode(current), exportedAt: current.exportedAt,
                                               context: context, encoder: encoder), .applied)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WeightEntry>()).map(\.kg), [74.2])
        XCTAssertEqual(WeekdayCalorieTargets.current.values, [3: 1700])
        XCTAssertEqual(defaults.object(forKey: "today.hideEmptyHours") as? Bool, true)
    }

    @MainActor
    func testMalformedCommandsAreInvalidNotApplied() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let encoder = NutritionSync.archiveEncoder()
        let backup = try ProfileBackupService.makeBackup(context: context)
        let sent = try encoder.encode(backup)
        for json in [#"{"command":{"id":1,"type":"replace","backup":{"entries":"oops"}}}"#,
                     #"{"command":{"id":2,"type":"weekday","weekday":9,"kcal":1500}}"#,
                     #"{"command":{"id":3,"type":"delete-everything"}}"#] {
            XCTAssertEqual(try NutritionSync.apply(command(json), sent: sent, exportedAt: backup.exportedAt,
                                                   context: context, encoder: encoder), .invalid, json)
        }
    }

    @MainActor
    func testOlderBackupsStillDecode() throws {
        let old = Data(#"{"version":1,"app":"Assiette","exportedAt":"2026-01-01T00:00:00Z","entries":[]}"#.utf8)
        let backup = try ProfileBackupService.decode(old)
        XCTAssertTrue(backup.healthDays.isEmpty)
        XCTAssertNil(backup.programPreferences)
        XCTAssertNil(backup.weekdayCalorieTargets)
    }
}
