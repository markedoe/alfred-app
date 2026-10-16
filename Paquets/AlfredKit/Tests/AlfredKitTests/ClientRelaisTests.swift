import Foundation
import Testing

@testable import AlfredKit

/// Une liaison en mémoire : le test joue le relais.
actor LiaisonFactice: Liaison {
    private(set) var envoyees: [Trame] = []
    private var file: [Trame] = []
    private var attente: CheckedContinuation<Trame, Error>?
    private(set) var fermee = false

    func envoyer(_ trame: Trame) async throws {
        if fermee { throw ErreurRelais.lienCoupe }
        envoyees.append(trame)
    }

    func recevoir() async throws -> Trame {
        if !file.isEmpty { return file.removeFirst() }
        if fermee { throw ErreurRelais.lienCoupe }
        return try await withCheckedThrowingContinuation { attente = $0 }
    }

    func fermer() async {
        fermee = true
        attente?.resume(throwing: ErreurRelais.lienCoupe)
        attente = nil
    }

    func pousser(_ texte: String) {
        if let a = attente {
            attente = nil
            a.resume(returning: .texte(texte))
        } else {
            file.append(.texte(texte))
        }
    }

    /// Messages JSON envoyés (les trames binaires à part).
    func messages() -> [ValeurJSON] {
        envoyees.compactMap {
            if case .texte(let t) = $0 { return ValeurJSON.lire(t) }
            return nil
        }
    }

    func binaires() -> [Data] {
        envoyees.compactMap {
            if case .binaire(let d) = $0 { return d }
            return nil
        }
    }
}

final class AccesFactice: AccesRelais, @unchecked Sendable {
    private let verrou = NSLock()
    private var _liaisons: [LiaisonFactice] = []
    private var _structure: ValeurJSON?
    var liaisons: [LiaisonFactice] { verrou.withLock { _liaisons } }
    /// La réponse de `/maison/structure` ; nil = 404 (relais d'avant la route).
    var structure: ValeurJSON? {
        get { verrou.withLock { _structure } }
        set { verrou.withLock { _structure = newValue } }
    }

    func ouvrir() async throws -> any Liaison {
        let l = LiaisonFactice()
        verrou.withLock { _liaisons.append(l) }
        return l
    }

    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) {
        guard chemin == "/maison/structure", let s = structure else { return (404, Data()) }
        return (200, Data(s.enTexte().utf8))
    }
}

/// Recueille les nouvelles du client.
actor Journal {
    private(set) var nouvelles: [ClientRelais.Nouvelle] = []
    func noter(_ n: ClientRelais.Nouvelle) { nouvelles.append(n) }
}

/// Attend qu'une condition devienne vraie (2 s au plus).
func attendre(_ quoi: String, _ condition: @Sendable () async -> Bool) async throws {
    for _ in 0..<400 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("attente dépassée : \(quoi)")
    throw ErreurRelais("attente dépassée : \(quoi)")
}

@Suite("Client du relais", .serialized)
struct ClientRelaisTests {
    static func reglagesCourts() -> ClientRelais.Reglages {
        var r = ClientRelais.Reglages()
        r.delaiDemande = .milliseconds(200)
        r.reconnexionInitiale = .milliseconds(20)
        r.reconnexionMaximale = .milliseconds(40)
        r.delaiConfirmation = .milliseconds(150)
        return r
    }

    struct Banc {
        let client: ClientRelais
        let fabrique: AccesFactice
        let journal: Journal
        let ecoute: Task<Void, Never>

        func liaison(_ i: Int = 0) async throws -> LiaisonFactice {
            try await attendre("liaison \(i)") { [fabrique] in fabrique.liaisons.count > i }
            return fabrique.liaisons[i]
        }

        /// Le dernier message envoyé d'un type donné.
        func envoye(_ type: String, liaison i: Int = 0) async throws -> ValeurJSON {
            let l = try await liaison(i)
            try await attendre("envoi de \(type)") { await l.messages().contains { $0["type"]?.texte == type } }
            return await l.messages().last { $0["type"]?.texte == type }!
        }

        func repondre(
            _ m: ValeurJSON, succes: Bool = true, resultat: ValeurJSON = .nul, liaison i: Int = 0
        ) async throws {
            let l = try await liaison(i)
            await l.pousser(
                ValeurJSON.objet([
                    "id": m["id"]!, "type": "result", "success": .booleen(succes),
                    "result": resultat,
                ]).enTexte())
        }

        /// ready → get_states → subscribe_events → (structure par HTTP) → pipeline/list → prêt.
        func connecter(etats: ValeurJSON = [], liaison i: Int = 0) async throws {
            let l = try await liaison(i)
            await l.pousser(#"{"type":"ready","ha_version":"2026.9.4"}"#)
            try await repondre(try await envoye("get_states", liaison: i), resultat: etats, liaison: i)
            try await repondre(
                try await envoye("assist_pipeline/pipeline/list", liaison: i),
                resultat: ["pipelines": [], "preferred_pipeline": "p-alfred"], liaison: i)
            try await attendre("prêt") { [client] in
                if case .pret = await client.etat { return true }
                return false
            }
        }

        func nouvelles() async -> [ClientRelais.Nouvelle] { await journal.nouvelles }
    }

    static func banc() async -> Banc {
        let f = AccesFactice()
        let c = ClientRelais(acces: f, reglages: reglagesCourts())
        let j = Journal()
        let ecoute = Task { for await n in c.nouvelles { await j.noter(n) } }
        await c.demarrer()
        return Banc(client: c, fabrique: f, journal: j, ecoute: ecoute)
    }

    @Test("Connexion : ready, états, abonnement, pipeline préféré, prêt")
    func connexion() async throws {
        let b = await Self.banc()
        defer { b.ecoute.cancel() }
        try await b.connecter(etats: [["entity_id": "light.a", "state": "off", "attributes": ["friendly_name": "A"]]])
        let l = try await b.liaison()
        let types = await l.messages().compactMap { $0["type"]?.texte }
        #expect(types == ["get_states", "subscribe_events", "assist_pipeline/pipeline/list"])
        #expect(await l.messages().map { $0["id"]?.entier } == [1, 2, 3])
        #expect(await b.client.structure.vide, "relais sans /maison/structure : la maison reste en liste")
        #expect(await b.client.pipelinePrefere == "p-alfred")
        #expect(await b.client.maison["light.a"]?.etat == "off")
        #expect(
            await l.messages().allSatisfy { $0["access_token"] == nil }, "rien qui ressemble à une authentification")
        await b.client.arreter()
    }

    @Test("Un tour part sur le pipeline préféré ; un 2e est refusé")
    func tour() async throws {
        let b = await Self.banc()
        defer { b.ecoute.cancel() }
        try await b.connecter()
        #expect(await b.client.parler())
        #expect(!(await b.client.ecrire("encore")))
        let run = try await b.envoye("assist_pipeline/run")
        #expect(run["pipeline"] == "p-alfred" && run["start_stage"] == "stt")
        await b.client.audio(Data([1, 2]))
        let l = try await b.liaison()
        await l.pousser(
            ValeurJSON.objet([
                "id": run["id"]!, "type": "event",
                "event": ["type": "run-start", "data": ["runner_data": ["stt_binary_handler_id": 9]]],
            ]).enTexte())
        try await attendre("audio envoyé") { await l.binaires() == [Data([9, 1, 2])] }
        await b.client.audio(Data([3]))
        await b.client.finParole()
        try await attendre("fin envoyée") { await l.binaires() == [Data([9, 1, 2]), Data([9, 3]), Data([9])] }
        await b.client.arreter()
    }

    @Test("Le relais ne répond pas : la synchronisation échoue après le délai")
    func delaiDemande() async throws {
        let b = await Self.banc()
        defer { b.ecoute.cancel() }
        let l = try await b.liaison()
        await l.pousser(#"{"type":"ready"}"#)
        try await attendre("échec") { [client = b.client] in
            await client.etat == ClientRelais.Etat.fatal("Délai de réponse dépassé")
        }
        try await attendre("liaison fermée") { await l.fermee }
        await b.client.arreter()
    }

    @Test("Coupure : le tour échoue, puis le client se reconnecte")
    func coupure() async throws {
        let b = await Self.banc()
        defer { b.ecoute.cancel() }
        try await b.connecter()
        #expect(await b.client.ecrire("allume le bureau"))
        await (try await b.liaison()).fermer()
        try await attendre("échec du tour") {
            await b.nouvelles().contains(.tour(.echec("Liaison interrompue avec la maison.")))
        }
        try await attendre("déconnecté") { await b.nouvelles().contains(.etat(.deconnecte)) }
        try await b.connecter(liaison: 1)
        #expect(await !b.client.tour.occupe)
        await b.client.arreter()
    }

    @Test("Le délai d'un tour : échec et jamais de renvoi")
    func delaiTour() async throws {
        let f = AccesFactice()
        var r = Self.reglagesCourts()
        r.delaiTour = .milliseconds(100)
        let c = ClientRelais(acces: f, reglages: r)
        let j = Journal()
        let ecoute = Task { for await n in c.nouvelles { await j.noter(n) } }
        defer { ecoute.cancel() }
        await c.demarrer()
        let b = Banc(client: c, fabrique: f, journal: j, ecoute: ecoute)
        try await b.connecter()
        #expect(await c.ecrire("ferme les velux"))
        try await attendre("délai") { await j.nouvelles.contains(.tour(.echec(AutomateTour.messageDelai))) }
        let runs = await (try await b.liaison()).messages().filter { $0["type"] == "assist_pipeline/run" }
        #expect(runs.count == 1)
        await c.arreter()
    }

    @Test("Lumière : confirmée par l'état reçu, pas par la réponse du service")
    func lumiereConfirmee() async throws {
        let b = await Self.banc()
        defer { b.ecoute.cancel() }
        try await b.connecter(etats: [["entity_id": "light.a", "state": "off", "attributes": [:]]])
        let tache = Task { await b.client.basculer(lumiere: "light.a") }
        let appel = try await b.envoye("call_service")
        #expect(
            appel["domain"] == "light" && appel["service"] == "turn_on" && appel["target"]?["entity_id"] == "light.a")
        try await b.repondre(appel)
        await tache.value
        #expect(await b.client.commandeEnCours("light.a"))
        await (try await b.liaison()).pousser(
            #"{"id":2,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.a","new_state":{"entity_id":"light.a","state":"on","attributes":{}}}}}"#
        )
        try await attendre("confirmée") { await b.nouvelles().contains(.commande(cle: "light.a", .confirmee)) }
        #expect(await !b.client.commandeEnCours("light.a"))
        await b.client.arreter()
    }

    @Test("Lumière : sans état reçu, échec visible ; refus de HA, échec avec son message")
    func lumiereEchecs() async throws {
        let b = await Self.banc()
        defer { b.ecoute.cancel() }
        try await b.connecter(etats: [
            ["entity_id": "light.a", "state": "off", "attributes": [:]],
            ["entity_id": "light.b", "state": "on", "attributes": [:]],
            ["entity_id": "light.c", "state": "unavailable", "attributes": [:]],
        ])
        let t1 = Task { await b.client.basculer(lumiere: "light.a") }
        try await b.repondre(try await b.envoye("call_service"))
        await t1.value
        try await attendre("sans confirmation") {
            await b.nouvelles().contains(.commande(cle: "light.a", .sansConfirmation))
        }

        let l = try await b.liaison()
        let t2 = Task { await b.client.basculer(lumiere: "light.b") }
        try await attendre("2e appel") { await l.messages().filter { $0["type"] == "call_service" }.count == 2 }
        let appel = await l.messages().last { $0["type"] == "call_service" }!
        #expect(appel["service"] == "turn_off")
        await l.pousser(
            ValeurJSON.objet([
                "id": appel["id"]!, "type": "result", "success": false,
                "error": ["code": "refuse", "message": "action non permise"],
            ]).enTexte())
        await t2.value
        try await attendre("refus") {
            await b.nouvelles().contains(.commande(cle: "light.b", .refusee("action non permise")))
        }

        await b.client.basculer(lumiere: "light.c")
        try await attendre("indisponible") {
            await b.nouvelles().contains(.commande(cle: "light.c", .refusee("État de la lumière indisponible.")))
        }
        await b.client.arreter()
    }

    @Test("Pièce : structure lue, toute la pièce s'éteint, confirmé quand plus rien n'est allumé")
    func piece() async throws {
        let b = await Self.banc()
        defer { b.ecoute.cancel() }
        b.fabrique.structure = [
            "version": 1, "etages": [["id": "rez", "nom": "Rez", "niveau": 0]],
            "pieces": [["id": "salon", "nom": "Salon", "etage": "rez"]],
            "lumieres": ["light.a": "salon", "light.b": "salon"],
        ]
        try await b.connecter(etats: [
            ["entity_id": "light.a", "state": "on", "attributes": [:]],
            ["entity_id": "light.b", "state": "on", "attributes": [:]],
        ])
        #expect(await b.client.structure.pieceDe == ["light.a": "salon", "light.b": "salon"])
        let t = Task { await b.client.basculer(piece: "salon") }
        let appel = try await b.envoye("call_service")
        #expect(appel["service"] == "turn_off" && appel["target"]?["area_id"] == "salon")
        try await b.repondre(appel)
        await t.value
        let l = try await b.liaison()
        await l.pousser(
            #"{"id":2,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.a","new_state":{"entity_id":"light.a","state":"off","attributes":{}}}}}"#
        )
        try await Task.sleep(for: .milliseconds(30))
        #expect(await b.client.commandeEnCours("piece:salon"), "une lampe encore allumée : pas encore confirmé")
        await l.pousser(
            #"{"id":2,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.b","new_state":{"entity_id":"light.b","state":"off","attributes":{}}}}}"#
        )
        try await attendre("pièce confirmée") {
            await b.nouvelles().contains(.commande(cle: "piece:salon", .confirmee))
        }
        await b.client.arreter()
    }
}
