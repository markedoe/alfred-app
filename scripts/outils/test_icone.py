"""Tests de icone.py : l'icône du dépôt est celle du générateur, et elle suit les consignes d'Apple.

    python3 -m unittest discover -s scripts/outils -p 'test_*.py'
"""

import json
import os
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

import icone  # noqa: E402

DEPOT = Path(__file__).resolve().parents[2] / "App/Ressources/AppIcon.icon"
SVG = "{http://www.w3.org/2000/svg}"


class Icone(unittest.TestCase):
    def test_depot_a_jour(self):
        with tempfile.TemporaryDirectory() as tmp:
            icone.ecrire(tmp)
            neuf = {p.relative_to(tmp): p.read_bytes() for p in Path(tmp).rglob("*") if p.is_file()}
        depot = {p.relative_to(DEPOT): p.read_bytes() for p in DEPOT.rglob("*") if p.is_file()}
        self.assertEqual(
            sorted(depot), sorted(neuf), "fichiers de l'icône ≠ générateur : python3 scripts/outils/icone.py"
        )
        for nom, contenu in neuf.items():
            self.assertEqual(depot[nom], contenu, f"{nom} ≠ générateur : python3 scripts/outils/icone.py")

    def test_groupes_et_calques(self):
        description = json.loads((DEPOT / "icon.json").read_text(encoding="utf-8"))
        self.assertLessEqual(len(description["groups"]), 4, "Icon Composer : quatre groupes au plus")
        noms = [c["image-name"] for g in description["groups"] for c in g["layers"]]
        self.assertEqual(sorted(noms), sorted(p.name for p in (DEPOT / "Assets").iterdir()))
        self.assertEqual(len(noms), len(set(noms)))

    def test_calques_selon_apple(self):
        # 1024 x 1024, ni flou, ni filtre, ni masque, ni texte, ni image intégrée (« Prepare your artwork for export »)
        for chemin in sorted((DEPOT / "Assets").iterdir()):
            with self.subTest(calque=chemin.name):
                racine = ET.parse(chemin).getroot()
                self.assertEqual(racine.get("viewBox"), "0 0 1024 1024")
                balises = {e.tag.removeprefix(SVG) for e in racine.iter()}
                self.assertFalse(balises & {"filter", "feGaussianBlur", "mask", "text", "image"}, balises)


if __name__ == "__main__":
    unittest.main()
