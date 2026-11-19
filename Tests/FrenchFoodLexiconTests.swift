import XCTest
@testable import Assiette

final class FrenchFoodLexiconTests: XCTestCase {
    func testCommonWords() {
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "poulet").contains("chicken"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "oeuf").contains("egg"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "pates").contains("pasta"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "fromage").contains("cheese"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "creme").contains("cream"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "riz").contains("rice"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "banane").contains("banana"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "saumon").contains("salmon"))
    }

    func testCookingStates() {
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "cuit").contains("cooked"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "cru").contains("raw"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "grille").contains("grilled"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "frit").contains("fried"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "entier").contains("whole"))
        XCTAssertFalse(FrenchFoodLexicon.translations(for: "ecreme").isEmpty)
    }

    func testPlurals() {
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "poulets").contains("chicken"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "oeufs").contains("egg"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "fromages").contains("cheese"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "bananes").contains("banana"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "choux").contains("cabbage"))
    }

    func testFeminineForms() {
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "cuite").contains("cooked"))
        XCTAssertTrue(FrenchFoodLexicon.translations(for: "cuites").contains("cooked"))
    }

    func testUnknownAndTooShortWords() {
        XCTAssertEqual(FrenchFoodLexicon.translations(for: "xyzzyq"), [])
        XCTAssertEqual(FrenchFoodLexicon.translations(for: ""), [])
        XCTAssertEqual(FrenchFoodLexicon.translations(for: "q"), [])
    }

    func testPrefixTypingIsCapped() {
        let partial = FrenchFoodLexicon.translations(for: "poul")
        XCTAssertTrue(partial.contains("chicken"), "\(partial)")
        XCTAssertLessThanOrEqual(partial.count, 4)
        // Two-letter prefixes are never expanded.
        XCTAssertLessThanOrEqual(FrenchFoodLexicon.translations(for: "po").count, 4)
    }

    func testTranslationsAreLowercase() {
        for word in ["poulet", "oeuf", "pates", "fromage", "creme", "cuit", "cru"] {
            for t in FrenchFoodLexicon.translations(for: word) {
                XCTAssertEqual(t, t.lowercased(), "\(word) → \(t)")
                XCTAssertFalse(t.isEmpty)
            }
        }
    }

    func testStopWords() {
        for word in ["de", "du", "la", "le", "les", "des", "au", "aux", "a", "et", "with", "and", "of"] {
            XCTAssertTrue(FrenchFoodLexicon.stopWords.contains(word), "missing stop word \(word)")
        }
        XCTAssertFalse(FrenchFoodLexicon.stopWords.contains("poulet"))
        XCTAssertFalse(FrenchFoodLexicon.stopWords.contains("chicken"))
        for word in FrenchFoodLexicon.stopWords {
            XCTAssertEqual(word, word.lowercased())
            XCTAssertEqual(word, word.folding(options: [.diacriticInsensitive], locale: nil))
        }
    }

    func testLookupIsFast() {
        let words = ["poulet", "oeufs", "pates", "fromage", "creme", "poul", "xyzzyq"]
        let start = Date()
        for _ in 0..<2_000 {
            for w in words { _ = FrenchFoodLexicon.translations(for: w) }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "14 000 lookups should be fast")
    }
}

final class FoodDatabaseQueryTests: XCTestCase {
    func testTokens() {
        XCTAssertEqual(FoodDatabase.tokens(of: "Crème  Fraîche, 30%"), ["creme", "fraiche", "30"])
        XCTAssertEqual(FoodDatabase.tokens(of: "  "), [])
    }

    func testEmptyOrStopWordsOnlyQuery() {
        XCTAssertNil(FoodDatabase.ftsQuery(for: ""))
        XCTAssertNil(FoodDatabase.ftsQuery(for: "   ,; "))
        XCTAssertNil(FoodDatabase.ftsQuery(for: "de la"))
    }

    func testUnknownWordIsPrefixMatched() {
        XCTAssertEqual(FoodDatabase.ftsQuery(for: "xyzzyq"), "\"xyzzyq\"*")
    }

    func testFrenchWordIsOredWithTranslation() throws {
        let q = try XCTUnwrap(FoodDatabase.ftsQuery(for: "poulet"))
        XCTAssertTrue(q.contains("\"poulet\"*"), q)
        XCTAssertTrue(q.contains("\"chicken\"*"), q)
        XCTAssertTrue(q.contains(" OR "), q)
        XCTAssertTrue(q.hasPrefix("(") && q.hasSuffix(")"), q)
    }

    func testAccentsAreFolded() throws {
        let q = try XCTUnwrap(FoodDatabase.ftsQuery(for: "Crème"))
        XCTAssertTrue(q.contains("\"creme\"*"), q)
        XCTAssertTrue(q.contains("\"cream\"*"), q)
        XCTAssertFalse(q.contains("è"))
    }

    func testWordsAreAndedAndStopWordsRemoved() throws {
        let q = try XCTUnwrap(FoodDatabase.ftsQuery(for: "xyzzyq de wqzzyx"))
        XCTAssertEqual(q, "\"xyzzyq\"* AND \"wqzzyx\"*")
        let french = try XCTUnwrap(FoodDatabase.ftsQuery(for: "poulet et riz"))
        XCTAssertEqual(french.components(separatedBy: " AND ").count, 2, french)
        XCTAssertTrue(french.contains("\"rice\"*"), french)
    }

    func testMultiWordTranslationsArePhrases() throws {
        // A translation containing a space must be matched as a phrase, without prefix star.
        for word in ["ecreme", "poulet", "creme", "oeuf", "fromage"] {
            let q = try XCTUnwrap(FoodDatabase.ftsQuery(for: word))
            for translation in FrenchFoodLexicon.translations(for: word) where translation.contains(" ") {
                let phrase = "\"" + FoodDatabase.tokens(of: translation).joined(separator: " ") + "\""
                XCTAssertTrue(q.contains(phrase), "\(q) should contain \(phrase)")
                XCTAssertFalse(q.contains(phrase + "*"), q)
            }
        }
    }

    func testNoDuplicateAlternatives() throws {
        let q = try XCTUnwrap(FoodDatabase.ftsQuery(for: "pates"))
        let parts = q.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            .components(separatedBy: " OR ")
        XCTAssertEqual(parts.count, Set(parts).count, q)
    }

    func testQuotesInInputCannotBreakQuery() throws {
        let q = try XCTUnwrap(FoodDatabase.ftsQuery(for: "\"xyzzyq\" OR*"))
        // Punctuation is stripped by tokenization; every token is quoted.
        XCTAssertFalse(q.contains("\"\""), q)
        XCTAssertTrue(q.hasPrefix("\"xyzzyq\"*"), q)
    }
}
