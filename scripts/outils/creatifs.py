#!/usr/bin/env python3
"""Fiche App Store : « En-tête et résultats de recherche » (iOS 27 et plus), par l'API App Store Connect.

    creatifs.py etat                        la version modifiable, ses langues, ce qui y est placé, et les formats
                                            qu'Apple accepte pour ces deux emplacements (données de référence)
    creatifs.py deposer [--entete F] [--recherche F]
                                            dépose chaque image dans la bibliothèque de l'app, attend son traitement,
                                            puis la place sur chaque langue de la version modifiable (remplace ce qui
                                            y était) ; RIEN n'est envoyé à l'examen : l'image part avec la version

Bibliothèque d'éléments de l'app (App Asset Library, API App Store Connect 4.5.1, documentation d'Apple :
« Placing assets on your App Store surfaces ») : une image est réservée, envoyée, validée, traitée, puis placée sur une
langue de la version. Les dimensions et les groupes d'emplacement se lisent dans les données de référence d'Apple,
jamais écrits en dur. Le journal est public : seulement des identifiants techniques, des états et des dimensions.

Variables : ASC_CLE, ASC_CLE_ID, ASC_EMETTEUR_ID (comme testflight_externe.py).
"""

import json
import os
import struct
import sys
import time
import urllib.request

from testflight_externe import ErreurASC, api, appli, lister, requete_url

TYPES = {"entete": "PRODUCT_PAGE_HEADER_ASSET", "recherche": "APP_STORE_SEARCH_RESULTS_ASSET"}
CATEGORIE = "CREATIVE_ASSETS"
FONCTION = "APP_STORE_VERSIONS"
# États d'une version où la fiche se modifie encore (après, Apple refuse de nouveaux emplacements : 409)
MODIFIABLES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


# MARK: - fichiers : dimensions et transparence, sans dépendance


def dimensions_png(octets):
    """(largeur, hauteur, transparence) d'un PNG : canal alpha (types 4 et 6) ou bloc tRNS."""
    if octets[:8] != b"\x89PNG\r\n\x1a\n" or octets[12:16] != b"IHDR":
        raise ValueError("pas un PNG")
    largeur, hauteur = struct.unpack(">II", octets[16:24])
    alpha = octets[25] in (4, 6) or b"tRNS" in octets[: octets.find(b"IDAT")]
    return largeur, hauteur, alpha


def dimensions_jpeg(octets):
    """(largeur, hauteur, False) d'un JPEG, lues dans son premier marqueur SOF."""
    if octets[:2] != b"\xff\xd8":
        raise ValueError("pas un JPEG")
    i = 2
    while i + 9 < len(octets):
        if octets[i] != 0xFF:
            i += 1
            continue
        marqueur = octets[i + 1]
        longueur = struct.unpack(">H", octets[i + 2 : i + 4])[0]
        if 0xC0 <= marqueur <= 0xCF and marqueur not in (0xC4, 0xC8, 0xCC):
            hauteur, largeur = struct.unpack(">HH", octets[i + 5 : i + 9])
            return largeur, hauteur, False
        i += 2 + longueur
    raise ValueError("JPEG sans dimensions")


def decrire(chemin):
    with open(chemin, "rb") as f:
        octets = f.read()
    ext = os.path.splitext(chemin)[1].lower()
    largeur, hauteur, alpha = (dimensions_png if ext == ".png" else dimensions_jpeg)(octets)
    return {"chemin": chemin, "nom": os.path.basename(chemin), "ext": ext, "taille": len(octets), "largeur": largeur,
            "hauteur": hauteur, "alpha": alpha, "octets": octets}


# MARK: - données de référence


def reference():
    """Les six tableaux des données de référence (un seul élément dans la collection)."""
    d = api("GET", "/v1/appAssetLibraryRefData")["data"]
    return (d[0] if isinstance(d, list) else d)["attributes"]


def _cle(x, *noms):
    for n in noms:
        if n in x:
            return x[n]
    return None


def formats(ref, type_):
    """Pour un type d'emplacement : catégories acceptées, plafond par groupe (version de l'App Store) et, par groupe,
    les spécifications d'image qu'il accepte."""
    specs = {_cle(s, "specId", "id"): s for s in ref.get("imageSpecs") or []}
    t = next((x for x in ref.get("placementTypes") or [] if _cle(x, "placementType", "type", "id") == type_), {}) or {}
    groupes = {}
    for m in t.get("specMappings") or []:
        g = _cle(m, "placementGroup", "groupId", "group", "id")
        groupes[g] = [specs[i] for i in (m.get("specs") or []) if i in specs]
    plafonds = {}
    for f in ref.get("features") or []:
        if _cle(f, "feature", "id", "name") != FONCTION:
            continue
        for p in f.get("placementPolicies") or []:
            if _cle(p, "placementType", "type") == type_:
                for lim in p.get("groupLimits") or []:
                    for g in lim.get("groupIds") or []:
                        plafonds[g] = lim.get("maxCount")
    return {"categories": t.get("acceptsAssetCategories") or [], "groupes": groupes, "plafonds": plafonds}


def spec_texte(s):
    d = s.get("dimensions") or {}
    taille = (f"{d.get('minWidth')}×{d.get('minHeight')}" if d.get("minWidth") == d.get("maxWidth")
              and d.get("minHeight") == d.get("maxHeight")
              else f"{d.get('minWidth')}–{d.get('maxWidth')} × {d.get('minHeight')}–{d.get('maxHeight')}")
    return (f"{s.get('shortName')} {taille} ({s.get('aspectRatio')}) {','.join(s.get('fileExtensions') or [])}"
            f"{' alpha' if s.get('alphaAllowed') else ''}{' universel' if s.get('universalAsset') else ''}")


def accepte(spec, fichier):
    d = spec.get("dimensions") or {}
    return (d.get("minWidth", 0) <= fichier["largeur"] <= d.get("maxWidth", 0)
            and d.get("minHeight", 0) <= fichier["hauteur"] <= d.get("maxHeight", 0)
            and fichier["ext"] in [e.lower() for e in spec.get("fileExtensions") or []]
            and (spec.get("alphaAllowed") or not fichier["alpha"])
            and fichier["taille"] <= (spec.get("maxFileSize") or fichier["taille"]))


# MARK: - version et langues


def versions(app_id):
    return lister(requete_url(f"/v1/apps/{app_id}/appStoreVersions", **{
        "filter[platform]": "IOS", "fields[appStoreVersions]": "versionString,appStoreState,appVersionState",
        "limit": "20"}))


def etat_version(v):
    a = v["attributes"]
    return a.get("appVersionState") or a.get("appStoreState")


def modifiable(app_id):
    v = [x for x in versions(app_id) if etat_version(x) in MODIFIABLES]
    if len(v) != 1:
        sys.exit(f"version modifiable : {len(v)} trouvée(s) (il en faut exactement une ; voir « etat »)")
    return v[0]


def langues(version_id):
    return lister(requete_url(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
                              **{"fields[appStoreVersionLocalizations]": "locale"}))


def placements(localisation_id, type_):
    return lister(requete_url(f"/v1/appStoreVersionLocalizations/{localisation_id}/placements",
                              **{"filter[placementType]": type_, "include": "image",
                                 "fields[appAssetLibraryImages]": "referenceName,state,imageAsset"}))


def bibliotheque(app_id):
    return api("GET", f"/v1/apps/{app_id}/assetLibrary")["data"]["id"]


# MARK: - etat


def etat():
    app = appli()
    print(f"app : {app['attributes']['bundleId']} (langue principale {app['attributes'].get('primaryLocale')})")
    try:
        print(f"bibliothèque d'éléments : {bibliotheque(app['id'])}")
    except ErreurASC as e:
        print(f"bibliothèque d'éléments : illisible ({e})")
    ref = reference()
    for nom, type_ in TYPES.items():
        f = formats(ref, type_)
        print(f"{nom} ({type_}) : catégories {f['categories']}")
        if not f["groupes"]:          # forme des données de référence inattendue : la montrer (rien de personnel)
            brut = [x for x in ref.get("placementTypes") or [] if type_ in json.dumps(x)]
            print(f"  données de référence ({', '.join(sorted(ref))}) : {json.dumps(brut)[:1500]}")
        for g, specs in f["groupes"].items():
            print(f"  groupe {g} (au plus {f['plafonds'].get(g, '?')}) : " + " ; ".join(spec_texte(s) for s in specs))
    for v in versions(app["id"]):
        a = v["attributes"]
        print(f"version {a.get('versionString')} : {a.get('appStoreState')} / {a.get('appVersionState')}"
              f"{'  ← modifiable' if etat_version(v) in MODIFIABLES else ''}")
        if etat_version(v) not in MODIFIABLES:
            continue
        for loc in langues(v["id"]):
            places = {nom: placements(loc["id"], t) for nom, t in TYPES.items()}
            print(f"  {loc['attributes']['locale']} : " + ", ".join(
                f"{nom} {len(p)} ({', '.join(x['attributes'].get('state', '?') for x in p) or 'vide'})"
                for nom, p in places.items()))


# MARK: - deposer


def envoyer(bib, fichier, reference_nom):
    """Réserver, envoyer les morceaux, valider ; attendre le traitement. Rend l'identifiant de l'image."""
    r = api("POST", "/v1/appAssetLibraryImages", {"data": {
        "type": "appAssetLibraryImages",
        "attributes": {"fileName": fichier["nom"], "fileSize": fichier["taille"], "category": CATEGORIE,
                       "referenceName": reference_nom},
        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": bib}}}}})["data"]
    for op in r["attributes"].get("uploadOperations") or []:
        morceau = fichier["octets"][op["offset"]: op["offset"] + op["length"]]
        requete = urllib.request.Request(op["url"], data=morceau, method=op["method"],
                                         headers={h["name"]: h["value"] for h in op.get("requestHeaders") or []})
        with urllib.request.urlopen(requete, timeout=120) as reponse:
            reponse.read()
    api("PATCH", f"/v1/appAssetLibraryImages/{r['id']}",
        {"data": {"type": "appAssetLibraryImages", "id": r["id"], "attributes": {"uploaded": True}}})
    for _ in range(60):
        a = api("GET", f"/v1/appAssetLibraryImages/{r['id']}")["data"]["attributes"]
        if a.get("state") == "PREPARE_FOR_SUBMISSION":
            print(f"  {fichier['nom']} : traité ({(a.get('imageAsset') or {}).get('width')}×"
                  f"{(a.get('imageAsset') or {}).get('height')})")
            return r["id"]
        if a.get("state") == "FAILED":
            sys.exit(f"  {fichier['nom']} : traitement en échec ({a.get('stateDetails')})")
        time.sleep(10)
    sys.exit(f"  {fichier['nom']} : toujours en traitement après 10 min")


def placer(image_id, localisation_id, type_, groupe):
    for ancien in placements(localisation_id, type_):
        if ancien["attributes"].get("placementGroup") == groupe:
            api("DELETE", f"/v1/appAssetLibraryPlacements/{ancien['id']}")
    p = api("POST", "/v1/appAssetLibraryPlacements", {"data": {
        "type": "appAssetLibraryPlacements",
        "attributes": {"placementType": type_, "placementGroup": groupe},
        "relationships": {"image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
                          "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations",
                                                                   "id": localisation_id}}}}})["data"]
    return p["attributes"].get("state")


def deposer(fichiers):
    app = appli()
    version = modifiable(app["id"])
    ref = reference()
    choisis = {}
    for nom, chemin in fichiers.items():
        f = decrire(chemin)
        fmt = formats(ref, TYPES[nom])
        if CATEGORIE not in fmt["categories"]:
            sys.exit(f"{nom} : la catégorie {CATEGORIE} n'est pas acceptée ({fmt['categories']})")
        groupes = [g for g, specs in fmt["groupes"].items() if any(accepte(s, f) for s in specs)]
        if not groupes:
            sys.exit(f"{nom} : {f['nom']} ({f['largeur']}×{f['hauteur']} {f['ext']}{' alpha' if f['alpha'] else ''}) "
                     f"ne correspond à aucun format accepté (voir « etat »)")
        choisis[nom] = (f, groupes)
    bib = bibliotheque(app["id"])
    locs = langues(version["id"])
    print(f"version {version['attributes'].get('versionString')} : {len(locs)} langue(s)")
    for nom, (f, groupes) in choisis.items():
        image = envoyer(bib, f, f"Alfred — {nom} ({f['largeur']}×{f['hauteur']})")
        for loc in locs:
            for g in groupes:
                print(f"  {loc['attributes']['locale']} {nom} {g} : {placer(image, loc['id'], TYPES[nom], g)}")


def main(argv):
    if argv[:1] == ["etat"]:
        etat()
    elif argv[:1] == ["deposer"]:
        fichiers, reste = {}, argv[1:]
        while reste:
            option = reste.pop(0)
            if option not in ("--entete", "--recherche") or not reste:
                sys.exit("deposer [--entete FICHIER] [--recherche FICHIER]")
            fichiers[option[2:]] = reste.pop(0)
        if not fichiers:
            sys.exit("deposer : au moins un fichier")
        deposer(fichiers)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
