import Foundation

/// Les annexes de la console, autour de la conversation : documents, notifications, liens vers les autres systèmes et
/// état des services. Routes du relais (`docs/contrat-relais.md`), au mot près de ce que la console en montre.

/// Une requête au relais qui n'est pas une lecture : dépôt d'un document, notifications lues ou effacées, suppression.
public struct RequeteRelais: Sendable, Equatable {
    public enum Methode: String, Sendable {
        case post = "POST"
        case delete = "DELETE"
    }

    public let methode: Methode
    public let chemin: String
    public let corps: Data?
    /// Le type du corps (`Content-Type`) ; nil sans corps.
    public let type: String?

    public init(_ methode: Methode, _ chemin: String, corps: Data? = nil, type: String? = nil) {
        self.methode = methode
        self.chemin = chemin
        self.corps = corps
        self.type = type
    }
}

// MARK: - notifications

/// Une notification : la copie de celles des téléphones de la personne connectée, ou une réponse d'Hermes annoncée
/// (`GET /notifications`).
public struct NotificationConsole: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let titre: String?
    public let message: String
    /// Heure de réception (secondes depuis 1970).
    public let t: Double
    public let lu: Bool

    public init(id: String, titre: String?, message: String, t: Double, lu: Bool) {
        self.id = id
        self.titre = titre
        self.message = message
        self.t = t
        self.lu = lu
    }

    public var date: Date { Date(timeIntervalSince1970: t) }
}

public struct ListeNotifications: Sendable, Equatable, Decodable {
    public let notifications: [NotificationConsole]
    public let nonLues: Int

    public init(notifications: [NotificationConsole], nonLues: Int) {
        self.notifications = notifications
        self.nonLues = nonLues
    }

    enum CodingKeys: String, CodingKey {
        case notifications
        case nonLues = "non_lues"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try c.decodeIfPresent([NotificationConsole].self, forKey: .notifications) ?? []
        nonLues = try c.decodeIfPresent(Int.self, forKey: .nonLues) ?? 0
    }
}

// MARK: - documents

/// Un document déposé à la maison (`GET /docs`) : sa fiche, jamais son texte.
public struct DocumentMaison: Sendable, Equatable, Identifiable, Decodable {
    public enum Etat: Sendable, Equatable {
        case pret, enCours, erreur
    }

    public let id: String
    public let nom: String
    /// « pret », « en cours » ou « erreur ».
    public let etatBrut: String
    public let resume: String?
    public let erreur: String?
    /// ISO 8601, avec le fuseau de la maison.
    public let deposeLe: String?
    /// AAAA-MM-JJ, le jour que le document concerne.
    public let pourLe: String?
    /// Archivé dans Paperless.
    public let paperless: Bool
    /// Un passage suspect (adressé à un assistant, ou qui réclame un paiement) ; nil sinon.
    public let alerte: String?

    public init(
        id: String, nom: String, etat: String, resume: String? = nil, erreur: String? = nil, deposeLe: String? = nil,
        pourLe: String? = nil, paperless: Bool = false, alerte: String? = nil
    ) {
        self.id = id
        self.nom = nom
        etatBrut = etat
        self.resume = resume
        self.erreur = erreur
        self.deposeLe = deposeLe
        self.pourLe = pourLe
        self.paperless = paperless
        self.alerte = alerte
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, resume, erreur, paperless, alerte
        case etatBrut = "etat"
        case deposeLe = "depose_le"
        case pourLe = "pour_le"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nom = try c.decodeIfPresent(String.self, forKey: .nom) ?? id
        etatBrut = try c.decodeIfPresent(String.self, forKey: .etatBrut) ?? "en cours"
        resume = try c.decodeIfPresent(String.self, forKey: .resume)
        erreur = try c.decodeIfPresent(String.self, forKey: .erreur)
        deposeLe = try c.decodeIfPresent(String.self, forKey: .deposeLe)
        pourLe = try c.decodeIfPresent(String.self, forKey: .pourLe)
        // la console : `d.paperless ? " · archivé" : ""` ; le relais y range la tâche de Paperless (un objet)
        paperless = try c.decodeIfPresent(ValeurJSON.self, forKey: .paperless).map(Self.vrai) ?? false
        alerte = try c.decodeIfPresent(String.self, forKey: .alerte)
    }

    /// Une valeur « vraie » au sens de JavaScript (la console teste le champ tel quel).
    static func vrai(_ v: ValeurJSON) -> Bool {
        switch v {
        case .nul: false
        case .booleen(let b): b
        case .nombre(let n): n != 0 && !n.isNaN
        case .texte(let t): !t.isEmpty
        case .liste, .objet: true
        }
    }

    /// Comme la console : « pret », « erreur », tout le reste « en cours ».
    public var etat: Etat {
        switch etatBrut {
        case "pret": .pret
        case "erreur": .erreur
        default: .enCours
        }
    }
}

public struct ListeDocuments: Sendable, Equatable, Decodable {
    public let documents: [DocumentMaison]

    public init(documents: [DocumentMaison]) { self.documents = documents }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documents = try c.decodeIfPresent([DocumentMaison].self, forKey: .documents) ?? []
    }

    enum CodingKeys: String, CodingKey { case documents }
}

/// Le dépôt d'un document (`POST /docs`) : un corps multipart, comme le `FormData` de la console (« fichier »,
/// « nom », « pour_le » facultatif).
public struct DepotDocument: Sendable, Equatable {
    /// 20 Mo au plus (la limite du relais).
    public static let tailleMax = 20 * 1024 * 1024

    public let fichier: Data
    public let nomFichier: String
    public let type: String
    /// AAAA-MM-JJ.
    public let pourLe: String?

    public init(fichier: Data, nomFichier: String, type: String, pourLe: String? = nil) {
        self.fichier = fichier
        self.nomFichier = nomFichier
        self.type = type
        self.pourLe = pourLe
    }

    /// Le nom lisible, comme la console : sans extension, tirets et soulignés en espaces.
    public var nom: String {
        let base = (nomFichier as NSString).deletingPathExtension
        return base.replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
    }

    /// La requête, avec une frontière tirée au hasard (absente du fichier, vérifié).
    public func requete(frontiere: String = "alfred-" + UUID().uuidString) -> RequeteRelais {
        var f = frontiere
        while fichier.range(of: Data(f.utf8)) != nil { f += "-" + UUID().uuidString.prefix(8) }
        return RequeteRelais(.post, "/docs", corps: corps(frontiere: f), type: "multipart/form-data; boundary=\(f)")
    }

    func corps(frontiere: String) -> Data {
        var d = Data()
        func ligne(_ s: String) { d.append(Data((s + "\r\n").utf8)) }
        func champ(_ nom: String, _ valeur: String) {
            ligne("--\(frontiere)")
            ligne("Content-Disposition: form-data; name=\"\(nom)\"")
            ligne("")
            ligne(valeur)
        }
        ligne("--\(frontiere)")
        ligne("Content-Disposition: form-data; name=\"fichier\"; filename=\"\(Self.echapper(nomFichier))\"")
        ligne("Content-Type: \(type)")
        ligne("")
        d.append(fichier)
        ligne("")
        champ("nom", Self.echapper(nom))
        if let pourLe { champ("pour_le", pourLe) }
        ligne("--\(frontiere)--")
        return d
    }

    /// Un nom dans un en-tête : sans guillemet ni retour à la ligne (ce que fait un navigateur, WHATWG).
    static func echapper(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}

// MARK: - liens et état des services

/// Un lien vers un autre système (Home Assistant, Paperless…), selon le compte (`GET /liens`).
public struct LienSysteme: Sendable, Equatable, Identifiable, Decodable {
    public let nom: String
    public let url: URL
    public let note: String?
    public var id: String { nom }

    public init(nom: String, url: URL, note: String?) {
        self.nom = nom
        self.url = url
        self.note = note
    }

    /// Les liens utilisables : une adresse http(s) seulement (rien d'autre ne s'ouvre d'ici).
    public static func lire(_ donnees: Data) -> [LienSysteme]? {
        guard let liste = try? JSONDecoder().decode([LienSysteme].self, from: donnees) else { return nil }
        return liste.filter { ["http", "https"].contains($0.url.scheme?.lowercased()) && $0.url.host != nil }
    }
}

/// L'état des services, lu dans Uptime Kuma par le relais (`GET /etat`) : les pastilles de la console.
public struct EtatServices: Sendable, Equatable, Decodable {
    public struct Groupe: Sendable, Equatable, Decodable, Identifiable {
        public let nom: String
        public let services: [Service]
        public var id: String { nom }

        public init(nom: String, services: [Service]) {
            self.nom = nom
            self.services = services
        }

        /// Le nom court de la console (`ETAT_COURT`).
        public var nomCourt: String {
            ["Maison": "maison", "Voix d'Alfred": "voix", "Cabinet": "cabinet", "Surveillance": "nuit"][nom] ?? nom
        }
    }

    public struct Service: Sendable, Equatable, Decodable, Identifiable {
        public let nom: String
        /// ok, attente, panne, eteint (desktop arrêté : normal), inconnu.
        public let statut: String
        public let message: String?
        /// « AAAA-MM-JJ HH:MM:SS(.ms) », en UTC sans fuseau (Uptime Kuma), ou ISO 8601.
        public let depuis: String?
        public var id: String { nom }

        public init(nom: String, statut: String, message: String? = nil, depuis: String? = nil) {
            self.nom = nom
            self.statut = statut
            self.message = message
            self.depuis = depuis
        }

        /// Le mot de la console (`ETAT_MOT`).
        public var mot: String {
            [
                "ok": "en service", "attente": "en attente", "panne": "EN PANNE", "eteint": "éteint (normal)",
                "inconnu": "pas encore mesuré",
            ][statut] ?? statut
        }

        /// Comme la console : sans fuseau, l'heure est en UTC.
        public var dateDepuis: Date? {
            guard var s = depuis?.replacingOccurrences(of: " ", with: "T"), !s.isEmpty else { return nil }
            if !s.contains("Z"), !s.contains("+"), s.range(of: #"-\d\d:\d\d$"#, options: .regularExpression) == nil {
                s += "Z"
            }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        }
    }

    public let groupes: [Groupe]
    /// La page d'état d'Uptime Kuma (historique), si le relais la donne.
    public let kuma: URL?

    public init(groupes: [Groupe], kuma: URL?) {
        self.groupes = groupes
        self.kuma = kuma
    }

    enum CodingKeys: String, CodingKey { case groupes, kuma }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupes = try c.decodeIfPresent([Groupe].self, forKey: .groupes) ?? []
        let k = try? c.decodeIfPresent(URL.self, forKey: .kuma)
        kuma = ["http", "https"].contains(k?.scheme?.lowercased()) ? k : nil
    }

    /// Un service en panne : les pastilles passent en alerte.
    public var panne: Bool { groupes.contains { $0.services.contains { $0.statut == "panne" } } }
}

/// L'heure d'une notification ou d'un état, comme la console (`quandNotif`) : « 14:05 », « hier 14:05 », « 3.10 14:05 ».
public enum Quand {
    public static func texte(_ date: Date, maintenant: Date = .now, calendrier: Calendar = .current) -> String {
        let c = calendrier.dateComponents([.hour, .minute, .day, .month], from: date)
        let h = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if calendrier.isDate(date, inSameDayAs: maintenant) { return h }
        if let hier = calendrier.date(byAdding: .day, value: -1, to: maintenant),
            calendrier.isDate(date, inSameDayAs: hier)
        {
            return "hier " + h
        }
        return "\(c.day ?? 0).\(c.month ?? 0) " + h
    }
}
