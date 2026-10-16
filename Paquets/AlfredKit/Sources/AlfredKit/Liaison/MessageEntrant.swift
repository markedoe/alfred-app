import Foundation

/// Un message texte reçu du relais (`/ws`). Le relais s'authentifie auprès de Home Assistant à notre place :
/// il envoie `ready` (ou `fatal`), puis transmet les messages de HA tels quels.
public enum MessageEntrant: Sendable, Equatable {
    case pret(versionHA: String?)
    case fatal(String)
    case resultat(Resultat)
    case evenement(id: Int?, EvenementHA)
    case autre(type: String?)

    public struct Resultat: Sendable, Equatable {
        public let id: Int?
        public let succes: Bool
        public let valeur: ValeurJSON?
        public let erreur: ErreurHA?
    }

    public struct ErreurHA: Sendable, Equatable {
        public let code: String?
        public let message: String?
    }

    /// nil si le texte n'est pas un objet JSON (ignoré, comme dans la console).
    public static func lire(_ texte: String) -> MessageEntrant? {
        guard let m = ValeurJSON.lire(texte), m.objet != nil else { return nil }
        let type = m["type"]?.texte
        switch type {
        case "ready":
            return .pret(versionHA: m["ha_version"]?.texte)
        case "fatal":
            return .fatal(m["message"]?.texte ?? "erreur du relais")
        case "result":
            let e = m["error"].flatMap { e -> ErreurHA? in
                e.objet == nil ? nil : ErreurHA(code: e["code"]?.texte, message: e["message"]?.texte)
            }
            return .resultat(
                Resultat(
                    id: m["id"]?.entier, succes: m["success"]?.booleen ?? false,
                    valeur: m["result"], erreur: e))
        case "event":
            return .evenement(id: m["id"]?.entier, EvenementHA(m["event"] ?? .nul))
        default:
            return .autre(type: type)
        }
    }
}

/// Le contenu d'un message `event` : un changement d'état (abonnement) ou une étape du pipeline d'Assist.
public enum EvenementHA: Sendable, Equatable {
    case etatChange(entite: String, nouvelEtat: EtatEntite?)
    case pipeline(EvenementPipeline)
    case autre

    init(_ e: ValeurJSON) {
        if e["event_type"]?.texte == "state_changed" {
            let d = e["data"] ?? .nul
            guard let entite = d["entity_id"]?.texte else {
                self = .autre
                return
            }
            self = .etatChange(entite: entite, nouvelEtat: EtatEntite(d["new_state"] ?? .nul))
            return
        }
        if let t = e["type"]?.texte {
            self = .pipeline(EvenementPipeline(type: t, donnees: e["data"] ?? .nul))
            return
        }
        self = .autre
    }
}

/// L'état d'une entité de HA, tel que `get_states` ou `state_changed` le donnent.
public struct EtatEntite: Sendable, Equatable {
    public let id: String
    public let etat: String
    public let attributs: [String: ValeurJSON]
    public let derniereModification: String?

    public init(id: String, etat: String, attributs: [String: ValeurJSON] = [:], derniereModification: String? = nil) {
        self.id = id
        self.etat = etat
        self.attributs = attributs
        self.derniereModification = derniereModification
    }

    /// nil pour un état absent (`new_state: null` = entité supprimée).
    public init?(_ v: ValeurJSON) {
        guard let id = v["entity_id"]?.texte, let etat = v["state"]?.texte else { return nil }
        self.init(
            id: id, etat: etat, attributs: v["attributes"]?.objet ?? [:],
            derniereModification: v["last_changed"]?.texte)
    }

    public var domaine: String { String(id.prefix { $0 != "." }) }
    public var nom: String { attributs["friendly_name"]?.texte ?? id }
    /// `unknown` et `unavailable` : la valeur n'est pas connue.
    public var disponible: Bool { etat != "unknown" && etat != "unavailable" }
    /// Valeur numérique ; nil si l'état n'est pas un nombre complet (« 23oops » → nil, comme `numOf` de la console).
    public var nombre: Double? {
        guard disponible, let n = Double(etat), n.isFinite else { return nil }
        return n
    }
}
