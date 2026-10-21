#!/usr/bin/env python3
"""Les masques des journaux publics de la CI pour le sujet d'un certificat de signature (variable SUJET) : le nom
commun entier, le nom du titulaire, l'organisation et chaque mot de ces noms. Écrit les commandes `::add-mask::` (que
GitHub retire du journal), puis leur nombre seulement.

    SUJET="$(openssl x509 -noout -subject …)" python3 scripts/outils/masques_certificat.py

Lit les deux écritures du sujet : celle d'OpenSSL 3 (« CN = …, O = … ») et celle de LibreSSL, l'openssl de macOS
(« /CN=…/O=… »).
"""

import os
import re

# des mots du métier, jamais personnels : les masquer cacherait la moitié du journal de Xcode
COMMUNS = {"Apple", "Development", "Distribution", "iPhone", "Developer"}


def valeurs(sujet):
    champs = {}
    for cle in ("CN", "O"):
        trouve = re.search(r"(?:^|[/,]\s*|subject=\s*)" + cle + r"\s*=\s*([^/,\n]+)", sujet)
        if trouve:
            champs[cle] = trouve.group(1).strip()
    noms = set()
    if "CN" in champs:
        # « Apple Development: Prénom Nom (ABC123XYZ) » : le nom du titulaire
        titulaire = re.match(r"^[^:]+:\s*(.+?)\s*(?:\([^)]*\))?$", champs["CN"])
        if titulaire:
            noms.add(titulaire.group(1))
    if "O" in champs:
        noms.add(champs["O"])
    masques = {v for v in champs.values() if v} | noms
    for nom in noms:
        masques.update(m for m in nom.split() if len(m) >= 3 and m not in COMMUNS)
    return masques


if __name__ == "__main__":
    masques = valeurs(os.environ.get("SUJET", ""))
    for v in sorted(masques, key=len, reverse=True):
        print(f"::add-mask::{v}")
    print(f"certificat : {len(masques)} valeur(s) masquée(s)")
