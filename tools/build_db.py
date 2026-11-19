#!/usr/bin/env python3
"""Build the compact, read-only SQLite food database bundled in the iOS app.

Usage: python3 -I tools/build_db.py <opennutrition_foods.tsv> <out.sqlite>

Data: OpenNutrition dataset (ODbL) - https://www.opennutrition.app
The resulting database is a Derivative Database and remains under ODbL.
"""
import csv
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
        {cols})""")
    db.execute("""CREATE VIRTUAL TABLE food_fts USING fts5(
        name, alt, content='', columnsize=0,
        tokenize='unicode61 remove_diacritics 2', prefix='2 3')""")
    db.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)")

    placeholders = ",".join("?" * (11 + len(NUTRIENTS)))
    n = 0
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
            db.execute(
                f"INSERT INTO food VALUES({placeholders})",
                (n, row["id"], name, brand, t, row["ean_13"] or None,
                 common.get("unit"), num(common.get("quantity")),
                 num(metric.get("quantity")), is_liquid, pkg,
                 *[num(nut.get(k)) for k in NUTRIENTS]),
            )
            db.execute("INSERT INTO food_fts(rowid, name, alt) VALUES(?,?,?)", (n, name, alt))
    db.execute("CREATE INDEX ix_food_ean ON food(ean) WHERE ean IS NOT NULL")
    db.execute("INSERT INTO food_fts(food_fts) VALUES('optimize')")
    db.executemany("INSERT INTO meta VALUES(?,?)", [
        ("dataset", "OpenNutrition 2025.1"),
        ("license", "ODbL 1.0"),
        ("count", str(n)),
        ("schema", "1"),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"{n} foods -> {dst} ({os.path.getsize(dst) / 1e6:.1f} MB)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
