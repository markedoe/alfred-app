import Foundation
import Security

/// La confiance TLS envers le relais.
///
/// Avec une autorité de la maison, elle est ÉPINGLÉE : pour l'hôte du relais, seule cette autorité est acceptée
/// (pas les autorités du système, ni un profil installé sur l'appareil). Les règles de TLS d'iOS restent appliquées
/// (nom d'hôte, durée, algorithmes). Sans autorité, ou pour un autre hôte : le traitement normal du système.
///
/// Accepter une autorité que le système ne connaît pas ASSOUPLIT sa confiance, ce qu'App Transport Security interdit
/// pour un domaine qu'il protège (Apple, « Performing Manual Server Trust Authentication ») : la fabrication déclare
/// donc le relais en exception d'ATS quand elle épingle son autorité (`scripts/generer.sh`).
struct ConfianceTLS: Sendable {
    let hote: String
    let autorite: Data?

    enum Decision: Equatable {
        case parDefaut
        case accepter
        /// `code` : l'erreur de Security qui fait refuser la chaîne (par exemple -67602 pour le nom d'hôte) ; nil s'il
        /// n'y a aucune chaîne à évaluer.
        case refuser(code: Int?)
    }

    func decider(_ defi: URLAuthenticationChallenge) -> Decision {
        let espace = defi.protectionSpace
        return decider(methode: espace.authenticationMethod, hote: espace.host, confiance: espace.serverTrust)
    }

    func decider(methode: String, hote h: String, confiance: SecTrust?) -> Decision {
        guard methode == NSURLAuthenticationMethodServerTrust else { return .parDefaut }
        guard h.caseInsensitiveCompare(hote) == .orderedSame, let autorite else { return .parDefaut }
        guard let confiance, let ancre = SecCertificateCreateWithData(nil, autorite as CFData) else {
            return .refuser(code: nil)
        }
        return Self.refus(confiance, hote: h, ancre: ancre).map { .refuser(code: $0) } ?? .accepter
    }

    static func evaluer(_ confiance: SecTrust, hote: String, ancre: SecCertificate) -> Bool {
        refus(confiance, hote: hote, ancre: ancre) == nil
    }

    /// nil si la chaîne est acceptée ; sinon le code de l'erreur de Security qui la fait refuser.
    static func refus(_ confiance: SecTrust, hote: String, ancre: SecCertificate) -> Int? {
        let reglages = [
            SecTrustSetPolicies(confiance, SecPolicyCreateSSL(true, hote as CFString)),
            SecTrustSetAnchorCertificates(confiance, [ancre] as CFArray),
            SecTrustSetAnchorCertificatesOnly(confiance, true),
        ]
        if let echec = reglages.first(where: { $0 != errSecSuccess }) { return Int(echec) }
        var erreur: CFError?
        guard !SecTrustEvaluateWithError(confiance, &erreur) else { return nil }
        return erreur.map { CFErrorGetCode($0) } ?? Int(errSecNotTrusted)
    }

    /// La réponse à donner à un défi d'authentification (URLSession ou WebKit).
    func repondre(_ defi: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        Self.reponse(decider(defi), a: defi)
    }

    static func reponse(
        _ decision: Decision, a defi: URLAuthenticationChallenge
    )
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        switch decision {
        case .parDefaut: return (.performDefaultHandling, nil)
        case .refuser: return (.cancelAuthenticationChallenge, nil)
        case .accepter:
            guard let confiance = defi.protectionSpace.serverTrust else { return (.cancelAuthenticationChallenge, nil) }
            return (.useCredential, URLCredential(trust: confiance))
        }
    }
}
