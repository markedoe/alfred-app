import Foundation
import Security

/// La confiance TLS envers le relais.
///
/// Avec une autorité de la maison, elle est ÉPINGLÉE : pour l'hôte du relais, seule cette autorité est acceptée
/// (pas les autorités du système, ni un profil installé sur l'appareil). Les règles de TLS d'iOS restent appliquées
/// (nom d'hôte, durée, algorithmes). Sans autorité, ou pour un autre hôte : le traitement normal du système.
struct ConfianceTLS: Sendable {
    let hote: String
    let autorite: Data?

    enum Decision: Equatable {
        case parDefaut
        case accepter
        case refuser
    }

    func decider(methode: String, hote h: String, confiance: SecTrust?) -> Decision {
        guard methode == NSURLAuthenticationMethodServerTrust else { return .parDefaut }
        guard h.caseInsensitiveCompare(hote) == .orderedSame, let autorite else { return .parDefaut }
        guard let confiance, let ancre = SecCertificateCreateWithData(nil, autorite as CFData) else { return .refuser }
        return Self.evaluer(confiance, hote: h, ancre: ancre) ? .accepter : .refuser
    }

    static func evaluer(_ confiance: SecTrust, hote: String, ancre: SecCertificate) -> Bool {
        guard SecTrustSetPolicies(confiance, SecPolicyCreateSSL(true, hote as CFString)) == errSecSuccess,
            SecTrustSetAnchorCertificates(confiance, [ancre] as CFArray) == errSecSuccess,
            SecTrustSetAnchorCertificatesOnly(confiance, true) == errSecSuccess
        else { return false }
        return SecTrustEvaluateWithError(confiance, nil)
    }

    /// La réponse à donner à un défi d'authentification (URLSession ou WebKit).
    func repondre(_ defi: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let espace = defi.protectionSpace
        switch decider(methode: espace.authenticationMethod, hote: espace.host, confiance: espace.serverTrust) {
        case .parDefaut: return (.performDefaultHandling, nil)
        case .refuser: return (.cancelAuthenticationChallenge, nil)
        case .accepter:
            guard let confiance = espace.serverTrust else { return (.cancelAuthenticationChallenge, nil) }
            return (.useCredential, URLCredential(trust: confiance))
        }
    }
}
