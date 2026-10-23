import AVFAudio
import Foundation

/// Le clip d'accueil (« Bien, Monsieur ») pendant une conversation, joué par le moteur du micro comme la voix d'Alfred.
///
/// Le traitement de la voix d'Apple baisse tout son de l'app qui ne passe pas par lui (« other audio », WWDC23
/// « What's new in voice processing ») : joué à côté, par un `AVAudioPlayer`, l'accueil sortait plus bas que la
/// réponse, à fichiers de même niveau. Ici, il a son propre nœud sur ce moteur (la réponse a le sien) et aucune mesure
/// sur le mélangeur (celle de la réponse anime le noyau).
///
/// Touché seulement par `VoixSysteme`, sur le fil principal.
final class LecteurAccueil {
    private let moteur: AVAudioEngine
    private let joueur = AVAudioPlayerNode()
    private var formatBranche: AVAudioFormat?

    /// Son moteur (celui du micro, le même que la réponse).
    var moteurAudio: AVAudioEngine { moteur }

    init(moteur: AVAudioEngine) {
        self.moteur = moteur
        moteur.attach(joueur)
    }

    deinit {
        moteur.detach(joueur)
    }

    /// Joue le clip depuis le début. false si le moteur ne tourne pas (micro fermé, matériel changé) : rien ne sonne,
    /// car jouer un nœud sur un moteur arrêté lève une exception, et seule la capture démarre ce moteur.
    @discardableResult
    func jouer(_ clip: AVAudioPCMBuffer) -> Bool {
        arreter()
        guard moteur.isRunning, clip.frameLength > 0 else { return false }
        // le nœud a le format du clip (doc d'Apple : un tampon a le taux et les canaux de la sortie du nœud) ; le
        // mélangeur fait le reste. Brancher en marche est permis en amont d'un mélangeur (doc d'AVAudioEngine).
        if formatBranche != clip.format || moteur.outputConnectionPoints(for: joueur, outputBus: 0).isEmpty {
            moteur.disconnectNodeOutput(joueur)
            moteur.connect(joueur, to: moteur.mainMixerNode, format: clip.format)
            formatBranche = clip.format
        }
        joueur.scheduleBuffer(clip, completionHandler: nil)
        joueur.play()
        return true
    }

    /// Coupe le clip net (doc d'Apple : `stop` retire tout ce qui était programmé).
    func arreter() {
        if joueur.isPlaying { joueur.stop() }
    }

    /// Un clip MP3 décodé d'avance (le format standard d'`AVAudioFile` : flottants, canaux séparés), prêt à jouer sans
    /// délai ; nil s'il est illisible, vide ou plus long que 10 s (un accueil dure 1 à 2 s). `AVAudioFile` ne lit qu'un
    /// fichier : le clip (la voix d'Alfred, rien de privé) passe un instant par le dossier temporaire de l'app.
    static func decoder(_ mp3: Data) -> AVAudioPCMBuffer? {
        let url = URL.temporaryDirectory.appending(path: "accueil-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? mp3.write(to: url)) != nil, let fichier = try? AVAudioFile(forReading: url) else { return nil }
        let format = fichier.processingFormat
        guard fichier.length > 0, Double(fichier.length) <= format.sampleRate * 10,
            let clip = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(fichier.length))
        else { return nil }
        guard (try? fichier.read(into: clip)) != nil, clip.frameLength > 0 else { return nil }
        return clip
    }
}
