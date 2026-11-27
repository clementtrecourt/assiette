#!/usr/bin/env python3
"""Weekly nutrition summary for the Sunday openGym job, from the Assiette snapshot.

Usage:
  weekly_summary.py                      # fetch with ~/.config/nutrition-sync/reader.curl
  weekly_summary.py --file report.json   # read a saved snapshot
  options: --week-end YYYY-MM-DD (default: the latest Sunday on or before today), --json

Prints French Markdown (or JSON) and never prints credentials. Exit code 0 even when the
snapshot is missing or stale: the job reports it and carries on with openGym.
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from statistics import mean
from zoneinfo import ZoneInfo

READER = os.path.expanduser("~/.config/nutrition-sync/reader.curl")
MACROS = (("kcal", "kcal"), ("proteinG", "protéines"), ("carbsG", "glucides"), ("fatG", "lipides"))
STALE_HOURS = 36


def fetch():
    """Returns (report or None, problem or None)."""
    if not os.path.exists(READER):
        return None, "configuration du lecteur absente"
    proc = subprocess.run(["curl", "--silent", "--show-error", "--max-time", "8", "--config", READER,
                           "--write-out", "\n%{http_code}"], capture_output=True, text=True)
    if proc.returncode != 0:
        return None, f"serveur injoignable (curl {proc.returncode})"
    body, _, code = proc.stdout.rpartition("\n")
    if code == "404":
        return None, "aucun relevé reçu de l’iPhone pour l’instant"
    if code != "200":
        return None, f"réponse HTTP {code}"
    return json.loads(body), None


def week_stats(days, start, end):
    week = [d for d in days if start <= d["date"] <= end]
    usable = [d for d in week if d["status"] == "logged" and d.get("intake")]
    intake = {}
    for key, _ in MACROS:
        values = [d["intake"][key] for d in usable if d["intake"].get(key) is not None]
        intake[key] = round(mean(values)) if values else None
    matched = [d for d in usable if d.get("targets") and d["targets"].get("kcal")]
    targets, adherence = {}, {}
    for key, _ in MACROS:
        pairs = [(d["intake"][key], d["targets"][key]) for d in matched
                 if d["intake"].get(key) is not None and d["targets"].get(key)]
        targets[key] = round(mean(t for _, t in pairs)) if pairs else None
        adherence[key] = round(100 * sum(i for i, _ in pairs) / sum(t for _, t in pairs)) if pairs else None
    trend = [d for d in week if d.get("trendKg") is not None]
    expenditure = [d["expenditureKcal"] for d in week if d.get("expenditureKcal") is not None]
    return {
        "start": start, "end": end,
        "days": len(week),
        "logged": len(usable),
        "fromHealth": sum(1 for d in usable if d.get("source") == "health"),
        "missing": [d["date"] for d in week if d["status"] == "missing"],
        "excluded": [d["date"] for d in week if d["status"] == "excluded"],
        "inProgress": [d["date"] for d in week if d["status"] == "in_progress"],
        "weighIns": sum(1 for d in week if d.get("weightKg") is not None),
        "intake": intake,
        "targets": targets,
        "adherencePercent": adherence,
        "matchedDays": len(matched),
        "trendEndKg": round(trend[-1]["trendKg"], 2) if trend else None,
        "expenditureKcal": round(expenditure[-1]) if expenditure else None,
    }


def summarize(report, week_end=None):
    zone = ZoneInfo(report.get("timeZone") or "Europe/Paris")
    today = dt.datetime.now(zone).date()
    if week_end is None:
        week_end = today - dt.timedelta(days=(today.weekday() + 1) % 7)  # latest Sunday
    start = week_end - dt.timedelta(days=6)
    days = sorted(report["days"], key=lambda d: d["date"])
    iso = dt.date.isoformat
    this = week_stats(days, iso(start), iso(week_end))
    prev = week_stats(days, iso(start - dt.timedelta(days=7)), iso(start - dt.timedelta(days=1)))
    generated = dt.datetime.fromisoformat(report["generatedAt"].replace("Z", "+00:00"))
    age_h = (dt.datetime.now(dt.timezone.utc) - generated).total_seconds() / 3600
    first, last = days[0]["date"], days[-1]["date"]
    change = None
    if this["trendEndKg"] is not None and prev["trendEndKg"] is not None:
        change = round(this["trendEndKg"] - prev["trendEndKg"], 2)
    flags = []
    if age_h > STALE_HOURS:
        flags.append(f"relevé ancien ({age_h:.0f} h)")
    if last < iso(week_end):
        flags.append(f"le relevé s’arrête au {last}, avant la fin de semaine")
    if this["logged"] < 4:
        flags.append(f"journal peu exploitable ({this['logged']} jours)")
    if this["weighIns"] < 3:
        flags.append(f"peu de pesées ({this['weighIns']})")
    return {
        "generatedAt": report["generatedAt"], "syncAgeHours": round(age_h, 1),
        "snapshotRange": [first, last], "goal": report.get("goal"),
        "week": this, "previousWeek": prev, "trendChangeKg": change, "flags": flags,
    }


def fmt(value, unit=""):
    return "—" if value is None else f"{value}{unit}"


def markdown(summary):
    w, p = summary["week"], summary["previousWeek"]
    goal = summary.get("goal") or {}
    kinds = {"lose": "perte", "maintain": "maintien", "gain": "prise"}
    lines = [f"**Nutrition Assiette · semaine du {w['start']} au {w['end']}**",
             f"Dernière synchro : {summary['generatedAt']} (il y a {summary['syncAgeHours']} h)."]
    if goal:
        lines.append(f"Objectif : {kinds.get(goal.get('kind'), goal.get('kind'))}, "
                     f"{goal.get('weeklyRatePercent', 0):.2f} %/sem"
                     + (f", cible {goal['targetWeightKg']} kg" if goal.get("targetWeightKg") else "") + ".")
    cover = f"Journal exploitable {w['logged']}/{w['days']} jours"
    if w["fromHealth"]:
        cover += f" (dont {w['fromHealth']} via Apple Santé)"
    if w["inProgress"]:
        cover += " · dimanche en cours, non compté"
    if w["excluded"]:
        cover += f" · {len(w['excluded'])} jour(s) exclu(s)"
    lines.append(cover + f" · {w['weighIns']} pesée(s).")
    lines += ["", "| | Moyenne semaine | Cible (jours appariés) | Écart | Sem. précédente |", "|---|---|---|---|---|"]
    for key, label in MACROS:
        unit = " kcal" if key == "kcal" else " g"
        mean_v, target = w["intake"][key], w["targets"][key]
        delta = None if mean_v is None or target is None else mean_v - target
        pct = w["adherencePercent"][key]
        lines.append(f"| {label} | {fmt(mean_v, unit)} | {fmt(target, unit)} | "
                     f"{'—' if delta is None else f'{delta:+d}{unit} ({pct} %)'} | {fmt(p['intake'][key], unit)} |")
    lines.append("")
    trend = f"Tendance poids : {fmt(w['trendEndKg'], ' kg')}"
    if summary["trendChangeKg"] is not None:
        trend += f" ({summary['trendChangeKg']:+.2f} kg vs semaine précédente)"
    lines.append(trend + f" · dépense estimée {fmt(w['expenditureKcal'], ' kcal/j')}.")
    if summary["flags"]:
        lines.append("⚠️ " + " ; ".join(summary["flags"]) + ".")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file")
    parser.add_argument("--week-end", type=dt.date.fromisoformat)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.file:
        with open(args.file) as f:
            report, problem = json.load(f), None
    else:
        report, problem = fetch()
    if report is None:
        print(json.dumps({"error": problem}) if args.json
              else f"**Nutrition Assiette** : indisponible ({problem}). Bilan openGym sans contexte nutrition.")
        return
    summary = summarize(report, args.week_end)
    print(json.dumps(summary, ensure_ascii=False, indent=2) if args.json else markdown(summary))


if __name__ == "__main__":
    sys.exit(main())
