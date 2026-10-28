import Foundation

/// Un tracé SVG (l'attribut `d` d'un `<path>`, SVG 1.1 § 8.3) lu en segments ABSOLUS, prêts à dessiner : les arcs et les
/// quadratiques deviennent des courbes de Bézier cubiques. Pur Foundation (aucun CoreGraphics) : testé aussi sous Linux.
/// Sert aux logos des connecteurs (Simple Icons, viewBox 0 0 24 24) et aux pictogrammes au trait d'Alfred.
public struct TraceSVG: Sendable, Equatable {
    public enum Segment: Sendable, Equatable {
        case deplacer(x: Double, y: Double)
        case ligne(x: Double, y: Double)
        case courbe(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
        case fermer
    }

    public let segments: [Segment]

    /// nil si le tracé est vide ou illisible : commande inconnue, nombre ou drapeau manquant, tracé qui ne commence pas
    /// par M.
    public init?(_ d: String) {
        var lecteur = LecteurTrace(d)
        guard let segments = lecteur.lire(), !segments.isEmpty else { return nil }
        self.segments = segments
    }
}

/// Le lecteur : un balayage des octets (un tracé est en ASCII) et l'état du crayon.
private struct LecteurTrace {
    private typealias Point = (x: Double, y: Double)

    private let octets: [UInt8]
    private var i = 0
    private var segments: [TraceSVG.Segment] = []
    /// Le point courant et le début du sous-tracé (où ramène Z).
    private var courant: Point = (0, 0)
    private var debut: Point = (0, 0)
    /// Le second point de contrôle de la dernière cubique (C, S) ou celui de la dernière quadratique (Q, T) : reflété
    /// par S et T, oublié après toute autre commande.
    private var controleCubique: Point?
    private var controleQuadratique: Point?
    /// Après Z, une commande autre que M commence un sous-tracé au même début : un « deplacer » explicite l'écrit.
    private var apresFermeture = false

    init(_ d: String) { octets = Array(d.utf8) }

    mutating func lire() -> [TraceSVG.Segment]? {
        var premiere = true
        while true {
            sauterSeparateurs()
            guard i < octets.count else { return segments }
            let commande = Character(Unicode.Scalar(octets[i]))
            guard "MmLlHhVvCcSsQqTtAaZz".contains(commande), !premiere || commande == "M" || commande == "m" else {
                return nil
            }
            i += 1
            premiere = false
            if commande == "Z" || commande == "z" {
                fermer()
                continue
            }
            // la commande, puis ses jeux d'arguments répétés tant qu'un nombre suit (après M : des L)
            var actuelle = commande
            repeat {
                guard executer(actuelle) else { return nil }
                if actuelle == "M" { actuelle = "L" }
                if actuelle == "m" { actuelle = "l" }
                sauterSeparateurs()
            } while i < octets.count && Self.debutNombre(octets[i])
        }
    }

    // MARK: - commandes

    private mutating func executer(_ commande: Character) -> Bool {
        let o: Point = commande.isLowercase ? courant : (0, 0)
        switch commande.lowercased() {
        case "m":
            guard let p = point() else { return false }
            deplacer((o.x + p.x, o.y + p.y))
        case "l":
            guard let p = point() else { return false }
            ligne((o.x + p.x, o.y + p.y))
        case "h":
            guard let n = nombre() else { return false }
            ligne((o.x + n, courant.y))
        case "v":
            guard let n = nombre() else { return false }
            ligne((courant.x, o.y + n))
        case "c":
            guard let p1 = point(), let p2 = point(), let p = point() else { return false }
            courbe((o.x + p1.x, o.y + p1.y), (o.x + p2.x, o.y + p2.y), (o.x + p.x, o.y + p.y))
        case "s":
            guard let p2 = point(), let p = point() else { return false }
            courbe(reflet(controleCubique), (o.x + p2.x, o.y + p2.y), (o.x + p.x, o.y + p.y))
        case "q":
            guard let pq = point(), let p = point() else { return false }
            quadratique((o.x + pq.x, o.y + pq.y), (o.x + p.x, o.y + p.y))
        case "t":
            guard let p = point() else { return false }
            quadratique(reflet(controleQuadratique), (o.x + p.x, o.y + p.y))
        case "a":
            guard let rx = nombre(), let ry = nombre(), let rotation = nombre(), let grand = drapeau(),
                let positif = drapeau(), let p = point()
            else { return false }
            arc(rx: rx, ry: ry, rotation: rotation, grand: grand, positif: positif, vers: (o.x + p.x, o.y + p.y))
        default:
            return false
        }
        return true
    }

    /// Le contrôle reflété autour du point courant (S, T) ; le point courant lui-même sans courbe du même genre avant.
    private func reflet(_ controle: Point?) -> Point {
        guard let controle else { return courant }
        return (2 * courant.x - controle.x, 2 * courant.y - controle.y)
    }

    private mutating func deplacer(_ p: Point) {
        segments.append(.deplacer(x: p.x, y: p.y))
        courant = p
        debut = p
        oublierControles()
        apresFermeture = false
    }

    private mutating func ligne(_ p: Point) {
        reprendreApresFermeture()
        segments.append(.ligne(x: p.x, y: p.y))
        courant = p
        oublierControles()
    }

    private mutating func courbe(_ c1: Point, _ c2: Point, _ p: Point) {
        reprendreApresFermeture()
        segments.append(.courbe(x1: c1.x, y1: c1.y, x2: c2.x, y2: c2.y, x: p.x, y: p.y))
        courant = p
        controleCubique = c2
        controleQuadratique = nil
    }

    /// Une quadratique est une cubique exacte : contrôles aux 2/3 vers le point de contrôle commun.
    private mutating func quadratique(_ q: Point, _ p: Point) {
        let o = courant
        courbe(
            (o.x + 2 / 3 * (q.x - o.x), o.y + 2 / 3 * (q.y - o.y)),
            (p.x + 2 / 3 * (q.x - p.x), p.y + 2 / 3 * (q.y - p.y)),
            p)
        controleCubique = nil
        controleQuadratique = q
    }

    private mutating func fermer() {
        segments.append(.fermer)
        courant = debut
        oublierControles()
        apresFermeture = true
    }

    private mutating func reprendreApresFermeture() {
        guard apresFermeture else { return }
        segments.append(.deplacer(x: debut.x, y: debut.y))
        apresFermeture = false
    }

    private mutating func oublierControles() {
        controleCubique = nil
        controleQuadratique = nil
    }

    /// Un arc elliptique (SVG 1.1, annexe F.6) : extrémités égales → rien ; un rayon nul → une ligne ; rayons trop petits
    /// agrandis (F.6.6) ; puis centre et angles (F.6.5), et des cubiques de 90° au plus.
    private mutating func arc(rx: Double, ry: Double, rotation: Double, grand: Bool, positif: Bool, vers p: Point) {
        guard p != courant else { return oublierControles() }
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0 else { return ligne(p) }
        let phi = rotation * .pi / 180
        let (cosPhi, sinPhi) = (cos(phi), sin(phi))
        let dx = (courant.x - p.x) / 2
        let dy = (courant.y - p.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let (rx2, ry2) = (rx * rx, ry * ry)
        let denominateur = rx2 * y1 * y1 + ry2 * x1 * x1
        let radicande = max(0, (rx2 * ry2 - denominateur) / denominateur)
        let coef = (grand != positif ? 1.0 : -1.0) * radicande.squareRoot()
        let cx1 = coef * rx * y1 / ry
        let cy1 = -coef * ry * x1 / rx
        let centre: Point = (
            cosPhi * cx1 - sinPhi * cy1 + (courant.x + p.x) / 2, sinPhi * cx1 + cosPhi * cy1 + (courant.y + p.y) / 2
        )
        let (ux, uy) = ((x1 - cx1) / rx, (y1 - cy1) / ry)
        let (vx, vy) = ((-x1 - cx1) / rx, (-y1 - cy1) / ry)
        let theta = atan2(uy, ux)
        var delta = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !positif && delta > 0 { delta -= 2 * .pi }
        if positif && delta < 0 { delta += 2 * .pi }

        // un point de l'ellipse : le cercle unité étiré, tourné, placé au centre
        func surEllipse(_ c: Double, _ s: Double) -> Point {
            (centre.x + rx * cosPhi * c - ry * sinPhi * s, centre.y + rx * sinPhi * c + ry * cosPhi * s)
        }
        let troncons = max(1, Int((abs(delta) / (.pi / 2) - 1e-9).rounded(.up)))
        let pas = delta / Double(troncons)
        let k = 4 / 3 * tan(pas / 4)
        for n in 0..<troncons {
            let a0 = theta + Double(n) * pas
            let a1 = a0 + pas
            let (c0, s0, c1, s1) = (cos(a0), sin(a0), cos(a1), sin(a1))
            let fin = n == troncons - 1 ? p : surEllipse(c1, s1)
            courbe(surEllipse(c0 - k * s0, s0 + k * c0), surEllipse(c1 + k * s1, s1 - k * c1), fin)
        }
        oublierControles()
    }

    // MARK: - nombres et drapeaux

    private mutating func point() -> Point? {
        guard let x = nombre(), let y = nombre() else { return nil }
        return (x, y)
    }

    /// Un nombre SVG compact : « 1.5.5 » = 1,5 puis 0,5 ; « -1-2 » = -1 puis -2 ; « .5 », « 1e-3 ».
    private mutating func nombre() -> Double? {
        sauterSeparateurs()
        let depart = i
        sauterSigne()
        let entiers = chiffres()
        var decimales = 0
        if i < octets.count, octets[i] == UInt8(ascii: ".") {
            i += 1
            decimales = chiffres()
        }
        guard entiers + decimales > 0 else { return nil }
        if i < octets.count, octets[i] == UInt8(ascii: "e") || octets[i] == UInt8(ascii: "E") {
            i += 1
            sauterSigne()
            guard chiffres() > 0 else { return nil }
        }
        guard let n = Double(String(decoding: octets[depart..<i], as: UTF8.self)), n.isFinite else { return nil }
        return n
    }

    /// Un drapeau d'arc : un seul caractère, « 0 » ou « 1 », souvent collé à la suite (« a1 1 0 0112 0 »).
    private mutating func drapeau() -> Bool? {
        sauterSeparateurs()
        guard i < octets.count, octets[i] == UInt8(ascii: "0") || octets[i] == UInt8(ascii: "1") else { return nil }
        i += 1
        return octets[i - 1] == UInt8(ascii: "1")
    }

    private mutating func sauterSigne() {
        if i < octets.count, octets[i] == UInt8(ascii: "+") || octets[i] == UInt8(ascii: "-") { i += 1 }
    }

    private mutating func chiffres() -> Int {
        let depart = i
        while i < octets.count, Self.chiffre(octets[i]) { i += 1 }
        return i - depart
    }

    /// Espaces et virgules entre deux valeurs.
    private mutating func sauterSeparateurs() {
        while i < octets.count {
            switch octets[i] {
            case 0x20, 0x09, 0x0A, 0x0D, 0x0C, UInt8(ascii: ","): i += 1
            default: return
            }
        }
    }

    private static func chiffre(_ o: UInt8) -> Bool { o >= UInt8(ascii: "0") && o <= UInt8(ascii: "9") }

    private static func debutNombre(_ o: UInt8) -> Bool {
        chiffre(o) || o == UInt8(ascii: ".") || o == UInt8(ascii: "+") || o == UInt8(ascii: "-")
    }
}
