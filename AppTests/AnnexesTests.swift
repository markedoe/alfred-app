import AlfredKit
import Foundation
import Testing

@testable import Alfred

/// Les annexes de la console contre la maison de démonstration (aucun réseau) : documents, notifications, liens, état.
@MainActor
@Suite("Annexes", .serialized)
struct AnnexesTests {
    static func pretes() async throws -> Annexes {
        let a = Annexes(acces: AccesDemo()) { _, _ in }
        a.demarrer(connecte: true)
        try await attendre { a.etat != nil && !a.documents.isEmpty && !a.liens.isEmpty && a.notificationsPermises }
        return a
    }

    static func attendre(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("attente dépassée")
    }

    @Test("Au démarrage : documents, notifications, liens et état des services")
    func demarrage() async throws {
        let a = try await Self.pretes()
        #expect(a.documents.map(\.nom) == ["Facture d’exemple"])
        #expect(a.documents.first?.paperless == true)
        #expect(a.nonLues == 1 && a.notifications.count == 2)
        #expect(a.liens.map(\.nom) == ["Home Assistant", "Paperless"])
        #expect(a.etat?.groupes.map(\.nomCourt) == ["maison", "voix", "nuit"])
        #expect(a.etat?.kuma == nil)
        a.suspendre()
    }

    @Test("Dépôt puis suppression d'un document : la liste suit")
    func depot() async throws {
        let a = try await Self.pretes()
        await a.deposer(
            DepotDocument(fichier: Data("%PDF-1.7".utf8), nomFichier: "devis.pdf", type: "application/pdf"))
        try await Self.attendre { a.documents.count == 2 }
        #expect(a.documents.first?.nom == "devis.pdf")
        #expect(a.etatDepot == "Reçu. Alfred le lit…")
        let depose = try #require(a.documents.first)
        await a.supprimer(depose)
        try await Self.attendre { a.documents.count == 1 }
        a.suspendre()
    }

    @Test("Un document de plus de 20 Mo n'est pas envoyé : l'erreur est dans la fenêtre, puis oubliée à sa fermeture")
    func tropLourd() async throws {
        let avis = Recueil()
        let a = Annexes(acces: AccesDemo()) { texte, _ in avis.textes.append(texte) }
        a.demarrer(connecte: true)
        try await Self.attendre { !a.documents.isEmpty }
        // le refus est immédiat (rien ne part) : vérifié dès le retour, sans attente
        await a.deposer(
            DepotDocument(
                fichier: Data(count: DepotDocument.tailleMax + 1), nomFichier: "gros.pdf", type: "application/pdf"))
        #expect(a.documents.count == 1 && a.etatDepot == nil)
        #expect(a.erreurDepot == "Document trop lourd : 20 Mo au plus.", "dans la fenêtre Documents (point 11)")
        #expect(avis.textes == ["Document trop lourd : 20 Mo au plus."])
        a.oublierErreurDepot()
        #expect(a.erreurDepot == nil)
        a.suspendre()
    }

    @Test("L'identifiant d'un document ne vise jamais une autre route")
    func segment() {
        #expect(Annexes.segment("42") == "42")
        #expect(Annexes.segment("../notifications/effacer") == "..%2Fnotifications%2Feffacer")
    }

    @Test("Notifications : lues, puis effacées")
    func notifications() async throws {
        let a = try await Self.pretes()
        await a.marquerLues()
        try await Self.attendre { a.nonLues == 0 }
        let toutesLues = a.notifications.allSatisfy { $0.lu }
        #expect(toutesLues)
        await a.effacerNotifications()
        try await Self.attendre { a.notifications.isEmpty }
        a.suspendre()
    }

    @Test("Réponse d'Hermes (22.10) : réclamée une seule fois pendant l'attente, puis passée à la conversation")
    func reponseHermes() async throws {
        let acces = AccesHermesDeTest()
        let c = Conversation(voix: VoixMuette())
        let a = Annexes(acces: acces) { _, _ in }
        a.conversation = c
        c.attendreHermes()
        a.demarrer(connecte: true)
        try await Self.attendre { c.messages.contains { $0.texte == AccesHermesDeTest.texte } }
        #expect(acces.reclamations == 1)
        #expect(c.attentesHermes.isEmpty)
        a.suspendre()
    }

    @Test("Deux questions à Hermes de suite (23.10) : les deux réponses sont réclamées et lues, dans l'ordre")
    func deuxQuestionsHermes() async throws {
        let acces = AccesHermesDeTest(prete: false)
        let voix = VoixMuette()
        let c = ConversationTests.seule(voix)
        let a = Annexes(acces: acces) { _, _ in }
        a.conversation = c
        c.attendreHermes()
        c.attendreHermes()
        a.demarrer(connecte: true)
        acces.publier("h1", "Première réponse.")
        a.relireNotifications()
        try await Self.attendre { c.phase == .repos && voix.lues.count == 1 }
        #expect(c.messages.map(\.texte) == ["Première réponse."])
        #expect(c.attentesHermes.count == 1 && c.ecranAllume, "la 2e réponse est encore attendue")
        acces.publier("h2", "Seconde réponse.")
        a.relireNotifications()
        try await Self.attendre { c.phase == .repos && voix.lues.count == 2 }
        #expect(c.messages.map(\.texte) == ["Première réponse.", "Seconde réponse."])
        #expect(voix.lues == ["/tts/h1.mp3", "/tts/h2.mp3"])
        #expect(acces.reclamations == 2 && c.attentesHermes.isEmpty && !c.ecranAllume)
        a.suspendre()
    }

    @Test("Réponse d'Hermes réclamée, puis la conversation fermée (déconnexion) avant son retour : ignorée (23.10)")
    func reponseHermesApresNouvelle() async throws {
        let acces = AccesHermesDeTest()
        let porte = PorteDeTest()
        acces.porte = porte
        let voix = VoixMuette()
        let c = ConversationTests.seule(voix)
        let a = Annexes(acces: acces) { _, _ in }
        a.conversation = c
        c.attendreHermes()
        a.demarrer(connecte: true)
        try await Self.attendre { acces.reclamations == 1 }
        // les annexes tournent encore : seule l'attente fermée par nouvelle() arrête la réponse
        await c.nouvelle()
        await porte.ouvrir()
        try await Self.attendre { acces.rendues == 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(c.vide && c.differees.isEmpty && voix.lues.isEmpty)
        #expect(!c.ecranAllume, "l'écran se verrouille de nouveau")
        a.suspendre()
    }

    @Test("Une relecture pendant une réclamation ne la coupe pas : la réponse d'Hermes est quand même lue (23.10)")
    func reclamationNonCoupee() async throws {
        let acces = AccesHermesDeTest()
        let porte = PorteDeTest()
        acces.porte = porte
        let voix = VoixMuette()
        let c = ConversationTests.seule(voix)
        let a = Annexes(acces: acces) { _, _ in }
        a.conversation = c
        c.attendreHermes()
        a.demarrer(connecte: true)
        try await Self.attendre { acces.reclamations == 1 }
        // la fenêtre Notifications ouverte, ou une nouvelle question : les notifications se relisent
        a.relireNotifications()
        await porte.ouvrir()
        try await Self.attendre { c.messages.contains { $0.texte == AccesHermesDeTest.texte } }
        try await Self.attendre { voix.lues == ["/tts/h1.mp3"] }
        #expect(acces.reclamations == 1 && c.attentesHermes.isEmpty)
        a.suspendre()
    }

    @Test("Invité (non connecté) : ni notifications ni liens")
    func invite() async throws {
        let a = Annexes(acces: AccesDemo()) { _, _ in }
        a.demarrer(connecte: false)
        try await Self.attendre { a.etat != nil }
        #expect(!a.notificationsPermises && a.liens.isEmpty)
        a.suspendre()
    }
}

/// Les avis reçus (une boîte : la fonction des avis est isolée sur l'acteur principal, donc envoyable).
@MainActor
final class Recueil {
    var textes: [String] = []
}

/// 22.10 : un relais qui n'a que des réponses d'Hermes « à lire », chacune réclamable une seule fois (comme le vrai :
/// marquée livrée avant de répondre). `publier` en range une de plus ; `porte` retient la réponse d'une réclamation, et
/// une réclamation annulée pendant ce temps échoue (comme une requête d'URLSession).
final class AccesHermesDeTest: AccesRelais, @unchecked Sendable {
    static let texte = "La facture du garage est arrivée."

    private struct Reponse {
        let id: String
        let texte: String
        let t: Double
        var livree = false
    }

    private let verrou = NSLock()
    private var _reponses: [Reponse] = []
    private var _reclamations = 0
    private var _rendues = 0
    private var _porte: PorteDeTest?

    /// `prete` : la réponse « h1 » (`texte`) est là dès le départ.
    init(prete: Bool = true) {
        if prete { publier("h1", Self.texte) }
    }

    var reclamations: Int { verrou.withLock { _reclamations } }
    /// Les réclamations qui ont reçu leur réponse.
    var rendues: Int { verrou.withLock { _rendues } }
    var porte: PorteDeTest? {
        get { verrou.withLock { _porte } }
        set { verrou.withLock { _porte = newValue } }
    }

    func publier(_ id: String, _ texte: String) {
        let r = Reponse(id: id, texte: texte, t: Date.now.timeIntervalSince1970)
        verrou.withLock { _reponses.append(r) }
    }

    func ouvrir() async throws -> any Liaison {
        throw ErreurRelais("pas de liaison dans ce test")
    }

    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) {
        guard chemin == "/notifications" else { return (404, Data()) }
        let reponses = verrou.withLock { _reponses }
        // la plus récente d'abord, comme le relais
        let liste = reponses.reversed().map { r -> [String: Any] in
            [
                "id": r.id, "t": r.t, "titre": "Hermes", "message": r.texte, "source": "hermes", "a_lire": true,
                "livree": r.livree, "lu": r.livree,
            ]
        }
        let nonLues = reponses.filter { !$0.livree }.count
        let corps = try JSONSerialization.data(withJSONObject: ["notifications": liste, "non_lues": nonLues])
        return (200, corps)
    }

    func envoyer(_ requete: RequeteRelais) async throws -> (statut: Int, corps: Data) {
        guard requete.chemin == "/notifications/livrer", let corps = requete.corps,
            let demande = try JSONSerialization.jsonObject(with: corps) as? [String: String], let id = demande["id"]
        else { return (404, Data()) }
        let prise: Reponse? = verrou.withLock {
            _reclamations += 1
            guard let i = _reponses.firstIndex(where: { $0.id == id && !$0.livree }) else { return nil }
            _reponses[i].livree = true
            return _reponses[i]
        }
        if let p = porte { await p.passer() }
        try Task.checkCancellation()
        verrou.withLock { _rendues += 1 }
        var r: [String: Any] = ["ok": false]
        if let reponse = prise { r = ["ok": true, "message": reponse.texte, "tts": reponse.id + ".mp3"] }
        return (200, try JSONSerialization.data(withJSONObject: r))
    }
}
