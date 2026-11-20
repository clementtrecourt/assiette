#!/usr/bin/env python3
"""Build the compact, read-only SQLite food database bundled in the iOS app.

Usage: python3 -I tools/build_db.py <opennutrition_foods.tsv> <out.sqlite>

Data: OpenNutrition dataset (ODbL) - https://www.opennutrition.app
The resulting database is a Derivative Database and remains under ODbL.
"""
import csv
import importlib.util
import json
import os
import re
import sqlite3
import sys

csv.field_size_limit(10**9)

# Nutrients stored per 100 g (or 100 ml). Order == column order. Keep in sync with
# App/Sources/Core/Nutrients.swift (NutrientKey raw values are these column names).
NUTRIENTS = [
    "calories", "protein", "carbohydrates", "total_fat", "saturated_fats",
    "monounsaturated_fats", "polyunsaturated_fats", "trans_fats", "cholesterol",
    "dietary_fiber", "total_sugars", "added_sugars", "sodium", "potassium",
    "calcium", "iron", "magnesium", "zinc", "phosphorus", "vitamin_a",
    "vitamin_c", "vitamin_d", "vitamin_e", "vitamin_k", "thiamin", "riboflavin",
    "niacin", "vitamin_b6", "folate_dfe", "vitamin_b12", "omega_3", "caffeine",
    "ethyl_alcohol", "water",
]
TYPES = {"everyday": 0, "prepared": 1, "restaurant": 2, "grocery": 3}
BY_RE = re.compile(r"^(.*) by (.+)$")
WORD_RE = re.compile(r"[a-z0-9]+")
ICONS_TSV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "icons.tsv")
MAP_FLUENT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "map_fluent.py")


def load_fluent_matcher(path=MAP_FLUENT):
    """`match(name) -> snake name | None` from tools/map_fluent.py (loaded by path: `python3 -I`
    does not put the script directory on sys.path). None if the file is missing."""
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("map_fluent", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.match


def load_icons(path=ICONS_TSV):
    """ext_id -> icon basename, from the crawler output (tools/map_icons.py). {} if absent."""
    icons = {}
    if not os.path.exists(path):
        return icons
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[0] and parts[1].strip():
                icons[parts[0].strip()] = parts[1].strip()
    return icons


def norm_word(w):
    """Crude singular form, applied identically to keys and names (only consistency matters):
    eggs -> egg, tomatoes -> tomato, peaches -> peach, berries/berry -> berry,
    cookies/cookie -> cooky."""
    if len(w) > 4 and (w.endswith("oes") or w.endswith("ches") or w.endswith("shes")):
        w = w[:-2]
    elif len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
        w = w[:-1]
    if len(w) > 2 and w.endswith("ie"):
        w = w[:-2] + "y"
    return w


def name_words(name):
    m = BY_RE.match(name)
    if m:
        name = m.group(1)
    return [norm_word(w) for w in WORD_RE.findall(name.lower())]


def assign_fallback_icons(db):
    """Give foods without an icon the icon of the best-matching short generic food name."""
    index = {}  # "white rice" -> icon
    rows = db.execute("SELECT name, icon FROM food WHERE icon IS NOT NULL AND type IN (0, 1) ORDER BY id")
    for name, icon in rows:
        words = name_words(name)
        if not 1 <= len(words) <= 3:
            continue
        key = " ".join(words)
        # Prefer the canonical illustrations ("white_rice_3iVYQH") over per-food ones ("fd_...").
        if key not in index or (index[key].startswith("fd_") and not icon.startswith("fd_")):
            index[key] = icon
    updates = []
    misses = db.execute("SELECT id, name FROM food WHERE icon IS NULL").fetchall()
    for food_id, name in misses:
        words = name_words(name)
        found = None
        for size in (3, 2, 1):
            # Rightmost n-gram first: English head nouns come last ("chocolate chip cookie").
            for start in range(len(words) - size, -1, -1):
                icon = index.get(" ".join(words[start:start + size]))
                if icon:
                    found = icon
                    break
            if found:
                break
        if found:
            updates.append((found, food_id))
    db.executemany("UPDATE food SET icon = ? WHERE id = ?", updates)
    return len(index), len(misses), len(updates)


def num(v):
    if v is None or v == "":
        return None
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return round(f, 4)


def main(src, dst):
    if os.path.exists(dst):
        os.remove(dst)
    db = sqlite3.connect(dst)
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("PRAGMA synchronous=OFF")
    cols = ", ".join(f"{n} REAL" for n in NUTRIENTS)
    db.execute(f"""CREATE TABLE food(
        id INTEGER PRIMARY KEY,
        ext_id TEXT NOT NULL,
        name TEXT NOT NULL,
        brand TEXT,
        type INTEGER NOT NULL,
        ean TEXT,
        serving_unit TEXT,
        serving_qty REAL,
        serving_g REAL,
        is_liquid INTEGER NOT NULL DEFAULT 0,
        package_g REAL,
        {cols},
        icon TEXT,
        fluent TEXT)""")
    db.execute("""CREATE VIRTUAL TABLE food_fts USING fts5(
        name, alt, content='', columnsize=0,
        tokenize='unicode61 remove_diacritics 2', prefix='2 3')""")
    db.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)")

    # Localized names for staple foods with a known preparation state.
    french_names = {
        "fd_VoAECiJlRO4t": "Riz basmati cru",
        "fd_rhmHl8WBly89": "Riz complet cru",
        "fd_gbtVB7G9twmc": "Riz cuit",
        "fd_ScotusF79jyh": "Poulet cru, entier découpé",
        "fd_57Ne2bwpolgJ": "Poulet cuit, entier",
        "fd_z3bVu8Loyy6a": "Blanc de poulet cuit, grillé",
        "fd_8P5faGPYoPZ1": "Pâtes crues, spaghetti",
        "fd_r3FR60zh9Wz4": "Quinoa cru",
        "fd_zkscDlk1dkn8": "Couscous cru",
    }
    icons = load_icons()
    fluent_match = load_fluent_matcher()
    placeholders = ",".join("?" * (13 + len(NUTRIENTS)))
    n = 0
    exact = 0
    fluent_count = 0
    with open(src, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            try:
                nut = json.loads(row["nutrition_100g"] or "{}")
            except json.JSONDecodeError:
                continue
            if nut.get("calories") is None:
                continue
            n += 1
            name = row["name"].strip()
            brand = None
            t = TYPES.get(row["type"], 3)
            if t >= 2:
                m = BY_RE.match(name)
                if m:
                    brand = m.group(2).strip()
            try:
                s = json.loads(row["serving"] or "{}")
            except json.JSONDecodeError:
                s = {}
            common = s.get("common") or {}
            metric = s.get("metric") or {}
            is_liquid = 1 if metric.get("unit") == "ml" else 0
            try:
                p = json.loads(row["package_size"] or "{}")
            except json.JSONDecodeError:
                p = {}
            pkg = num((p.get("metric") or {}).get("quantity"))
            try:
                alt = " ".join(json.loads(row["alternate_names"] or "[]"))
            except json.JSONDecodeError:
                alt = ""
            icon = icons.get(row["id"])
            if icon:
                exact += 1
            # Bundled Fluent Emoji (App/Resources/Assets.xcassets/FoodEmoji/<fluent>), shown
            # before the OpenNutrition illustration when the name is a clear generic match.
            fluent = fluent_match(name) if fluent_match else None
            if fluent:
                fluent_count += 1
            if localized := french_names.get(row["id"]):
                alt = f"{name} {alt}"
                name = localized
            db.execute(
                f"INSERT INTO food VALUES({placeholders})",
                (n, row["id"], name, brand, t, row["ean_13"] or None,
                 common.get("unit"), num(common.get("quantity")),
                 num(metric.get("quantity")), is_liquid, pkg,
                 *[num(nut.get(k)) for k in NUTRIENTS], icon, fluent),
            )
            db.execute("INSERT INTO food_fts(rowid, name, alt) VALUES(?,?,?)", (n, name, alt))
    if icons:
        keys, missing, matched = assign_fallback_icons(db)
        total = exact + matched
        print(f"icons: {len(icons)} mapped, {exact} exact, {matched}/{missing} fallback "
              f"({keys} keys) -> {total}/{n} foods ({100 * total / max(n, 1):.1f} %)")
        for t_name, t in TYPES.items():
            c, w = db.execute("SELECT count(*), count(icon) FROM food WHERE type = ?", (t,)).fetchone()
            print(f"  {t_name:10s} {w}/{c} ({100 * w / max(c, 1):.1f} %)")
    else:
        print(f"icons: {ICONS_TSV} not found, icon column left NULL")
    if fluent_match:
        print(f"fluent: {fluent_count}/{n} foods ({100 * fluent_count / max(n, 1):.1f} %)")
    else:
        print(f"fluent: {MAP_FLUENT} not found, fluent column left NULL")
    db.execute("CREATE INDEX ix_food_ean ON food(ean) WHERE ean IS NOT NULL")
    db.execute("INSERT INTO food_fts(food_fts) VALUES('optimize')")
    db.executemany("INSERT INTO meta VALUES(?,?)", [
        ("dataset", "OpenNutrition 2025.1"),
        ("license", "ODbL 1.0"),
        ("count", str(n)),
        ("schema", "3"),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{n} foods -> {dst} ({os.path.getsize(dst) / 1e6:.1f} MB)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
