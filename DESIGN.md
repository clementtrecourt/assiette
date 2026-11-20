# Assiette — design spec "Coaching" (validated 2026-11-20)

Reference mockups: `design/coaching-v1/maquettes.html` (11 screens). The app's structure is
inspired by MacroFactor's information architecture (dashboard, hourly timeline journal,
quick add flow, weekly coached program). The look is Assiette's own: DM Sans, our own icons
(SF Symbols, Fluent Emoji, OpenNutrition), our own French copy. Never reuse MacroFactor's
assets, logo, illustrations or text.

## Non-negotiable rules
1. **Macro order is always Glucides / Protéines / Lipides** (G, P, L). Use `Theme.macroOrder`
   and `Theme.letter(for:)` everywhere: headers, rows, cards, sheets, charts, program, check-in.
2. **Keyboard first.** Whenever a screen's main job is typing (search, quantity, quick add,
   weight, manual barcode, any numeric target), the right keyboard is up when the screen appears,
   with no extra tap. Use `@FocusState` set in `.onAppear`/`.task` (or `defaultFocus`), the right
   `keyboardType` (`.decimalPad` for quantities, `.numberPad` for barcodes), `submitLabel` and
   `.onSubmit` to validate. Food quantities use the in-sheet numeric keypad (no system keyboard,
   instant). Pressing return/validate does the main action. Never make the user dismiss a keyboard
   to reach the main button: keep it above the keyboard (`safeAreaInset(edge: .bottom)`).
3. Speed: every add flow is reachable in one tap ("+" tab, floating search bar, per-hour "+").

## Tokens (`Shared/Theme.swift`)
| token | value | use |
|---|---|---|
| background | #0F0F11 | every screen |
| raised (card) | #232326 | cards, sheets, fields; cards use `.themedCard()` (gradient #26262A→#212124, white 4.5 % border, radius 16) |
| raised2 | #2E2E32 | round buttons, chips, keypad keys, icon tiles on cards |
| separator / separatorStrong / track | #2A2A2E / #38383D / #2C2C31 | hairlines / inputs / ring & bar tracks |
| textPrimary / textBody / textSecondary / textTertiary / textQuaternary | #FAFAFA / #D4D4D8 / #A1A1AA / #71717A / #52525B | |
| calories | #6EA4F7 | kcal (gradient #9CC2FF→#4F86EC on rings) |
| carbs / protein / fat | #5FBF8F / #F28C6B / #F5C95A | macro data only |
| flame / expenditure | #F97316 | kcal flame, expenditure charts |
| weight | #C4B5FD | weight & trend |
| good / overTarget | #6FCF97 / #E45A5A | goal progress / over target |

Primary buttons and the "+" tab: white fill (`accent`) with near-black content (`onAccent`).
Selected chip/segment: white fill, black text. Numbers always `.monospacedDigit()`.

## Navigation
Tabs: **Accueil · Journal · + · Programme · Profil**. "+" opens the shortcuts sheet
(Scanner, Rechercher, Rapide, Recettes, then Pesée, Eau). Accueil, Journal and Programme
show a floating "Rechercher un aliment" bar above the tab bar (`AddSearchBar`), which opens
the add sheet in search mode with the keyboard up. All adding goes through
`appState.presentAdd(_:context:)` → `AddFlowView`.

## Screens (see mockups for layout)
- **Accueil**: title + date; calorie ring (thin 6 pt gradient arc, inner tick ring, white end dot,
  center "RESTANT / 1 251 / sur 1 911 kcal", sides Mangé / Objectif); G/P/L bars; Mangé/Restant
  segmented control. Sections of 2-column cards (`.themedCard()`): Tendances (Dépense, Poids
  tendance, Objectif, Bilan énergétique), Nutrition du jour, Mesures, Régularité (30-day grids).
- **Journal**: title + date + calendar/menu buttons; remaining header (kcal, G, P, L with bars);
  hourly timeline: hour pills on a vertical line at the right, per-hour totals (kcal, G, P, L chips)
  and a round "+", food cards (icon tile, name, "kcal · G · P · L · qty", round edit button),
  empty hours show only "+" and the pill, current hour pill outlined in calories blue.
- **Remaining header** (`DayRemainingView`): what is left for the day (kcal, G, P, L + bars) stays
  in view on every screen that adds or edits a food: add sheet header, quantity screen opened as
  a sheet (close button + remaining, replaces the nav bar), food detail (one row under the title).
  It previews the quantity being typed: values already count it and the part of each bar it
  uses is drawn lighter (an edited entry's old values are given back first).
- **Add sheet**: header (close, time chip, remaining kcal/G/P/L mini bars); mode tabs
  Scanner / Rechercher / Rapide / Recettes; search shows Favoris, "Souvent à 9 h", Récents with
  multi-select and a bottom "Ajouter (n)" button. Food detail: kcal + G/P/L with % of energy,
  Favori / Créer un aliment perso, "Part de la journée" mini rings, quantity field + unit chips +
  numeric keypad with "Ajouter et continuer" / "Ajouter". Quick add: kcal (focused) + G/P/L fields,
  macro-sum check, optional name.
- **Programme**: check-in countdown (7-segment ring for the week, thin outer goal ring), current
  program card (7 day columns: kcal chip + stacked G/P/L blocks), goal card (poids visé, kg/sem,
  %/sem), goal history, exception periods, check-in history.
- **Bilan de la semaine**: expenditure + change + chart, week summary (trend, real vs target rate,
  average intake), new program (old → new, G/P/L), −/+ adjust (collaborative), Plus tard / Appliquer.

## Food icons
Fluent Emoji Flat (MIT, bundled in the asset catalog, license shown in About) when a generic
match exists; otherwise the OpenNutrition illustration (CDN, `<name>@4x.webp`); otherwise the
generic fallback. Icons sit on a `raised2` rounded tile.
