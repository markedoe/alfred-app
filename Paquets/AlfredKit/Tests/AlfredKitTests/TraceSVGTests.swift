import Foundation
import Testing

@testable import AlfredKit

@Suite("Les tracés SVG")
struct TraceSVGTests {
    typealias Point = (x: Double, y: Double)

    static func segments(_ d: String) throws -> [TraceSVG.Segment] { try #require(TraceSVG(d)).segments }

    /// Les valeurs d'un segment, pour comparer à une tolérance près.
    static func valeurs(_ s: TraceSVG.Segment) -> [Double] {
        switch s {
        case .deplacer(let x, let y): [0, x, y]
        case .ligne(let x, let y): [1, x, y]
        case .courbe(let x1, let y1, let x2, let y2, let x, let y): [2, x1, y1, x2, y2, x, y]
        case .fermer: [3]
        }
    }

    static func proches(_ a: [TraceSVG.Segment], _ b: [TraceSVG.Segment], _ ecart: Double = 1e-9) -> Bool {
        let (va, vb) = (a.map(valeurs), b.map(valeurs))
        return va.count == vb.count
            && zip(va, vb).allSatisfy { u, v in u.count == v.count && zip(u, v).allSatisfy { abs($0 - $1) <= ecart } }
    }

    static func proche(_ p: Point, _ q: Point, _ ecart: Double = 1e-2) -> Bool {
        abs(p.x - q.x) <= ecart && abs(p.y - q.y) <= ecart
    }

    /// Le point d'une courbe au paramètre t, depuis le point de départ `p0`.
    static func bezier(_ p0: Point, _ s: TraceSVG.Segment, _ t: Double) -> Point? {
        guard case .courbe(let x1, let y1, let x2, let y2, let x, let y) = s else { return nil }
        let u = 1 - t
        func f(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
        }
        return (f(p0.x, x1, x2, x), f(p0.y, y1, y2, y))
    }

    static func fin(_ s: TraceSVG.Segment) -> Point? {
        switch s {
        case .deplacer(let x, let y), .ligne(let x, let y), .courbe(_, _, _, _, let x, let y): (x, y)
        case .fermer: nil
        }
    }

    /// Les courbes d'un tracé qui commence par `M` : leur point de départ et la courbe.
    static func courbes(_ segments: [TraceSVG.Segment]) -> [(depart: Point, courbe: TraceSVG.Segment)] {
        var courant: Point = (0, 0)
        var resultat: [(depart: Point, courbe: TraceSVG.Segment)] = []
        for s in segments {
            if case .courbe = s { resultat.append((courant, s)) }
            if let p = fin(s) { courant = p }
        }
        return resultat
    }

    @Test("M et L, absolus et relatifs ; après M, des L implicites ; m relatif au point courant")
    func deplacerEtLigne() throws {
        #expect(try Self.segments("M1 2 L3 4 l1 1") == [.deplacer(x: 1, y: 2), .ligne(x: 3, y: 4), .ligne(x: 4, y: 5)])
        #expect(try Self.segments("M1 2 3 4,5 6") == [.deplacer(x: 1, y: 2), .ligne(x: 3, y: 4), .ligne(x: 5, y: 6)])
        #expect(try Self.segments("m1 2 3 4l1,1") == [.deplacer(x: 1, y: 2), .ligne(x: 4, y: 6), .ligne(x: 5, y: 7)])
        #expect(try Self.segments("M1 2m1 1") == [.deplacer(x: 1, y: 2), .deplacer(x: 2, y: 3)])
        #expect(try Self.segments("M1 2L3 4 5 6") == [.deplacer(x: 1, y: 2), .ligne(x: 3, y: 4), .ligne(x: 5, y: 6)])
    }

    @Test("H et V, absolus et relatifs")
    func horizontaleEtVerticale() throws {
        #expect(
            try Self.segments("M1 2H5h-1V8v1 2") == [
                .deplacer(x: 1, y: 2), .ligne(x: 5, y: 2), .ligne(x: 4, y: 2), .ligne(x: 4, y: 8), .ligne(x: 4, y: 9),
                .ligne(x: 4, y: 11),
            ])
    }

    @Test("C et S : le premier contrôle de S reflète le second de la courbe d'avant, sinon le point courant")
    func cubiques() throws {
        let attendu: [TraceSVG.Segment] = [
            .deplacer(x: 0, y: 0), .courbe(x1: 1, y1: 2, x2: 3, y2: 4, x: 5, y: 6),
            .courbe(x1: 7, y1: 8, x2: 9, y2: 10, x: 11, y: 12),
        ]
        #expect(try Self.segments("M0 0C1 2 3 4 5 6S9 10 11 12") == attendu)
        #expect(try Self.segments("M0 0c1 2 3 4 5 6s4 4 6 6") == attendu)
        #expect(try Self.segments("M0 0C1 2 3 4 5 6 7 8 9 10 11 12").count == 3, "jeux d'arguments répétés")
        #expect(
            try Self.segments("M1 1S3 4 5 6") == [
                .deplacer(x: 1, y: 1), .courbe(x1: 1, y1: 1, x2: 3, y2: 4, x: 5, y: 6),
            ])
        #expect(
            try Self.segments("M0 0Q1 1 2 2S3 4 5 6").last == .courbe(x1: 2, y1: 2, x2: 3, y2: 4, x: 5, y: 6),
            "après une quadratique, S ne reflète rien")
    }

    @Test("Q et T : cubiques exactes (contrôles aux 2/3), reflet du contrôle par T, sinon une droite")
    func quadratiques() throws {
        let attendu: [TraceSVG.Segment] = [
            .deplacer(x: 0, y: 0), .courbe(x1: 2, y1: 2, x2: 4, y2: 2, x: 6, y: 0),
            .courbe(x1: 8, y1: -2, x2: 10, y2: -2, x: 12, y: 0),
        ]
        #expect(Self.proches(try Self.segments("M0 0Q3 3 6 0T12 0"), attendu))
        #expect(Self.proches(try Self.segments("m0 0q3 3 6 0t6 0"), attendu))
        #expect(
            Self.proches(
                try Self.segments("M0 0T6 0"), [.deplacer(x: 0, y: 0), .courbe(x1: 0, y1: 0, x2: 2, y2: 0, x: 6, y: 0)])
        )
        #expect(
            Self.proches(
                try Self.segments("M0 0C1 1 2 2 3 3T6 0"),
                [
                    .deplacer(x: 0, y: 0), .courbe(x1: 1, y1: 1, x2: 2, y2: 2, x: 3, y: 3),
                    .courbe(x1: 3, y1: 3, x2: 4, y2: 2, x: 6, y: 0),
                ]), "après une cubique, T ne reflète rien")
    }

    @Test("Z : retour au début du sous-tracé ; une commande après Z repart de ce début")
    func fermer() throws {
        #expect(
            try Self.segments("M1 1L5 1L5 5Zl1 0") == [
                .deplacer(x: 1, y: 1), .ligne(x: 5, y: 1), .ligne(x: 5, y: 5), .fermer, .deplacer(x: 1, y: 1),
                .ligne(x: 2, y: 1),
            ])
        #expect(
            try Self.segments("M1 1h4zm2 2h1z") == [
                .deplacer(x: 1, y: 1), .ligne(x: 5, y: 1), .fermer, .deplacer(x: 3, y: 3), .ligne(x: 4, y: 3), .fermer,
            ])
        #expect(try Self.segments("M0 0z") == [.deplacer(x: 0, y: 0), .fermer])
    }

    @Test("Nombres compacts : 1.5.5, -1-2, 1e-3, .5, +1, exposant en capitale")
    func nombres() throws {
        #expect(
            Self.proches(
                try Self.segments("M1.5.5L-1-2l1e-3.5E1M+1,+.5"),
                [.deplacer(x: 1.5, y: 0.5), .ligne(x: -1, y: -2), .ligne(x: -0.999, y: 3), .deplacer(x: 1, y: 0.5)]))
        #expect(try Self.segments("M1 2e3") == [.deplacer(x: 1, y: 2000)])
        #expect(try Self.segments("M1.,2.") == [.deplacer(x: 1, y: 2)], "point final sans décimale")
    }

    @Test("Arc : le demi-cercle de l'icône d'alerte passe par (12,5) ; sens inverse par (12,17)")
    func demiCercle() throws {
        let s = try Self.segments("M6 16v-5a6 6 0 0 1 12 0v5l2 2H4z")
        #expect(s.count == 8 && s[1] == .ligne(x: 6, y: 11) && s[4] == .ligne(x: 18, y: 16) && s.last == .fermer)
        let arc = Self.courbes(s)
        #expect(arc.count == 2, "deux tronçons de 90°")
        #expect(Self.fin(arc[1].courbe).map { $0 == (18, 11) } == true, "l'extrémité exacte")
        let sommet = try #require(Self.fin(arc[0].courbe))
        #expect(Self.proche(sommet, (12, 5)))
        for (depart, courbe) in arc {
            let milieu = try #require(Self.bezier(depart, courbe, 0.5))
            #expect(abs(hypot(milieu.x - 12, milieu.y - 11) - 6) < 1e-2, "sur le cercle")
            #expect(milieu.y < 11, "la moitié du haut")
        }
        let inverse = Self.courbes(try Self.segments("M6 11a6 6 0 0 0 12 0"))
        #expect(inverse.count == 2 && Self.fin(inverse[0].courbe).map { Self.proche($0, (12, 17)) } == true)
    }

    @Test("Arc : drapeaux collés (Simple Icons), rayons trop petits agrandis, rayons négatifs")
    func arcCompact() throws {
        let arc = Self.courbes(try Self.segments("M0 0a1 1 0 0112 0"))
        #expect(arc.count == 2 && Self.fin(arc[1].courbe).map { $0 == (12, 0) } == true)
        #expect(Self.fin(arc[0].courbe).map { Self.proche($0, (6, -6)) } == true, "rayon 1 agrandi à 6")
        #expect(Self.proches(try Self.segments("M0 0A-6 -6 0 0 1 12 0"), try Self.segments("M0 0a1 1 0 0112 0")))
        let quart = try Self.segments("M0 0a.5.5 0 01.5.5")
        #expect(quart.count == 2 && Self.fin(quart[1]).map { $0 == (0.5, 0.5) } == true)
    }

    @Test("Arc : grand arc, rotation de l'ellipse, rayon nul (ligne), extrémités égales (rien)")
    func arcs() throws {
        #expect(Self.courbes(try Self.segments("M0 0A10 10 0 0 1 10 0")).count == 1, "60° : un tronçon")
        let grand = Self.courbes(try Self.segments("M0 0A10 10 0 1 1 10 0"))
        #expect(grand.count == 4, "300° : quatre tronçons")
        #expect(Self.fin(grand[1].courbe).map { Self.proche($0, (5, -8.660_254 - 10)) } == true)
        for (depart, courbe) in grand {
            let milieu = try #require(Self.bezier(depart, courbe, 0.5))
            #expect(abs(hypot(milieu.x - 5, milieu.y + 8.660_254) - 10) < 1e-2)
        }
        let tourne = Self.courbes(try Self.segments("M0 0A2 1 90 0 1 0 4"))
        #expect(tourne.count == 2 && Self.fin(tourne[0].courbe).map { Self.proche($0, (1, 2)) } == true)
        #expect(try Self.segments("M0 0A0 5 0 0 1 3 4") == [.deplacer(x: 0, y: 0), .ligne(x: 3, y: 4)])
        #expect(try Self.segments("M1 1A5 5 0 0 1 1 1L2 2") == [.deplacer(x: 1, y: 1), .ligne(x: 2, y: 2)])
    }

    @Test("Illisible ou vide : nil")
    func illisibles() {
        for d in [
            "", "  ", "L1 2", "M1", "M1 2L3", "M1 2X3 4", "M1 2 3e", "M1 2Z3 4", "M1 2A1 1 0 2 1 3 4", "M1 2 é",
            "M1 2L1e999 0", "M . 1", "M1 2C1 2 3",
        ] {
            #expect(TraceSVG(d) == nil, "\(d)")
        }
    }

    @Test("Tous les tracés de l'exemple réel se lisent et restent dans leur cadre de 24 × 24")
    func exempleReel() throws {
        let l = try #require(ListeConnecteurs.lire(ExempleConnecteurs.json))
        #expect(l.tous.count == 15)
        for c in l.tous {
            let segments = try #require(TraceSVG(c.icone.d), "\(c.id)").segments
            #expect(segments.first.map { if case .deplacer = $0 { true } else { false } } == true, "\(c.id)")
            let points = segments.compactMap(Self.fin)
            #expect(points.allSatisfy { (-0.5...24.5).contains($0.x) && (-0.5...24.5).contains($0.y) }, "\(c.id)")
        }
    }
}
