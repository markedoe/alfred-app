import Foundation

/// La page « Connecteurs » (28.10) : tout ce à quoi Alfred est relié, par groupe, avec l'état du moment lu dans Uptime
/// Kuma par le relais (`GET /connecteurs`). Les textes viennent du relais, au mot près de la console ; ici, une lecture
/// tolérante : un champ absent ou d'un autre type donne une valeur vide, une carte sans identifiant, sans nom ou sans
/// statut est ignorée (jamais toute la liste), un groupe sans carte est retiré.
public struct ListeConnecteurs: Sendable, Equatable, Decodable {
    public let groupes: [GroupeConnecteurs]
    /// Le bandeau « PC éteint » (`veille.texte`) ; nil quand rien n'est en veille.
    public let veille: String?
    /// La page d'état d'Uptime Kuma (historique) : http(s) seulement.
    public let historique: URL?

    public init(groupes: [GroupeConnecteurs], veille: String? = nil, historique: URL? = nil) {
        self.groupes = groupes
        self.veille = veille
        self.historique = historique
    }

    /// Toutes les cartes, dans l'ordre des groupes.
    public var tous: [Connecteur] { groupes.flatMap(\.connecteurs) }

    /// La réponse du relais ; nil si ce n'est pas un objet avec une liste `groupes` (erreur, autre route).
    public static func lire(_ corps: Data) -> ListeConnecteurs? {
        try? JSONDecoder().decode(ListeConnecteurs.self, from: corps)
    }

    public init(from decoder: any Decoder) throws {
        let json = try ValeurJSON(from: decoder)
        guard let groupes = json["groupes"]?.liste else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "pas de groupes"))
        }
        self.groupes = groupes.compactMap(GroupeConnecteurs.init(json:))
        veille = Connecteur.texte(json["veille"]?["texte"])
        historique = Connecteur.lien(json["historique"])
    }
}

/// Un groupe de cartes (« Maison », « Voix et cerveau »…).
public struct GroupeConnecteurs: Sendable, Equatable, Decodable, Identifiable {
    public let nom: String
    public let connecteurs: [Connecteur]
    public var id: String { nom }

    public init(nom: String, connecteurs: [Connecteur]) {
        self.nom = nom
        self.connecteurs = connecteurs
    }

    public init(from decoder: any Decoder) throws {
        guard let groupe = Self(json: try ValeurJSON(from: decoder)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "groupe vide"))
        }
        self = groupe
    }

    /// nil sans aucune carte lisible.
    init?(json: ValeurJSON) {
        let cartes = (json["connecteurs"]?.liste ?? []).compactMap(Connecteur.init(json:))
        guard !cartes.isEmpty else { return nil }
        self.init(nom: Connecteur.texte(json["nom"]) ?? "", connecteurs: cartes)
    }
}

/// Une carte : un système relié à Alfred, son logo, où il tourne, ce qu'Alfred en fait, son état et sa fiche.
public struct Connecteur: Sendable, Equatable, Decodable, Identifiable {
    /// Le statut de la carte ou d'un service ; une valeur inconnue (un relais plus récent) : `.inconnu`.
    public enum Statut: String, Sendable, Equatable, Decodable {
        case ok
        case attente
        case panne
        /// Le PC du bureau est arrêté : en veille, c'est normal.
        case eteint
        /// Pas encore mesuré.
        case inconnu
        /// Rien à surveiller : utilisé à la demande (Claude).
        case demande

        public init(from decoder: any Decoder) throws {
            let brut = try? decoder.singleValueContainer().decode(String.self)
            self = brut.flatMap(Self.init(rawValue:)) ?? .inconnu
        }
    }

    /// Un logo de produit (Simple Icons, plein) ou un pictogramme au trait d'Alfred.
    public enum Forme: String, Sendable, Equatable {
        case marque
        case trait
    }

    /// Le dessin de la carte, viewBox 0 0 24 24 : `trace` est nil si `d` est vide ou illisible.
    public struct Icone: Sendable, Equatable {
        public let forme: Forme
        public let d: String
        public let trace: TraceSVG?

        public init(forme: Forme, d: String) {
            self.forme = forme
            self.d = d
            trace = TraceSVG(d)
        }
    }

    /// Un service d'Uptime Kuma rattaché à la carte.
    public struct Service: Sendable, Equatable, Identifiable {
        public let nom: String
        public let statut: Statut
        public let mot: String
        /// L'heure du dernier changement (Uptime Kuma, sans fuseau = UTC) ; lue par `dateDepuis`.
        public let depuis: String?
        public let message: String?
        public var id: String { nom }
        public var dateDepuis: Date? { EtatServices.date(depuis) }

        public init(nom: String, statut: Statut, mot: String, depuis: String? = nil, message: String? = nil) {
            self.nom = nom
            self.statut = statut
            self.mot = mot
            self.depuis = depuis
            self.message = message
        }
    }

    /// L'état de la carte : le pire de ses services (panne > attente > éteint > en service > pas encore mesuré).
    public struct Etat: Sendable, Equatable {
        public let statut: Statut
        /// Le mot de la console (« En service », « En veille · PC éteint »…).
        public let mot: String
        public let depuis: String?
        public let services: [Service]
        public var dateDepuis: Date? { EtatServices.date(depuis) }

        public init(statut: Statut, mot: String, depuis: String? = nil, services: [Service] = []) {
            self.statut = statut
            self.mot = mot
            self.depuis = depuis
            self.services = services
        }
    }

    /// Ce que la fiche détaillée explique, et des phrases à essayer.
    public struct Fiche: Sendable, Equatable {
        public let fait: String
        public let jamais: String
        public let donnees: String
        public let acces: String
        public let essayer: [String]

        public init(
            fait: String = "", jamais: String = "", donnees: String = "", acces: String = "", essayer: [String] = []
        ) {
            self.fait = fait
            self.jamais = jamais
            self.donnees = donnees
            self.acces = acces
            self.essayer = essayer
        }
    }

    public let id: String
    public let nom: String
    /// Une ligne sous le nom.
    public let phrase: String
    public let icone: Icone
    /// Sur Internet (`lieu` : « cloud ») plutôt qu'à la maison.
    public let nuage: Bool
    /// « À la maison », « Internet ».
    public let lieuMot: String
    /// Ce qu'Alfred en fait : « Agit », « Lit et range »…
    public let modeMot: String
    public let etat: Etat
    /// Le système lui-même, selon le compte : http(s) seulement, nil pour un invité ou sans lien.
    public let lien: URL?
    public let fiche: Fiche

    public init(
        id: String, nom: String, phrase: String = "", icone: Icone = Icone(forme: .trait, d: ""), nuage: Bool = false,
        lieuMot: String = "", modeMot: String = "", etat: Etat, lien: URL? = nil, fiche: Fiche = Fiche()
    ) {
        self.id = id
        self.nom = nom
        self.phrase = phrase
        self.icone = icone
        self.nuage = nuage
        self.lieuMot = lieuMot
        self.modeMot = modeMot
        self.etat = etat
        self.lien = lien
        self.fiche = fiche
    }

    public init(from decoder: any Decoder) throws {
        guard let carte = Self(json: try ValeurJSON(from: decoder)) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "carte sans identifiant, nom ou statut"))
        }
        self = carte
    }

    /// nil sans identifiant, sans nom ou sans statut ; tout le reste a une valeur vide par défaut.
    init?(json: ValeurJSON) {
        guard let id = Self.texte(json["id"]), let nom = Self.texte(json["nom"]),
            let etat = json["etat"], let statut = etat["statut"], !statut.estNul
        else { return nil }
        let services: [Service] = (etat["services"]?.liste ?? []).compactMap { s in
            guard let nom = Self.texte(s["nom"]) else { return nil }
            return Service(
                nom: nom, statut: Self.statut(s["statut"]), mot: Self.texte(s["mot"]) ?? "",
                depuis: Self.texte(s["depuis"]), message: Self.texte(s["message"]))
        }
        let icone = json["icone"]
        let fiche = json["fiche"]
        self.init(
            id: id, nom: nom, phrase: Self.texte(json["phrase"]) ?? "",
            icone: Icone(
                forme: Self.texte(icone?["forme"]).flatMap(Forme.init(rawValue:)) ?? .trait,
                d: Self.texte(icone?["d"]) ?? ""),
            nuage: json["lieu"]?.texte == "cloud", lieuMot: Self.texte(json["lieu_mot"]) ?? "",
            modeMot: Self.texte(json["mode_mot"]) ?? "",
            etat: Etat(
                statut: Self.statut(statut), mot: Self.texte(etat["mot"]) ?? "", depuis: Self.texte(etat["depuis"]),
                services: services),
            lien: Self.lien(json["lien"]),
            fiche: Fiche(
                fait: Self.texte(fiche?["fait"]) ?? "", jamais: Self.texte(fiche?["jamais"]) ?? "",
                donnees: Self.texte(fiche?["donnees"]) ?? "", acces: Self.texte(fiche?["acces"]) ?? "",
                essayer: DocumentMaison.textes(fiche?["essayer"])))
    }

    /// Un texte non vide, sinon nil.
    static func texte(_ v: ValeurJSON?) -> String? {
        guard let t = v?.texte, !t.isEmpty else { return nil }
        return t
    }

    static func statut(_ v: ValeurJSON?) -> Statut { v?.texte.flatMap(Statut.init(rawValue:)) ?? .inconnu }

    /// Un lien http(s) seulement (rien d'autre ne s'ouvre d'ici, comme les liens des systèmes).
    static func lien(_ v: ValeurJSON?) -> URL? { DocumentMaison.web(v?.texte.flatMap(URL.init(string:))) }
}
