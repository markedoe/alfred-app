import Foundation
import Security
import Testing

@testable import Alfred

/// Certificats de TEST, jetables (clés privées détruites à la création, le 16.10.2026) : une autorité, une autorité
/// intruse, et un certificat de serveur pour `relais.test` signé par la première (valable du 16.10.2026 au 24.12.2028 ;
/// les tests fixent la date de vérification, ils ne vieillissent pas).
enum CertificatsDeTest {
    // swift-format-ignore
    static let autorite = Data(base64Encoded: "MIIDNTCCAh2gAwIBAgIUHem2kZfDFfAHLe+4jPzxQw6VA8gwDQYJKoZIhvcNAQELBQAwIjEgMB4GA1UEAwwXQXV0b3JpdGUgZGUgdGVzdCBBbGZyZWQwHhcNMjYxMDE2MTE1NzI4WhcNMzYxMDEzMTE1NzI4WjAiMSAwHgYDVQQDDBdBdXRvcml0ZSBkZSB0ZXN0IEFsZnJlZDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJRT1zj2cI6gejV5+i5Xw4AKZHkoGFPZBm3BFUWzPizI5u9a6DLr0VSN+CkVvRuDKeR/1+iNXz7bDvI/fS84JvO81pUaRoe8er5aRyU5JrqoaxwnxRcy479VgYhAGn9SAmoCF5gYmqLOiC+aC3GvNYaTDuS3PNzyljiBupfa+FY5ELyGHXS7DdhoKXLp+5K+LkcsBLCo77THD7vQEa2ZOENRa4K04m4qtlMSqQbLQ+DjCgZXucSayS961PQxeBwIMLHrnGeBCkeNNK+uUa992mlM9vBBBget8yIvJH7os+adCOeFw8l2IUDwhUd9WmO+FlM4zSop8ulDUtQTU77n7zkCAwEAAaNjMGEwHQYDVR0OBBYEFNceOQlTiUGKiSZwtfQikbkSdcitMB8GA1UdIwQYMBaAFNceOQlTiUGKiSZwtfQikbkSdcitMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQAvLUzSPyUW3/2fnYuAW+A5Su3W3EQ5cv2fCpLOVe4eu3mmdYibkj7j6QIRf3vlNgjZ7/j8sJktItPsilwT+4/56rXOd64cix774AFc7LurVBy4HfNcyYfW+RxyNTwOTQM2h4dsdOAZDA/vKGNW6Tv0zy8qiWTzQm28XEwLwNixh2F3z3N7jGKI6KMe2ALSFl+2+CbvJf7/uZIsqXFRpibbz5e4L32hIKVBkYiZ4ITUyzUgw9m1RyVO+HjceTOL/xlJkrW5Fzi2YQr0+M9qlPqG4Jix29P8Hclh889wavmgTNQFqrBfsBtoSErn/e07Ww5VceHVrNWuHSNKLG3Pxgeq")!
    // swift-format-ignore
    static let intrus = Data(base64Encoded: "MIIDJzCCAg+gAwIBAgIUVZbRp7XQ/rISoI/mfrIRQGHjb9gwDQYJKoZIhvcNAQELBQAwGzEZMBcGA1UEAwwQQXV0b3JpdGUgaW50cnVzZTAeFw0yNjEwMTYxMTU3MjlaFw0zNjEwMTMxMTU3MjlaMBsxGTAXBgNVBAMMEEF1dG9yaXRlIGludHJ1c2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCLwxDLLwfDPAA+0E/L2fzsa2WnU5ltIKlrOK8FvnSjDtouUpEZiszS36m7VqHZ5O1BLncbJ+GTnjgSXHzGrNRcBIgQ7qEbaauKDrOvon1rIMrAaj5LgLHgdwl5mrujTYfbkzQuzsMWGjTS0HkSC/Yd+ZxT/3jSq/vEbpTfglcfhcUY80LMyDxVyLTG3W8ii3Sri/g/3FGbV0MV97bhd7B8+eXiZMiUIq/rKybRUm4LR82ULRbX0V2kQT0zJMuHjia5sdXlW7JcOzZcCzgaub/ZLin9kqzB29+bbkiG1HBmoELxLz3+TLBeNvR6Kttq4Pcm5DOQE6beFHMbQm0w9X03AgMBAAGjYzBhMB0GA1UdDgQWBBSX/SaplENg06I/KvUXLcp8FsdIODAfBgNVHSMEGDAWgBSX/SaplENg06I/KvUXLcp8FsdIODAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEAbE5SFW2vwIwFXe4c2XRe0a8uyrIN7upelHm1SiK0tatbagRqkinD7TNDXPr5wsgM+/x+U4l3IZQYZxjd175BQEsG34l4wTyl6tC2AUVQtniLytk8mQtcOGnyTa8v/08/RA/6B/r3/zjO/NzqFoVKrTJfoUyAq2A5KCOPZeRTG2hv1J7NkFrbyBQoTrPxhEWk1jbtt5pDPjGbytUmHZnNlgRMQxNBukwz3felx8t+oUiT/2DSF14HZ8xTpe6N26yJKpI8q+LdW57uPb5xoyBhuwy3rUCAc14zkBRJZRr0NNImAt7ktzKfOEssfrGHWpsXjDSb/73TSEpo3JeyHj3X6g==")!
    // swift-format-ignore
    static let serveur = Data(base64Encoded: "MIIDUjCCAjqgAwIBAgIUE8fQ7BwmZhQCN8kEsW3/jcBIm8YwDQYJKoZIhvcNAQELBQAwIjEgMB4GA1UEAwwXQXV0b3JpdGUgZGUgdGVzdCBBbGZyZWQwHhcNMjYxMDE2MTE1NzI5WhcNMjgxMjI0MTE1NzI5WjAWMRQwEgYDVQQDDAtyZWxhaXMudGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJaQMELKNM+X+kez/cn7tnHGwzqmI+TBXyDE4u5XpyYfD7t26cy+cDkycsvwaU5pcPBEGTuxK15f7KeDGJ4cEKyZJlLtmtbsMY5Gsb65aiWJ8wXNDoCSROorZ02WTXDSTFp1Rmpl6pzzlHQrj7EkeRIp199U59FfKBXoim6AN2La34R7uR1e5dLLOYRo+9RQsJPwWNKRFDjh9wYpOIb661OetzhvHGt9rrtpyIJjQ4ohMl+eHRsZr85rjcUTc/2bHT+5E6ZZUxCxqKDTPObhh0MG7e9kqQEbPBqJJInxnM6sKuuBrInKDHHJqkIrVKZq3uYijgyx1nDv4sU72h0snDMCAwEAAaOBizCBiDAJBgNVHRMEAjAAMA4GA1UdDwEB/wQEAwIFoDATBgNVHSUEDDAKBggrBgEFBQcDATAWBgNVHREEDzANggtyZWxhaXMudGVzdDAdBgNVHQ4EFgQUHuXdOq2dCdv/rYPe3MfN7w3GXr4wHwYDVR0jBBgwFoAU1x45CVOJQYqJJnC19CKRuRJ1yK0wDQYJKoZIhvcNAQELBQADggEBAFYj+k41wC2VHvgRZ2K9xNoO5FCgMePg9I5hTORHE169UCslPioYq+gmHXs6V6vYQ5SSi/v8jIOAWJ3jbm+mNBft5dBfRv5buKuxya+i1/zZfDr7HakWPA2UpSYLEs4xcxJTA++rMTEbajOkaL3pYvRiUtQMGKVP/0Oz7J/Gc9lycRuDHip+iWepmCQSDl3SK7xyOGrCZsIZabTO0TfQOEgWJZrtZy5uu+nxgs33v2IOq8qavLEq2nhwXGkrfRuIh4TkbrLggIdi+/p8jRRWLtKl6EcbKsMvKQCGpBJX2oUkp6xr0Jkc2112ypPICblSU39yTc9hWEPOB1yB8Xjuls4=")!
    /// Une date où le certificat du serveur est valable.
    static let dateValide = Date(timeIntervalSince1970: 1_800_000_000)  // 15.01.2027

    static func confiance(hote: String) -> SecTrust {
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

    @Test("Décisions : autre hôte et autre méthode → traitement du système ; sans confiance → refus")
    func decisions() {
        let c = ConfianceTLS(hote: "relais.test", autorite: CertificatsDeTest.autorite)
        #expect(
            c.decider(methode: NSURLAuthenticationMethodServerTrust, hote: "ailleurs.test", confiance: nil)
                == .parDefaut)
        #expect(
            c.decider(methode: NSURLAuthenticationMethodHTTPBasic, hote: "relais.test", confiance: nil) == .parDefaut)
        #expect(
            c.decider(methode: NSURLAuthenticationMethodServerTrust, hote: "relais.test", confiance: nil) == .refuser)
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
