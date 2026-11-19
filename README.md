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
- **Export** CSV du journal, sauvegarde / restauration JSON.

Toutes les données personnelles restent sur l'appareil (SwiftData).

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
