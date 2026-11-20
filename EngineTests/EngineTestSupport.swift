import Foundation
@testable import AssietteEngine

/// Deterministic pseudo-random generator (SplitMix64) so synthetic histories are reproducible.
struct EngineTestRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// Approximately normal noise (sum of uniforms), mean 0, standard deviation `sd`.
    mutating func gaussian(sd: Double) -> Double {
        var sum = 0.0
        for _ in 0..<12 { sum += next() }
        return (sum - 6) * sd
    }
}

enum EngineFixtures {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func date(_ dayOffset: Int) -> Date {
        // 2026-05-29 00:00 UTC.
        calendar.date(byAdding: .day, value: dayOffset, to: Date(timeIntervalSince1970: 1_780_012_800))!
    }

    /// Person with a constant true expenditure eating `intake` ± noise; the true weight follows the
    /// energy balance with `density` kcal/kg and the scale adds water noise.
    static func synthetic(days: Int, trueExpenditure: Double, intake: Double, startWeight: Double = 80,
                          density: Double = EngineParameters.calibrated.expenditureEnergyDensity,
                          seed: UInt64 = 42) -> [EngineDay]
    {
        var rng = EngineTestRandom(seed: seed)
        var weight = startWeight
        return (0..<days).map { i in
            let eaten = intake + rng.gaussian(sd: 300)
            weight += (eaten - trueExpenditure) / density
            return EngineDay(date: date(i), intakeKcal: eaten, scaleWeightKg: weight + rng.gaussian(sd: 0.4))
        }
    }
}

/// The owner's MacroFactor export converted by `tools/mf/parse_export.py` into `reference/`
/// (gitignored, personal data). Tests that need it are skipped when it is absent (CI).
enum EngineReference {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("reference")

    static func table(_ name: String) -> [[String: String]]? {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else { return nil }
        var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        guard !lines.isEmpty else { return nil }
        let header = lines.removeFirst()
        return lines.map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
    }
}

extension Dictionary where Key == String, Value == String {
    func number(_ key: String) -> Double? { self[key].flatMap(Double.init) }
}

func engineRMSE(_ pairs: [(Double, Double)]) -> (rmse: Double, max: Double) {
    let errors = pairs.map { $0.0 - $0.1 }
    let rmse = (errors.map { $0 * $0 }.reduce(0, +) / Double(errors.count)).squareRoot()
    return (rmse, errors.map(abs).max() ?? 0)
}
