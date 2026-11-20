# Assiette — architecture & contracts

Personal iOS nutrition tracker (SwiftUI, iOS 17+, SwiftData, French UI) on top of the
OpenNutrition dataset (ODbL). No backend: the dataset is converted at build time into a
read-only SQLite file (`App/Resources/foods.sqlite`, built by `tools/build_db.py`, ~93 MB,
~327k foods) bundled in the app. Built on GitHub Actions (macOS) into an **unsigned .ipa**
that the user signs and sideloads.

There is **no Mac locally** (a Linux Swift toolchain only builds the Foundation-only engine): app code must compile on the first try with
Xcode 16 (Swift 6 compiler in Swift 5 language mode, `SWIFT_VERSION = 5.0`), iOS 17.0
deployment target. Be conservative with APIs: anything newer than iOS 17.0 must be avoided
(no iOS 18-only APIs such as `@Entry`, `MeshGradient`, `Tab(...)` builder, `.onScrollGeometryChange`,
`#Preview` with traits, `ControlWidget`, etc.).

## Layout

```
App/Sources/
  App/        AssietteApp.swift (entry, RootView with 4 tabs), AppState.swift   [DONE]
  Core/       Nutrients.swift, Food.swift, FoodDatabase.swift, Models.swift      [DONE]
              FrenchFoodLexicon.swift                                            [search agent]
  Shared/     Formatters.swift, Theme.swift (ProgressBar, RingView), AttributionFooter.swift [DONE]
              NutritionTableView.swift                                           [search agent]
  Features/
    Today/        journal tab                                                    [today agent]
    Log/          add / edit entry sheets, quick add                             [today agent]
    Search/       search tab, food detail                                        [search agent]
    Scan/         barcode scanner + Open Food Facts client                       [scan agent]
    Progress/     weight + history charts                                        [progress agent]
    Profile/      onboarding, profile & goals, settings, export, about           [profile agent]
    CustomFoods/  my foods, custom food editor, recipe editor                    [custom agent]
  Engine/     adaptive engine: trend weight, expenditure, weekly coaching (Foundation only)
Tests/            XCTest unit tests (host app = Assiette, so Bundle.main has foods.sqlite)
EngineTests/      engine tests, run on Linux with `swift test` (Package.swift) and in CI
```

### Adaptive engine (`App/Sources/Engine/`)

Pure Foundation code (no SwiftUI/SwiftData), compiled both into the app and as the
`AssietteEngine` Swift package so it can be tested on Linux (`swift test`; toolchain in
`~/.local/share/swift`). Types are prefixed `Engine…`. Pipeline:
`[EngineDay]` (one per calendar day) → `EngineWeightTrend` (Kalman filter = real-time trend,
RTS smoother = retrospective trend) → `EngineExpenditure` (7-day energy balance, adapted ~1.7 %/day)
→ `EngineCoach` (weekly calorie target). Constants live in `EngineParameters`, calibrated
against a MacroFactor export with `tools/mf/`; `EngineCalibrationTests` replays that export
from the gitignored `reference/` folder and is skipped when it is absent.

Files marked [DONE] are the shared core. **Do not modify them** — if you believe a core
change is truly required, implement a workaround in your own files and mention it in your
final report.

## Rules for every feature file

* Only create/edit files inside the folders you own.
* Every type that is not a contract below must be `private`/`fileprivate`, or prefixed
  with your feature name (e.g. `TodayMealSection`, `ScanResultCard`) to avoid duplicate
  symbol errors across agents. No global free functions without a prefix.
* UI text in French. Numbers via `Formatters`. Colors via `Theme`.
* Read app state with `@Environment(AppState.self) private var appState`.
* SwiftData: `@Query`, `@Environment(\.modelContext)`. Models in `Core/Models.swift`.
  Note SwiftData `#Predicate` cannot call computed properties or enums' rawValue
  conveniences — filter on stored properties (`day`, `mealRaw`, `date`, …). Capture
  values in local `let`s before the predicate.
* Screens that display OpenNutrition data must show `AttributionFooter()` (license requirement);
  pass `includeOpenFoodFacts: true` where OFF data can be shown.
* Use `NavigationStack` only at the root of a tab or of a sheet; pushed views must not
  create their own `NavigationStack`.
* Add a `#Preview` only if it is trivial and compiles against an in-memory container:
  `.modelContainer(for: AppSchema.models, inMemory: true)` — **`AppSchema.models` is an
  array, use `try! ModelContainer(for: Schema(AppSchema.models), configurations: ...)` when
  you need a container value**. Previews are optional; prefer none over risky ones.

## Contracts (public types/signatures other agents rely on — implement EXACTLY)

### Core (already written — read the files)
* `NutrientKey`, `NutrientValues` (per-100 g storage, `forGrams`, `+`, `.data`), `FoodKind`,
  `FoodSource`, `Food` (DB row, `.item`), `FoodItem` (unified loggable value; `.id` = "source:ref").
* `FoodDatabase.shared`: `search(_:kinds:limit:)`, `searchAsync(_:kinds:limit:)`,
  `food(id:)`, `food(barcode:)`, `count`, `datasetVersion`, `isAvailable`, `openError`.
* SwiftData models: `JournalEntry(item:grams:day:meal:)`, `UserProfile` (`current(in:)`),
  `WeightEntry(date:kg:)`, `WaterEntry(day:ml:)`, `CustomFood(name:brand:per100:)`,
  `RecipeIngredient`, `FavoriteFood(item:)`. Enums `Meal`, `Sex`, `ActivityLevel`, `WeightGoal`.
* `AppState` (`selectedTab`, `selectedDay`, `addTabContext`), `AppTab`, `LogContext(day:meal:)`.
* `Theme`, `ProgressBar(value:total:color:)`, `RingView(progress:color:lineWidth:)`,
  `AttributionFooter(includeOpenFoodFacts:)`, `Formatters`, `Date.startOfDay`, `Date.adding(days:)`.

### Root view requires (App/AssietteApp.swift)
* `TodayView()` — Features/Today
* `FoodSearchView(context: LogContext, isSheet: Bool)` — Features/Search
* `ProgressDashboardView()` — Features/Progress
* `ProfileView()` — Features/Profile (contains its own NavigationStack)
* `OnboardingView()` — Features/Profile. Presented full screen until
  `UserProfile.hasCompletedOnboarding == true`; it must fetch/create the profile with
  `UserProfile.current(in:)` and set the flag (and save) when finished. It also inserts a
  first `WeightEntry` with the entered weight.

### Search agent
* `enum FrenchFoodLexicon` (Core/FrenchFoodLexicon.swift):
  `static let stopWords: Set<String>` (French + English filler words, already lowercased &
  accent-folded, e.g. "de", "du", "la", "le", "les", "des", "au", "aux", "a", "et", "with", "and", "of");
  `static func translations(for word: String) -> [String]` — `word` is lowercased and
  accent-folded (e.g. "poulet", "oeuf", "pates", "fromage", "creme"); returns English
  equivalents used by the dataset (e.g. ["chicken"], ["egg"], ["pasta"]). Handle plurals
  (strip trailing s/x). Must be fast (dictionary lookup). Cover ≥ 400 common French food
  words (meats, fish, dairy, fruits, vegetables, grains, drinks, dishes, cooking states
  such as cuit→cooked, cru→raw, grillé→grilled, frit→fried, entier→whole, écrémé→skim…).
  Also used for prefix typing: if `word` is a prefix (≥ 3 chars) of exactly one or a few
  lexicon keys, include their translations too (cap 4).
* `FoodSearchView(context: LogContext, isSheet: Bool)` — search field (`.searchable`),
  debounced FTS search through `FoodDatabase.shared.searchAsync`, kind filter chips
  (Tous / Aliments / Plats / Restaurants / Marques), results also include matching
  `CustomFood`s on top. When the query is empty: shortcuts (Scanner un code-barres →
  `BarcodeScanView(context:)` sheet, Ajout rapide → `QuickAddSheet(context:)` sheet,
  Mes aliments → `CustomFoodsListView(pickContext:)` push), then Favoris
  (`FavoriteFood`), then Récents (distinct latest `JournalEntry` items, ~20). Toolbar meal
  picker so the user can change the target meal (keeps a local `@State` copy of context).
  Tapping a result pushes `FoodDetailView(item:context:)`; a trailing "+" button on the
  row opens `AddEntrySheet(item:context:onLogged:)` directly for quick logging.
  When `isSheet` is true, show a "Fermer" toolbar button and dismiss after logging.
  Shows an error state if `FoodDatabase.shared.isAvailable == false`.
* `FoodDetailView(item: FoodItem, context: LogContext)` — header (name, brand, kind badge,
  serving), per-serving / per-100 g toggle, macro summary (kcal + P/G/L with colors and
  % of energy), `NutritionTableView`, favorite toggle (star, inserts/deletes `FavoriteFood`
  keyed by `item.id`), big "Ajouter au journal" button → `AddEntrySheet`. AttributionFooter.
* `NutritionTableView(values: NutrientValues, showDailyPercent: Bool = true)`
  (Shared/NutritionTableView.swift) — grouped list-like VStack (not a List, so it embeds
  anywhere) of all known nutrients by `NutrientKey.Group`, amount via `Formatters.amount`,
  optional % of `dailyReference`. Collapsible "Voir tous les nutriments" for micronutrients.
* `FoodRowView(item: FoodItem)` may be shared by others: name, brand/kind line, kcal per
  serving (or per 100 g) and P/G/L mini summary.

### Today agent (Features/Today + Features/Log)
* `TodayView()` — own `NavigationStack`. Day switcher (chevrons, swipe, tap title → DatePicker,
  "Aujourd'hui" button) bound to `appState.selectedDay`. Summary card: calorie ring
  (consumed / target / remaining from `UserProfile`), macro bars P/G/L vs targets, fiber.
  Water card (+250 ml / +500 ml buttons, total vs `waterTargetMl`, undo last).
  One section per `Meal` with total kcal, entries (`name`, `quantityDescription`, kcal),
  swipe to delete, tap to edit (`AddEntrySheet(editing:)`), "+" opening
  `FoodSearchView(context: LogContext(day:meal:), isSheet: true)` in a sheet wrapped in
  `NavigationStack`. Meal context menu: "Copier depuis hier", "Tout supprimer",
  "Enregistrer comme recette" (creates a `CustomFood` recipe from the meal entries).
  Daily micronutrient summary link (sum of all entries in a `NutritionTableView`).
* `AddEntrySheet(item: FoodItem, context: LogContext, onLogged: (() -> Void)? = nil)` and
  `AddEntrySheet(editing entry: JournalEntry)` — one View with two inits. Has its own
  `NavigationStack`. Quantity input: segmented unit (servings if `servingGrams` known,
  grams/ml always) with numeric field + quick chips (½, 1, 2 portions / 50, 100, 150, 200 g)
  and stepper; meal picker; day picker; live preview of kcal/P/G/L; "Ajouter"/"Enregistrer"
  inserts or updates the `JournalEntry`, calls `onLogged`, dismisses. Edit mode also has
  "Supprimer". Remember last quantity per item in `UserDefaults` (key "lastGrams.<item.id>").
* `QuickAddSheet(context: LogContext)` — name (default "Ajout rapide"), kcal (required),
  optional protein/carbs/fat grams, meal. Inserts a `JournalEntry` with
  `FoodItem(source: .quickAdd, ref: nil, name:…, per100: values)` and `grams: 100`
  (so per100 == absolute values).

### Scan agent
* `BarcodeScanView(context: LogContext)` — presented in a sheet (own `NavigationStack`).
  Uses VisionKit `DataScannerViewController` (EAN-13, EAN-8, UPC-E; check
  `DataScannerViewController.isSupported && isAvailable`), with a manual barcode text field
  fallback (also always available via a toolbar button). On a code: look up
  `FoodDatabase.shared.food(barcode:)`; then `CustomFood` with that `ean`; then
  `OpenFoodFactsClient.product(barcode:)`. Found → push/show `FoodDetailView(item:context:)`
  (OFF items get `includeOpenFoodFacts` attribution). Not found → offer
  "Créer cet aliment" → `CustomFoodEditor(food: nil, prefill: FoodItem?)` with the barcode.
  Haptic feedback on detection; avoid re-triggering on the same code.
* `struct OpenFoodFactsClient` — `static func product(barcode: String) async throws -> FoodItem?`
  using `https://world.openfoodfacts.org/api/v2/product/<code>.json?fields=…` with a generic
  `User-Agent: Assiette-iOS/0.1` header (no personal data). Map `nutriments` *_100g
  (energy-kcal_100g, proteins_100g, carbohydrates_100g, fat_100g, saturated-fat_100g,
  sugars_100g, fiber_100g, salt/sodium_100g (OFF sodium is in **g** → convert to mg),
  etc.) into `NutrientValues`; name from `product_name_fr` ?? `product_name`; brand from
  `brands` (first); serving from `serving_quantity` (+ `serving_size` label); liquid if
  `nutrition_data_per` == "100ml" or quantity unit ml/cl/l. Return `FoodItem(source:
  .openFoodFacts, ref: barcode, ...)`. 404 / status 0 → nil.

### Progress agent
* `ProgressDashboardView()` — own `NavigationStack`. Swift Charts. Range picker 7 / 30 / 90 j.
  Weight: chart of `WeightEntry` with 7-day moving average line, current / start / delta,
  target weight line if set, "Ajouter une pesée" sheet (date + kg, decimal keyboard),
  list of entries with delete. Calories: daily bars vs target rule mark, average, days
  logged. Macros: average P/G/L grams and % of energy, stacked bars per day.
  Streak (consecutive days with ≥1 entry). Fetch with `@Query` and aggregate in Swift
  (group `JournalEntry` by `day`). Weight change also updates `UserProfile.weightKg`
  to the latest entry.

### Profile agent
* `struct GoalCalculator` (Features/Profile/GoalCalculator.swift), pure & unit-testable:
  `static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double`
  (Mifflin-St Jeor), `static func tdee(bmr: Double, activity: ActivityLevel) -> Double`,
  `static func calorieTarget(tdee: Double, goal: WeightGoal, weeklyRateKg: Double) -> Double`
  (7700 kcal per kg, floor at max(1200, bmr*1.0)... keep simple: floor 1200),
  `static func macroTargets(calories: Double, weightKg: Double, goal: WeightGoal) -> (protein: Double, carbs: Double, fat: Double)`
  (protein 2.0 g/kg lose, 1.8 maintain, 1.8 gain; fat 25 % kcal min 0.6 g/kg; carbs = rest, ≥ 0),
  `static func apply(to profile: UserProfile)` recomputes the targets unless `manualTargets`.
* `OnboardingView()` — paged steps: welcome (mentions OpenNutrition), sex, birth year,
  height, weight, activity, goal (+ weekly rate & target weight when not maintain),
  summary of computed targets (editable), finish.
* `ProfileView()` — own `NavigationStack`: profile fields editable (recompute on change),
  targets section (auto vs manual with fields for kcal/P/G/L/fiber/water, macro % display),
  "Mes aliments & recettes" → `CustomFoodsListView(pickContext: nil)`,
  data: export journal CSV + full JSON backup via `ShareLink` (files written to temp dir),
  import JSON backup (fileImporter) , "Effacer toutes les données" (confirmation),
  About: app version, dataset version + count (`FoodDatabase.shared`), ODbL attribution
  & license text summary, links to opennutrition.app and Open Food Facts.

### Custom foods agent
* `CustomFoodsListView(pickContext: LogContext?)` — pushed view (no NavigationStack).
  Segments Aliments / Recettes, search, swipe delete, tap → editor; when `pickContext` is
  non-nil, tapping an item opens `AddEntrySheet(item: food.item, context:)` instead and a
  pencil button edits. Toolbar "+" menu: Nouvel aliment / Nouvelle recette.
* `CustomFoodEditor(food: CustomFood?, prefill: FoodItem? = nil, barcode: String? = nil)` —
  sheet content with own `NavigationStack`: name, brand, barcode, liquid toggle, serving
  label + grams, nutrition entered "pour 100 g" or "par portion" (converted to per 100 g),
  kcal/P/G/L required-ish, collapsible extras (fibres, sucres, AGS, sel→sodium mg …).
  Saves/updates a `CustomFood`.
* `RecipeEditor(recipe: CustomFood?)` — own `NavigationStack`: name, servings count or
  serving label, ingredient list (add via an internal search sheet over
  `FoodDatabase.shared.searchAsync` + custom foods, choose grams), cooked total weight
  (default = sum), live totals per portion and per 100 g; saves `CustomFood` with
  `ingredients`, `per100` = sum / totalGrams * 100, `servingGrams` = totalGrams / servings.

### Tests agent (Tests/)
XCTest (`@testable import Assiette`): NutrientValues math & Data round-trip,
FoodDatabase.ftsQuery building, FoodDatabase search/barcode against bundled db
(skip with `XCTSkip` if `!FoodDatabase.shared.isAvailable`), GoalCalculator values,
FrenchFoodLexicon (poulet → chicken, plural handling), OpenFoodFactsClient JSON mapping if
it exposes a pure `static func map(json: Data, barcode: String) -> FoodItem?` (scan agent: please expose it).
