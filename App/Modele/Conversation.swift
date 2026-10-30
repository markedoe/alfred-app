import AlfredKit
import Foundation
import Observation

/// La conversation avec Alfred : la parole (micro, détection, tours), l'écrit, les réponses et la voix.
///
/// Mêmes règles que la console :
/// - **conversation continue** : un toucher ouvre le micro ; chaque phrase est un tour ; après la réponse, Alfred
///   réécoute ; la conversation se ferme d'un toucher, ou après 90 s sans parole ;
/// - **micro coupé** (24.10 ; 25.10, retour d’essai : « vraiment couper le micro, instantanément, comme le bouton micro
///   de Claude » ; 30.10 : « si je coupe le micro, il ne fait pas la partie analyse ») : au toucher, plus RIEN ne part
///   ensuite ; une phrase en cours est ENVOYÉE telle quelle (fin de phrase : Alfred la comprend et répond) ; le micro
///   d’iOS s’éteint aussitôt — ou dès la fin de la voix d’Alfred s’il parle ou va répondre (sa voix passe par le même
///   moteur) ; sa réponse à une question déjà posée arrive quand même ; la conversation reste ouverte
///   (même fil), 10 min au plus ; rouvert, le micro se rallume et Alfred réécoute. Avant : la phrase commencée continuait,
///   la pièce qui parlait la tenait ouverte (Alfred entendait tout), puis le tour échouait au bout de 90 s et fermait la
///   conversation (« il ne réécoute pas ») ;
/// - **demi-duplex** : pendant la réflexion et la voix d'Alfred, le micro n'envoie rien ; 1 s de marge après sa voix
///   (la fin de sa phrase ne doit pas ouvrir un tour) ;
/// - **rien de compris** : on réécoute, sans drame ;
/// - **échec** (délai, refus, coupure) : affiché, jamais renvoyé ; la conversation se ferme ;
/// - **un fil par conversation** : chaque conversation part d'un fil neuf, et une question écrite hors conversation
///   aussi (décision du 06.10 : les liens entre demandes ne valent que dans la même session ; la console :
///   `session.convId`) ;
/// - **pendant une réponse** (la console : `voiceAction`, `talk`) : toucher le noyau fait taire Alfred ; une question
///   écrite le fait taire et part, une fois son tour fini ; pendant la réflexion, rien ne part (le texte reste) ;
/// - **l'écrit dans une conversation** (la console : `talk`, décision du 21.10) : la question garde le fil ET la
///   conversation ; sa réponse est lue, puis Alfred réécoute.
@Observable @MainActor
final class Conversation {
    enum Phase: Hashable, Sendable {
        case repos
        case ecoute
        case reflexion
        case reponse
    }

    /// Un outil appelé par Alfred, comme les « Détails techniques » de la console : son nom court et ses arguments
    /// (jamais le contenu de son résultat : l'agenda, par exemple, est privé).
    struct Outil: Identifiable, Equatable, Sendable {
        enum Etat: Equatable, Sendable { case enCours, fait, echec }
        let id: String
        let nom: String
        let arguments: String
        var etat: Etat
    }

    struct Message: Identifiable, Equatable, Sendable {
        enum Auteur: Equatable, Sendable { case moi, alfred }
        let id: UUID
        let auteur: Auteur
        var texte: String
        var outils: [Outil] = []
        var enCours = false
        var erreur = false
        var comprisLocalement = false
        /// Le temps de la réponse (de la demande comprise à la fin d'Alfred), comme le badge « 1.4s » de la console.
        var duree: Double?
        let date: Date
    }

    /// L'essai du micro (Réglages & état) : le micro s'ouvre et son niveau s'affiche ; rien n'est envoyé à la maison.
    enum Essai: Equatable, Sendable {
        case arrete, ouverture, actif
    }

    /// Un avis passager (en haut de l'écran, avec un retour haptique).
    struct Avis: Identifiable, Equatable, Sendable {
        enum Genre: Equatable, Sendable { case info, attention }
        let id = UUID()
        let texte: String
        let genre: Genre
    }

    /// Ce que VoiceOver doit dire (la console : le journal des échanges en `aria-live`).
    struct Annonce: Identifiable, Equatable, Sendable {
        let id = UUID()
        let texte: String
    }

    static let silenceMaximal: Duration = .seconds(90)
    /// Micro coupé : la conversation reste ouverte au plus ce temps-là (la console : `SESSION_MUET_MS`).
    static let silenceMicroCoupe: Duration = .seconds(600)
    static let margeApresReponse = 16_000  // échantillons : 1 s à 16 kHz
    static let cleLireEcrit = "voix.lireReponsesEcrites"

    private(set) var phase: Phase = .repos
    private(set) var messages: [Message] = []
    /// Le micro est ouvert (conversation continue).
    private(set) var enConversation = false
    /// 24.10 (« un bouton qui coupe le micro ») : dans la conversation, Alfred n’entend plus rien.
    private(set) var microCoupe = false

    /// La phase MONTRÉE (noyau, panneaux, statut) : micro coupé, Alfred n'écoute plus et ne doit plus en avoir l'air —
    /// comme la console, qui quitte l'écoute au micro coupé (`toggleMute` : `setMode("idle")`). Retour d'essai du
    /// 30.10 : « le micro était coupé, mais il n'arrêtait pas d'écouter » (le noyau restait sarcelle et animé).
    var phaseAffichee: Phase { microCoupe && phase == .ecoute ? .repos : phase }
    /// Le micro d'iOS allumé (il s'éteint quand le micro est coupé, puis se rallume).
    @ObservationIgnored private var micAllume = false
    /// L'écran reste allumé tant qu'une conversation est en cours : micro ouvert, réflexion, réponse ou envoi (22.10,
    /// retour d'essai : le verrouillage automatique d'iOS cachait l'app et coupait tout) ; aussi pendant l'attente des
    /// réponses d'Hermes (5 min au plus chacune) et jusqu'à leur lecture. Au repos, iOS reprend la main.
    var ecranAllume: Bool {
        enConversation || phase != .repos || envoiEnCours || !attentesHermes.isEmpty || !differees.isEmpty
    }

    /// Une réponse d'Hermes réclamée, pas encore montrée ni lue.
    struct ReponseDifferee: Equatable, Sendable {
        let texte: String
        let chemin: String?
        let aVoix: Bool
    }

    /// Une question confiée à Hermes ICI, dont la réponse est attendue (23.10 : une attente par question ; avec une
    /// seule, deux questions de suite ne faisaient lire que la 1re réponse).
    struct AttenteHermes: Equatable, Sendable {
        /// La réponse réclamée pour une attente fermée entre-temps (déconnexion, session expirée) est ignorée.
        let numero: Int
        /// L'appel de l'outil : un appel annoncé deux fois n'ouvre qu'une attente.
        let appel: String?
        /// L'heure de la question : une réponse plus ancienne n'est pas la sienne.
        let posee: Date
        /// 5 min après la question, ou après la réponse précédente (Hermes traite une question à la fois).
        var echeance: Date
        /// Partie à la voix (ou réponses écrites lues) : sa réponse se lit ; sinon, elle s'affiche seulement.
        let aVoix: Bool
    }

    /// 22.10 (retour d'essai : « je m'attendais à ce qu'Alfred me dicte la réponse d'Hermes ») : les questions confiées
    /// à Hermes ICI (l'outil script__demander_hermes, ou un outil mémoire ou e-mails dont le relais a passé la question
    /// à Hermes), dans l'ordre (le relais y répond dans cet ordre, une à la fois).
    /// Leurs réponses arrivent plus tard : `Annexes` les réclame au relais (toutes les 3 s pendant l'attente) et les
    /// passe à `recevoirDifferee`.
    private(set) var attentesHermes: [AttenteHermes] = []
    private(set) var differees: [ReponseDifferee] = []
    @ObservationIgnored private var numeroHermes = 0
    /// Appelé quand une attente commence : `Annexes` relit les notifications tout de suite.
    @ObservationIgnored var quandAttenteHermes: (@MainActor () -> Void)?
    static let attenteHermesMax: TimeInterval = 5 * 60
    private(set) var avis: Avis?
    /// La réponse à une question écrite qui n'est pas lue à voix haute, ou l'échec d'une demande : VoiceOver la dit.
    /// Jamais micro ouvert (le micro entendrait VoiceOver).
    private(set) var annonce: Annonce?
    /// Une question écrite part (observé : « Envoyer » attend ; ni le micro ni un 2e envoi ne partent entre-temps).
    private(set) var envoiEnCours = false
    /// Nombre de tours de voix réussis (retour haptique « succès »).
    private(set) var reponses = 0
    /// La durée de la dernière réponse (la console : « Dernière réponse », dans Réglages & état).
    private(set) var derniereDuree: Double?
    private(set) var essai = Essai.arrete
    private(set) var messageEssai = Conversation.messageEssaiInitial
    /// Le niveau du micro pendant l'essai (0…1), lu à chaque image par la jauge (hors observation).
    @ObservationIgnored private(set) var niveauEssai: Float = 0
    @ObservationIgnored private var tacheEssai: Task<Void, Never>?

    static let messageEssaiInitial = "Autorisez le micro, puis lancez le test pour vérifier le signal ici."
    /// Lire à voix haute les réponses aux questions écrites (comme Siri : non par défaut).
    var lireReponsesEcrites: Bool {
        didSet { reglages.set(lireReponsesEcrites, forKey: Self.cleLireEcrit) }
    }

    /// Niveau du micro (0…1), lu à chaque image par le noyau (hors observation : pas 50 invalidations par seconde).
    @ObservationIgnored private(set) var niveauMicro: Float = 0
    @ObservationIgnored private(set) var voix: any MoteurVoix
    @ObservationIgnored var client: ClientRelais?
    /// Les étapes de la voix notées par le relais (30.10) ; nil dans la démo et les tests.
    @ObservationIgnored var diagnostic: DiagnosticVoix?

    private let reglages: UserDefaults
    /// Le fil de HA de la conversation en cours (nil : un fil neuf au prochain tour).
    @ObservationIgnored private(set) var conversationId: String?
    /// La dernière réponse d'Alfred attend une suite (`continue_conversation` de HA : il a posé une question). La réponse
    /// suivante, écrite ou dite, garde alors le fil, même hors conversation — retour d'essai du 30.10 : « rappelle-moi de
    /// vérifier la garantie » → « À quel moment ? » → « lundi » partait d'un fil neuf, Alfred avait tout oublié.
    @ObservationIgnored private(set) var suiteAttendue = false
    @ObservationIgnored private var ecoute: Task<Void, Never>?
    @ObservationIgnored private var minuterieSilence: Task<Void, Never>?
    @ObservationIgnored private var lecture: Task<Void, Never>?
    @ObservationIgnored private var detecteur = DetecteurParole(conversation: true)
    @ObservationIgnored private var amorce = Amorce()
    /// Une phrase est en cours d'envoi (observé : l'écrit attend sa fin).
    private var tourOuvert = false
    @ObservationIgnored private var margeRestante = 0
    @ObservationIgnored private var tourVocal = false
    /// La maison a annoncé la voix de ce tour (30.10, revue du son : un tour à la voix fini sans voix est noté).
    @ObservationIgnored private var voixAnnoncee = false
    @ObservationIgnored private var voixEnCours = false
    /// La lecture en cours : une lecture coupée qui finit après le début de la suivante ne clôt pas le tour de celle-ci.
    @ObservationIgnored private var lectureEnCours = UUID()
    /// Le tour de la maison est fini (observé : pendant la voix d'Alfred, l'écrit attend cette fin).
    private var finRecue = false
    @ObservationIgnored private var messageAlfred: UUID?

    init(voix: any MoteurVoix, reglages: UserDefaults = .standard) {
        self.voix = voix
        self.reglages = reglages
        lireReponsesEcrites = reglages.bool(forKey: Self.cleLireEcrit)
        brancher(voix)
    }

    private func brancher(_ v: any MoteurVoix) {
        v.surInterruption = { [weak self] motif in
            Task {
                await self?.couper()
                if let motif { self?.aviser(motif, .attention) }
            }
        }
    }

    var niveauVoix: Float { voix.niveauVoix }

    /// Le son de l'appareil, une fois la maison jointe (la démo et les tests gardent la voix muette).
    func remplacerVoix(_ v: any MoteurVoix) {
        voix.interrompre()
        voix.surInterruption = nil
        voix = v
        brancher(v)
    }
    var vide: Bool { messages.isEmpty }

    // MARK: - parole

    /// Le toucher du noyau : ouvre la conversation, ou la ferme ; Alfred qui parle hors conversation se tait (la
    /// console : `voiceAction`). Pendant la réflexion, rien.
    func basculerEcoute() async {
        if enConversation {
            await terminer()
            return
        }
        if phase == .reponse {
            interrompreReponse()
            return
        }
        guard phase == .repos, essai == .arrete else { return }
        guard client != nil else {
            aviser("La maison n’est pas jointe pour l’instant.", .attention)
            return
        }
        guard await voix.autoriserMicro() else {
            aviser("Alfred n’a pas accès au micro. Autorisez-le dans Réglages › Alfred.", .attention)
            return
        }
        guard allumerMicro() else { return }
        signalerEntreeOubliee()
        enConversation = true
        microCoupe = false
        if !suiteAttendue { conversationId = nil }
        detecteur = DetecteurParole(conversation: true)
        ecouterTour(marge: 0)
    }

    /// Allume le micro d'iOS et la tâche qui l'écoute ; false (et c'est dit) s'il ne s'ouvre pas.
    private func allumerMicro() -> Bool {
        let flux: AsyncStream<[Float]>
        do {
            flux = try voix.ouvrirMicro()
        } catch {
            aviser("Le micro n’a pas pu s’ouvrir.", .attention)
            return false
        }
        micAllume = true
        ecoute = Task { [weak self] in
            for await echantillons in flux {
                guard let self else { return }
                await self.entendre(echantillons)
            }
        }
        return true
    }

    /// Éteint le micro d'iOS (micro coupé) : jamais pendant la voix d'Alfred, qui passe par le même moteur.
    private func eteindreMicro() {
        guard micAllume else { return }
        ecoute?.cancel()
        ecoute = nil
        voix.fermerMicro()
        micAllume = false
        niveauMicro = 0
    }

    /// Réécoute après un tour ; micro coupé, le micro d'iOS s'éteint (la voix d'Alfred est finie).
    private func reecouter(marge: Int) {
        ecouterTour(marge: marge)
        if microCoupe { eteindreMicro() }
    }

    private func ecouterTour(marge: Int) {
        phase = .ecoute
        let plancher = detecteur.plancher
        detecteur = DetecteurParole(conversation: true, plancher: plancher)
        amorce = Amorce()
        tourOuvert = false
        tourVocal = true
        voixAnnoncee = false
        margeRestante = marge
        armerSilence()
    }

    /// Couper ou rouvrir le micro pendant la conversation (le bouton du micro, la touche « m »).
    func basculerMicro() {
        guard enConversation else { return }
        microCoupe.toggle()
        if microCoupe {
            niveauMicro = 0
            // 30.10 (retour d'essai : « si je coupe le micro, il ne fait pas la partie analyse ») : la phrase en cours est
            // ENVOYÉE, comme le bouton micro de Claude garde ce qui a été dicté — Alfred la comprend et répond, puis le
            // micro reste coupé (25.10 → 30.10 : elle était abandonnée, rien n'était compris)
            if tourOuvert {
                tourOuvert = false
                phase = .reflexion
                let client = client
                Task { await client?.finParole() }
            }
            if phase == .ecoute { eteindreMicro() }  // sinon dès la fin de la voix d'Alfred (reecouter)
        } else {
            if !micAllume, !allumerMicro() {
                microCoupe = true
                return
            }
            // rien de ce qui précède ne compte : détecteur et amorce neufs
            if phase == .ecoute { ecouterTour(marge: 0) }
        }
        armerSilence()
    }

    private func armerSilence() {
        minuterieSilence?.cancel()
        let duree = microCoupe ? Self.silenceMicroCoupe : Self.silenceMaximal
        minuterieSilence = Task { [weak self] in
            try? await Task.sleep(for: duree)
            guard !Task.isCancelled, let self, self.enConversation, self.phase == .ecoute, !self.tourOuvert else {
                return
            }
            await self.terminer()
        }
    }

    /// Un paquet du micro (dans l'ordre, une seule tâche).
    func entendre(_ echantillons: [Float]) async {
        // micro coupé : plus rien, instantanément (une phrase en cours a été abandonnée)
        guard enConversation, phase == .ecoute, !envoiEnCours, !microCoupe, let client else {
            niveauMicro = 0
            return
        }
        niveauMicro = Self.niveau(echantillons)
        if margeRestante > 0 {
            detecteur.mesurer(echantillons)
            margeRestante -= echantillons.count
            // 30.10 (revue du son) : la marge garde aussi l'amorce — une réplique dite aussitôt après Alfred gardait sa
            // fin de phrase, mais perdait son premier mot (l'attaque n'est cherchée qu'après la marge)
            amorce.ajouter(PCM.enOctets(echantillons))
            return
        }
        let decisions = detecteur.analyser(echantillons)
        let pcm = PCM.enOctets(echantillons)
        if tourOuvert { await client.audio(pcm) } else { amorce.ajouter(pcm) }
        for decision in decisions {
            switch decision {
            case .attaque:
                // le micro a pu être coupé pendant l'envoi du paquet précédent : aucune phrase ne s'ouvre
                guard !microCoupe else { return }
                minuterieSilence?.cancel()
                guard await client.parler(conversation: conversationId, amorce: amorce.prendre()) else {
                    await aviserRefus(client)
                    await terminer()
                    return
                }
                // la conversation a pu se fermer pendant l'envoi (toucher, app cachée) : la phrase se clôt aussitôt
                guard enConversation else {
                    await client.finParole()
                    return
                }
                // micro coupé pendant l'ouverture (avant le premier mot envoyé) : la maison annule ce tour vide
                guard !microCoupe else {
                    await client.abandonnerParole()
                    return
                }
                tourOuvert = true
                finRecue = false
            case .fin:
                guard tourOuvert else { continue }
                await client.finParole()
                tourOuvert = false
                phase = .reflexion
                niveauMicro = 0
            case .bruitIgnore:
                continue
            }
        }
    }

    /// L'app cachée, un appel, Siri, la liaison coupée : le micro se ferme, l'essai s'arrête et Alfred se tait (la
    /// console à la coupure : `endSession`, `stopTest`, `stopSpeaking`).
    func couper() async {
        arreterEssai()
        await terminer()
        interrompreReponse()
    }

    /// Alfred se tait (sa voix s'arrête) ; son tour finit normalement quand la maison le clôt.
    private func interrompreReponse() {
        lecture?.cancel()
        voix.interrompre()
    }

    /// Ferme la conversation (toucher, silence, interruption par iOS, app en arrière-plan).
    func terminer() async {
        guard enConversation else { return }
        minuterieSilence?.cancel()
        ecoute?.cancel()
        ecoute = nil
        // une phrase en cours d'envoi part quand même : le flux se ferme proprement
        if tourOuvert, let client {
            await client.finParole()
            tourOuvert = false
            phase = .reflexion
        }
        enConversation = false
        microCoupe = false
        niveauMicro = 0
        lecture?.cancel()
        voix.fermerMicro()
        micAllume = false
        if phase == .ecoute || phase == .reponse { phase = .repos }
    }

    // MARK: - essai du micro

    /// « Tester le micro » / « Arrêter le test » (la console : `micTest`) : le niveau s'affiche, aucun pipeline n'est
    /// lancé ; sans signal au bout de 2,5 s, on le dit.
    func basculerEssai() async {
        if essai != .arrete {
            arreterEssai()
            return
        }
        guard !enConversation, phase == .repos else { return }
        essai = .ouverture
        messageEssai = "Ouverture du micro… Acceptez la demande d’iOS si elle apparaît."
        guard await voix.autoriserMicro() else {
            essai = .arrete
            messageEssai = "Test micro impossible : l’accès au micro est refusé. Autorisez-le dans Réglages › Alfred."
            return
        }
        let flux: AsyncStream<[Float]>
        do {
            flux = try voix.ouvrirMicro()
        } catch {
            essai = .arrete
            messageEssai = "Test micro impossible : le micro n’a pas pu s’ouvrir."
            return
        }
        signalerEntreeOubliee()
        essai = .actif
        messageEssai = "Test actif · parlez : la barre ci-dessous doit réagir. Aucun son n’est envoyé à Alfred."
        let debut = Date.now
        tacheEssai = Task { [weak self] in
            var pic: Float = 0
            var silence = false
            for await echantillons in flux {
                guard let self, self.essai == .actif else { return }
                let n = Self.niveau(echantillons)
                self.niveauEssai = n
                pic = max(pic, n)
                if n > Self.seuilSignal, silence {
                    silence = false
                    self.messageEssai = "Signal reçu · le microphone fonctionne. Vous pouvez arrêter le test."
                }
                if !silence, pic <= Self.seuilSignal, Date.now.timeIntervalSince(debut) > 2.5 {
                    silence = true
                    self.messageEssai =
                        "Micro ouvert, mais aucun signal reçu. Parlez ou choisissez une autre entrée ; vérifiez aussi "
                        + "l’accès au micro dans Réglages › Alfred."
                }
            }
        }
    }

    /// Fin de l'essai (le bouton, la fenêtre fermée, l'app cachée) : le micro est libéré.
    func arreterEssai() {
        guard essai != .arrete else { return }
        tacheEssai?.cancel()
        tacheEssai = nil
        voix.fermerMicro()
        essai = .arrete
        niveauEssai = 0
        messageEssai = "Test arrêté · microphone libéré."
    }

    /// « Autoriser le micro » (la console : `unlockDevices`).
    func autoriserMicro() async {
        guard essai == .arrete, !enConversation else { return }
        if await voix.autoriserMicro() {
            let nom = voix.entrees().first { $0.uid == voix.entreeChoisie }?.nom ?? voix.entrees().first?.nom
            messageEssai =
                "Micro autorisé" + (nom.map { " · " + $0 } ?? "")
                + ". Lancez « Tester le micro » pour vérifier le signal."
        } else {
            messageEssai = "Autorisation micro refusée. Autorisez le micro dans Réglages › Alfred."
        }
    }

    /// Les micros de l'appareil, et celui qui est choisi (nil : celui d'iOS).
    func entreesMicro() -> [EntreeMicro] { voix.entrees() }
    var entreeMicroChoisie: String? { voix.entreeChoisie }

    /// Un autre micro : gardé sur l'appareil ; un essai en cours repart avec lui (comme la console).
    func choisirEntreeMicro(_ uid: String?) {
        voix.entreeChoisie = uid
        guard essai == .actif else { return }
        arreterEssai()
        Task { await basculerEssai() }
    }

    /// Le micro choisi a disparu (AirPods rangés, micro débranché) : retour à celui d'iOS, et on le dit.
    private func signalerEntreeOubliee() {
        guard voix.entreeOubliee else { return }
        voix.entreeOubliee = false
        aviser("Le micro choisi n’est plus là : retour au micro par défaut.", .attention)
    }

    static let seuilSignal: Float = 0.02

    // MARK: - écrit

    /// Une question écrite peut partir (la console : `talk`, `#send-text`) : au repos, au micro avant toute phrase, ou
    /// pendant la voix d'Alfred une fois son tour fini (elle le fait taire) ; jamais pendant la réflexion.
    var peutEcrire: Bool {
        if envoiEnCours { return false }
        return switch phase {
        case .repos: true
        case .ecoute: !tourOuvert
        case .reponse: finRecue
        case .reflexion: false
        }
    }

    /// Une question écrite : true si elle est partie (sinon, le texte reste à qui l'a écrit). Dans une conversation,
    /// elle en garde le fil, la conversation reste ouverte, sa réponse est lue et Alfred réécoute ensuite (la console :
    /// `talk`) ; hors conversation, elle part d'un fil neuf, sauf si Alfred vient de poser une question (`suiteAttendue`). Rien ne change avant que la maison l'ait acceptée : un
    /// refus ne fait pas taire Alfred, ne ferme rien, et le texte reste.
    @discardableResult
    func ecrire(_ texte: String) async -> Bool {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, peutEcrire else { return false }
        guard let client else {
            aviser("La maison n’est pas jointe pour l’instant.", .attention)
            return false
        }
        envoiEnCours = true
        defer { envoiEnCours = false }
        let fil = enConversation || suiteAttendue ? conversationId : nil
        minuterieSilence?.cancel()
        guard await client.ecrire(t, conversation: fil) else {
            if enConversation, phase == .ecoute { armerSilence() }
            await aviserRefus(client)
            return false
        }
        // Alfred qui lisait la réponse précédente (son tour est fini) se tait ; la question part
        if phase == .reponse { interrompreReponse() }
        messages.append(Message(id: UUID(), auteur: .moi, texte: t, date: .now))
        conversationId = fil
        tourVocal = enConversation
        voixAnnoncee = false
        finRecue = false
        niveauMicro = 0
        phase = .reflexion
        commencerReponse()
        return true
    }

    /// Un tour refusé par le client : la maison injoignable, ou une demande encore en cours.
    private func aviserRefus(_ client: ClientRelais) async {
        if case .pret = await client.etat {
            aviser("Alfred termine la demande précédente. Réessayez dans un instant.", .info)
        } else {
            aviser("La maison n’est pas jointe pour l’instant.", .attention)
        }
    }

    /// Nouvelle conversation : Alfred oublie le fil (la session de parole de HA). Elle sert à la déconnexion, à la
    /// session expirée et à la sortie de la démo : les réponses d'Hermes attendues ou en suspens sont oubliées aussi
    /// (23.10 : l'écran ne se verrouillait plus, et la personne suivante pouvait les voir et les entendre) ; celle
    /// d'une réclamation encore en route est ignorée à son retour (son attente n'existe plus).
    func nouvelle() async {
        await terminer()
        lecture?.cancel()
        voix.interrompre()
        // une lecture coupée qui finit plus tard ne clôt plus rien
        lectureEnCours = UUID()
        voixEnCours = false
        finRecue = false
        messages = []
        conversationId = nil
        suiteAttendue = false
        messageAlfred = nil
        attentesHermes = []
        differees = []
        phase = .repos
    }

    // MARK: - ce que dit la maison

    func recevoir(_ signal: AutomateTour.Signal) {
        switch signal {
        case .transcrit(let texte):
            messages.append(Message(id: UUID(), auteur: .moi, texte: texte, date: .now))
            // le « Bien, Monsieur » d'une demande lente : seulement micro ouvert (une conversation fermée pendant la
            // réflexion n'a plus de session audio active, et le clip couperait la musique)
            if enConversation, DemandeLente.estLente(texte) { voix.accueillir() }
        case .reflechit:
            phase = .reflexion
            commencerReponse()
        case .outilCommence(let appel):
            modifierReponse {
                guard !$0.outils.contains(where: { $0.id == appel.id }) else { return }
                $0.outils.append(
                    Outil(id: appel.id, nom: appel.nomCourt, arguments: appel.argumentsEnTexte, etat: .enCours))
            }
            if appel.nomCourt.hasSuffix("demander_hermes"), !attentesHermes.contains(where: { $0.appel == appel.id }) {
                attendreHermes(appel: appel.id)
            }
        case .outilTermine(let id, let succes, let hermes):
            modifierReponse { m in
                if let i = m.outils.firstIndex(where: { $0.id == id }) { m.outils[i].etat = succes ? .fait : .echec }
            }
            // l'outil mémoire ou e-mails n'a rien trouvé : le relais a confié la question à Hermes, sa réponse arrive ici
            if hermes, !attentesHermes.contains(where: { $0.appel == id }) {
                attendreHermes(appel: id)
            }
        case .fragment(let morceau):
            modifierReponse { $0.texte += morceau }
        case .reponse(let fin):
            modifierReponse {
                if !fin.texte.isEmpty { $0.texte = fin.texte }
                $0.enCours = false
                $0.comprisLocalement = fin.traiteeLocalement
                $0.duree = Date.now.timeIntervalSince($0.date)
                derniereDuree = $0.duree
            }
            reponses += 1
            // une réponse écrite qui ne sera pas lue à voix haute : VoiceOver la dit
            if !tourVocal, !lireReponsesEcrites {
                annoncer(messages.first { $0.id == messageAlfred }?.texte ?? fin.texte)
            }
        case .voix(let chemin):
            let lue = tourVocal || lireReponsesEcrites
            voixAnnoncee = true
            diagnostic?.noter(
                "annoncee",
                ["lue": lue ? "oui" : "non", "phase": "\(phase)", "micro_coupe": microCoupe ? "oui" : "non"])
            guard lue else { return }
            voixEnCours = true
            phase = .reponse
            let id = UUID()
            lectureEnCours = id
            lecture = Task { [weak self] in
                guard let self else { return }
                await self.voix.lire(chemin)
                guard self.lectureEnCours == id else { return }
                self.voixFinie()
            }
        case .abandonne:  // micro coupé à l'ouverture d'une phrase : rien n'a été compris ni fait
            retirerReponseVide()
            if enConversation, phase != .ecoute { reecouter(marge: 0) }
        case .rienSaisi:
            retirerReponseVide()
            if enConversation {
                aviser("Je n’ai rien saisi.", .info)
                reecouter(marge: 0)
            } else {
                phase = .repos
            }
        case .echec(let message):
            voix.interrompre()
            if messageAlfred == nil { commencerReponse() }
            modifierReponse {
                $0.texte = message
                $0.enCours = false
                $0.erreur = true
            }
            messageAlfred = nil
            // le tour est clos par la maison (coupure, refus, délai) : aucune phrase n'est plus en cours d'envoi. Sans
            // ça, la fermeture qui suit croyait la phrase encore en vol et remettait la réflexion, pour toujours (21.10)
            tourOuvert = false
            phase = .repos
            Task {
                await self.terminer()
                self.annoncer(message)
            }
        case .termine(let conversation, let continuer):
            if let conversation { conversationId = conversation }
            suiteAttendue = continuer && conversationId != nil
            if tourVocal, !voixAnnoncee { diagnostic?.noter("sans_voix", ["phase": "\(phase)"]) }
            finRecue = true
            modifierReponse { $0.enCours = false }
            if !voixEnCours { tourFini() }
        }
    }

    // MARK: - réponse d'Hermes, lue ici (22.10)

    /// Une question confiée à Hermes : une attente de plus, après celles des questions précédentes.
    @discardableResult
    func attendreHermes(appel: String? = nil) -> AttenteHermes {
        diagnostic?.noter("hermes_attente", ["lue": tourVocal || lireReponsesEcrites ? "oui" : "non"])
        numeroHermes += 1
        let maintenant = Date.now
        let fin = maintenant.addingTimeInterval(Self.attenteHermesMax)
        let lue = tourVocal || lireReponsesEcrites
        let a = AttenteHermes(numero: numeroHermes, appel: appel, posee: maintenant, echeance: fin, aVoix: lue)
        attentesHermes.append(a)
        quandAttenteHermes?()
        return a
    }

    /// À son échéance, une attente se ferme (le relais a envoyé la réponse sur le téléphone).
    func expirerAttenteHermes(maintenant: Date = .now) {
        guard attentesHermes.contains(where: { maintenant > $0.echeance }) else { return }
        attentesHermes.removeAll { maintenant > $0.echeance }
    }

    /// La réponse réclamée pour l'attente `numero` : montrée, puis lue (si sa question l'a été), dès que possible ;
    /// `livrer` faux (app cachée), elle attend le prochain passage d'`Annexes`. Une attente fermée entre-temps (par
    /// `nouvelle()` : déconnexion, session expirée, démo quittée) ne livre rien.
    func recevoirDifferee(texte: String, chemin: String?, attente numero: Int, livrer: Bool = true) {
        guard let i = attentesHermes.firstIndex(where: { $0.numero == numero }) else { return }
        let attente = attentesHermes.remove(at: i)
        // Hermes ne prend la question suivante qu'après celle-ci (une à la fois) : ses 5 min repartent d'ici
        let fin = Date.now.addingTimeInterval(Self.attenteHermesMax)
        for j in attentesHermes.indices where attentesHermes[j].echeance < fin { attentesHermes[j].echeance = fin }
        guard !texte.isEmpty else { return }
        differees.append(ReponseDifferee(texte: texte, chemin: chemin, aVoix: attente.aVoix))
        if livrer { livrerDifferees() }
    }

    /// Au repos, ou micro ouvert avant toute phrase : affichée comme une réponse d'Alfred, puis lue comme une réponse
    /// ordinaire (micro ouvert, `entendre` ignore tout pendant la voix, puis Alfred réécoute avec la marge d'après
    /// réponse). Pendant un tour : au prochain passage d'`Annexes` (toutes les 3 s).
    func livrerDifferees() {
        guard let d = differees.first, !envoiEnCours, !voixEnCours else { return }
        guard phase == .repos || (phase == .ecoute && !tourOuvert) else { return }
        differees.removeFirst()
        messages.append(Message(id: UUID(), auteur: .alfred, texte: d.texte, date: .now))
        diagnostic?.noter(
            "hermes_livree", ["avec_voix": d.aVoix && d.chemin != nil ? "oui" : "non", "phase": "\(phase)"])
        guard d.aVoix, let chemin = d.chemin else {
            annoncer(d.texte)
            return
        }
        minuterieSilence?.cancel()
        voixEnCours = true
        finRecue = true
        phase = .reponse
        let id = UUID()
        lectureEnCours = id
        lecture = Task { [weak self] in
            guard let self else { return }
            await self.voix.lire(chemin)
            guard self.lectureEnCours == id else { return }
            self.voixFinie()
        }
    }

    private func voixFinie() {
        voixEnCours = false
        if finRecue { tourFini() }
    }

    private func tourFini() {
        messageAlfred = nil
        finRecue = false
        if enConversation {
            reecouter(marge: Self.margeApresReponse)
        } else {
            phase = .repos
        }
    }

    private func commencerReponse() {
        let m = Message(id: UUID(), auteur: .alfred, texte: "", enCours: true, date: .now)
        messages.append(m)
        messageAlfred = m.id
    }

    private func modifierReponse(_ changer: (inout Message) -> Void) {
        guard let id = messageAlfred, let i = messages.firstIndex(where: { $0.id == id }) else { return }
        changer(&messages[i])
    }

    private func retirerReponseVide() {
        if let id = messageAlfred, let i = messages.firstIndex(where: { $0.id == id }), messages[i].texte.isEmpty {
            messages.remove(at: i)
        }
        messageAlfred = nil
    }

    func aviser(_ texte: String, _ genre: Avis.Genre) {
        avis = Avis(texte: texte, genre: genre)
    }

    private func annoncer(_ texte: String) {
        guard !enConversation, essai == .arrete, !texte.isEmpty else { return }
        annonce = Annonce(texte: texte)
    }

    func oublierAvis(_ a: Avis) {
        if avis == a { avis = nil }
    }

    // MARK: - outils

    static func niveau(_ echantillons: [Float]) -> Float {
        guard !echantillons.isEmpty else { return 0 }
        var somme: Float = 0
        for s in echantillons { somme += s * s }
        return min(1, (somme / Float(echantillons.count)).squareRoot() * 6)
    }
}
