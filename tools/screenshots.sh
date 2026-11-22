#!/usr/bin/env bash
# Boot a simulator, install the Debug simulator build, launch each screen in demo mode and
# capture screenshots into build/screenshots. Usage: tools/screenshots.sh <sim-udid> <Assiette.app>
set -euo pipefail
SIM="$1"; APP="$2"; OUT=build/screenshots; BID=app.assiette.ios
mkdir -p "$OUT"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b
xcrun simctl ui "$SIM" appearance dark || true
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$SIM" "$APP"
shot() { # name, args...
  local name="$1"; shift
  xcrun simctl terminate "$SIM" "$BID" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$BID" -demo "$@" >/dev/null
  sleep "${WAIT:-6}"
  xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name.png" >/dev/null
  echo "captured $name"
}
WAIT=12 shot 01-journal -startTab today        # first launch seeds demo data
shot 02-recherche -startTab today -startSheet search
shot 03-fiche-aliment -startTab today -startSheet detail
shot 04-ajout-quantite -startTab today -startSheet add
shot 04b-ajout-quantite-panneau -startTab today -startSheet addflow-entry
shot 05-ajout-rapide -startTab today -startSheet quickadd
shot 06-scanner -startTab today -startSheet scan
shot 07-accueil -startTab progress
shot 07a-depense -startTab progress -startRoute expenditure
shot 07b-poids-tendance -startTab progress -startRoute weight
shot 07c-objectif -startTab progress -startRoute goal
shot 07d-bilan -startTab progress -startRoute balance
shot 09-programme -startTab program
shot 08-profil -startTab profile
shot 10-programme-regime -startTab program -startSheet wizard
shot 11-mise-a-jour -startTab progress -updateBanner
shot 11-programme-pret -startTab program -startSheet wizard-summary
shot 12-objectif-intro -startTab program -startSheet goal-new
shot 13-objectif-rythme -startTab program -startSheet goal-rate
xcrun simctl uninstall "$SIM" "$BID"
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" "$BID" >/dev/null; sleep 6
xcrun simctl io "$SIM" screenshot --type=png "$OUT/00-accueil.png" >/dev/null; echo "captured onboarding"
ls -la "$OUT"
