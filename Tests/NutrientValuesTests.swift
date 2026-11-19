import XCTest
@testable import Assiette

final class NutrientValuesTests: XCTestCase {
    private let sample = NutrientValues([
        .calories: 200, .protein: 10, .carbohydrates: 30, .totalFat: 5, .sodium: 400,
    ])

    func testSubscriptAndMissingKeys() throws {
        XCTAssertEqual(try XCTUnwrap(sample[.protein]), 10, accuracy: 1e-9)
        XCTAssertNil(sample[.vitaminC], "Missing key must be unknown, not zero")
        XCTAssertEqual(sample.value(.vitaminC), 0, accuracy: 1e-9)
        XCTAssertEqual(sample.calories, 200, accuracy: 1e-9)
        XCTAssertEqual(sample.protein, 10, accuracy: 1e-9)
        XCTAssertEqual(sample.carbs, 30, accuracy: 1e-9)
        XCTAssertEqual(sample.fat, 5, accuracy: 1e-9)
        XCTAssertFalse(sample.isEmpty)
        XCTAssertTrue(NutrientValues().isEmpty)
    }

    func testSubscriptSetterAndRemoval() {
        var values = NutrientValues()
        values[.iron] = 2.5
        XCTAssertEqual(values.value(.iron), 2.5, accuracy: 1e-9)
        values[.iron] = nil
        XCTAssertNil(values[.iron])
        XCTAssertTrue(values.isEmpty)
    }

    func testKnownKeysFollowCaseOrder() {
        XCTAssertEqual(sample.knownKeys, [.calories, .protein, .carbohydrates, .totalFat, .sodium])
    }

    func testForGramsScalesEveryValue() {
        let portion = sample.forGrams(150)
        XCTAssertEqual(portion.calories, 300, accuracy: 1e-9)
        XCTAssertEqual(portion.protein, 15, accuracy: 1e-9)
        XCTAssertEqual(portion.value(.sodium), 600, accuracy: 1e-9)
        XCTAssertNil(portion[.vitaminC])
        XCTAssertEqual(sample.forGrams(100), sample)
        XCTAssertEqual(sample.forGrams(0).calories, 0, accuracy: 1e-9)
    }

    func testScaled() {
        let half = sample.scaled(by: 0.5)
        XCTAssertEqual(half.calories, 100, accuracy: 1e-9)
        XCTAssertEqual(half.fat, 2.5, accuracy: 1e-9)
    }

    func testAdditionMergesKeys() throws {
        let other = NutrientValues([.calories: 50, .vitaminC: 12])
        let total = sample + other
        XCTAssertEqual(total.calories, 250, accuracy: 1e-9)
        XCTAssertEqual(total.protein, 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(total[.vitaminC]), 12, accuracy: 1e-9)
        XCTAssertNil(total[.iron])

        var accumulated = NutrientValues()
        accumulated += sample
        accumulated += sample
        XCTAssertEqual(accumulated.calories, 400, accuracy: 1e-9)
    }

    func testSum() {
        let total = NutrientValues.sum([sample, sample.forGrams(50), NutrientValues()])
        XCTAssertEqual(total.calories, 300, accuracy: 1e-9)
        XCTAssertEqual(total.protein, 15, accuracy: 1e-9)
        XCTAssertTrue(NutrientValues.sum([NutrientValues]()).isEmpty)
    }

    func testDataRoundTrip() {
        let restored = NutrientValues(data: sample.data)
        XCTAssertEqual(restored, sample)
        XCTAssertEqual(restored.knownKeys, sample.knownKeys)
    }

    func testDataInitWithInvalidOrNilData() {
        XCTAssertTrue(NutrientValues(data: nil).isEmpty)
        XCTAssertTrue(NutrientValues(data: Data()).isEmpty)
        XCTAssertTrue(NutrientValues(data: Data("not json".utf8)).isEmpty)
    }

    func testEmptyValuesRoundTrip() {
        let empty = NutrientValues()
        XCTAssertTrue(NutrientValues(data: empty.data).isEmpty)
    }

    func testNutrientKeyMetadata() {
        XCTAssertEqual(NutrientKey.totalFat.rawValue, "total_fat")
        XCTAssertEqual(NutrientKey.folate.rawValue, "folate_dfe")
        XCTAssertEqual(NutrientKey.calories.unit, "kcal")
        XCTAssertEqual(NutrientKey.protein.unit, "g")
        XCTAssertEqual(NutrientKey.sodium.unit, "mg")
        XCTAssertEqual(NutrientKey.vitaminD.unit, "µg")
        XCTAssertEqual(NutrientKey.macros, [.protein, .carbohydrates, .totalFat])
        for key in NutrientKey.allCases {
            XCTAssertFalse(key.label.isEmpty, "\(key) has no label")
            XCTAssertFalse(key.unit.isEmpty, "\(key) has no unit")
        }
        XCTAssertEqual(Set(NutrientKey.allCases.map(\.rawValue)).count, NutrientKey.allCases.count)
    }
}
