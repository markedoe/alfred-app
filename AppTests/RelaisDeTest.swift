import AlfredKit
import Foundation

@testable import Alfred

/// Le relais joué par les tests de l'app (aucun réseau). Il répond à la synchronisation et à `/moi` ; un tour écrit
/// reçoit une courte réponse lue (fil « fil-test ») ; un tour à la voix reste en vol (la personne parle encore) ; un
/// tour peut être refusé ; la liaison peut tomber. Il garde chaque tour demandé et le fil envoyé.
final class RelaisDeTest: AccesRelais, @unchecked Sendable {
    static let reponse = "C’est fait."
    static let fil = "fil-test"

    let etats: ValeurJSON
    private let verrou = NSLock()
    private var _liaisons: [LiaisonDeTest] = []
    private var _refuserTours = false
    private var _connecte = true
    private var _deconnexions = 0
    private var _avantStructure: (@Sendable () async -> Void)?
    private var _repondreALaVoix = false
    private var _diags: [[String: String]] = []

    init(etats: ValeurJSON = []) {
        self.etats = etats
    }

    var liaisons: [LiaisonDeTest] { verrou.withLock { _liaisons } }
    /// Les tours des liaisons ouvertes ENSUITE sont refusés par la maison.
    var refuserTours: Bool {
        get { verrou.withLock { _refuserTours } }
        set { verrou.withLock { _refuserTours = newValue } }
    }
    /// La réponse de `/moi` (false : la session a expiré).
    var connecte: Bool {
        get { verrou.withLock { _connecte } }
        set { verrou.withLock { _connecte = newValue } }
    }
    var deconnexions: Int { verrou.withLock { _deconnexions } }
    /// 30.10 : les liaisons ouvertes ENSUITE ouvrent le canal du son d'un tour à la voix (run-start) et y répondent à la
    /// fin de la phrase (marqueur d'un octet) ; sinon le tour reste en vol.
    var repondreALaVoix: Bool {
        get { verrou.withLock { _repondreALaVoix } }
        set { verrou.withLock { _repondreALaVoix = newValue } }
    }
    /// Attendue avant de répondre à `/maison/structure` : un test y retient la synchronisation.
    var avantStructure: (@Sendable () async -> Void)? {
        get { verrou.withLock { _avantStructure } }
        set { verrou.withLock { _avantStructure = newValue } }
    }

    func ouvrir() async throws -> any Liaison {
        let l = LiaisonDeTest(etats: etats, refuser: refuserTours, repondreALaVoix: repondreALaVoix)
        verrou.withLock { _liaisons.append(l) }
        await l.pousser(["type": "ready", "ha_version": "test"])
        return l
    }

    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) {
        switch chemin {
        case "/moi":
            let moi: ValeurJSON = ["connecte": .booleen(connecte), "nom": "Test", "user_id": .nul, "titre": .nul]
            return (200, Data(moi.enTexte().utf8))
        case "/deconnexion":
            verrou.withLock { _deconnexions += 1 }
            return (200, Data())
        case "/maison/structure":
            if let attendre = avantStructure { await attendre() }
            return (404, Data())
        default:
            return (404, Data())
        }
    }

    /// Tous les tours demandés, liaison après liaison.
    func tours() async -> [TourDeTest] {
        var tous: [TourDeTest] = []
        for l in liaisons { tous += await l.tours }
        return tous
    }

    /// Les étapes de la voix notées par l'app (`POST /diag`, 30.10).
    var diags: [[String: String]] { verrou.withLock { _diags } }

    func envoyer(_ requete: RequeteRelais) async throws -> (statut: Int, corps: Data) {
        guard requete.chemin == "/diag", let corps = requete.corps,
            let d = try JSONSerialization.jsonObject(with: corps) as? [String: String]
        else { return (404, Data()) }
        verrou.withLock { _diags.append(d) }
        return (200, Data("ok".utf8))
    }

    /// Les fins de phrase reçues (marqueur d'un octet), liaison après liaison.
    func finsDeParole() async -> Int {
        var n = 0
        for l in liaisons { n += await l.finsDeParole }
        return n
    }

    /// Les tours dont l'app s'est désabonnée (micro coupé pendant une phrase : la maison annule le tour).
    func desabonnements() async -> [Int] {
        var tous: [Int] = []
        for l in liaisons { tous += await l.desabonnements }
        return tous
    }
}

/// Un tour demandé à la maison : à la voix ou écrit, et le fil envoyé (nil : un fil neuf).
struct TourDeTest: Equatable, Sendable {
    let voix: Bool
    let fil: String?
}

actor LiaisonDeTest: Liaison {
    private let etats: ValeurJSON
    private let refuser: Bool
    private var file: [Trame] = []
    private var attente: CheckedContinuation<Trame, Error>?
    private var fermee = false
    private(set) var tours: [TourDeTest] = []
    private(set) var desabonnements: [Int] = []
    private(set) var finsDeParole = 0
    private let repondreALaVoix: Bool
    private var tourALaVoix: ValeurJSON?

    init(etats: ValeurJSON, refuser: Bool, repondreALaVoix: Bool = false) {
        self.etats = etats
        self.refuser = refuser
        self.repondreALaVoix = repondreALaVoix
    }

    func envoyer(_ trame: Trame) async throws {
        if fermee { throw ErreurRelais.lienCoupe }
        if case .binaire(let d) = trame {
            // la fin de la phrase : le marqueur seul (le numéro du canal)
            if d.count == 1, let id = tourALaVoix {
                finsDeParole += 1
                tourALaVoix = nil
                repondre(id, dejaOuvert: true)
            }
            return
        }
        guard case .texte(let t) = trame, let m = ValeurJSON.lire(t), let id = m["id"] else { return }
        switch m["type"]?.texte {
        case "get_states":
            pousser(["id": id, "type": "result", "success": true, "result": etats])
        case "subscribe_events":
            pousser(["id": id, "type": "result", "success": true, "result": .nul])
        case "unsubscribe_events":
            if case .nombre(let n) = m["subscription"] { desabonnements.append(Int(n)) }
            pousser(["id": id, "type": "result", "success": true, "result": .nul])
        case "assist_pipeline/pipeline/list":
            pousser([
                "id": id, "type": "result", "success": true, "result": ["pipelines": [], "preferred_pipeline": .nul],
            ])
        case "assist_pipeline/run":
            let voix = m["start_stage"]?.texte == "stt"
            tours.append(TourDeTest(voix: voix, fil: m["conversation_id"]?.texte))
            if refuser {
                pousser([
                    "id": id, "type": "result", "success": false,
                    "error": ["code": "refuse", "message": "Tour refusé par la maison."],
                ])
            } else if !voix {
                repondre(id)
            } else if repondreALaVoix {
                tourALaVoix = id
                pousser(["id": id, "type": "result", "success": true, "result": .nul])
                pousser(
                    evenement(
                        id, "run-start",
                        ["conversation_id": .texte(RelaisDeTest.fil), "runner_data": ["stt_binary_handler_id": 1]]))
            }
        // à la voix : le tour reste en vol, comme quand la personne parle encore
        default:
            break
        }
    }

    private func evenement(_ id: ValeurJSON, _ type: String, _ data: ValeurJSON = [:]) -> ValeurJSON {
        ["id": id, "type": "event", "event": ["type": .texte(type), "data": data]]
    }

    private func repondre(_ id: ValeurJSON, dejaOuvert: Bool = false) {
        if dejaOuvert {
            pousser(evenement(id, "stt-end", ["stt_output": ["text": "Quelle heure est-il"]]))
        } else {
            pousser(["id": id, "type": "result", "success": true, "result": .nul])
            pousser(evenement(id, "run-start", ["conversation_id": .texte(RelaisDeTest.fil), "runner_data": [:]]))
        }
        pousser(
            evenement(
                id, "intent-end",
                [
                    "processed_locally": false,
                    "intent_output": [
                        "conversation_id": .texte(RelaisDeTest.fil), "continue_conversation": false,
                        "response": ["speech": ["plain": ["speech": .texte(RelaisDeTest.reponse)]]],
                    ],
                ]))
        pousser(evenement(id, "tts-end", ["tts_output": ["url": "/api/tts_proxy/test.mp3"]]))
        pousser(evenement(id, "run-end"))
    }

    func pousser(_ m: ValeurJSON) {
        let t = Trame.texte(m.enTexte())
        if let a = attente {
            attente = nil
            a.resume(returning: t)
        } else {
            file.append(t)
        }
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
}

/// Une porte fermée jusqu'à `ouvrir()` (retenir une étape, puis la libérer).
actor PorteDeTest {
    private var ouverte = false
    private var attentes: [CheckedContinuation<Void, Never>] = []

    func passer() async {
        if ouverte { return }
        await withCheckedContinuation { attentes.append($0) }
    }

    func ouvrir() {
        ouverte = true
        attentes.forEach { $0.resume() }
        attentes = []
    }
}

/// Une voix d'appareil pour les tests (pas la voix muette de la démo) : rien ne sonne.
@MainActor
final class VoixDeTest: MoteurVoix {
    private var continuation: AsyncStream<[Float]>.Continuation?
    var surInterruption: (@MainActor (_ motif: String?) -> Void)?
    var entreeChoisie: String?
    var entreeOubliee = false

    func autoriserMicro() async -> Bool { true }
    func ouvrirMicro() throws -> AsyncStream<[Float]> {
        let (flux, cont) = AsyncStream.makeStream(of: [Float].self)
        continuation = cont
        return flux
    }
    func fermerMicro() {
        continuation?.finish()
        continuation = nil
    }
    func lire(_ chemin: String) async {}
    func interrompre() {}
    func accueillir() {}
    var niveauVoix: Float { 0 }
    func entrees() -> [EntreeMicro] { [] }
}
