"""Tests de masques_certificat.py (noms inventés)."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import masques_certificat as mc  # noqa: E402


class Masques(unittest.TestCase):
    attendus = {
        "Apple Development: Camille Exemple (A1B2C3D4E5)",
        "Camille Exemple",
        "Camille",
        "Exemple",
    }

    def test_openssl_3(self):
        sujet = (
            "subject=UID=X1Y2Z3, CN=Apple Development: Camille Exemple (A1B2C3D4E5), OU=TEAM123456, "
            "O=Camille Exemple, C=CH"
        )
        self.assertEqual(mc.valeurs(sujet), self.attendus)

    def test_openssl_3_espaces(self):
        sujet = "subject=UID = X1, CN = Apple Development: Camille Exemple (A1B2C3D4E5), OU = T1, O = Camille Exemple"
        self.assertEqual(mc.valeurs(sujet), self.attendus)

    def test_libressl(self):
        sujet = "subject= /UID=X1/CN=Apple Development: Camille Exemple (A1B2C3D4E5)/OU=T1/O=Camille Exemple/C=CH"
        self.assertEqual(mc.valeurs(sujet), self.attendus)

    def test_jamais_les_mots_du_metier(self):
        v = mc.valeurs("subject=CN=Apple Development: Camille Exemple (A1), O=Camille Exemple")
        self.assertFalse(v & mc.COMMUNS)
        self.assertNotIn("OU", " ".join(v))

    def test_sujet_vide(self):
        self.assertEqual(mc.valeurs(""), set())


if __name__ == "__main__":
    unittest.main()
