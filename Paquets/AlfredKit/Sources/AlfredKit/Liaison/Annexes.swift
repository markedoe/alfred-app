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
    /// D'où elle vient (« hermes » : une réponse d'Hermes).
    public let source: String?
    /// 22.10 : une réponse d'Hermes que la console ou l'app qui l'attend doit réclamer et lire
    /// (`POST /notifications/livrer`) ; `livree` : déjà réclamée (par elle ou par une autre).
    public let aLire: Bool?
    public let livree: Bool?

    public init(
        id: String, titre: String?, message: String, t: Double, lu: Bool, source: String? = nil, aLire: Bool? = nil,
        livree: Bool? = nil
    ) {
        self.id = id
        self.titre = titre
        self.message = message
        self.t = t
        self.lu = lu
        self.source = source
        self.aLire = aLire
        self.livree = livree
    }

    enum CodingKeys: String, CodingKey {
        case id, titre, message, t, lu, source, livree
        case aLire = "a_lire"
    }

    public var date: Date { Date(timeIntervalSince1970: t) }
}

extension ListeNotifications {
    /// 22.10 : la réponse d'Hermes à lire, arrivée depuis la question (5 s de marge : horloges) et pas encore
    /// réclamée ; la plus ancienne d'abord (23.10 : deux questions de suite, leurs réponses se lisent dans l'ordre).
    public func reponseHermes(depuis: Date) -> NotificationConsole? {
        let pretes = notifications.filter {
            $0.source == "hermes" && $0.aLire == true && $0.livree != true && $0.t >= depuis.timeIntervalSince1970 - 5
        }
        return pretes.min { $0.t < $1.t }
    }
}

/// 22.10 : la réponse d'une réclamation (`POST /notifications/livrer`) : `ok` pour la PREMIÈRE console ou app
/// seulement, avec le texte et le jeton de la voix d'Alfred (absent si la voix n'a pas pu être préparée).
public struct ReponseLivree: Sendable, Equatable, Decodable {
    public let ok: Bool
    public let message: String?
    public let tts: String?

    public init(ok: Bool, message: String?, tts: String?) {
        self.ok = ok
        self.message = message
        self.tts = tts
    }

    /// Le chemin de la voix sur le relais (`/tts/<jeton>`), seulement pour un jeton fait de caractères sûrs.
    public var cheminVoix: String? {
        guard let tts, !tts.isEmpty, tts.count <= 200,
            tts.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) })
        else { return nil }
        return "/tts/" + tts
    }
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
/// 23.10 (la boîte d'arrivée) : le relais range d'abord le document dans Paperless, le résume ensuite, et donne un
/// verdict (`statut`) : rangé, envoyé, refusé (avec son motif). Les champs nouveaux sont FACULTATIFS : face à un
/// relais plus ancien, le statut se déduit comme l'ancienne console (`etat`, `paperless`).
public struct DocumentMaison: Sendable, Equatable, Identifiable, Decodable {
    public enum Etat: Sendable, Equatable {
        case pret, enCours, erreur
    }

    /// Le verdict de la carte (23.10), dans l'ordre du cycle.
    public enum Statut: String, Sendable, Equatable {
        /// Lecture du document (extraction du texte) par le relais.
        case lecture
        /// Envoyé à Paperless, en attente de sa réponse.
        case rangement
        /// Rangé dans Paperless (son numéro est connu).
        case range
        /// Envoyé à Paperless, sans réponse lisible (le droit de lire l'état d'un dépôt manque) : rien à faire.
        case envoye
        /// Refusé, avec son motif : reste jusqu'à « Retirer » ou « Réessayer ».
        case refuse
        /// Un document de banc (essais) : jamais rangé dans Paperless.
        case banc
        /// 23.10 (soir) : déjà présent dans Paperless — un avertissement, pas un refus (une étiquette en plus y est
        /// ajoutée) ; il quitte le panneau comme un rangé.
        case doublon
        /// Un relais plus ancien : lu et résumé, sans archivage connu.
        case lu
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
    /// Archivé (ou envoyé) dans Paperless.
    public let paperless: Bool
    /// Un passage suspect (adressé à un assistant, ou qui réclame un paiement) ; nil sinon.
    public let alerte: String?
    /// 23.10 : le verdict tel que le relais l'écrit (nil : relais plus ancien).
    public let statutBrut: String?
    /// 23.10 : le motif lisible d'un refus.
    public let motif: String?
    /// 23.10 : la nature d'un refus (« illisible », « lecture », « paperless », « paperless_refus »,
    /// « paperless_absent », « doublon ») ; un code inconnu reste un simple refus (le `motif` est montré tel quel).
    public let refus: String?
    /// 23.10 : un nouvel essai a un sens (pas pour un doublon).
    public let reessayer: Bool
    /// 23.10 : la fiche dans Paperless (http(s) seulement), si la personne a le droit de la voir.
    public let lien: URL?
    /// 23.10 : un doublon dont la fiche existante n'est pas montrée (« déjà archivé »).
    public let dejaArchive: Bool
    /// 23.10 : le résumé attend (« pc » : le PC d'Alfred est éteint ; « file » : son tour vient).
    public let resumeAttente: String?
    /// 23.10 (soir) : quand le document a été rangé dans Paperless (ISO 8601), pour les cartes `recents` ; un document
    /// rangé quitte le panneau aussitôt (le champ `quitte_le` du midi n'existe plus).
    public let rangeLe: String?
    /// 23.10 (soir) : l'avertissement d'un doublon, prêt à afficher (« déjà présent dans Paperless — étiquette « X »
    /// ajoutée », « déjà archivé »…), et les étiquettes en plus ajoutées ou non à l'exemplaire existant.
    public let avertissement: String?
    public let etiquettesAjoutees: [String]
    public let etiquettesNonAjoutees: [String]
    /// 23.10 : les étiquettes du document (posées, ou en attente du rangement) et celles que Paperless n'a pas posées.
    public let etiquettes: [String]
    public let etiquettesNonPosees: [String]

    public init(
        id: String, nom: String, etat: String, resume: String? = nil, erreur: String? = nil, deposeLe: String? = nil,
        pourLe: String? = nil, paperless: Bool = false, alerte: String? = nil, statut: String? = nil,
        motif: String? = nil, refus: String? = nil, reessayer: Bool = false, lien: URL? = nil,
        dejaArchive: Bool = false, resumeAttente: String? = nil, rangeLe: String? = nil, etiquettes: [String] = [],
        etiquettesNonPosees: [String] = [], avertissement: String? = nil, etiquettesAjoutees: [String] = [],
        etiquettesNonAjoutees: [String] = []
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
        statutBrut = statut
        self.motif = motif
        self.refus = refus
        self.reessayer = reessayer
        self.lien = Self.web(lien)
        self.dejaArchive = dejaArchive
        self.resumeAttente = resumeAttente
        self.rangeLe = rangeLe
        self.etiquettes = etiquettes
        self.etiquettesNonPosees = etiquettesNonPosees
        self.avertissement = avertissement
        self.etiquettesAjoutees = etiquettesAjoutees
        self.etiquettesNonAjoutees = etiquettesNonAjoutees
    }

    enum CodingKeys: String, CodingKey {
        case id, nom, resume, erreur, paperless, alerte, motif, refus, reessayer, lien
        case etiquettes
        case etatBrut = "etat"
        case deposeLe = "depose_le"
        case pourLe = "pour_le"
        case statutBrut = "statut"
        case etiquettesNonPosees = "etiquettes_non_posees"
        case avertissement
        case etiquettesAjoutees = "etiquettes_ajoutees"
        case etiquettesNonAjoutees = "etiquettes_non_ajoutees"
        case dejaArchive = "deja_archive"
        case resumeAttente = "resume_attente"
        case rangeLe = "range_le"
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
        // 23.10 : facultatifs, et tolérants (une valeur d'un autre type est ignorée, jamais une liste perdue)
        statutBrut = try? c.decodeIfPresent(String.self, forKey: .statutBrut)
        motif = try? c.decodeIfPresent(String.self, forKey: .motif)
        refus = try? c.decodeIfPresent(String.self, forKey: .refus)
        reessayer = (try? c.decodeIfPresent(ValeurJSON.self, forKey: .reessayer)).map(Self.vrai) ?? false
        lien = Self.web((try? c.decodeIfPresent(String.self, forKey: .lien)).flatMap(URL.init(string:)))
        dejaArchive = (try? c.decodeIfPresent(ValeurJSON.self, forKey: .dejaArchive)).map(Self.vrai) ?? false
        resumeAttente = try? c.decodeIfPresent(String.self, forKey: .resumeAttente)
        rangeLe = try? c.decodeIfPresent(String.self, forKey: .rangeLe)
        etiquettes = Self.textes(try? c.decodeIfPresent(ValeurJSON.self, forKey: .etiquettes))
        etiquettesNonPosees = Self.textes(try? c.decodeIfPresent(ValeurJSON.self, forKey: .etiquettesNonPosees))
        avertissement = try? c.decodeIfPresent(String.self, forKey: .avertissement)
        etiquettesAjoutees = Self.textes(try? c.decodeIfPresent(ValeurJSON.self, forKey: .etiquettesAjoutees))
        etiquettesNonAjoutees = Self.textes(try? c.decodeIfPresent(ValeurJSON.self, forKey: .etiquettesNonAjoutees))
    }

    /// Une liste de noms (23.10), tolérante : ce qui n'est pas un texte non vide est sauté.
    static func textes(_ v: ValeurJSON?) -> [String] {
        guard case .liste(let l)? = v else { return [] }
        return l.compactMap { $0.texte.flatMap { $0.isEmpty ? nil : $0 } }
    }

    /// 23.10 : ce que la carte écrit après la date : « · étiquettes : A, B · non posée : C » (vide sans étiquette).
    public var texteEtiquettes: String {
        var t = ""
        if !etiquettes.isEmpty { t += " · étiquettes : " + etiquettes.joined(separator: ", ") }
        if !etiquettesNonPosees.isEmpty {
            t +=
                (etiquettesNonPosees.count > 1 ? " · non posées : " : " · non posée : ")
                + etiquettesNonPosees.joined(separator: ", ")
        }
        return t
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

    /// Un lien vers Paperless : une adresse http(s) seulement (rien d'autre ne s'ouvre d'ici, comme les liens).
    static func web(_ u: URL?) -> URL? {
        guard let u, ["http", "https"].contains(u.scheme?.lowercased()), u.host != nil else { return nil }
        return u
    }

    /// Comme la console : « pret », « erreur », tout le reste « en cours ».
    public var etat: Etat {
        switch etatBrut {
        case "pret": .pret
        case "erreur": .erreur
        default: .enCours
        }
    }

    /// Le verdict (23.10) : celui du relais ; sans lui (relais plus ancien, ou valeur inconnue), déduit comme l'ancienne
    /// console — prêt et archivé : rangé ; prêt : lu ; erreur : refusé (motif : l'erreur) ; le reste : en lecture.
    public var statut: Statut {
        if let s = statutBrut.flatMap(Statut.init(rawValue:)), s != .lu { return s }
        switch etat {
        case .pret: return paperless ? .range : .lu
        case .erreur: return .refuse
        case .enCours: return .lecture
        }
    }

    /// La carte demande une action, ou attend encore (la pastille de l'en-tête) : en lecture, en rangement, refusée.
    public var aTraiter: Bool { [.lecture, .rangement, .refuse].contains(statut) }

    /// L'état écrit sur la carte, les mots de la console ; nil pour un document lu par un relais plus ancien (la carte
    /// montre alors son résumé seul, comme avant).
    public var texteEtat: String? {
        let attente: String =
            switch resumeAttente {
            case "pc": " — résumé quand le PC d’Alfred sera allumé"
            case "file": " — résumé en cours…"
            default: ""
            }
        switch statut {
        case .lecture: return "Lecture en cours…"
        case .rangement: return "Rangement dans Paperless…"
        case .range: return "Rangé dans Paperless" + attente
        case .envoye: return "Envoyé à Paperless" + attente
        case .refuse: return "Refusé : " + motifRefus
        case .banc: return "Lu (banc : pas rangé dans Paperless)"
        case .doublon: return "Déjà présent : " + (avertissement ?? "déjà présent dans Paperless")
        case .lu: return nil
        }
    }

    /// Le motif d'un refus : celui du relais, sinon l'erreur de lecture (relais plus ancien).
    public var motifRefus: String {
        if let m = motif?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        if refus == "doublon" { return "déjà dans Paperless" }
        if let e = erreur?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return "lecture impossible (\(e))"
        }
        return "lecture impossible"
    }

    /// Le résumé à montrer sous l'état : jamais pendant la lecture ; celui du relais sinon.
    public var resumeAffiche: String? {
        guard statut != .lecture, let r = resume?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
            return nil
        }
        return r
    }

    /// Les boutons d'une carte (23.10) : « Réessayer » et « Retirer » sur un refus, « Supprimer » sur un document que
    /// Paperless n'a pas (banc, ou lu par un relais plus ancien) ; plus jamais « Supprimer » sur un document rangé.
    public var peutReessayer: Bool { statut == .refuse && reessayer }
    public var peutRetirer: Bool { statut == .refuse }
    public var peutSupprimer: Bool { statut == .banc || statut == .lu }

    /// L'identifiant dans un chemin : « / » échappé aussi (il ne doit jamais viser une autre route).
    public static func segment(_ id: String) -> String {
        var permis = CharacterSet.urlPathAllowed
        permis.remove("/")
        return id.addingPercentEncoding(withAllowedCharacters: permis) ?? id
    }

    /// 23.10 : un nouvel essai d'un document refusé (`POST /docs/<id>/reessayer`, corps vide).
    public var requeteReessayer: RequeteRelais { RequeteRelais(.post, "/docs/" + Self.segment(id) + "/reessayer") }

    /// « Retirer » (un refus) ou « Supprimer » (banc) : `DELETE /docs/<id>`.
    public var requeteRetirer: RequeteRelais { RequeteRelais(.delete, "/docs/" + Self.segment(id)) }
}

public struct ListeDocuments: Sendable, Equatable, Decodable {
    /// Le panneau : en lecture, en rangement, refusés, banc (23.10, soir : un document rangé le quitte aussitôt).
    public let documents: [DocumentMaison]
    /// 23.10 (soir) : les documents rangés ou envoyés depuis moins de 15 min (`range_le`, `lien`) : ils confirment un
    /// lot ; absents d'un relais plus ancien.
    public let recents: [DocumentMaison]
    /// 23.10 (soir) : les refusés (la section « À revoir ») ; nil : relais plus ancien.
    public let aRevoir: Int?
    /// 23.10 : ce que le relais compte « à traiter » (= `a_revoir` depuis le soir, pour l'ancienne app).
    public let aTraiter: Int?
    /// 23.10 : les fiches gardées à la maison mais hors du panneau.
    public let horsPanneau: Int?
    /// 23.10 (soir) : la liste de Paperless, derniers ajoutés en tête (le lien « voir » de plusieurs documents rangés).
    public let paperlessListe: URL?

    public init(
        documents: [DocumentMaison], recents: [DocumentMaison] = [], aRevoir: Int? = nil, aTraiter: Int? = nil,
        horsPanneau: Int? = nil, paperlessListe: URL? = nil
    ) {
        self.documents = documents
        self.recents = recents
        self.aRevoir = aRevoir
        self.aTraiter = aTraiter
        self.horsPanneau = horsPanneau
        self.paperlessListe = DocumentMaison.web(paperlessListe)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documents = try c.decodeIfPresent([DocumentMaison].self, forKey: .documents) ?? []
        // tolérant : une liste illisible ne perd jamais le panneau
        recents = (try? c.decodeIfPresent([DocumentMaison].self, forKey: .recents)) ?? []
        aRevoir = try? c.decodeIfPresent(Int.self, forKey: .aRevoir)
        aTraiter = try? c.decodeIfPresent(Int.self, forKey: .aTraiter)
        horsPanneau = try? c.decodeIfPresent(Int.self, forKey: .horsPanneau)
        paperlessListe = DocumentMaison.web(
            (try? c.decodeIfPresent(String.self, forKey: .paperlessListe)).flatMap(URL.init(string:)))
    }

    enum CodingKeys: String, CodingKey {
        case documents, recents
        case aRevoir = "a_revoir"
        case aTraiter = "a_traiter"
        case horsPanneau = "hors_panneau"
        case paperlessListe = "paperless_liste"
    }

    /// Les cartes « À revoir » : les refusés.
    public var refuses: [DocumentMaison] { documents.filter { $0.statut == .refuse } }

    /// Les cartes du relais encore « en cours » (lecture, rangement) et celles d'un banc.
    public var enCours: [DocumentMaison] { documents.filter { [.lecture, .rangement, .banc].contains($0.statut) } }

    /// La pastille de l'en-tête (23.10, soir) : les lignes « À envoyer » (valables ou refusées), plus « À revoir » —
    /// les refusés du relais (`a_revoir`, sinon comptés ici) et les refus de l'app au dépôt (400, 413, 415, envoi coupé).
    public func pastille(aEnvoyer: Int = 0, refusLocaux: Int = 0) -> Int {
        max(0, aEnvoyer) + max(0, aRevoir ?? refuses.count) + max(0, refusLocaux)
    }

    /// Le rythme de relecture (23.10, soir) : 2,5 s tant qu'un fichier est en cours (envoyé par l'app, ou une carte du
    /// relais en lecture ou en rangement), sinon 60 s.
    public func delaiRelecture(lotEnCours: Bool = false) -> Duration {
        if lotEnCours || documents.contains(where: { [.lecture, .rangement].contains($0.statut) }) {
            return .milliseconds(2500)
        }
        return .seconds(60)
    }
}

// MARK: - à envoyer (23.10, soir)

/// Le type d'un fichier d'après ses premiers octets, comme le relais (`documents._type`) : PDF, JPEG, PNG, WebP par leur
/// signature ; e-mail par l'extension `.eml` ou le type déclaré ; texte par `.txt`, `.md` ou un type `text/…` ; nil :
/// type non pris en charge.
public enum TypeDocument {
    public static func detecter(nom: String, entete: Data, typeDeclare: String? = nil) -> String? {
        let o = [UInt8](entete.prefix(16))
        let ext = (nom as NSString).pathExtension.lowercased()
        let declare = (typeDeclare ?? "").lowercased()
        if o.starts(with: Array("%PDF".utf8)) { return "application/pdf" }
        if o.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if o.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if o.count >= 12, o.starts(with: Array("RIFF".utf8)), Array(o[8..<12]) == Array("WEBP".utf8) {
            return "image/webp"
        }
        if ext == "eml" || declare == "message/rfc822" { return "message/rfc822" }
        if ext == "txt" || ext == "md" || declare.hasPrefix("text/") { return "text/plain" }
        return nil
    }
}

/// La taille d'un fichier comme la console l'écrit : « 340 ko » (arrondi, 1 au moins), « 1,2 Mo » (une décimale,
/// virgule) ; 1 ko = 1 024 octets, comme la limite de 20 Mo du relais.
public enum TailleDocument {
    public static func texte(_ octets: Int) -> String {
        let mo = 1024 * 1024
        if octets < mo { return "\(max(1, Int((Double(octets) / 1024).rounded()))) ko" }
        let dixiemes = Int((Double(octets) / Double(mo) * 10).rounded())
        return "\(dixiemes / 10),\(dixiemes % 10) Mo"
    }
}

/// Une ligne de « À envoyer » (23.10, soir) : un fichier choisi, rien n'est encore parti. Refusé d'emblée s'il est trop
/// lourd ou d'un type que le relais refuserait.
public struct FichierAEnvoyer: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let nom: String
    public let octets: Int
    /// Le type que le relais reconnaîtra (nil : refusé).
    public let type: String?
    public let refus: RefusLocal.Motif?

    /// `entete` : les premiers octets du fichier (16 suffisent) ; `typeDeclare` : le type annoncé par l'appareil.
    public init(nom: String, octets: Int, entete: Data, typeDeclare: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.nom = nom
        self.octets = octets
        if octets > DepotDocument.tailleMax {
            type = nil
            refus = .taille
        } else if let t = TypeDocument.detecter(nom: nom, entete: entete, typeDeclare: typeDeclare) {
            type = t
            refus = nil
        } else {
            type = nil
            refus = .type
        }
    }

    public var valable: Bool { refus == nil }

    /// « devis.pdf · 340 ko ».
    public var ligne: String { nom + " · " + TailleDocument.texte(octets) }

    /// « Refusé : trop lourd (20 Mo au plus) », « Refusé : type non pris en charge (…) », ou nil.
    public var texteRefus: String? { refus.map { RefusLocal(nom: nom, motif: $0).texte } }
}

/// Le suivi d'un lot envoyé (23.10, soir) : chaque fichier « Envoi… » (requête en route), puis « Rangement… » (la carte
/// du relais en lecture ou en rangement), jusqu'à ce qu'il apparaisse dans `recents` (rangé) ; refusé, il passe dans
/// « À revoir » (une carte du relais, ou un refus de l'app au dépôt).
public struct SuiviLot: Sendable, Equatable {
    public enum Etat: Sendable, Equatable {
        case envoi
        case rangement(String)
        case range(String)
        /// 23.10 (soir) : déjà présent dans Paperless (un avertissement, pas un refus).
        case doublon(String)
        /// Refusé, coupé, ou disparu du relais : plus « en cours », pas compté comme rangé.
        case fini
    }

    public struct Fichier: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let nom: String
        public var etat: Etat
    }

    public private(set) var fichiers: [Fichier] = []

    public init() {}

    /// Un nouveau lot : le précédent est oublié (sa confirmation aussi).
    public mutating func nouveau() { fichiers = [] }

    public mutating func envoi(_ id: UUID, nom: String) { fichiers.append(Fichier(id: id, nom: nom, etat: .envoi)) }

    /// Le relais a reçu le fichier (202) : sa fiche porte son identifiant (sans lui, on ne peut plus le suivre).
    public mutating func recu(_ id: UUID, document: String?) {
        changer(id) { $0 = document.map(Etat.rangement) ?? .fini }
    }

    /// Refusé au dépôt (400, 413, 415) ou envoi coupé : plus en cours.
    public mutating func echec(_ id: UUID) { changer(id) { $0 = .fini } }

    private mutating func changer(_ id: UUID, _ f: (inout Etat) -> Void) {
        if let i = fichiers.firstIndex(where: { $0.id == id }) { f(&fichiers[i].etat) }
    }

    /// Une relecture du relais : rangé s'il est dans `recents` ; fini s'il est refusé ou n'est plus nulle part. Rend
    /// true si un document vient d'être rangé.
    @discardableResult
    public mutating func maj(_ liste: ListeDocuments) -> Bool {
        var nouveau = false
        for i in fichiers.indices {
            guard case .rangement(let d) = fichiers[i].etat else { continue }
            if let carte = liste.recents.first(where: { $0.id == d }) {
                fichiers[i].etat = carte.statut == .doublon ? .doublon(d) : .range(d)
                nouveau = true
            } else if let carte = liste.documents.first(where: { $0.id == d }) {
                if ![.lecture, .rangement].contains(carte.statut) { fichiers[i].etat = .fini }
            } else {
                fichiers[i].etat = .fini
            }
        }
        return nouveau
    }

    /// Les identifiants du relais suivis ici (leurs cartes ne se montrent pas une 2e fois dans « En cours »).
    public var documentsSuivis: Set<String> {
        Set(
            fichiers.compactMap {
                if case .rangement(let d) = $0.etat { return d }
                return nil
            })
    }

    /// Un fichier du lot est encore en cours (relecture toutes les 2,5 s).
    public var enCours: Bool { fichiers.contains { $0.etat == .envoi || $0.etatRangement } }

    /// Les lignes « En cours » du lot : « <nom> — Envoi… », « <nom> — Rangement… ».
    public var lignes: [String] {
        fichiers.compactMap { f in
            switch f.etat {
            case .envoi: f.nom + " — Envoi…"
            case .rangement: f.nom + " — Rangement…"
            case .range, .doublon, .fini: nil
            }
        }
    }

    /// La ligne de confirmation (23.10, soir), pour les documents de CE lot arrivés dans les récents — R rangés, D déjà
    /// présents (doublons, un avertissement) — avec les mots de la console :
    /// « 1 document rangé dans Paperless », « 3 documents rangés dans Paperless, 2 déjà présents », « 1 document rangé
    /// dans Paperless, 1 déjà présent (étiquette « X » ajoutée) », « 1 document déjà présent dans Paperless — étiquette
    /// « X » ajoutée », « 2 documents déjà présents dans Paperless » ; « voir » : la fiche d'un document seul (s'il en a
    /// une), la liste de Paperless pour plusieurs. nil si aucun.
    public func confirmation(_ liste: ListeDocuments) -> ConfirmationRangement? {
        var ranges: [String] = []
        var doublons: [String] = []
        for f in fichiers {
            switch f.etat {
            case .range(let d): ranges.append(d)
            case .doublon(let d): doublons.append(d)
            default: break
            }
        }
        let (r, n) = (ranges.count, doublons.count)
        guard r + n > 0 else { return nil }
        let avertissement = doublons.first.flatMap { d in liste.recents.first { $0.id == d }?.avertissement }
        let texte: String
        if n == 0 {
            texte = r == 1 ? "1 document rangé dans Paperless" : "\(r) documents rangés dans Paperless"
        } else if r > 0 {
            var t = r == 1 ? "1 document rangé dans Paperless, " : "\(r) documents rangés dans Paperless, "
            t += n == 1 ? "1 déjà présent" : "\(n) déjà présents"
            if n == 1, let a = avertissement, let tiret = a.range(of: " — ") {
                let suite = a[tiret.upperBound...].trimmingCharacters(in: .whitespaces)
                if !suite.isEmpty { t += " (" + suite + ")" }
            }
            texte = t
        } else if n == 1 {
            texte = "1 document " + (avertissement ?? "déjà présent dans Paperless")
        } else {
            texte = "\(n) documents déjà présents dans Paperless"
        }
        let seul = r + n == 1 ? (ranges + doublons).first : nil
        let lien = seul.map { d in liste.recents.first { $0.id == d }?.lien } ?? liste.paperlessListe
        return ConfirmationRangement(texte: texte, lien: lien)
    }
}

extension SuiviLot.Fichier {
    fileprivate var etatRangement: Bool {
        if case .rangement = etat { return true }
        return false
    }
}

/// « 3 documents rangés dans Paperless — voir » : le texte, et le lien de « voir » (nil : pas de lien).
public struct ConfirmationRangement: Sendable, Equatable {
    public let texte: String
    public let lien: URL?

    public init(texte: String, lien: URL?) {
        self.texte = texte
        self.lien = lien
    }

    /// Le texte complet, « voir » compris quand il y a un lien.
    public var ligne: String { lien == nil ? texte : texte + " — voir" }
}

// MARK: - étiquettes (23.10)

/// Une étiquette de Paperless proposée au dépôt (`GET /docs/etiquettes`).
public struct EtiquetteDocument: Sendable, Equatable, Hashable, Identifiable, Decodable {
    public let id: Int
    public let nom: String

    public init(id: Int, nom: String) {
        self.id = id
        self.nom = nom
    }
}

/// La liste des étiquettes (`GET /docs/etiquettes`), triée par nom, sans les étiquettes techniques ; `disponible` faux :
/// Paperless ne répond pas (liste vide, un nom nouveau reste possible).
public struct ListeEtiquettes: Sendable, Equatable, Decodable {
    public let etiquettes: [EtiquetteDocument]
    public let disponible: Bool

    public init(etiquettes: [EtiquetteDocument], disponible: Bool) {
        self.etiquettes = etiquettes
        self.disponible = disponible
    }

    enum CodingKeys: String, CodingKey { case etiquettes, disponible }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // une entrée mal formée est sautée, jamais toute la liste
        let brutes = (try? c.decodeIfPresent([ValeurJSON].self, forKey: .etiquettes)) ?? []
        etiquettes = brutes.compactMap { v in
            guard case .nombre(let n)? = v["id"], n == n.rounded(), let nom = v["nom"]?.texte, !nom.isEmpty else {
                return nil
            }
            return EtiquetteDocument(id: Int(n), nom: nom)
        }
        disponible = (try? c.decodeIfPresent(Bool.self, forKey: .disponible)) ?? false
    }
}

/// Une étiquette choisie au dépôt : une de la liste (son n° part au relais), ou une nouvelle (son nom nettoyé ; le
/// relais la crée au rangement, sans doublon).
public enum ChoixEtiquette: Sendable, Equatable, Hashable, Identifiable {
    case existante(EtiquetteDocument)
    case nouvelle(String)

    public var nom: String {
        switch self {
        case .existante(let e): e.nom
        case .nouvelle(let n): n
        }
    }

    /// La valeur du champ `etiquette` : le n° en décimal, ou le nom.
    public var valeur: String {
        switch self {
        case .existante(let e): String(e.id)
        case .nouvelle(let n): n
        }
    }

    public var id: String { Etiquettes.cle(nom) }
}

/// Une ligne de la liste de propositions sous le champ « Ajouter une étiquette… ».
public enum PropositionEtiquette: Sendable, Equatable, Identifiable {
    case existante(EtiquetteDocument)
    /// « Nouvelle étiquette : <nom> » (toujours la dernière).
    case nouvelle(String)

    public var texte: String {
        switch self {
        case .existante(let e): e.nom
        case .nouvelle(let n): "Nouvelle étiquette : " + n
        }
    }

    public var choix: ChoixEtiquette {
        switch self {
        case .existante(let e): .existante(e)
        case .nouvelle(let n): .nouvelle(n)
        }
    }

    public var id: String { texte }
}

/// Les règles des étiquettes, les mêmes que la console et le relais (23.10).
public enum Etiquettes {
    /// 10 étiquettes au plus par dépôt (le relais refuse au-delà).
    public static let max = 10
    /// 8 propositions au plus sous le champ.
    public static let maxPropositions = 8
    /// 40 caractères au plus pour un nom.
    public static let longueurMax = 40

    /// Un nom tapé, nettoyé comme le relais : NFC ; caractère de contrôle, de format (invisible) ou séparateur → espace ;
    /// espaces réduits, bords retirés ; 40 caractères au plus ; nil s'il ne reste rien.
    public static func nettoyer(_ s: String) -> String? {
        var sortie = String.UnicodeScalarView()
        for u in s.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch u.properties.generalCategory {
            case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator:
                sortie.append(" ")
            default:
                sortie.append(u)
            }
        }
        let mots = String(sortie).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        // 40 points de code, comme le relais (Python compte les points de code, pas les caractères affichés)
        let coupe = String(String.UnicodeScalarView(mots.unicodeScalars.prefix(longueurMax)))
        let propre = coupe.trimmingCharacters(in: .whitespaces)
        return propre.isEmpty ? nil : propre
    }

    /// La clé de comparaison : sans casse ni accents (« Électricité » = « electricite »).
    public static func cle(_ s: String) -> String {
        let sansAccents = s.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark
        }
        return String(String.UnicodeScalarView(sansAccents)).lowercased()
    }

    /// Les propositions pour une saisie : les étiquettes dont le nom, ou l'un de ses mots, commence par la saisie (sans
    /// casse ni accents), celles déjà choisies exclues, 8 au plus ; puis « Nouvelle étiquette : <nom> » si la saisie
    /// nettoyée ne correspond à aucune étiquette de la liste (ni à une nouvelle déjà choisie). Saisie vide (le champ
    /// touché, rien de tapé) : les 8 premières, dans l'ordre du relais, sans « Nouvelle étiquette ».
    public static func propositions(
        _ saisie: String, liste: [EtiquetteDocument], choisies: [ChoixEtiquette]
    ) -> [PropositionEtiquette] {
        let prises = Set(choisies.map(\.id))
        guard let propre = nettoyer(saisie) else {
            return liste.filter { !prises.contains(cle($0.nom)) }.prefix(maxPropositions).map(
                PropositionEtiquette.existante)
        }
        let q = cle(propre)
        let trouvees = liste.filter { e in
            guard !prises.contains(cle(e.nom)) else { return false }
            let k = cle(e.nom)
            return k.hasPrefix(q)
                || k.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(q) }
        }
        var out = trouvees.prefix(maxPropositions).map(PropositionEtiquette.existante)
        if !liste.contains(where: { cle($0.nom) == q }), !prises.contains(q) { out.append(.nouvelle(propre)) }
        return out
    }

    /// Ce que la touche Retour choisit : l'étiquette de la liste qui porte exactement ce nom (sans casse ni accents),
    /// sinon une nouvelle ; nil pour une saisie vide ou déjà choisie.
    public static func choixDirect(
        _ saisie: String, liste: [EtiquetteDocument], choisies: [ChoixEtiquette]
    )
        -> ChoixEtiquette?
    {
        guard let propre = nettoyer(saisie) else { return nil }
        let q = cle(propre)
        guard !choisies.contains(where: { $0.id == q }) else { return nil }
        if let e = liste.first(where: { cle($0.nom) == q }) { return .existante(e) }
        return .nouvelle(propre)
    }
}

/// 23.10 : un bouton en deux temps (« Retirer », « Supprimer ») : le premier toucher ARME l'action pour ce document
/// pendant 3,5 s, le second, dans ce délai, la confirme. Gardé hors de la carte (dans les annexes) : une relecture de la
/// liste (toutes les 2,5 s pendant qu'un autre fichier du lot est lu) ne le remet jamais à zéro. Une seule action armée
/// à la fois : en armer une autre désarme la précédente.
public struct DeuxTemps: Sendable, Equatable {
    public static let delai: TimeInterval = 3.5

    struct Arme: Sendable, Equatable {
        let action: String
        let id: String
        let jusqua: Date
    }

    private(set) var arme: Arme?

    public init() {}

    /// Un toucher : true s'il CONFIRME l'action armée (même action, même document, dans le délai) ; sinon il l'arme et
    /// rend false.
    public mutating func toucher(_ action: String, id: String, maintenant: Date = .now) -> Bool {
        if estArme(action, id: id, maintenant: maintenant) {
            arme = nil
            return true
        }
        arme = Arme(action: action, id: id, jusqua: maintenant.addingTimeInterval(Self.delai))
        return false
    }

    public func estArme(_ action: String, id: String, maintenant: Date = .now) -> Bool {
        guard let arme else { return false }
        return arme.action == action && arme.id == id && maintenant < arme.jusqua
    }

    /// Le délai passé : plus rien d'armé (la carte redevient « Retirer » ou « Supprimer »).
    public mutating func expirer(maintenant: Date = .now) {
        if let a = arme, maintenant >= a.jusqua { arme = nil }
    }
}

/// 23.10 : un fichier refusé AVANT tout envoi, ou par le relais au dépôt (413, 415) : une carte de l'app seule (rien
/// n'est gardé à la maison), jusqu'à « Retirer ».
public struct RefusLocal: Sendable, Equatable, Identifiable {
    public enum Motif: Sendable, Equatable {
        case taille, type
        /// 23.10 : un refus du relais (400) avec son texte lisible (étiquette inconnue, nom réservé…).
        case relais(String)
        /// 23.10 (soir) : l'envoi n'a pas abouti (réseau, maison muette) ; la raison courte.
        case envoiCoupe(String)
        /// 23.10 (soir) : le fichier n'a plus pu être lu au moment de l'envoi.
        case illisible
    }

    public let id: UUID
    public let nom: String
    public let motif: Motif

    public init(nom: String, motif: Motif, id: UUID = UUID()) {
        self.id = id
        self.nom = nom
        self.motif = motif
    }

    /// Le refus d'un dépôt d'après le code du relais : 413 (trop lourd), 415 (type), 400 avec un texte (23.10 : une
    /// étiquette refusée) ; nil pour toute autre réponse.
    public init?(nom: String, statut: Int, corps: Data = Data()) {
        switch statut {
        case 413: self.init(nom: nom, motif: .taille)
        case 415: self.init(nom: nom, motif: .type)
        case 400:
            let texte = String(decoding: corps.prefix(300), as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard !texte.isEmpty else { return nil }
            self.init(nom: nom, motif: .relais(texte))
        default: return nil
        }
    }

    /// Les mots de la console.
    public var texte: String {
        switch motif {
        case .taille: "Refusé : trop lourd (20 Mo au plus)"
        case .type: "Refusé : type non pris en charge (PDF, image, texte ou e-mail)"
        case .relais(let t): "Refusé : " + t
        case .envoiCoupe(let r): "Refusé : envoi coupé (\(r))"
        case .illisible: "Refusé : ce fichier n’a pas pu être lu"
        }
    }
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
    /// 23.10 : les étiquettes du dépôt, chacune un champ `etiquette` : le n° d'une étiquette de la liste, ou le nom
    /// (nettoyé) d'une nouvelle ; 10 au plus.
    public let etiquettes: [String]

    public init(fichier: Data, nomFichier: String, type: String, pourLe: String? = nil, etiquettes: [String] = []) {
        self.fichier = fichier
        self.nomFichier = nomFichier
        self.type = type
        self.pourLe = pourLe
        self.etiquettes = Array(etiquettes.prefix(Etiquettes.max))
    }

    /// Le nom lisible, comme la console : sans extension, tirets et soulignés en espaces.
    public var nom: String {
        let base = (nomFichier as NSString).deletingPathExtension
        return base.replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
    }

    /// La requête, avec une frontière tirée au hasard (absente du fichier, vérifié).
    public func requete(frontiere: String = "alfred-" + UUID().uuidString) -> RequeteRelais {
        var f = frontiere
        // ni dans le fichier, ni dans une étiquette (23.10)
        while fichier.range(of: Data(f.utf8)) != nil || etiquettes.contains(where: { $0.contains(f) }) {
            f += "-" + UUID().uuidString.prefix(8)
        }
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
        // 23.10 : un champ par étiquette, sans retour à la ligne (le nettoyage les retire déjà)
        for e in etiquettes { champ("etiquette", Self.echapper(e)) }
        ligne("--\(frontiere)--")
        return d
    }

    /// Un nom dans un en-tête : sans guillemet ni retour à la ligne (ce que fait un navigateur, WHATWG).
    static func echapper(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}

/// 23.10 : un lot de documents choisis d'un coup (photothèque, fichiers) : « Pour le », lu une fois au choix, vaut pour
/// tout le lot ; les fichiers partent l'un après l'autre (une requête chacun, comme la console), un seul en mémoire.
public struct LotDepot: Sendable, Equatable {
    /// AAAA-MM-JJ, ou nil.
    public let pourLe: String?
    public let total: Int
    /// 23.10 : les étiquettes du lot (valeurs des champs `etiquette`), les mêmes pour chaque fichier.
    public let etiquettes: [String]

    public init(pourLe: String?, total: Int, etiquettes: [String] = []) {
        self.pourLe = pourLe
        self.total = total
        self.etiquettes = etiquettes
    }

    /// Le dépôt d'un fichier du lot, avec le jour et les étiquettes du lot.
    public func depot(fichier: Data, nomFichier: String, type: String) -> DepotDocument {
        DepotDocument(fichier: fichier, nomFichier: nomFichier, type: type, pourLe: pourLe, etiquettes: etiquettes)
    }

    /// La ligne d'état pendant l'envoi : « Envoi de devis.pdf… », « Envoi de devis.pdf (2 sur 3)… ».
    public func etatEnvoi(_ nom: String, rang: Int) -> String {
        total > 1 ? "Envoi de \(nom) (\(rang) sur \(total))…" : "Envoi de \(nom)…"
    }

    /// La ligne d'état une fois le lot reçu : « Reçu. Alfred le lit… », « 3 reçus. Alfred les lit… » ; nil si rien n'est
    /// parti.
    public static func recus(_ n: Int) -> String? {
        switch n {
        case ..<1: nil
        case 1: "Reçu. Alfred le lit…"
        default: "\(n) reçus. Alfred les lit…"
        }
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
