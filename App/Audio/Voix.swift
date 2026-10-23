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
    /// Un court « Bien, Monsieur » (demande lente), coupé dès que la vraie réponse arrive ; jamais par-dessus une
    /// réponse.
    func accueillir()
    /// Niveau de la voix d'Alfred (0…1), pour le noyau.
    var niveauVoix: Float { get }
    /// Appelé quand le son s'arrête sans nous : iOS l'interrompt (appel, alarme, Siri ; motif nil), le matériel change
    /// (écouteurs mis ou retirés) ou le service média redémarre (motif : ce que la conversation dit). Elle se ferme.
    var surInterruption: (@MainActor (_ motif: String?) -> Void)? { get set }
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
    // refaits si le service média d'iOS redémarre (doc d'Apple : tous les objets audio sont à recréer)
    private var capture = CaptureMicro()
    private var lecteurConversation: LecteurVoix?
    /// L'accueil pendant une conversation, sur le moteur du micro comme la réponse (voir `LecteurAccueil`).
    private var accueilConversation: LecteurAccueil?
    private var lecteurSeul = LecteurVoix()
    private var lecture: Task<Void, Never>?
    /// L'accueil hors conversation : un lecteur à part (aucun traitement de la voix ne le baisse).
    private var clip: AVAudioPlayer?
    private var clips: [Int: Data] = [:]
    /// Les mêmes clips décodés d'avance, pour le moteur du micro.
    private var clipsDecodes: [Int: AVAudioPCMBuffer] = [:]
    private var dernierClip = 0
    private var micOuvert = false
    private let journal = Logger(subsystem: "io.github.markedoe.alfred", category: "voix")
    var surInterruption: (@MainActor (_ motif: String?) -> Void)?
    var entreeOubliee = false
    private var observateurs: [any NSObjectProtocol] = []
    private let reglages: UserDefaults
    static let cleEntree = "micro.entree"

    init(acces: AccesURLSession, reglages: UserDefaults = .standard) {
        self.acces = acces
        self.reglages = reglages
        let centre = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observateurs.append(
            centre.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) {
                [weak self] note in
                let debut =
                    (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
                guard debut else { return }
                MainActor.assumeIsolated { self?.surInterruption?(nil) }
            })
        // le matériel change (écouteurs mis ou retirés, autre fréquence) : le moteur s'arrête seul et se désinitialise
        // (doc d'Apple, AVAudioEngineConfigurationChangeNotification) ; sans ça, la conversation attendait 90 s un
        // micro muet, ou la voix d'Alfred une fin qui ne venait pas
        observateurs.append(
            centre.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) {
                [weak self] note in
                guard let moteur = note.object as AnyObject? else { return }
                let id = ObjectIdentifier(moteur)
                MainActor.assumeIsolated { self?.moteurChange(id) }
            })
        observateurs.append(
            centre.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.servicesRedemarres() }
            })
        // des écouteurs retirés : Alfred se tait au lieu de continuer sur le haut-parleur (sa réponse peut être privée ;
        // doc d'Apple, « Responding to audio route changes » : « automatically pause playback when users disconnect
        // their headphones »). La notification arrive sur un autre fil : la file principale la reçoit.
        observateurs.append(
            centre.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) {
                [weak self] note in
                let raison = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                guard VoixSysteme.seTaire(apres: raison) else { return }
                MainActor.assumeIsolated { self?.interrompre() }
            })
    }

    /// Un appareil de sortie a disparu (écouteurs retirés, AirPods rangés) : Alfred se tait.
    nonisolated static func seTaire(apres raison: AVAudioSession.RouteChangeReason?) -> Bool {
        raison == .oldDeviceUnavailable
    }

    isolated deinit {
        for o in observateurs { NotificationCenter.default.removeObserver(o) }
    }

    /// Un moteur s'est arrêté avec le matériel. Le notre seulement, et seulement s'il est vraiment arrêté (activer le
    /// traitement de la voix peut aussi annoncer un changement, moteur toujours en marche).
    private func moteurChange(_ id: ObjectIdentifier) {
        let micro = micOuvert ? (id: ObjectIdentifier(capture.moteur), tourne: capture.moteur.isRunning) : nil
        let lecteur = (id: ObjectIdentifier(lecteurSeul.moteurAudio), tourne: lecteurSeul.moteurAudio.isRunning)
        let suite = Self.suite(moteur: id, micro: micro, lecteur: lecteur)
        switch suite {
        case .fermerConversation:
            journal.notice("moteur du micro arrêté par un changement de matériel")
            surInterruption?(Self.motifMateriel)
        case .taireAlfred: interrompre()
        case .rien: break
        }
    }

    enum SuiteChangement: Equatable { case rien, fermerConversation, taireAlfred }
    static let motifMateriel = "Le son a changé de sortie (écouteurs) : touchez le noyau pour reprendre."

    /// Que faire d'un changement de matériel annoncé pour `moteur` : `micro` (le moteur du micro et s'il tourne) quand
    /// une conversation est ouverte, `lecteur` (celui de la voix hors conversation). Seul NOTRE moteur compte, et
    /// seulement s'il s'est vraiment arrêté (activer le traitement de la voix l'annonce aussi, moteur en marche).
    nonisolated static func suite(
        moteur: ObjectIdentifier, micro: (id: ObjectIdentifier, tourne: Bool)?,
        lecteur: (id: ObjectIdentifier, tourne: Bool)
    ) -> SuiteChangement {
        if let micro, moteur == micro.id { return micro.tourne ? .rien : .fermerConversation }
        if moteur == lecteur.id, !lecteur.tourne { return .taireAlfred }
        return .rien
    }

    /// Le service média d'iOS a redémarré (rare ; Réglages › Développeur › « Reset Media Services » le provoque) :
    /// les objets audio sont refaits (doc d'Apple) ; une conversation ouverte se ferme et le dit.
    private func servicesRedemarres() {
        journal.notice("service média redémarré")
        let ouvert = micOuvert
        interrompre()
        capture.arreter()
        lecteurConversation = nil
        accueilConversation = nil
        micOuvert = false
        capture = CaptureMicro()
        lecteurSeul = LecteurVoix()
        if ouvert { surInterruption?("Le son de l’appareil a redémarré : touchez le noyau pour reprendre.") }
    }

    /// Prépare les clips d'accueil du titre de la personne (Monsieur, Madame, Mademoiselle), décodés d'avance pour
    /// le moteur du micro.
    func chargerClips(titre: String?) async {
        var charges: [Int: Data] = [:]
        var decodes: [Int: AVAudioPCMBuffer] = [:]
        for n in 1...ClipsAlfred.nombreAccueils {
            guard let d = try? await acces.telecharger(ClipsAlfred.accueil(n, titre: titre)) else { continue }
            charges[n] = d
            if let clip = LecteurAccueil.decoder(d) { decodes[n] = clip }
        }
        clips = charges
        clipsDecodes = decodes
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

    /// La liste d'iOS (la catégorie « enregistrement » est posée sans activer la session : la musique continue). Jamais
    /// pendant qu'Alfred parle ou que le micro est ouvert : changer la catégorie d'une session active couperait la
    /// musique et pourrait arrêter sa voix.
    func entrees() -> [EntreeMicro] {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord, lecture == nil, clip == nil, !micOuvert {
            try? session.setCategory(.playAndRecord, mode: .voiceChat, options: Self.optionsMicro)
        }
        return (session.availableInputs ?? []).map { EntreeMicro(uid: $0.uid, nom: $0.portName) }
    }

    /// Le haut-parleur plutôt que l'écouteur de l'iPhone, et les micros Bluetooth.
    static let optionsMicro: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]

    func ouvrirMicro() throws -> AsyncStream<[Float]> {
        let session = AVAudioSession.sharedInstance()
        // le mode « voiceChat » : celui que le traitement de la voix (annulation d'écho) pose de lui-même s'il ne l'est
        // pas (doc d'Apple) ; posé d'avance, il ne change plus à l'ouverture du micro
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: Self.optionsMicro)
        try session.setActive(true)
        // le micro choisi, APRÈS l'activation (doc d'Apple de setPreferredInput : « only after setting the audio
        // session's category and mode and activating the session »), s'il est encore là ; sinon celui d'iOS, et le choix
        // périmé est oublié (comme la console). Un micro qu'iOS refuse : celui d'iOS pour cette fois, et c'est dit.
        if let uid = entreeChoisie {
            if let port = session.availableInputs?.first(where: { $0.uid == uid }) {
                do {
                    try session.setPreferredInput(port)
                } catch {
                    journal.error("micro choisi refusé par iOS : \(error.localizedDescription, privacy: .public)")
                    entreeOubliee = true
                }
            } else {
                entreeChoisie = nil
                entreeOubliee = true
                try? session.setPreferredInput(nil)
            }
        } else {
            try? session.setPreferredInput(nil)
        }
        let flux: AsyncStream<[Float]>
        do {
            flux = try capture.demarrer()
        } catch {
            // la session non mixable a coupé la musique : elle lui est rendue
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        let lecteurs = Self.lecteurs(moteur: capture.moteur)
        lecteurConversation = lecteurs.reponse
        accueilConversation = lecteurs.accueil
        micOuvert = true
        return flux
    }

    /// Les lecteurs d'une conversation, tous deux sur le moteur du micro : la réponse (le traitement de la voix la
    /// connaît et l'ôte du micro) et l'accueil (joué à côté, il serait baissé par ce traitement).
    nonisolated static func lecteurs(moteur: AVAudioEngine) -> (reponse: LecteurVoix, accueil: LecteurAccueil) {
        (LecteurVoix(moteur: moteur, possedeMoteur: false), LecteurAccueil(moteur: moteur))
    }

    func fermerMicro() {
        interrompre()
        capture.arreter()
        lecteurConversation = nil
        accueilConversation = nil
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
            // une réponse lue par synthèse : le mode « voicePrompt », avec les options que la doc d'Apple lui associe
            // (la musique baisse, un podcast s'interrompt)
            try? AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
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
        arreterAccueil()
    }

    private func arreterAccueil() {
        clip?.stop()
        clip = nil
        accueilConversation?.arreter()
    }

    /// Par où passe l'accueil.
    enum CheminAccueil: Equatable { case moteurDuMicro, lecteurAPart, aucun }

    /// Rien pendant une réponse (l'accueil et la réponse ne se chevauchent jamais ; la réponse, elle, coupe l'accueil) ;
    /// micro ouvert, le moteur du micro, celui de la réponse ; micro fermé, un lecteur à part, comme la réponse lue
    /// hors conversation (rien ne la baisse).
    nonisolated static func cheminAccueil(micOuvert: Bool, reponseEnCours: Bool) -> CheminAccueil {
        if reponseEnCours { return .aucun }
        return micOuvert ? .moteurDuMicro : .lecteurAPart
    }

    func accueillir() {
        let n = ClipsAlfred.prochainAccueil(apres: dernierClip, tirage: Int.random(in: 0..<ClipsAlfred.nombreAccueils))
        switch Self.cheminAccueil(micOuvert: micOuvert, reponseEnCours: lecture != nil) {
        case .aucun:
            return
        case .moteurDuMicro:
            guard let decode = clipsDecodes[n], let accueil = accueilConversation else {
                // un clip que l'app n'a pas su décoder : à côté, comme avant (plus bas, mais dit)
                accueillirAPart(n)
                return
            }
            arreterAccueil()
            // moteur arrêté (matériel changé : la conversation se ferme) : rien ne sonne
            if accueil.jouer(decode) { dernierClip = n }
        case .lecteurAPart:
            accueillirAPart(n)
        }
    }

    private func accueillirAPart(_ n: Int) {
        guard let d = clips[n], let joueur = try? AVAudioPlayer(data: d, fileTypeHint: "public.mp3") else { return }
        dernierClip = n
        arreterAccueil()
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
    /// Les accueils joués ; `cheminsAccueil` : par où chacun des demandés serait passé (la règle de `VoixSysteme`).
    private(set) var accueils = 0
    private(set) var cheminsAccueil: [VoixSysteme.CheminAccueil] = []
    var surInterruption: (@MainActor (_ motif: String?) -> Void)?
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

    /// Pour les tests : le son s'arrête sans nous (un appel : motif nil ; des écouteurs : un motif).
    func simulerInterruption(_ motif: String?) { surInterruption?(motif) }

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
    func accueillir() {
        let chemin = VoixSysteme.cheminAccueil(micOuvert: continuation != nil, reponseEnCours: tenue != nil)
        cheminsAccueil.append(chemin)
        if chemin != .aucun { accueils += 1 }
    }
    var niveauVoix: Float { 0 }
}
