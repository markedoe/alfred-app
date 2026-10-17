#!/usr/bin/env bash
# Rend l'identifiant d'un simulateur disponible, sur le runtime iOS le plus récent (jamais un modèle deviné : les
# modèles installés changent avec les images des runners et les versions de Xcode).
#
#   scripts/simulateur.sh          un iPhone (de préférence un « Pro » : ProMotion, Dynamic Island)
#   scripts/simulateur.sh ipad     un iPad (de préférence le plus grand « Pro » : la disposition large à l'horizontale)
set -euo pipefail
xcrun simctl list devices available -j | GENRE="${1:-iphone}" python3 -c '
import json, os, re, sys
d = json.load(sys.stdin)["devices"]
ipad = os.environ["GENRE"] == "ipad"
def version(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
runtimes = sorted((rt for rt in d if "iOS" in rt and d[rt]), key=version, reverse=True)
for rt in runtimes:
    prefixe = "iPad" if ipad else "iPhone"
    appareils = [x for x in d[rt] if x.get("isAvailable") and x["name"].startswith(prefixe)]
    if ipad:
        appareils.sort(key=lambda x: (" Pro" not in x["name"], "13" not in x["name"], x["name"]))
    else:
        appareils.sort(key=lambda x: (" Pro" not in x["name"], "Max" in x["name"], x["name"]))
    if appareils:
        print(appareils[0]["udid"]); sys.exit(0)
sys.exit("aucun simulateur disponible")
'
