import XCTest
import UIKit
@testable import Assiette

/// Fluent Emoji icons: the conservative name matcher (custom foods, quick adds, Open Food Facts),
/// the bundled assets, and the `fluent` column of the bundled database.
final class FoodEmojiTests: XCTestCase {
    // BEGIN CASES (also run on Linux against the matcher source; keep one case per line)
    static let positives: [(String, String)] = [
        ("Banane", "banana"),
        ("bananes", "banana"),
        ("Banana", "banana"),
        ("2 œufs durs", "egg"),
        ("Oeuf", "egg"),
        ("Hard boiled egg", "egg"),
        ("Œuf au plat", "cooking"),
        ("Riz basmati cuit", "cooked_rice"),
        ("Riz blanc", "cooked_rice"),
        ("White rice", "cooked_rice"),
        ("Cooked rice", "cooked_rice"),
        ("Blanc de poulet", "poultry_leg"),
        ("Poulet rôti", "poultry_leg"),
        ("Chicken breast", "poultry_leg"),
        ("Roast chicken", "poultry_leg"),
        ("Filet de saumon", "fish"),
        ("Salmon fillet", "fish"),
        ("Pavé de saumon fumé", "fish"),
        ("Poisson", "fish"),
        ("Pomme", "red_apple"),
        ("Pommes de terre", "potato"),
        ("Pomme de terre au four", "potato"),
        ("Lait demi-écrémé", "glass_of_milk"),
        ("Café", "hot_beverage"),
        ("Café crème", "hot_beverage"),
        ("Pain complet", "bread"),
        ("Baguette", "baguette_bread"),
        ("Fromage", "cheese_wedge"),
        ("Emmental râpé", "cheese_wedge"),
        ("Yaourt nature", "bowl_with_spoon"),
        ("Fromage blanc 0%", "bowl_with_spoon"),
        ("Carottes râpées", "carrot"),
        ("Tomates cerises", "tomato"),
        ("Avocat", "avocado"),
        ("Chocolat noir 70%", "chocolate_bar"),
        ("Chocolat au lait", "chocolate_bar"),
        ("Pâtes", "spaghetti"),
        ("Pâtes complètes", "spaghetti"),
        ("Citron vert", "lime"),
        ("Citron", "lemon"),
        ("Frites", "french_fries"),
        ("Pommes frites", "french_fries"),
        ("Thé vert", "teacup_without_handle"),
        ("Gâteau au chocolat", "shortcake"),
        ("Tarte aux pommes", "pie"),
        ("Patate douce", "roasted_sweet_potato"),
        ("Steak haché", "cut_of_meat"),
        ("Raisin blanc", "grapes"),
    ]

    static let negatives: [String] = [
        "Pain à la banane",
        "Banana bread",
        "Egg salad sandwich",
        "Chicken and mushroom crepe",
        "Crêpe poulet champignons",
        "Salade de riz",
        "Lait au chocolat",
        "Chocolate milk",
        "Riz au lait",
        "Lait de coco",
        "Pain au chocolat",
        "Haricots verts",
        "Jus de pomme",
        "Compote de pommes",
        "Yaourt à la fraise",
        "Café au lait",
        "Thé glacé",
        "Frozen cappuccino",
        "Ajout rapide",
        "Nuggets de poulet",
        "Poulet au curry",
        "Thon en boîte",
        "Pâté",
        "Pâte à tartiner",
        "Riz cantonais",
        "Œufs brouillés au bacon",
        "Granola bar",
        "Peanut butter",
        "Beurre de cacahuète",
        "Raisins secs",
        "Raisins",
        "Mango bowl",
        "Spaghetti bolognaise",
        "",
    ]
    // END CASES

    func testPositiveMatches() {
        for (name, expected) in Self.positives {
            XCTAssertEqual(FoodEmojiMatcher.match(name: name), expected, name)
        }
    }

    func testConservativeNonMatches() {
        for name in Self.negatives {
            XCTAssertNil(FoodEmojiMatcher.match(name: name), name)
        }
    }

    func testTokensFoldAccentsLigaturesAndPlurals() {
        XCTAssertEqual(FoodEmojiMatcher.tokens(of: "Œufs Durs"), ["oeuf", "dur"])
        XCTAssertEqual(FoodEmojiMatcher.tokens(of: "Tomatoes"), ["tomato"])
        XCTAssertEqual(FoodEmojiMatcher.tokens(of: "Cherries"), ["cherry"])
        XCTAssertEqual(FoodEmojiMatcher.tokens(of: "Pâtes"), ["pasta"])
    }

    func testEveryMatcherIconIsBundled() {
        for icon in FoodEmojiMatcher.allIcons {
            XCTAssertNotNil(UIImage(named: FoodEmojiMatcher.assetName(icon)), icon)
            XCTAssertTrue(FoodEmojiMatcher.hasAsset(icon), icon)
        }
        XCTAssertFalse(FoodEmojiMatcher.hasAsset("not_an_emoji"))
    }

    /// Dataset foods get their icon from the `fluent` column (tools/map_fluent.py).
    func testDatabaseFluentColumn() throws {
        let db = FoodDatabase.shared
        try XCTSkipUnless(db.isAvailable, "foods.sqlite unavailable")
        let foods = db.search("banana", limit: 30)
        let banana = try XCTUnwrap(foods.first { $0.name == "Banane" }, "\(foods.prefix(5).map(\.name))")
        try XCTSkipIf(banana.fluent == nil, "database built without the fluent column")
        XCTAssertEqual(banana.fluent, "banana")
        XCTAssertEqual(banana.item.fluent, "banana")
        XCTAssertEqual(db.iconNames(forFoodId: banana.id).fluent, "banana")

        let bread = db.search("banana bread", limit: 30).first { $0.name.lowercased().hasPrefix("banana bread") }
        if let bread {
            XCTAssertNil(bread.fluent, bread.name)
        }
        if let fluent = foods.compactMap(\.fluent).first {
            XCTAssertTrue(FoodEmojiMatcher.hasAsset(fluent), fluent)
        }
    }
}
