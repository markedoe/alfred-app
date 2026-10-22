#!/usr/bin/env python3
"""Ce qui a changé depuis la dernière vérification réussie, ou depuis la dernière fabrication (22.10.2026).

    changements.py ci                 « Intégration » : l'app a-t-elle changé depuis la dernière Intégration RÉUSSIE
                                      d'un envoi sur main ? Écrit app=true|false.
    changements.py testflight <sha>   « TestFlight » lancé par une Intégration verte : ce qui part dans l'app a-t-il
                                      changé entre le dernier commit fabriqué et <sha> ? Écrit fabriquer=true|false.

Le résultat va dans $GITHUB_OUTPUT, la raison dans le journal (des chemins du dépôt public, rien d'autre).

Sûr par défaut : sans base CERTAINE, tout tourne (événement autre qu'un envoi sur main, aucune exécution réussie,
commit absent de l'historique ou qui n'en est pas l'ancêtre, API muette). La base est le commit de la dernière
exécution RÉUSSIE, jamais le commit précédent : une Intégration annulée par un envoi plus récent n'a rien vérifié, et
comparer au commit précédent laisserait partir à TestFlight un code jamais testé.

Ce qui n'est PAS l'app se liste (HORS_APP) : tout chemin inconnu compte comme un changement de l'app.
"""

import json
import os
import re
import subprocess
import sys
import urllib.request

# Hors de l'app : ni les tests iOS ni l'icône n'ont à tourner pour eux (les outils Python ont leurs propres tests)
HORS_APP = (
    re.compile(r"^scripts/outils/"),
    re.compile(r"^AppStore/"),
    re.compile(r"^docs/"),
    re.compile(r"\.md$"),
    re.compile(r"^\.github/dependabot\.yml$"),
    re.compile(r"^\.github/workflows/(certificats|codeql|fiche-app-store|testeurs-externes|testflight)\.yml$"),
)
# Hors de ce qui part dans l'app : en plus, les tests et la CI qui les fait tourner
HORS_FABRICATION = HORS_APP + (
    re.compile(r"^AppTests/"),
    re.compile(r"^AppUITests/"),
    re.compile(r"^Paquets/AlfredKit/Tests/"),
    re.compile(r"^\.github/workflows/ci\.yml$"),
    re.compile(r"^\.swift-format$"),
    re.compile(r"^scripts/simulateur\.sh$"),
)
SHA = re.compile(r"\b[0-9a-f]{40}\b")


def touches(fichiers, hors):
    """Les fichiers qui ne sont dans aucun motif de `hors` (ceux qui comptent)."""
    return [f for f in fichiers if f and not any(m.search(f) for m in hors)]


def sha_fabrique(execution):
    """Le commit qu'une exécution de « TestFlight » a fabriqué : celui que son titre nomme (lancée par une
    Intégration, son head_sha est la tête de main au lancement, pas le commit vérifié), sinon son head_sha (à la main
    ou par une étiquette, c'est le commit fabriqué)."""
    m = SHA.search(execution.get("display_title") or "")
    return m.group(0) if m else execution.get("head_sha")


def base_testflight(executions, moi):
    """Le commit de la dernière exécution RÉUSSIE (en sautant celle-ci) ; None s'il n'y en a pas.

    TestFlight passe une exécution à la fois : quand celle-ci décide, aucune plus ancienne ne tourne encore ; une
    exécution non terminée est forcément PLUS RÉCENTE (en attente) et ne peut pas servir de base. Une exécution réussie
    qui n'a rien fabriqué (rien de livré n'avait changé) reste une base juste : son commit livre la même app.
    Cas connu : une fabrication envoyée dont l'envoi aux testeurs externes échoue compte comme un échec → la suivante
    refabrique la même app une fois."""
    for e in sorted(executions, key=lambda x: x.get("created_at") or "", reverse=True):
        if str(e.get("id")) != str(moi) and e.get("status") == "completed" and e.get("conclusion") == "success":
            return sha_fabrique(e)
    return None


# MARK: - git et API de GitHub


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def ancetre(base, tete):
    """Vrai si `base` est un commit connu et un ancêtre de `tete` (ou `tete` lui-même)."""
    if not base or git("cat-file", "-e", f"{base}^{{commit}}").returncode != 0:
        return False
    return git("merge-base", "--is-ancestor", base, tete).returncode == 0


def fichiers_changes(base, tete):
    r = git("diff", "--name-only", base, tete)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.splitlines()


def api(chemin):
    requete = urllib.request.Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{chemin}",
        headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}", "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(requete, timeout=30) as r:
        return json.load(r)


def ecrire(cle, valeur, raison):
    print(f"{cle}={'true' if valeur else 'false'} : {raison}")
    sortie = os.environ.get("GITHUB_OUTPUT")
    if sortie:
        with open(sortie, "a", encoding="utf-8") as f:
            f.write(f"{cle}={'true' if valeur else 'false'}\n")


def decider(cle, base, tete, hors, quoi):
    """Écrit `cle` : vrai si un fichier hors de `hors` a changé entre `base` et `tete` (ou si la base est incertaine)."""
    if not ancetre(base, tete):
        return ecrire(cle, True, f"base {str(base)[:7]} absente ou hors de l'historique de {tete[:7]} : tout tourne")
    comptent = touches(fichiers_changes(base, tete), hors)
    if comptent:
        return ecrire(cle, True, f"{quoi} changé depuis {base[:7]} : " + ", ".join(comptent[:10])
                      + (f" (+{len(comptent) - 10})" if len(comptent) > 10 else ""))
    return ecrire(cle, False, f"{quoi} identique à {base[:7]} (seuls des fichiers hors de l'app ont changé)")


# MARK: - commandes


def ci():
    tete = git("rev-parse", "HEAD").stdout.strip()
    evenement, ref = os.environ.get("GITHUB_EVENT_NAME"), os.environ.get("GITHUB_REF")
    if evenement != "push" or ref != "refs/heads/main":
        return ecrire("app", True, f"{evenement} sur {ref} : tout tourne")
    try:
        runs = api("actions/workflows/ci.yml/runs?branch=main&event=push&status=success&per_page=1")["workflow_runs"]
    except Exception as e:  # API muette : sûr par défaut
        return ecrire("app", True, f"API de GitHub illisible ({type(e).__name__}) : tout tourne")
    decider("app", runs[0]["head_sha"] if runs else None, tete, HORS_APP, "l'app")


def testflight(tete):
    if not SHA.fullmatch(tete or ""):
        sys.exit(f"commit invalide : {tete!r}")
    try:
        runs = api("actions/workflows/testflight.yml/runs?per_page=30")["workflow_runs"]
    except Exception as e:
        return ecrire("fabriquer", True, f"API de GitHub illisible ({type(e).__name__}) : fabrication")
    decider("fabriquer", base_testflight(runs, os.environ.get("GITHUB_RUN_ID")), tete, HORS_FABRICATION,
            "ce qui part dans l'app")


def main(argv):
    if argv == ["ci"]:
        ci()
    elif len(argv) == 2 and argv[0] == "testflight":
        testflight(argv[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
