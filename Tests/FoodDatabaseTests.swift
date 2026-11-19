import XCTest
@testable import Assiette

/// Integration tests against the bundled `foods.sqlite` (host app = Assiette).
final class FoodDatabaseTests: XCTestCase {
    private var db: FoodDatabase { FoodDatabase.shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(FoodDatabase.shared.isAvailable,
                          "foods.sqlite unavailable: \(FoodDatabase.shared.openError ?? "?")")
    }

    private func names(_ foods: [Food], first n: Int = 10) -> [String] {
        foods.prefix(n).map(\.name)
    }

    func testMetadata() {
        XCTAssertNil(db.openError)
        XCTAssertGreaterThan(db.count, 100_000)
        XCTAssertFalse(db.datasetVersion.isEmpty)
    }

    func testMissingDatabaseReportsError() {
        let missing = FoodDatabase(url: nil)
        XCTAssertFalse(missing.isAvailable)
        XCTAssertNotNil(missing.openError)
        XCTAssertEqual(missing.search("chicken"), [])
        XCTAssertNil(missing.food(id: 1))
        XCTAssertNil(missing.food(barcode: "0013764027091"))
    }

    func testSearchChickenBreast() {
        let results = db.search("chicken breast")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(names(results).contains { $0.contains("Chicken Breast") }, "\(names(results))")
    }

    func testSearchCommonFoods() {
        let eggs = db.search("large eggs")
        XCTAssertTrue(names(eggs).contains("Large Eggs"), "\(names(eggs))")

        let rice = db.search("white rice")
        XCTAssertTrue(names(rice).contains { $0.contains("White Rice") }, "\(names(rice))")

        let banana = db.search("banana")
        XCTAssertTrue(names(banana).contains("Banana"), "\(names(banana))")
    }

    func testGenericFoodsRankFirst() throws {
        let first = try XCTUnwrap(db.search("banana").first)
        XCTAssertEqual(first.kind, .everyday)
    }

    func testSearchIsCaseAndAccentInsensitive() {
        let a = db.search("BANANA", limit: 10).map(\.id)
        let b = db.search("banana", limit: 10).map(\.id)
        XCTAssertEqual(a, b)
        XCTAssertFalse(db.search("crème", limit: 10).isEmpty)
    }

    func testFrenchQueryFindsEnglishFoods() {
        let results = db.search("poulet", limit: 20)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.name.lowercased().contains("chicken") },
                      "\(names(results, first: 20))")
    }

    func testPrefixMatching() {
        let results = db.search("banan", limit: 20)
        XCTAssertTrue(results.contains { $0.name.lowercased().contains("banana") })
    }

    func testLimitAndEmptyQuery() {
        XCTAssertLessThanOrEqual(db.search("chicken", limit: 5).count, 5)
        XCTAssertEqual(db.search("chicken", limit: 5).count, 5)
        XCTAssertEqual(db.search(""), [])
        XCTAssertEqual(db.search("de la"), [])
        XCTAssertEqual(db.search("xyzzyqwv"), [])
    }

    func testKindFilter() {
        let grocery = db.search("bread", kinds: [.grocery], limit: 30)
        XCTAssertFalse(grocery.isEmpty)
        XCTAssertTrue(grocery.allSatisfy { $0.kind == .grocery })

        let generic = db.search("bread", kinds: [.everyday, .prepared], limit: 30)
        XCTAssertFalse(generic.isEmpty)
        XCTAssertTrue(generic.allSatisfy { $0.kind == .everyday || $0.kind == .prepared })

        // Empty / full sets mean "no filter".
        XCTAssertEqual(db.search("bread", kinds: [], limit: 10).map(\.id),
                       db.search("bread", kinds: nil, limit: 10).map(\.id))
        XCTAssertEqual(db.search("bread", kinds: Set(FoodKind.allCases), limit: 10).map(\.id),
                       db.search("bread", limit: 10).map(\.id))
    }

    func testFoodsHaveNutrients() throws {
        let chicken = try XCTUnwrap(db.search("chicken breast").first { $0.kind == .everyday })
        XCTAssertGreaterThan(chicken.per100.calories, 50)
        XCTAssertGreaterThan(chicken.per100.protein, 10)
        XCTAssertFalse(chicken.extId.isEmpty)
    }

    func testFoodByIdRoundTrip() throws {
        let found = try XCTUnwrap(db.search("white rice").first)
        let byId = try XCTUnwrap(db.food(id: found.id))
        XCTAssertEqual(byId, found)
        XCTAssertEqual(byId.item.id, "openNutrition:\(found.id)")
        XCTAssertNil(db.food(id: -1))
    }

    func testUnknownBarcode() {
        XCTAssertNil(db.food(barcode: "0000000000000"))
        XCTAssertNil(db.food(barcode: ""))
        XCTAssertNil(db.food(barcode: "abc"))
    }

    func testBarcodeRoundTrip() throws {
        let bread = try XCTUnwrap(db.search("Dave's Killer Bread", kinds: [.grocery]).first)
        let ean = try XCTUnwrap(bread.ean, "first Dave's Killer Bread result has no EAN")
        let byBarcode = try XCTUnwrap(db.food(barcode: ean))
        XCTAssertEqual(byBarcode.id, bread.id)
        XCTAssertEqual(byBarcode.ean, ean)

        // UPC-A (12 digits) form of a zero-prefixed EAN-13 resolves to the same food.
        if ean.count == 13, ean.hasPrefix("0") {
            XCTAssertEqual(db.food(barcode: String(ean.dropFirst()))?.id, bread.id)
        }
        // Non-digit characters are ignored.
        XCTAssertEqual(db.food(barcode: " \(ean) ")?.id, bread.id)
    }

    func testSearchAsyncMatchesSearch() async {
        let sync = FoodDatabase.shared.search("large eggs", limit: 15).map(\.id)
        let asyncIDs = await FoodDatabase.shared.searchAsync("large eggs", limit: 15).map(\.id)
        XCTAssertEqual(sync, asyncIDs)
    }

    func testConcurrentSearchesAreSafe() async {
        let queries = ["banana", "chicken", "rice", "bread", "poulet", "fromage"]
        await withTaskGroup(of: Int.self) { group in
            for q in queries {
                group.addTask { await FoodDatabase.shared.searchAsync(q, limit: 20).count }
            }
            for await count in group {
                XCTAssertGreaterThan(count, 0)
            }
        }
    }
}
