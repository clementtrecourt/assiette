import XCTest
@testable import AssietteEngine

final class EngineWeightTrendTests: XCTestCase {
    func testConstantWeightGivesFlatTrend() {
        let points = EngineWeightTrend.compute(scaleWeights: Array(repeating: 70, count: 60))
        for point in points {
            XCTAssertEqual(point!.realtime, 70, accuracy: 1e-9)
            XCTAssertEqual(point!.smoothed, 70, accuracy: 1e-9)
        }
    }

    func testNilBeforeFirstWeighIn() {
        let points = EngineWeightTrend.compute(scaleWeights: [nil, nil, 71, nil, 70.5])
        XCTAssertNil(points[0])
        XCTAssertNil(points[1])
        XCTAssertNotNil(points[2])
        XCTAssertNotNil(points[3], "days without a weigh-in still get a trend")
        XCTAssertEqual(points.count, 5)
    }

    func testEmptyAndWeightlessInputs() {
        XCTAssertTrue(EngineWeightTrend.compute(scaleWeights: []).isEmpty)
        XCTAssertEqual(EngineWeightTrend.compute(scaleWeights: [nil, nil]), [nil, nil])
    }

    func testFollowsSteadyLossThroughNoise() {
        var rng = EngineTestRandom(seed: 7)
        let truth = (0..<120).map { 80 - 0.05 * Double($0) }
        let scale: [Double?] = truth.map { $0 + rng.gaussian(sd: 0.5) }
        let points = EngineWeightTrend.compute(scaleWeights: scale)
        let smoothed = engineRMSE(zip(points.map { $0!.smoothed }, truth).map { ($0, $1) })
        let raw = engineRMSE(zip(scale.map { $0! }, truth).map { ($0, $1) })
        XCTAssertLessThan(smoothed.rmse, raw.rmse / 2, "the trend must remove most of the scale noise")
        // Real-time trend after warm-up: slope learned, lag small.
        XCTAssertEqual(points[119]!.realtime, truth[119], accuracy: 0.4)
        XCTAssertEqual(points[119]!.smoothed, points[119]!.realtime, accuracy: 1e-9,
                       "on the last day both trends know the same readings")
    }

    func testSingleOutlierBarelyMovesTrend() {
        var scale: [Double?] = Array(repeating: 70, count: 40)
        scale[20] = 73 // salty dinner, water retention
        let points = EngineWeightTrend.compute(scaleWeights: scale)
        XCTAssertLessThan(points[20]!.realtime - 70, 0.6, "less than 20 % of the spike")
        XCTAssertLessThan(points[20]!.smoothed - 70, 0.3)
    }

    func testRetrospectiveTrendUsesLaterReadings() {
        // A real drop starting on day 30: the smoothed trend anticipates it, the real-time one can't.
        let scale: [Double?] = (0..<60).map { $0 < 30 ? 70 : 70 - 0.1 * Double($0 - 30) }
        let points = EngineWeightTrend.compute(scaleWeights: scale)
        XCTAssertEqual(points[25]!.realtime, 70, accuracy: 1e-9)
        XCTAssertLessThan(points[25]!.smoothed, 70)
    }
}
