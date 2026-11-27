# Assiette

Application iOS personnelle de suivi nutritionnel (SwiftUI, iOS 17+), entièrement hors ligne,
construite sur la base de données ouverte [OpenNutrition](https://www.opennutrition.app)
(~327 000 aliments : génériques, plats, restaurants US, produits de marque avec code-barres).

## Fonctionnalités

- **Journal** par jour et par repas, anneau de calories, barres protéines / glucides / lipides, eau.
- **Recherche** instantanée hors ligne (plein texte, en français ou en anglais : `poulet` trouve `chicken`).
- **Fiche aliment** : macros, ~30 micronutriments, % des apports de référence, par portion ou pour 100 g.
- **Scan de code-barres** (VisionKit) : base locale, puis Open Food Facts en ligne si le produit est inconnu.
- **Ajout rapide**, favoris, récents, copie d'un repas de la veille.
- **Mes aliments & recettes** personnalisés.
- **Objectifs** calculés (Mifflin-St Jeor + niveau d'activité + objectif de poids) ou manuels.
- **Progrès** : poids (moyenne mobile), calories et macros sur 7 / 30 / 90 jours.
- **Objectifs par jour** : un objectif kcal fixe par jour de la semaine (ex. 1 500 le lundi, 2 000 le mardi),
  par-dessus le programme (Programme › Objectifs par jour).
- **Export** CSV du journal, sauvegarde / restauration JSON.
- **Synchronisation serveur** (optionnelle) : bilan 28 jours et, si activée, archive complète vers ton serveur.

Les données personnelles restent sur l'appareil (SwiftData), sauf si tu actives la synchronisation serveur.

## Synchronisation serveur

`tools/nutrition-sync/receiver.py` (HTTPS, clés d'écriture et de lecture distinctes) reçoit :

- `PUT /api/nutrition/snapshot` : bilan des 28 derniers jours, lu par `weekly_summary.py` (seule route en lecture) ;
- `PUT /api/nutrition/archive` : sauvegarde complète (même format que l'export JSON), jamais servie en HTTP.

Sur le serveur, un agent (Claude, Codex) lit et écrit **toutes** les données en local avec `archive.py`
(pas de clé réseau ; rien ne peut écrire depuis le réseau) :

```sh
archive.py export > a.json          # tout : journal, pesées, Santé, eau, recettes, favoris, profil, objectifs,
                                    # programme, objectifs par jour, réglages ; la révision s'affiche sur stderr
archive.py replace a.json --revision N   # l'iPhone remplace toutes ses données par a.json (modifié)
archive.py set 1 1500               # raccourci : lundi = 1 500 kcal (1 lundi … 7 dimanche, 800 à 10 000)
archive.py clear 7                  # dimanche : revient au programme
archive.py pending | log            # en attente / résultats (applied, conflict, invalid)
archive.py history                  # versions gardées (une par jour, et avant chaque remplacement)
archive.py export --history ID      # récupérer une ancienne version (puis `replace` pour revenir en arrière)
archive.py cancel                   # annuler ce que l'iPhone n'a pas encore reçu
```

Les commandes partent dans la réponse au prochain envoi de l'iPhone, qui les applique puis les confirme.
Un `replace` n'est appliqué que si l'iPhone n'a rien changé depuis la révision `N` ; sinon il finit en
`conflict`, rien n'est touché, et il suffit de réexporter et de refaire la modification. Les dates doivent
garder le format `2026-11-27T08:30:00Z`.

## Installer

1. Télécharger `Assiette.ipa` depuis la [release `latest`](../../releases/tag/latest)
   (ou l'artefact du dernier run GitHub Actions).
2. L'IPA **n'est pas signé** : le signer et l'installer avec l'outil de ton choix
   (Sideloadly, AltStore / SideStore, ESign, `zsign`…), avec ton identifiant Apple ou ton certificat.

## Build

Pas besoin de Mac en local : `.github/workflows/build.yml` tourne sur `macos-15` :

1. télécharge le dataset OpenNutrition et vérifie son SHA-256 ;
2. `tools/build_db.py` le convertit en SQLite compacte avec index FTS5 (`App/Resources/foods.sqlite`, ~93 Mo) ;
3. `xcodegen` génère le projet depuis `project.yml` ;
4. lance les tests unitaires sur simulateur ;
5. compile en Release sans signature et empaquette `Assiette.ipa`.

Sur un Mac : `python3 tools/build_db.py <opennutrition_foods.tsv> App/Resources/foods.sqlite && xcodegen && open Assiette.xcodeproj`.

Voir [ARCHITECTURE.md](ARCHITECTURE.md) pour l'organisation du code.

## Licences et attribution

- Données : **OpenNutrition**, sous licence [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) —
  https://www.opennutrition.app. La base SQLite dérivée reste sous ODbL.
- Certaines données proviennent d'Open Food Facts : « © Open Food Facts contributors » —
  https://world.openfoodfacts.org (ODbL).
- Application sans lien avec OpenNutrition ni Open Food Facts.
