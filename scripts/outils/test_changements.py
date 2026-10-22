"""Tests de changements.py, sans réseau (l'API de GitHub est simulée), dans un dépôt git jetable. Valeurs inventées.

    python3 -m unittest discover -s scripts/outils -p 'test_*.py'
"""

import io
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))

import changements  # noqa: E402


class Motifs(unittest.TestCase):
    def test_hors_de_l_app(self):
        fichiers = ["scripts/outils/creatifs.py", "AppStore/entete.png", "README.md", "docs/contrat-relais.md",
                    ".github/workflows/testflight.yml", ".github/dependabot.yml"]
        self.assertEqual(changements.touches(fichiers, changements.HORS_APP), [])

    def test_l_app_et_tout_chemin_inconnu_comptent(self):
        fichiers = ["App/AlfredApp.swift", "AppTests/EnTeteTests.swift", ".github/workflows/ci.yml", "project.yml",
                    "scripts/generer.sh", "Paquets/AlfredKit/Sources/X.swift", "nouveau/fichier.txt"]
        self.assertEqual(changements.touches(fichiers, changements.HORS_APP), fichiers)

    def test_ce_qui_part_dans_l_app(self):
        tests_seuls = ["AppTests/EnTeteTests.swift", "AppUITests/ParcoursUITests.swift", ".github/workflows/ci.yml",
                       "Paquets/AlfredKit/Tests/T.swift", ".swift-format", "scripts/simulateur.sh"]
        self.assertEqual(changements.touches(tests_seuls, changements.HORS_FABRICATION), [])
        livre = ["App/Fonctions/Console/EnTete.swift", "Paquets/AlfredKit/Sources/X.swift", "Configuration/Base.xcconfig",
                 "scripts/generer.sh", "scripts/trousseau.sh", "project.yml"]
        self.assertEqual(changements.touches(livre, changements.HORS_FABRICATION), livre)


class BaseTestFlight(unittest.TestCase):
    A, B, C = "a" * 40, "b" * 40, "c" * 40

    def test_titre_d_abord_puis_head_sha(self):
        self.assertEqual(changements.sha_fabrique({"display_title": f"TestFlight {self.A}", "head_sha": self.B}), self.A)
        self.assertEqual(changements.sha_fabrique({"display_title": "TestFlight", "head_sha": self.B}), self.B)

    def test_derniere_reussie_sans_soi_ni_les_echecs_ni_les_plus_recentes_en_attente(self):
        runs = [
            {"id": 10, "created_at": "2026-10-22T13:00:00Z", "status": "queued", "display_title": f"TestFlight {self.C}"},
            {"id": 9, "created_at": "2026-10-22T12:00:00Z", "status": "in_progress", "display_title": f"TestFlight {self.C}"},
            {"id": 8, "created_at": "2026-10-22T11:00:00Z", "status": "completed", "conclusion": "failure",
             "display_title": f"TestFlight {self.B}"},
            {"id": 7, "created_at": "2026-10-22T10:00:00Z", "status": "completed", "conclusion": "success",
             "display_title": "TestFlight", "head_sha": self.A},
        ]
        self.assertEqual(changements.base_testflight(runs, moi=9), self.A)      # soi sauté, l'échec aussi
        # une exécution plus récente, en attente, n'est jamais la base (elle viserait un commit hors de l'historique)
        self.assertEqual(changements.base_testflight(runs, moi=11), self.A)
        self.assertIsNone(changements.base_testflight([], moi=1))


class Depot(unittest.TestCase):
    """Un vrai dépôt git : base → app → outils (hors app)."""

    def setUp(self):
        self.dossier = tempfile.TemporaryDirectory()
        self.ancien = os.getcwd()
        os.chdir(self.dossier.name)
        self.addCleanup(self.dossier.cleanup)
        self.addCleanup(os.chdir, self.ancien)
        env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t.invalid", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t.invalid"}
        identite = mock.patch.dict(os.environ, env)
        identite.start()
        self.addCleanup(identite.stop)
        subprocess.run(["git", "init", "-q", "-b", "main"], check=True)
        self.base = self.commit("App/A.swift", "1")
        self.app = self.commit("App/A.swift", "2")
        self.outils = self.commit("scripts/outils/x.py", "1")
        self.sortie = os.path.join(self.dossier.name, "sortie")

    def commit(self, chemin, contenu):
        os.makedirs(os.path.dirname(chemin), exist_ok=True)
        with open(chemin, "w") as f:
            f.write(contenu)
        subprocess.run(["git", "add", chemin], check=True)
        subprocess.run(["git", "commit", "-q", "-m", chemin], check=True)
        return subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()

    def ci(self, runs, evenement="push", ref="refs/heads/main", erreur=None):
        def faux_api(chemin):
            if erreur:
                raise erreur
            self.assertIn("status=success", chemin)
            return {"workflow_runs": runs}
        env = {"GITHUB_EVENT_NAME": evenement, "GITHUB_REF": ref, "GITHUB_OUTPUT": self.sortie}
        with mock.patch.dict(os.environ, env), mock.patch.object(changements, "api", faux_api), \
                redirect_stdout(io.StringIO()) as journal:
            changements.ci()
        with open(self.sortie) as f:
            return f.read().strip().splitlines()[-1], journal.getvalue()

    def test_seuls_les_outils_depuis_la_derniere_reussie(self):
        valeur, journal = self.ci([{"head_sha": self.app}])
        self.assertEqual(valeur, "app=false", journal)

    def test_base_plus_ancienne_que_le_commit_precedent(self):
        # l'Intégration de « app » a été annulée : la dernière RÉUSSIE est « base », donc l'app a changé
        valeur, journal = self.ci([{"head_sha": self.base}])
        self.assertEqual(valeur, "app=true")
        self.assertIn("App/A.swift", journal)

    def test_sans_base_certaine_tout_tourne(self):
        self.assertEqual(self.ci([])[0], "app=true")                                   # aucune réussie
        self.assertEqual(self.ci([{"head_sha": "d" * 40}])[0], "app=true")             # commit inconnu
        self.assertEqual(self.ci([{"head_sha": self.app}], evenement="pull_request")[0], "app=true")
        self.assertEqual(self.ci([{"head_sha": self.app}], ref="refs/tags/v1.0.0")[0], "app=true")
        self.assertEqual(self.ci([], erreur=OSError("muet"))[0], "app=true")

    def test_base_hors_de_l_historique(self):
        subprocess.run(["git", "checkout", "-q", "-b", "autre", self.base], check=True)
        cote = self.commit("App/B.swift", "1")
        subprocess.run(["git", "checkout", "-q", "main"], check=True)
        self.assertEqual(self.ci([{"head_sha": cote}])[0], "app=true")

    def test_testflight_tests_seuls_ne_fabriquent_pas(self):
        tests = self.commit("AppTests/T.swift", "1")
        runs = [{"id": 1, "created_at": "1", "status": "completed", "conclusion": "success",
                 "display_title": f"TestFlight {self.app}"}]
        with mock.patch.dict(os.environ, {"GITHUB_OUTPUT": self.sortie, "GITHUB_RUN_ID": "2"}), \
                mock.patch.object(changements, "api", lambda c: {"workflow_runs": runs}), redirect_stdout(io.StringIO()):
            changements.testflight(tests)
            self.assertEqual(open(self.sortie).read().strip().splitlines()[-1], "fabriquer=false")
            runs[0]["display_title"] = f"TestFlight {self.base}"                       # dernière fabrication avant « app »
            changements.testflight(tests)
            self.assertEqual(open(self.sortie).read().strip().splitlines()[-1], "fabriquer=true")
        with self.assertRaises(SystemExit):
            changements.testflight("pas-un-sha")


if __name__ == "__main__":
    unittest.main()
