#!/usr/bin/env bash
# Rend l'identifiant d'un simulateur disponible, sur le runtime iOS le plus récent (jamais un modèle deviné : les
# modèles installés changent avec les images des runners et les versions de Xcode).
#
#   scripts/simulateur.sh          un iPhone (de préférence un « Pro » : ProMotion, Dynamic Island)
#   scripts/simulateur.sh ipad     un iPad (de préférence le plus grand « Pro » : la disposition large à l'horizontale)
#   scripts/simulateur.sh etroit   l'iPhone à l'écran le plus étroit, en points (lu dans le profil de son modèle) ;
#                                  échoue s'il n'est pas plus étroit que l'iPhone choisi par défaut
set -euo pipefail
modeles=$(xcrun simctl list devicetypes -j)
xcrun simctl list devices available -j | GENRE="${1:-iphone}" MODELES="$modeles" python3 -c '
import json, os, plistlib, re, sys
d = json.load(sys.stdin)["devices"]
genre = os.environ["GENRE"]
chemins = {t["identifier"]: t["bundlePath"] for t in json.loads(os.environ["MODELES"])["devicetypes"]}

def version(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

def largeur(x):
    """La largeur de l’écran en points (pixels / échelle), lue dans le profil du modèle."""
    chemin = os.path.join(chemins[x["deviceTypeIdentifier"]], "Contents", "Resources", "profile.plist")
    with open(chemin, "rb") as f:
        p = plistlib.load(f)
    if "mainScreenWidth" not in p or "mainScreenScale" not in p:
        sys.exit("%s : ni mainScreenWidth ni mainScreenScale (%s)" % (chemin, sorted(p)))
    return p["mainScreenWidth"] / p["mainScreenScale"]

def defaut(appareils):
    return sorted(appareils, key=lambda x: (" Pro" not in x["name"], "Max" in x["name"], x["name"]))[0]

runtimes = sorted((rt for rt in d if "iOS" in rt and d[rt]), key=version, reverse=True)
for rt in runtimes:
    prefixe = "iPad" if genre == "ipad" else "iPhone"
    appareils = [x for x in d[rt] if x.get("isAvailable") and x["name"].startswith(prefixe)]
    if not appareils:
        continue
    if genre == "ipad":
        choisi = sorted(appareils, key=lambda x: (" Pro" not in x["name"], "13" not in x["name"], x["name"]))[0]
    elif genre == "etroit":
        choisi, reference = min(appareils, key=largeur), defaut(appareils)
        print("%s : %g pt (par défaut, %s : %g pt)" % (choisi["name"], largeur(choisi), reference["name"],
              largeur(reference)), file=sys.stderr)
        if largeur(choisi) >= largeur(reference):
            sys.exit("aucun iPhone plus étroit que celui choisi par défaut")
    else:
        choisi = defaut(appareils)
    print(choisi["udid"])
    sys.exit(0)
sys.exit("aucun simulateur disponible")
'
