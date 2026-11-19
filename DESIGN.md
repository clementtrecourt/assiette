# Assiette — design spec (validated by the user, 2026-11-19)

Mockups: `design/directions-v2.html` (header #02), `design/directions-v3.html` (log #02),
`design/directions-v4.html` (theme #02 "Graphite" with background of #04).
Inspiration: MacroFactor — flat, data-dense, one color per macro, numbers first.

## Theme — always dark

App forces dark mode: `.preferredColorScheme(.dark)` at the root.

| Token | Hex | Use |
|---|---|---|
| background | `#0A0A0A` | every screen background (lists too: `.scrollContentBackground(.hidden)` + this) |
| card | `#2C2C2E` | cards, grouped rows, timeline blocks, pills |
| separator | `#2C2C2E` / hairline `#3A3A3C` | dividers |
| text | `#F2F2F7` | primary |
| secondary text | `#98989F` | labels, quantities, units |
| accent | `#0A84FF` | buttons, FAB, selected tab, links, "Maintenant" dot |
| calories | `#E5E5EA` | kcal bar |
| protein | `#FF6482` | |
| carbs | `#5EB1FF` | |
| fat | `#FFC94D` | |
| fiber | `#4CD38A` | |
| water | `#40C8E0` | |
| over target | `#FF453A` | bar turns red when > 105 % |

Typography: system SF. Big numbers `.system(size: 22, weight: .bold, design: .default)` +
`.monospacedDigit()`. Labels `.caption2`/`.caption` secondary. No serif, no rounded design.
Corner radius 12 (cards), 999 (pills), bars 3. No shadows (dark), separation by card color.

## Journal screen (TodayView)

1. **Day bar**: `‹  Aujourd'hui  ›` (title tappable → date picker; swipe left/right changes day).
2. **Header, pinned (stays visible while scrolling)** — 4 equal columns: Kcal, Prot., Gluc., Lip.
   Each column: small label (secondary), **remaining** value big (bold, monospaced digits),
   thin 4–6 pt progress bar in the macro color (consumed/target), "sur 2 200" caption.
   Tap header → toggle remaining ↔ consumed.
3. **Log = timeline (no meal boxes in the UI)**: vertical line on the left with time labels
   (`7:45`), a dot per group; entries logged within the same ~30 min are grouped into one
   card (`#2C2C2E`): each row "Name  qty(secondary)  kcal(right)", then a footer row with
   P/G/L colored dots + group total kcal. Last item: accent dot "Maintenant : + Ajouter"
   dashed card.
   (Meals still exist in the data model — the meal is inferred from the time and shown as a
   small secondary label on the group, e.g. "Déjeuner", and remains editable in AddEntrySheet.)
4. **FAB** bottom-right, accent circle "+", opens a menu: Rechercher, Scanner un code-barres,
   Ajout rapide. Tabs: Journal · Progrès · Profil (search is reached via the FAB, not a tab —
   keep the "Ajouter" tab only if trivial; preferred: 3 tabs + FAB).
5. Water and micronutrients: compact rows below the timeline (not above the header).

## Everywhere else

Same tokens. Lists/forms: dark background `#0A0A0A`, rows `#2C2C2E`. Macro values always
shown with their color dot. Numbers French-formatted (`Formatters`). Search results rows:
name, brand/qty secondary, kcal right + P/G/L dots row (same as timeline rows).
