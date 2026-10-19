#!/usr/bin/env python3
"""TestFlight pour les testeurs EXTERNES, par l'API App Store Connect (workflow « Testeurs externes »).

    testflight_externe.py etat                  ce qui est en place, sans aucune donnée personnelle
    testflight_externe.py preparer              groupe externe, informations de test, contact de l'examen d'Apple
    testflight_externe.py soumettre <numéro>    la fabrication <numéro> : traitement d'Apple attendu, « À tester »,
                                                ajout au groupe externe, envoi à l'examen d'Apple
    testflight_externe.py inviter               les testeurs (secret ASC_TESTEURS) dans le groupe externe

Le journal d'un dépôt public est public : rien de personnel n'y est écrit (ni nom, ni e-mail, ni téléphone), seulement
des états et des nombres. Les valeurs personnelles viennent des secrets, et tout message d'erreur d'Apple est expurgé de
ces valeurs avant d'être affiché (le workflow les masque aussi).

Variables :
    ASC_CLE, ASC_CLE_ID, ASC_EMETTEUR_ID   la clé d'API (comme certificats.py)
    ASC_CONTACT_REVUE  JSON {"prenom", "nom", "email", "telephone", "retours"} : le contact de l'examen d'Apple et
                       l'adresse des retours des testeurs (preparer)
    ASC_TESTEURS       JSON [{"email", "prenom", "nom"}] (inviter)
    ALFRED_A_TESTER    le texte « À tester » de la fabrication (soumettre ; un texte par défaut sinon)
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from certificats import API, jeton

BUNDLE = "io.github.markedoe.alfred"
GROUPE = "Famille (externe)"
LANGUE = "fr-FR"

DESCRIPTION = (
    "Alfred, l’assistant vocal de la maison, en natif : la console « Manor Command » sur iPhone, iPad et Mac. On lui "
    "parle ou on lui écrit, il agit sur la maison et répond ; on voit la maison pièce par pièce, avec l’état qu’elle "
    "confirme. Réservée à la famille : l’app ne se connecte qu’à la maison (Wi-Fi ou VPN). « Essayer avec une maison "
    "de démonstration » l’ouvre sans connexion."
)

# Pour l'équipe d'Apple : en anglais (sa langue de travail), avec les libellés de l'app tels qu'ils s'affichent
NOTES = (
    "Alfred is the companion app of a private home automation server: it only connects to the developer's own home "
    "(home network or its VPN), so no reviewer account can reach it. To review the app, tap “Essayer avec une "
    "maison de démonstration” (Try with a demo home) on the first screen: a simulated house, with no "
    "network, no account and no microphone. In the demo, “Écrire” (Write) shows a simulated exchange "
    "with Alfred; the rooms wheel, the documents and notifications windows and the settings all work with simulated "
    "data. The app collects no data and has no tracking."
)

A_TESTER = (
    "Parler et écrire à Alfred, la roue des pièces (allumer, éteindre), Documents et Notifications. Un souci ? Une "
    "capture d’écran depuis TestFlight, avec un mot."
)

# États de traitement d'une fabrication chez Apple (attribut processingState) : seul VALID est utilisable
TRAITEMENT_FINI = {"VALID"}
TRAITEMENT_ECHOUE = {"FAILED", "INVALID"}


class ErreurASC(Exception):
    def __init__(self, statut, message):
        super().__init__(message)
        self.statut = statut


# MARK: - données personnelles : lues dans les secrets, jamais affichées


def _json_env(nom, defaut):
    brut = os.environ.get(nom, "").strip()
    if not brut:
        return defaut
    try:
        return json.loads(brut)
    except ValueError:
        sys.exit(f"{nom} : JSON invalide ({len(brut)} caractères)")


def valeurs_personnelles():
    """Toutes les valeurs à ne jamais afficher : celles du contact et des testeurs, et la partie locale des e-mails."""
    valeurs = set()
    contact = _json_env("ASC_CONTACT_REVUE", {})
    testeurs = _json_env("ASC_TESTEURS", [])
    for v in list(contact.values()) + [x for t in testeurs for x in t.values()]:
        if isinstance(v, str) and v.strip():
            valeurs.add(v.strip())
            if "@" in v:
                valeurs.add(v.split("@", 1)[0])
    return valeurs


def expurger(texte, valeurs):
    """Le texte sans aucune des valeurs (les plus longues d'abord : un nom contenu dans un e-mail reste caché)."""
    for v in sorted(valeurs, key=len, reverse=True):
        if len(v) >= 2:
            texte = texte.replace(v, "***")
    return texte


SECRETES = valeurs_personnelles()


# MARK: - API


def api(methode, chemin, corps=None):
    """Une requête ; rend le JSON (None pour une réponse vide). ErreurASC, expurgée, en cas d'échec HTTP."""
    j = jeton(os.environ["ASC_CLE"], os.environ["ASC_CLE_ID"], os.environ["ASC_EMETTEUR_ID"])
    requete = urllib.request.Request(
        chemin if chemin.startswith("https://") else API + chemin,
        data=json.dumps(corps).encode() if corps is not None else None,
        headers={"Authorization": f"Bearer {j}", "Content-Type": "application/json"},
        method=methode,
    )
    try:
        with urllib.request.urlopen(requete, timeout=30) as r:
            contenu = r.read()
            return json.loads(contenu) if contenu else None
    except urllib.error.HTTPError as e:
        try:
            erreurs = json.loads(e.read()).get("errors", [])
        except ValueError:
            erreurs = []
        motifs = "; ".join(f"{x.get('code')} : {x.get('title')} ({x.get('detail')})" for x in erreurs)
        raise ErreurASC(e.code, expurger(f"{methode} {chemin.split('?')[0]} → HTTP {e.code} {motifs}", SECRETES))


def lister(chemin):
    page = api("GET", chemin)
    tout = list(page["data"])
    while page.get("links", {}).get("next"):
        page = api("GET", page["links"]["next"])
        tout.extend(page["data"])
    return tout


def requete_url(chemin, **params):
    return chemin + "?" + urllib.parse.urlencode(params)


def appli():
    apps = api("GET", requete_url("/v1/apps", **{"filter[bundleId]": BUNDLE, "fields[apps]": "bundleId,primaryLocale"}))
    if len(apps["data"]) != 1:
        sys.exit(f"app {BUNDLE} : {len(apps['data'])} trouvée(s) dans App Store Connect")
    return apps["data"][0]


def groupe_externe(app_id, creer=False):
    groupes = lister(
        requete_url("/v1/betaGroups", **{"filter[app]": app_id, "filter[isInternalGroup]": "false", "limit": 200})
    )
    trouve = next((g for g in groupes if g["attributes"]["name"] == GROUPE), None)
    if trouve or not creer:
        return trouve
    g = api(
        "POST",
        "/v1/betaGroups",
        {
            "data": {
                "type": "betaGroups",
                "attributes": {
                    "name": GROUPE,
                    "isInternalGroup": False,
                    "publicLinkEnabled": False,
                    "feedbackEnabled": True,
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )["data"]
    print(f"groupe externe « {GROUPE} » créé (sans lien public)")
    return g


def fabrication(app_id, numero):
    builds = api(
        "GET",
        requete_url(
            "/v1/builds",
            **{"filter[app]": app_id, "filter[version]": str(numero), "include": "preReleaseVersion", "limit": 10},
        ),
    )
    if len(builds["data"]) != 1:
        raise ErreurASC(404, f"fabrication {numero} : {len(builds['data'])} trouvée(s)")
    return builds["data"][0], builds.get("included", [])


# MARK: - commandes


def etat():
    app = appli()
    app_id = app["id"]
    print(f"app : {BUNDLE} (langue principale {app['attributes'].get('primaryLocale')})")
    for loc in lister(f"/v1/apps/{app_id}/betaAppLocalizations"):
        a = loc["attributes"]
        print(
            f"  informations de test {a['locale']} : description {'oui' if a.get('description') else 'NON'}, "
            f"e-mail des retours {'oui' if a.get('feedbackEmail') else 'NON'}"
        )
    d = api("GET", f"/v1/apps/{app_id}/betaAppReviewDetail")["data"]["attributes"]
    champs = ("contactFirstName", "contactLastName", "contactEmail", "contactPhone")
    complet = all(d.get(c) for c in champs)
    print(
        f"  contact de l'examen : {'complet' if complet else 'INCOMPLET'}, compte de démo exigé : "
        f"{d.get('demoAccountRequired')}, notes : {'oui' if d.get('notes') else 'NON'}"
    )
    groupes = lister(requete_url("/v1/betaGroups", **{"filter[app]": app_id, "limit": 200}))
    for g in groupes:
        a = g["attributes"]
        testeurs = lister(requete_url("/v1/betaTesters", **{"filter[betaGroups]": g["id"], "limit": 200}))
        etats = {}
        for t in testeurs:
            etats[t["attributes"].get("state")] = etats.get(t["attributes"].get("state"), 0) + 1
        print(
            f"  groupe « {a['name']} » ({'interne' if a.get('isInternalGroup') else 'externe'}, lien public "
            f"{'oui' if a.get('publicLinkEnabled') else 'non'}) : {len(testeurs)} testeur(s) "
            + (", ".join(f"{n} {e}" for e, n in sorted(etats.items(), key=lambda x: str(x[0]))) or "")
        )
    externe = next((g for g in groupes if g["attributes"]["name"] == GROUPE), None)
    dans_groupe = set()
    if externe:
        dans_groupe = {b["id"] for b in lister(f"/v1/betaGroups/{externe['id']}/builds?limit=200")}
    builds = api(
        "GET",
        requete_url(
            "/v1/builds",
            **{"filter[app]": app_id, "sort": "-uploadedDate", "limit": 5, "include": "buildBetaDetail"},
        ),
    )
    details = {x["id"]: x["attributes"] for x in builds.get("included", []) if x["type"] == "buildBetaDetails"}
    for b in builds["data"]:
        a = b["attributes"]
        bd = b["relationships"].get("buildBetaDetail", {}).get("data") or {}
        externe_etat = details.get(bd.get("id"), {}).get("externalBuildState")
        print(
            f"  fabrication {a['version']} : {a.get('processingState')}, externe {externe_etat}, "
            f"{'dans le groupe externe' if b['id'] in dans_groupe else 'hors du groupe externe'}"
        )


def preparer():
    contact = _json_env("ASC_CONTACT_REVUE", None)
    manque = [c for c in ("prenom", "nom", "email", "telephone", "retours") if not (contact or {}).get(c)]
    if manque:
        sys.exit("ASC_CONTACT_REVUE : champ(s) manquant(s) : " + ", ".join(manque))
    if not contact["telephone"].startswith("+"):
        sys.exit("ASC_CONTACT_REVUE : le téléphone au format international (+ et l'indicatif du pays)")
    app = appli()
    app_id = app["id"]

    # informations de test : la langue de l'app (fr-FR) et toute autre déjà présente
    locs = lister(f"/v1/apps/{app_id}/betaAppLocalizations")
    attributs = {"description": DESCRIPTION, "feedbackEmail": contact["retours"]}
    if not any(l["attributes"]["locale"] == LANGUE for l in locs):
        api(
            "POST",
            "/v1/betaAppLocalizations",
            {
                "data": {
                    "type": "betaAppLocalizations",
                    "attributes": {"locale": LANGUE, **attributs},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )
        print(f"informations de test {LANGUE} : créées")
    for l in locs:
        api(
            "PATCH",
            f"/v1/betaAppLocalizations/{l['id']}",
            {"data": {"type": "betaAppLocalizations", "id": l["id"], "attributes": attributs}},
        )
        print(f"informations de test {l['attributes']['locale']} : à jour")

    # le contact de l'examen d'Apple ; aucun compte de démo (la démo de l'app n'en demande pas)
    detail = api("GET", f"/v1/apps/{app_id}/betaAppReviewDetail")["data"]
    api(
        "PATCH",
        f"/v1/betaAppReviewDetails/{detail['id']}",
        {
            "data": {
                "type": "betaAppReviewDetails",
                "id": detail["id"],
                "attributes": {
                    "contactFirstName": contact["prenom"],
                    "contactLastName": contact["nom"],
                    "contactEmail": contact["email"],
                    "contactPhone": contact["telephone"],
                    "demoAccountRequired": False,
                    "notes": NOTES,
                },
            }
        },
    )
    print("contact et notes de l'examen d'Apple : à jour (aucun compte de démo)")
    groupe_externe(app_id, creer=True)


def attendre_traitement(app_id, numero, minutes):
    """La fabrication, une fois traitée par Apple (VALID) ; l'envoi d'une fabrication neuve met 5 à 30 min."""
    fin = time.monotonic() + minutes * 60
    while True:
        try:
            b, inclus = fabrication(app_id, numero)
            etat = b["attributes"].get("processingState")
            if etat in TRAITEMENT_FINI:
                return b, inclus
            if etat in TRAITEMENT_ECHOUE:
                sys.exit(f"fabrication {numero} : traitement d'Apple en échec ({etat})")
            print(f"fabrication {numero} : {etat}, j'attends")
        except ErreurASC as e:
            if e.statut != 404:
                raise
            print(f"fabrication {numero} : pas encore visible, j'attends")
        if time.monotonic() > fin:
            sys.exit(f"fabrication {numero} : pas traitée après {minutes} min")
        time.sleep(30)


def soumettre(numero, minutes=45):
    app = appli()
    app_id = app["id"]
    groupe = groupe_externe(app_id)
    if not groupe:
        sys.exit(f"groupe « {GROUPE} » absent : lancer d'abord « preparer »")
    b, inclus = attendre_traitement(app_id, numero, minutes)
    a = b["attributes"]
    version = next((x["attributes"].get("version") for x in inclus if x["type"] == "preReleaseVersions"), "?")
    if a.get("expired"):
        sys.exit(f"fabrication {numero} : expirée")
    if a.get("buildAudienceType") == "INTERNAL_ONLY":
        sys.exit(f"fabrication {numero} : réservée aux testeurs internes (envoyée « TestFlight Internal Only »)")
    if a.get("usesNonExemptEncryption") is None:
        sys.exit(f"fabrication {numero} : conformité d'exportation absente (ITSAppUsesNonExemptEncryption)")
    print(f"fabrication {version} ({numero}) : traitée par Apple")

    # « À tester », dans la langue de l'app
    texte = os.environ.get("ALFRED_A_TESTER", "").strip() or A_TESTER
    locs = lister(f"/v1/builds/{b['id']}/betaBuildLocalizations")
    loc = next((l for l in locs if l["attributes"]["locale"] == LANGUE), None)
    if loc:
        api(
            "PATCH",
            f"/v1/betaBuildLocalizations/{loc['id']}",
            {"data": {"type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": texte}}},
        )
    else:
        api(
            "POST",
            "/v1/betaBuildLocalizations",
            {
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": LANGUE, "whatsNew": texte},
                    "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}},
                }
            },
        )
    print("« À tester » : à jour")

    try:
        api(
            "POST",
            f"/v1/betaGroups/{groupe['id']}/relationships/builds",
            {"data": [{"type": "builds", "id": b["id"]}]},
        )
        print(f"ajoutée au groupe « {GROUPE} »")
    except ErreurASC as e:
        # une relance (examen refusé ou informations incomplètes la 1re fois) : la fabrication y est déjà
        if e.statut != 409:
            raise
        print(f"déjà dans le groupe « {GROUPE} »")

    try:
        deja = api("GET", f"/v1/builds/{b['id']}/betaAppReviewSubmission")
    except ErreurASC as e:
        if e.statut != 404:
            raise
        deja = None
    if deja and deja.get("data"):
        print(f"examen d'Apple déjà demandé : {deja['data']['attributes'].get('betaReviewState')}")
        return
    s = api(
        "POST",
        "/v1/betaAppReviewSubmissions",
        {
            "data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}},
            }
        },
    )["data"]
    print(f"envoyée à l'examen d'Apple : {s['attributes'].get('betaReviewState')}")


def inviter():
    testeurs = _json_env("ASC_TESTEURS", None)
    if not isinstance(testeurs, list) or not testeurs or not all(t.get("email") for t in testeurs):
        sys.exit("ASC_TESTEURS : une liste JSON [{\"email\", \"prenom\", \"nom\"}] est attendue")
    app = appli()
    app_id = app["id"]
    groupe = groupe_externe(app_id)
    if not groupe:
        sys.exit(f"groupe « {GROUPE} » absent : lancer d'abord « preparer »")
    ajoutes = deja = 0
    for t in testeurs:
        existants = api(
            "GET",
            requete_url("/v1/betaTesters", **{"filter[email]": t["email"], "include": "betaGroups", "limit": 5}),
        )["data"]
        if existants:
            ident = existants[0]["id"]
            groupes = {g["id"] for g in existants[0]["relationships"].get("betaGroups", {}).get("data", [])}
            if groupe["id"] in groupes:
                deja += 1
                continue
            api(
                "POST",
                f"/v1/betaTesters/{ident}/relationships/betaGroups",
                {"data": [{"type": "betaGroups", "id": groupe["id"]}]},
            )
        else:
            api(
                "POST",
                "/v1/betaTesters",
                {
                    "data": {
                        "type": "betaTesters",
                        "attributes": {
                            "email": t["email"],
                            "firstName": t.get("prenom", ""),
                            "lastName": t.get("nom", ""),
                        },
                        "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": groupe["id"]}]}},
                    }
                },
            )
        ajoutes += 1
    print(f"testeurs : {ajoutes} ajouté(s) au groupe « {GROUPE} », {deja} déjà dedans")
    etats = {}
    for t in lister(requete_url("/v1/betaTesters", **{"filter[betaGroups]": groupe["id"], "limit": 200})):
        etats[t["attributes"].get("state")] = etats.get(t["attributes"].get("state"), 0) + 1
    print("états : " + (", ".join(f"{n} {e}" for e, n in sorted(etats.items(), key=lambda x: str(x[0]))) or "aucun"))


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        if a == ["etat"]:
            etat()
        elif a == ["preparer"]:
            preparer()
        elif a[:1] == ["soumettre"] and len(a) == 2 and a[1].isdigit():
            soumettre(a[1])
        elif a == ["inviter"]:
            inviter()
        else:
            sys.exit(__doc__)
    except ErreurASC as e:
        sys.exit(f"App Store Connect : {e}")
