import XCTest

/// Les parcours principaux, sur la maison de démonstration (aucun réseau, aucun micro) :
/// écrire à Alfred, voir son action et sa réponse ; allumer une pièce depuis la maison ; l'audit d'accessibilité
/// d'Apple sur chaque écran, en clair et en sombre. Des captures sont jointes au résultat (relecture du design).
@MainActor
final class ParcoursUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func lancer(sombre: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        if sombre { app.launchArguments.append("-sombre") }
        app.launch()
        return app
    }

    /// Un élément dont le libellé d'accessibilité contient ce texte (les messages regroupent leurs textes).
    private func element(_ app: XCUIApplication, contenant texte: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", texte)).firstMatch
    }

    private func capturer(_ app: XCUIApplication, _ nom: String) {
        let c = XCTAttachment(screenshot: app.screenshot())
        c.name = nom
        c.lifetime = .keepAlways
        add(c)
    }

    func testEcrireAAlfred() throws {
        let app = lancer()
        let saisie = app.textFields["saisie"].firstMatch.exists ? app.textFields["saisie"] : app.textViews["saisie"]
        XCTAssertTrue(saisie.waitForExistence(timeout: 10))
        capturer(app, "1-accueil-alfred")
        saisie.tap()
        saisie.typeText("Allume la cuisine")
        // par l'identifiant seul : la touche « envoyer » du clavier français porte le même libellé
        app.buttons.matching(NSPredicate(format: "identifier == %@", "envoyer")).firstMatch.tap()
        XCTAssertTrue(element(app, contenant: "Allumer · Cuisine, fait").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, contenant: "C’est fait : cuisine allumé.").waitForExistence(timeout: 10))
        capturer(app, "2-conversation")
    }

    func testAllumerUnePiece() throws {
        let app = lancer()
        app.tabBars.buttons["Maison"].tap()
        let entree = app.buttons["Allumer Entrée"]
        XCTAssertTrue(entree.waitForExistence(timeout: 10))
        capturer(app, "3-maison")
        entree.tap()
        // l'état affiché est celui que la maison confirme
        XCTAssertTrue(app.buttons["Éteindre Entrée"].waitForExistence(timeout: 10))
        app.buttons["Salon"].tap()
        XCTAssertTrue(app.navigationBars["Salon"].waitForExistence(timeout: 5))
        capturer(app, "4-piece")
    }

    func testAccessibiliteClair() throws {
        try auditer(lancer())
    }

    func testAccessibiliteSombre() throws {
        try auditer(lancer(sombre: true))
    }

    /// Les trois écrans, chacun audité en entier : tous les problèmes sont listés dans UN échec, avec l'écran,
    /// le type de problème et l'élément (sinon le test s'arrêterait au premier).
    private func auditer(_ app: XCUIApplication) throws {
        var problemes: [String] = []
        func auditerEcran(_ ecran: String) throws {
            try app.performAccessibilityAudit { probleme in
                let element = probleme.element.map { "« \($0.label) » (\($0.identifier))" } ?? "sans élément"
                problemes.append(
                    "\(ecran) · \(probleme.compactDescription) · \(element) · \(probleme.detailedDescription)")
                return true
            }
        }
        XCTAssertTrue(app.buttons["noyau"].waitForExistence(timeout: 10))
        try auditerEcran("Alfred")
        app.tabBars.buttons["Maison"].tap()
        XCTAssertTrue(app.buttons["Salon"].waitForExistence(timeout: 10))
        try auditerEcran("Maison")
        app.buttons["reglages"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 5))
        try auditerEcran("Réglages")
        capturer(app, "audit-reglages")
        XCTAssertTrue(
            problemes.isEmpty, "\(problemes.count) problème(s) d'accessibilité :\n" + problemes.joined(separator: "\n"))
    }
}
