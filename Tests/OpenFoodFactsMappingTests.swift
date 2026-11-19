import XCTest
@testable import Assiette

final class OpenFoodFactsMappingTests: XCTestCase {
    private func map(_ json: String, barcode: String = "3017620422003") -> FoodItem? {
        OpenFoodFactsClient.map(json: Data(json.utf8), barcode: barcode)
    }

    func testFullProduct() throws {
        let json = """
        {
          "code": "3017620422003",
          "status": 1,
          "product": {
            "product_name": "Nutella",
            "product_name_fr": "Pâte à tartiner",
            "brands": "Ferrero, Nutella",
            "serving_quantity": 15,
            "serving_size": "15 g",
            "nutrition_data_per": "100g",
            "quantity": "400 g",
            "product_quantity": 400,
            "nutriments": {
              "energy-kcal_100g": 539,
              "proteins_100g": 6.3,
              "carbohydrates_100g": 57.5,
              "fat_100g": 30.9,
              "saturated-fat_100g": 10.6,
              "sugars_100g": 56.3,
              "fiber_100g": 0,
              "sodium_100g": 0.0428,
              "salt_100g": 0.107
            }
          }
        }
        """
        let item = try XCTUnwrap(map(json))
        XCTAssertEqual(item.source, .openFoodFacts)
        XCTAssertEqual(item.ref, "3017620422003")
        XCTAssertEqual(item.id, "openFoodFacts:3017620422003")
        XCTAssertEqual(item.name, "Pâte à tartiner", "French name preferred")
        XCTAssertEqual(item.brand, "Ferrero", "first brand only")
        XCTAssertEqual(item.servingGrams, 15)
        XCTAssertNotNil(item.servingLabel)
        XCTAssertFalse(item.isLiquid)

        let n = item.per100
        XCTAssertEqual(n.calories, 539, accuracy: 1e-9)
        XCTAssertEqual(n.protein, 6.3, accuracy: 1e-9)
        XCTAssertEqual(n.carbs, 57.5, accuracy: 1e-9)
        XCTAssertEqual(n.fat, 30.9, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(n[.saturatedFats]), 10.6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(n[.totalSugars]), 56.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(n[.dietaryFiber]), 0, accuracy: 1e-9)
        // OFF sodium is in g -> mg
        XCTAssertEqual(try XCTUnwrap(n[.sodium]), 42.8, accuracy: 1e-6)
    }

    func testFallbackToEnglishNameAndSaltToSodium() throws {
        let json = """
        {"status": 1, "product": {
          "product_name": "Orange juice",
          "nutrition_data_per": "100ml",
          "nutriments": {"energy-kcal_100g": 45, "salt_100g": 0.25}
        }}
        """
        let item = try XCTUnwrap(map(json, barcode: "5449000000996"))
        XCTAssertEqual(item.name, "Orange juice")
        XCTAssertEqual(item.ref, "5449000000996")
        XCTAssertTrue(item.isLiquid)
        XCTAssertNil(item.servingGrams)
        // sodium = salt / 2.5, in mg
        XCTAssertEqual(try XCTUnwrap(item.per100[.sodium]), 100, accuracy: 1e-6)
    }

    func testLiquidFromQuantityUnit() throws {
        let json = """
        {"status": 1, "product": {
          "product_name": "Eau minérale",
          "quantity": "1,5 L",
          "nutriments": {"energy-kcal_100g": 0}
        }}
        """
        XCTAssertTrue(try XCTUnwrap(map(json)).isLiquid)

        let cl = """
        {"status": 1, "product": {
          "product_name": "Soda",
          "quantity": "33 cl",
          "nutriments": {"energy-kcal_100g": 42}
        }}
        """
        XCTAssertTrue(try XCTUnwrap(map(cl)).isLiquid)
    }

    func testEnergyFromKilojoules() throws {
        let json = """
        {"status": 1, "product": {
          "product_name": "Biscuit",
          "nutriments": {"energy-kj_100g": 2092}
        }}
        """
        let item = try XCTUnwrap(map(json))
        XCTAssertEqual(item.per100.calories, 500, accuracy: 0.5)
    }

    func testStringNumbersAreParsed() throws {
        let json = """
        {"status": 1, "product": {
          "product_name": "Yaourt",
          "serving_quantity": "125",
          "nutriments": {"energy-kcal_100g": "60", "proteins_100g": "4.2"}
        }}
        """
        let item = try XCTUnwrap(map(json))
        XCTAssertEqual(item.servingGrams, 125)
        XCTAssertEqual(item.per100.calories, 60, accuracy: 1e-9)
        XCTAssertEqual(item.per100.protein, 4.2, accuracy: 1e-9)
    }

    func testNotFoundPayload() {
        XCTAssertNil(map(#"{"code": "0000000000000", "status": 0, "status_verbose": "product not found"}"#))
    }

    func testInvalidPayloads() {
        XCTAssertNil(map(""))
        XCTAssertNil(map("not json"))
        XCTAssertNil(map("[]"))
        XCTAssertNil(map(#"{"status": 1}"#))
    }

    func testProductWithoutNameNorNutrients() {
        XCTAssertNil(map(#"{"status": 1, "product": {"brands": "X"}}"#))
    }

    func testMissingNutrientsStayUnknown() throws {
        let json = #"{"status": 1, "product": {"product_name": "Mystère"}}"#
        let item = try XCTUnwrap(map(json))
        XCTAssertNil(item.per100[.protein])
        XCTAssertNil(item.per100[.sodium])
    }
}
