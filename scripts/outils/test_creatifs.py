"""Tests de creatifs.py, sans réseau (l'API d'App Store Connect est simulée). Valeurs inventées.

    python3 -m unittest discover -s scripts/outils -p 'test_*.py'
"""

import io
import os
import struct
import sys
import tempfile
import unittest
import zlib
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))

import creatifs  # noqa: E402

# creatifs importe testflight_externe, qui lit ses valeurs à masquer À L'IMPORT : le retirer, pour que
# test_testflight_externe le réimporte avec les siennes (sinon son test d'expurgation voit une liste vide)
sys.modules.pop("testflight_externe", None)


def png(largeur, hauteur, type_couleur=2, trns=False):
    def bloc(nom, donnees):
        return struct.pack(">I", len(donnees)) + nom + donnees + struct.pack(">I", zlib.crc32(nom + donnees))
    entete = struct.pack(">IIBBBBB", largeur, hauteur, 8, type_couleur, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + bloc(b"IHDR", entete) + (bloc(b"tRNS", b"\x00\x00") if trns else b"")
            + bloc(b"IDAT", zlib.compress(b"\x00")) + bloc(b"IEND", b""))


def jpeg(largeur, hauteur):
    app0 = b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00" + b"\x00" * 9
    sof = b"\xff\xc0" + struct.pack(">HBHHB", 11, 8, hauteur, largeur, 1) + b"\x01\x11\x00"
    return b"\xff\xd8" + app0 + sof + b"\xff\xd9"


SPEC_ENTETE = {"specId": "s-entete", "shortName": "i3840x1646a0",
               "dimensions": {"minWidth": 3840, "maxWidth": 3840, "minHeight": 1646, "maxHeight": 1646},
               "aspectRatio": "21:9", "alphaAllowed": False, "fileExtensions": [".jpg", ".jpeg", ".png"],
               "maxFileSize": 50_000_000, "universalAsset": False}
SPEC_RECHERCHE = {"specId": "s-recherche", "shortName": "i3840x2560a0",
                  "dimensions": {"minWidth": 1920, "maxWidth": 3840, "minHeight": 1280, "maxHeight": 2560},
                  "aspectRatio": "3:2", "alphaAllowed": False, "fileExtensions": [".jpg", ".jpeg", ".png"],
                  "maxFileSize": 50_000_000, "universalAsset": False}
REF = {
    "features": [{"featureId": "APP_STORE_VERSIONS", "placementPolicies": [
        {"placementTypeId": "PRODUCT_PAGE_HEADER_ASSET", "groupLimits": [{"placementGroupIds": ["UNIVERSAL"], "maxCount": 1}]},
        {"placementTypeId": "APP_STORE_SEARCH_RESULTS_ASSET", "groupLimits": [{"placementGroupIds": ["UNIVERSAL"], "maxCount": 1}]}]}],
    "placementTypes": [
        {"placementTypeId": "PRODUCT_PAGE_HEADER_ASSET", "acceptsAssetCategories": ["CREATIVE_ASSETS"],
         "specMappings": [{"placementGroupId": "UNIVERSAL", "specs": ["s-entete"]}]},
        {"placementTypeId": "APP_STORE_SEARCH_RESULTS_ASSET", "acceptsAssetCategories": ["CREATIVE_ASSETS"],
         "specMappings": [{"placementGroupId": "UNIVERSAL", "specs": ["s-recherche"]}]}],
    "imageSpecs": [SPEC_ENTETE, SPEC_RECHERCHE],
}


class Fichiers(unittest.TestCase):
    def test_png_sans_et_avec_transparence(self):
        self.assertEqual(creatifs.dimensions_png(png(3840, 1646)), (3840, 1646, False))
        self.assertEqual(creatifs.dimensions_png(png(10, 20, type_couleur=6)), (10, 20, True))
        self.assertEqual(creatifs.dimensions_png(png(10, 20, trns=True)), (10, 20, True))
        with self.assertRaises(ValueError):
            creatifs.dimensions_png(b"pas une image")

    def test_jpeg(self):
        self.assertEqual(creatifs.dimensions_jpeg(jpeg(3840, 2560)), (3840, 2560, False))
        with self.assertRaises(ValueError):
            creatifs.dimensions_jpeg(png(1, 1))


class Formats(unittest.TestCase):
    def test_lus_dans_les_donnees_de_reference(self):
        f = creatifs.formats(REF, "PRODUCT_PAGE_HEADER_ASSET")
        self.assertEqual(f["categories"], ["CREATIVE_ASSETS"])
        self.assertEqual(f["plafonds"], {"UNIVERSAL": 1})
        self.assertEqual([s["specId"] for s in f["groupes"]["UNIVERSAL"]], ["s-entete"])

    def test_accepte_dimensions_extension_transparence(self):
        f = {"largeur": 3840, "hauteur": 1646, "ext": ".png", "alpha": False, "taille": 1000}
        self.assertTrue(creatifs.accepte(SPEC_ENTETE, f))
        self.assertFalse(creatifs.accepte(SPEC_ENTETE, dict(f, alpha=True)))
        self.assertFalse(creatifs.accepte(SPEC_ENTETE, dict(f, hauteur=1645)))
        self.assertFalse(creatifs.accepte(SPEC_ENTETE, dict(f, ext=".webp")))
        self.assertTrue(creatifs.accepte(SPEC_RECHERCHE, dict(f, largeur=2400, hauteur=1600)))


class Deposer(unittest.TestCase):
    def setUp(self):
        self.dossier = tempfile.TemporaryDirectory()
        self.entete = os.path.join(self.dossier.name, "entete.png")
        with open(self.entete, "wb") as f:
            f.write(png(3840, 1646))
        self.appels = []

    def tearDown(self):
        self.dossier.cleanup()

    def faux_api(self, methode, chemin, corps=None):
        self.appels.append((methode, chemin.split("?")[0], corps))
        if chemin.startswith("/v1/apps?"):
            return {"data": [{"id": "app1", "attributes": {"bundleId": creatifs.__dict__.get("BUNDLE", "x")}}]}
        if chemin == "/v1/appAssetLibraryRefData":
            return {"data": [{"attributes": REF}]}
        if chemin == "/v1/apps/app1/assetLibrary":
            return {"data": {"id": "bib1"}}
        if methode == "POST" and chemin == "/v1/appAssetLibraryImages":
            return {"data": {"id": "img1", "attributes": {"uploadOperations": [
                {"method": "PUT", "url": "https://televersement.example/1", "offset": 0, "length": 8,
                 "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}]}}}
        if methode == "GET" and chemin == "/v1/appAssetLibraryImages/img1":
            return {"data": {"attributes": {"state": "PREPARE_FOR_SUBMISSION",
                                            "imageAsset": {"width": 3840, "height": 1646}}}}
        if methode == "POST" and chemin == "/v1/appAssetLibraryPlacements":
            return {"data": {"attributes": {"state": "PARENT_PREPARE_FOR_SUBMISSION"}}}
        return None

    def faux_lister(self, chemin):
        self.appels.append(("LIST", chemin.split("?")[0], None))
        if chemin.startswith("/v1/apps/app1/appStoreVersions"):
            return [{"id": "v1", "attributes": {"versionString": "1.0.0", "appVersionState": "PREPARE_FOR_SUBMISSION"}},
                    {"id": "v0", "attributes": {"versionString": "0.9", "appVersionState": "READY_FOR_DISTRIBUTION"}}]
        if chemin.startswith("/v1/appStoreVersions/v1/appStoreVersionLocalizations"):
            return [{"id": "loc-fr", "attributes": {"locale": "fr-FR"}}]
        if chemin.startswith("/v1/appStoreVersionLocalizations/loc-fr/placements"):
            return [{"id": "ancien", "attributes": {"placementGroup": "UNIVERSAL"}}]
        return []

    def test_depose_place_et_remplace_sans_examen(self):
        envois = []

        class Reponse(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        def faux_urlopen(requete, timeout=0):
            envois.append((requete.get_method(), requete.full_url, len(requete.data), requete.headers))
            self.assertNotIn("Authorization", requete.headers)          # adresse d'envoi : jamais le jeton
            return Reponse(b"")

        with mock.patch.object(creatifs, "api", self.faux_api), mock.patch.object(creatifs, "lister", self.faux_lister), \
                mock.patch.object(creatifs, "appli", lambda: {"id": "app1", "attributes": {}}), \
                mock.patch.object(creatifs.urllib.request, "urlopen", faux_urlopen), redirect_stdout(io.StringIO()):
            creatifs.deposer({"entete": self.entete})
        self.assertEqual([(m, u, n) for m, u, n, _ in envois], [("PUT", "https://televersement.example/1", 8)])
        reservation = next(c for m, ch, c in self.appels if m == "POST" and ch == "/v1/appAssetLibraryImages")
        self.assertEqual(reservation["data"]["attributes"]["category"], "CREATIVE_ASSETS")
        self.assertIn(("PATCH", "/v1/appAssetLibraryImages/img1",
                       {"data": {"type": "appAssetLibraryImages", "id": "img1", "attributes": {"uploaded": True}}}),
                      self.appels)
        self.assertIn(("DELETE", "/v1/appAssetLibraryPlacements/ancien", None), self.appels)
        place = next(c for m, ch, c in self.appels if m == "POST" and ch == "/v1/appAssetLibraryPlacements")
        self.assertEqual(place["data"]["attributes"], {"placementType": "PRODUCT_PAGE_HEADER_ASSET",
                                                       "placementGroup": "UNIVERSAL"})
        self.assertEqual(place["data"]["relationships"]["appStoreVersionLocalization"]["data"]["id"], "loc-fr")
        self.assertFalse([c for c in self.appels if "reviewSubmission" in c[1]])     # rien envoyé à l'examen

    def test_format_refuse_avant_tout_envoi(self):
        with open(self.entete, "wb") as f:
            f.write(png(3840, 1646, type_couleur=6))                       # transparence : refusée
        with mock.patch.object(creatifs, "api", self.faux_api), mock.patch.object(creatifs, "lister", self.faux_lister), \
                mock.patch.object(creatifs, "appli", lambda: {"id": "app1", "attributes": {}}), \
                self.assertRaises(SystemExit):
            creatifs.deposer({"entete": self.entete})
        self.assertFalse([c for c in self.appels if c[0] in ("POST", "PATCH", "DELETE")])

    def test_une_seule_version_modifiable(self):
        def deux(chemin):
            return [{"id": "a", "attributes": {"appVersionState": "PREPARE_FOR_SUBMISSION"}},
                    {"id": "b", "attributes": {"appVersionState": "REJECTED"}}]
        with mock.patch.object(creatifs, "lister", deux), self.assertRaises(SystemExit):
            creatifs.modifiable("app1")


if __name__ == "__main__":
    unittest.main()
