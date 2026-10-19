import AlfredKit
import Foundation
import Observation

/// La conversation avec Alfred : la parole (micro, détection, tours), l'écrit, les réponses et la voix.
///
/// Mêmes règles que la console :
/// - **conversation continue** : un toucher ouvre le micro ; chaque phrase est un tour ; après la réponse, Alfred
///   réécoute ; la conversation se ferme d'un toucher, ou après 90 s sans parole ;
/// - **demi-duplex** : pendant la réflexion et la voix d'Alfred, le micro n'envoie rien ; 1 s de marge après sa voix
///   (la fin de sa phrase ne doit pas ouvrir un tour) ;
/// - **rien de compris** : on réécoute, sans drame ;
/// - **échec** (délai, refus, coupure) : affiché, jamais renvoyé ; la conversation se ferme ;
/// - **un fil par conversation** : chaque conversation part d'un fil neuf, et une question écrite hors conversation
///   aussi (décision du 06.10 : les liens entre demandes ne valent que dans la même session ; la console :
///   `session.convId`) ;
/// - **pendant une réponse** (la console : `voiceAction`, `talk`) : toucher le noyau fait taire Alfred ; une question
///   écrite le fait taire et part, une fois son tour fini ; pendant la réflexion, rien ne part (le texte reste).
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

    static let silenceMaximal: Duration = .seconds(90)
    static let margeApresReponse = 16_000  // échantillons : 1 s à 16 kHz
    static let cleLireEcrit = "voix.lireReponsesEcrites"

    private(set) var phase: Phase = .repos
    private(set) var messages: [Message] = []
    /// Le micro est ouvert (conversation continue).
    private(set) var enConversation = false
    private(set) var avis: Avis?
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

    private let reglages: UserDefaults
    /// Le fil de HA de la conversation en cours (nil : un fil neuf au prochain tour).
    @ObservationIgnored private(set) var conversationId: String?
    @ObservationIgnored private var ecoute: Task<Void, Never>?
    @ObservationIgnored private var minuterieSilence: Task<Void, Never>?
    @ObservationIgnored private var lecture: Task<Void, Never>?
    @ObservationIgnored private var detecteur = DetecteurParole(conversation: true)
    @ObservationIgnored private var amorce = Amorce()
    /// Une phrase est en cours d'envoi (observé : l'écrit attend sa fin).
    private var tourOuvert = false
    @ObservationIgnored private var margeRestante = 0
    @ObservationIgnored private var tourVocal = false
    @ObservationIgnored private var voixEnCours = false
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
        let flux: AsyncStream<[Float]>
        do {
            flux = try voix.ouvrirMicro()
        } catch {
            aviser("Le micro n’a pas pu s’ouvrir.", .attention)
            return
        }
        signalerEntreeOubliee()
        enConversation = true
        conversationId = nil
        detecteur = DetecteurParole(conversation: true)
        ecouterTour(marge: 0)
        ecoute = Task { [weak self] in
            for await echantillons in flux {
                guard let self else { return }
                await self.entendre(echantillons)
            }
        }
    }

    private func ecouterTour(marge: Int) {
        phase = .ecoute
        let plancher = detecteur.plancher
        detecteur = DetecteurParole(conversation: true, plancher: plancher)
        amorce = Amorce()
        tourOuvert = false
        tourVocal = true
        margeRestante = marge
        armerSilence()
    }

    private func armerSilence() {
        minuterieSilence?.cancel()
        minuterieSilence = Task { [weak self] in
            try? await Task.sleep(for: Self.silenceMaximal)
            guard !Task.isCancelled, let self, self.enConversation, self.phase == .ecoute, !self.tourOuvert else {
                return
            }
            await self.terminer()
        }
    }

    /// Un paquet du micro (dans l'ordre, une seule tâche).
    func entendre(_ echantillons: [Float]) async {
        guard enConversation, phase == .ecoute, let client else {
            niveauMicro = 0
            return
        }
        niveauMicro = Self.niveau(echantillons)
        if margeRestante > 0 {
            detecteur.mesurer(echantillons)
            margeRestante -= echantillons.count
            return
        }
        let decisions = detecteur.analyser(echantillons)
        let pcm = PCM.enOctets(echantillons)
        if tourOuvert { await client.audio(pcm) } else { amorce.ajouter(pcm) }
        for decision in decisions {
            switch decision {
            case .attaque:
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
        niveauMicro = 0
        lecture?.cancel()
        voix.fermerMicro()
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
        switch phase {
        case .repos: true
        case .ecoute: !tourOuvert
        case .reponse: finRecue
        case .reflexion: false
        }
    }

    /// Une question écrite : true si elle est partie (sinon, le texte reste à qui l'a écrit). Dans une conversation,
    /// elle en garde le fil et la ferme ; hors conversation, elle part d'un fil neuf.
    @discardableResult
    func ecrire(_ texte: String) async -> Bool {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, peutEcrire else { return false }
        let fil = enConversation ? conversationId : nil
        if enConversation { await terminer() } else if phase == .reponse { interrompreReponse() }
        guard let client else {
            aviser("La maison n’est pas jointe pour l’instant.", .attention)
            return false
        }
        guard await client.ecrire(t, conversation: fil) else {
            await aviserRefus(client)
            return false
        }
        messages.append(Message(id: UUID(), auteur: .moi, texte: t, date: .now))
        conversationId = fil
        tourVocal = false
        finRecue = false
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

    /// Nouvelle conversation : Alfred oublie le fil (la session de parole de HA).
    func nouvelle() async {
        await terminer()
        lecture?.cancel()
        voix.interrompre()
        messages = []
        conversationId = nil
        messageAlfred = nil
        phase = .repos
    }

    // MARK: - ce que dit la maison

    func recevoir(_ signal: AutomateTour.Signal) {
        switch signal {
        case .transcrit(let texte):
            messages.append(Message(id: UUID(), auteur: .moi, texte: texte, date: .now))
            if DemandeLente.estLente(texte) { voix.accueillir() }
        case .reflechit:
            phase = .reflexion
            commencerReponse()
        case .outilCommence(let appel):
            modifierReponse {
                guard !$0.outils.contains(where: { $0.id == appel.id }) else { return }
                $0.outils.append(
                    Outil(id: appel.id, nom: appel.nomCourt, arguments: appel.argumentsEnTexte, etat: .enCours))
            }
        case .outilTermine(let id, let succes):
            modifierReponse { m in
                if let i = m.outils.firstIndex(where: { $0.id == id }) { m.outils[i].etat = succes ? .fait : .echec }
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
        case .voix(let chemin):
            guard tourVocal || lireReponsesEcrites else { return }
            voixEnCours = true
            phase = .reponse
            lecture = Task { [weak self] in
                guard let self else { return }
                await self.voix.lire(chemin)
                self.voixFinie()
            }
        case .rienSaisi:
            retirerReponseVide()
            if enConversation {
                aviser("Je n’ai rien saisi.", .info)
                ecouterTour(marge: 0)
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
            phase = .repos
            Task { await self.terminer() }
        case .termine(let conversation, _):
            if let conversation { conversationId = conversation }
            finRecue = true
            modifierReponse { $0.enCours = false }
            if !voixEnCours { tourFini() }
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
            ecouterTour(marge: Self.margeApresReponse)
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
