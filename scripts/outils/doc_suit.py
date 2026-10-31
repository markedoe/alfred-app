#!/usr/bin/env python3
"""La documentation suit le code (31.10.2026 : « vérifier que tout soit toujours bien documenté quand il y a des
nouvelles features »).

Règle : un commit qui change du CODE (une fonction, un outil, un prompt, l'app…) change aussi de la DOC dans le même
commit — ou son message le dit : « Doc : inchangée — <raison> ». Ce que sont le code et la doc est réglé par dépôt dans
un fichier JSON (motifs glob, `**` = n'importe quels dossiers) :

    {"doc": ["**.md"], "code": ["App/**", …], "hors": ["**/tests/**", …]}

Un fichier « hors » ne compte ni comme code ni comme doc (tests, exports, réglages). Ce contrôle dit seulement qu'une doc
a BOUGÉ avec le code, pas qu'elle est juste.

    doc_suit.py --reglages R --message-commit FICHIER   crochet commit-msg : l'index contre le message (bloque)
    doc_suit.py --reglages R --plage A..B               CI et revue de nuit : chaque commit de la plage
    doc_suit.py --reglages R --depuis "26 hours ago"    revue de nuit : les commits récents

Code de sortie 1 au moindre commit fautif (la liste est écrite). Même script dans les deux dépôts du projet ; un
test vérifie que les deux copies sont identiques. Rien de privé ici : le dépôt de l'app
est public.
"""
import argparse
import fnmatch
import json
import re
import subprocess
import sys

MARQUEUR = re.compile(r"doc\s*:\s*inchang", re.IGNORECASE)
VIDE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"   # l'arbre vide de git (premier commit d'un dépôt)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def correspond(chemin, motifs):
    # « ** » : n'importe quels dossiers ; fnmatch fait déjà traverser « / » par « * », on traite « **/ » comme facultatif
    for m in motifs:
        if fnmatch.fnmatchcase(chemin, m) or ("**/" in m and fnmatch.fnmatchcase(chemin, m.replace("**/", ""))):
            return True
    return False


def juger(fichiers, message, reglages):
    """Rend la liste du code changé sans doc (vide = conforme)."""
    utiles = [f for f in fichiers if not correspond(f, reglages.get("hors", []))]
    if any(correspond(f, reglages["doc"]) for f in utiles) or MARQUEUR.search(message or ""):
        return []
    return [f for f in utiles if correspond(f, reglages["code"])]


def commits(plage=None, depuis=None):
    args = ["log", "--no-merges", "--format=%H", "--reverse"]
    if depuis:
        args += ["--since", depuis]
    if plage:
        args.append(plage)
    return [c for c in git(*args).split() if c]


def fichiers_du_commit(sha):
    parents = git("rev-list", "--parents", "-n", "1", sha).split()[1:]
    base = parents[0] if parents else VIDE
    return [f for f in git("diff", "--name-only", base, sha).splitlines() if f]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--reglages", required=True)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--message-commit", metavar="FICHIER")
    g.add_argument("--plage")
    g.add_argument("--depuis")
    x = ap.parse_args()
    with open(x.reglages, encoding="utf-8") as f:
        reglages = json.load(f)

    if x.message_commit:
        with open(x.message_commit, encoding="utf-8") as f:
            message = "\n".join(l for l in f.read().splitlines() if not l.startswith("#"))
        fichiers = [f for f in git("diff", "--cached", "--name-only").splitlines() if f]
        manque = juger(fichiers, message, reglages)
        if manque:
            print("doc : commit refusé — du code change sans aucune doc (%s%s).\n"
                  "Mets à jour la doc qui décrit ce changement, ou écris dans le message : « Doc : inchangée — <raison> »."
                  % (", ".join(manque[:5]), " …" if len(manque) > 5 else ""), file=sys.stderr)
            return 1
        print("doc : OK")
        return 0

    plage = x.plage
    if plage and plage.split("..")[0].strip("0") == "":
        plage = plage.split("..")[1]     # premier push d'une branche (« before » = 000…) : tout l'historique atteignable
    fautifs = []
    liste = commits(plage=plage, depuis=x.depuis)
    for sha in liste:
        message = git("log", "-1", "--format=%B", sha)
        manque = juger(fichiers_du_commit(sha), message, reglages)
        if manque:
            fautifs.append((sha[:7], message.splitlines()[0][:90] if message else "", manque))
    for sha, sujet, manque in fautifs:
        print("%s %s\n    code sans doc : %s%s" % (sha, sujet, ", ".join(manque[:6]), " …" if len(manque) > 6 else ""))
    print("doc : %d commit(s) sur %d sans doc" % (len(fautifs), len(liste)))
    return 1 if fautifs else 0


if __name__ == "__main__":
    sys.exit(main())
