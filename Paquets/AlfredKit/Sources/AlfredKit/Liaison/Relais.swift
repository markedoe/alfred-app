import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Le relais de la console Alfred : le serveur de l'app. Il tient le jeton de Home Assistant (qui ne sort jamais),
/// filtre les commandes (liste blanche) et sert la voix. Contrat : `docs/contrat-relais.md`.
public struct Relais: Sendable, Equatable {
    public let base: URL

    /// `base` : l'adresse https du relais (sans chemin). nil si ce n'est pas une adresse https.
    public init?(base: URL) {
        guard base.scheme == "https", base.host != nil else { return nil }
        self.base = base
    }

    public init?(adresse: String) {
        var a = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.contains("://") { a = "https://" + a }
        while a.hasSuffix("/") { a.removeLast() }
        guard let u = URL(string: a), u.path.isEmpty else { return nil }
        self.init(base: u)
    }

    public var hote: String { base.host ?? "" }

    /// La WebSocket de HA, à travers le relais.
    public var webSocket: URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.scheme = "wss"
        c.path = "/ws"
        return c.url!
    }

    public func url(_ chemin: String) -> URL {
        URL(string: chemin, relativeTo: base)!.absoluteURL
    }

    public var moi: URL { url("/moi") }
    public var connexion: URL { url("/connexion") }
    public var deconnexion: URL { url("/deconnexion") }
    public var version: URL { url("/version") }
}

/// Réponse de `GET /moi`.
public struct Moi: Sendable, Equatable, Decodable {
    public let connecte: Bool
    public let nom: String?
    public let userId: String?
    /// « Monsieur », « Madame », « Mademoiselle » ou vide (invité).
    public let titre: String?

    public init(connecte: Bool, nom: String? = nil, userId: String? = nil, titre: String? = nil) {
        self.connecte = connecte
        self.nom = nom
        self.userId = userId
        self.titre = titre
    }

    enum CodingKeys: String, CodingKey {
        case connecte, nom, titre
        case userId = "user_id"
    }
}

/// La session de l'app auprès du relais : le cookie `alfred_session` posé à la connexion (compte HA de la personne).
public struct SessionRelais: Sendable, Equatable, Codable {
    public static let nomCookie = "alfred_session"
    public let valeur: String

    public init(valeur: String) { self.valeur = valeur }

    /// Le cookie à placer dans le magasin de cookies de la session réseau de l'app (jamais un en-tête écrit à la main :
    /// URLSession peut le remplacer).
    public func cookie(pour relais: Relais) -> HTTPCookie? {
        HTTPCookie(properties: [
            .name: Self.nomCookie, .value: valeur, .domain: relais.hote, .path: "/",
            .secure: "TRUE",
        ])
    }
}
