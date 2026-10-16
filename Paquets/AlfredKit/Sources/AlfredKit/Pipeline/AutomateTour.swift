import Foundation

/// Un tour de conversation avec Alfred (`assist_pipeline/run`), sans réseau ni horloge : on lui donne ce qui arrive,
/// il rend ce qu'il faut faire (`Effet`). Porté de la console (`index.html`), règle par règle :
///
/// - un seul tour à la fois : une 2e demande pendant un tour est refusée ;
/// - les événements d'un AUTRE tour (périmés) sont ignorés ;
/// - l'audio reçu avant `run-start` est mis en file, pas jeté : c'est le début de la phrase ;
/// - la fin de parole est une trame binaire d'un seul octet (le canal) ; si elle survient avant `run-start`, elle part
///   juste après la file ;
/// - un refus de HA (`result` en échec pour ce tour) libère le tour ;
/// - au bout de 90 s sans fin, le tour échoue et on demande de vérifier la maison : une action n'est JAMAIS renvoyée
///   après un délai dépassé (elle a pu être exécutée).
public struct AutomateTour: Sendable {
    public enum Mode: Sendable, Equatable {
        case voix
        case texte(String)
    }

    public enum Effet: Sendable, Equatable {
        case envoyer(String)
        case envoyerAudio(Data)
        case armerDelai(Duration)
        case annulerDelai
        case signal(Signal)
    }

    public enum Signal: Sendable, Equatable {
        case transcrit(String)
        case reflechit
        case outilCommence(AppelOutil)
        case outilTermine(appelId: String, succes: Bool)
        case fragment(String)
        case reponse(FinIntention)
        case voix(chemin: String)
        /// Whisper n'a rien compris (`stt-no-text-recognized`) : en conversation, on réécoute sans drame.
        case rienSaisi(message: String)
        case echec(String)
        case termine(conversationId: String?, continuer: Bool)
    }

    public static let delaiPipeline: Duration = .seconds(90)
    public static let messageDelai =
        "Alfred n’a pas répondu dans le délai prévu. Vérifiez l’état de la maison avant de réessayer une commande."
    public static let tauxEchantillonnage = 16_000

    public private(set) var actif: Int?
    public private(set) var canal: UInt8?
    public private(set) var capture = false
    private var finDemandee = false
    private var file: [Data] = []
    private var outilsVus: Set<String> = []
    private var conversationId: String?
    private var continuer = false

    public init() {}

    public var occupe: Bool { actif != nil }

    /// Démarre un tour. nil si un tour est déjà en cours (demande en double refusée).
    /// `amorce` : l'audio capté juste avant l'attaque de la parole (conversation continue).
    public mutating func commencer(
        id: Int, mode: Mode, pipeline: String? = nil, conversationId: String? = nil,
        amorce: [Data] = []
    ) -> [Effet]? {
        guard actif == nil else { return nil }
        actif = id
        canal = nil
        finDemandee = false
        outilsVus = []
        self.conversationId = conversationId
        continuer = false
        var m: [String: ValeurJSON] = ["id": .nombre(Double(id)), "type": "assist_pipeline/run", "end_stage": "tts"]
        switch mode {
        case .voix:
            capture = true
            file = amorce
            m["start_stage"] = "stt"
            m["input"] = ["sample_rate": .nombre(Double(Self.tauxEchantillonnage)), "no_vad": true]
        case .texte(let t):
            capture = false
            file = []
            m["start_stage"] = "intent"
            m["input"] = ["text": .texte(t)]
        }
        if let pipeline { m["pipeline"] = .texte(pipeline) }
        if let conversationId { m["conversation_id"] = .texte(conversationId) }
        return [.envoyer(ValeurJSON.objet(m).enTexte()), .armerDelai(Self.delaiPipeline)]
    }

    /// Audio PCM 16 bits, 16 kHz, mono, petit-boutiste.
    public mutating func audio(_ pcm: Data) -> [Effet] {
        guard actif != nil, capture, !pcm.isEmpty else { return [] }
        guard let canal else {
            file.append(pcm)
            return []
        }
        var effets = vider(canal)
        effets.append(.envoyerAudio(Self.trame(canal, pcm)))
        return effets
    }

    /// Fin de la parole (décidée par l'app : HA demande une détection externe).
    public mutating func finParole() -> [Effet] {
        guard actif != nil, capture else { return [] }
        capture = false
        guard let canal else {
            finDemandee = true
            return []
        }
        return vider(canal) + [.envoyerAudio(Data([canal]))]
    }

    public mutating func recevoir(_ message: MessageEntrant) -> [Effet] {
        guard let actif else { return [] }
        switch message {
        case .resultat(let r) where r.id == actif && !r.succes:
            return terminer(.echec(r.erreur?.message ?? "La demande a été refusée."))
        case .evenement(let id, .pipeline(let e)) where id == actif:
            return evenement(e)
        default:
            return []
        }
    }

    public mutating func delaiDepasse() -> [Effet] {
        guard actif != nil else { return [] }
        return terminer(.echec(Self.messageDelai))
    }

    public mutating func lienCoupe() -> [Effet] {
        guard actif != nil else { return [] }
        return terminer(.echec("Liaison interrompue avec la maison."))
    }

    // MARK: - interne

    private mutating func evenement(_ e: EvenementPipeline) -> [Effet] {
        switch e {
        case .debut(let c, let conv):
            if let conv { conversationId = conv }
            guard let c else { return [] }
            canal = c
            var effets = vider(c)
            if !capture && finDemandee {
                finDemandee = false
                effets.append(.envoyerAudio(Data([c])))
            }
            return effets
        case .transcription(let t):
            capture = false
            return (t.isEmpty ? [] : [.signal(.transcrit(t))]) + [.signal(.reflechit)]
        case .progression(let d):
            var effets: [Effet] = []
            for a in d.appels where !outilsVus.contains(a.id) {
                outilsVus.insert(a.id)
                effets.append(.signal(.outilCommence(a)))
            }
            if let r = d.resultat, outilsVus.contains(r.appelId) {
                effets.append(.signal(.outilTermine(appelId: r.appelId, succes: r.succes)))
            }
            if let c = d.contenu { effets.append(.signal(.fragment(c))) }
            return effets
        case .intention(let fin):
            if let c = fin.conversationId { conversationId = c }
            continuer = fin.continuer
            return [.signal(.reponse(fin))]
        case .voix(let chemin):
            return [.signal(.voix(chemin: chemin))]
        case .erreur(let code, let message):
            if code == "stt-no-text-recognized" {
                return terminer(.rienSaisi(message: message ?? "Je n’ai rien saisi."))
            }
            return terminer(.echec(message ?? code ?? "erreur du pipeline"))
        case .fin:
            return terminer(.termine(conversationId: conversationId, continuer: continuer))
        case .autre:
            return []
        }
    }

    private mutating func vider(_ canal: UInt8) -> [Effet] {
        defer { file = [] }
        return file.map { .envoyerAudio(Self.trame(canal, $0)) }
    }

    private mutating func terminer(_ s: Signal) -> [Effet] {
        actif = nil
        canal = nil
        capture = false
        finDemandee = false
        file = []
        return [.annulerDelai, .signal(s)]
    }

    static func trame(_ canal: UInt8, _ pcm: Data) -> Data {
        var d = Data([canal])
        d.append(pcm)
        return d
    }
}
