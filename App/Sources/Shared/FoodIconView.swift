import SwiftUI
import UIKit

/// Rounded-square tile (Theme.raised2 + 1 pt Theme.separator border) showing a food icon,
/// resolved in this order (see DESIGN.md, "Food icons"):
/// 1. a bundled Fluent Emoji "Flat" icon (asset `FoodEmoji/<name>`, instant, offline) when the
///    food is a clear generic match: `fluent` column of the dataset (tools/map_fluent.py), or
///    `FoodEmojiMatcher` on the name for custom foods, Open Food Facts products, quick adds;
/// 2. the OpenNutrition illustration (webp with alpha, loaded from the OpenNutrition CDN and
///    cached in memory + on disk);
/// 3. a subtle SF Symbol (also shown while loading, or offline).
///
/// When `icon` is nil but `foodId` is given (journal entries, favorites, recents rebuilt
/// from a `JournalEntry`), both icon names are looked up in `FoodDatabase` off the main thread.
struct FoodIconView: View {
    private let icon: String?
    /// Fluent Emoji known at init (item / name match); dataset foods may also get one by id.
    private let fluent: String?
    private let foodId: Int64?
    private let kind: FoodKind?
    private let size: CGFloat
    private let placeholder: String?

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?
    @State private var loadedFluent: String?
    @State private var loadedKey: String?

    init(icon: String?, kind: FoodKind?, size: CGFloat = 40) {
        self.init(icon: icon, foodId: nil, kind: kind, size: size, placeholder: nil)
    }

    /// - Parameters:
    ///   - name: display name, matched with `FoodEmojiMatcher` when the food is not from the
    ///     bundled dataset (`foodId == nil`) and no `fluent` is given (custom foods, quick adds).
    ///   - fluent: Fluent Emoji name already known (e.g. `FoodItem.fluent`).
    init(icon: String?, foodId: Int64?, kind: FoodKind?, size: CGFloat = 40, placeholder: String? = nil,
         name: String? = nil, fluent: String? = nil) {
        self.icon = (icon?.isEmpty ?? true) ? nil : icon
        if let fluent, !fluent.isEmpty {
            self.fluent = fluent
        } else if foodId == nil, let name {
            self.fluent = FoodEmojiMatcher.match(name: name)
        } else {
            self.fluent = nil
        }
        self.foodId = foodId
        self.kind = kind
        self.size = size
        self.placeholder = placeholder
    }

    init(item: FoodItem, size: CGFloat = 40) {
        self.init(icon: item.icon,
                  foodId: item.source == .openNutrition ? item.ref.flatMap { Int64($0) } : nil,
                  kind: item.kind,
                  size: size,
                  placeholder: FoodIconView.placeholderSymbol(for: item.source),
                  name: item.name,
                  fluent: item.fluent)
    }

    /// Symbol for items without a kind (custom foods, Open Food Facts, quick adds).
    static func placeholderSymbol(for source: FoodSource) -> String? {
        switch source {
        case .openNutrition: return nil
        case .custom: return "fork.knife"
        case .openFoodFacts: return "barcode"
        case .quickAdd: return "bolt.fill"
        }
    }

    /// Illustration side (~90 % of the frame).
    private var imageSide: CGFloat { (size * 0.9).rounded() }

    /// Fluent emojis fill their whole canvas: drawn a bit smaller to match the illustrations.
    private var emojiSide: CGFloat { (size * 0.8).rounded() }

    private var pixelSide: Int { max(Int((imageSide * max(displayScale, 1)).rounded()), 1) }

    /// Identity of the image to show: changes when the row is reused for another food.
    private var taskKey: String {
        "\(icon ?? "")|\(fluent ?? "")|\(foodId.map { String($0) } ?? "")|\(pixelSide)"
    }

    /// Names known synchronously from the database cache (only looked up when `icon` is nil).
    private var cachedNames: FoodIconNames? {
        guard icon == nil, let foodId else { return nil }
        return FoodIconLoader.cachedIconNames(forFoodId: foodId)
    }

    /// Bundled Fluent Emoji to show, if any (asset checked, so a stale name falls through).
    private var displayedFluent: String? {
        var candidates: [String] = []
        if let fluent { candidates.append(fluent) }
        if let name = cachedNames?.fluent { candidates.append(name) }
        if loadedKey == taskKey, let name = loadedFluent { candidates.append(name) }
        return candidates.first { FoodEmojiMatcher.hasAsset($0) }
    }

    /// Image available synchronously (memory cache), so cached icons never flash.
    private var cachedImage: UIImage? {
        guard let name = icon ?? cachedNames?.icon else { return nil }
        return FoodIconLoader.memoryImage(name: name, pixelSide: pixelSide)
    }

    var body: some View {
        let emoji = displayedFluent
        let image = emoji == nil ? (cachedImage ?? (loadedKey == taskKey ? loadedImage : nil)) : nil
        // Bare icon, no tile (MacroFactor-style lists).
        ZStack {
            if let emoji {
                Image(FoodEmojiMatcher.assetName(emoji))
                    .resizable()
                    .scaledToFit()
                    .frame(width: emojiSide, height: emojiSide)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: imageSide, height: imageSide)
            } else {
                Image(systemName: placeholder ?? kind?.systemImage ?? "fork.knife")
                    .font(.system(size: size * 0.6, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: taskKey) {
            await load(key: taskKey)
        }
    }

    private func load(key: String) async {
        if displayedFluent != nil || cachedImage != nil { return }
        var name = icon
        if name == nil, let foodId {
            let names = await FoodIconLoader.shared.iconNames(forFoodId: foodId)
            guard !Task.isCancelled else { return }
            if let emoji = names.fluent, FoodEmojiMatcher.hasAsset(emoji) {
                loadedFluent = emoji
                loadedImage = nil
                loadedKey = key
                return
            }
            name = names.icon
        }
        guard let name, !Task.isCancelled else { return }
        let image = await FoodIconLoader.shared.image(name: name, pixelSide: pixelSide)
        guard !Task.isCancelled else { return }
        loadedImage = image
        loadedFluent = nil
        loadedKey = key
    }
}

/// Shared icon loader: de-duplicates in-flight downloads, decodes + downscales once per
/// display size off the main thread, caches decoded images in memory (NSCache) and raw
/// webp files in Caches/FoodIcons/<basename>.webp.
actor FoodIconLoader {
    static let shared = FoodIconLoader()

    private static let baseURL = "https://drd3kry2ubqnc.cloudfront.net/"

    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    /// foodId -> icon names (Fluent Emoji + OpenNutrition illustration; nil = none).
    private static let namesCache: NSCache<NSNumber, FoodIconNamesBox> = {
        let cache = NSCache<NSNumber, FoodIconNamesBox>()
        cache.countLimit = 2000
        return cache
    }()

    private var inFlight: [String: Task<FoodIconLoadResult, Never>] = [:]
    /// Names the CDN answered with an error (e.g. 404): not retried during this session.
    private var missing: Set<String> = []

    private static func cacheKey(name: String, pixelSide: Int) -> String { "\(name)@\(pixelSide)" }

    // MARK: Synchronous cache peeks (thread-safe, NSCache)

    static func memoryImage(name: String, pixelSide: Int) -> UIImage? {
        images.object(forKey: cacheKey(name: name, pixelSide: pixelSide) as NSString)
    }

    /// nil when not looked up yet (a looked-up food without icons has both names nil).
    static func cachedIconNames(forFoodId id: Int64) -> FoodIconNames? {
        namesCache.object(forKey: NSNumber(value: id))?.names
    }

    // MARK: Loading

    /// Icon names of a bundled food, resolved from the database off the main thread.
    func iconNames(forFoodId id: Int64) async -> FoodIconNames {
        if let cached = Self.cachedIconNames(forFoodId: id) { return cached }
        let names = await Task.detached(priority: .utility) {
            FoodDatabase.shared.iconNames(forFoodId: id)
        }.value
        Self.namesCache.setObject(FoodIconNamesBox(names), forKey: NSNumber(value: id))
        return names
    }

    func image(name: String, pixelSide: Int) async -> UIImage? {
        let key = Self.cacheKey(name: name, pixelSide: pixelSide)
        if let image = Self.images.object(forKey: key as NSString) { return image }
        if missing.contains(name) { return nil }
        if let task = inFlight[key] { return await task.value.image }

        let task = Task.detached(priority: .utility) { () -> FoodIconLoadResult in
            await FoodIconLoader.fetch(name: name, pixelSide: pixelSide)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let image = result.image {
            Self.images.setObject(image, forKey: key as NSString)
        } else if result.notFound {
            missing.insert(name)
        }
        return result.image
    }

    // MARK: Disk + network (nonisolated, runs on a background task)

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("FoodIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func safeName(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    }

    private static func fetch(name: String, pixelSide: Int) async -> FoodIconLoadResult {
        let file = directory?.appendingPathComponent(safeName(name) + ".webp")
        if let file, let data = try? Data(contentsOf: file), let image = decode(data, pixelSide: pixelSide) {
            return FoodIconLoadResult(image: image, notFound: false)
        }
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: baseURL + encoded + "@4x.webp") else {
            return FoodIconLoadResult(image: nil, notFound: true)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let fetched: (Data, URLResponse)? = try? await URLSession.shared.data(for: request)
        guard let fetched else {
            return FoodIconLoadResult(image: nil, notFound: false) // offline: retry later
        }
        let data = fetched.0
        let status = (fetched.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let image = decode(data, pixelSide: pixelSide) else {
            return FoodIconLoadResult(image: nil, notFound: (400..<500).contains(status) || status == 200)
        }
        if let file {
            try? data.write(to: file, options: .atomic)
        }
        return FoodIconLoadResult(image: image, notFound: false)
    }

    /// Decodes the webp and redraws it once at the display size (smooth scrolling: no
    /// per-frame scaling of the 192 px source).
    private static func decode(_ data: Data, pixelSide: Int) -> UIImage? {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
            return nil
        }
        let side = CGFloat(pixelSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let ratio = min(side / source.size.width, side / source.size.height)
        let drawSize = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

/// Result of one icon fetch (`notFound` = do not retry this session). Unchecked: UIImage is
/// immutable once rendered, and `Task` requires a Sendable result.
struct FoodIconLoadResult: @unchecked Sendable {
    let image: UIImage?
    let notFound: Bool
}

/// Boxed `FoodIconNames` for NSCache.
final class FoodIconNamesBox {
    let names: FoodIconNames

    init(_ names: FoodIconNames) {
        self.names = names
    }
}

// MARK: - Fluent Emoji

/// Conservative name -> bundled Fluent Emoji matcher for foods that do not come from the
/// dataset (custom foods, recipes, Open Food Facts products, quick adds, journal entries).
/// French and English. Dataset foods use the `fluent` column computed at build time by
/// tools/map_fluent.py instead.
///
/// A name matches a rule only when it contains one of the rule's head phrases and every
/// other word is a harmless modifier (cooking state, variety, size, quantity, stop word):
/// "Banane", "2 œufs durs", "Riz basmati cuit", "Blanc de poulet", "Filet de saumon",
/// "Chicken breast" match; "Pain à la banane", "Salade de riz", "Lait au chocolat",
/// "Egg salad sandwich", "Crêpe poulet champignons" do not (they keep the generic icon).
enum FoodEmojiMatcher {
    /// Asset catalog name of a Fluent icon (folder `FoodEmoji` provides a namespace).
    static func assetName(_ name: String) -> String { "FoodEmoji/" + name }

    /// Whether the asset exists in the app bundle (cached; false for unknown names).
    static func hasAsset(_ name: String) -> Bool {
        let key = name as NSString
        if let known = assetCache.object(forKey: key) { return known.boolValue }
        let exists = UIImage(named: assetName(name)) != nil
        assetCache.setObject(NSNumber(value: exists), forKey: key)
        return exists
    }

    /// Fluent icon name (e.g. "banana", "cooked_rice") or nil when the name is not a clear
    /// generic food. Cached per name.
    static func match(name: String) -> String? {
        let key = name as NSString
        if let cached = matchCache.object(forKey: key) {
            let value = cached as String
            return value.isEmpty ? nil : value
        }
        let result = match(tokens: tokens(of: name))
        matchCache.setObject((result ?? "") as NSString, forKey: key)
        return result
    }

    /// Every icon a rule can return (tests check that each one is bundled).
    static var allIcons: Set<String> { Set(rules.map(\.icon)) }

    // MARK: Normalisation

    /// Lowercased, accent-free, singular tokens: "Œufs durs" -> ["oeuf", "dur"].
    static func tokens(of text: String) -> [String] {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0 == "pates" ? "pasta" : singular($0) }
    }

    /// Crude singular applied identically to rules and names: eggs -> egg, tomatoes -> tomato,
    /// cherries -> cherry, oeufs -> oeuf, gateaux -> gateau.
    static func singular(_ word: String) -> String {
        let n = word.count
        if n > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if n > 4, word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes") {
            return String(word.dropLast(2))
        }
        if n > 3, (word.hasSuffix("s") && !word.hasSuffix("ss")) || word.hasSuffix("x") {
            return String(word.dropLast())
        }
        return word
    }

    // MARK: Matching

    private struct Rule {
        let icon: String
        let heads: [[String]]
        let modifiers: Set<String>
        /// Global modifiers that do not apply to this rule ("frozen cappuccino" is not hot).
        let excluded: Set<String>
    }

    private static func words(_ text: String) -> Set<String> { Set(tokens(of: text)) }

    private static func rule(_ icon: String, _ heads: String, _ modifiers: String = "",
                             except excluded: String = "") -> Rule {
        Rule(icon: icon,
             heads: heads.components(separatedBy: "|").map { tokens(of: $0) }.filter { !$0.isEmpty },
             modifiers: words(modifiers),
             excluded: words(excluded))
    }

    /// Articles, prepositions and quantity words, ignored around the head.
    private static let stopWords = words("""
        de du des d la le les l au aux a en un une of
        g gr kg ml cl oz portion part tranche piece bol verre tasse serving slice
        """)

    /// Words that never change what a generic food looks like.
    private static let globalModifiers = words("""
        cuit cuite cru crue frais fraiche nature bio biologique maison entier entiere gros grosse
        petit petite moyen moyenne surgele surgelee vapeur grille grillee roti rotie poele poelee
        bouilli bouillie tranche tranchee coupe coupee
        raw cooked fresh frozen organic plain whole large medium small homemade boiled grilled
        roasted baked steamed sliced chopped diced boneless skinless ripe natural mini
        """)

    /// Ordered: specific phrases first ("pomme de terre" before "pomme", "fromage blanc"
    /// before "fromage", "oeuf au plat" before "oeuf").
    private static let rules: [Rule] = [
        // Eggs
        rule("cooking", "oeuf au plat|oeuf sur le plat|oeuf plat|fried egg"),
        rule("egg", "oeuf|egg", "dur coque mollet poche brouille plein air hard soft boiled poached scrambled free range brown white"),
        // Fruit
        rule("green_apple", "pomme verte|granny smith|pomme granny|granny smith apple|green apple"),
        rule("roasted_sweet_potato", "patate douce|sweet potato"),
        rule("potato", "pomme de terre|patate|potato", "four rissolee nouvelle grenaille russet red"),
        rule("red_apple", "pomme|apple", "rouge gala golden fuji pink lady red delicious honeycrisp"),
        rule("banana", "banane|banana"),
        rule("strawberry", "fraise|strawberry"),
        rule("blueberries", "myrtille|blueberry"),
        rule("cherries", "cerise|cherry"),
        // Bare "raisin" is ambiguous (French grape, English raisins): colour required.
        rule("grapes", "grape|raisin blanc|raisin noir|raisin rouge|raisin vert|grain de raisin",
             "red green white black seedless"),
        rule("watermelon", "pasteque|watermelon"),
        rule("melon", "melon|cantaloup|cantaloupe|honeydew", "charentais jaune"),
        rule("tangerine", "orange|clementine|mandarine|tangerine|mandarin", "sanguine navel blood"),
        rule("lime", "citron vert|lime"),
        rule("lemon", "citron|lemon", "jaune"),
        rule("pineapple", "ananas|pineapple"),
        rule("mango", "mangue|mango"),
        rule("peach", "peche|nectarine|brugnon|peach", "jaune blanche plate"),
        rule("pear", "poire|pear", "williams conference"),
        rule("kiwi_fruit", "kiwi|kiwifruit", "jaune gold"),
        rule("coconut", "noix de coco|coco|coconut"),
        rule("avocado", "avocat|avocado", "hass"),
        rule("olive", "olive", "verte noire green black kalamata denoyautee pitted"),
        // Vegetables
        rule("tomato", "tomate|tomato|tomate cerise|cherry tomato", "cerise grappe roma cherry"),
        rule("carrot", "carotte|carrot", "rapee rape grated baby"),
        rule("cucumber", "concombre|cucumber"),
        rule("eggplant", "aubergine|eggplant"),
        rule("broccoli", "brocoli|broccoli"),
        rule("leafy_green", "epinard|kale|chou kale|laitue|roquette|mache|blette|spinach|lettuce|arugula", "pousse jeune baby"),
        rule("green_salad", "salade verte|salade|salad|green salad|side salad|garden salad", "verte mixte green side garden mixed"),
        rule("onion", "oignon|onion", "rouge jaune blanc red yellow white"),
        rule("garlic", "ail|gousse d ail|garlic"),
        rule("brown_mushroom", "champignon|champignon de paris|mushroom", "paris blanc brun button"),
        rule("bell_pepper", "poivron|bell pepper", "rouge vert jaune red green yellow"),
        rule("hot_pepper", "piment|jalapeno|chili pepper", "rouge vert red green"),
        rule("ear_of_corn", "mais|epi de mais|corn|corn on the cob", "doux sweet"),
        rule("pea_pod", "petit poi|poi|pois gourmand|edamame|green pea|pea", "gourmand"),
        rule("beans", "haricot rouge|haricot noir|haricot blanc|flageolet|kidney bean|black bean|pinto bean|red bean"),
        rule("peanuts", "cacahuete|arachide|peanut", "sale grillee salted"),
        // Bread & bakery
        rule("baguette_bread", "baguette|baguette tradition", "tradition blanche"),
        rule("croissant", "croissant", "beurre butter"),
        rule("bagel", "bagel"),
        rule("bread", "pain|bread|toast",
             "complet blanc mie seigle cereale campagne levain grille tranche white wheat whole grain multigrain rye sourdough"),
        rule("pancakes", "pancake"),
        rule("waffle", "gaufre|waffle"),
        rule("doughnut", "donut|doughnut|beignet", "glace sucre glazed"),
        rule("cookie", "cookie", "chocolat chocolate chip"),
        rule("shortcake", "gateau|cake|cheesecake", "chocolat chocolate vanille vanilla"),
        rule("pie", "tarte|pie", "pomme apple"),
        // Dairy
        rule("bowl_with_spoon", "fromage blanc|yaourt|yogourt|yoghourt|yogurt|yoghurt|skyr|porridge|flocon d avoine|oatmeal",
             "grec grecque greek nature brebis chevre vache 0 maigre"),
        rule("glass_of_milk", "lait|milk",
             "demi ecreme entier vache avoine soja amande lactose sans skim skimmed semi low fat reduced oat soy almond"),
        rule("cheese_wedge", "fromage|cheese|emmental|comte|gruyere|cheddar|gouda|parmesan|beaufort|cantal|mimolette|edam",
             "rape affine vieux chevre brebis aged sharp goat"),
        rule("butter", "beurre|butter", "doux demi sel salted unsalted"),
        // Meat & fish
        rule("bacon", "bacon"),
        rule("poultry_leg", "poulet|dinde|chicken|turkey|cuisse de poulet|blanc de poulet|aile de poulet|pilon de poulet",
             "blanc filet escalope cuisse aile pilon breast thigh wing drumstick leg roast rotisserie fried"),
        rule("cut_of_meat", "steak|entrecote|bavette|faux filet|rumsteck|cote de boeuf|cote de porc|cotelette|cote d agneau|pork chop|lamb chop",
             "boeuf porc agneau beef pork lamb hache"),
        rule("fish", "poisson|saumon|cabillaud|colin|merlu|thon|truite|sardine|maquereau|bar|dorade|lieu|sole|fish|salmon|cod|tuna|trout|tilapia|hake|mackerel",
             "filet pave dos fume blanc fillet steak loin smoked atlantic wild"),
        rule("shrimp", "crevette|gambas|shrimp|prawn", "rose decortiquee"),
        rule("crab", "crabe|crab"),
        rule("lobster", "homard|langouste|lobster"),
        rule("oyster", "huitre|oyster"),
        rule("squid", "calamar|encornet|poulpe|squid|calamari|octopus"),
        // Grains & dishes
        rule("cooked_rice", "riz|rice",
             "blanc complet basmati thai jasmin parfume long rond gluant white brown jasmine grain sticky"),
        rule("spaghetti", "pasta|spaghetti|tagliatelle|linguine|fettuccine|penne|fusilli|coquillette|macaroni",
             "complete completes blanche al dente whole wheat"),
        rule("steaming_bowl", "ramen|pho"),
        rule("sushi", "sushi|maki|nigiri"),
        rule("dumpling", "gyoza|dumpling|ravioli chinois|dim sum"),
        rule("falafel", "falafel"),
        rule("burrito", "burrito"),
        rule("taco", "taco"),
        rule("hot_dog", "hot dog|hotdog"),
        rule("hamburger", "hamburger|burger|cheeseburger"),
        rule("sandwich", "sandwich|croque monsieur"),
        rule("pizza", "pizza", "margherita reine fromage cheese pepperoni"),
        rule("french_fries", "frite|pomme frite|french fry|fry"),
        rule("popcorn", "popcorn|pop corn"),
        // Sweets
        rule("chocolate_bar", "chocolat|chocolate|chocolat au lait|milk chocolate", "noir blanc patissier dessert cacao dark white 70 85 tablette carre bar"),
        rule("ice_cream", "glace|crème glacee|ice cream|gelato", "vanille chocolat fraise vanilla chocolate strawberry"),
        rule("candy", "bonbon|candy"),
        rule("lollipop", "sucette|lollipop"),
        rule("honey_pot", "miel|honey", "acacia fleur toutes fleurs liquide cremeux"),
        rule("salt", "sel|salt", "fin gros mer marin sea"),
        // Drinks
        rule("hot_beverage", "cafe|expresso|espresso|cappuccino|latte|cafe creme|coffee|americano",
             "noir allonge serre court long creme decafeine deca black decaf",
             except: "frozen surgele glace glacee iced"),
        rule("teacup_without_handle", "the|infusion|tisane|tea|green tea", "vert noir menthe green black herbal",
             except: "frozen surgele glace glacee iced"),
        rule("beer_mug", "biere|beer", "blonde brune ambree blanche pression"),
        rule("wine_glass", "vin rouge|red wine"),
        rule("bottle_with_popping_cork", "champagne|prosecco|cremant"),
        rule("tumbler_glass", "whisky|whiskey|rhum|rum|cognac"),
        rule("cup_with_straw", "soda|coca|cola|smoothie|milkshake|milk shake", "zero light diet"),
    ]

    private static func match(tokens: [String]) -> String? {
        guard !tokens.isEmpty, tokens.count <= 8 else { return nil }
        for rule in rules {
            for head in rule.heads {
                guard let start = firstIndex(of: head, in: tokens) else { continue }
                var rest = tokens
                rest.removeSubrange(start..<(start + head.count))
                let ok = rest.allSatisfy { word in
                    stopWords.contains(word) || rule.modifiers.contains(word)
                        || (globalModifiers.contains(word) && !rule.excluded.contains(word))
                        || word.allSatisfy(\.isNumber)
                }
                if ok { return rule.icon }
            }
        }
        return nil
    }

    private static func firstIndex(of phrase: [String], in tokens: [String]) -> Int? {
        guard !phrase.isEmpty, phrase.count <= tokens.count else { return nil }
        for start in 0...(tokens.count - phrase.count) where Array(tokens[start..<(start + phrase.count)]) == phrase {
            return start
        }
        return nil
    }

    private static let matchCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 2000
        return cache
    }()

    private static let assetCache = NSCache<NSString, NSNumber>()
}
