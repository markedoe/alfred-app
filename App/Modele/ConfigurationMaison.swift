import AlfredKit
import Foundation

/// La configuration de la maison : l'adresse du relais et l'autorité de certification à épingler.
///
/// Elle n'est jamais dans le code (dépôt public) : la fabrication l'embarque (`Configuration.plist`, écrit par
/// `scripts/generer.sh` depuis les secrets de la CI), sinon l'app la demande au premier lancement.
struct ConfigurationMaison: Equatable, Sendable {
    let relais: Relais
    /// Certificat de l'autorité de la maison (DER) ; nil : autorités du système.
    let autorite: Data?

    static let cleAdresseSaisie = "configuration.relais"

    /// Configuration embarquée, sinon saisie au premier lancement ; nil s'il n'y en a aucune.
    static func actuelle(bundle: Bundle = .main, reglages: UserDefaults = .standard) -> ConfigurationMaison? {
        embarquee(bundle: bundle) ?? saisie(reglages: reglages)
    }

    static func embarquee(bundle: Bundle = .main) -> ConfigurationMaison? {
        guard let url = bundle.url(forResource: "Configuration", withExtension: "plist"),
            let donnees = try? Data(contentsOf: url)
        else { return nil }
        return lire(donnees)
    }

    /// Lit le contenu de `Configuration.plist` ; nil s'il est incomplet ou invalide.
    static func lire(_ donnees: Data) -> ConfigurationMaison? {
        guard let f = try? PropertyListDecoder().decode(Fichier.self, from: donnees),
            let relais = Relais(adresse: f.relais)
        else { return nil }
        return ConfigurationMaison(relais: relais, autorite: f.autorite)
    }

    static func saisie(reglages: UserDefaults = .standard) -> ConfigurationMaison? {
        guard let adresse = reglages.string(forKey: cleAdresseSaisie), let relais = Relais(adresse: adresse) else {
            return nil
        }
        return ConfigurationMaison(relais: relais, autorite: nil)
    }

    private struct Fichier: Decodable {
        let relais: String
        let autorite: Data?

        enum CodingKeys: String, CodingKey {
            case relais = "Relais"
            case autorite = "Autorite"
        }
    }
}
