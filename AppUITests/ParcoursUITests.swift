import XCTest

/// Les parcours principaux, sur la maison de démonstration (aucun réseau, aucun micro) :
/// écrire à Alfred, voir son action et sa réponse ; allumer une pièce depuis la maison ; l'audit d'accessibilité
/// d'Apple sur chaque écran, en clair et en sombre. Des captures sont jointes au résultat (relecture du design).
@MainActor
final class ParcoursUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// `figee` : sans animations (audit et mesures : l'état final, jamais un écran en transition).
    private func lancer(sombre: Bool = false, tailleTexte: String? = nil, figee: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        if sombre { app.launchArguments.append("-sombre") }
        if figee { app.launchArguments.append("-sansAnimations") }
        if let tailleTexte { app.launchArguments += ["-UIPreferredContentSizeCategoryName", tailleTexte] }
        app.launch()
        return app
    }

    /// La démo est prête (suggestions actives) : l'audit porte sur l'état stable, pas sur le démarrage.
    private func attendrePret(_ app: XCUIApplication) {
        let suggestion = app.buttons["Quelle heure est-il ?"]
        let actif = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: suggestion)
        XCTAssertEqual(XCTWaiter().wait(for: [actif], timeout: 10), .completed, "la démo ne devient pas prête")
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
        XCTAssertTrue(
            element(app, contenant: "C’est fait : j’ai allumé la pièce Cuisine.").waitForExistence(timeout: 10))
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
        try auditer(lancer(figee: true))
    }

    func testAccessibiliteSombre() throws {
        try auditer(lancer(sombre: true, figee: true))
    }

    /// La plus grande taille de texte : le texte grandit vraiment (mesuré), et des captures de chaque écran sont
    /// jointes pour la relecture (rien n'est coupé, tout reste atteignable).
    ///
    /// La taille du texte se vérifie ici plutôt que par l'audit : sa sonde perd les éléments du bas de l'écran,
    /// poussés hors de la vue quand le texte grandit (l'élément le plus bas de chaque écran était signalé, ses
    /// semblables plus haut non). L'app n'emploie aucune taille de police fixe.
    func testGrandTexte() throws {
        let normal = hauteurs(lancer(figee: true))
        let app = lancer(tailleTexte: "UICTContentSizeCategoryAccessibilityXXXL", figee: true)
        let grand = hauteurs(app, captures: true)
        for (nom, h) in normal {
            let g = try XCTUnwrap(grand[nom], nom)
            XCTAssertGreaterThan(g, h * 1.5, "« \(nom) » ne grandit pas avec le texte (\(h) → \(g) pt)")
        }
    }

    /// La hauteur d'un texte en haut de chaque écran (toujours dans la vue, quelle que soit la taille du texte).
    private func hauteurs(_ app: XCUIApplication, captures: Bool = false) -> [String: CGFloat] {
        var h: [String: CGFloat] = [:]
        let salutation = element(app, contenant: "Bonjour")
        XCTAssertTrue(salutation.waitForExistence(timeout: 10))
        h["salutation"] = salutation.frame.height
        if captures { capturer(app, "grand-texte-1-alfred") }
        app.tabBars.buttons["Maison"].tap()
        let bureau = app.buttons["Bureau"]
        XCTAssertTrue(bureau.waitForExistence(timeout: 10))
        h["tuile Bureau"] = bureau.frame.height
        if captures {
            capturer(app, "grand-texte-2-maison")
            app.swipeUp()
            capturer(app, "grand-texte-3-maison-suite")
        }
        app.buttons["reglages"].firstMatch.tap()
        let compte = element(app, contenant: "Connecté en tant que")
        XCTAssertTrue(compte.waitForExistence(timeout: 5))
        h["Connecté en tant que"] = compte.frame.height
        if captures {
            capturer(app, "grand-texte-4-reglages")
            app.swipeUp()
            capturer(app, "grand-texte-5-reglages-suite")
            app.swipeUp()
            capturer(app, "grand-texte-6-reglages-fin")
        }
        return h
    }

    /// Le fondu des bords de défilement (iOS 26) estompe le contenu qui passe sous la barre d'onglets : il commence
    /// 40 pt au-dessus d'elle (mesuré sur une capture : iPhone 17 Pro, iOS 26.5). Un élément dans cette zone est
    /// jugé sur son rendu estompé ; ses semblables plus haut dans l'écran sont audités normalement.
    private static let zoneFonduBas: CGFloat = 40

    /// Les trois écrans, chacun audité en entier (sauf la taille du texte : voir `testGrandTexte`) : tous les
    /// problèmes sont listés dans UN échec, avec l'écran, le type de problème, l'élément et sa place. Deux cas sont
    /// écartés, et listés à part (pièce jointe « audit-ecartes ») :
    /// - un élément dans le fondu du bas (ci-dessus) : contraste, texte coupé ;
    /// - le champ de recherche du système (`.searchable`) : la couleur et la taille de son texte indicatif sont
    ///   celles d'iOS, que l'app ne peut pas changer.
    private func auditer(_ app: XCUIApplication) throws {
        var problemes: [String] = []
        var ecartes: [String] = []
        func auditerEcran(_ ecran: String, sousBarreOnglets: Bool) throws {
            // la feuille des réglages couvre la barre d'onglets, qui reste pourtant dans l'arbre d'accessibilité
            let barre = app.tabBars.firstMatch
            let limite =
                sousBarreOnglets && barre.exists ? barre.frame.minY - Self.zoneFonduBas : .greatestFiniteMagnitude
            let rendu: XCUIAccessibilityAuditType = [.contrast, .textClipped]
            try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.dynamicType)) {
                probleme in
                let cadre = probleme.element?.frame
                let description =
                    "\(ecran) · \(probleme.compactDescription) · "
                    + (probleme.element.map { "« \($0.label) » \(Int($0.frame.minY))…\(Int($0.frame.maxY)) pt" }
                        ?? "sans élément (\(probleme.debugDescription))")
                    + " · \(probleme.detailedDescription)"
                if let cadre, rendu.contains(probleme.auditType), cadre.maxY > limite {
                    ecartes.append("fondu du bas · " + description)
                } else if probleme.element?.elementType == .searchField, rendu.contains(probleme.auditType) {
                    ecartes.append("champ de recherche du système · " + description)
                } else {
                    problemes.append(description)
                }
                return true
            }
        }
        XCTAssertTrue(app.buttons["noyau"].waitForExistence(timeout: 10))
        attendrePret(app)
        try auditerEcran("Alfred", sousBarreOnglets: true)
        app.tabBars.buttons["Maison"].tap()
        XCTAssertTrue(app.buttons["Salon"].waitForExistence(timeout: 10))
        try auditerEcran("Maison", sousBarreOnglets: true)
        app.buttons["reglages"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 5))
        try auditerEcran("Réglages", sousBarreOnglets: false)
        capturer(app, "audit-reglages")
        let note = XCTAttachment(string: ecartes.joined(separator: "\n"))
        note.name = "audit-ecartes"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(
            problemes.isEmpty, "\(problemes.count) problème(s) d'accessibilité :\n" + problemes.joined(separator: "\n"))
    }
}
