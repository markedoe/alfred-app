import Foundation

/// L'état de la maison vu par l'app : `get_states` au départ, puis chaque `state_changed`.
public struct Maison: Sendable, Equatable {
    public private(set) var etats: [String: EtatEntite] = [:]

    public init() {}

    public init(etats: [EtatEntite]) {
        for e in etats { self.etats[e.id] = e }
    }

    public subscript(id: String) -> EtatEntite? { etats[id] }

    /// Ne garde que les entités utiles à l'app (les lumières et les capteurs des pièces, sur 1 500 et plus).
    public mutating func garder(_ utile: (EtatEntite) -> Bool) {
        etats = etats.filter { utile($0.value) }
    }

    /// Remplace tout (résultat de `get_states`).
    public mutating func charger(_ resultat: ValeurJSON?) {
        etats = [:]
        for v in resultat?.liste ?? [] {
            if let e = EtatEntite(v) { etats[e.id] = e }
        }
    }

    /// Applique un changement ; rend l'ancien état (pour savoir si la valeur a vraiment changé).
    @discardableResult
    public mutating func appliquer(entite: String, nouvelEtat: EtatEntite?) -> EtatEntite? {
        let ancien = etats[entite]
        etats[entite] = nouvelEtat
        return ancien
    }

    public func entites(domaine: String) -> [EtatEntite] {
        etats.values.filter { $0.domaine == domaine }.sorted {
            $0.nom.localizedStandardCompare($1.nom) == .orderedAscending
        }
    }

    public var lumieres: [EtatEntite] { entites(domaine: "light") }
}

/// L'issue d'une commande : confirmée par l'état REÇU de HA (pas par la réponse du service), comme la console :
/// « allumé » ne s'affiche que quand HA dit `on`. Sans confirmation en 8 s : échec visible.
public enum IssueCommande: Sendable, Equatable {
    case confirmee
    case refusee(String)
    case sansConfirmation
}

/// Allumer ou éteindre une lumière.
public struct CommandeLumiere: Sendable, Equatable {
    public let entite: String
    public let voulu: String

    /// nil si l'état actuel n'est ni `on` ni `off` (indisponible : on ne devine pas).
    public init?(basculer etat: EtatEntite) {
        guard etat.domaine == "light", etat.etat == "on" || etat.etat == "off" else { return nil }
        entite = etat.id
        voulu = etat.etat == "on" ? "off" : "on"
    }

    public var message: ValeurJSON {
        [
            "type": "call_service", "domain": "light", "service": .texte(voulu == "on" ? "turn_on" : "turn_off"),
            "target": ["entity_id": .texte(entite)],
        ]
    }

    public func confirmee(par etat: EtatEntite?) -> Bool { etat?.id == entite && etat?.etat == voulu }
}

/// Une commande de la maison envoyée par l'app (toutes passent la liste blanche du relais : lumières seulement).
public enum Commande: Sendable, Equatable {
    case lumiere(CommandeLumiere)
    case piece(CommandePiece)
    case luminosite(CommandeLuminosite)

    public static let delaiConfirmation: Duration = .seconds(8)

    /// Une seule commande à la fois par lumière ou par pièce.
    public var cle: String {
        switch self {
        case .lumiere(let c): c.entite
        case .piece(let c): "piece:" + c.piece
        case .luminosite(let c): c.entite
        }
    }

    public var message: ValeurJSON {
        switch self {
        case .lumiere(let c): c.message
        case .piece(let c): c.message
        case .luminosite(let c): c.message
        }
    }

    /// La maison a-t-elle suivi ?
    public func confirmee(maison: Maison, structure: StructureMaison) -> Bool {
        switch self {
        case .lumiere(let c): return c.confirmee(par: maison[c.entite])
        case .luminosite(let c): return c.confirmee(par: maison[c.entite])
        case .piece(let c):
            let vue = maison.vue(structure).flatMap(\.pieces).first { $0.id == c.piece }
            return c.confirmee(par: vue)
        }
    }
}
