import Foundation

/// French → English food vocabulary used to search the (US English) OpenNutrition dataset
/// with French words. All keys are lowercased and accent-folded ("oeuf", "pates", "creme").
///
/// * `translations(for:)` is used by `FoodDatabase.ftsQuery(for:)`: every French token is
///   OR-ed with its English equivalents. Single-word translations are prefix-matched by
///   FTS ("egg" matches "Eggs"), multi-word translations are matched as phrases.
/// * `rewritingPhrases(_:)` turns common French compound names ("pomme de terre",
///   "haricots verts", "blanc de poulet") into their English name before searching, since
///   they cannot be translated word by word.
enum FrenchFoodLexicon {

    // MARK: - Public API

    /// French + English filler words (lowercased, accent-folded) ignored by the search.
    /// Note: "the" is deliberately absent, it is the folded form of "thé" (tea).
    static let stopWords: Set<String> = [
        // French articles, prepositions, conjunctions, pronouns
        "a", "au", "aux", "avec", "c", "ce", "ces", "cet", "cette", "d", "dans", "de", "des",
        "du", "en", "et", "j", "l", "la", "le", "les", "m", "ma", "mes", "mon", "n", "ou",
        "par", "pour", "qu", "que", "s", "sa", "ses", "son", "sur", "t", "ta", "tes", "ton",
        "un", "une", "y", "chez", "facon", "fait", "faite", "faits", "faites", "genre",
        "style", "type", "sorte", "comme", "tres", "plus", "peu", "bien", "aussi",
        // English filler
        "and", "an", "of", "with", "in", "on", "or", "for", "to", "w",
    ]

    /// English equivalents of a French word (`word` lowercased & accent-folded, e.g.
    /// "poulet" → ["chicken"]). Handles plurals (trailing s/x, -aux → -al) and feminine
    /// forms (trailing e). When the word is not a known key but is a prefix (≥ 3 letters)
    /// of a few keys (search-as-you-type: "poul" → "poulet"), their translations are
    /// returned (at most 4). Returns [] for unknown words.
    static func translations(for word: String) -> [String] {
        let w = normalize(word)
        guard w.count >= 2 else { return [] }
        for candidate in variants(of: w) {
            if let found = table[candidate] { return found }
        }
        guard w.count >= 3 else { return [] }
        return prefixTranslations(for: w)
    }

    /// Rewrites known French multi-word food names into their English dataset name, e.g.
    /// "pommes de terre vapeur" → "potato vapeur", "blanc de poulet" → "chicken breast".
    /// Other words are returned unchanged (lowercased, accent-folded; stop words removed).
    /// Feed the result to `FoodDatabase.search`.
    static func rewritingPhrases(_ text: String) -> String {
        let words = tokenize(text).filter { !stopWords.contains($0) }
        guard words.count >= 2 else { return words.joined(separator: " ") }
        let keys = words.map(phraseKeyComponent)
        var output: [String] = []
        var i = 0
        while i < words.count {
            var matched = false
            var length = min(maxPhraseLength, words.count - i)
            while length >= 2 {
                let key = keys[i..<(i + length)].joined(separator: " ")
                if let english = phrases[key] {
                    output.append(english)
                    i += length
                    matched = true
                    break
                }
                length -= 1
            }
            if !matched {
                output.append(words[i])
                i += 1
            }
        }
        return output.joined(separator: " ")
    }

    /// Number of distinct French keys (for tests / diagnostics).
    static var entryCount: Int { table.count }

    // MARK: - Normalization

    private static func normalize(_ word: String) -> String {
        word.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ text: String) -> [String] {
        normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Lookup candidates: the word, its singular, then their masculine forms.
    private static func variants(of w: String) -> [String] {
        var out = [w]
        if w.count > 3 {
            if w.hasSuffix("aux") { out.append(String(w.dropLast(3)) + "al") }
            if w.hasSuffix("s") || w.hasSuffix("x") { out.append(String(w.dropLast())) }
        }
        for v in out where v.count > 3 && v.hasSuffix("e") {
            out.append(String(v.dropLast()))
        }
        return out
    }

    /// Phrase keys ignore plurals: trailing s/x stripped on words longer than 3 letters.
    private static func phraseKeyComponent(_ w: String) -> String {
        if w.count > 3, w.hasSuffix("s") || w.hasSuffix("x") { return String(w.dropLast()) }
        return w
    }

    private static func prefixTranslations(for w: String) -> [String] {
        // Binary search for the first key >= w.
        var lo = 0
        var hi = sortedKeys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedKeys[mid] < w { lo = mid + 1 } else { hi = mid }
        }
        var matches: [String] = []
        var i = lo
        while i < sortedKeys.count, sortedKeys[i].hasPrefix(w) {
            matches.append(sortedKeys[i])
            if matches.count > maxPrefixKeys { return [] } // too ambiguous
            i += 1
        }
        var out: [String] = []
        for key in matches {
            for t in table[key] ?? [] where !out.contains(t) {
                out.append(t)
                if out.count >= maxPrefixTranslations { return out }
            }
        }
        return out
    }

    private static let maxPrefixKeys = 5
    private static let maxPrefixTranslations = 4
    private static let maxPhraseLength = 4

    // MARK: - Tables (parsed once, lazily and thread-safely, from the text below)

    private static let table: [String: [String]] = {
        var dict: [String: [String]] = [:]
        for rawLine in lexiconSource.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let key = normalize(String(line[..<colon]))
            let values = line[line.index(after: colon)...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            guard !key.isEmpty, !values.isEmpty else { continue }
            var existing = dict[key] ?? []
            for v in values where !existing.contains(v) { existing.append(v) }
            dict[key] = existing
        }
        return dict
    }()

    private static let sortedKeys: [String] = table.keys.sorted()

    private static let phrases: [String: String] = {
        var dict: [String: String] = [:]
        for rawLine in phraseSource.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = tokenize(String(line[..<eq]))
                .filter { !stopWords.contains($0) }
                .map(phraseKeyComponent)
                .joined(separator: " ")
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, !value.isEmpty else { continue }
            dict[key] = value
        }
        return dict
    }()

    // Format: `french: english, english phrase, …` (one key per line, singular form).
    private static let lexiconSource = """
    # Volailles & viandes
    poulet: chicken
    poule: chicken, hen
    poussin: chicken
    volaille: poultry, chicken
    dinde: turkey
    dindon: turkey
    canard: duck
    caneton: duck
    oie: goose
    pintade: guinea fowl
    caille: quail
    faisan: pheasant
    pigeon: pigeon, squab
    lapin: rabbit
    boeuf: beef
    bovin: beef
    veau: veal
    porc: pork
    cochon: pork, pig
    agneau: lamb
    mouton: mutton, lamb
    chevre: goat
    cheval: horse
    gibier: game, venison
    cerf: venison, deer
    chevreuil: venison
    sanglier: boar
    bison: bison
    autruche: ostrich
    viande: meat
    charcuterie: deli, cold cuts, charcuterie
    jambon: ham
    lardon: bacon, lardons
    lard: bacon, lard
    bacon: bacon
    saucisse: sausage
    saucisson: salami, sausage
    chipolata: sausage
    merguez: merguez, sausage
    boudin: blood sausage, sausage
    andouille: andouille, sausage
    andouillette: andouillette, sausage
    knacki: hot dog, frankfurter
    francfort: frankfurter, hot dog
    mortadelle: mortadella, bologna
    rosette: salami
    coppa: coppa
    pancetta: pancetta
    bresaola: bresaola
    steak: steak
    bifteck: steak
    entrecote: ribeye, rib eye, steak
    filet: fillet, filet, tenderloin
    rumsteck: rump, sirloin
    romsteck: rump, sirloin
    bavette: flank steak, skirt steak
    onglet: hanger steak
    tournedos: tenderloin, filet mignon
    cote: chop, rib
    cotelette: chop, cutlet
    escalope: cutlet, scallopini, breast
    roti: roast, roasted
    rotisserie: rotisserie
    poitrine: breast, belly, brisket
    epaule: shoulder
    gigot: leg
    jarret: shank
    joue: cheek
    queue: tail
    echine: shoulder, pork shoulder
    travers: spare ribs, ribs
    carre: rack
    cuisse: thigh, leg
    pilon: drumstick
    aile: wing
    aileron: wing
    aiguillette: tender, tenderloin
    blanc: white, breast
    magret: duck breast
    foie: liver
    rognon: kidney
    coeur: heart
    langue: tongue
    tripe: tripe
    abat: offal, giblets
    gesier: gizzard
    cervelle: brain
    peau: skin
    desosse: boneless
    gras: fat, fatty
    maigre: lean
    hache: ground, minced, chopped
    nugget: nugget
    pane: breaded
    panure: breaded
    kebab: kebab, gyro
    gyros: gyro
    brochette: skewer, kebab
    paupiette: roulade
    confit: confit
    rillette: rillettes
    terrine: terrine, pate
    quenelle: dumpling, quenelle
    boulette: meatball
    hamburger: hamburger, burger
    burger: burger
    cheeseburger: cheeseburger
    croquette: croquette, nugget

    # Poissons & fruits de mer
    poisson: fish
    saumon: salmon
    thon: tuna
    cabillaud: cod
    morue: cod
    colin: pollock, hake
    lieu: pollock
    merlu: hake
    merlan: whiting
    sole: sole
    bar: sea bass, bass
    loup: sea bass
    dorade: sea bream, bream
    daurade: sea bream, bream
    truite: trout
    sardine: sardine
    maquereau: mackerel
    hareng: herring
    anchois: anchovy, anchovies
    espadon: swordfish
    tilapia: tilapia
    panga: pangasius, swai
    fletan: halibut
    raie: skate
    turbot: turbot
    lotte: monkfish
    rouget: mullet
    eglefin: haddock
    haddock: haddock
    carpe: carp
    perche: perch
    brochet: pike
    anguille: eel
    sandre: pike perch, walleye
    mulet: mullet
    surimi: surimi, imitation crab
    crevette: shrimp, prawn
    gambas: prawn, shrimp
    langoustine: langoustine, prawn
    homard: lobster
    langouste: lobster
    crabe: crab
    tourteau: crab
    moule: mussel
    huitre: oyster
    coquille: scallop, shell
    petoncle: scallop
    calamar: calamari, squid
    calmar: squid, calamari
    encornet: squid
    poulpe: octopus
    pieuvre: octopus
    seiche: cuttlefish
    bulot: whelk
    bigorneau: periwinkle
    oursin: sea urchin
    palourde: clam
    coque: cockle, clam
    caviar: caviar
    tarama: taramasalata
    crustace: shellfish
    coquillage: shellfish
    sushi: sushi
    sashimi: sashimi
    maki: maki, sushi roll
    poke: poke

    # Oeufs & produits laitiers
    oeuf: egg
    jaune: yolk, yellow
    omelette: omelet, omelette
    lait: milk
    laitage: dairy
    fromage: cheese
    yaourt: yogurt
    yoghourt: yogurt
    yogourt: yogurt
    skyr: skyr
    creme: cream
    beurre: butter
    margarine: margarine
    emmental: emmental, swiss cheese
    gruyere: gruyere, swiss cheese
    comte: comte, gruyere
    camembert: camembert
    brie: brie
    roquefort: roquefort, blue cheese
    feta: feta
    mozzarella: mozzarella
    parmesan: parmesan, parmigiano
    cheddar: cheddar
    raclette: raclette
    reblochon: reblochon
    munster: muenster, munster
    tomme: tomme
    cantal: cantal
    mimolette: mimolette
    bleu: blue
    ricotta: ricotta
    mascarpone: mascarpone
    burrata: burrata
    halloumi: halloumi
    gouda: gouda
    edam: edam
    gorgonzola: gorgonzola
    pecorino: pecorino
    manchego: manchego
    provolone: provolone
    cottage: cottage
    faisselle: cottage cheese
    kefir: kefir
    lactose: lactose
    ecreme: skim, nonfat, fat free, low fat, reduced fat
    entier: whole
    demi: half, reduced
    allege: light, lite, reduced, low
    leger: light, lite
    nature: plain, natural
    chantilly: whipped cream
    fouette: whipped
    glace: ice cream, ice
    sorbet: sorbet
    lactose: lactose
    lactique: dairy

    # Fruits
    fruit: fruit
    pomme: apple
    poire: pear
    banane: banana
    orange: orange
    clementine: clementine, mandarin
    mandarine: mandarin, tangerine
    citron: lemon
    lime: lime
    pamplemousse: grapefruit
    pomelo: grapefruit, pomelo
    fraise: strawberry, strawberries
    framboise: raspberry, raspberries
    myrtille: blueberry, blueberries
    mure: blackberry, blackberries
    cassis: blackcurrant, currant
    groseille: currant, redcurrant
    cerise: cherry, cherries
    griotte: cherry, cherries
    abricot: apricot
    peche: peach
    nectarine: nectarine
    brugnon: nectarine
    prune: plum
    mirabelle: plum
    quetsche: plum
    pruneau: prune
    raisin: grape, raisin
    figue: fig
    datte: date
    kiwi: kiwi
    ananas: pineapple
    mangue: mango
    papaye: papaya
    goyave: guava
    passion: passion fruit
    maracuja: passion fruit
    litchi: lychee, litchi
    grenade: pomegranate
    melon: melon, cantaloupe
    pasteque: watermelon
    coco: coconut
    avocat: avocado
    olive: olive
    rhubarbe: rhubarb
    coing: quince
    kaki: persimmon
    physalis: physalis, ground cherry
    canneberge: cranberry, cranberries
    cranberry: cranberry, cranberries
    airelle: lingonberry, cranberry
    baie: berry, berries
    agrume: citrus
    compote: applesauce, compote, fruit puree
    confiture: jam, preserves, jelly
    gelee: jelly, gelatin
    marmelade: marmalade
    jus: juice
    nectar: nectar
    smoothie: smoothie
    sec: dried, dry
    seche: dried, dry
    sirop: syrup

    # Légumes
    legume: vegetable
    legumineuse: legume, beans
    carotte: carrot
    tomate: tomato
    patate: potato
    courgette: zucchini, courgette
    aubergine: eggplant, aubergine
    poivron: bell pepper, pepper
    piment: chili, pepper, jalapeno
    jalapeno: jalapeno
    concombre: cucumber
    cornichon: pickle, gherkin
    salade: salad, lettuce
    laitue: lettuce
    roquette: arugula
    mache: lettuce, mache
    epinard: spinach
    chou: cabbage
    brocoli: broccoli
    kale: kale
    blette: chard, swiss chard
    poireau: leek
    oignon: onion
    ognon: onion
    echalote: shallot
    ail: garlic
    ciboulette: chives
    persil: parsley
    basilic: basil
    coriandre: cilantro, coriander
    menthe: mint
    thym: thyme
    romarin: rosemary
    laurier: bay leaf
    origan: oregano
    estragon: tarragon
    aneth: dill
    sauge: sage
    champignon: mushroom
    cepe: porcini
    girolle: chanterelle
    pleurote: oyster mushroom
    shiitake: shiitake
    truffe: truffle
    asperge: asparagus
    artichaut: artichoke
    celeri: celery
    fenouil: fennel
    radis: radish
    navet: turnip
    betterave: beet, beetroot
    panais: parsnip
    topinambour: jerusalem artichoke, sunchoke
    potiron: pumpkin
    citrouille: pumpkin
    courge: squash
    butternut: butternut
    potimarron: squash
    haricot: bean
    flageolet: flageolet, bean
    feve: fava, broad bean
    pois: pea
    lentille: lentil
    chiche: chickpea, garbanzo
    soja: soy
    tofu: tofu
    tempeh: tempeh
    seitan: seitan
    edamame: edamame
    mais: corn
    germe: sprout
    pousse: sprout, shoot
    bambou: bamboo
    algue: seaweed, algae
    endive: endive
    chicoree: chicory
    cresson: watercress
    gombo: okra
    manioc: cassava, yuca
    igname: yam
    taro: taro
    capre: caper
    crudite: raw vegetables, vegetable
    ratatouille: ratatouille
    soupe: soup
    potage: soup
    veloute: soup, bisque
    bouillon: broth, stock, bouillon
    gaspacho: gazpacho
    gazpacho: gazpacho
    minestrone: minestrone

    # Épices, condiments, sauces
    gingembre: ginger
    curcuma: turmeric
    cannelle: cinnamon
    muscade: nutmeg
    poivre: pepper
    sel: salt
    paprika: paprika
    cumin: cumin
    curry: curry
    vanille: vanilla
    girofle: clove
    safran: saffron
    moutarde: mustard
    ketchup: ketchup
    mayonnaise: mayonnaise, mayo
    mayo: mayonnaise, mayo
    vinaigrette: dressing, vinaigrette
    sauce: sauce, gravy
    pesto: pesto
    bechamel: bechamel, white sauce
    huile: oil
    vinaigre: vinegar
    balsamique: balsamic
    colza: canola, rapeseed
    tournesol: sunflower
    arachide: peanut
    saindoux: lard
    graisse: fat, shortening
    houmous: hummus
    hummus: hummus
    tzatziki: tzatziki
    guacamole: guacamole
    salsa: salsa
    tapenade: tapenade
    harissa: harissa
    sriracha: sriracha
    wasabi: wasabi
    epice: spice, spicy
    herbe: herb
    aromate: herb, seasoning
    condiment: condiment

    # Céréales, féculents, boulangerie
    pain: bread
    baguette: baguette, french bread
    brioche: brioche
    croissant: croissant
    chocolatine: chocolate croissant
    viennoiserie: pastry
    biscotte: rusk, toast
    toast: toast
    tartine: toast
    complet: whole wheat, whole grain, wholemeal
    cereale: cereal, grain
    ble: wheat
    farine: flour
    riz: rice
    pates: pasta
    pate: pasta, pate, dough
    spaghetti: spaghetti
    nouille: noodle
    macaroni: macaroni
    coquillette: macaroni, pasta
    penne: penne
    fusilli: fusilli, rotini
    tagliatelle: tagliatelle, fettuccine
    linguine: linguine
    lasagne: lasagna
    ravioli: ravioli
    tortellini: tortellini
    gnocchi: gnocchi
    couscous: couscous
    semoule: semolina, couscous
    boulgour: bulgur
    quinoa: quinoa
    avoine: oat
    flocon: flakes
    muesli: muesli
    granola: granola
    orge: barley
    seigle: rye
    sarrasin: buckwheat
    epeautre: spelt
    millet: millet
    polenta: polenta, cornmeal
    tortilla: tortilla
    wrap: wrap
    pita: pita
    naan: naan
    bagel: bagel
    bretzel: pretzel
    galette: galette, pancake, rice cake
    crepe: crepe, pancake
    gaufre: waffle
    pancake: pancake
    blini: blini
    biscuit: cookie, biscuit, cracker
    sable: shortbread
    cracker: cracker
    gateau: cake
    tarte: pie, tart
    tartelette: tart
    quiche: quiche
    pizza: pizza
    sandwich: sandwich
    panini: panini
    feuillete: puff pastry
    patisserie: pastry
    muffin: muffin
    madeleine: madeleine
    financier: financier
    cookie: cookie
    brownie: brownie
    donut: donut, doughnut
    beignet: donut, fritter, beignet
    chouquette: cream puff
    eclair: eclair
    macaron: macaron, macaroon
    meringue: meringue
    flan: custard, flan
    mousse: mousse
    tiramisu: tiramisu
    clafoutis: clafoutis
    crumble: crumble
    cake: cake
    chapelure: breadcrumbs, bread crumbs
    levure: yeast
    amidon: starch
    fecule: starch
    popcorn: popcorn
    chips: chips, crisps

    # Noix & graines
    noix: walnut, nut
    noisette: hazelnut
    amande: almond
    cacahuete: peanut
    cacahouete: peanut
    pistache: pistachio
    cajou: cashew
    pecan: pecan
    macadamia: macadamia
    chataigne: chestnut
    marron: chestnut, brown
    graine: seed
    sesame: sesame
    lin: flax, flaxseed
    chia: chia
    pavot: poppy
    pignon: pine nut
    oleagineux: nut

    # Sucré
    chocolat: chocolate
    cacao: cocoa, cacao
    sucre: sugar, sweetened
    edulcorant: sweetener
    stevia: stevia
    miel: honey
    erable: maple
    agave: agave
    bonbon: candy
    confiserie: candy, confectionery
    caramel: caramel
    nougat: nougat
    praline: praline
    pralin: praline
    nutella: nutella, hazelnut spread
    tartiner: spread
    barre: bar
    dessert: dessert
    reglisse: licorice
    guimauve: marshmallow
    chewing: gum
    gelatine: gelatin
    sucette: lollipop
    friandise: candy, treat
    pudding: pudding

    # Boissons
    eau: water
    cafe: coffee
    expresso: espresso
    espresso: espresso
    cappuccino: cappuccino
    the: tea
    tisane: herbal tea, tea
    infusion: tea, infusion
    boisson: drink, beverage
    soda: soda
    cola: cola
    coca: cola, coke
    limonade: lemonade
    biere: beer
    vin: wine
    champagne: champagne
    cidre: cider
    alcool: alcohol
    whisky: whiskey, whisky
    vodka: vodka
    rhum: rum
    gin: gin
    tequila: tequila
    cocktail: cocktail
    aperitif: aperitif
    liqueur: liqueur
    gazeuse: sparkling, carbonated
    gazeux: sparkling, carbonated
    petillant: sparkling
    energisant: energy
    proteine: protein
    whey: whey
    lactoserum: whey
    milkshake: milkshake
    frappe: frappe, iced

    # Plats
    plat: dish, entree
    repas: meal
    entree: appetizer, starter
    gratin: gratin, au gratin, casserole
    puree: puree, mashed
    frite: fries, french fries
    frit: fried
    friture: fried
    blanquette: stew
    ragout: stew
    bourguignon: stew
    pot: pot
    cassoulet: cassoulet
    choucroute: sauerkraut
    tajine: tagine
    tagine: tagine
    paella: paella
    risotto: risotto
    hachis: shepherd pie, hash
    parmentier: shepherd pie
    chili: chili
    taco: taco
    burrito: burrito
    nachos: nachos
    fajita: fajita
    enchilada: enchilada
    quesadilla: quesadilla
    ramen: ramen
    pho: pho
    nem: spring roll, egg roll
    rouleau: roll
    samoussa: samosa
    samosa: samosa
    falafel: falafel
    taboule: tabbouleh
    dahl: dal, dahl
    dal: dal, dahl
    biryani: biryani
    tandoori: tandoori
    wok: stir fry
    barbecue: barbecue, bbq
    raviole: ravioli
    croque: croque, grilled cheese
    tartiflette: tartiflette
    fondue: fondue
    moussaka: moussaka
    goulash: goulash
    bolognaise: bolognese
    carbonara: carbonara
    souffle: souffle
    feuille: leaf, leaves
    bol: bowl

    # Préparations & états
    cuit: cooked
    cru: raw
    grille: grilled, toasted
    bouilli: boiled
    poele: pan fried, sauteed
    vapeur: steamed
    braise: braised
    mijote: stewed, simmered
    saute: sauteed
    fume: smoked
    cuisine: cooked, prepared
    prepare: prepared
    surgele: frozen
    congele: frozen
    frais: fresh
    fraiche: fresh
    conserve: canned
    boite: canned
    appertise: canned
    marine: marinated
    sale: salted, salty
    doux: sweet, mild
    sucree: sweet, sweetened
    pique: spicy, hot
    piquant: spicy, hot
    fort: strong, hot
    moitie: half
    tranche: slice, sliced
    morceau: piece, chunk
    rape: grated, shredded
    emince: sliced
    coupe: cut
    cube: cubed, diced
    mixe: blended
    liquide: liquid
    poudre: powder, powdered
    concentre: concentrate, condensed
    instantane: instant
    soluble: instant
    lyophilise: freeze dried
    maison: homemade
    bio: organic
    biologique: organic
    vegetal: plant based, vegan
    vegetarien: vegetarian
    vegan: vegan
    vegetalien: vegan
    sans: free, unsweetened
    gluten: gluten
    petit: small, mini
    grand: large
    gros: large, big
    moyen: medium
    mini: mini
    extra: extra
    double: double
    simple: plain, single
    plein: whole, full
    rouge: red
    vert: green
    noir: black
    brun: brown
    roux: brown
    violet: purple
    rose: rose, pink
    dore: golden
    orange: orange
    bouteille: bottle
    canette: can
    verre: glass
    tasse: cup
    cuillere: spoon, tablespoon
    portion: serving, portion
    nouveau: new
    original: original
    classique: classic, original
    traditionnel: traditional
    ancien: old fashioned
    epais: thick
    fin: thin
    croustillant: crispy, crunchy
    croquant: crunchy
    fondant: melting
    onctueux: creamy
    cremeux: creamy
    chaud: hot, warm
    froid: cold, iced
    """

    // Format: `french words = english name` (plural-insensitive, stop words ignored).
    private static let phraseSource = """
    pomme de terre = potato
    pomme de terre douce = sweet potato
    patate douce = sweet potato
    pomme de terre au four = baked potato
    puree de pomme de terre = mashed potatoes
    puree de pommes de terre = mashed potatoes
    pomme vapeur = boiled potatoes
    pomme frite = french fries
    pomme dauphine = potato croquettes
    gratin dauphinois = scalloped potatoes
    chou fleur = cauliflower
    chou rouge = red cabbage
    chou blanc = white cabbage
    chou de bruxelles = brussels sprouts
    chou kale = kale
    chou chinois = bok choy
    chou frise = kale
    celeri rave = celeriac
    haricot vert = green beans
    haricot rouge = kidney beans
    haricot blanc = white beans
    haricot noir = black beans
    haricot beurre = wax beans
    petit pois = peas
    pois chiche = chickpea
    pois casse = split peas
    pousse de soja = bean sprouts
    germe de soja = bean sprouts
    fruit de mer = seafood
    fruits de la passion = passion fruit
    fruit de la passion = passion fruit
    fruit sec = dried fruit
    raisin sec = raisins
    citron vert = lime
    noix de coco = coconut
    lait de coco = coconut milk
    creme de coco = coconut cream
    noix de cajou = cashew
    noix de pecan = pecan
    noix de macadamia = macadamia
    noix de muscade = nutmeg
    noix de saint jacques = scallops
    saint jacques = scallops
    beurre de cacahuete = peanut butter
    beurre de cacahouete = peanut butter
    beurre d arachide = peanut butter
    pate a tartiner = hazelnut spread
    creme fraiche = sour cream
    creme glacee = ice cream
    creme chantilly = whipped cream
    creme anglaise = custard
    creme dessert = pudding
    creme brulee = creme brulee
    fromage rape = shredded cheese
    fromage de chevre = goat cheese
    fromage frais = cream cheese
    fromage a tartiner = cream cheese
    yaourt grec = greek yogurt
    lait ecreme = skim milk
    lait demi ecreme = reduced fat milk
    lait entier = whole milk
    lait en poudre = powdered milk
    lait concentre = condensed milk
    lait d avoine = oat milk
    lait d amande = almond milk
    lait de soja = soy milk
    lait de riz = rice milk
    riz au lait = rice pudding
    oeuf dur = hard boiled egg
    oeuf brouille = scrambled eggs
    oeufs brouilles = scrambled eggs
    oeuf au plat = fried egg
    oeuf poche = poached egg
    oeuf a la coque = boiled egg
    blanc d oeuf = egg white
    jaune d oeuf = egg yolk
    blanc de poulet = chicken breast
    filet de poulet = chicken breast
    escalope de poulet = chicken breast
    cuisse de poulet = chicken thigh
    haut de cuisse = chicken thigh
    aile de poulet = chicken wings
    pilon de poulet = chicken drumstick
    blanc de dinde = turkey breast
    escalope de dinde = turkey breast
    filet de dinde = turkey breast
    dinde hachee = ground turkey
    steak hache = ground beef
    viande hachee = ground beef
    boeuf hache = ground beef
    porc hache = ground pork
    filet mignon = tenderloin
    faux filet = sirloin steak
    cote de porc = pork chop
    cote d agneau = lamb chop
    jambon blanc = ham
    jambon cuit = ham
    jambon cru = prosciutto
    jambon de parme = prosciutto
    jambon de bayonne = prosciutto
    blanc de volaille = chicken breast
    cordon bleu = cordon bleu
    boeuf bourguignon = beef stew
    pot au feu = beef stew
    hachis parmentier = shepherd pie
    salade verte = green salad
    salade cesar = caesar salad
    salade nicoise = nicoise salad
    huile d olive = olive oil
    sauce tomate = tomato sauce
    sauce soja = soy sauce
    pain de mie = white bread
    pain complet = whole wheat bread
    pain d epice = gingerbread
    pain perdu = french toast
    pain grille = toast
    pain au chocolat = chocolate croissant
    pain aux raisins = raisin bread
    pain burger = hamburger bun
    pain hamburger = hamburger bun
    pain pita = pita
    pate brisee = pie crust
    pate feuilletee = puff pastry
    pate a pizza = pizza dough
    pate complete = whole wheat pasta
    pates completes = whole wheat pasta
    riz complet = brown rice
    riz basmati = basmati rice
    riz blanc = white rice
    flocon d avoine = oats
    flocons d avoine = oats
    chocolat noir = dark chocolate
    chocolat au lait = milk chocolate
    chocolat blanc = white chocolate
    chocolat chaud = hot chocolate
    sucre roux = brown sugar
    sucre glace = powdered sugar
    sucre vanille = vanilla sugar
    sirop d erable = maple syrup
    eau gazeuse = sparkling water
    eau petillante = sparkling water
    the vert = green tea
    the noir = black tea
    the glace = iced tea
    cafe au lait = latte
    jus d orange = orange juice
    jus de pomme = apple juice
    vin rouge = red wine
    vin blanc = white wine
    pomme chips = potato chips
    hot dog = hot dog
    pop corn = popcorn
    croque monsieur = croque monsieur
    cheese cake = cheesecake
    gateau au fromage = cheesecake
    gateau au chocolat = chocolate cake
    mousse au chocolat = chocolate mousse
    tarte aux pommes = apple pie
    glace a la vanille = vanilla ice cream
    """
}
