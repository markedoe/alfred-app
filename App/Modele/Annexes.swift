import AlfredKit
import Foundation
import Observation

/// Les annexes de la console, autour de la conversation : documents, notifications, liens vers les autres systèmes
/// et état des services. Mêmes routes et mêmes rythmes que la console :
/// - documents : toutes les 60 s, toutes les 2,5 s tant qu'un document est en lecture ou en rangement, 10 s si un
///   résumé est en file (23.10), 30 s après un échec ;
/// - notifications : toutes les 15 s (la personne connectée seulement) ; toutes les 3 s pendant l'attente d'une réponse
///   d'Hermes posée ici (22.10), réclamée puis passée à la conversation pour être lue ;
/// - liens : une fois (redemandés toutes les 15 s si la maison ne répond pas) ;
/// - état des services : toutes les 30 s.
/// Rien ne tourne app cachée : `suspendre()` arrête tout (une réclamation déjà partie finit, et sa réponse attend le
/// retour à l'écran), `reprendre()` relit tout de suite.
@Observable @MainActor
final class Annexes {
    /// Ce qu'un document peut montrer à la place de la liste (accès refusé, liste indisponible).
    enum AccesDocuments: Equatable, Sendable {
        case ouvert
        case reserve(String)
    }

    private(set) var documents: [DocumentMaison] = []
    /// 23.10 (soir, retour d'essai : « ajouter les docs, choisir le tag et cliquer sur envoyer ») : « À envoyer », les
    /// fichiers choisis — rien n'est parti ; le lot envoyé, ses lignes sont retirées.
    private(set) var aEnvoyer: [FichierAEnvoyer] = []
    /// 23.10 (soir) : le dernier lot envoyé, fichier par fichier (« En cours », puis la confirmation).
    private(set) var suivi = SuiviLot()
    /// 23.10 (soir) : « 3 documents rangés dans Paperless — voir » ; disparaît seule après 60 s, ou au prochain ajout.
    private(set) var confirmation: ConfirmationRangement?
    /// 23.10 : les fichiers refusés par l'appareil ou au dépôt (trop lourd, type) : une carte locale, jusqu'à « Retirer ».
    private(set) var refusLocaux: [RefusLocal] = []
    /// 23.10 : la pastille de l'en-tête : ce qui demande une action (en cours, refusés), refus locaux compris.
    private(set) var pastilleDocuments = 0
    /// 23.10 : le bouton armé (« Retirer », « Supprimer ») d'une carte, gardé ici et non dans la carte : une relecture de
    /// la liste ne le remet pas à zéro.
    private(set) var deuxTemps = DeuxTemps()
    /// 23.10 : les étiquettes proposées au dépôt (`GET /docs/etiquettes`) ; nil : le relais ne les connaît pas (plus
    /// ancien) ou ne les a pas encore données — le champ « Étiquettes » est alors caché.
    private(set) var etiquettes: ListeEtiquettes?
    private(set) var accesDocuments = AccesDocuments.ouvert
    /// « Envoi de devis.pdf… », « Reçu. Alfred le lit… » (la ligne d'état de la console, sous le dépôt).
    private(set) var etatDepot: String?
    /// Le dernier échec d'un dépôt ou d'une suppression, écrit dans la fenêtre Documents elle-même (un avis de la
    /// console resterait caché sous la fenêtre ouverte).
    private(set) var erreurDepot: String?
    private(set) var envoiEnCours = false
    private(set) var notifications: [NotificationConsole] = []
    private(set) var nonLues = 0
    /// Les notifications existent pour la personne connectée (le bouton de l'en-tête n'apparaît qu'alors).
    private(set) var notificationsPermises = false
    private(set) var liens: [LienSysteme] = []
    private(set) var etat: EtatServices?

    /// 22.10 : la conversation qui attend une réponse d'Hermes posée ici, et la lit.
    @ObservationIgnored weak var conversation: Conversation?
    /// La réclamation en cours d'une réponse d'Hermes (23.10) : une tâche à part, qu'aucune relecture ni suspension
    /// n'annule (coupée en route, la réponse, déjà marquée livrée par le relais, n'était ni lue ni envoyée au
    /// téléphone).
    @ObservationIgnored private var reclamation: Task<Void, Never>?
    @ObservationIgnored private let acces: any AccesRelais
    @ObservationIgnored private let aviser: @MainActor (String, Conversation.Avis.Genre) -> Void
    @ObservationIgnored private var taches: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var connecte = false
    /// La dernière liste du relais (pour la pastille : son compte `a_revoir`).
    @ObservationIgnored private var listeDocuments: ListeDocuments?
    /// 23.10 (soir) : d'où lire chaque fichier valable de « À envoyer » au moment de l'envoi.
    @ObservationIgnored private var sources: [UUID: SourceFichier] = [:]
    @ObservationIgnored private var finConfirmation: Task<Void, Never>?
    /// Les relectures tournent.
    @ObservationIgnored private var actif = false
    /// L'app est cachée : rien ne repart avant `reprendre()`, même une reconnexion.
    @ObservationIgnored private var cachee = false

    init(acces: any AccesRelais, aviser: @escaping @MainActor (String, Conversation.Avis.Genre) -> Void) {
        self.acces = acces
        self.aviser = aviser
    }

    // MARK: - cycle

    /// La personne est connectée (`/moi`) : notifications et liens ; l'état et les documents tournent dans tous les cas.
    func demarrer(connecte: Bool) {
        self.connecte = connecte
        guard !cachee else { return }
        relancerTout()
    }

    func reprendre() {
        cachee = false
        guard !actif else { return }
        relancerTout()
    }

    func suspendre() {
        cachee = true
        arreterBoucles()
    }

    private func arreterBoucles() {
        actif = false
        for t in taches.values { t.cancel() }
        taches = [:]
    }

    private func relancerTout() {
        arreterBoucles()
        actif = true
        boucle("etat") { [weak self] in await self?.chargerEtat() ?? .seconds(30) }
        boucle("documents") { [weak self] in await self?.chargerDocuments() ?? .seconds(60) }
        if connecte {
            boucle("notifications") { [weak self] in await self?.chargerNotifications() ?? .seconds(15) }
            boucle("liens") { [weak self] in await self?.chargerLiens() }
        } else {
            notificationsPermises = false
            liens = []
        }
    }

    /// Une lecture, puis la suivante après le délai qu'elle rend (nil : plus de relecture).
    private func boucle(_ nom: String, _ lire: @escaping @MainActor () async -> Duration?) {
        taches[nom]?.cancel()
        taches[nom] = Task { [weak self] in
            while !Task.isCancelled {
                guard let delai = await lire() else { return }
                try? await Task.sleep(for: delai)
                guard self?.actif == true else { return }
            }
        }
    }

    /// Relire les documents tout de suite (après un dépôt, une suppression, à l'ouverture de la fenêtre).
    func relireDocuments() {
        guard actif else { return }
        boucle("documents") { [weak self] in await self?.chargerDocuments() ?? .seconds(60) }
    }

    /// 23.10 : relire les étiquettes proposées (à l'ouverture de la fenêtre Documents). 404 : un relais plus ancien
    /// (champ caché) ; la maison muette : liste vide, « indisponible » (un nom nouveau reste possible).
    func relireEtiquettes() {
        guard actif else { return }
        Task { [weak self] in await self?.chargerEtiquettes() }
    }

    private func chargerEtiquettes() async {
        guard let (statut, corps) = try? await acces.lire("/docs/etiquettes") else {
            if etiquettes != nil { etiquettes = ListeEtiquettes(etiquettes: [], disponible: false) }
            return
        }
        let l: ListeEtiquettes? =
            switch statut {
            case 200:
                (try? JSONDecoder().decode(ListeEtiquettes.self, from: corps))
                    ?? ListeEtiquettes(etiquettes: [], disponible: false)
            case 500...: ListeEtiquettes(etiquettes: [], disponible: false)
            default: nil
            }
        if l != etiquettes { etiquettes = l }
    }

    func relireNotifications() {
        guard actif, connecte else { return }
        boucle("notifications") { [weak self] in await self?.chargerNotifications() ?? .seconds(15) }
    }

    // MARK: - lectures

    private func chargerEtat() async -> Duration {
        if let (statut, corps) = try? await acces.lire("/etat"), statut == 200,
            let e = try? JSONDecoder().decode(EtatServices.self, from: corps)
        {
            if e != etat { etat = e }
        }
        return .seconds(30)
    }

    private func chargerDocuments() async -> Duration {
        let lecture = suivi.lectureLancee()
        do {
            let (statut, corps) = try await acces.lire("/docs")
            switch statut {
            case 200:
                let liste = try JSONDecoder().decode(ListeDocuments.self, from: corps)
                if accesDocuments != .ouvert { accesDocuments = .ouvert }
                if liste.documents != documents { documents = liste.documents }
                listeDocuments = liste
                // 23.10 (soir) : un document du lot apparu dans les récents n'est plus « en cours » ; la confirmation suit
                if suivi.maj(liste, lecture: lecture) { confirmer(suivi.confirmation(liste)) }
                compterDocuments()
                return liste.delaiRelecture(lotEnCours: envoiEnCours || suivi.enCours)
            case 401:
                documents = []
                listeDocuments = nil
                compterDocuments()
                accesDocuments = .reserve("Les documents sont réservés aux personnes connectées.")
                return .seconds(60)
            case 403:
                documents = []
                listeDocuments = nil
                compterDocuments()
                accesDocuments = .reserve(
                    String(decoding: corps.prefix(200), as: UTF8.self).nonVide ?? "Les documents vous sont fermés.")
                return .seconds(60)
            default:
                throw ErreurRelais("HTTP \(statut)")
            }
        } catch is CancellationError {
            return .seconds(60)
        } catch {
            accesDocuments = .reserve("Liste indisponible : " + Self.motif(error))
            return .seconds(30)
        }
    }

    private func chargerNotifications() async -> Duration {
        conversation?.expirerAttenteHermes()
        conversation?.livrerDifferees()
        let attend = conversation.map { !$0.attentesHermes.isEmpty || !$0.differees.isEmpty } ?? false
        let pas: Duration = attend ? .seconds(3) : .seconds(15)
        guard let (statut, corps) = try? await acces.lire("/notifications") else { return pas }
        if statut == 401 {
            if notificationsPermises { notificationsPermises = false }
            return pas
        }
        guard statut == 200, let l = try? JSONDecoder().decode(ListeNotifications.self, from: corps) else {
            return pas
        }
        if !notificationsPermises { notificationsPermises = true }
        if l.notifications != notifications { notifications = l.notifications }
        if l.nonLues != nonLues { nonLues = l.nonLues }
        // la plus ancienne attente, relue après la lecture : une déconnexion a pu tout fermer entre-temps
        if actif, reclamation == nil, let conversation, let attente = conversation.attentesHermes.first,
            let n = l.reponseHermes(depuis: attente.posee)
        {
            reclamer(n, pour: attente.numero, conversation)
        }
        return pas
    }

    /// La réponse d'Hermes à lire : réclamée au relais (la première console ou app seulement), puis passée à la
    /// conversation pour cette attente ; une autre l'a prise : rien. L'app cachée entre-temps, elle attend le retour à
    /// l'écran (rien ne se lit écran caché).
    private func reclamer(_ n: NotificationConsole, pour numero: Int, _ conversation: Conversation) {
        let corps = try? JSONEncoder().encode(["id": n.id])
        let requete = RequeteRelais(.post, "/notifications/livrer", corps: corps, type: "application/json")
        let acces = acces
        reclamation = Task { [weak self] in
            let reponse = try? await acces.envoyer(requete)
            self?.reclamation = nil
            guard let (statut, data) = reponse, statut == 200,
                let r = try? JSONDecoder().decode(ReponseLivree.self, from: data), r.ok
            else { return }
            let visible = self?.cachee == false
            conversation.recevoirDifferee(
                texte: r.message ?? n.message, chemin: r.cheminVoix, attente: numero, livrer: visible)
        }
    }

    /// Comme la console : maison muette (5xx) → redemandée toutes les 15 s ; une liste vide n'est pas redemandée.
    private func chargerLiens() async -> Duration? {
        guard let (statut, corps) = try? await acces.lire("/liens") else { return .seconds(15) }
        if statut >= 500 { return .seconds(15) }
        let l = statut == 200 ? LienSysteme.lire(corps) ?? [] : []
        if l != liens { liens = l }
        return nil
    }

    // MARK: - actions

    /// 23.10 (soir) : un fichier choisi rejoint « À envoyer » (rien ne part) ; un refus immédiat (trop lourd, type) y
    /// reste, écrit dans sa ligne. La confirmation du lot précédent disparaît.
    func ajouter(_ fichier: FichierAEnvoyer, source: SourceFichier) {
        aEnvoyer.append(fichier)
        if fichier.valable { sources[fichier.id] = source }
        confirmer(nil)
        compterDocuments()
    }

    /// « Retirer <nom> de la liste » (un toucher) : rien n'était parti.
    func retirerAEnvoyer(_ id: UUID) {
        aEnvoyer.removeAll { $0.id == id }
        sources[id] = nil
        compterDocuments()
    }

    /// 23.10 (soir) : « Envoyer à Paperless (n) » — les fichiers valables de « À envoyer », un POST chacun, avec les
    /// étiquettes et le jour du lot ; puis les lignes de ce lot (valables ou refusées) quittent « À envoyer ».
    func envoyer(etiquettes: [String], pourLe: String?) async {
        let lot = aEnvoyer
        let valables = lot.filter(\.valable)
        guard !envoiEnCours, !valables.isEmpty else { return }
        suivi.nouveau()
        confirmer(nil)
        let depot = LotDepot(pourLe: pourLe, total: valables.count, etiquettes: etiquettes)
        let sources = sources
        await deposer(lot: depot) { rang in
            let f = valables[rang]
            guard let donnees = sources[f.id]?.lire(), let type = f.type else {
                refuserLocalement(RefusLocal(nom: f.nom, motif: .illisible))
                return nil
            }
            return depot.depot(fichier: donnees, nomFichier: f.nom, type: type)
        }
        let partis = Set(lot.map(\.id))
        aEnvoyer.removeAll { partis.contains($0.id) }
        for id in partis { self.sources[id] = nil }
        compterDocuments()
    }

    /// Dépose un document (20 Mo au plus) ; la liste se relit ensuite.
    func deposer(_ depot: DepotDocument) async {
        await deposer(lot: LotDepot(pourLe: depot.pourLe, total: 1, etiquettes: depot.etiquettes)) { _ in depot }
    }

    /// 23.10 : dépose un LOT, un fichier à la fois, comme la console : chacun est préparé (lu) juste avant son envoi — un
    /// seul en mémoire —, puis envoyé et suivi (« Envoi… », puis « Rangement… » d'après sa fiche) ; `preparer` rend nil
    /// pour un fichier illisible (il l'a signalé). Refusé par le relais (400, 413, 415) ou coupé en route : une carte
    /// « Refusé » de l'app, dans « À revoir » ; le lot continue. La liste se relit après chaque fichier.
    func deposer(lot: LotDepot, preparer: @MainActor (Int) async -> DepotDocument?) async {
        guard !envoiEnCours, lot.total > 0 else { return }
        envoiEnCours = true
        erreurDepot = nil
        defer { envoiEnCours = false }
        var recus = 0
        for rang in 0..<lot.total {
            guard let depot = await preparer(rang) else { continue }
            guard depot.fichier.count <= DepotDocument.tailleMax else {
                refuserLocalement(RefusLocal(nom: depot.nomFichier, motif: .taille))
                continue
            }
            let cle = UUID()
            suivi.envoi(cle, nom: depot.nomFichier)
            etatDepot = lot.etatEnvoi(depot.nomFichier, rang: rang + 1)
            do {
                let (statut, corps) = try await acces.envoyer(depot.requete())
                // 413, 415, et 400 avec le texte du relais (23.10 : une étiquette refusée) : une carte « Refusé »
                if let refus = RefusLocal(nom: depot.nomFichier, statut: statut, corps: corps) {
                    suivi.echec(cle)
                    refuserLocalement(refus)
                    continue
                }
                guard (200..<300).contains(statut) else { throw ErreurRelais("HTTP \(statut)") }
                suivi.recu(cle, document: Self.identifiant(corps))
                recus += 1
            } catch {
                suivi.echec(cle)
                refuserLocalement(RefusLocal(nom: depot.nomFichier, motif: .envoiCoupe(Self.motif(error))))
            }
            relireDocuments()
        }
        etatDepot = LotDepot.recus(recus)
        if recus > 0 {
            aviser(recus > 1 ? "\(recus) documents reçus." : "Document reçu.", .info)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                if self?.etatDepot == LotDepot.recus(recus) { self?.etatDepot = nil }
            }
        }
        relireDocuments()
    }

    /// L'identifiant de la fiche rendue par le relais (202) ; nil s'il manque (le fichier n'est alors plus suivi).
    static func identifiant(_ corps: Data) -> String? {
        guard let objet = try? JSONSerialization.jsonObject(with: corps) as? [String: Any],
            let id = objet["id"] as? String, !id.isEmpty
        else { return nil }
        return id
    }

    /// La ligne de confirmation : posée (60 s, relancées à chaque document rangé), ou retirée.
    private func confirmer(_ c: ConfirmationRangement?) {
        finConfirmation?.cancel()
        if c != confirmation { confirmation = c }
        guard c != nil else { return }
        finConfirmation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.confirmation = nil
        }
    }

    /// 23.10 : un fichier refusé au dépôt (400, 413, 415, envoi coupé, illisible) : une carte « Refusé » de l'app dans
    /// « À revoir », et un avis.
    func refuserLocalement(_ refus: RefusLocal) {
        refusLocaux.insert(refus, at: 0)
        compterDocuments()
        aviser(refus.texte, .attention)
    }

    /// 23.10 : un toucher sur un bouton en deux temps : true s'il confirme l'action armée pour ce document ; sinon il
    /// l'arme (3,5 s, puis la carte redevient d'elle-même « Retirer » ou « Supprimer ») et rend false.
    func toucherEnDeuxTemps(_ action: String, _ document: DocumentMaison) -> Bool {
        if deuxTemps.toucher(action, id: document.id) { return true }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(DeuxTemps.delai + 0.05))
            self?.deuxTemps.expirer()
        }
        return false
    }

    /// « Retirer » sur un refus de l'appareil : la carte disparaît (rien n'a été gardé à la maison).
    func retirer(_ refus: RefusLocal) {
        refusLocaux.removeAll { $0.id == refus.id }
        compterDocuments()
    }

    /// La pastille (23.10, soir) : « À envoyer » (valables ou refusées) + « À revoir » (refusés du relais, refus au dépôt).
    private func compterDocuments() {
        let n = (listeDocuments ?? ListeDocuments(documents: [])).pastille(
            aEnvoyer: aEnvoyer.count, refusLocaux: refusLocaux.count)
        if n != pastilleDocuments { pastilleDocuments = n }
    }

    /// Un échec de dépôt (fichier illisible, trop lourd, envoi refusé) : dans la fenêtre Documents, et en avis.
    func signaler(_ message: String) {
        erreurDepot = message
        aviser(message, .attention)
    }

    /// La fenêtre Documents se ferme : l'échec d'un dépôt passé n'y reste pas (rouverte le lendemain, elle le
    /// montrait encore).
    func oublierErreurDepot() {
        erreurDepot = nil
    }

    /// L'identifiant d'un document dans un chemin : « / » échappé aussi (il ne doit jamais viser une autre route).
    static func segment(_ id: String) -> String { DocumentMaison.segment(id) }

    /// « Supprimer » (un document de banc, ou lu par un relais plus ancien) : la fiche quitte la maison.
    func supprimer(_ document: DocumentMaison) async {
        await effacer(document, fait: "Document supprimé.", echec: "Suppression impossible : ")
    }

    /// 23.10 : « Retirer » un document refusé : il quitte la maison (il n'est pas dans Paperless ; un doublon y est
    /// déjà).
    func retirer(_ document: DocumentMaison) async {
        await effacer(document, fait: "Document retiré.", echec: "Retrait impossible : ")
    }

    private func effacer(_ document: DocumentMaison, fait: String, echec: String) async {
        do {
            let (statut, _) = try await acces.envoyer(document.requeteRetirer)
            guard (200..<300).contains(statut) else { throw ErreurRelais("HTTP \(statut)") }
            erreurDepot = nil
            aviser(fait, .info)
        } catch {
            signaler(echec + Self.motif(error))
        }
        relireDocuments()
    }

    /// 23.10 : « Réessayer » un document refusé (lecture, Paperless) : le relais reprend l'étape qui a échoué.
    func reessayer(_ document: DocumentMaison) async {
        do {
            let (statut, corps) = try await acces.envoyer(document.requeteReessayer)
            // 409 : le texte du relais (« rien à réessayer », « ce document n'est pas refusé »), comme la console
            if statut == 409 {
                throw ErreurRelais(String(decoding: corps.prefix(200), as: UTF8.self).nonVide ?? "rien à réessayer")
            }
            guard (200..<300).contains(statut) else { throw ErreurRelais("HTTP \(statut)") }
            erreurDepot = nil
        } catch {
            signaler("Nouvel essai impossible : " + Self.motif(error))
        }
        relireDocuments()
    }

    /// À l'ouverture de la fenêtre : tout est marqué lu (si elle est encore ouverte une fois la liste chargée).
    func marquerLues() async {
        guard nonLues > 0 else { return }
        _ = try? await acces.envoyer(RequeteRelais(.post, "/notifications/lues"))
        relireNotifications()
    }

    func effacerNotifications() async {
        _ = try? await acces.envoyer(RequeteRelais(.post, "/notifications/effacer"))
        relireNotifications()
    }

    private static func motif(_ e: any Error) -> String {
        (e as? ErreurRelais)?.message ?? (e as NSError).localizedDescription
    }
}

extension String {
    fileprivate var nonVide: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
