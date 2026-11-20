"""Convert the text dump of a MacroFactor .xlsx export into one daily CSV.

Usage: python3 -I parse_export.py <export.txt> <out.csv>
"""
import csv, sys, datetime as dt

SHEETS = {
    "Calories & Macros": {"Calories (kcal)": "kcal", "Fat (g)": "fat", "Carbs (g)": "carbs", "Protein (g)": "protein"},
    "Scale Weight": {"Weight (kg)": "weight", "Fat Percent": "bodyfat"},
    "Weight Trend": {"Trend Weight (kg)": "trend"},
    "Expenditure": {"Expenditure": "expenditure"},
    "Steps": {"Steps": "steps"},
}

def to_date(cell):
    cell = cell.split(" [")[0]
    if "/" in cell:
        return dt.datetime.strptime(cell, "%d/%m/%Y").date()
    return dt.date(1899, 12, 30) + dt.timedelta(days=int(float(cell)))

def main(src, dst):
    days, sheet, header = {}, None, None
    for line in open(src, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("## Sheet: "):
            sheet, header = line[10:], None
            continue
        if sheet not in SHEETS or not line.strip():
            continue
        cells = line.split("\t")
        if header is None:
            header = cells
            continue
        day = days.setdefault(to_date(cells[0]), {})
        for name, value in zip(header[1:], cells[1:]):
            key = SHEETS[sheet].get(name)
            if key and value != "":
                day[key] = float(value)
    cols = ["date", "kcal", "protein", "fat", "carbs", "weight", "bodyfat", "trend", "expenditure", "steps"]
    with open(dst, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for d in sorted(days):
            w.writerow([d.isoformat()] + [days[d].get(c, "") for c in cols[1:]])
    print(f"{len(days)} days, {min(days)} -> {max(days)}")
    write_checkins(src, dst.rsplit("/", 1)[0] + "/checkins.csv", days)

GOALS = {"Weight Loss": "lose", "Maintenance": "maintain", "Weight Gain": "gain"}

def sheet_rows(src, name):
    text = open(src, encoding="utf-8").read().split("## Sheet: " + name + "\n")[1].split("## Sheet: ")[0]
    return [l.split("\t") for l in text.strip().splitlines()[1:]]

def write_checkins(src, dst, days):
    """One row per program update: goal in force, MacroFactor's expenditure, weight and target."""
    goals = []
    for g in sheet_rows(src, "Weight Goals"):
        end = to_date(g[3]) if g[3] else dt.date.max
        goals.append((GOALS[g[0]], to_date(g[2]), end, float(g[4]), float(g[5])))
    seen, out = set(), []
    for c in sheet_rows(src, "Nutrition Program Settings"):
        if c[0] in seen:
            continue
        seen.add(c[0])
        day, target = to_date(c[0]), float(c[7] or 0)
        active = [g for g in goals if g[1] <= day < g[2]] or [g for g in goals if g[1] <= day <= g[2]]
        goal = active[-1] if active and target else None
        trend = days.get(day, {}).get("trend", "")
        out.append([day.isoformat(), goal[0] if goal else "manual", goal[4] if goal else "",
                    goal[3] if goal else "", c[6], c[8], trend, target or ""])
    with open(dst, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["date", "goal", "rate_percent", "goal_weight", "expenditure", "scale_weight", "trend", "target"])
        w.writerows(out)
    print(f"{len(out)} check-ins -> {dst}")

if __name__ == "__main__":
    main(*sys.argv[1:3])
