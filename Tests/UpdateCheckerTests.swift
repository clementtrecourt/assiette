import XCTest
@testable import Assiette

/// Parsing of the AltStore source that CI publishes with each release.
final class UpdateCheckerTests: XCTestCase {
    private func source(_ versions: String, bundleID: String = "app.assiette.ios") -> Data {
        Data("""
        {"name": "Assiette", "apps": [{"name": "Assiette", "bundleIdentifier": "\(bundleID)", "versions": [\(versions)]}]}
        """.utf8)
    }

    func testReadsBuildVersion() {
        let data = source(#"{"version": "0.1.42", "buildVersion": "42", "localizedDescription": "Notes"}"#)
        XCTAssertEqual(UpdateChecker.latest(in: data),
                       UpdateChecker.Available(version: "0.1.42", build: 42, notes: "Notes"))
    }

    func testFallsBackToLastVersionComponent() {
        let data = source(#"{"version": "0.1.7"}"#)
        XCTAssertEqual(UpdateChecker.latest(in: data)?.build, 7)
    }

    func testPicksNewestBuild() {
        let data = source(#"{"version": "0.1.5", "buildVersion": "5"}, {"version": "0.1.9", "buildVersion": "9"}"#)
        XCTAssertEqual(UpdateChecker.latest(in: data)?.version, "0.1.9")
    }

    func testIgnoresOtherApps() {
        XCTAssertNil(UpdateChecker.latest(in: source(#"{"version": "1.0.3"}"#, bundleID: "other.app")))
        XCTAssertNil(UpdateChecker.latest(in: Data("not json".utf8)))
    }
}
