#!/usr/bin/env python3
"""Certificats de signature de l'équipe Apple, par l'API App Store Connect (workflow « Certificats », à la main).

    certificats.py inventaire                       tous les certificats, sans aucun nom : type, repère, dates, actif
    certificats.py creer <demande.csr> <sortie.der>  crée le certificat « Apple Development » de la CI pour cette
                                                    demande (CSR) ; un seul, réutilisé par chaque fabrication

Le nom d'un certificat est celui du titulaire du compte : rien n'en est affiché, le journal d'un dépôt public est public.
Un certificat se désigne par son repère, les 12 premiers caractères de l'empreinte SHA-256 de son numéro de série.

Variables : ASC_CLE (chemin de la clé .p8), ASC_CLE_ID, ASC_EMETTEUR_ID. Aucune dépendance : la bibliothèque standard,
et openssl pour signer le jeton (ES256) et lire les dates des certificats.
"""

import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

API = "https://api.appstoreconnect.apple.com"


def _b64url(octets):
    return base64.urlsafe_b64encode(octets).rstrip(b"=").decode()


def signature_brute(der):
    """Signature ECDSA DER (SEQUENCE de deux INTEGER) → r‖s sur 64 octets, la forme qu'exige un JWT ES256."""

    def longueur(i):
        n = der[i]
        if n < 0x80:
            return n, i + 1
        k = n & 0x7F
        return int.from_bytes(der[i + 1 : i + 1 + k], "big"), i + 1 + k

    if der[0] != 0x30:
        raise ValueError("signature : pas une SEQUENCE DER")
    _, i = longueur(1)
    entiers = []
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("signature : INTEGER attendu")
        n, i = longueur(i + 1)
        valeur = int.from_bytes(der[i : i + n], "big")
        if valeur.bit_length() > 256:
            raise ValueError("signature : entier hors de P-256")
        entiers.append(valeur.to_bytes(32, "big"))
        i += n
    return entiers[0] + entiers[1]


def jeton(cle, ident, emetteur, maintenant=None):
    """Le jeton d'App Store Connect : ES256, 10 minutes (Apple en accepte 20 au plus)."""
    t = int(maintenant if maintenant is not None else time.time())
    entete = _b64url(json.dumps({"alg": "ES256", "kid": ident, "typ": "JWT"}, separators=(",", ":")).encode())
    charge = _b64url(
        json.dumps(
            {"iss": emetteur, "iat": t, "exp": t + 600, "aud": "appstoreconnect-v1"}, separators=(",", ":")
        ).encode()
    )
    signe = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", cle],
        input=f"{entete}.{charge}".encode(),
        capture_output=True,
        check=True,
    ).stdout
    return f"{entete}.{charge}.{_b64url(signature_brute(signe))}"


def _api(chemin, corps=None):
    j = jeton(os.environ["ASC_CLE"], os.environ["ASC_CLE_ID"], os.environ["ASC_EMETTEUR_ID"])
    requete = urllib.request.Request(
        chemin if chemin.startswith("https://") else API + chemin,
        data=json.dumps(corps).encode() if corps is not None else None,
        headers={"Authorization": f"Bearer {j}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(requete, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            erreurs = json.loads(e.read()).get("errors", [])
        except ValueError:
            erreurs = []
        motifs = "; ".join(f"{x.get('code')} : {x.get('title')} ({x.get('detail')})" for x in erreurs)
        methode = "POST" if corps is not None else "GET"
        sys.exit(f"App Store Connect : {methode} {chemin.split('?')[0]} → HTTP {e.code} {motifs}")


def certificats():
    """Tous les certificats de l'équipe (pages suivies), avec leur contenu (pour les dates)."""
    champs = "certificateType,serialNumber,expirationDate,activated,certificateContent,platform"
    page = _api("/v1/certificates?" + urllib.parse.urlencode({"limit": 200, "fields[certificates]": champs}))
    tous = list(page["data"])
    while page.get("links", {}).get("next"):
        page = _api(page["links"]["next"])
        tous.extend(page["data"])
    return tous


def repere(certificat):
    return hashlib.sha256(certificat["attributes"]["serialNumber"].encode()).hexdigest()[:12]


def dates(certificat):
    """(début, fin) en UTC, lues dans le certificat lui-même ; (None, expirationDate) s'il n'a pas de contenu."""
    a = certificat["attributes"]
    fin = datetime.fromisoformat(a["expirationDate"].replace("Z", "+00:00")) if a.get("expirationDate") else None
    if not a.get("certificateContent"):
        return None, fin
    sortie = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-startdate", "-enddate"],
        input=base64.b64decode(a["certificateContent"]),
        capture_output=True,
        check=True,
    ).stdout.decode()
    lues = dict(ligne.split("=", 1) for ligne in sortie.strip().splitlines())

    def lire(texte):
        return datetime.strptime(" ".join(texte.split()), "%b %d %H:%M:%S %Y GMT").replace(tzinfo=timezone.utc)

    return lire(lues["notBefore"]), lire(lues["notAfter"])


def _ligne(c):
    debut, fin = dates(c)
    a = c["attributes"]
    return (
        f"{a['certificateType']:<26} {repere(c)}  "
        f"du {debut.strftime('%Y-%m-%d %H:%M') if debut else '?':<16}  "
        f"au {fin.strftime('%Y-%m-%d') if fin else '?':<10}  "
        f"{'actif' if a.get('activated', True) else 'inactif'}"
    )


def inventaire():
    tous = sorted(certificats(), key=lambda c: (dates(c)[0] or datetime.min.replace(tzinfo=timezone.utc)))
    print(f"{len(tous)} certificat(s) dans l'équipe (heures UTC)")
    for c in tous:
        print("  " + _ligne(c))
    par_type = {}
    for c in tous:
        par_type[c["attributes"]["certificateType"]] = par_type.get(c["attributes"]["certificateType"], 0) + 1
    print("par type : " + (", ".join(f"{t} {n}" for t, n in sorted(par_type.items())) or "aucun"))


def creer(demande, sortie):
    with open(demande) as f:
        csr = f.read()
    if "CERTIFICATE REQUEST-----" not in csr:
        sys.exit(f"{demande} : pas une demande de certificat (CSR) au format PEM")
    c = _api(
        "/v1/certificates",
        {"data": {"type": "certificates", "attributes": {"certificateType": "DEVELOPMENT", "csrContent": csr}}},
    )["data"]
    descripteur = os.open(sortie, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descripteur, "wb") as f:
        f.write(base64.b64decode(c["attributes"]["certificateContent"]))
    print("créé : " + _ligne(c))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["inventaire"]:
        inventaire()
    elif a[:1] == ["creer"] and len(a) == 3:
        creer(a[1], a[2])
    else:
        sys.exit(__doc__)
