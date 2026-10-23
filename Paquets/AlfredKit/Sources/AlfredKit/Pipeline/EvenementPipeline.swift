import Foundation

/// Une étape du pipeline d'Assist (`assist_pipeline/run`).
///
/// Formes relevées par la console sur HA 2026.9 :
/// - le 2e `tool_calls` et les suivants arrivent SANS champ `role` ;
/// - pas de `tts_start_streaming` : la voix arrive par `tts-end` et son URL ;
/// - le contenu des résultats d'outils n'est jamais montré (l'agenda est privé) : seul leur succès compte.
public enum EvenementPipeline: Sendable, Equatable {
    /// `run-start` : le numéro du canal binaire où envoyer l'audio.
    case debut(canalAudio: UInt8?, conversationId: String?)
    /// `stt-end` : ce que Whisper a compris.
    case transcription(String)
    /// `intent-progress` : appels d'outils, résultats, morceaux de réponse.
    case progression(DeltaConversation)
    /// `intent-end` : la réponse complète.
    case intention(FinIntention)
    /// `tts-end` : le chemin de la voix sur le relais (`/tts/<jeton>`).
    case voix(chemin: String)
    case erreur(code: String?, message: String?)
    /// `run-end`
    case fin
    case autre(String)

    public init(type: String, donnees d: ValeurJSON) {
        switch type {
        case "run-start":
            let canal = d["runner_data"]?["stt_binary_handler_id"]?.entier
            self = .debut(canalAudio: canal.flatMap { UInt8(exactly: $0) }, conversationId: d["conversation_id"]?.texte)
        case "stt-end":
            self = .transcription(d["stt_output"]?["text"]?.texte ?? "")
        case "intent-progress":
            self = .progression(DeltaConversation(d["chat_log_delta"] ?? .nul))
        case "intent-end":
            self = .intention(FinIntention(d))
        case "tts-end":
            // la console ne garde que le dernier segment de l'URL de HA et le sert par son propre relais
            let url = d["tts_output"]?["url"]?.texte ?? ""
            let jeton = url.split(separator: "/").last.map(String.init) ?? ""
            self = jeton.isEmpty ? .autre(type) : .voix(chemin: "/tts/" + jeton)
        case "error":
            self = .erreur(code: d["code"]?.texte, message: d["message"]?.texte)
        case "run-end":
            self = .fin
        default:
            self = .autre(type)
        }
    }
}

public struct DeltaConversation: Sendable, Equatable {
    public let appels: [AppelOutil]
    public let resultat: ResultatOutil?
    public let contenu: String?

    public init(appels: [AppelOutil] = [], resultat: ResultatOutil? = nil, contenu: String? = nil) {
        self.appels = appels
        self.resultat = resultat
        self.contenu = contenu
    }

    init(_ dl: ValeurJSON) {
        appels = (dl["tool_calls"]?.liste ?? []).compactMap(AppelOutil.init)
        if dl["role"]?.texte == "tool_result", let id = dl["tool_call_id"]?.texte {
            // un résultat sans `success: false` est un succès (règle de la console)
            let r = dl["tool_result"]
            // la réponse d'un script : `{success, result: {…}}` ; une enveloppe `{data: …}` est lue aussi (`relaisHermes`)
            let reponse = r?["result"] ?? r?["data"]?["result"] ?? r?["data"]
            resultat = ResultatOutil(
                appelId: id, succes: r?["success"]?.booleen != false, hermes: reponse?["hermes"]?.booleen == true)
        } else {
            resultat = nil
        }
        contenu = dl["content"]?.texte.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct AppelOutil: Sendable, Equatable, Identifiable {
    public let id: String
    public let nom: String
    public let arguments: ValeurJSON

    public init(id: String, nom: String, arguments: ValeurJSON = .objet([:])) {
        self.id = id
        self.nom = nom
        self.arguments = arguments
    }

    init?(_ v: ValeurJSON) {
        guard let id = v["id"]?.texte, let nom = v["tool_name"]?.texte else { return nil }
        self.init(id: id, nom: nom, arguments: v["tool_args"] ?? .objet([:]))
    }

    /// Le nom sans le préfixe de l'API de HA (`homeassistant__HassTurnOn` → `HassTurnOn`).
    public var nomCourt: String {
        for p in ["homeassistant__", "hass__"] where nom.hasPrefix(p) { return String(nom.dropFirst(p.count)) }
        return nom
    }

    /// Les arguments comme la console les montre dans « Détails techniques » (`argsOf`) : les valeurs, séparées par des
    /// virgules, un objet ou une liste en JSON. Les clés sont dans l'ordre alphabétique (la console garde l'ordre
    /// d'arrivée, qu'un dictionnaire ne connaît pas).
    public var argumentsEnTexte: String {
        guard case .objet(let o) = arguments else { return Self.texte(arguments) }
        return o.sorted { $0.key < $1.key }.map { Self.texte($0.value) }.joined(separator: ", ")
    }

    /// `String(v)` de JavaScript pour une valeur simple, `JSON.stringify` pour un objet ou une liste.
    static func texte(_ v: ValeurJSON) -> String {
        switch v {
        case .texte(let t): return t
        case .booleen(let b): return b ? "true" : "false"
        case .nul: return "null"
        case .nombre(let n):
            if n.rounded() == n, abs(n) < 1e15 { return String(Int(n)) }
            return "\(n)"
        case .liste, .objet: return v.enTexte()
        }
    }

    /// Les entités nommées dans les arguments (pour montrer la pièce visée).
    public var entitesVisees: [String] {
        var vues: [String] = []
        func parcourir(_ v: ValeurJSON) {
            switch v {
            case .texte(let t) where t.contains("."): vues.append(t)
            case .liste(let l): l.forEach(parcourir)
            case .objet(let o): o.keys.sorted().forEach { parcourir(o[$0]!) }
            default: break
            }
        }
        parcourir(arguments)
        return vues
    }
}

public struct ResultatOutil: Sendable, Equatable {
    public let appelId: String
    public let succes: Bool
    /// L'outil n'a rien trouvé et le relais a confié la question à Hermes (outils mémoire et e-mails, `hermes: true`) :
    /// sa réponse arrivera plus tard, comme après `demander_hermes`.
    public let hermes: Bool

    public init(appelId: String, succes: Bool, hermes: Bool = false) {
        self.appelId = appelId
        self.succes = succes
        self.hermes = hermes
    }
}

public struct FinIntention: Sendable, Equatable {
    public let conversationId: String?
    /// HA attend une suite (la réponse finit par une question) : réécouter sans nouveau toucher.
    public let continuer: Bool
    public let texte: String
    /// Comprise par les intentions locales de HA, sans le modèle.
    public let traiteeLocalement: Bool

    public init(conversationId: String? = nil, continuer: Bool = false, texte: String, traiteeLocalement: Bool = false)
    {
        self.conversationId = conversationId
        self.continuer = continuer
        self.texte = texte
        self.traiteeLocalement = traiteeLocalement
    }

    init(_ d: ValeurJSON) {
        let io = d["intent_output"] ?? .nul
        self.init(
            conversationId: io["conversation_id"]?.texte,
            continuer: io["continue_conversation"]?.booleen ?? false,
            texte: io["response"]?["speech"]?["plain"]?["speech"]?.texte ?? "",
            traiteeLocalement: d["processed_locally"]?.booleen ?? false)
    }
}
