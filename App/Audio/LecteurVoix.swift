@preconcurrency import AVFAudio
import AudioToolbox
import Foundation
import Synchronization

/// La voix d'Alfred, lue PENDANT sa synthèse : le relais sert l'audio au fil de l'eau ; chaque paquet est décodé et
/// joué dès qu'il arrive (pas d'attente du fichier entier). Le niveau de la voix anime le noyau.
///
/// Décodage : AudioFileStream (découpe en paquets) → AVAudioConverter (→ PCM) → AVAudioPlayerNode.
///
/// Le moteur : celui du micro pendant une conversation (le traitement de la voix connaît alors ce qu'Alfred dit et
/// l'ôte du micro), ou un moteur à lui pour une réponse écrite (le micro n'est jamais ouvert pour rien).
///
/// Concurrence : `lire` est appelée par UNE tâche à la fois ; tout l'état du décodage n'est touché que par elle (les
/// rappels du parseur sont synchrones, dans `AudioFileStreamParseBytes`). Pour arrêter, on annule cette tâche.
/// Seul `niveau` est lu ailleurs, sous verrou.
final class LecteurVoix: @unchecked Sendable {
    private let moteur: AVAudioEngine
    /// Le moteur est à ce lecteur (il le démarre et l'arrête) ; sinon il appartient à la capture du micro.
    private let possedeMoteur: Bool
    private let joueur = AVAudioPlayerNode()
    /// Niveau de la voix (0…1), lu par l'interface à chaque image.
    let niveau = Mutex<Float>(0)
    private let joues = Mutex<Int>(0)

    private var flux: AudioFileStreamID?
    private var formatSource: AVAudioFormat?
    private var formatSortie: AVAudioFormat?
    private var convertisseur: AVAudioConverter?
    private var programmes = 0
    private var enLecture = false
    /// Ce que la dernière lecture a fait (30.10, diagnostic de la voix) : octets reçus, tampons joués, et si elle a pu
    /// démarrer (le moteur du micro arrêté la rend muette sans erreur).
    struct Bilan: Sendable {
        var octets = 0
        var programmes = 0
        var joues = 0
        var demarree = false
        var moteurArrete = false
    }
    private var bilan = Bilan()

    /// Son moteur (pour reconnaître son arrêt par un changement de matériel).
    var moteurAudio: AVAudioEngine { moteur }

    init(moteur: AVAudioEngine = AVAudioEngine(), possedeMoteur: Bool = true) {
        self.moteur = moteur
        self.possedeMoteur = possedeMoteur
        moteur.attach(joueur)
    }

    deinit {
        moteur.detach(joueur)
    }

    /// Lit un flux audio jusqu'au bout. L'annulation de la tâche l'arrête net (et lève `CancellationError`).
    /// `type` : l'indice du format (`kAudioFileMP3Type`, `kAudioFileWAVEType`…), d'après l'extension du chemin.
    @discardableResult
    func lire<S: AsyncSequence>(_ octets: S, type: AudioFileTypeID) async throws -> Bilan where S.Element == UInt8 {
        bilan = Bilan()
        try ouvrir(type: type)
        defer { fermer() }
        var morceau: [UInt8] = []
        morceau.reserveCapacity(4096)
        for try await o in octets {
            bilan.octets += 1
            morceau.append(o)
            if morceau.count >= 4096 {
                try Task.checkCancellation()
                try analyser(morceau)
                morceau.removeAll(keepingCapacity: true)
            }
        }
        if !morceau.isEmpty { try analyser(morceau) }
        // un moteur arrêté (changement de matériel) ne jouera plus rien : on n'attend pas une fin qui ne viendrait pas
        while enLecture, joues.withLock({ $0 }) < programmes, moteur.isRunning {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
        bilan.programmes = programmes
        bilan.joues = joues.withLock { $0 }
        return bilan
    }

    static func type(chemin: String) -> AudioFileTypeID {
        switch (chemin as NSString).pathExtension.lowercased() {
        case "wav": kAudioFileWAVEType
        case "flac": kAudioFileFLACType
        case "aac", "m4a": kAudioFileAAC_ADTSType
        default: kAudioFileMP3Type
        }
    }

    // MARK: - cycle

    private func ouvrir(type: AudioFileTypeID) throws {
        programmes = 0
        joues.withLock { $0 = 0 }
        let contexte = Unmanaged.passUnretained(self).toOpaque()
        let statut = AudioFileStreamOpen(
            contexte,
            { contexte, _, propriete, _ in
                Unmanaged<LecteurVoix>.fromOpaque(contexte).takeUnretainedValue().propriete(propriete)
            },
            { contexte, octets, paquets, donnees, descriptions in
                Unmanaged<LecteurVoix>.fromOpaque(contexte).takeUnretainedValue()
                    .paquets(octets: octets, nombre: paquets, donnees: donnees, descriptions: descriptions)
            }, type, &flux)
        guard statut == noErr else { throw ErreurAudio.decodage(statut) }
    }

    private func fermer() {
        if let flux { AudioFileStreamClose(flux) }
        flux = nil
        formatSource = nil
        convertisseur = nil
        if joueur.isPlaying { joueur.stop() }
        joueur.reset()
        moteur.mainMixerNode.removeTap(onBus: 0)
        if possedeMoteur, moteur.isRunning { moteur.stop() }
        enLecture = false
        niveau.withLock { $0 = 0 }
    }

    private func analyser(_ morceau: [UInt8]) throws {
        guard let flux else { return }
        let statut = morceau.withUnsafeBytes { AudioFileStreamParseBytes(flux, UInt32($0.count), $0.baseAddress, []) }
        guard statut == noErr else { throw ErreurAudio.decodage(statut) }
    }

    // MARK: - rappels du parseur (synchrones, dans `analyser`)

    private func propriete(_ id: AudioFileStreamPropertyID) {
        guard id == kAudioFileStreamProperty_DataFormat, let flux else { return }
        var asbd = AudioStreamBasicDescription()
        var taille = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(flux, kAudioFileStreamProperty_DataFormat, &taille, &asbd) == noErr,
            let source = AVAudioFormat(streamDescription: &asbd),
            let sortie = AVAudioFormat(
                standardFormatWithSampleRate: asbd.mSampleRate,
                channels: max(1, asbd.mChannelsPerFrame))
        else { return }
        formatSource = source
        convertisseur = AVAudioConverter(from: source, to: sortie)
        if formatSortie != sortie || moteur.outputConnectionPoints(for: joueur, outputBus: 0).isEmpty {
            moteur.disconnectNodeOutput(joueur)
            moteur.connect(joueur, to: moteur.mainMixerNode, format: sortie)
            formatSortie = sortie
        }
    }

    private func paquets(
        octets: UInt32, nombre: UInt32, donnees: UnsafeRawPointer,
        descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        guard nombre > 0, let source = formatSource, let sortie = formatSortie, let conv = convertisseur else { return }
        let pcm: AVAudioPCMBuffer?
        if let descriptions {
            // format compressé (MP3…) : paquets de tailles variables, décrits un par un
            var tailleMax = 0
            for i in 0..<Int(nombre) { tailleMax = max(tailleMax, Int(descriptions[i].mDataByteSize)) }
            let compresse = AVAudioCompressedBuffer(
                format: source, packetCapacity: nombre, maximumPacketSize: tailleMax)
            compresse.data.copyMemory(from: donnees, byteCount: Int(octets))
            compresse.byteLength = octets
            compresse.packetCount = nombre
            compresse.packetDescriptions?.update(from: descriptions, count: Int(nombre))
            let parPaquet = max(source.streamDescription.pointee.mFramesPerPacket, 1)
            pcm = convertir(compresse, avec: conv, vers: sortie, capacite: parPaquet * nombre)
        } else {
            // PCM (WAV) : paquets de taille fixe
            let parTrame = max(source.streamDescription.pointee.mBytesPerFrame, 1)
            let trames = octets / parTrame
            guard trames > 0, let brut = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: trames) else { return }
            brut.frameLength = trames
            UnsafeMutableRawPointer(brut.mutableAudioBufferList.pointee.mBuffers.mData)?
                .copyMemory(from: donnees, byteCount: Int(trames * parTrame))
            pcm = convertir(brut, avec: conv, vers: sortie, capacite: trames)
        }
        if let pcm { programmer(pcm) }
    }

    private func convertir(
        _ entree: AVAudioBuffer, avec conv: AVAudioConverter, vers sortie: AVAudioFormat,
        capacite: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard let pcm = AVAudioPCMBuffer(pcmFormat: sortie, frameCapacity: max(capacite, 1)) else { return nil }
        return conv.convertirUneFois(entree, vers: pcm) ? pcm : nil
    }

    private func programmer(_ pcm: AVAudioPCMBuffer) {
        programmes += 1
        joueur.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.joues.withLock { $0 += 1 }
        }
        guard !enLecture else { return }
        do {
            // le moteur du micro n'est démarré que par la capture : arrêté (micro fermé, matériel changé), la voix ne
            // le relance pas (son entrée garde l'ancien format)
            if !moteur.isRunning, !possedeMoteur {
                bilan.moteurArrete = true
                return
            }
            installerMesure()
            if !moteur.isRunning {
                moteur.prepare()
                try moteur.start()
            }
            joueur.play()
            enLecture = true
            bilan.demarree = true
        } catch {
            enLecture = false
        }
    }

    private func installerMesure() {
        let melangeur = moteur.mainMixerNode
        melangeur.removeTap(onBus: 0)
        melangeur.installTap(onBus: 0, bufferSize: 1024, format: melangeur.outputFormat(forBus: 0)) {
            [weak self] tampon, _ in
            guard let canal = tampon.floatChannelData?[0], tampon.frameLength > 0 else { return }
            var somme: Float = 0
            for i in 0..<Int(tampon.frameLength) { somme += canal[i] * canal[i] }
            let rms = (somme / Float(tampon.frameLength)).squareRoot()
            self?.niveau.withLock { $0 = min(1, rms * 4) }
        }
    }
}

enum ErreurAudio: Error, Equatable {
    case decodage(OSStatus)
    case permissionMicro
}
