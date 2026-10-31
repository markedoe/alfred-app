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
    """Ordre des runtimes : le runtime GÉNÉRAL d’abord, puis le plus récent. Xcode 27.2 installe aussi un runtime propre
    à un modèle (« iOS-27-2-iPhone19-4 », l’iPhone Duo seul), parfois plus récent que le général (image « xcode-27 » de
    GitHub, 31.10 : iOS 27.1 général, 27.2 pour le Duo) : il n’est pris qu’à défaut."""
    m = re.search(r"iOS-(\d+)-(\d+)(-.+)?$", rt)
    return (m.group(3) is None, int(m.group(1)), int(m.group(2))) if m else (False, 0, 0)

def ecran_integre(v):
    """Le premier écran « integrated » d’une liste « displays », où qu’elle soit dans capabilities.plist."""
    if isinstance(v, dict):
        if v.get("displayType") == "integrated" and "width" in v and "scale" in v:
            return v
        v = list(v.values())
    if isinstance(v, list):
        for e in v:
            r = ecran_integre(e)
            if r:
                return r
    return None

def largeur(x):
    """La largeur de l’écran en points (pixels / échelle), lue dans le profil du modèle — profile.plist jusqu’à Xcode
    26 ; depuis Xcode 27.2, l’écran intégré de capabilities.plist (31.10). Sans aucune des deux : écarté."""
    ressources = os.path.join(chemins[x["deviceTypeIdentifier"]], "Contents", "Resources")
    with open(os.path.join(ressources, "profile.plist"), "rb") as f:
        p = plistlib.load(f)
    if "mainScreenWidth" in p and "mainScreenScale" in p:
        return p["mainScreenWidth"] / p["mainScreenScale"]
    try:
        with open(os.path.join(ressources, "capabilities.plist"), "rb") as f:
            e = ecran_integre(plistlib.load(f))
    except OSError:
        e = None
    if e:
        return e["width"] / e["scale"]
    print("%s : sans taille d’écran, écarté" % x["name"], file=sys.stderr)
    return None

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
        mesurables = [x for x in appareils if largeur(x) is not None]
        if not mesurables:
            continue
        choisi, reference = min(mesurables, key=largeur), defaut(mesurables)
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
