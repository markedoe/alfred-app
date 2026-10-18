import Foundation

/// La maison telle que la CONSOLE la montre : `GET /maison/console` du relais (contrat v1, `docs/contrat-relais.md`).
///
/// La console a sa propre roue (des groupes de lumières aux noms courts, avec leurs capteurs), ses jauges et sa
/// météo ; l'app montre exactement les mêmes. Aucun identifiant d'entité n'est écrit dans l'app : ils arrivent ici,
/// comme les mots qui désignent chaque pièce, le mode invités et la voix reconnue (champs facultatifs du contrat v1).
public struct ConsoleMaison: Sendable, Equatable {
    public static let versionContrat = 1

    /// Un secteur de la roue : un groupe de lumières, ses mesures.
    public struct Piece: Sendable, Equatable, Identifiable {
        public let nom: String
        public let etage: String
        public let lumiere: String
        public let temperature: String?
        public let humidite: String?
        public let air: String?
        /// L'expression qui reconnaît la pièce dans une réponse d'Alfred (la console : `ROOM_WORDS`), appliquée au
        /// texte en minuscules ; nil si la pièce n'en a pas.
        public let mots: String?
        public var id: String { lumiere }

        public init(
            nom: String, etage: String, lumiere: String, temperature: String? = nil, humidite: String? = nil,
            air: String? = nil, mots: String? = nil
        ) {
            self.nom = nom
            self.etage = etage
            self.lumiere = lumiere
            self.temperature = temperature
            self.humidite = humidite
            self.air = air
            self.mots = mots
        }
    }

    /// Une pièce mesurée sans lumières (liste « Intérieur »).
    public struct Mesuree: Sendable, Equatable, Identifiable {
        public let nom: String
        public let etage: String
        public let temperature: String?
        public let humidite: String?
        public var id: String { nom + "·" + etage }

        public init(nom: String, etage: String, temperature: String?, humidite: String?) {
            self.nom = nom
            self.etage = etage
            self.temperature = temperature
            self.humidite = humidite
        }
    }

    public struct Jauge: Sendable, Equatable, Identifiable {
        public let entite: String
        /// gpu, pc, maison, jour (affiché en capitales).
        public let libelle: String
        public let unite: String
        public let max: Double
        public var id: String { entite }

        public init(entite: String, libelle: String, unite: String, max: Double) {
            self.entite = entite
            self.libelle = libelle
            self.unite = unite
            self.max = max
        }

        /// Décimales du bandeau (la console : 1 pour les kWh, sinon aucune).
        public var decimalesBandeau: Int { unite == "kWh" ? 1 : 0 }
        /// Décimales du panneau Énergie & système (la console : 2 pour les kWh, sinon aucune).
        public var decimalesPanneau: Int { unite == "kWh" ? 2 : 0 }

        /// Le libellé long du panneau Énergie & système (repris de la console).
        public var description: String {
            switch libelle {
            case "gpu": "GPU · température"
            case "pc": "Ordinateur · puissance"
            case "maison": "Maison · puissance"
            case "jour": "Ordinateur · énergie du jour"
            default: libelle
            }
        }

        /// Remplissage de l'anneau (0…1) ; 0 sans mesure.
        public func fraction(_ valeur: Double?) -> Double {
            guard let valeur, max > 0 else { return 0 }
            return Swift.min(Swift.max(valeur / max, 0), 1)
        }
    }

    public private(set) var pieces: [Piece] = []
    public private(set) var autres: [Mesuree] = []
    public private(set) var jauges: [Jauge] = []
    public private(set) var meteo: String?
    public private(set) var puissance: String?
    /// Le mode invités (`input_boolean`) : tant qu'il est « on », l'historique et le résumé sont masqués.
    public private(set) var invites: String?
    /// La voix reconnue par la maison (un prénom en minuscules, « incertain »…), montrée 8 s à chaque changement.
    public private(set) var voix: String?

    public init() {}

    public init(
        pieces: [Piece], autres: [Mesuree], jauges: [Jauge], meteo: String?, puissance: String?,
        invites: String? = nil, voix: String? = nil
    ) {
        self.pieces = pieces
        self.autres = autres
        self.jauges = jauges
        self.meteo = meteo
        self.puissance = puissance
        self.invites = invites
        self.voix = voix
    }

    /// nil si la réponse n'est pas du contrat v1.
    public static func lire(_ v: ValeurJSON) -> ConsoleMaison? {
        guard v["version"]?.entier == versionContrat else { return nil }
        let pieces = (v["pieces"]?.liste ?? []).compactMap { p -> Piece? in
            guard let nom = p["nom"]?.texte, let lumiere = p["lumiere"]?.texte else { return nil }
            return Piece(
                nom: nom, etage: p["etage"]?.texte ?? "", lumiere: lumiere, temperature: p["temperature"]?.texte,
                humidite: p["humidite"]?.texte, air: p["air"]?.texte, mots: p["mots"]?.texte)
        }
        let autres = (v["autres"]?.liste ?? []).compactMap { p -> Mesuree? in
            guard let nom = p["nom"]?.texte else { return nil }
            return Mesuree(
                nom: nom, etage: p["etage"]?.texte ?? "", temperature: p["temperature"]?.texte,
                humidite: p["humidite"]?.texte)
        }
        let jauges = (v["jauges"]?.liste ?? []).compactMap { j -> Jauge? in
            guard let e = j["entite"]?.texte, let l = j["libelle"]?.texte, let m = j["max"]?.nombre else { return nil }
            return Jauge(entite: e, libelle: l, unite: j["unite"]?.texte ?? "", max: m)
        }
        return ConsoleMaison(
            pieces: pieces, autres: autres, jauges: jauges, meteo: v["meteo"]?.texte, puissance: v["puissance"]?.texte,
            invites: v["invites"]?.texte, voix: v["voix"]?.texte)
    }

    public var vide: Bool { pieces.isEmpty }

    /// Toutes les entités que la console montre (l'app ne garde qu'elles, sur 1 500 et plus).
    public var entites: Set<String> {
        var s = Set(pieces.flatMap { [$0.lumiere, $0.temperature, $0.humidite, $0.air].compactMap { $0 } })
        s.formUnion(autres.flatMap { [$0.temperature, $0.humidite].compactMap { $0 } })
        s.formUnion(jauges.map(\.entite))
        if let meteo { s.insert(meteo) }
        if let puissance { s.insert(puissance) }
        if let invites { s.insert(invites) }
        if let voix { s.insert(voix) }
        return s
    }

    /// Les pièces qu'une réponse d'Alfred nomme, dans l'ordre de la roue (la console : `highlightRooms`). Une expression
    /// illisible est ignorée.
    public func citees(_ texte: String) -> [Piece] {
        let t = texte.lowercased()
        let plage = NSRange(t.startIndex..., in: t)
        return pieces.filter { p in
            guard let mots = p.mots, let rx = try? NSRegularExpression(pattern: mots) else { return false }
            return rx.firstMatch(in: t, range: plage) != nil
        }
    }

    /// L'ordre des étages de la console (du sous-sol au 2e), pour la liste « Intérieur ».
    public static func rang(etage: String) -> Int {
        ["ss": 0, "rdc": 1, "1er": 2, "1-2": 3, "2e": 4][etage] ?? 5
    }

    /// La liste « Intérieur » : toutes les pièces mesurées (de la roue, puis les autres), par étage.
    public var interieur: [Mesuree] {
        let roue = pieces.filter { $0.temperature != nil }.map {
            Mesuree(nom: $0.nom, etage: $0.etage, temperature: $0.temperature, humidite: $0.humidite)
        }
        // tri stable par étage, comme Array.prototype.sort de la console
        return (roue + autres).enumerated()
            .sorted {
                (Self.rang(etage: $0.element.etage), $0.offset) < (Self.rang(etage: $1.element.etage), $1.offset)
            }
            .map(\.element)
    }

    /// « 0 groupe allumé · 14/14 groupes disponibles · 19° à 23.5° dans les pièces mesurées » (la console, au mot près).
    public func resume(_ maison: Maison) -> String {
        let connues = pieces.filter { ["on", "off"].contains(maison[$0.lumiere]?.etat) }
        guard !connues.isEmpty else { return "Mesures indisponibles · En attente de la maison" }
        let n = connues.filter { maison[$0.lumiere]?.etat == "on" }.count
        let s = n > 1 ? "s" : ""
        var texte = "\(n) groupe\(s) allumé\(s) · \(connues.count)/\(pieces.count) groupes disponibles"
        let temps = (pieces.map(\.temperature) + autres.map(\.temperature)).compactMap {
            $0.flatMap { maison[$0]?.nombre }
        }
        if let bas = temps.min(), let haut = temps.max() {
            texte += " · \(Format.valeur(bas, "°", 1)) à \(Format.valeur(haut, "°", 1)) dans les pièces mesurées"
        } else {
            texte += " · Températures indisponibles"
        }
        return texte
    }
}

/// Les nombres comme la console les écrit (`fmt`) : arrondis, sans zéro inutile (19°, 19.5°), « — » sans mesure.
public enum Format {
    public static func valeur(_ v: Double?, _ unite: String = "", _ decimales: Int = 0) -> String {
        guard let v, v.isFinite else { return "—" }
        let p = pow(10, Double(decimales))
        // Math.round de JavaScript : la demie vers le haut (2.5 → 3, -2.5 → -2)
        let arrondi = ((v * p) + 0.5).rounded(.down) / p
        let texte: String
        if arrondi == arrondi.rounded(), abs(arrondi) < 1e15 {
            texte = String(Int(arrondi))
        } else {
            texte = "\(arrondi)"
        }
        return texte + unite
    }

    /// Les 8 points cardinaux de la console (N, NE, E, SE, S, SO, O, NO).
    public static func boussole(_ degres: Double?) -> String {
        guard let degres, degres.isFinite else { return "" }
        let points = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let a = (degres.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return points[Int((a / 45).rounded()) % 8]
    }

    /// L'état d'une `weather.*` en français (la table de la console).
    public static func meteo(_ etat: String) -> String {
        [
            "clear-night": "nuit claire", "sunny": "ensoleillé", "partlycloudy": "partiellement nuageux",
            "cloudy": "nuageux", "rainy": "pluie", "pouring": "forte pluie", "snowy": "neige",
            "snowy-rainy": "neige et pluie", "fog": "brouillard", "windy": "venteux", "windy-variant": "venteux",
            "hail": "grêle", "lightning": "orage", "lightning-rainy": "orage et pluie", "exceptional": "exceptionnel",
        ][etat] ?? etat
    }
}

/// La géométrie de la roue de la console : un secteur par pièce, autour du réacteur (angles en radians, 0 = à droite,
/// sens horaire à l'écran ; le 1er secteur commence en haut).
public struct GeometrieRoue: Sendable, Equatable {
    public struct Secteur: Sendable, Equatable {
        public let debut: Double
        public let fin: Double
        public let interieur: Double
        public let exterieur: Double
        public var milieu: Double { (debut + fin) / 2 }
        public var rayonMoyen: Double { (interieur + exterieur) / 2 }
    }

    public let rayon: Double
    public let secteurs: [Secteur]

    /// `rayon` : celui de la roue (R de la console). Les secteurs vont de 0,60 R (0,66 R pour une grande roue) à 0,98 R.
    public init(nombre: Int, rayon: Double) {
        self.rayon = rayon
        guard nombre > 0 else {
            secteurs = []
            return
        }
        let r0 = rayon * (rayon < 300 ? 0.60 : 0.66)
        let r1 = rayon * 0.98
        let ecart = 0.016
        let pas = 2 * Double.pi / Double(nombre)
        secteurs = (0..<nombre).map { i in
            let a0 = -Double.pi / 2 + Double(i) * pas + ecart
            return Secteur(debut: a0, fin: a0 + pas - ecart * 2, interieur: r0, exterieur: r1)
        }
    }

    /// Le rayon du disque central (le noyau) : 0,16 R, au moins 30.
    public var rayonNoyau: Double { Swift.max(30, rayon * 0.16) }
}
