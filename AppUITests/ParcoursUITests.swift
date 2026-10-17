import UIKit
import XCTest

/// Les parcours principaux, sur la maison de démonstration (aucun réseau, aucun micro) : écrire à Alfred et lire sa
/// réponse dans les échanges ; allumer une pièce depuis la roue, l'état affiché étant celui que la maison confirme ;
/// l'audit d'accessibilité d'Apple sur chaque vue ; la disposition large (iPad à l'horizontale). Des captures sont
/// jointes au résultat : elles se comparent à celles de la console web (relecture du design).
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

    /// La démo est prête (« Parler à Alfred » actif) : l'audit porte sur l'état stable, pas sur le démarrage.
    private func attendrePret(_ app: XCUIApplication) {
        let parler = bouton(app, "parler")
        XCTAssertTrue(parler.waitForExistence(timeout: 10))
        let actif = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: parler)
        XCTAssertEqual(XCTWaiter().wait(for: [actif], timeout: 10), .completed, "la démo ne devient pas prête")
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
        let saisie = app.textFields["saisie"].firstMatch.exists ? app.textFields["saisie"] : app.textViews["saisie"]
        XCTAssertTrue(saisie.waitForExistence(timeout: 5))
        saisie.tap()
        saisie.typeText("Allume la cuisine")
        // par l'identifiant seul : la touche « envoyer » du clavier français porte le même libellé
        bouton(app, "envoyer").tap()
        // comme la console : l'envoi ferme la saisie et montre les échanges
        XCTAssertTrue(app.staticTexts["briefing"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, contenant: "Allumer · Cuisine, fait").waitForExistence(timeout: 10))
        XCTAssertTrue(
            element(app, contenant: "C’est fait : j’ai allumé la pièce Cuisine.").waitForExistence(timeout: 10))
        capturer(app, "2-alfred-echanges")
        vue(app, "environnement")
        XCTAssertTrue(element(app, contenant: "Extérieur").waitForExistence(timeout: 5))
        capturer(app, "3-environnement")
    }

    func testAllumerUnePiece() throws {
        let app = lancer()
        attendrePret(app)
        let entree = bouton(app, "piece-Entrée")
        XCTAssertTrue(entree.waitForExistence(timeout: 10))
        XCTAssertTrue((entree.value as? String ?? "").contains("éteinte"), "\(entree.value ?? "")")
        entree.tap()
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
        XCTAssertTrue((entree.value as? String ?? "").contains("allumée"), "\(entree.value ?? "")")
        capturer(app, "5-piece-allumee")
    }

    func testAccessibilite() throws {
        let app = lancer()
        attendrePret(app)
        try auditerEcrans(app, ["Pièces", "Alfred", "Environnement", "Réglages"])
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
        try auditerEcrans(app, ["Large"])
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
        if captures { capturer(app, "grand-texte-1-pieces") }
        vue(app, "alfred")
        let briefing = app.staticTexts["briefing"]
        XCTAssertTrue(briefing.waitForExistence(timeout: 5))
        h["briefing"] = briefing.frame.height
        if captures { capturer(app, "grand-texte-2-alfred") }
        vue(app, "environnement")
        let exterieur = element(app, contenant: "Extérieur")
        XCTAssertTrue(exterieur.waitForExistence(timeout: 5))
        h["Extérieur"] = exterieur.frame.height
        if captures {
            capturer(app, "grand-texte-3-environnement")
            app.swipeUp()
            capturer(app, "grand-texte-4-environnement-suite")
        }
        bouton(app, "reglages").tap()
        let compte = element(app, contenant: "Connecté en tant que")
        XCTAssertTrue(compte.waitForExistence(timeout: 5))
        h["Connecté en tant que"] = compte.frame.height
        if captures {
            capturer(app, "grand-texte-5-reglages")
            app.swipeUp()
            capturer(app, "grand-texte-6-reglages-suite")
            app.swipeUp()
            capturer(app, "grand-texte-7-reglages-fin")
        }
        return h
    }

    private static let engagementMicro =
        "Le micro ne s’ouvre que pendant une conversation, et jamais en arrière-plan."

    /// Les vues de la console et les réglages, chacune auditée en entier (sauf la taille du texte : voir
    /// `testGrandTexte`) : tous les problèmes sont listés dans UN échec, avec la vue, le type de problème, l'élément
    /// et sa place. Un cas est écarté, et listé à part (pièce jointe « audit-ecartes ») : « texte coupé » prédit pour
    /// l'engagement du micro, démenti par la capture « grand-texte-7-reglages-fin » (le texte passe à la ligne
    /// jusqu'au bout, rien n'est coupé).
    private func auditerEcrans(_ app: XCUIApplication, _ ecrans: [String]) throws {
        var problemes: [String] = []
        var ecartes: [String] = []
        for ecran in ecrans {
            switch ecran {
            case "Alfred": vue(app, "alfred")
            case "Environnement": vue(app, "environnement")
            case "Réglages":
                bouton(app, "reglages").tap()
                XCTAssertTrue(app.navigationBars["Réglages & état"].waitForExistence(timeout: 5))
            default: vue(app, "pieces")
            }
            try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.dynamicType)) {
                probleme in
                let description =
                    "\(ecran) · \(probleme.compactDescription) · "
                    + (probleme.element.map { "« \($0.label) » \(Int($0.frame.minY))…\(Int($0.frame.maxY)) pt" }
                        ?? "sans élément (\(probleme.debugDescription))")
                    + " · \(probleme.detailedDescription)"
                if probleme.auditType == .textClipped, probleme.element?.label == Self.engagementMicro {
                    ecartes.append("vérifié en très grand texte · " + description)
                } else {
                    problemes.append(description)
                }
                return true
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
