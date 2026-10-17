import AlfredKit
import SwiftUI
import WebKit

/// La page de connexion de Home Assistant, dans l'app : le parcours du relais tel quel (`/connexion`), dans une
/// vue web SANS mémoire (rien ne reste sur l'appareil après la fermeture). À la fin du parcours, le relais pose le
/// cookie de session et renvoie vers `/moi` : l'app reprend alors le cookie, le range dans le trousseau, et ferme.
struct PageConnexion: UIViewRepresentable {
    let configuration: ConfigurationMaison
    let etat: Binding<EtatPage>
    let reussite: @MainActor (SessionRelais) -> Void

    enum EtatPage: Equatable {
        case chargement
        case affichee
        case echec(String)
    }

    func makeCoordinator() -> Coordinateur {
        Coordinateur(configuration: configuration, etat: etat, reussite: reussite)
    }

    func makeUIView(context: Context) -> WKWebView {
        let reglages = WKWebViewConfiguration()
        reglages.websiteDataStore = .nonPersistent()
        reglages.applicationNameForUserAgent = "Alfred"
        let vue = WKWebView(frame: .zero, configuration: reglages)
        vue.navigationDelegate = context.coordinator
        vue.allowsBackForwardNavigationGestures = false
        vue.isOpaque = false
        vue.backgroundColor = .clear
        vue.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.charger(vue)
        return vue
    }

    func updateUIView(_ vue: WKWebView, context: Context) {
        context.coordinator.etat = etat
        if etat.wrappedValue == .chargement, context.coordinator.aEchoue {
            context.coordinator.charger(vue)
        }
    }

    static func dismantleUIView(_ vue: WKWebView, coordinator: Coordinateur) {
        vue.stopLoading()
        vue.navigationDelegate = nil
    }

    @MainActor
    final class Coordinateur: NSObject, WKNavigationDelegate {
        let configuration: ConfigurationMaison
        var etat: Binding<EtatPage>
        let reussite: @MainActor (SessionRelais) -> Void
        private let confiance: ConfianceTLS
        private(set) var aEchoue = false
        private var termine = false

        init(
            configuration: ConfigurationMaison, etat: Binding<EtatPage>,
            reussite: @escaping @MainActor (SessionRelais) -> Void
        ) {
            self.configuration = configuration
            self.etat = etat
            self.reussite = reussite
            confiance = ConfianceTLS(hote: configuration.relais.hote, autorite: configuration.autorite)
        }

        func charger(_ vue: WKWebView) {
            aEchoue = false
            var c = URLComponents(url: configuration.relais.connexion, resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "retour", value: "/moi")]
            vue.load(URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }

        // La fin du parcours : le relais renvoie vers /moi une fois le cookie posé.
        func webView(_ vue: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let schema = url.scheme?.lowercased() else { return .cancel }
            guard schema == "https" || schema == "http" else { return .cancel }  // aucune autre app ouverte d'ici
            if url.host()?.caseInsensitiveCompare(configuration.relais.hote) == .orderedSame, url.path() == "/moi" {
                await terminer(vue)
                return .cancel
            }
            return .allow
        }

        private func terminer(_ vue: WKWebView) async {
            guard !termine else { return }
            let cookies = await withCheckedContinuation { (suite: CheckedContinuation<[HTTPCookie], Never>) in
                vue.configuration.websiteDataStore.httpCookieStore.getAllCookies { suite.resume(returning: $0) }
            }
            let hote = configuration.relais.hote
            guard
                let cookie = cookies.first(where: {
                    $0.name == SessionRelais.nomCookie && $0.domain.caseInsensitiveCompare(hote) == .orderedSame
                })
            else {
                echec("La maison n’a pas confirmé la connexion. Réessayez.")
                return
            }
            termine = true
            reussite(SessionRelais(valeur: cookie.value))
        }

        func webView(_ vue: WKWebView, didFinish navigation: WKNavigation!) {
            if !termine, !aEchoue { etat.wrappedValue = .affichee }
        }

        func webView(
            _ vue: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError erreur: any Error
        ) {
            echec(Self.message(erreur))
        }

        func webView(_ vue: WKWebView, didFail navigation: WKNavigation!, withError erreur: any Error) {
            echec(Self.message(erreur))
        }

        func webView(
            _ vue: WKWebView, respondTo defi: URLAuthenticationChallenge
        ) async
            -> (URLSession.AuthChallengeDisposition, URLCredential?)
        {
            confiance.repondre(defi)
        }

        private func echec(_ message: String) {
            // une navigation annulée par nous (fin du parcours) n'est pas un échec
            guard !termine else { return }
            aEchoue = true
            etat.wrappedValue = .echec(message)
        }

        /// Le message, suivi du code technique de l'erreur (« code -1202 ») : de quoi trouver la cause d'un coup.
        static func message(_ erreur: any Error) -> String {
            let e = erreur as NSError
            return texte(e) + " (\(e.domain == NSURLErrorDomain ? "code" : e.domain) \(e.code))"
        }

        private static func texte(_ e: NSError) -> String {
            if e.domain == NSURLErrorDomain {
                switch e.code {
                case NSURLErrorCancelled:
                    return "La connexion a été interrompue. Réessayez."
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                    NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                    return "La maison ne répond pas. Vérifiez que vous êtes sur le Wi-Fi de la maison ou sur son VPN."
                case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                    NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
                    NSURLErrorSecureConnectionFailed:
                    return "L’identité de la maison n’a pas pu être vérifiée. Connexion refusée par sécurité."
                case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                    return "Cette version de l’app ne peut pas ouvrir la page de connexion de la maison."
                default: break
                }
            }
            return "La connexion a échoué. Réessayez."
        }
    }
}
