import AlfredKit
import Foundation

/// L'accès au relais par URLSession : session éphémère (aucun cache, aucun cookie sur disque), cookie de la personne
/// posé dans le magasin de cookies de CETTE session, autorité de la maison épinglée, TLS 1.2 au moins.
final class AccesURLSession: NSObject, AccesRelais, URLSessionDelegate, @unchecked Sendable {
    let relais: Relais
    private let confiance: ConfianceTLS
    // Écrite une seule fois dans init, lue ensuite seulement : sûre entre fils (d'où @unchecked Sendable).
    private var session: URLSession!

    /// Taille maximale d'un message de la WebSocket : l'état complet de la maison pèse déjà ~0,7 Mo (mesuré le 16.10)
    /// et la limite par défaut d'URLSession est de 1 Mo.
    static let tailleMessageMax = 16 * 1024 * 1024

    init(configuration: ConfigurationMaison, session cookie: SessionRelais) {
        relais = configuration.relais
        confiance = ConfianceTLS(hote: configuration.relais.hote, autorite: configuration.autorite)
        super.init()
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        if let cookie = cookie.cookie(pour: relais) { c.httpCookieStorage?.setCookie(cookie) }
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 15
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": Self.agent]
        session = URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }

    /// Ferme la session (déconnexion) ; l'accès n'est plus utilisable ensuite.
    func fermer() {
        session.invalidateAndCancel()
    }

    static let agent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return "Alfred/\(version) (iPhone)"
    }()

    // MARK: AccesRelais

    func ouvrir() async throws -> any Liaison {
        var requete = URLRequest(url: relais.webSocket)
        // le relais accepte sa propre origine, et refuse une page d'une autre origine
        requete.setValue(relais.base.absoluteString, forHTTPHeaderField: "Origin")
        let tache = session.webSocketTask(with: requete)
        tache.maximumMessageSize = Self.tailleMessageMax
        tache.resume()
        return LiaisonWebSocket(tache: tache)
    }

    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) {
        let (corps, reponse) = try await session.data(from: relais.url(chemin))
        return ((reponse as? HTTPURLResponse)?.statusCode ?? 0, corps)
    }

    /// Les octets d'une ressource du relais, au fil de leur arrivée (la voix d'Alfred se lit pendant sa synthèse).
    func flux(_ chemin: String) async throws -> URLSession.AsyncBytes {
        let (octets, reponse) = try await session.bytes(from: relais.url(chemin))
        guard (reponse as? HTTPURLResponse)?.statusCode == 200 else { throw ErreurRelais("ressource indisponible") }
        return octets
    }

    /// Une ressource entière (clips d'accueil).
    func telecharger(_ chemin: String) async throws -> Data {
        let (statut, corps) = try await lire(chemin)
        guard statut == 200 else { throw ErreurRelais("ressource indisponible (\(statut))") }
        return corps
    }

    // MARK: URLSessionDelegate

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        confiance.repondre(challenge)
    }
}

/// La WebSocket du relais.
final class LiaisonWebSocket: Liaison, @unchecked Sendable {
    // URLSessionWebSocketTask est sûre entre fils (ses méthodes peuvent être appelées de n'importe où).
    private let tache: URLSessionWebSocketTask

    init(tache: URLSessionWebSocketTask) {
        self.tache = tache
    }

    func envoyer(_ trame: Trame) async throws {
        switch trame {
        case .texte(let t): try await tache.send(.string(t))
        case .binaire(let d): try await tache.send(.data(d))
        }
    }

    func recevoir() async throws -> Trame {
        switch try await tache.receive() {
        case .string(let t): return .texte(t)
        case .data(let d): return .binaire(d)
        @unknown default: throw ErreurRelais("trame inconnue")
        }
    }

    func fermer() async {
        tache.cancel(with: .goingAway, reason: nil)
    }
}
