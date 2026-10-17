import AlfredKit
import Foundation
import OSLog
import Observation

/// L'état de l'app : où l'on en est (configuration, accueil, connecté), la maison, les commandes, la conversation.
@Observable @MainActor
final class Alfred {
    enum Etape: Equatable, Sendable {
        /// Aucune adresse de relais (fabrication sans configuration de la maison).
        case configuration
        /// Pas encore connecté.
        case accueil
        case connecte
    }

    /// L'issue d'une commande de la maison, pour l'interface (retour haptique, avis).
    struct Retour: Equatable, Sendable {
        let id = UUID()
        let cle: String
        let issue: IssueCommande
    }

    private(set) var etape: Etape
    private(set) var configuration: ConfigurationMaison?
    /// « connexion » au départ : rien n'a encore échoué (« injoignable » s'affichait au lancement).
    private(set) var liaison: ClientRelais.Etat = .connexion
    /// Ce que l'app garde de la maison : les lumières et les capteurs des pièces.
    private(set) var maison = Maison()
    private(set) var structure = StructureMaison()
    private(set) var moi: Moi?
    private(set) var enCours: Set<String> = []
    private(set) var dernierRetour: Retour?
    /// Raison de la dernière déconnexion forcée (session expirée, refusée par la maison).
    private(set) var motifAccueil: String?
    let conversation: Conversation
    /// La maison de démonstration (tests d'interface, ou choisie à l'accueil pour découvrir l'app hors de la maison).
    private(set) var demo: Bool

    @ObservationIgnored private var client: ClientRelais?
    @ObservationIgnored private var acces: AccesURLSession?
    @ObservationIgnored private var abonnement: Task<Void, Never>?
    @ObservationIgnored private let reglages: UserDefaults
    @ObservationIgnored private let journal = Logger(subsystem: "io.github.markedoe.alfred", category: "app")

    /// L'app sur l'appareil : configuration embarquée ou saisie, session dans le trousseau.
    static func surAppareil() -> Alfred {
        if ProcessInfo.processInfo.arguments.contains("-demo") { return demonstration() }
        return Alfred(configuration: ConfigurationMaison.actuelle(), reglages: .standard)
    }

    /// La démo : une maison simulée, sans réseau ni micro (tests d'interface, aperçus, captures).
    static func demonstration() -> Alfred {
        let a = Alfred(demo: true)
        a.demarrer(acces: AccesDemo(), voix: nil)
        return a
    }

    private init(configuration: ConfigurationMaison?, reglages: UserDefaults) {
        self.configuration = configuration
        self.reglages = reglages
        demo = false
        conversation = Conversation(voix: VoixMuette(), reglages: reglages)
        etape = configuration == nil ? .configuration : .accueil
        if let configuration, let valeur = Trousseau.lire(compte: configuration.relais.hote) {
            ouvrir(configuration, session: SessionRelais(valeur: valeur))
        }
    }

    private init(demo: Bool) {
        self.demo = demo
        reglages = UserDefaults(suiteName: "demo") ?? .standard
        configuration = nil
        conversation = Conversation(voix: VoixMuette(), reglages: reglages)
        etape = .connecte
    }

    // MARK: - configuration et connexion

    /// Adresse saisie au premier lancement (fabrication sans configuration). false si elle n'est pas valable.
    func configurer(adresse: String) -> Bool {
        guard let relais = Relais(adresse: adresse) else { return false }
        reglages.set(relais.hote, forKey: ConfigurationMaison.cleAdresseSaisie)
        configuration = ConfigurationMaison(relais: relais, autorite: nil)
        etape = .accueil
        return true
    }

    /// Fin du parcours de connexion : la session part dans le trousseau, et l'app rejoint la maison.
    func connexionReussie(_ session: SessionRelais) {
        guard let configuration else { return }
        do {
            try Trousseau.ecrire(session.valeur, compte: configuration.relais.hote)
        } catch {
            journal.error("trousseau : écriture refusée")
        }
        motifAccueil = nil
        ouvrir(configuration, session: session)
    }

    private func ouvrir(_ configuration: ConfigurationMaison, session: SessionRelais) {
        let acces = AccesURLSession(configuration: configuration, session: session)
        self.acces = acces
        let voix = VoixSysteme(acces: acces)
        etape = .connecte
        demarrer(acces: acces, voix: voix)
    }

    private func demarrer(acces: any AccesRelais, voix: VoixSysteme?) {
        let client = ClientRelais(acces: acces)
        self.client = client
        liaison = .connexion
        if let voix { conversation.remplacerVoix(voix) }
        conversation.client = client
        abonnement?.cancel()
        abonnement = Task { [weak self] in
            await client.demarrer()
            for await n in client.nouvelles {
                guard let self else { return }
                await self.traiter(n, client: client, voix: voix)
            }
        }
    }

    /// La démonstration, choisie à l'accueil : une maison simulée, sans réseau ni micro. Rien n'est envoyé ni gardé.
    func essayerDemo() {
        guard !demo, client == nil else { return }
        demo = true
        motifAccueil = nil
        etape = .connecte
        demarrer(acces: AccesDemo(), voix: nil)
    }

    /// Quitter la démonstration : retour à l'accueil (ou à la configuration).
    func quitterDemo() async {
        guard demo else { return }
        await conversation.nouvelle()
        await fermer()
        demo = false
        etape = configuration == nil ? .configuration : .accueil
    }

    /// Se déconnecter : le jeton est supprimé dans HA (route du relais), la session quitte le trousseau.
    func seDeconnecter() async {
        await conversation.nouvelle()
        if let acces { _ = try? await acces.lire("/deconnexion") }
        await fermer()
        if let configuration { Trousseau.effacer(compte: configuration.relais.hote) }
        etape = configuration == nil ? .configuration : .accueil
    }

    private func fermer() async {
        abonnement?.cancel()
        abonnement = nil
        await client?.arreter()
        client = nil
        conversation.client = nil
        acces?.fermer()
        acces = nil
        maison = Maison()
        structure = StructureMaison()
        moi = nil
        enCours = []
        liaison = .deconnecte
    }

    /// L'app passe en arrière-plan : la conversation se ferme (le micro ne reste jamais ouvert écran caché).
    func arrierePlan() async {
        await conversation.terminer()
    }

    // MARK: - nouvelles de la maison

    private func traiter(_ n: ClientRelais.Nouvelle, client: ClientRelais, voix: VoixSysteme?) async {
        switch n {
        case .etat(let e):
            liaison = e
            if case .pret = e { await verifierSession(voix: voix) }
        case .maisonChargee:
            maison = Self.utile(await client.maison, structure)
        case .structureChargee:
            structure = await client.structure
            maison = Self.utile(await client.maison, structure)
        case .entite(let id, let etat):
            guard id.hasPrefix("light.") || structure.capteurs.contains(id) else { return }
            maison.appliquer(entite: id, nouvelEtat: etat)
        case .tour(let signal):
            conversation.recevoir(signal)
        case .commande(let cle, let issue):
            enCours.remove(cle)
            dernierRetour = Retour(cle: cle, issue: issue)
        }
    }

    /// Les lumières et les capteurs des pièces (sans structure : les lumières seules).
    private static func utile(_ m: Maison, _ s: StructureMaison) -> Maison {
        var m = m
        m.garder { s.vide ? $0.domaine == "light" : s.utile($0) }
        return m
    }

    /// Le relais accepte une session révoquée en la traitant comme invitée : on vérifie `/moi` à chaque connexion.
    private func verifierSession(voix: VoixSysteme?) async {
        guard let acces else {
            if demo { moi = Moi(connecte: true, nom: "Démo", userId: nil, titre: "Monsieur") }
            return
        }
        guard let (statut, corps) = try? await acces.lire("/moi"), statut == 200,
            let m = try? JSONDecoder().decode(Moi.self, from: corps)
        else { return }
        guard m.connecte else {
            motifAccueil = "Votre connexion à la maison a expiré. Reconnectez-vous."
            await fermer()
            if let configuration { Trousseau.effacer(compte: configuration.relais.hote) }
            etape = .accueil
            return
        }
        let titreChange = moi?.titre != m.titre
        moi = m
        if titreChange { await voix?.chargerClips(titre: m.titre) }
    }

    // MARK: - commandes

    var etages: [VueEtage] { maison.vue(structure) }
    var lumieresAllumees: Int { maison.lumieres.filter { $0.etat == "on" && !$0.estGroupe }.count }

    func basculer(piece: VuePiece) {
        commander("piece:" + piece.id) { await $0.basculer(piece: piece.id) }
    }

    func basculer(lumiere: EtatEntite) {
        commander(lumiere.id) { await $0.basculer(lumiere: lumiere.id) }
    }

    func regler(lumiere: EtatEntite, pourcent: Int) {
        commander(lumiere.id) { await $0.regler(lumiere: lumiere.id, pourcent: pourcent) }
    }

    func enCours(_ cle: String) -> Bool { enCours.contains(cle) }

    private func commander(_ cle: String, _ action: @escaping @Sendable (ClientRelais) async -> Void) {
        guard let client, !enCours.contains(cle) else { return }
        enCours.insert(cle)
        Task { await action(client) }
    }
}
