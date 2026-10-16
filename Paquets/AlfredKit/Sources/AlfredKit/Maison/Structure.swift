import Foundation

/// Étages, pièces et pièce de chaque lumière : `GET /maison/structure` du relais (contrat v1,
/// `docs/contrat-relais.md`), lu dans les registres de HA avec le jeton de la personne.
public struct StructureMaison: Sendable, Equatable {
    public static let versionContrat = 1

    public struct Etage: Sendable, Equatable, Identifiable {
        public let id: String
        public let nom: String
        public let niveau: Int?
        public let icone: String?
    }

    public struct Piece: Sendable, Equatable, Identifiable {
        public let id: String
        public let nom: String
        public let etage: String?
        public let icone: String?
        public let capteurTemperature: String?
        public let capteurHumidite: String?
    }

    public private(set) var etages: [Etage] = []
    public private(set) var pieces: [Piece] = []
    /// lumière → pièce.
    public private(set) var pieceDe: [String: String] = [:]

    public init() {}

    public init(etages: [Etage], pieces: [Piece], pieceDe: [String: String]) {
        self.etages = etages
        self.pieces = pieces
        self.pieceDe = pieceDe
    }

    /// nil si la réponse n'est pas du contrat v1 (un relais plus récent : l'app garde la liste simple).
    public static func lire(_ v: ValeurJSON) -> StructureMaison? {
        guard v["version"]?.entier == versionContrat else { return nil }
        let etages = (v["etages"]?.liste ?? []).compactMap { e -> Etage? in
            guard let id = e["id"]?.texte, let nom = e["nom"]?.texte else { return nil }
            return Etage(id: id, nom: nom, niveau: e["niveau"]?.entier, icone: e["icone"]?.texte)
        }
        // du plus haut au plus bas, comme HA ; sans niveau : à la fin, par nom
        .sorted { x, y in
            switch (x.niveau, y.niveau) {
            case (let a?, let b?) where a != b: a > b
            case (nil, _?): false
            case (_?, nil): true
            default: x.nom.localizedStandardCompare(y.nom) == .orderedAscending
            }
        }
        let pieces = (v["pieces"]?.liste ?? []).compactMap { p -> Piece? in
            guard let id = p["id"]?.texte, let nom = p["nom"]?.texte else { return nil }
            return Piece(
                id: id, nom: nom, etage: p["etage"]?.texte, icone: p["icone"]?.texte,
                capteurTemperature: p["temperature"]?.texte, capteurHumidite: p["humidite"]?.texte)
        }
        .sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
        var pieceDe: [String: String] = [:]
        for (id, piece) in v["lumieres"]?.objet ?? [:] {
            if let piece = piece.texte { pieceDe[id] = piece }
        }
        return StructureMaison(etages: etages, pieces: pieces, pieceDe: pieceDe)
    }

    public var vide: Bool { pieces.isEmpty }

    /// Les capteurs (température, humidité) des pièces.
    public var capteurs: Set<String> {
        Set(pieces.flatMap { [$0.capteurTemperature, $0.capteurHumidite].compactMap { $0 } })
    }

    /// Ce que l'app garde de la maison : les lumières et les capteurs des pièces.
    public func utile(_ e: EtatEntite) -> Bool { e.domaine == "light" || capteurs.contains(e.id) }

    public func piece(_ id: String) -> Piece? { pieces.first { $0.id == id } }

    /// Les entités d'une pièce, d'un domaine donné.
    public func entites(de piece: String, domaine: String) -> [String] {
        pieceDe.compactMap { $0.value == piece && $0.key.hasPrefix(domaine + ".") ? $0.key : nil }.sorted()
    }
}

/// Une pièce telle que l'app la montre : ses lumières, sa température.
public struct VuePiece: Sendable, Equatable, Identifiable {
    public let piece: StructureMaison.Piece
    /// Les lampes à montrer : les lampes seules ; s'il n'y en a pas, les groupes (Hue ou HA).
    public let lumieres: [EtatEntite]
    /// Toutes les lumières de la pièce, groupes compris (pour l'état d'ensemble).
    public let toutes: [EtatEntite]
    public let temperature: EtatEntite?
    public let humidite: EtatEntite?

    public var id: String { piece.id }

    /// Allumée si au moins une lumière l'est.
    public var allumee: Bool { toutes.contains { $0.etat == "on" } }
    /// Pilotable si au moins une lumière répond.
    public var disponible: Bool { toutes.contains { $0.etat == "on" || $0.etat == "off" } }
    public var nombreAllumees: Int { lumieres.filter { $0.etat == "on" }.count }
}

public struct VueEtage: Sendable, Equatable, Identifiable {
    /// nil : les pièces sans étage.
    public let etage: StructureMaison.Etage?
    public let pieces: [VuePiece]
    public var id: String { etage?.id ?? "_sans_etage" }
}

extension EtatEntite {
    /// Un groupe de lumières (groupe HA ou pièce Hue) : il commande d'autres lampes.
    public var estGroupe: Bool {
        if let l = attributs["entity_id"]?.liste, !l.isEmpty { return true }
        return attributs["is_hue_group"]?.booleen == true
    }

    /// Variateur : luminosité réglable (`supported_color_modes` autre que `onoff`).
    public var variable: Bool {
        guard let modes = attributs["supported_color_modes"]?.liste?.compactMap(\.texte), !modes.isEmpty else {
            return false
        }
        return modes != ["onoff"]
    }

    /// Luminosité en pour cent (0-100), si allumée et variable.
    public var luminosite: Int? {
        guard etat == "on", let b = attributs["brightness"]?.nombre else { return nil }
        return max(1, min(100, Int((b / 255 * 100).rounded())))
    }
}

extension Maison {
    /// Les étages et leurs pièces qui ont au moins une lumière ; les pièces sans étage à la fin.
    public func vue(_ s: StructureMaison) -> [VueEtage] {
        var parEtage: [String?: [VuePiece]] = [:]
        for p in s.pieces {
            let toutes = s.entites(de: p.id, domaine: "light").compactMap { self[$0] }
                .sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
            guard !toutes.isEmpty else { continue }
            let seules = toutes.filter { !$0.estGroupe }
            let vue = VuePiece(
                piece: p, lumieres: seules.isEmpty ? toutes : seules, toutes: toutes,
                temperature: p.capteurTemperature.flatMap { self[$0] },
                humidite: p.capteurHumidite.flatMap { self[$0] })
            let etage = p.etage.flatMap { id in s.etages.contains { $0.id == id } ? id : nil }
            parEtage[etage, default: []].append(vue)
        }
        var vues = s.etages.compactMap { e in parEtage[e.id].map { VueEtage(etage: e, pieces: $0) } }
        if let sans = parEtage[nil] { vues.append(VueEtage(etage: nil, pieces: sans)) }
        return vues
    }
}

/// Allumer ou éteindre toute une pièce (`target: {area_id}`), confirmé quand l'état d'ensemble a suivi.
public struct CommandePiece: Sendable, Equatable {
    public let piece: String
    public let allumer: Bool

    public init(_ vue: VuePiece) {
        piece = vue.piece.id
        allumer = !vue.allumee
    }

    public var message: ValeurJSON {
        [
            "type": "call_service", "domain": "light", "service": .texte(allumer ? "turn_on" : "turn_off"),
            "target": ["area_id": .texte(piece)],
        ]
    }

    public func confirmee(par vue: VuePiece?) -> Bool { vue?.allumee == allumer }
}

/// Régler la luminosité d'une lumière (`brightness_pct`), confirmé par l'état reçu (à 2 % près, arrondis de HA).
public struct CommandeLuminosite: Sendable, Equatable {
    public let entite: String
    public let pourcent: Int

    public init(entite: String, pourcent: Int) {
        self.entite = entite
        self.pourcent = max(1, min(100, pourcent))
    }

    public var message: ValeurJSON {
        [
            "type": "call_service", "domain": "light", "service": "turn_on",
            "target": ["entity_id": .texte(entite)], "service_data": ["brightness_pct": .nombre(Double(pourcent))],
        ]
    }

    public func confirmee(par e: EtatEntite?) -> Bool {
        guard let l = e?.luminosite else { return false }
        return abs(l - pourcent) <= 2
    }
}
