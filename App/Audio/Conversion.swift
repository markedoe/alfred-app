import AVFAudio

extension AVAudioConverter {
    /// Convertit UN tampon complet, rééchantillonnage compris. Le bloc d'entrée le fournit une fois, puis répond « plus
    /// rien pour l'instant » : le convertisseur garde son état (filtre, reste d'échantillons) pour le tampon suivant.
    func convertirUneFois(_ entree: AVAudioBuffer, vers sortie: AVAudioPCMBuffer) -> Bool {
        let fourni = Fourni()
        var erreur: NSError?
        let statut = convert(to: sortie, error: &erreur) { _, etat in
            if fourni.fait {
                etat.pointee = .noDataNow
                return nil
            }
            fourni.fait = true
            etat.pointee = .haveData
            return entree
        }
        return statut != .error && sortie.frameLength > 0
    }
}

/// Le bloc d'entrée n'est appelé que pendant `convert`, sur le fil de l'appelant : ce drapeau n'est jamais lu par deux
/// fils à la fois.
private final class Fourni: @unchecked Sendable {
    var fait = false
}
