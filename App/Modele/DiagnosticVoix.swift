import AlfredKit
import Foundation

/// Les étapes de la voix d'Alfred, notées par le relais (`POST /diag`), comme la console (`sendDiag`) : la voix
/// annoncée par la maison, demandée, jouée ou en erreur. Jamais de texte ni de chemin (le jeton de la voix reste ici).
///
/// Retour d'essai du 30.10 : « il écrit la réponse, mais je n'entends rien » — la maison avait produit et servi la voix,
/// le relais n'avait reçu aucune demande, et l'app ne disait rien de ce qu'elle avait fait. Envoi au fil de l'eau,
/// sans attendre ni réessayer : une étape perdue ne gêne jamais la conversation.
struct DiagnosticVoix: Sendable {
    let acces: any AccesRelais

    func noter(_ etape: String, _ details: [String: String] = [:]) {
        var d = details
        d["quoi"] = "voix_app"
        d["etape"] = etape
        guard let corps = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]) else { return }
        let acces = acces
        Task.detached(priority: .utility) {
            _ = try? await acces.envoyer(RequeteRelais(.post, "/diag", corps: corps, type: "application/json"))
        }
    }
}
