#!/usr/bin/env python3
"""Conservative mapping of OpenNutrition food names (English) to bundled Fluent Emoji icons.

A food gets a Fluent icon only when its *head noun* is a generic food that one emoji depicts
well, and every other word of the name is a harmless modifier ("Hard Boiled Eggs", "White
Rice, Cooked", "Roasted Chicken Breast", "Salmon Fillet, Raw", "Bananas by Dole"). Anything
else ("Banana Bread", "Egg Salad Sandwich", "Chicken and Mushroom Crepe", "Spaghetti with
Meatballs") stays NULL and the app falls back to the OpenNutrition illustration.

Name anatomy: "<head phrase>[, <qualifier>, ...] [(...)] [by <Brand>]". The brand and
parentheses are dropped; the head phrase must END with one of a rule's heads and the words
before it must all be modifiers (global or rule-specific); every qualifier word after a
comma must be a qualifier/modifier word too. Rules are tried in order (specific first).

Usage:
  python3 -I tools/map_fluent.py --report <opennutrition_foods.tsv | names.txt> [--samples N] [--seed S]
  python3 -I tools/map_fluent.py --check      # every icon used exists in the asset catalog
  python3 -I tools/map_fluent.py --test       # precision examples (positive and negative)
  python3 -I tools/map_fluent.py "Hard Boiled Egg" "Banana Bread"   # try names

Imported by tools/build_db.py (fills the `fluent` column). Keep conservative: when unsure,
do not add a rule; the OpenNutrition illustration is a fine fallback. The Swift-side
matcher for user-typed names is `FoodEmojiMatcher` (App/Sources/Shared/FoodIconView.swift).
"""
import os
import re
import sys

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources",
                      "Assets.xcassets", "FoodEmoji")

BY_RE = re.compile(r"^(.*?) by [^,]+$")
PAREN_RE = re.compile(r"\([^)]*\)|\[[^\]]*\]")
WORD_RE = re.compile(r"[a-z0-9]+")


def norm_word(w):
    """Crude singular: eggs -> egg, tomatoes -> tomato, peaches -> peach, berries -> berry."""
    if len(w) > 4 and w.endswith("ies"):
        return w[:-3] + "y"
    if len(w) > 4 and (w.endswith("oes") or w.endswith("ches") or w.endswith("shes")):
        return w[:-2]
    if len(w) > 3 and w.endswith("s") and not w.endswith("ss") and not w.endswith("us"):
        w = w[:-1]
    if len(w) > 2 and w.endswith("ie"):  # cookie(s) -> cooky, consistently for keys and names
        w = w[:-2] + "y"
    return w


def words(text):
    text = text.lower().replace("’", "'").replace("'s ", " ")
    return [norm_word(w) for w in WORD_RE.findall(text)]


# Words that never change what a generic food looks like (allowed before the head and in
# comma qualifiers).
GLOBAL_MODS = set(words("""
    raw cooked fresh frozen organic whole large medium small extra jumbo mini plain natural
    regular conventional uncooked sliced chopped diced peeled trimmed boneless skinless ripe
    homemade classic traditional original premium select choice standard simple pure
    unsweetened lightly steamed boiled roasted grilled broiled
"""))

# Extra words allowed only in comma qualifiers ("Eggs, Large, Grade A", "Peas, Canned,
# Drained Solids", "Chicken Breast, Roasted, Without Skin", "Fries, Medium (1 serving)").
QUALIFIER_WORDS = set(words("""
    without with skin no salt added drained solid solids grade a aa us edible portion only
    meat flesh oz fl ml g kg lb count piece pieces pc serving servings each item kids kid
    size cup cups slice slices ounce ounces bag
""")) | {str(i) for i in range(0, 1000)}

# (icon, heads, rule-specific modifiers). Heads are phrases (singularised like names).
RULES = [
    # --- eggs (fried before plain egg) ---
    ("cooking", "fried egg|sunny side up egg|egg over easy", "over easy medium hard"),
    ("egg", "egg|hen egg|chicken egg|duck egg",
     "hard soft boiled white brown free range cage pasture pastured omega 3 hardboiled softboiled"),

    # --- fruit ---
    ("green_apple", "green apple|granny smith apple|granny smith", ""),
    ("red_apple", "apple",
     "red gala fuji honeycrisp braeburn pink lady red delicious golden delicious mcintosh "
     "jazz envy ambrosia cosmic crisp empire jonagold rome cortland with skin"),
    ("banana", "banana", "yellow baby cavendish"),
    ("grapes", "grape", "red green black white seedless concord muscat table"),
    ("watermelon", "watermelon", "seedless red yellow"),
    ("melon", "melon|cantaloupe|honeydew|honeydew melon|cantaloupe melon|muskmelon",
     "charentais galia canary casaba crenshaw"),
    ("tangerine", "orange|tangerine|mandarin|mandarin orange|clementine|satsuma",
     "navel blood valencia cara seville"),
    ("lemon", "lemon", "meyer yellow"),
    ("lime", "lime", "key persian green"),
    ("pineapple", "pineapple", "gold golden"),
    ("mango", "mango", "ataulfo haden kent keitt tommy atkins honey champagne"),
    ("peach", "peach|nectarine", "yellow white donut flat"),
    ("pear", "pear", "bartlett anjou bosc green red asian comice"),
    ("cherries", "cherry|sweet cherry|sour cherry", "bing rainier red dark sweet sour tart"),
    ("strawberry", "strawberry", ""),
    ("blueberries", "blueberry", "wild"),
    ("kiwi_fruit", "kiwi|kiwifruit|kiwi fruit", "green gold golden"),
    ("coconut", "coconut", "brown young mature"),
    ("avocado", "avocado", "hass florida green"),
    ("olive", "olive", "green black kalamata ripe pitted castelvetrano manzanilla"),

    # --- vegetables ---
    ("roasted_sweet_potato", "sweet potato|yam", "orange baked"),
    ("tomato", "tomato|cherry tomato|grape tomato|roma tomato|plum tomato",
     "red yellow heirloom beefsteak vine ripened on the"),
    ("eggplant", "eggplant|aubergine", "japanese chinese italian globe"),
    ("cucumber", "cucumber", "english persian seedless mini"),
    ("carrot", "carrot", "baby orange purple"),
    ("ear_of_corn", "corn on the cob|ear of corn|sweet corn|corn|corn kernel",
     "yellow white bicolor"),
    ("hot_pepper", "jalapeno|jalapeno pepper|chili pepper|chile pepper|hot pepper|habanero|"
     "serrano pepper|serrano|thai chili|bird eye chili|red chili|green chili",
     "red green !frozen"),
    ("bell_pepper", "bell pepper|sweet pepper|green pepper|red pepper|yellow pepper",
     "red green yellow orange"),
    ("broccoli", "broccoli|broccoli floret|broccoli crown", ""),
    ("leafy_green", "kale|spinach|bok choy|pak choi|swiss chard|chard|collard green|collard|"
     "romaine lettuce|lettuce|arugula|baby spinach|mustard green|leafy green",
     "baby curly lacinato tuscan red green leaf iceberg butterhead bibb boston"),
    ("garlic", "garlic|garlic clove", ""),
    ("onion", "onion", "red yellow white sweet vidalia spanish"),
    ("brown_mushroom", "mushroom|button mushroom|cremini mushroom|portobello mushroom|"
     "portabella mushroom|shiitake mushroom|white mushroom|baby bella mushroom|shiitake",
     "white brown button cremini crimini portobello portabella shiitake baby bella"),
    ("potato", "potato", "russet red white yellow yukon gold fingerling new baby baked"),
    ("pea_pod", "pea|green pea|snow pea|sugar snap pea|snap pea|edamame|garden pea", "sweet"),
    ("beans", "bean|kidney bean|black bean|pinto bean|navy bean|cannellini bean|"
     "red kidney bean|great northern bean|adzuki bean|borlotti bean|cranberry bean",
     "dark light red small white mature seed dry dried"),
    ("ginger_root", "ginger|ginger root", ""),
    ("peanuts", "peanut", "salted unsalted dry in shell"),
    ("chestnut", "chestnut", ""),

    # --- bread & bakery ---
    ("baguette_bread", "baguette|french baguette", "white whole wheat sourdough"),
    ("croissant", "croissant", "butter all"),
    ("bagel", "bagel",
     "everything sesame poppy seed onion whole wheat cinnamon raisin multigrain white"),
    ("flatbread", "pita|pita bread|naan|naan bread|flatbread|flour tortilla|corn tortilla|"
     "tortilla|chapati|roti|lavash", "white wheat whole garlic"),
    ("bread", "bread|bread slice|loaf|toast",
     "white wheat whole multigrain multi grain rye sourdough grain seeded country italian "
     "sandwich enriched honey oat oatmeal toasted cracked 7 9 12"),
    ("pancakes", "pancake|hotcake", "buttermilk"),
    ("waffle", "waffle", "belgian buttermilk"),
    ("pretzel", "pretzel|soft pretzel", "salted"),
    ("doughnut", "doughnut|donut", "glazed sugar raised yeast cake powdered"),
    ("cupcake", "cupcake", "vanilla chocolate"),
    ("birthday_cake", "birthday cake", ""),
    ("shortcake", "cake|cake slice|shortcake|cheesecake|sponge cake|layer cake",
     "vanilla chocolate yellow white sponge strawberry new york layer"),
    ("pie", "pie", "apple cherry pumpkin pecan blueberry peach sweet potato"),
    ("cookie", "cookie|biscuit cookie",
     "chocolate chip sugar oatmeal raisin peanut butter shortbread snickerdoodle"),
    ("fortune_cookie", "fortune cookie", ""),
    ("custard", "flan|custard|creme caramel|caramel custard|creme brulee", "vanilla egg !frozen"),

    # --- dairy & fats ---
    ("glass_of_milk", "milk",
     "whole skim nonfat fat free low fat reduced 1 2 percent lactose free 2 1 organic almond oat "
     "soy cow goat vitamin d grass fed ultra filtered dairy"),
    ("sandwich", "grilled cheese|grilled cheese sandwich", ""),
    ("cheese_wedge", "cheddar|cheddar cheese|swiss cheese|gouda|gouda cheese|emmental|"
     "emmentaler|gruyere|jarlsberg|edam|edam cheese|manchego|parmesan|parmesan cheese|"
     "comte|colby|monterey jack|colby jack|havarti|provolone|cheese",
     "sharp mild aged extra white yellow swiss smoked"),
    ("butter", "butter|butter stick", "salted unsalted sweet cream cultured grass fed"),

    # --- meat & fish ---
    ("bacon", "bacon|bacon strip|bacon slice", "pork thick cut center crispy smoked applewood"),
    ("poultry_leg", "chicken|chicken breast|chicken thigh|chicken leg|chicken drumstick|"
     "drumstick|chicken wing|turkey leg|turkey drumstick|rotisserie chicken|whole chicken|"
     "roast chicken|fried chicken",
     "roast rotisserie fried oven baked breaded bone in grilled breast thigh leg broiler fryer"),
    ("cut_of_meat", "steak|beef steak|ribeye|ribeye steak|rib eye steak|sirloin|sirloin steak|"
     "t bone steak|strip steak|new york strip|flank steak|skirt steak|filet mignon|"
     "porterhouse steak|tenderloin steak|beef tenderloin|tomahawk steak|pork chop|lamb chop",
     "beef grass fed top bone in angus wagyu new york strip"),
    ("meat_on_bone", "rib|spare rib|baby back rib|short rib|pork rib|beef rib",
     "pork beef bbq barbecue smoked"),
    ("fish", "salmon|salmon fillet|salmon steak|cod|cod fillet|tilapia|tilapia fillet|trout|"
     "halibut|haddock|mackerel|sardine|sea bass|bass|hake|pollock|snapper|red snapper|"
     "catfish|mahi mahi|swordfish|tuna steak|whole fish|fish fillet|fish|herring|carp|"
     "sole|flounder|perch|pike|branzino|sea bream|bream|anchovy|monkfish|grouper|"
     "hake steak|cod loin|salmon loin|trout fillet|halibut fillet|haddock fillet",
     "atlantic pacific wild farmed farm raised king sockeye coho chinook pink rainbow "
     "black striped white yellowfin ahi bluefin lake steelhead smoked fillet steak baked"),
    ("fried_shrimp", "fried shrimp|tempura shrimp|shrimp tempura|breaded shrimp", ""),
    ("shrimp", "shrimp|prawn|king prawn|tiger prawn", "jumbo tiger white pink"),
    ("crab", "crab|crab leg|king crab leg|snow crab leg|dungeness crab|blue crab", "king snow"),
    ("lobster", "lobster|lobster tail", "maine spiny rock"),
    ("oyster", "oyster", "pacific eastern atlantic"),
    ("squid", "squid|calamari|octopus", ""),

    # --- grains & dishes ---
    ("curry_rice", "curry rice|japanese curry|curry", "japanese chicken beef pork vegetable"),
    ("rice_ball", "rice ball|onigiri", ""),
    ("rice_cracker", "rice cracker|senbei", ""),
    ("cooked_rice", "rice|white rice|brown rice|jasmine rice|basmati rice|steamed rice",
     "white brown jasmine basmati long short medium grain enriched parboiled sushi sticky "
     "glutinous instant"),
    ("spaghetti", "spaghetti|pasta|linguine|fettuccine|fettuccini|angel hair pasta|capellini",
     "whole wheat white durum semolina enriched egg"),
    ("steaming_bowl", "ramen|ramen noodle|pho|noodle soup|udon soup", "tonkotsu shoyu miso"),
    ("bowl_with_spoon", "oatmeal|porridge|oat porridge", "instant rolled steel cut"),
    ("bowl_with_spoon", "yogurt|yoghurt|greek yogurt|skyr",
     "plain nonfat non fat free low whole milk greek unsweetened icelandic 0 1 2 5 percent"),
    ("green_salad", "salad|green salad|garden salad|side salad|mixed green salad|house salad",
     "green garden side mixed house"),
    ("pot_of_food", "stew|beef stew|lamb stew", "beef lamb"),
    ("shallow_pan_of_food", "paella", "valenciana seafood"),
    ("takeout_box", "lo mein|chow mein", ""),
    ("dumpling", "dumpling|gyoza|potsticker|pot sticker|jiaozi|momo", "pork chicken vegetable"),
    ("sushi", "sushi|nigiri|sushi roll|maki|maki roll", "salmon tuna"),
    ("bento_box", "bento|bento box", ""),
    ("falafel", "falafel", ""),
    ("stuffed_flatbread", "gyro|doner kebab|shawarma|doner", "chicken lamb beef"),
    ("burrito", "burrito", "bean beef chicken"),
    ("taco", "taco", "beef chicken"),
    ("tamale", "tamale", ""),
    ("hot_dog", "hot dog|hotdog", "beef"),
    ("hamburger", "hamburger|cheeseburger|burger|bacon cheeseburger", "beef double single"),
    ("sandwich", "sandwich|club sandwich", "club ham turkey"),
    ("pizza", "pizza|pizza slice", "cheese pepperoni margherita"),
    ("french_fries", "french fry|fry|fries|french fries", "shoestring crinkle cut steak"),
    ("popcorn", "popcorn", "air popped salted buttered butter"),
    ("fondue", "fondue", "cheese"),
    ("moon_cake", "mooncake|moon cake", ""),
    ("dango", "dango", ""),
    ("oden", "oden", ""),
    ("fish_cake_with_swirl", "narutomaki|kamaboko", ""),

    # --- sweets ---
    ("soft_ice_cream", "soft serve|soft serve ice cream|frozen yogurt|frozen custard",
     "vanilla chocolate"),
    ("ice_cream", "ice cream|gelato", "vanilla chocolate strawberry"),
    ("shaved_ice", "shaved ice|snow cone", ""),
    ("chocolate_bar", "chocolate|chocolate bar",
     "dark milk white bittersweet semisweet semi sweet 70 85 cacao cocoa !frozen"),
    ("lollipop", "lollipop", ""),
    ("candy", "hard candy|candy", "hard"),
    ("honey_pot", "honey", "raw clover wildflower manuka acacia orange blossom"),
    ("salt", "salt|sea salt|table salt|kosher salt", "iodized fine coarse"),

    # --- drinks ---
    ("bubble_tea", "bubble tea|boba tea|boba milk tea|boba", ""),
    ("mate", "yerba mate|mate", ""),
    ("teacup_without_handle", "tea|green tea|matcha tea|black tea|herbal tea|oolong tea|"
     "jasmine tea|chamomile tea|mint tea|peppermint tea|hot tea|brewed tea",
     "brewed hot green black herbal !frozen"),
    ("hot_beverage", "coffee|espresso|americano|black coffee|brewed coffee|drip coffee|"
     "hot coffee|cappuccino|latte|caffe latte|flat white",
     "brewed black hot drip filtered caffe regular decaf decaffeinated double !frozen"),
    ("beer_mug", "beer|lager|ale|pale ale|ipa|stout|pilsner|draft beer", "light regular"),
    ("wine_glass", "red wine|wine", "red table dry"),
    ("bottle_with_popping_cork", "champagne|prosecco|sparkling wine|cava", "brut dry"),
    ("cocktail_glass", "martini|cocktail|cosmopolitan", "dry"),
    ("tropical_drink", "pina colada|mai tai|daiquiri", ""),
    ("tumbler_glass", "whiskey|whisky|bourbon|scotch|scotch whisky|cognac|brandy|rum",
     "dark white"),
    ("sake", "sake", ""),
    ("cup_with_straw", "soda|cola|soft drink|milkshake|smoothie", "regular diet"),
    ("ice", "ice|ice cube", ""),
]


def _compile():
    """-> [(icon, [head tuples], allowed words, denied global words)]. In the modifier string,
    "!word" removes a global modifier for that rule ("Frozen Coffee" is not a hot drink)."""
    compiled = []
    for icon, heads, mods in RULES:
        head_list = [tuple(words(h)) for h in heads.split("|") if words(h)]
        deny = set(words(" ".join(m[1:] for m in mods.split() if m.startswith("!"))))
        extra = set(words(" ".join(m for m in mods.split() if not m.startswith("!"))))
        compiled.append((icon, head_list, (GLOBAL_MODS | extra) - deny, deny))
    return compiled


COMPILED = _compile()

# Joiners that always mean "a dish made of several things" in the head phrase.
REJECT_WORDS = set(words("and with in on or n of style flavor flavored flavoured stuffed filled "
                         "topped coated covered sauce glazed mix bread"))


def split_name(name):
    """-> (head words, qualifier words) or None when the name has a 'with ...' style tail."""
    m = BY_RE.match(name.strip())
    if m:
        name = m.group(1)
    name = PAREN_RE.sub(" ", name)
    parts = [p for p in re.split(r"[,;:/]| - ", name) if p.strip()]
    if not parts:
        return None
    head = words(parts[0].replace("&", " and ").replace("-", " "))
    quals = []
    for p in parts[1:]:
        quals.extend(words(p.replace("&", " and ").replace("-", " ")))
    return head, quals


def match(name):
    """Fluent snake name for a dataset food name, or None."""
    split = split_name(name)
    if not split:
        return None
    head, quals = split
    if not head:
        return None
    for icon, heads, allowed, deny in COMPILED:
        for h in heads:
            n = len(h)
            if len(head) < n or tuple(head[-n:]) != h:
                continue
            prefix = head[:-n]
            # A joiner anywhere before the head ("egg salad sandwich", "banana bread") is a
            # dish, not the generic food; multi-word heads may contain "of"/"on" themselves.
            if any(w in REJECT_WORDS and w not in allowed for w in prefix):
                return None
            if not all(w in allowed for w in prefix):
                continue
            if not all(w in allowed or (w in QUALIFIER_WORDS and w not in deny) for w in quals):
                continue
            return icon
    return None


# --------------------------------------------------------------------------- CLI

def _read_names(path):
    import csv
    csv.field_size_limit(10**9)
    with open(path, newline="", encoding="utf-8") as f:
        first = f.readline()
        f.seek(0)
        if first.startswith("id\t") and "\tname\t" in first:
            for row in csv.DictReader(f, delimiter="\t"):
                yield row["name"], row.get("type", "")
        else:
            for line in f:
                line = line.rstrip("\n")
                if line:
                    yield line, ""


def report(path, samples=40, seed=None):
    import collections
    import random
    total = collections.Counter()
    hit = collections.Counter()
    per_icon = collections.Counter()
    matches = []
    for name, kind in _read_names(path):
        total[kind] += 1
        icon = match(name)
        if icon:
            hit[kind] += 1
            per_icon[icon] += 1
            matches.append((icon, name))
    n, h = sum(total.values()), sum(hit.values())
    print(f"fluent: {h}/{n} foods ({100 * h / max(n, 1):.2f} %)")
    for kind in sorted(total):
        print(f"  {kind or '-':10s} {hit[kind]}/{total[kind]} ({100 * hit[kind] / max(total[kind], 1):.1f} %)")
    print(f"icons used: {len(per_icon)}; top: " +
          ", ".join(f"{k} {v}" for k, v in per_icon.most_common(15)))
    rng = random.Random(seed)
    print(f"\n{samples} random matches:")
    for icon, name in rng.sample(matches, min(samples, len(matches))):
        print(f"  {icon:22s} {name}")


# Precision examples, also mirrored by Tests/FoodEmojiTests.swift for the Swift matcher.
EXAMPLES = {
    "Banana": "banana", "Bananas, Raw": "banana", "Hard Boiled Egg": "egg", "Eggs": "egg",
    "Large White Eggs by Kroger": "egg", "Fried Egg": "cooking", "White Rice": "cooked_rice",
    "Rice, White, Long-Grain, Enriched, Cooked": "cooked_rice", "Cooked Rice": "cooked_rice",
    "Chicken Breast": "poultry_leg", "Roast Chicken": "poultry_leg",
    "Chicken Breast, Boneless Skinless, Cooked": "poultry_leg", "Salmon Fillet": "fish",
    "Hake Steaks, Raw": "fish", "Apples, Raw, With Skin": "red_apple",
    "Granny Smith Apples": "green_apple", "Whole Milk": "glass_of_milk",
    "Cheese Pizza, Large (1 slice, 1/8 pizza) by Pizza Hut": "pizza",
    "French Fries, Medium by Burger King": "french_fries", "Greek Yogurt": "bowl_with_spoon",
    "Grilled Cheese by Five Guys": "sandwich", "Frozen Custard": "soft_ice_cream",
    "Chicken and Mushroom Crepe": None, "Banana Bread": None, "Egg Salad Sandwich": None,
    "Chocolate Milk": None, "Peanut Butter": None, "French Toast": None, "Candy Corn": None,
    "Shrimp Cocktail": None, "Ice Cream Sandwich": None, "Green Beans": None, "Rice Milk": None,
    "Fried Rice": None, "Spaghetti with Meatballs": None, "Chicken Pot Pie": None,
    "Cream Cheese": None, "Frozen Coffee, Large by Dunkin'": None, "Coconut Water": None,
    "Sweet Potato Fries": None, "Buffalo Chicken Wings": None, "Garlic Bread": None,
    "Strawberry Yogurt": None, "Egg Noodles": None, "Root Beer": None, "Baking Soda": None,
}


def selftest():
    bad = [(n, e, match(n)) for n, e in EXAMPLES.items() if match(n) != e]
    for n, e, got in bad:
        print(f"FAIL {n!r}: expected {e}, got {got}")
    print(f"{len(EXAMPLES) - len(bad)}/{len(EXAMPLES)} examples OK")
    if bad:
        sys.exit(1)


def check():
    bundled = {d[:-len(".imageset")] for d in os.listdir(ASSETS) if d.endswith(".imageset")}
    used = {rule[0] for rule in RULES}
    missing = sorted(used - bundled)
    print(f"{len(used)} icons used by {len(RULES)} rules, {len(bundled)} bundled")
    if missing:
        sys.exit(f"missing in asset catalog: {missing}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "--check":
        check()
    elif args[0] == "--test":
        selftest()
    elif args[0] == "--report":
        if len(args) < 2:
            sys.exit(__doc__)
        samples = int(args[args.index("--samples") + 1]) if "--samples" in args else 40
        seed = int(args[args.index("--seed") + 1]) if "--seed" in args else None
        report(args[1], samples, seed)
    else:
        for a in args:
            print(f"{match(a) or '-':22s} {a}")
