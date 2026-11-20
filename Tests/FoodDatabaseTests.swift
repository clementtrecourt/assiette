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
        // Staples are shown with their French name (tools/data/french_names.tsv).
        let eggs = db.search("large eggs")
        XCTAssertTrue(names(eggs).contains("Œufs entiers"), "\(names(eggs))")

        let rice = db.search("white rice")
        XCTAssertTrue(names(rice).contains { $0.contains("White Rice") }, "\(names(rice))")

        let banana = db.search("banana")
        XCTAssertTrue(names(banana).contains("Banane"), "\(names(banana))")
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

    // MARK: Ranking

    /// Everyday queries (French first, as typed in the app) and a food expected in the top 3.
    /// Includes the owner's usual foods (MacroFactor history).
    private static let goldenQueries: [(query: String, expected: String)] = [
        ("oeuf", "Œufs entiers"), ("oeu", "Œuf"), ("egg", "Œufs entiers"), ("lait", "Lait"),
        ("milk", "Lait"), ("pain", "Pain"), ("riz", "Riz cuit"), ("pomme", "Pomme"),
        ("thon", "Thon"), ("avocat", "Avocat"), ("banane", "Banane"), ("poulet", "poulet"),
        ("poul", "Poulet"), ("blanc de poulet", "Blanc de poulet"), ("chicken breast", "Blanc de poulet"),
        ("steak hache", "Steak haché"), ("steak 5%", "Steak haché 5 %"), ("jambon blanc", "Jambon blanc"),
        ("yaourt grec", "Yaourt grec"), ("yao", "Yaourt"), ("fromage blanc", "Fromage Blanc"),
        ("pates", "Pâtes"), ("pommes de terre", "Pommes de terre"), ("haricots verts", "Haricots verts"),
        ("saumon", "Saumon"), ("pave de saumon", "Pavé de saumon"), ("whey", "Protéine en poudre"),
        ("flocons d'avoine", "Flocons d'avoine"), ("baguette", "Baguette"), ("croissant", "Croissant"),
        ("pain au chocolat", "Pain au chocolat"), ("crepe", "Crêpe"), ("glace", "Glace"),
        ("galette de riz", "Galettes de riz"), ("barre proteinee", "Barre protéinée"),
        ("nutella", "chocolat-noisette"), ("cookie", "Cookies"), ("frites", "Frites"),
        ("eau", "Eau"), ("fraises", "Fraises"), ("tomate", "Tomates"), ("concombre", "Concombre"),
        ("dinde hachee", "Dinde hachée"), ("lait de coco", "Lait de coco"), ("sauce soja", "Sauce soja"),
        ("large eggs", "Œufs entiers"), ("white rice", "White Rice"), ("banana", "Banane"),
    ]

    func testGoldenQueries() {
        var failures: [String] = []
        for (query, expected) in Self.goldenQueries {
            let top = names(db.search(query, limit: 10), first: 3)
            if !top.contains(where: { $0.localizedCaseInsensitiveContains(expected) }) {
                failures.append("\(query) -> \(top) (expected \(expected))")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testCompleteFrenchWordsDoNotPrefixMatchOtherWords() {
        let bread = names(db.search("pain", limit: 30), first: 30)
        XCTAssertFalse(bread.contains { $0.lowercased().contains("painkiller") }, "\(bread)")
        let rice = names(db.search("riz", limit: 30), first: 30)
        XCTAssertFalse(rice.contains { $0.contains("Rizo") || $0.contains("Řízek") }, "\(rice)")
        let apple = names(db.search("pomme", limit: 30), first: 30)
        XCTAssertFalse(apple.contains { $0.contains("Pommersche") }, "\(apple)")
        let ham = names(db.search("jambon blanc", limit: 10))
        XCTAssertFalse(ham.prefix(5).contains { $0.contains("Hamburger") }, "\(ham)")
    }

    func testAlternateNameOnlyMatchesRankLast() throws {
        // "Île Flottante" only matches "oeuf" through its alternate name "Oeufs à la neige".
        let first = try XCTUnwrap(db.search("oeuf").first)
        XCTAssertNotEqual(first.name, "Île Flottante")
        XCTAssertEqual(first.fluent, "egg")
    }

    func testLoggedFoodsRankFirst() throws {
        let plain = db.search("poulet", limit: 30)
        let logged = try XCTUnwrap(plain.dropFirst(10).first)
        let boosted = db.search("poulet", limit: 30, history: [logged.id: 3])
        XCTAssertEqual(boosted.first?.id, logged.id, "\(names(boosted))")
        // A logged food that does not match the query is not added.
        XCTAssertFalse(db.search("banane", history: [logged.id: 3]).contains { $0.id == logged.id })
    }

    func testUnknownWordDoesNotEmptyTheResults() {
        let results = db.search("saumon xyzzyq", limit: 10)
        XCTAssertTrue(names(results).contains { $0.contains("Saumon") }, "\(names(results))")
    }

    func testStaplesHaveIcons() throws {
        for query in ["oeuf", "lait", "riz", "pomme", "banane", "thon", "steak hache", "poulet", "pain"] {
            let first = try XCTUnwrap(db.search(query).first, query)
            XCTAssertTrue(first.fluent != nil || first.icon != nil, "\(query): \(first.name) has no icon")
        }
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
