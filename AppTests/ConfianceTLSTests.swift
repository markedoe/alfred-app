import Foundation
import Security
import Testing

@testable import Alfred

/// Certificats de TEST, jetables (clés privées détruites à la création, le 16.10.2026) : une autorité, une autorité
/// intruse, et un certificat de serveur pour `relais.test` signé par la première (valable du 16.10.2026 au 24.12.2028 ;
/// les tests fixent la date de vérification, ils ne vieillissent pas).
///
/// Et une chaîne faite COMME celle d'une maison (17.10.2026, clés détruites aussi), noms neutres : une autorité sans
/// usage de clé (`openssl req -x509` par défaut), un serveur valable 825 jours tout juste (le plafond d'Apple) dont le
/// nom ne correspond que par un joker (`*.lan.9z`, domaine de premier niveau commençant par un chiffre), avec des
/// adresses IP et `localhost` dans ses noms.
enum CertificatsDeTest {
    // swift-format-ignore
    static let autorite = Data(base64Encoded: "MIIDNTCCAh2gAwIBAgIUHem2kZfDFfAHLe+4jPzxQw6VA8gwDQYJKoZIhvcNAQELBQAwIjEgMB4GA1UEAwwXQXV0b3JpdGUgZGUgdGVzdCBBbGZyZWQwHhcNMjYxMDE2MTE1NzI4WhcNMzYxMDEzMTE1NzI4WjAiMSAwHgYDVQQDDBdBdXRvcml0ZSBkZSB0ZXN0IEFsZnJlZDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJRT1zj2cI6gejV5+i5Xw4AKZHkoGFPZBm3BFUWzPizI5u9a6DLr0VSN+CkVvRuDKeR/1+iNXz7bDvI/fS84JvO81pUaRoe8er5aRyU5JrqoaxwnxRcy479VgYhAGn9SAmoCF5gYmqLOiC+aC3GvNYaTDuS3PNzyljiBupfa+FY5ELyGHXS7DdhoKXLp+5K+LkcsBLCo77THD7vQEa2ZOENRa4K04m4qtlMSqQbLQ+DjCgZXucSayS961PQxeBwIMLHrnGeBCkeNNK+uUa992mlM9vBBBget8yIvJH7os+adCOeFw8l2IUDwhUd9WmO+FlM4zSop8ulDUtQTU77n7zkCAwEAAaNjMGEwHQYDVR0OBBYEFNceOQlTiUGKiSZwtfQikbkSdcitMB8GA1UdIwQYMBaAFNceOQlTiUGKiSZwtfQikbkSdcitMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQAvLUzSPyUW3/2fnYuAW+A5Su3W3EQ5cv2fCpLOVe4eu3mmdYibkj7j6QIRf3vlNgjZ7/j8sJktItPsilwT+4/56rXOd64cix774AFc7LurVBy4HfNcyYfW+RxyNTwOTQM2h4dsdOAZDA/vKGNW6Tv0zy8qiWTzQm28XEwLwNixh2F3z3N7jGKI6KMe2ALSFl+2+CbvJf7/uZIsqXFRpibbz5e4L32hIKVBkYiZ4ITUyzUgw9m1RyVO+HjceTOL/xlJkrW5Fzi2YQr0+M9qlPqG4Jix29P8Hclh889wavmgTNQFqrBfsBtoSErn/e07Ww5VceHVrNWuHSNKLG3Pxgeq")!
    // swift-format-ignore
    static let intrus = Data(base64Encoded: "MIIDJzCCAg+gAwIBAgIUVZbRp7XQ/rISoI/mfrIRQGHjb9gwDQYJKoZIhvcNAQELBQAwGzEZMBcGA1UEAwwQQXV0b3JpdGUgaW50cnVzZTAeFw0yNjEwMTYxMTU3MjlaFw0zNjEwMTMxMTU3MjlaMBsxGTAXBgNVBAMMEEF1dG9yaXRlIGludHJ1c2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCLwxDLLwfDPAA+0E/L2fzsa2WnU5ltIKlrOK8FvnSjDtouUpEZiszS36m7VqHZ5O1BLncbJ+GTnjgSXHzGrNRcBIgQ7qEbaauKDrOvon1rIMrAaj5LgLHgdwl5mrujTYfbkzQuzsMWGjTS0HkSC/Yd+ZxT/3jSq/vEbpTfglcfhcUY80LMyDxVyLTG3W8ii3Sri/g/3FGbV0MV97bhd7B8+eXiZMiUIq/rKybRUm4LR82ULRbX0V2kQT0zJMuHjia5sdXlW7JcOzZcCzgaub/ZLin9kqzB29+bbkiG1HBmoELxLz3+TLBeNvR6Kttq4Pcm5DOQE6beFHMbQm0w9X03AgMBAAGjYzBhMB0GA1UdDgQWBBSX/SaplENg06I/KvUXLcp8FsdIODAfBgNVHSMEGDAWgBSX/SaplENg06I/KvUXLcp8FsdIODAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEAbE5SFW2vwIwFXe4c2XRe0a8uyrIN7upelHm1SiK0tatbagRqkinD7TNDXPr5wsgM+/x+U4l3IZQYZxjd175BQEsG34l4wTyl6tC2AUVQtniLytk8mQtcOGnyTa8v/08/RA/6B/r3/zjO/NzqFoVKrTJfoUyAq2A5KCOPZeRTG2hv1J7NkFrbyBQoTrPxhEWk1jbtt5pDPjGbytUmHZnNlgRMQxNBukwz3felx8t+oUiT/2DSF14HZ8xTpe6N26yJKpI8q+LdW57uPb5xoyBhuwy3rUCAc14zkBRJZRr0NNImAt7ktzKfOEssfrGHWpsXjDSb/73TSEpo3JeyHj3X6g==")!
    // swift-format-ignore
    static let serveur = Data(base64Encoded: "MIIDUjCCAjqgAwIBAgIUE8fQ7BwmZhQCN8kEsW3/jcBIm8YwDQYJKoZIhvcNAQELBQAwIjEgMB4GA1UEAwwXQXV0b3JpdGUgZGUgdGVzdCBBbGZyZWQwHhcNMjYxMDE2MTE1NzI5WhcNMjgxMjI0MTE1NzI5WjAWMRQwEgYDVQQDDAtyZWxhaXMudGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJaQMELKNM+X+kez/cn7tnHGwzqmI+TBXyDE4u5XpyYfD7t26cy+cDkycsvwaU5pcPBEGTuxK15f7KeDGJ4cEKyZJlLtmtbsMY5Gsb65aiWJ8wXNDoCSROorZ02WTXDSTFp1Rmpl6pzzlHQrj7EkeRIp199U59FfKBXoim6AN2La34R7uR1e5dLLOYRo+9RQsJPwWNKRFDjh9wYpOIb661OetzhvHGt9rrtpyIJjQ4ohMl+eHRsZr85rjcUTc/2bHT+5E6ZZUxCxqKDTPObhh0MG7e9kqQEbPBqJJInxnM6sKuuBrInKDHHJqkIrVKZq3uYijgyx1nDv4sU72h0snDMCAwEAAaOBizCBiDAJBgNVHRMEAjAAMA4GA1UdDwEB/wQEAwIFoDATBgNVHSUEDDAKBggrBgEFBQcDATAWBgNVHREEDzANggtyZWxhaXMudGVzdDAdBgNVHQ4EFgQUHuXdOq2dCdv/rYPe3MfN7w3GXr4wHwYDVR0jBBgwFoAU1x45CVOJQYqJJnC19CKRuRJ1yK0wDQYJKoZIhvcNAQELBQADggEBAFYj+k41wC2VHvgRZ2K9xNoO5FCgMePg9I5hTORHE169UCslPioYq+gmHXs6V6vYQ5SSi/v8jIOAWJ3jbm+mNBft5dBfRv5buKuxya+i1/zZfDr7HakWPA2UpSYLEs4xcxJTA++rMTEbajOkaL3pYvRiUtQMGKVP/0Oz7J/Gc9lycRuDHip+iWepmCQSDl3SK7xyOGrCZsIZabTO0TfQOEgWJZrtZy5uu+nxgs33v2IOq8qavLEq2nhwXGkrfRuIh4TkbrLggIdi+/p8jRRWLtKl6EcbKsMvKQCGpBJX2oUkp6xr0Jkc2112ypPICblSU39yTc9hWEPOB1yB8Xjuls4=")!
    // swift-format-ignore
    static let autoriteSansUsage = Data(base64Encoded: "MIIDSzCCAjOgAwIBAgIUQtxUSR5N7d4a/D3W/Jt0QndhkDYwDQYJKoZIhvcNAQELBQAwNTEkMCIGA1UEAwwbQXV0b3JpdGUgZGUgdGVzdCBzYW5zIHVzYWdlMQ0wCwYDVQQKDARUZXN0MB4XDTI2MTAxNzE5MTcxMFoXDTM2MTAxNDE5MTcxMFowNTEkMCIGA1UEAwwbQXV0b3JpdGUgZGUgdGVzdCBzYW5zIHVzYWdlMQ0wCwYDVQQKDARUZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlx8Id6KyLTBIM3+mTpdC/Z58Gc6eaha04eRdk5POnPPVkMIKudg6+CTvyB0eV7sljpPNliUwEpk05aljOATmo+fkGEFgdXmsB4eeNJAPwgoo0dhBV0X+zaq3qdJfc0pyiIUeelWT1FrhTgCyYf9LA8dhFW9ytebyVn2m9SamfOHddXPRKPiEoDgLh/ISDcc/ftv/lxtu4rEkA5LlPLXtY7EWNBwnESIebNwECz5hHiSiBkkZ8GhGdBwI6wu84EuFuhJwfOxJtZxB46fU2ZJnGEI3l/GrIsrwE879n3o8YfO87MkFR+ywIngD1TbiKaMAgg6BUpz8RygoQo+NiztEOQIDAQABo1MwUTAdBgNVHQ4EFgQUtQKqQox2C//4/MMF7FFW8vZSv0UwHwYDVR0jBBgwFoAUtQKqQox2C//4/MMF7FFW8vZSv0UwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAB9Pm3FDVNehZ/1ApMcvUIFxkqYYlXmZiKJMsXRnmHE7sYYgeAdqH6w7opVP0dIKPiurAnHsfXYEKxblEQur8uiXqcrQnxw+6Odldwc6uWhlecTK9uTsbPBrjB9n3IZcc8YPYkzF7Di571M5q78EO7WOY0BqzbQBgiiOK/YNSAgbv01cb8HdVO+0IVx6uLE/WZ2huz4uoqBNIYZ4OH0LaZVxQ0TQSwf8kv1/BODsafoFH1rxE2I9lTGKRJgZALucYF4TxkVVmDQskXq1N3UDw7XnQP0gUmfLVUe3PkYX6Ft0ok0mrcEPemmkL7ImlMh7uQxDYnmBGwbE6UmZy4jB9Nw==")!
    // swift-format-ignore
    static let serveurJoker = Data(base64Encoded: "MIIDjjCCAnagAwIBAgIUKslJLT2Ly8VlVTwVGBVkH6lu5skwDQYJKoZIhvcNAQELBQAwNTEkMCIGA1UEAwwbQXV0b3JpdGUgZGUgdGVzdCBzYW5zIHVzYWdlMQ0wCwYDVQQKDARUZXN0MB4XDTI2MTAxNzE5MTcxMFoXDTI5MDExOTE5MTcxMFowFzEVMBMGA1UEAwwMYXV0cmUubGFuLjl6MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwZ+u6F0iJk0SkfZCVu2zweoP992/Fz/rHRnsY3+y1SydSe9QerHrYhdTwDFpRMGBfqjStX5wKoABiwU/qdP8zrnFBCPCC4lAaM72WJIgUBNqk5c62ra6pCn0GSdRWR3GYIQht1lwSH0ucm2isoxIJIOtZARx7eQkbBEPwubkuViSeJzt7feIExq4+/84viPvTy1VE05d4oGJ4u1YC6bZHVj9i74/PimCmLlNmEPel4XzeUH3tdjv1DSWHK/Gnd5KgZLk2SsO89Iocqy8Zj2UCdLQy2EWq9adE1SMRIEtKVw61vMbME8hidin9mJWHHnEvk4pCFeeU2Nvf3HTW8fgiwIDAQABo4GzMIGwMEwGA1UdEQRFMEOHBMAAAgqHBH8AAAGCDGF1dHJlLmxhbi45eoIFYXV0cmWCC2F1dHJlLmxvY2Fsgglsb2NhbGhvc3SCCCoubGFuLjl6MAsGA1UdDwQEAwIFoDATBgNVHSUEDDAKBggrBgEFBQcDATAdBgNVHQ4EFgQU+5tNiq2g0iaXxWpuEhaS6GSCvWcwHwYDVR0jBBgwFoAUtQKqQox2C//4/MMF7FFW8vZSv0UwDQYJKoZIhvcNAQELBQADggEBAAUdCOhKiYNbmG3dbV5BE/z/fPAUSOkqF8mUipDkSYOhQI+bsZSuE49OenuUD+xtHxmp34rizwpNC2dHGmOAEFO736EG+wgpZat1eZWXW3USGNIdu99HhT0K1FRpag0SKHlkdw1wNtCFw0Q0/ARaTBw5CR/4ExgwFb/LmELXSc/ZTNbXDTZNviH0VuIrv6eVm24bIPAhG1JusM6skDIC1xxksfVL5CdNvXGNamAnZip4p46dRxufvcm4XvmhxwRPhm2frHrpWFy+TsxhFFGMjq/iHDVPaXzv1AyZsKI4AtBZumtDa5mTtVNtNxit65cRsfKUFKMwiEfY2yVh3yHQ8lQ=")!
    /// Une date où le certificat du serveur est valable.
    static let dateValide = Date(timeIntervalSince1970: 1_800_000_000)  // 15.01.2027

    static func confiance(hote: String, serveur: Data = CertificatsDeTest.serveur) -> SecTrust {
        let feuille = SecCertificateCreateWithData(nil, serveur as CFData)!
        var t: SecTrust?
        SecTrustCreateWithCertificates(feuille, SecPolicyCreateSSL(true, hote as CFString), &t)
        SecTrustSetVerifyDate(t!, dateValide as CFDate)
        return t!
    }
}

@Suite("Épinglage TLS")
struct ConfianceTLSTests {
    @Test("Le relais signé par l'autorité de la maison est accepté")
    func accepte() {
        let ancre = SecCertificateCreateWithData(nil, CertificatsDeTest.autorite as CFData)!
        #expect(
            ConfianceTLS.evaluer(CertificatsDeTest.confiance(hote: "relais.test"), hote: "relais.test", ancre: ancre))
    }

    @Test("Une autre autorité est refusée, même valide")
    func intrus() {
        let ancre = SecCertificateCreateWithData(nil, CertificatsDeTest.intrus as CFData)!
        #expect(
            !ConfianceTLS.evaluer(CertificatsDeTest.confiance(hote: "relais.test"), hote: "relais.test", ancre: ancre))
    }

    @Test("Le bon certificat pour un autre nom d'hôte est refusé")
    func mauvaisHote() {
        let ancre = SecCertificateCreateWithData(nil, CertificatsDeTest.autorite as CFData)!
        #expect(
            !ConfianceTLS.evaluer(CertificatsDeTest.confiance(hote: "autre.test"), hote: "autre.test", ancre: ancre))
    }

    @Test("Une chaîne faite comme celle d'une maison est acceptée (sans usage de clé, 825 jours, nom par joker)")
    func chaineDeMaison() {
        let ancre = SecCertificateCreateWithData(nil, CertificatsDeTest.autoriteSansUsage as CFData)!
        let confiance = CertificatsDeTest.confiance(hote: "relais.lan.9z", serveur: CertificatsDeTest.serveurJoker)
        #expect(ConfianceTLS.refus(confiance, hote: "relais.lan.9z", ancre: ancre) == nil)
        // le joker ne couvre qu'un niveau, et que son domaine
        for hote in ["relais.ailleurs.9z", "un.relais.lan.9z"] {
            let autre = CertificatsDeTest.confiance(hote: hote, serveur: CertificatsDeTest.serveurJoker)
            #expect(ConfianceTLS.refus(autre, hote: hote, ancre: ancre) != nil, "\(hote)")
        }
    }

    @Test("Un refus garde le code de Security qui l'explique")
    func codeDuRefus() {
        let c = ConfianceTLS(hote: "autre.test", autorite: CertificatsDeTest.autorite)
        let decision = c.decider(
            methode: NSURLAuthenticationMethodServerTrust, hote: "autre.test",
            confiance: CertificatsDeTest.confiance(hote: "autre.test"))
        guard case .refuser(let code) = decision else {
            Issue.record("refus attendu : \(decision)")
            return
        }
        #expect(code != nil && code != 0)
    }

    @Test("Décisions : autre hôte et autre méthode → traitement du système ; sans confiance → refus")
    func decisions() {
        let c = ConfianceTLS(hote: "relais.test", autorite: CertificatsDeTest.autorite)
        #expect(
            c.decider(methode: NSURLAuthenticationMethodServerTrust, hote: "ailleurs.test", confiance: nil)
                == .parDefaut)
        #expect(
            c.decider(methode: NSURLAuthenticationMethodHTTPBasic, hote: "relais.test", confiance: nil) == .parDefaut)
        #expect(
            c.decider(methode: NSURLAuthenticationMethodServerTrust, hote: "relais.test", confiance: nil)
                == .refuser(code: nil))
        #expect(
            c.decider(
                methode: NSURLAuthenticationMethodServerTrust, hote: "RELAIS.test",
                confiance: CertificatsDeTest.confiance(hote: "relais.test")) == .accepter)
        let sansAutorite = ConfianceTLS(hote: "relais.test", autorite: nil)
        #expect(
            sansAutorite.decider(methode: NSURLAuthenticationMethodServerTrust, hote: "relais.test", confiance: nil)
                == .parDefaut)
    }
}

@Suite("Message d'échec de la connexion")
@MainActor
struct MessageConnexionTests {
    static let url = URL(string: "https://relais.test/connexion")!

    @Test("Le code de l'erreur et l'hôte en cause suivent le message")
    func details() {
        let e = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted,
            userInfo: [NSURLErrorFailingURLErrorKey: Self.url])
        #expect(
            PageConnexion.Coordinateur.message(e)
                == "L’identité de la maison n’a pas pu être vérifiée. Connexion refusée par sécurité."
                + " (code -1202 · relais.test)")
    }

    @Test("Une annulation qui suit NOTRE refus de la chaîne est un refus d'identité, avec son code de Security")
    func annulationApresRefus() {
        let e = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: [NSURLErrorFailingURLErrorKey: Self.url])
        #expect(
            PageConnexion.Coordinateur.message(e, refus: .refuser(code: -67602))
                == "L’identité de la maison n’a pas pu être vérifiée. Connexion refusée par sécurité."
                + " (code -999 · relais.test · confiance -67602)")
        #expect(PageConnexion.Coordinateur.message(e).hasPrefix("La connexion a été interrompue."))
    }
}
