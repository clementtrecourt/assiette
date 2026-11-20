#!/usr/bin/env python3
"""Write the AltStore-format source (source.json) that Feather and the app's update banner read.

Usage: make_source.py <ipa> <version> <build> <notes> <repo> <out>
  repo: owner/name on GitHub; the IPA and the source live in its `latest` release.
"""
import json
import os
import sys
from datetime import datetime, timezone


def main() -> None:
    ipa, version, build, notes, repo, out = sys.argv[1:7]
    base = f"https://github.com/{repo}/releases/download/latest"
    icon = f"https://raw.githubusercontent.com/{repo}/main/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    size = os.path.getsize(ipa)
    download = f"{base}/Assiette.ipa"
    description = "Suivi nutritionnel personnel, hors ligne, sur les données OpenNutrition."

    source = {
        "name": "Assiette",
        "identifier": "app.assiette.source",
        "sourceURL": f"{base}/source.json",
        "iconURL": icon,
        "website": f"https://github.com/{repo}",
        "apps": [
            {
                "name": "Assiette",
                "bundleIdentifier": "app.assiette.ios",
                "developerName": "Assiette",
                "subtitle": "Suivi nutritionnel",
                "localizedDescription": description,
                "iconURL": icon,
                "tintColor": "689FFA",
                "category": "lifestyle",
                "versions": [
                    {
                        "version": version,
                        "buildVersion": build,
                        "date": date,
                        "localizedDescription": notes,
                        "downloadURL": download,
                        "size": size,
                        "minOSVersion": "17.0",
                    }
                ],
                "version": version,
                "versionDate": date,
                "versionDescription": notes,
                "downloadURL": download,
                "size": size,
                "appPermissions": {},
                "screenshotURLs": [],
            }
        ],
        "news": [],
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(source, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
