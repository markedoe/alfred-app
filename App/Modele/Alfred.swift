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
    /// La roue, les jauges et la météo de la console (`/maison/console`).
    private(set) var console = ConsoleMaison()
    /// L'action en cours ou qui vient de finir, pour le HUD du réacteur (comme `actionCue` de la console).
    private(set) var action: ActionHUD?
    /// La consommation de la maison, relevée toutes les 15 s (160 points au plus, comme la console).
    private(set) var historiquePuissance: [Double] = []
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
    @ObservationIgnored private var releve: Task<Void, Never>?
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
        releve?.cancel()
        releve = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.releverPuissance()
            }
        }
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
        releve?.cancel()
        releve = nil
        await client?.arreter()
        client = nil
        conversation.client = nil
        acces?.fermer()
        acces = nil
        maison = Maison()
        structure = StructureMaison()
        console = ConsoleMaison()
        action = nil
        historiquePuissance = []
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
            maison = Self.utile(await client.maison, structure, console)
        case .structureChargee:
            structure = await client.structure
            maison = Self.utile(await client.maison, structure, console)
        case .consoleChargee:
            console = await client.console
            maison = Self.utile(await client.maison, structure, console)
            releverPuissance()
        case .entite(let id, let etat):
            guard id.hasPrefix("light.") || structure.capteurs.contains(id) || console.entites.contains(id) else {
                return
            }
            maison.appliquer(entite: id, nouvelEtat: etat)
        case .tour(let signal):
            conversation.recevoir(signal)
        case .commande(let cle, let issue):
            enCours.remove(cle)
            dernierRetour = Retour(cle: cle, issue: issue)
            terminerAction(cle: cle, issue: issue)
        }
    }

    /// Les lumières, les capteurs des pièces et tout ce que la console montre (météo, jauges).
    private static func utile(_ m: Maison, _ s: StructureMaison, _ c: ConsoleMaison) -> Maison {
        var m = m
        let entites = c.entites
        m.garder { entites.contains($0.id) || (s.vide ? $0.domaine == "light" : s.utile($0)) }
        return m
    }

    private func releverPuissance() {
        guard let id = console.puissance, let v = maison[id]?.nombre else { return }
        historiquePuissance.append(v)
        if historiquePuissance.count > 160 { historiquePuissance.removeFirst(historiquePuissance.count - 160) }
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
    /// La maison répond : on peut parler, écrire et commander.
    var estPret: Bool {
        if case .pret = liaison { return true }
        return false
    }
    var lumieresAllumees: Int { maison.lumieres.filter { $0.etat == "on" && !$0.estGroupe }.count }

    func enCours(_ cle: String) -> Bool { enCours.contains(cle) }

    // MARK: - la roue

    /// Les secteurs de la roue : ceux de la console ; sans elle (relais plus ancien), les pièces de HA.
    var secteurs: [Secteur] {
        if !console.vide {
            return console.pieces.map { p in
                Secteur(
                    id: p.lumiere, nom: p.nom, etage: p.etage, etat: maison[p.lumiere]?.etat,
                    temperature: mesure(p.temperature), humidite: mesure(p.humidite), air: mesure(p.air))
            }
        }
        return etages.flatMap { e in
            e.pieces.map { p in
                Secteur(
                    id: "piece:" + p.id, nom: p.piece.nom.uppercased(), etage: e.etage?.nom ?? "",
                    etat: p.disponible ? (p.allumee ? "on" : "off") : nil,
                    temperature: p.temperature.map { Mesure(valeur: $0.nombre, unite: "°C") },
                    humidite: p.humidite.map { Mesure(valeur: $0.nombre, unite: "%") }, air: nil)
            }
        }
    }

    private func mesure(_ id: String?) -> Mesure? {
        guard let id else { return nil }
        let e = maison[id]
        return Mesure(valeur: e?.nombre, unite: e?.attributs["unit_of_measurement"]?.texte ?? "")
    }

    /// Le résumé de la console (« 0 groupe allumé · 14/14 groupes disponibles · … »).
    var resume: String {
        if !console.vide { return console.resume(maison) }
        let n = lumieresAllumees
        return n == 0 ? "Toutes les lumières sont éteintes." : n == 1 ? "1 lumière allumée." : "\(n) lumières allumées."
    }

    /// Allumer ou éteindre un secteur ; le HUD suit la commande jusqu'à l'état confirmé par la maison.
    func basculer(_ s: Secteur) {
        guard s.disponible, !enCours.contains(s.id) else { return }
        action = ActionHUD(
            secteur: s.id, libelle: s.allumee ? "EXTINCTION" : "ALLUMAGE", etat: .attente, voulu: !s.allumee)
        if s.id.hasPrefix("piece:") {
            commander(s.id) { await $0.basculer(piece: String(s.id.dropFirst(6))) }
        } else {
            commander(s.id) { await $0.basculer(lumiere: s.id) }
        }
    }

    private func terminerAction(cle: String, issue: IssueCommande) {
        guard var a = action, a.secteur == cle, a.fin == nil else { return }
        switch issue {
        case .confirmee:
            a.etat = .confirmee
            a.libelle = a.voulu ? "ALLUMAGE CONFIRMÉ" : "EXTINCTION CONFIRMÉE"
        case .refusee:
            a.etat = .echec
            a.libelle = "COMMANDE REFUSÉE"
        case .sansConfirmation:
            a.etat = .echec
            a.libelle = "CONFIRMATION NON REÇUE"
        }
        a.fin = .now
        action = a
    }

    private func commander(_ cle: String, _ action: @escaping @Sendable (ClientRelais) async -> Void) {
        guard let client, !enCours.contains(cle) else { return }
        enCours.insert(cle)
        Task { await action(client) }
    }
}

/// Un secteur de la roue : un groupe de lumières de la console (ou une pièce de HA), son état, ses mesures.
struct Secteur: Identifiable, Equatable, Sendable {
    /// La clé de commande : l'entité de lumière, ou « piece:<id> ».
    let id: String
    /// En capitales, comme sur la roue de la console.
    let nom: String
    let etage: String
    /// `on`, `off`, ou autre chose (indisponible : on ne devine pas).
    let etat: String?
    let temperature: Mesure?
    let humidite: Mesure?
    let air: Mesure?

    var allumee: Bool { etat == "on" }
    var disponible: Bool { etat == "on" || etat == "off" }
    /// « Salon » pour VoiceOver et les phrases (« Salon allumé »).
    var nomCourant: String { String(nom.prefix(1)) + nom.dropFirst().lowercased() }
}

/// Une mesure et son unité (celle que donne Home Assistant).
struct Mesure: Equatable, Sendable {
    let valeur: Double?
    let unite: String
}

/// Le HUD d'une action (la console : `actionCue`) : en attente, confirmée par l'état reçu, ou en échec.
struct ActionHUD: Equatable, Sendable {
    enum Etat: Equatable, Sendable { case attente, confirmee, echec }
    let secteur: String
    var libelle: String
    var etat: Etat
    /// Allumer (true) ou éteindre.
    let voulu: Bool
    let debut = Date.now
    var fin: Date?

    /// Le HUD s'efface 2,2 s après la fin.
    func visible(a date: Date) -> Bool { fin.map { date.timeIntervalSince($0) < 2.2 } ?? true }
}
