import UIKit
import XCTest

/// Les parcours principaux, sur la maison de démonstration (aucun réseau, aucun micro) : écrire à Alfred et lire sa
/// réponse dans les échanges ; allumer une pièce depuis la roue, l'état affiché étant celui que la maison confirme ;
/// les fenêtres de l'en-tête (documents, notifications, autres systèmes, réglages) ; l'audit d'accessibilité d'Apple
/// sur chaque vue et chaque fenêtre ; la disposition large (iPad à l'horizontale). Des captures sont jointes au
/// résultat : elles se comparent à celles de la console web vue connecté (relecture du design).
@MainActor
final class ParcoursUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Toujours sans animations (« -sansAnimations ») : l'audit et les mesures lisent l'état final, et XCTest sait
    /// quand l'app est au repos (le réacteur, animé sans fin, l'en empêche sinon).
    private func lancer(tailleTexte: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH", "-sansAnimations"]
        if let tailleTexte { app.launchArguments += ["-UIPreferredContentSizeCategoryName", tailleTexte] }
        app.launch()
        return app
    }

    /// La démo est prête (« Parler à Alfred » actif) : l'audit porte sur l'état stable, pas sur le démarrage. Jusqu'à
    /// 30 s : sur les Mac de la CI, le simulateur met parfois 20 s à lancer l'app (vidéos des tests), et le test attend
    /// alors un bouton déjà affiché.
    private func attendrePret(_ app: XCUIApplication) {
        let parler = bouton(app, "parler")
        XCTAssertTrue(parler.waitForExistence(timeout: 30))
        let actif = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: parler)
        XCTAssertEqual(XCTWaiter().wait(for: [actif], timeout: 30), .completed, "la démo ne devient pas prête")
    }

    /// Un élément dont le libellé d'accessibilité contient ce texte, sans tenir compte de la casse : les titres de la
    /// console sont en capitales (« EXTÉRIEUR »), et les messages regroupent leurs textes.
    private func element(_ app: XCUIApplication, contenant texte: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", texte)).firstMatch
    }

    private func bouton(_ app: XCUIApplication, _ identifiant: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@", identifiant)).firstMatch
    }

    private func capturer(_ app: XCUIApplication, _ nom: String) {
        let c = XCTAttachment(screenshot: app.screenshot())
        c.name = nom
        c.lifetime = .keepAlways
        add(c)
    }

    /// Choisir une vue de la console (sur téléphone ; en disposition large, toutes sont visibles).
    private func vue(_ app: XCUIApplication, _ nom: String) {
        let onglet = bouton(app, "onglet-\(nom)")
        if onglet.exists { onglet.tap() }
    }

    func testEcrireAAlfred() throws {
        let app = lancer()
        attendrePret(app)
        capturer(app, "1-pieces")
        bouton(app, "ecrire").tap()
        let saisie = app.textFields["saisie"]
        XCTAssertTrue(saisie.waitForExistence(timeout: 5))
        saisie.tap()
        // la touche « envoyer » du clavier envoie (revue du 18.10, point 16)
        saisie.typeText("Allume la cuisine\n")
        // comme la console : l'envoi ferme la saisie et montre les échanges
        XCTAssertTrue(app.staticTexts["briefing"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            element(app, contenant: "C’est fait : j’ai allumé la pièce Cuisine.").waitForExistence(timeout: 10))
        // les badges de la console sous la réponse : sa durée, « llm », le nombre d'outils
        XCTAssertTrue(element(app, contenant: "1 outil").waitForExistence(timeout: 5))
        capturer(app, "2-alfred-echanges")
        // « Détails techniques », replié comme dans la console : l'outil, ses arguments, fait
        app.buttons["Détails techniques"].firstMatch.tap()
        XCTAssertTrue(element(app, contenant: "HassTurnOn, Cuisine").waitForExistence(timeout: 5))
        capturer(app, "2b-details-techniques")
        vue(app, "environnement")
        XCTAssertTrue(element(app, contenant: "Extérieur").waitForExistence(timeout: 5))
        capturer(app, "3-environnement")
    }

    /// Le clavier s'ouvre puis se ferme : la roue ne bouge pas (les jauges ne dépendent pas de la hauteur que le
    /// clavier laisse ; revue du 18.10, point 12).
    func testClavierSansSaut() throws {
        let app = lancer()
        attendrePret(app)
        let atelier = bouton(app, "piece-Atelier")
        XCTAssertTrue(atelier.waitForExistence(timeout: 10))
        // ce qui bouge, s'il y a lieu : l'en-tête, la pièce, « Parler », les onglets (dans le message d'échec)
        let reperes = ["reglages", "piece-Atelier", "parler", "onglet-pieces"].map { bouton(app, $0) }
        func positions() -> String {
            reperes.map { "\($0.identifier) \(Int($0.frame.minY))-\(Int($0.frame.maxY))" }.joined(separator: ", ")
        }
        let jauges = app.descendants(matching: .any).matching(identifier: "jauge")
        let nombreDeJauges = jauges.count
        XCTAssertGreaterThan(nombreDeJauges, 0, "les jauges de la console")
        let avant = atelier.frame
        let positionsAvant = positions()
        capturer(app, "clavier-1-avant")
        bouton(app, "ecrire").tap()
        XCTAssertTrue(app.textFields["saisie"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "le clavier ne s'ouvre pas")
        capturer(app, "clavier-2-ouvert")
        XCTAssertEqual(jauges.count, nombreDeJauges, "les jauges disparaissent quand le clavier s'ouvre")
        XCTAssertEqual(
            atelier.frame.minY, avant.minY, accuracy: 1,
            "la roue saute à l'ouverture du clavier : avant \(positionsAvant) ; après \(positions())")
        app.buttons["Fermer la saisie"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        capturer(app, "clavier-3-ferme")
        XCTAssertEqual(
            atelier.frame.minY, avant.minY, accuracy: 1,
            "la roue saute à la fermeture du clavier : avant \(positionsAvant) ; après \(positions())")
    }

    /// Échap (clavier de l'iPad, Mac) ferme, comme la console : la saisie, puis la pièce (revue du 18.10, point 13).
    func testEchap() throws {
        let app = lancer()
        attendrePret(app)
        let atelier = bouton(app, "piece-Atelier")
        XCTAssertTrue(atelier.waitForExistence(timeout: 10))
        // d'abord la pièce seule : si la touche n'y arrive pas, c'est le simulateur (pas de clavier matériel)
        atelier.tap()
        XCTAssertTrue(bouton(app, "actionPiece").waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        if !bouton(app, "actionPiece").waitForNonExistence(timeout: 3) {
            throw XCTSkip("Échap : la touche n'arrive pas à l'app sur ce simulateur (pas de clavier matériel)")
        }
        // la touche arrive : la saisie (champ actif), puis la pièce
        atelier.tap()
        XCTAssertTrue(bouton(app, "actionPiece").waitForExistence(timeout: 5))
        bouton(app, "ecrire").tap()
        XCTAssertTrue(app.textFields["saisie"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textFields["saisie"].waitForNonExistence(timeout: 3), "Échap : la saisie d'abord")
        XCTAssertTrue(bouton(app, "actionPiece").exists, "la pièce reste ouverte")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(bouton(app, "actionPiece").waitForNonExistence(timeout: 5), "Échap : puis la pièce")
    }

    func testAllumerUnePiece() throws {
        let app = lancer()
        attendrePret(app)
        let atelier = bouton(app, "piece-Atelier")
        XCTAssertTrue(atelier.waitForExistence(timeout: 10))
        XCTAssertTrue((atelier.value as? String ?? "").contains("éteinte"), "\(atelier.value ?? "")")
        atelier.tap()
        let action = bouton(app, "actionPiece")
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, "Allumer")
        capturer(app, "4-carte-piece")
        action.tap()
        // l'état affiché est celui que la maison confirme
        let etat = app.staticTexts["etatPiece"]
        let allumee = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Lumière allumée"), object: etat)
        XCTAssertEqual(XCTWaiter().wait(for: [allumee], timeout: 10), .completed, "la maison n'a pas confirmé")
        XCTAssertEqual(action.label, "Éteindre")
        XCTAssertTrue((atelier.value as? String ?? "").contains("allumée"), "\(atelier.value ?? "")")
        capturer(app, "5-piece-allumee")
    }

    func testAccessibilite() throws {
        let app = lancer()
        attendrePret(app)
        try auditerEcrans(app, ["Pièces", "Alfred", "Environnement", "Documents", "Notifications", "Réglages"])
    }

    /// Les fenêtres de l'en-tête, comme la console connectée : les documents déposés, les notifications (marquées lues
    /// à l'ouverture), les autres systèmes, les réglages et l'état de la maison.
    func testFenetresDeLEnTete() throws {
        let app = lancer()
        attendrePret(app)
        let fermer = bouton(app, "fermerFenetre")

        let documents = bouton(app, "documents")
        XCTAssertTrue(documents.waitForExistence(timeout: 10))
        // 23.10 (la boîte d'arrivée) : la pastille ne compte que ce qui demande une action (le refus de la démo)
        XCTAssertTrue(documents.label.contains("1 à traiter"), documents.label)
        documents.tap()
        // 23.10 (soir) : « À envoyer » vide, le bouton d'envoi désactivé, le refus de la démo dans « À revoir »
        XCTAssertTrue(element(app, contenant: "Aucun document à envoyer.").waitForExistence(timeout: 5))
        let envoyer = bouton(app, "envoyerPaperless")
        XCTAssertTrue(envoyer.exists && !envoyer.isEnabled, "aucun fichier : « Envoyer à Paperless (0) » désactivé")
        XCTAssertTrue(element(app, contenant: "Refusé : aucun texte lisible").exists)
        XCTAssertTrue(element(app, contenant: "Ajouter des documents").exists)
        // plus de « Supprimer » sur un document rangé
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Supprimer ")).firstMatch.exists)
        // « Retirer » se touche sur 44 pt au moins, pas seulement sur son texte (revue du 18.10, point 15)
        let retirer = app.buttons["Retirer Photo floue d’exemple"]
        XCTAssertTrue(retirer.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(retirer.frame.height, 44, "cible de « Retirer »")
        XCTAssertGreaterThanOrEqual(retirer.frame.width, 44, "cible de « Retirer »")
        XCTAssertTrue(app.buttons["Réessayer Photo floue d’exemple"].exists)
        capturer(app, "6-documents")
        fermer.tap()

        let notifications = bouton(app, "notifications")
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        XCTAssertTrue(notifications.label.contains("1 non lue"), notifications.label)
        notifications.tap()
        XCTAssertTrue(element(app, contenant: "la lessive est terminée").waitForExistence(timeout: 5))
        capturer(app, "7-notifications")
        fermer.tap()
        // lues à l'ouverture : le compteur disparaît
        let lues = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Notifications"), object: notifications)
        XCTAssertEqual(XCTWaiter().wait(for: [lues], timeout: 20), .completed, "notifications non marquées lues")

        bouton(app, "liens").tap()
        XCTAssertTrue(element(app, contenant: "Paperless").waitForExistence(timeout: 5))
        capturer(app, "8-autres-systemes")
        // un toucher ailleurs referme la liste
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)).tap()
        XCTAssertFalse(element(app, contenant: "Paperless").waitForExistence(timeout: 1))

        bouton(app, "reglages").tap()
        XCTAssertTrue(element(app, contenant: "demo").waitForExistence(timeout: 5), "le modèle du pipeline")
        XCTAssertTrue(element(app, contenant: "Tester le micro").exists)
        capturer(app, "9-reglages")
        fermer.tap()

        vue(app, "environnement")
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["etatServices"].waitForExistence(timeout: 5))
        capturer(app, "10-etat-des-services")
    }

    /// L'en-tête tient dans la largeur de l'écran : la marque dans la marge, puis chaque bouton entier, d'au moins
    /// 44 pt, sans chevaucher le précédent, le dernier en deçà de la marge de droite. La CI le passe aussi sur le plus
    /// étroit des iPhone disponibles, avec la largeur à ne pas dépasser (`ALFRED_LARGEUR_MAX`) : un iPhone trop large
    /// ferait échouer le test plutôt que de vérifier autre chose.
    func testEnTete() throws {
        let app = lancer()
        attendrePret(app)
        let largeur = app.frame.width
        if let max = ProcessInfo.processInfo.environment["ALFRED_LARGEUR_MAX"].flatMap(Double.init) {
            XCTAssertLessThanOrEqual(largeur, max, "écran de \(largeur) pt : pas le plus étroit des iPhone visés")
        }
        capturer(app, "entete-\(Int(largeur))pt")
        let marque = app.descendants(matching: .any)["marque"]
        XCTAssertTrue(marque.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(marque.frame.minX, 16 - 0.5, "marque hors de la marge : \(marque.frame)")
        var precedent = marque.frame
        for id in ["documents", "notifications", "reglages", "liens", "compte"] {
            let b = bouton(app, id)
            XCTAssertTrue(b.exists, id)
            let f = b.frame
            XCTAssertGreaterThanOrEqual(min(f.width, f.height), 44 - 0.5, "« \(id) » : cible de \(f.size)")
            XCTAssertGreaterThanOrEqual(f.minX, precedent.maxX - 0.5, "« \(id) » \(f) chevauche \(precedent)")
            // la cible du compte déborde de 5 pt dans la marge de 16 pt : son cadre de 34 pt s'arrête à la marge
            XCTAssertLessThanOrEqual(f.maxX, largeur - 11 + 0.5, "« \(id) » \(f) sort de l'écran de \(largeur) pt")
            precedent = f
        }
    }

    /// La disposition large de la console (iPad à l'horizontale, Mac) : l'assistant, la roue, l'environnement et le
    /// bas, côte à côte. Ne tourne que sur iPad (la CI le lance sur un simulateur d'iPad).
    func testDispositionLarge() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "disposition large : iPad seulement")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = lancer()
        attendrePret(app)
        XCTAssertFalse(bouton(app, "onglet-pieces").exists, "pas d'onglets en disposition large")
        XCTAssertTrue(element(app, contenant: "Extérieur").exists)
        capturer(app, "ipad-1-large")
        bouton(app, "piece-Salon").tap()
        XCTAssertTrue(bouton(app, "actionPiece").waitForExistence(timeout: 5))
        capturer(app, "ipad-2-piece")
        // à l'horizontale, la capture de l'écran sort tournée (mesuré : « ipad-2-piece », l'interface couchée et une bande
        // noire) ; l'audit y juge le contraste sur les mauvais points, et signale des textes à 8:1 : il est fait sur
        // iPhone (mêmes vues, mêmes couleurs), tout le reste est audité ici
        try auditerEcrans(
            app, ["Large"], types: XCUIAccessibilityAuditType.all.subtracting([.dynamicType, .contrast]),
            sansElementEcarte: true)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(bouton(app, "onglet-pieces").waitForExistence(timeout: 5), "onglets en disposition étroite")
        capturer(app, "ipad-3-portrait")
    }

    /// La plus grande taille de texte : le texte grandit vraiment (mesuré), et des captures de chaque vue sont
    /// jointes pour la relecture (rien n'est coupé, tout reste atteignable).
    ///
    /// La taille du texte se vérifie ici plutôt que par l'audit : sa sonde perd les éléments poussés hors de la vue
    /// quand le texte grandit. Les textes de l'app suivent tous la taille choisie, sauf ceux dessinés dans la roue (le
    /// nom et la température d'une pièce, à la taille du secteur) et l'en-tête, plafonné : chaque pièce garde son nom
    /// et sa valeur pour VoiceOver, et la vue Environnement les donne en texte.
    func testGrandTexte() throws {
        let normal = hauteurs(lancer())
        let app = lancer(tailleTexte: "UICTContentSizeCategoryAccessibilityXXXL")
        let grand = hauteurs(app, captures: true)
        for (nom, h) in normal {
            let g = try XCTUnwrap(grand[nom], nom)
            XCTAssertGreaterThan(g, h * 1.5, "« \(nom) » ne grandit pas avec le texte (\(h) → \(g) pt)")
        }
    }

    /// La hauteur d'un texte en haut de chaque vue (toujours visible, quelle que soit la taille du texte).
    private func hauteurs(_ app: XCUIApplication, captures: Bool = false) -> [String: CGFloat] {
        var h: [String: CGFloat] = [:]
        attendrePret(app)
        // à la plus grande taille : chaque écran capturé est aussi vérifié en LARGEUR (rien ne sort par le côté)
        func capturerEtVerifier(_ nom: String) {
            capturer(app, nom)
            horsEcran(app, nom)
        }
        if captures {
            capturerEtVerifier("grand-texte-1-pieces")
            // la carte d'une pièce : elle défile au lieu de passer sous l'en-tête (revue du 18.10, point 17)
            bouton(app, "piece-Atelier").tap()
            XCTAssertTrue(app.descendants(matching: .any)["cartePiece"].waitForExistence(timeout: 5))
            capturerEtVerifier("grand-texte-1b-carte-piece")
            app.buttons["Fermer la pièce"].firstMatch.tap()
            // la saisie : le champ sur sa ligne, assez large pour lire ce qu'on écrit (revue du 21.10, ATTENTION 10)
            bouton(app, "ecrire").tap()
            let saisie = app.textFields["saisie"]
            XCTAssertTrue(saisie.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(saisie.frame.width, app.frame.width * 0.6, "le champ de saisie est écrasé")
            capturerEtVerifier("grand-texte-1c-saisie")
            app.buttons["Fermer la saisie"].tap()
        }
        vue(app, "alfred")
        let briefing = app.staticTexts["briefing"]
        XCTAssertTrue(briefing.waitForExistence(timeout: 5))
        h["briefing"] = briefing.frame.height
        if captures { capturerEtVerifier("grand-texte-2-alfred") }
        vue(app, "environnement")
        let exterieur = element(app, contenant: "Extérieur")
        XCTAssertTrue(exterieur.waitForExistence(timeout: 5))
        h["Extérieur"] = exterieur.frame.height
        if captures {
            capturerEtVerifier("grand-texte-3-environnement")
            app.swipeUp()
            capturerEtVerifier("grand-texte-4-environnement-suite")
        }
        bouton(app, "reglages").tap()
        let modele = element(app, contenant: "Modèle")
        XCTAssertTrue(modele.waitForExistence(timeout: 5))
        h["Modèle"] = modele.frame.height
        if captures {
            capturerEtVerifier("grand-texte-5-reglages")
            app.swipeUp()
            capturerEtVerifier("grand-texte-6-reglages-suite")
            app.swipeUp()
            capturerEtVerifier("grand-texte-7-reglages-fin")
        }
        // 23.10 : le champ « Ajouter une étiquette » des Documents — l'audit d'Apple y prédit un texte coupé aux grandes
        // tailles ; sa hauteur MESURÉE doit grandir avec le texte (sinon l'audit avait raison), capture à l'appui
        bouton(app, "fermerFenetre").tap()
        vue(app, "pieces")
        bouton(app, "documents").tap()
        let etiquette = app.textFields["etiquette"]
        XCTAssertTrue(etiquette.waitForExistence(timeout: 5))
        h["etiquette"] = etiquette.frame.height
        if captures { capturerEtVerifier("grand-texte-8-documents") }
        return h
    }

    /// Un texte ou un bouton visible en hauteur mais coupé par le côté de l'écran : ni l'audit d'Apple ni les hauteurs
    /// ne le voient, la capture si (les Réglages débordaient à gauche en très grand texte, revue du 18.10). Une seule
    /// lecture de l'arbre (rapide), puis les cadres.
    private func horsEcran(_ app: XCUIApplication, _ ecran: String) {
        let largeur = app.frame.width
        let hauteur = app.frame.height
        guard let racine = try? app.snapshot() else {
            XCTFail("\(ecran) : arbre des éléments illisible")
            return
        }
        var fautes: [String] = []
        func parcourir(_ e: XCUIElementSnapshot) {
            let f = e.frame
            if [.staticText, .button].contains(e.elementType), f.width > 0, f.height > 0, f.maxY > 0, f.minY < hauteur,
                f.minX < -0.5 || f.maxX > largeur + 0.5
            {
                fautes.append("« \(e.label) » de \(Int(f.minX)) à \(Int(f.maxX))")
            }
            e.children.forEach(parcourir)
        }
        parcourir(racine)
        XCTAssert(
            fautes.isEmpty, "\(ecran) : sort de l'écran (\(Int(largeur)) pt) : " + fautes.joined(separator: " ; "))
    }

    /// L'accueil (sans la démo) : le motif d'une déconnexion se voit sans défiler, sous la marque, et rien ne sort de
    /// l'écran, à la taille normale comme en très grand texte (revue du 18.10, point 18 ; du 21.10, ATTENTION 9).
    func testAccueil() throws {
        for taille in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH", "-sansAnimations", "-motifAccueil",
                Self.motifExpire,
            ]
            if let taille { app.launchArguments += ["-UIPreferredContentSizeCategoryName", taille] }
            app.launch()
            // une fabrication sans configuration demande d'abord l'adresse du relais (gardée ensuite)
            let adresse = app.textFields["adresseRelais"]
            if adresse.waitForExistence(timeout: 5) {
                adresse.tap()
                adresse.typeText("relais.maison.example\n")
            }
            let motif = app.staticTexts["motifAccueil"]
            XCTAssertTrue(motif.waitForExistence(timeout: 10))
            XCTAssertTrue(motif.isHittable, "le motif est caché")
            if taille == nil {
                let connexion = bouton(app, "seConnecter")
                XCTAssertTrue(connexion.exists)
                XCTAssertLessThan(motif.frame.maxY, connexion.frame.minY, "le motif passe sous la connexion")
            }
            capturer(app, taille == nil ? "11-accueil" : "grand-texte-8-accueil")
            horsEcran(app, taille == nil ? "accueil" : "accueil (très grand texte)")
            app.terminate()
        }
    }

    private static let motifExpire = "Votre connexion à la maison a expiré. Reconnectez-vous."

    /// Un élément coupé par le bord d'une zone qui défile (en partie dans la vue, en partie dessous).
    private static func enPartieCache(_ e: XCUIElement, dans app: XCUIApplication) -> Bool {
        let cadre = e.frame
        return app.scrollViews.allElementsBoundByIndex.contains { zone in
            zone.frame.intersects(cadre) && !zone.frame.contains(cadre)
        }
    }

    private static let engagementMicro =
        "Le micro ne s’ouvre que pendant une conversation, et jamais en arrière-plan."
    /// 23.10 : le champ des étiquettes des Documents (« texte coupé » prédit ; sa hauteur en très grand texte est
    /// mesurée par `testGrandTexte`, capture « grand-texte-8-documents »).
    private static let champEtiquette = "Ajouter une étiquette"

    /// Les vues de la console et les réglages, chacune auditée en entier (sauf la taille du texte : voir
    /// `testGrandTexte`) : tous les problèmes sont listés dans UN échec, avec la vue, le type de problème, l'élément
    /// et sa place. Deux cas sont écartés, et listés à part (pièce jointe « audit-ecartes ») :
    /// - « texte coupé » prédit pour l'engagement du micro, démenti par la capture « grand-texte-7-reglages-fin » (le
    ///   texte passe à la ligne jusqu'au bout, rien n'est coupé), et pour le champ des étiquettes des Documents,
    ///   démenti par sa hauteur mesurée en très grand texte (`testGrandTexte`, capture « grand-texte-8-documents ») ;
    /// - le contraste d'un texte hors de la vue (sous le bord d'un panneau qui défile, sous la carte d'une pièce).
    ///
    /// Le nom et la température des pièces, l'heure et l'état du noyau sont dessinés dans la roue, comme dans la
    /// console : ce ne sont pas des éléments d'accessibilité (chaque secteur porte sa pièce, son état et sa
    /// température ; l'état de la conversation est sur « Parler à Alfred » et la ligne d'état).
    /// `sansElementEcarte` (disposition large) : un « texte coupé » que l'audit ne rattache à aucun élément est écarté,
    /// listé à part. Il ne peut pas être situé ; les mêmes vues passent l'audit complet sur iPhone, et les deux groupes
    /// propres à la disposition large (l'étiquette « LIEN », la consommation) gardent la taille de la console.
    private func auditerEcrans(
        _ app: XCUIApplication, _ ecrans: [String],
        types: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting(.dynamicType),
        sansElementEcarte: Bool = false
    ) throws {
        var problemes: [String] = []
        var ecartes: [String] = []
        for ecran in ecrans {
            // une fenêtre restée ouverte (l'écran d'avant) se ferme d'abord
            if bouton(app, "fermerFenetre").exists { bouton(app, "fermerFenetre").tap() }
            switch ecran {
            case "Alfred": vue(app, "alfred")
            case "Environnement": vue(app, "environnement")
            case "Documents", "Notifications", "Réglages":
                vue(app, "pieces")
                bouton(app, ["Documents": "documents", "Notifications": "notifications"][ecran] ?? "reglages").tap()
                XCTAssertTrue(bouton(app, "fermerFenetre").waitForExistence(timeout: 5))
            default: vue(app, "pieces")
            }
            // l'audit relève, le tri vient après (une capture ou une requête pendant l'audit le ralentit)
            var signales: [XCUIAccessibilityAuditIssue] = []
            try app.performAccessibilityAudit(for: types) { probleme in
                signales.append(probleme)
                return true
            }
            // les contrastes contestés se mesurent sur UNE capture de l'écran audité
            var capture: Capture?
            if signales.contains(where: { $0.auditType == .contrast }) { capture = Capture(app) }
            for probleme in signales {
                let description =
                    "\(ecran) · \(probleme.compactDescription) · "
                    + (probleme.element.map { "« \($0.label) » \(Int($0.frame.minY))…\(Int($0.frame.maxY)) pt" }
                        ?? "sans élément (\(probleme.debugDescription))")
                    + " · \(probleme.detailedDescription)"
                if probleme.auditType == .textClipped,
                    probleme.element?.label == Self.engagementMicro || probleme.element?.label == Self.champEtiquette
                {
                    // démentis par testGrandTexte : capture et hauteur mesurée en très grand texte
                    ecartes.append("vérifié en très grand texte · " + description)
                } else if sansElementEcarte, probleme.auditType == .textClipped, probleme.element == nil {
                    ecartes.append("sans élément, disposition large · " + description)
                } else if probleme.auditType == .contrast, let e = probleme.element,
                    !e.isHittable || Self.enPartieCache(e, dans: app)
                {
                    // hors de la vue : sous le bord d'un panneau qui défile, ou sous la carte d'une pièce ; un texte
                    // qu'on ne voit pas ne se juge pas sur ce qui le recouvre (il l'est une fois amené dans la vue)
                    ecartes.append("hors de la vue · " + description)
                } else if probleme.auditType == .contrast, let c = capture,
                    let mesure = probleme.element.map({ e in c.contraste(e.frame).map { ($0, e.label) } })
                        ?? c.minimum(app)
                {
                    // le texte visé (ou, sans élément, le moins contrasté de TOUS les textes et boutons visibles) mesuré
                    // sur la capture ; démenti s'il atteint 4,5:1 (WCAG AA pour un petit texte) ; la mesure est notée
                    let note =
                        "contraste mesuré sur la capture : " + String(format: "%.1f", mesure.0) + ":1 (« \(mesure.1) »)"
                    if mesure.0 >= 4.5 {
                        ecartes.append(note + " · " + description)
                    } else {
                        problemes.append(description + " · " + note)
                    }
                } else {
                    problemes.append(description)
                }
            }
            capturer(app, "audit-\(ecran)")
        }
        let note = XCTAttachment(string: ecartes.joined(separator: "\n"))
        note.name = "audit-ecartes"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(
            problemes.isEmpty, "\(problemes.count) problème(s) d'accessibilité :\n" + problemes.joined(separator: "\n"))
    }
}

/// Une capture de l'écran, lue pixel par pixel : le contraste (WCAG) d'un texte dans son cadre. Le fond est la couleur la
/// plus fréquente sur le pourtour du cadre, lu 2 pt à l'intérieur (le bord d'un bouton est son trait, pas le fond de son
/// texte : « Écrire » mesurait 3,6:1, le trait contre le fond, au lieu de 13,8:1) ; le texte, la couleur (au moins 2 % des
/// pixels) la plus contrastée avec ce fond. Les couleurs sont ramenées à des pas de 8 (les bords lissés d'un même texte se
/// regroupent).
@MainActor
private struct Capture {
    private let pixels: [UInt8]
    private let largeur: Int
    private let hauteur: Int
    private let echelle: CGFloat

    init?(_ app: XCUIApplication) {
        guard let image = app.screenshot().image.cgImage else { return nil }
        let (l, h) = (image.width, image.height)
        var p = [UInt8](repeating: 0, count: l * h * 4)
        let lu = p.withUnsafeMutableBytes { tampon -> Bool in
            guard
                let c = CGContext(
                    data: tampon.baseAddress, width: l, height: h, bitsPerComponent: 8, bytesPerRow: l * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            c.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))
            return true
        }
        guard lu else { return nil }
        pixels = p
        largeur = l
        hauteur = h
        echelle = CGFloat(l) / max(1, app.frame.width)
    }

    /// Le plus faible contraste parmi les textes et boutons visibles de l'écran.
    func minimum(_ app: XCUIApplication) -> (Double, String)? {
        var pire: (Double, String)?
        let elements = app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex
        for e in elements where e.exists && e.isHittable && !e.label.isEmpty {
            guard let r = contraste(e.frame) else { continue }
            if r < (pire?.0 ?? .infinity) { pire = (r, e.label) }
        }
        return pire
    }

    func contraste(_ cadre: CGRect) -> Double? {
        // 2 pt en retrait, au plus le quart du petit côté (un texte d'une ligne garde sa hauteur utile)
        let retrait = min(2, min(cadre.width, cadre.height) / 4)
        let cadre = cadre.insetBy(dx: retrait, dy: retrait)
        let x0 = max(0, Int(cadre.minX * echelle))
        let x1 = min(largeur - 1, Int(cadre.maxX * echelle))
        let y0 = max(0, Int(cadre.minY * echelle))
        let y1 = min(hauteur - 1, Int(cadre.maxY * echelle))
        guard x1 - x0 > 4, y1 - y0 > 4 else { return nil }
        var bord: [Int: Int] = [:]
        for x in x0...x1 {
            bord[couleur(x, y0), default: 0] += 1
            bord[couleur(x, y1), default: 0] += 1
        }
        for y in y0...y1 {
            bord[couleur(x0, y), default: 0] += 1
            bord[couleur(x1, y), default: 0] += 1
        }
        guard let fond = bord.max(by: { $0.value < $1.value })?.key else { return nil }
        var dedans: [Int: Int] = [:]
        for y in y0...y1 { for x in x0...x1 { dedans[couleur(x, y), default: 0] += 1 } }
        let seuil = (x1 - x0 + 1) * (y1 - y0 + 1) / 50
        let candidats = dedans.filter { $0.value >= seuil && $0.key != fond }.keys
        guard let texte = candidats.max(by: { Self.rapport($0, fond) < Self.rapport($1, fond) }) else { return nil }
        return Self.rapport(texte, fond)
    }

    private func couleur(_ x: Int, _ y: Int) -> Int {
        let i = (y * largeur + x) * 4
        return (Int(pixels[i]) >> 3) << 10 | (Int(pixels[i + 1]) >> 3) << 5 | Int(pixels[i + 2]) >> 3
    }

    private static func luminance(_ c: Int) -> Double {
        func canal(_ v: Int) -> Double {
            let s = Double(v * 8 + 4) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * canal(c >> 10) + 0.7152 * canal((c >> 5) & 31) + 0.0722 * canal(c & 31)
    }

    private static func rapport(_ a: Int, _ b: Int) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
