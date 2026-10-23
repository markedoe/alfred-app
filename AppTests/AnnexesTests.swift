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
        #expect(a.documents.map(\.nom) == ["Facture d’exemple", "Photo floue d’exemple"])
        #expect(a.documents.first?.paperless == true)
        // 23.10 : la boîte d'arrivée — un rangé, un refusé ; la pastille ne compte que le refus
        #expect(a.documents.map(\.statut) == [.range, .refuse])
        #expect(a.pastilleDocuments == 1)
        #expect(a.nonLues == 1 && a.notifications.count == 2)
        #expect(a.liens.map(\.nom) == ["Home Assistant", "Paperless"])
        #expect(a.etat?.groupes.map(\.nomCourt) == ["maison", "voix", "nuit"])
        #expect(a.etat?.kuma == nil)
        a.suspendre()
    }

    @Test("Dépôt, puis le refus réessayé et retiré (23.10) : la liste et la pastille suivent")
    func depot() async throws {
        let a = try await Self.pretes()
        await a.deposer(
            DepotDocument(fichier: Data("%PDF-1.7".utf8), nomFichier: "devis.pdf", type: "application/pdf"))
        try await Self.attendre { a.documents.count == 3 }
        #expect(a.documents.first?.nom == "devis.pdf" && a.documents.first?.statut == .range)
        #expect(a.etatDepot == "Reçu. Alfred le lit…")
        let refuse = try #require(a.documents.first { $0.statut == .refuse })
        await a.reessayer(refuse)
        try await Self.attendre { a.pastilleDocuments == 0 }
        #expect(a.documents.allSatisfy { $0.statut == .range })
        await a.reessayer(refuse)
        #expect(a.erreurDepot == "Nouvel essai impossible : rien à réessayer", "409 : rien à réessayer")
        let depose = try #require(a.documents.first)
        await a.retirer(depose)
        try await Self.attendre { a.documents.count == 2 }
        a.suspendre()
    }

    @Test(
        "Lot (23.10) : une requête par fichier, « Pour le » pour chacun, un fichier illisible sauté, 413/415 en cartes")
    func lot() async throws {
        let acces = AccesDepotsDeTest()
        let avis = Recueil()
        let a = Annexes(acces: acces) { texte, _ in avis.textes.append(texte) }
        a.demarrer(connecte: true)
        let lot = LotDepot(pourLe: "2026-10-24", total: 5)
        let noms = ["a.pdf", "illisible", "b.txt", "gros.pdf", "c.docx"]
        await a.deposer(lot: lot) { rang in
            if noms[rang] == "illisible" { return nil }
            return lot.depot(fichier: Data("%PDF".utf8), nomFichier: noms[rang], type: "application/pdf")
        }
        #expect(acces.noms == ["a.pdf", "b.txt", "gros.pdf", "c.docx"], "l'un après l'autre, dans l'ordre")
        #expect(acces.corps.allSatisfy { $0.contains("name=\"pour_le\"\r\n\r\n2026-10-24") })
        #expect(
            a.refusLocaux.map(\.texte).sorted() == [
                "Refusé : trop lourd (20 Mo au plus)", "Refusé : type non pris en charge (PDF, image, texte ou e-mail)",
            ])
        #expect(a.etatDepot == "2 reçus. Alfred les lit…")
        #expect(avis.textes.contains("2 documents reçus."))
        try await Self.attendre { a.pastilleDocuments == 2 }
        a.retirer(a.refusLocaux[0])
        #expect(a.refusLocaux.count == 1 && a.pastilleDocuments == 1)
        a.suspendre()
    }

    @Test(
        "Un document de plus de 20 Mo n'est pas envoyé : une carte « Refusé » dans la fenêtre (23.10), jusqu'à Retirer")
    func tropLourd() async throws {
        let avis = Recueil()
        let a = Annexes(acces: AccesDemo()) { texte, _ in avis.textes.append(texte) }
        a.demarrer(connecte: true)
        try await Self.attendre { !a.documents.isEmpty }
        // le refus est immédiat (rien ne part) : vérifié dès le retour, sans attente
        await a.deposer(
            DepotDocument(
                fichier: Data(count: DepotDocument.tailleMax + 1), nomFichier: "gros.pdf", type: "application/pdf"))
        #expect(a.documents.count == 2 && a.etatDepot == nil)
        #expect(a.refusLocaux.map(\.nom) == ["gros.pdf"], "dans la fenêtre Documents (point 11)")
        #expect(a.refusLocaux.first?.texte == "Refusé : trop lourd (20 Mo au plus)")
        #expect(avis.textes == ["Refusé : trop lourd (20 Mo au plus)"])
        #expect(a.pastilleDocuments == 2, "le refus de la démo et celui de l'appareil")
        a.retirer(a.refusLocaux[0])
        #expect(a.refusLocaux.isEmpty && a.pastilleDocuments == 1)
        a.suspendre()
    }

    @Test("Étiquettes (23.10) : la liste de la maison ; un relais plus ancien (404) : pas de champ")
    func etiquettes() async throws {
        let a = try await Self.pretes()
        a.relireEtiquettes()
        try await Self.attendre { a.etiquettes != nil }
        #expect(a.etiquettes?.disponible == true)
        #expect(a.etiquettes?.etiquettes.map(\.nom) == ["Assurance", "Électricité", "Impôts", "Maison", "Voiture"])
        // un dépôt avec une étiquette de la liste (son n°) et une nouvelle (son nom) : la carte les porte
        let lot = LotDepot(pourLe: nil, total: 1, etiquettes: ["2", "Jardin"])
        await a.deposer(lot.depot(fichier: Data("%PDF-1.7".utf8), nomFichier: "facture.pdf", type: "application/pdf"))
        try await Self.attendre { a.documents.first?.nom == "facture.pdf" }
        #expect(a.documents.first?.etiquettes == ["Électricité", "Jardin"])
        #expect(a.documents.first?.texteEtiquettes == " · étiquettes : Électricité, Jardin")
        a.suspendre()
        let ancien = Annexes(acces: AccesDepotsDeTest()) { _, _ in }
        ancien.demarrer(connecte: true)
        ancien.relireEtiquettes()
        try await Task.sleep(for: .milliseconds(100))
        #expect(ancien.etiquettes == nil, "404 : le champ « Étiquettes » reste caché")
        ancien.suspendre()
    }

    @Test(
        "Étiquettes d'un lot (23.10) : les mêmes pour chaque fichier ; un 400 du relais devient une carte avec son texte"
    )
    func etiquettesLot() async throws {
        let acces = AccesDepotsDeTest()
        let a = Annexes(acces: acces) { _, _ in }
        a.demarrer(connecte: true)
        let lot = LotDepot(pourLe: nil, total: 2, etiquettes: ["12", "Jardin"])
        let noms = ["a.pdf", "etiquette-refusee.pdf"]
        await a.deposer(lot: lot) { rang in
            lot.depot(fichier: Data("%PDF".utf8), nomFichier: noms[rang], type: "application/pdf")
        }
        #expect(acces.noms == noms)
        #expect(
            acces.corps.allSatisfy {
                $0.contains("name=\"etiquette\"\r\n\r\n12\r\n") && $0.contains("name=\"etiquette\"\r\n\r\nJardin\r\n")
            })
        #expect(
            a.refusLocaux.map(\.texte) == [
                "Refusé : étiquette inconnue (n° 12) : rechoisissez-la dans la liste"
            ])
        #expect(a.etatDepot == "Reçu. Alfred le lit…")
        a.suspendre()
    }

    @Test("Deux temps (23.10) : l'état armé survit aux relectures de la liste, puis expire seul après 3,5 s")
    func deuxTempsApresRelecture() async throws {
        let a = try await Self.pretes()
        let refuse = try #require(a.documents.first { $0.statut == .refuse })
        #expect(!a.toucherEnDeuxTemps("retirer", refuse), "le premier toucher arme")
        // pendant la lecture d'un autre fichier du lot, la liste se relit toutes les 2,5 s : ici, deux fois de suite
        a.relireDocuments()
        try await Task.sleep(for: .milliseconds(50))
        a.relireDocuments()
        try await Task.sleep(for: .milliseconds(50))
        #expect(a.deuxTemps.estArme("retirer", id: refuse.id), "toujours armé après les relectures")
        #expect(a.toucherEnDeuxTemps("retirer", refuse), "le second toucher confirme")
        #expect(!a.toucherEnDeuxTemps("supprimer", refuse))
        try await Task.sleep(for: .seconds(DeuxTemps.delai + 0.2))
        #expect(!a.deuxTemps.estArme("supprimer", id: refuse.id), "expiré : la carte redevient « Supprimer »")
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

/// 23.10 : un relais qui ne fait que recevoir des dépôts : 202 (avec la carte), 413 pour « gros.pdf », 415 pour un
/// « .docx », 400 avec un texte pour « etiquette-refusee.pdf » ; il garde le nom et le corps de chaque requête, dans
/// l'ordre. Il ne connaît pas les étiquettes (`/docs/etiquettes` : 404, comme un relais plus ancien).
final class AccesDepotsDeTest: AccesRelais, @unchecked Sendable {
    private let verrou = NSLock()
    private var _noms: [String] = []
    private var _corps: [String] = []

    var noms: [String] { verrou.withLock { _noms } }
    var corps: [String] { verrou.withLock { _corps } }

    func ouvrir() async throws -> any Liaison {
        throw ErreurRelais("pas de liaison dans ce test")
    }

    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) {
        guard chemin == "/docs" else { return (404, Data()) }
        let n = noms.filter { $0 == "a.pdf" || $0 == "b.txt" }.count
        let docs = (0..<n).map { i -> [String: Any] in
            ["id": "d\(i)", "nom": "d\(i)", "etat": "pret", "statut": "range"]
        }
        return (
            200, try JSONSerialization.data(withJSONObject: ["documents": docs, "a_traiter": 0, "hors_panneau": 0])
        )
    }

    func envoyer(_ requete: RequeteRelais) async throws -> (statut: Int, corps: Data) {
        guard requete.methode == .post, requete.chemin == "/docs", let donnees = requete.corps else {
            return (404, Data())
        }
        let texte = String(decoding: donnees, as: UTF8.self)
        let nom =
            texte.range(of: #"filename="([^"]+)""#, options: .regularExpression)
            .map { String(texte[$0].dropFirst("filename=\"".count).dropLast()) } ?? ""
        verrou.withLock {
            _noms.append(nom)
            _corps.append(texte)
        }
        if nom == "gros.pdf" { return (413, Data()) }
        if nom == "etiquette-refusee.pdf" {
            return (400, Data("étiquette inconnue (n° 12) : rechoisissez-la dans la liste".utf8))
        }
        if nom.hasSuffix(".docx") { return (415, Data()) }
        return (202, Data("{}".utf8))
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
