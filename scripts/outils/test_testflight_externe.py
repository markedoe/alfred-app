"""Tests de testflight_externe.py, sans réseau (l'API d'App Store Connect est simulée). Valeurs inventées.

    python3 -m unittest discover -s scripts/outils -p 'test_*.py'
"""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))

CONTACT = {
    "prenom": "Camille",
    "nom": "Exemple",
    "email": "camille.exemple@example.com",
    "telephone": "+41000000000",
    "retours": "retours@example.com",
}
with mock.patch.dict(os.environ, {"ASC_CONTACT_REVUE": json.dumps(CONTACT)}):
    import testflight_externe as tf


class Expurger(unittest.TestCase):
    def test_valeurs_et_partie_locale(self):
        with mock.patch.dict(
            os.environ,
            {
                "ASC_CONTACT_REVUE": json.dumps(CONTACT),
                "ASC_TESTEURS": json.dumps([{"email": "dominique@example.com", "prenom": "Dominique", "nom": "X"}]),
            },
        ):
            v = tf.valeurs_personnelles()
        self.assertIn("camille.exemple@example.com", v)
        self.assertIn("camille.exemple", v)
        self.assertIn("Dominique", v)
        self.assertIn("+41000000000", v)

    def test_le_plus_long_d_abord(self):
        texte = "contactEmail camille.exemple@example.com invalide, Camille"
        self.assertEqual(
            tf.expurger(texte, {"camille.exemple@example.com", "camille.exemple", "Camille"}),
            "contactEmail *** invalide, ***",
        )

    def test_erreur_d_apple_expurgee(self):
        reponse = io.BytesIO(
            json.dumps(
                {"errors": [{"code": "ENTITY_ERROR", "title": "invalide", "detail": "+41000000000 refusé"}]}
            ).encode()
        )
        erreur = tf.urllib.error.HTTPError("https://x", 409, "conflit", {}, reponse)
        with (
            mock.patch.object(tf, "jeton", return_value="j"),
            mock.patch.dict(os.environ, {"ASC_CLE": "k", "ASC_CLE_ID": "i", "ASC_EMETTEUR_ID": "e"}),
            mock.patch.object(tf.urllib.request, "urlopen", side_effect=erreur),
        ):
            with self.assertRaises(tf.ErreurASC) as e:
                tf.api("PATCH", "/v1/betaAppReviewDetails/1", {})
        self.assertNotIn("+41000000000", str(e.exception))
        self.assertIn("*** refusé", str(e.exception))


class FausseAPI:
    """Rend des réponses d'App Store Connect selon (méthode, début du chemin) ; garde les appels."""

    def __init__(self, reponses):
        self.reponses = reponses
        self.appels = []

    def __call__(self, methode, chemin, corps=None):
        self.appels.append((methode, chemin, corps))
        for (m, debut), r in self.reponses.items():
            if m == methode and chemin.startswith(debut):
                if isinstance(r, Exception):
                    raise r
                return r
        raise AssertionError(f"appel inattendu : {methode} {chemin}")


def build(etat="VALID", audience="APP_STORE_ELIGIBLE", chiffrement=False):
    return {
        "data": [
            {
                "id": "b1",
                "type": "builds",
                "attributes": {
                    "version": "13",
                    "processingState": etat,
                    "expired": False,
                    "buildAudienceType": audience,
                    "usesNonExemptEncryption": chiffrement,
                },
                "relationships": {},
            }
        ],
        "included": [{"type": "preReleaseVersions", "attributes": {"version": "1.0.0"}}],
    }


BASE = {
    ("GET", "/v1/apps?"): {"data": [{"id": "a1", "attributes": {"primaryLocale": "fr-FR"}}]},
    ("GET", "/v1/betaGroups?"): {"data": [{"id": "g1", "attributes": {"name": tf.GROUPE}}]},
    ("GET", "/v1/builds/b1/betaBuildLocalizations"): {"data": []},
    ("POST", "/v1/betaBuildLocalizations"): {"data": {}},
    ("POST", "/v1/betaGroups/g1/relationships/builds"): None,
    ("GET", "/v1/builds/b1/buildBetaDetail"): {"data": {"id": "d1", "attributes": {"autoNotifyEnabled": True}}},
    ("PATCH", "/v1/buildBetaDetails/d1"): {"data": {}},
    ("POST", "/v1/betaAppReviewSubmissions"): {"data": {"attributes": {"betaReviewState": "WAITING_FOR_REVIEW"}}},
}


class Soumettre(unittest.TestCase):
    def lancer(self, reponses):
        faux = FausseAPI({**BASE, **reponses})
        sortie = io.StringIO()
        with mock.patch.object(tf, "api", faux), redirect_stdout(sortie):
            tf.soumettre("13", minutes=0)
        return faux, sortie.getvalue()

    def test_envoi_a_l_examen(self):
        faux, sortie = self.lancer(
            {("GET", "/v1/builds?"): build(), ("GET", "/v1/builds/b1/betaAppReviewSubmission"): {"data": None}}
        )
        self.assertIn(("POST", "/v1/betaGroups/g1/relationships/builds"), [(m, c) for m, c, _ in faux.appels])
        self.assertIn("WAITING_FOR_REVIEW", sortie)
        a_tester = next(corps for m, c, corps in faux.appels if (m, c) == ("POST", "/v1/betaBuildLocalizations"))
        self.assertEqual(a_tester["data"]["attributes"]["locale"], "fr-FR")
        self.assertEqual(a_tester["data"]["attributes"]["whatsNew"], tf.A_TESTER)

    def test_pas_d_e_mail_aux_testeurs(self):
        # 24.10 : autoNotifyEnabled mis à faux AVANT l'ajout au groupe externe (plus un e-mail par mise à jour)
        faux, sortie = self.lancer(
            {("GET", "/v1/builds?"): build(), ("GET", "/v1/builds/b1/betaAppReviewSubmission"): {"data": None}}
        )
        appels = [(m, c) for m, c, _ in faux.appels]
        patch = next(corps for m, c, corps in faux.appels if (m, c) == ("PATCH", "/v1/buildBetaDetails/d1"))
        self.assertIs(patch["data"]["attributes"]["autoNotifyEnabled"], False)
        self.assertLess(appels.index(("PATCH", "/v1/buildBetaDetails/d1")),
                        appels.index(("POST", "/v1/betaGroups/g1/relationships/builds")))
        self.assertIn("pas d'e-mail", sortie)

    def test_avertir_sur_demande(self):
        with mock.patch.dict(os.environ, {"ALFRED_AVERTIR_TESTEURS": "1"}):
            faux, sortie = self.lancer(
                {("GET", "/v1/builds?"): build(), ("GET", "/v1/builds/b1/betaAppReviewSubmission"): {"data": None}}
            )
        # déjà à vrai chez Apple : rien à changer
        self.assertNotIn(("PATCH", "/v1/buildBetaDetails/d1"), [(m, c) for m, c, _ in faux.appels])
        self.assertIn("avertis par e-mail", sortie)

    def test_examen_deja_demande(self):
        faux, sortie = self.lancer(
            {
                ("GET", "/v1/builds?"): build(),
                ("GET", "/v1/builds/b1/betaAppReviewSubmission"): {
                    "data": {"attributes": {"betaReviewState": "APPROVED"}}
                },
            }
        )
        self.assertNotIn("/v1/betaAppReviewSubmissions", [c for m, c, _ in faux.appels if m == "POST"])
        self.assertIn("déjà demandé : APPROVED", sortie)

    def test_examen_refuse_en_rouge(self):
        with self.assertRaises(SystemExit) as e:
            self.lancer(
                {
                    ("GET", "/v1/builds?"): build(),
                    ("GET", "/v1/builds/b1/betaAppReviewSubmission"): {
                        "data": {"attributes": {"betaReviewState": "REJECTED"}}
                    },
                }
            )
        self.assertIn("REFUSÉ", str(e.exception))

    def test_relance_deja_dans_le_groupe(self):
        faux, sortie = self.lancer(
            {
                ("GET", "/v1/builds?"): build(),
                ("POST", "/v1/betaGroups/g1/relationships/builds"): tf.ErreurASC(409, "déjà là"),
                ("GET", "/v1/builds/b1/betaAppReviewSubmission"): {"data": None},
            }
        )
        self.assertIn("déjà dans le groupe", sortie)
        self.assertIn("WAITING_FOR_REVIEW", sortie)

    def test_reservee_aux_internes(self):
        with self.assertRaises(SystemExit) as e:
            self.lancer({("GET", "/v1/builds?"): build(audience="INTERNAL_ONLY")})
        self.assertIn("testeurs internes", str(e.exception))

    def test_traitement_en_echec(self):
        with self.assertRaises(SystemExit) as e:
            self.lancer({("GET", "/v1/builds?"): build(etat="INVALID")})
        self.assertIn("en échec", str(e.exception))

    def test_conformite_absente(self):
        with self.assertRaises(SystemExit) as e:
            self.lancer({("GET", "/v1/builds?"): build(chiffrement=None)})
        self.assertIn("conformité", str(e.exception))


class Preparer(unittest.TestCase):
    def test_champ_manquant(self):
        incomplet = {k: v for k, v in CONTACT.items() if k != "telephone"}
        with mock.patch.dict(os.environ, {"ASC_CONTACT_REVUE": json.dumps(incomplet)}):
            with self.assertRaises(SystemExit) as e:
                tf.preparer()
        self.assertIn("telephone", str(e.exception))
        self.assertNotIn(CONTACT["email"], str(e.exception))

    def test_telephone_international(self):
        local = {**CONTACT, "telephone": "0000000000"}
        with mock.patch.dict(os.environ, {"ASC_CONTACT_REVUE": json.dumps(local)}):
            with self.assertRaises(SystemExit) as e:
                tf.preparer()
        self.assertIn("international", str(e.exception))
        self.assertNotIn("0000000000", str(e.exception))


if __name__ == "__main__":
    unittest.main()
