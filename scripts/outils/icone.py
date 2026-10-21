#!/usr/bin/env python3
"""Icône de l'app : le noyau de la console (anneau de lumière, arc champagne, noyau), au format d'Icon Composer.

    python3 scripts/outils/icone.py [dossier]      (par défaut : App/Ressources/AppIcon.icon)

Un fichier `.icon` = `icon.json` (fond, groupes, effets du verre) et des calques SVG dans `Assets/`, comme le
produit Icon Composer (structure reprise du projet d'exemple d'Apple « Landmarks »). Le système en tire le verre
liquide d'iOS 26 (reflets, profondeur) et chaque apparence : par défaut, sombre, transparente, teintée. Les calques
suivent les consignes d'Apple (« Creating your app icon using Icon Composer ») : 1024 x 1024, formes pleines, ni fond,
ni flou, ni ombre, ni masque. Les couleurs sont celles de la console : faisceau #61caff, glace #e0f4ff, champagne
#d7c6a4. La CI rend l'icône par l'outil d'Apple dans les six apparences (artefact « icone »).
"""

import json
import math
import sys
from pathlib import Path

C = 512  # centre du canevas de 1024


def nombre(x):
    return f"{x:.2f}".rstrip("0").rstrip(".")


def point(r, a):
    """Point à r du centre, angle a en degrés (0 = à droite, -90 = en haut)."""
    return nombre(C + r * math.cos(math.radians(a))), nombre(C + r * math.sin(math.radians(a)))


def secteur(r0, r1, a0, a1):
    """Secteur d'anneau plein (entre les rayons r0 et r1, de l'angle a0 à a1), en tracé fermé."""
    g = 1 if a1 - a0 > 180 else 0
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = point(r1, a0), point(r1, a1), point(r0, a1), point(r0, a0)
    r0, r1 = nombre(r0), nombre(r1)
    return f"M{x0} {y0}A{r1} {r1} 0 {g} 1 {x1} {y1}L{x2} {y2}A{r0} {r0} 0 {g} 0 {x3} {y3}Z"


def cercle(r):
    """Cercle plein de rayon r au centre, en deux demi-arcs."""
    haut, bas, r = nombre(C - r), nombre(C + r), nombre(r)
    return f"M{C} {haut}A{r} {r} 0 1 1 {C} {bas}A{r} {r} 0 1 1 {C} {haut}Z"


def svg(titre, defs, corps):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg width="1024px" height="1024px" viewBox="0 0 1024 1024" version="1.1" '
        'xmlns="http://www.w3.org/2000/svg">\n'
        f"    <title>{titre}</title>\n"
        f"    <defs>\n{defs}    </defs>\n"
        f"{corps}"
        "</svg>\n"
    )


def degrade(balise, id_, attributs, arrets):
    lignes = "".join(
        f'            <stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a}"' if a else "") + "/>\n"
        for o, c, a in arrets
    )
    return f'        <{balise} id="{id_}" {attributs}>\n{lignes}        </{balise}>\n'


RAYON, EPAISSEUR = 300, 60
ANNEAU = (-26, 266)  # l'anneau de lumière, ouvert en haut à droite
ARC = (-82, -36)  # l'arc champagne, dans l'ouverture (l'arc de progression de la console)
INTERIEUR, EXTERIEUR = RAYON - EPAISSEUR / 2, RAYON + EPAISSEUR / 2
FAISCEAU = 'x1="250" y1="150" x2="780" y2="880" gradientUnits="userSpaceOnUse"'

# Calques, de l'arrière vers l'avant (numérotés ainsi, comme le conseille Apple).
CALQUES = {
    "1-halo.svg": svg(
        "1-halo",
        degrade(
            "radialGradient",
            "halo",
            'cx="512" cy="512" r="440" gradientUnits="userSpaceOnUse"',
            [("0", "#61caff", ".55"), (".45", "#61caff", ".16"), ("1", "#61caff", "0")],
        )
        + degrade(
            "radialGradient",
            "lueur",
            'cx="512" cy="512" r="190" gradientUnits="userSpaceOnUse"',
            [("0", "#61caff", ".75"), (".45", "#61caff", ".45"), ("1", "#61caff", "0")],
        ),
        f'    <path d="{cercle(440)}" fill="url(#halo)"/>\n    <path d="{cercle(190)}" fill="url(#lueur)"/>\n',
    ),
    "2-cadran.svg": svg(
        "2-cadran",
        "",
        f'    <path d="{cercle(198.5)}{cercle(193.5)}" fill="#e0f4ff" fill-opacity=".28" fill-rule="evenodd"/>\n',
    ),
    "3-anneau.svg": svg(
        "3-anneau",
        degrade(
            "linearGradient", "faisceau", FAISCEAU, [("0", "#a6e4ff", ""), (".5", "#61caff", ""), ("1", "#2c86ba", "")]
        ),
        f'    <path d="{secteur(INTERIEUR, EXTERIEUR, *ANNEAU)}" fill="url(#faisceau)"/>\n',
    ),
    "4-arc.svg": svg(
        "4-arc",
        degrade(
            "linearGradient", "champagne", 'x1="0" y1="0" x2="1" y2="1"', [("0", "#f1e6cc", ""), ("1", "#bfa77a", "")]
        ),
        f'    <path d="{secteur(INTERIEUR, EXTERIEUR, *ARC)}" fill="url(#champagne)"/>\n',
    ),
    "5-noyau.svg": svg(
        "5-noyau",
        degrade(
            "radialGradient",
            "noyau",
            'cx=".42" cy=".38" r=".62"',
            [("0", "#ffffff", ""), (".35", "#e0f4ff", ""), (".8", "#61caff", ""), ("1", "#2c86ba", "")],
        ),
        f'    <path d="{cercle(84)}" fill="url(#noyau)"/>\n',
    ),
}


def calque(nom, verre=True):
    return {"glass": verre, "hidden": False, "image-name": nom, "name": nom.removesuffix(".svg"), "opacity": 1}


OMBRE = {"kind": "neutral", "opacity": 0.5}
OPAQUE = {"enabled": False, "value": 0.5}

# icon.json : les groupes de l'avant vers l'arrière (l'ordre de la barre latérale d'Icon Composer), quatre au plus.
ICONE = {
    # le fond de la console, du haut (#10283c) vers le bas (#03080d)
    "fill": {"linear-gradient": ["srgb:0.06275,0.15686,0.23529,1.00000", "srgb:0.01176,0.03137,0.05098,1.00000"]},
    "groups": [
        {"layers": [calque("5-noyau.svg")], "shadow": OMBRE, "translucency": OPAQUE},
        {
            "layers": [calque("4-arc.svg"), calque("3-anneau.svg")],
            "lighting": "individual",
            "shadow": OMBRE,
            "translucency": OPAQUE,
        },
        # la lumière derrière l'anneau : sans verre ni reflet
        {
            "layers": [calque("2-cadran.svg", verre=False), calque("1-halo.svg", verre=False)],
            "specular": False,
            "translucency": OPAQUE,
        },
    ],
    "supported-platforms": {"squares": "shared"},
}


def ecrire(dossier):
    dossier = Path(dossier)
    (dossier / "Assets").mkdir(parents=True, exist_ok=True)
    for ancien in (dossier / "Assets").iterdir():
        if ancien.name not in CALQUES:
            ancien.unlink()
    for nom, contenu in CALQUES.items():
        (dossier / "Assets" / nom).write_text(contenu, encoding="utf-8")
    (dossier / "icon.json").write_text(json.dumps(ICONE, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    racine = Path(__file__).resolve().parents[2]
    ecrire(sys.argv[1] if len(sys.argv) > 1 else racine / "App/Ressources/AppIcon.icon")
