@preconcurrency import AVFAudio
import AlfredKit
import Foundation
import OSLog

/// Ce dont la conversation a besoin côté son. `VoixSysteme` sur l'appareil ; `VoixMuette` pour la démo et les tests.
@MainActor
protocol MoteurVoix: AnyObject {
    /// Demande l'accès au micro (la 1re fois, iOS pose la question) ; false s'il est refusé.
    func autoriserMicro() async -> Bool
    /// Ouvre la session audio et le micro pour une conversation ; les échantillons (16 kHz mono) arrivent dans le flux.
    func ouvrirMicro() throws -> AsyncStream<[Float]>
    /// Ferme le micro et rend la main au son des autres apps (la musique reprend).
    func fermerMicro()
    /// Lit la voix d'Alfred (chemin du relais) jusqu'au bout, ou jusqu'à `interrompre()`.
    func lire(_ chemin: String) async
    /// Coupe la voix d'Alfred et le clip d'accueil.
    func interrompre()
    /// Un court « Bien, Monsieur » (demande lente), coupé dès que la vraie réponse arrive.
    func accueillir()
    /// Niveau de la voix d'Alfred (0…1), pour le noyau.
    var niveauVoix: Float { get }
    /// Appelé quand iOS interrompt le son (appel, alarme, Siri) : la conversation se ferme.
    var surInterruption: (@MainActor () -> Void)? { get set }
    /// Les micros de l'appareil (micro intégré, AirPods, micro USB…), dans l'ordre d'iOS.
    func entrees() -> [EntreeMicro]
    /// Le micro choisi dans Réglages & état (nil : celui d'iOS), gardé sur l'appareil.
    var entreeChoisie: String? { get set }
    /// Le micro choisi n'était plus là à l'ouverture : iOS a repris le sien (la conversation le dit, puis remet à false).
    var entreeOubliee: Bool { get set }
}

/// Un micro de l'appareil (la console : un périphérique d'entrée audio).
struct EntreeMicro: Identifiable, Equatable, Sendable {
    let uid: String
    let nom: String
    var id: String { uid }
}

/// Le son sur l'appareil.
@MainActor
final class VoixSysteme: MoteurVoix {
    private let acces: AccesURLSession
    private let capture = CaptureMicro()
    private var lecteurConversation: LecteurVoix?
    private let lecteurSeul = LecteurVoix()
    private var lecture: Task<Void, Never>?
    private var clip: AVAudioPlayer?
    private var clips: [Int: Data] = [:]
    private var dernierClip = 0
    private var micOuvert = false
    private let journal = Logger(subsystem: "io.github.markedoe.alfred", category: "voix")
    var surInterruption: (@MainActor () -> Void)?
    var entreeOubliee = false
    private var observateur: (any NSObjectProtocol)?
    private let reglages: UserDefaults
    static let cleEntree = "micro.entree"

    init(acces: AccesURLSession, reglages: UserDefaults = .standard) {
        self.acces = acces
        self.reglages = reglages
        observateur = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let debut =
                (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            guard debut else { return }
            MainActor.assumeIsolated { self?.surInterruption?() }
        }
    }

    isolated deinit {
        if let observateur { NotificationCenter.default.removeObserver(observateur) }
    }

    /// Prépare les clips d'accueil du titre de la personne (Monsieur, Madame, Mademoiselle).
    func chargerClips(titre: String?) async {
        var charges: [Int: Data] = [:]
        for n in 1...ClipsAlfred.nombreAccueils {
            if let d = try? await acces.telecharger(ClipsAlfred.accueil(n, titre: titre)) { charges[n] = d }
        }
        clips = charges
    }

    func autoriserMicro() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    var entreeChoisie: String? {
        get { reglages.string(forKey: Self.cleEntree) }
        set { reglages.set(newValue, forKey: Self.cleEntree) }
    }

    /// La liste d'iOS (la catégorie « enregistrement » est posée sans activer la session : la musique continue).
    func entrees() -> [EntreeMicro] {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        }
        return (session.availableInputs ?? []).map { EntreeMicro(uid: $0.uid, nom: $0.portName) }
    }

    func ouvrirMicro() throws -> AsyncStream<[Float]> {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        // le micro choisi, s'il est encore là ; sinon celui d'iOS, et le choix périmé est oublié (comme la console)
        if let uid = entreeChoisie {
            if let port = session.availableInputs?.first(where: { $0.uid == uid }) {
                try? session.setPreferredInput(port)
            } else {
                entreeChoisie = nil
                entreeOubliee = true
                try? session.setPreferredInput(nil)
            }
        } else {
            try? session.setPreferredInput(nil)
        }
        try session.setActive(true)
        let flux: AsyncStream<[Float]>
        do {
            flux = try capture.demarrer()
        } catch {
            // la session non mixable a coupé la musique : elle lui est rendue
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        lecteurConversation = LecteurVoix(moteur: capture.moteur, possedeMoteur: false)
        micOuvert = true
        return flux
    }

    func fermerMicro() {
        interrompre()
        capture.arreter()
        lecteurConversation = nil
        micOuvert = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            journal.error("session audio non rendue : \(error.localizedDescription, privacy: .public)")
        }
    }

    func lire(_ chemin: String) async {
        interrompre()
        let lecteur = (micOuvert ? lecteurConversation : nil) ?? lecteurSeul
        if !micOuvert {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        let acces = self.acces
        let tache = Task.detached(priority: .userInitiated) {
            do {
                try await lecteur.lire(try await acces.flux(chemin), type: LecteurVoix.type(chemin: chemin))
            } catch is CancellationError {
            } catch {
                Logger(subsystem: "io.github.markedoe.alfred", category: "voix")
                    .error("voix illisible : \(error.localizedDescription, privacy: .public)")
            }
        }
        lecture = tache
        await tache.value
        if lecture == tache { lecture = nil }
        if !micOuvert { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func interrompre() {
        lecture?.cancel()
        lecture = nil
        clip?.stop()
        clip = nil
    }

    func accueillir() {
        let n = ClipsAlfred.prochainAccueil(apres: dernierClip, tirage: Int.random(in: 0..<ClipsAlfred.nombreAccueils))
        guard let d = clips[n], let joueur = try? AVAudioPlayer(data: d, fileTypeHint: "public.mp3") else { return }
        dernierClip = n
        clip?.stop()
        clip = joueur
        joueur.play()
    }

    var niveauVoix: Float {
        let lecteur = (micOuvert ? lecteurConversation : nil) ?? lecteurSeul
        return lecteur.niveau.withLock { $0 }
    }
}

/// Aucun son : la démo et les tests (le micro n'est jamais ouvert ; un « tour » se joue au texte).
@MainActor
final class VoixMuette: MoteurVoix {
    private var continuation: AsyncStream<[Float]>.Continuation?
    private(set) var lues: [String] = []
    private(set) var accueils = 0
    var surInterruption: (@MainActor () -> Void)?
    var entreeChoisie: String?
    var entreeOubliee = false

    /// Un seul micro, générique (la démo n'en ouvre aucun).
    func entrees() -> [EntreeMicro] { [EntreeMicro(uid: "demo", nom: "Micro de l’appareil")] }

    func autoriserMicro() async -> Bool { true }

    func ouvrirMicro() throws -> AsyncStream<[Float]> {
        let (flux, cont) = AsyncStream.makeStream(of: [Float].self)
        continuation = cont
        return flux
    }

    func fermerMicro() {
        continuation?.finish()
        continuation = nil
    }

    /// Pour les tests : fait « entendre » des échantillons.
    func entendre(_ echantillons: [Float]) { continuation?.yield(echantillons) }

    /// Pour les tests : chaque lecture dure jusqu'à `interrompre()` (Alfred « en train de parler »).
    var lectureTenue = false
    private(set) var interruptions = 0
    private var tenue: CheckedContinuation<Void, Never>?

    func lire(_ chemin: String) async {
        lues.append(chemin)
        guard lectureTenue else { return }
        await withCheckedContinuation { tenue = $0 }
    }

    func interrompre() {
        interruptions += 1
        tenue?.resume()
        tenue = nil
    }
    func accueillir() { accueils += 1 }
    var niveauVoix: Float { 0 }
}
