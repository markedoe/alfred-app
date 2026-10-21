import Foundation
import Security

/// La session de la personne dans le trousseau de CET appareil : jamais synchronisée (iCloud), jamais sauvegardée
/// ailleurs, lisible après le premier déverrouillage (l'app peut se reconnecter à la maison écran verrouillé).
enum Trousseau {
    private static let service = "io.github.markedoe.alfred.session"

    struct Erreur: Error, Equatable {
        let statut: OSStatus
    }

    /// Les fonctions du trousseau d'iOS ; les tests en donnent d'autres (une fabrication non signée, celle de la CI,
    /// n'a pas accès au vrai trousseau : -34018).
    struct Acces: Sendable {
        var copier: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        var ajouter: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        var modifier: @Sendable (CFDictionary, CFDictionary) -> OSStatus
        var supprimer: @Sendable (CFDictionary) -> OSStatus

        static let systeme = Acces(
            copier: { SecItemCopyMatching($0, $1) }, ajouter: { SecItemAdd($0, $1) },
            modifier: { SecItemUpdate($0, $1) }, supprimer: { SecItemDelete($0) })
    }

    static func lire(compte: String, acces: Acces = .systeme) -> String? {
        let requete: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: compte,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var resultat: CFTypeRef?
        guard acces.copier(requete as CFDictionary, &resultat) == errSecSuccess, let donnees = resultat as? Data
        else { return nil }
        return String(data: donnees, encoding: .utf8)
    }

    /// Remplace la session (mise à jour, sinon ajout) : un échec laisse l'ancienne en place, jamais aucune.
    static func ecrire(_ valeur: String, compte: String, acces: Acces = .systeme) throws {
        let element: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: compte,
        ]
        let attributs: [CFString: Any] = [
            kSecValueData: Data(valeur.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var statut = acces.modifier(element as CFDictionary, attributs as CFDictionary)
        if statut == errSecItemNotFound {
            let nouveau = element.merging(attributs) { $1 }.merging([kSecAttrSynchronizable: false]) { $1 }
            statut = acces.ajouter(nouveau as CFDictionary, nil)
        }
        guard statut == errSecSuccess else { throw Erreur(statut: statut) }
    }

    static func effacer(compte: String, acces: Acces = .systeme) {
        let requete: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: compte,
        ]
        _ = acces.supprimer(requete as CFDictionary)
    }
}
