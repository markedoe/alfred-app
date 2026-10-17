import AVFAudio

extension AVAudioConverter {
    /// Convertit UN tampon complet, rééchantillonnage compris. Le bloc d'entrée le fournit une fois, puis répond « plus
    /// rien pour l'instant » : le convertisseur garde son état (filtre, reste d'échantillons) pour le tampon suivant.
    func convertirUneFois(_ entree: AVAudioBuffer, vers sortie: AVAudioPCMBuffer) -> Bool {
        let source = SourceUnique(entree)
        var erreur: NSError?
        let statut = convert(to: sortie, error: &erreur) { _, etat in
            guard let tampon = source.prendre() else {
                etat.pointee = .noDataNow
                return nil
            }
            etat.pointee = .haveData
            return tampon
        }
        return statut != .error && sortie.frameLength > 0
    }
}

/// Le tampon à fournir une seule fois. Le bloc d'entrée n'est appelé que PENDANT `convert`, sur le fil de l'appelant :
/// cette boîte n'est jamais lue par deux fils à la fois.
private final class SourceUnique: @unchecked Sendable {
    private var tampon: AVAudioBuffer?

    init(_ tampon: AVAudioBuffer) { self.tampon = tampon }

    func prendre() -> AVAudioBuffer? {
        defer { tampon = nil }
        return tampon
    }
}
