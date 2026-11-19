# Assiette — design spec "Minimal pro" (validated 2026-11-19)

Reference mockup: `design/v5/proposal-05.html` (phone 1 = Journal, phone 2 = Ajouter un aliment).
OpenNutrition-inspired (opennutrition.app) × MacroFactor density. Always dark.

## Principles
- **Monochrome UI**: zinc greys on near-black. **Only the macro colors carry color**
  (+ the small orange flame before kcal, + red when over target). No blue accent.
- **Hairlines instead of cards**: 1 px `Theme.separator` lines between rows/groups. Cards only
  where unavoidable (sheets, input fields) with `Theme.raised`, radius 8, 1 px `separatorStrong` border.
- **DM Sans** everywhere (`Theme.font(size, weight)`, presets `Theme.numberLarge/title/headline/body/callout/caption/label`).
  Numbers always `.monospacedDigit()` and right-aligned in a column.
- **Food icons** (OpenNutrition illustrations via `FoodIconView`) small (24–32 pt in lists, 56–64 in
  headers), full color, on a subtle tile.
- Controls: primary buttons and FAB = white fill (`Theme.accent`) with near-black content
  (`Theme.onAccent`). Secondary = text button in `textPrimary` / outline `separatorStrong`.
  Selected chip = white fill + black text; unselected = outline + `textSecondary`.
- kcal is shown with `KcalLabel` (orange flame + "105 kcal") in lists and search results.

## Tokens (Shared/Theme.swift)
| token | value | use |
|---|---|---|
| background | #050505 | every screen |
| raised | #0F0F11 | sheets, fields, rare cards |
| separator / separatorStrong | #1F1F23 / #2C2C31 | hairlines / inputs, chips, dashed rows |
| textPrimary / textBody | #FAFAFA / #D4D4D8 | titles, values / row text |
| textSecondary / textTertiary / textQuaternary | #A1A1AA / #71717A / #52525B | labels, quantities, times, disabled |
| calories / protein / carbs / fat | #4EC2B8 / #A1B0E8 / #F3BC52 / #E08B92 | macro data only |
| flame / overTarget | #F97316 / #E45A5A | kcal flame / over target |

## Journal
1. Nav: large title "Journal" + small date line; day chevrons; "…" menu.
2. **Pinned header**: 4 columns Kcal / Prot. / Gluc. / Lip. — tiny uppercase label in the macro color,
   big remaining number (numberLarge, textPrimary), 2 pt bar (macro color on separatorStrong), "sur 2 200"
   in textTertiary. Hairline below. Tap toggles remaining ↔ consumed.
3. **Timeline**: fixed left time column (textTertiary, 36 pt), rows: small icon, name (textBody) +
   quantity (textTertiary), kcal right column (monospaced). Group footer: P/G/L in their colors +
   group kcal. Groups separated by hairlines, no cards. "Maintenant" row: dashed outline + "+ Ajouter".
4. FAB: white circle, black "+".

## Ajouter un aliment (search)
Search field: raised fill, 1 px separatorStrong border, radius 8, white text. Chips row (Tout / Récents /
Favoris / Plats…). Result rows separated by hairlines: icon tile 32 pt, name with the typed part in
textPrimary bold and the rest textBody, second line `KcalLabel` • portion in textTertiary, trailing
"+" circle button outlined. Results count line in textTertiary.

## Everything else
Same rules: Lists with `.themedBackground()`, `.listRowBackground(Theme.background)`,
`.listRowSeparatorTint(Theme.separator)`; section headers = `Theme.label` uppercase textTertiary.
Charts: lines/bars in macro colors, axes textTertiary, grid separator.
