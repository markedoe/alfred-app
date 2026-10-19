import Foundation
import Security

/// La session de la personne dans le trousseau de CET appareil : jamais synchronisée (iCloud), jamais sauvegardée
/// ailleurs, lisible après le premier déverrouillage (l'app peut se reconnecter à la maison écran verrouillé).
enum Trousseau {
    private static let service = "io.github.markedoe.alfred.session"

    struct Erreur: Error, Equatable {
        let statut: OSStatus
    }

    static func lire(compte: String) -> String? {
        let requete: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: compte,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var resultat: CFTypeRef?
        guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
            let donnees = resultat as? Data
        else { return nil }
        return String(data: donnees, encoding: .utf8)
    }

    /// Remplace la session (mise à jour, sinon ajout) : un échec laisse l'ancienne en place, jamais aucune.
    static func ecrire(_ valeur: String, compte: String) throws {
        let element: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: compte,
        ]
        let attributs: [CFString: Any] = [
            kSecValueData: Data(valeur.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var statut = SecItemUpdate(element as CFDictionary, attributs as CFDictionary)
        if statut == errSecItemNotFound {
            let nouveau = element.merging(attributs) { $1 }.merging([kSecAttrSynchronizable: false]) { $1 }
            statut = SecItemAdd(nouveau as CFDictionary, nil)
        }
        guard statut == errSecSuccess else { throw Erreur(statut: statut) }
    }

    static func effacer(compte: String) {
        let requete: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: compte,
        ]
        SecItemDelete(requete as CFDictionary)
    }
}
