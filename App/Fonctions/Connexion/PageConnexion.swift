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
        /// La dernière chaîne du relais refusée par l'épinglage (son code de Security), pour le message d'échec.
        private var refus: ConfianceTLS.Decision?

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
            refus = nil
            var c = URLComponents(url: configuration.relais.connexion, resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "retour", value: "/moi")]
            vue.load(URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }

        // La fin du parcours : le relais renvoie vers /moi une fois le cookie posé.
        func webView(_ vue: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, let schema = url.scheme?.lowercased() else { return .cancel }
            guard schema == "https" || schema == "http" else { return .cancel }  // aucune autre app ouverte d'ici
            let versRelais = url.host()?.caseInsensitiveCompare(configuration.relais.hote) == .orderedSame
            // le relais en https seulement : son exception d'ATS (scripts/generer.sh) permettrait aussi http
            if versRelais, schema != "https" {
                echec("La maison a proposé une connexion non chiffrée. Connexion refusée par sécurité.")
                return .cancel
            }
            if versRelais, url.path() == "/moi" {
                await terminer(vue)
                return .cancel
            }
            return .allow
        }

        private func terminer(_ vue: WKWebView) async {
            // posé AVANT l'attente : une 2e navigation vers /moi pendant la lecture des cookies ne termine pas deux fois
            guard !termine else { return }
            termine = true
            let cookies = await withCheckedContinuation { (suite: CheckedContinuation<[HTTPCookie], Never>) in
                vue.configuration.websiteDataStore.httpCookieStore.getAllCookies { suite.resume(returning: $0) }
            }
            let hote = configuration.relais.hote
            guard
                let cookie = cookies.first(where: {
                    $0.name == SessionRelais.nomCookie && $0.domain.caseInsensitiveCompare(hote) == .orderedSame
                })
            else {
                termine = false
                echec("La maison n’a pas confirmé la connexion. Réessayez.")
                return
            }
            reussite(SessionRelais(valeur: cookie.value))
        }

        func webView(_ vue: WKWebView, didFinish navigation: WKNavigation!) {
            if !termine, !aEchoue { etat.wrappedValue = .affichee }
        }

        func webView(
            _ vue: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError erreur: any Error
        ) {
            echec(Self.message(erreur, refus: refus))
        }

        func webView(_ vue: WKWebView, didFail navigation: WKNavigation!, withError erreur: any Error) {
            echec(Self.message(erreur, refus: refus))
        }

        func webView(
            _ vue: WKWebView, respondTo defi: URLAuthenticationChallenge
        ) async
            -> (URLSession.AuthChallengeDisposition, URLCredential?)
        {
            let decision = confiance.decider(defi)
            if case .refuser = decision { refus = decision }
            return ConfianceTLS.reponse(decision, a: defi)
        }

        private func echec(_ message: String) {
            // une navigation annulée par nous (fin du parcours) n'est pas un échec
            guard !termine else { return }
            aEchoue = true
            etat.wrappedValue = .echec(message)
        }

        /// Le message, suivi des détails techniques : le code de l'erreur, l'hôte en cause et, si l'épinglage a refusé
        /// la chaîne du relais, le code de Security (« code -999 · relais.maison.example · confiance -67602 ») ; de
        /// quoi trouver la cause d'un coup.
        static func message(_ erreur: any Error, refus: ConfianceTLS.Decision? = nil) -> String {
            let e = erreur as NSError
            var details = ["\(e.domain == NSURLErrorDomain ? "code" : e.domain) \(e.code)"]
            if let hote = (e.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host() { details.append(hote) }
            if case .refuser(let code) = refus { details.append("confiance " + (code.map(String.init) ?? "absente")) }
            // un défi refusé par nous se termine en « annulé » (-999) : c'est un refus d'identité, pas une coupure
            let refuseParNous = refus != nil && e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled
            return (refuseParNous ? texteIdentite : texte(e)) + " (" + details.joined(separator: " · ") + ")"
        }

        private static let texteIdentite =
            "L’identité de la maison n’a pas pu être vérifiée. Connexion refusée par sécurité."

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
                    return texteIdentite
                case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                    return "Cette version de l’app ne peut pas ouvrir la page de connexion de la maison."
                default: break
                }
            }
            return "La connexion a échoué. Réessayez."
        }
    }
}
