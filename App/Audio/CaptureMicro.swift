@preconcurrency import AVFAudio
import AlfredKit
import Foundation

/// Le micro, rendu en échantillons flottants mono à 16 kHz (ce que HA et la détection de parole attendent).
///
/// - Traitement de la voix d'Apple ACTIVÉ (annulation d'écho, réduction du bruit, gain automatique) : c'est le réglage
///   par défaut de la console (contraintes du navigateur), celui qui a été mesuré au vrai micro.
/// - Les paquets du micro arrivent sur le fil audio ; ils sont convertis tout de suite et remis dans l'ordre à un seul
///   consommateur (`echantillons`).
final class CaptureMicro: @unchecked Sendable {
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// Le moteur du micro ; la voix d'Alfred y est jouée pendant une conversation (référence de l'annulation d'écho).
    let moteur = AVAudioEngine()
    private var convertisseur: AVAudioConverter?
    private var continuation: AsyncStream<[Float]>.Continuation?

    enum Erreur: Error {
        case formatMicro
    }

    /// Ouvre le micro. Les échantillons arrivent dans le flux rendu, jusqu'à `arreter()`.
    func demarrer() throws -> AsyncStream<[Float]> {
        arreter()
        let entree = moteur.inputNode
        // la voix d'Alfred passe par CE moteur : elle n'est pas baissée ; les autres sons (musique) le sont pendant la
        // conversation (réglage par défaut du traitement de la voix), ce qui aide à comprendre
        if !entree.isVoiceProcessingEnabled { try entree.setVoiceProcessingEnabled(true) }
        let formatMicro = entree.outputFormat(forBus: 0)
        guard formatMicro.sampleRate > 0, formatMicro.channelCount > 0,
            let conv = AVAudioConverter(from: formatMicro, to: Self.format)
        else { throw Erreur.formatMicro }
        convertisseur = conv
        let (flux, cont) = AsyncStream.makeStream(of: [Float].self, bufferingPolicy: .bufferingNewest(64))
        continuation = cont
        // ~20 ms par paquet au taux du micro
        let taille = AVAudioFrameCount(formatMicro.sampleRate / 50)
        entree.installTap(onBus: 0, bufferSize: taille, format: formatMicro) { [weak self] tampon, _ in
            guard let self, let echantillons = self.convertir(tampon, avec: conv) else { return }
            cont.yield(echantillons)
        }
        moteur.prepare()
        do {
            try moteur.start()
        } catch {
            entree.removeTap(onBus: 0)
            cont.finish()
            throw error
        }
        return flux
    }

    func arreter() {
        moteur.inputNode.removeTap(onBus: 0)
        if moteur.isRunning { moteur.stop() }
        continuation?.finish()
        continuation = nil
        convertisseur = nil
    }

    /// Conversion vers 16 kHz mono (appelée sur le fil audio : aucune allocation inutile, aucun verrou).
    private func convertir(_ tampon: AVAudioPCMBuffer, avec conv: AVAudioConverter) -> [Float]? {
        let rapport = Self.format.sampleRate / tampon.format.sampleRate
        let capacite = AVAudioFrameCount((Double(tampon.frameLength) * rapport).rounded(.up)) + 32
        guard let sortie = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacite) else { return nil }
        var fourni = false
        var erreur: NSError?
        let statut = conv.convert(to: sortie, error: &erreur) { _, etat in
            if fourni {
                etat.pointee = .noDataNow
                return nil
            }
            fourni = true
            etat.pointee = .haveData
            return tampon
        }
        guard statut != .error, let canal = sortie.floatChannelData?[0], sortie.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: canal, count: Int(sortie.frameLength)))
    }
}
