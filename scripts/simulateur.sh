#!/usr/bin/env bash
# Rend l'identifiant d'un simulateur d'iPhone disponible, sur le runtime iOS le plus récent (jamais un modèle deviné :
# les modèles installés changent avec les images des runners et les versions de Xcode).
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
d = json.load(sys.stdin)["devices"]
def version(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
runtimes = sorted((rt for rt in d if "iOS" in rt and d[rt]), key=version, reverse=True)
for rt in runtimes:
    iphones = [x for x in d[rt] if x.get("isAvailable") and x["name"].startswith("iPhone")]
    # de préférence un « Pro » (ProMotion, Dynamic Island), sinon le premier iPhone
    iphones.sort(key=lambda x: (" Pro" not in x["name"], "Max" in x["name"], x["name"]))
    if iphones:
        print(iphones[0]["udid"]); sys.exit(0)
sys.exit("aucun simulateur d iPhone disponible")
'
