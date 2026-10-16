import Foundation

/// Une trame de la WebSocket : texte (JSON) ou binaire (audio).
public enum Trame: Sendable, Equatable {
    case texte(String)
    case binaire(Data)
}

/// Une liaison ouverte avec le relais. `recevoir` lève une erreur quand elle se ferme.
public protocol Liaison: Sendable {
    func envoyer(_ trame: Trame) async throws
    func recevoir() async throws -> Trame
    func fermer() async
}

/// L'accès au relais : la WebSocket et les lectures HTTP (URLSession à l'autorité épinglée sur les appareils d'Apple,
/// avec le cookie de la personne ; un accès factice dans les tests).
public protocol AccesRelais: Sendable {
    func ouvrir() async throws -> any Liaison
    /// GET d'un chemin du relais : statut HTTP et corps.
    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data)
}

public struct ErreurRelais: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }

    public static let delai = ErreurRelais("Délai de réponse dépassé")
    public static let lienCoupe = ErreurRelais("lien coupé")
}

/// Le client du relais : la liaison, la maison, le tour de conversation et les commandes de lumière.
///
/// Comme la console :
/// - le relais s'authentifie à notre place : on attend `ready`, on n'envoie rien qui ressemble à une authentification ;
/// - une demande attend sa réponse 15 s au plus ;
/// - à la coupure, tout ce qui attendait échoue, et on se reconnecte (1 s, puis le double, 15 s au plus) ;
/// - les trames partent dans l'ordre où elles ont été produites (une seule file d'envoi).
public actor ClientRelais {
    public enum Etat: Sendable, Equatable {
        case deconnecte
        case connexion
        case synchronisation
        case pret(versionHA: String?)
        case fatal(String)
    }

    public enum Nouvelle: Sendable, Equatable {
        case etat(Etat)
        case maisonChargee
        /// Un état a changé (nil : entité supprimée).
        case entite(String, EtatEntite?)
        case tour(AutomateTour.Signal)
        case structureChargee
        case commande(cle: String, IssueCommande)
    }

    public struct Reglages: Sendable {
        public var delaiDemande: Duration = .seconds(15)
        public var reconnexionInitiale: Duration = .seconds(1)
        public var reconnexionMaximale: Duration = .seconds(15)
        public var delaiConfirmation: Duration = Commande.delaiConfirmation
        /// Remplace le délai de 90 s d'un tour (tests seulement).
        public var delaiTour: Duration?
        public init() {}
    }

    private let acces: any AccesRelais
    private let reglages: Reglages

    public private(set) var etat: Etat = .deconnecte
    public private(set) var maison = Maison()
    /// Étages et pièces ; vide si le relais ne permet pas la lecture des registres (la maison reste en liste).
    public private(set) var structure = StructureMaison()
    /// Le pipeline préféré de HA (« Alfred ») ; nil = celui de HA par défaut.
    public private(set) var pipelinePrefere: String?
    public private(set) var tour = AutomateTour()

    private var sortie: AsyncStream<Trame>.Continuation?
    private var liaison: (any Liaison)?
    private var prochainId = 1
    private var attentes: [Int: CheckedContinuation<MessageEntrant.Resultat, Error>] = [:]
    private var minuterieTour: Task<Void, Never>?
    private var commandes: [String: (commande: Commande, minuterie: Task<Void, Never>)] = [:]
    private var boucle: Task<Void, Never>?

    public nonisolated let nouvelles: AsyncStream<Nouvelle>
    private let annonce: AsyncStream<Nouvelle>.Continuation

    public init(acces: any AccesRelais, reglages: Reglages = Reglages()) {
        self.acces = acces
        self.reglages = reglages
        (nouvelles, annonce) = AsyncStream.makeStream(of: Nouvelle.self, bufferingPolicy: .unbounded)
    }

    // MARK: - liaison

    public func demarrer() {
        guard boucle == nil else { return }
        boucle = Task { await self.maintenir() }
    }

    public func arreter() async {
        boucle?.cancel()
        boucle = nil
        await liaison?.fermer()
    }

    private func maintenir() async {
        var attente = reglages.reconnexionInitiale
        while !Task.isCancelled {
            changer(.connexion)
            do {
                let l = try await acces.ouvrir()
                let (flux, cont) = AsyncStream.makeStream(of: Trame.self, bufferingPolicy: .unbounded)
                liaison = l
                sortie = cont
                let ecrivain = Task {
                    for await t in flux {
                        do { try await l.envoyer(t) } catch {
                            await l.fermer()
                            break
                        }
                    }
                }
                defer { ecrivain.cancel() }
                while !Task.isCancelled {
                    let t = try await l.recevoir()
                    if case .texte(let texte) = t, let m = MessageEntrant.lire(texte) {
                        if case .pret = m { attente = reglages.reconnexionInitiale }
                        traiter(m)
                    }
                }
            } catch {}
            coupure()
            if Task.isCancelled { break }
            try? await Task.sleep(for: attente)
            attente = min(attente * 2, reglages.reconnexionMaximale)
        }
        coupure()
    }

    private func coupure() {
        sortie?.finish()
        sortie = nil
        liaison = nil
        for (_, c) in attentes { c.resume(throwing: ErreurRelais.lienCoupe) }
        attentes = [:]
        executer(tour.lienCoupe())
        for (cle, c) in commandes {
            c.minuterie.cancel()
            annonce.yield(.commande(cle: cle, .refusee("Liaison interrompue.")))
        }
        commandes = [:]
        maison = Maison()
        if case .fatal = etat {} else { changer(.deconnecte) }
    }

    private func changer(_ e: Etat) {
        guard e != etat else { return }
        etat = e
        annonce.yield(.etat(e))
    }

    // MARK: - messages reçus

    private func traiter(_ m: MessageEntrant) {
        switch m {
        case .pret(let v):
            changer(.synchronisation)
            Task { await self.synchroniser(versionHA: v) }
        case .fatal(let message):
            changer(.fatal(message))
        case .resultat(let r):
            if let id = r.id, let c = attentes.removeValue(forKey: id) { c.resume(returning: r) }
            executer(tour.recevoir(m))
        case .evenement(_, .etatChange(let id, let nouvel)):
            let ancien = maison.appliquer(entite: id, nouvelEtat: nouvel)
            guard ancien != nouvel else { break }
            annonce.yield(.entite(id, nouvel))
            for (cle, c) in commandes where c.commande.confirmee(maison: maison, structure: structure) {
                c.minuterie.cancel()
                commandes[cle] = nil
                annonce.yield(.commande(cle: cle, .confirmee))
            }
        case .evenement(_, .pipeline):
            executer(tour.recevoir(m))
        case .evenement(_, .autre), .autre:
            break
        }
    }

    private func synchroniser(versionHA: String?) async {
        do {
            let r = try await demander(["type": "get_states"])
            guard r.succes else { throw ErreurRelais("Synchronisation de la maison impossible") }
            maison.charger(r.valeur)
            annonce.yield(.maisonChargee)
            envoyer(["type": "subscribe_events", "event_type": "state_changed"])
            structure = await lireStructure()
            annonce.yield(.structureChargee)
            // prêt seulement quand le pipeline est connu : un tour lancé avant partirait sur un autre pipeline
            let p = try await demander(["type": "assist_pipeline/pipeline/list"])
            pipelinePrefere = p.succes ? p.valeur?["preferred_pipeline"]?.texte : nil
            changer(.pret(versionHA: versionHA))
        } catch {
            changer(.fatal((error as? ErreurRelais)?.message ?? "Synchronisation de la maison impossible"))
            await liaison?.fermer()
        }
    }

    /// `GET /maison/structure` ; un relais sans cette route (ou d'un autre contrat) laisse la structure vide :
    /// la maison s'affiche alors en liste simple.
    private func lireStructure() async -> StructureMaison {
        guard let (statut, corps) = try? await acces.lire("/maison/structure"), statut == 200,
            let v = try? JSONDecoder().decode(ValeurJSON.self, from: corps),
            let s = StructureMaison.lire(v)
        else { return StructureMaison() }
        return s
    }

    // MARK: - envoi

    private func nouvelId() -> Int {
        defer { prochainId += 1 }
        return prochainId
    }

    @discardableResult
    private func envoyer(_ m: ValeurJSON) -> Int? {
        guard let sortie, case .objet(var o) = m else { return nil }
        let id = nouvelId()
        o["id"] = .nombre(Double(id))
        sortie.yield(.texte(ValeurJSON.objet(o).enTexte()))
        return id
    }

    /// Envoie une commande et attend son `result` (15 s au plus).
    public func demander(_ m: ValeurJSON) async throws -> MessageEntrant.Resultat {
        guard sortie != nil else { throw ErreurRelais.lienCoupe }
        let delai = reglages.delaiDemande
        return try await withCheckedThrowingContinuation { c in
            guard let id = envoyer(m) else {
                c.resume(throwing: ErreurRelais.lienCoupe)
                return
            }
            attentes[id] = c
            Task { [weak self] in
                try? await Task.sleep(for: delai)
                await self?.expirer(id)
            }
        }
    }

    private func expirer(_ id: Int) {
        attentes.removeValue(forKey: id)?.resume(throwing: ErreurRelais.delai)
    }

    private func executer(_ effets: [AutomateTour.Effet]) {
        for e in effets {
            switch e {
            case .envoyer(let t): sortie?.yield(.texte(t))
            case .envoyerAudio(let d): sortie?.yield(.binaire(d))
            case .armerDelai(let d):
                minuterieTour?.cancel()
                let duree = reglages.delaiTour ?? d
                minuterieTour = Task { [weak self] in
                    try? await Task.sleep(for: duree)
                    if !Task.isCancelled { await self?.tourExpire() }
                }
            case .annulerDelai:
                minuterieTour?.cancel()
                minuterieTour = nil
            case .signal(let s):
                annonce.yield(.tour(s))
            }
        }
    }

    private func tourExpire() { executer(tour.delaiDepasse()) }

    // MARK: - conversation

    /// Commence un tour à la voix. false si la maison n'est pas jointe ou si un tour est en cours.
    public func parler(conversation: String? = nil, amorce: [Data] = []) -> Bool {
        commencer(.voix, conversation: conversation, amorce: amorce)
    }

    /// Commence un tour écrit.
    public func ecrire(_ texte: String, conversation: String? = nil) -> Bool {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return commencer(.texte(t), conversation: conversation, amorce: [])
    }

    private func commencer(_ mode: AutomateTour.Mode, conversation: String?, amorce: [Data]) -> Bool {
        guard case .pret = etat, sortie != nil, !tour.occupe else { return false }
        let id = nouvelId()
        guard
            let effets = tour.commencer(
                id: id, mode: mode, pipeline: pipelinePrefere, conversationId: conversation,
                amorce: amorce)
        else { return false }
        executer(effets)
        return true
    }

    /// Audio PCM 16 bits à 16 kHz. À appeler depuis UNE seule tâche, dans l'ordre de la capture.
    public func audio(_ pcm: Data) { executer(tour.audio(pcm)) }

    public func finParole() { executer(tour.finParole()) }

    // MARK: - maison

    /// Allume ou éteint une lumière.
    public func basculer(lumiere id: String) async {
        guard let e = maison[id], let c = CommandeLumiere(basculer: e) else {
            annonce.yield(.commande(cle: id, .refusee("État de la lumière indisponible.")))
            return
        }
        await executer(.lumiere(c))
    }

    /// Allume ou éteint toute une pièce (éteinte si au moins une lumière est allumée).
    public func basculer(piece id: String) async {
        guard let vue = maison.vue(structure).flatMap(\.pieces).first(where: { $0.id == id }), vue.disponible else {
            annonce.yield(.commande(cle: "piece:" + id, .refusee("État de la pièce indisponible.")))
            return
        }
        await executer(.piece(CommandePiece(vue)))
    }

    /// Règle la luminosité d'une lumière (1-100 %).
    public func regler(lumiere id: String, pourcent: Int) async {
        await executer(.luminosite(CommandeLuminosite(entite: id, pourcent: pourcent)))
    }

    /// Envoie une commande ; l'issue arrive dans `nouvelles` (confirmée par l'état reçu, 8 s au plus).
    /// Une commande déjà en cours pour la même lumière ou pièce est ignorée.
    public func executer(_ c: Commande) async {
        let cle = c.cle
        guard commandes[cle] == nil else { return }
        guard case .pret = etat else {
            annonce.yield(.commande(cle: cle, .refusee("Le lien avec la maison est coupé — reconnexion en cours.")))
            return
        }
        let delai = reglages.delaiConfirmation
        let minuterie = Task { [weak self] in
            try? await Task.sleep(for: delai)
            if !Task.isCancelled { await self?.abandonner(cle, .sansConfirmation) }
        }
        commandes[cle] = (c, minuterie)
        do {
            let r = try await demander(c.message)
            if !r.succes { abandonner(cle, .refusee(r.erreur?.message ?? "Commande refusée")) }
        } catch {
            abandonner(cle, .refusee((error as? ErreurRelais)?.message ?? "Commande refusée"))
        }
    }

    public func commandeEnCours(_ cle: String) -> Bool { commandes[cle] != nil }

    private func abandonner(_ cle: String, _ issue: IssueCommande) {
        guard let c = commandes.removeValue(forKey: cle) else { return }
        c.minuterie.cancel()
        annonce.yield(.commande(cle: cle, issue))
    }
}
