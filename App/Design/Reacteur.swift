import AlfredKit
import SwiftUI

/// Le réacteur de la console, au centre de la roue : l'anneau incandescent (le son en direct), les rails, les
/// particules, le noyau (l'heure, ou ce qu'Alfred fait), le démarrage et le HUD des actions. Repris de `index.html`
/// (soundRing, reactorRails, reactorAtmosphere, core, ambient, lockPulse, actionHud), mêmes proportions de R.
///
/// Dessiné à chaque image : 30 images/s au repos (comme la console), toutes celles de l'écran pendant une
/// conversation ou une action. Lueur par deux passes additives (`plusLighter`), jamais de flou par image.
/// « Réduire les animations » : ni rotation, ni particules qui dérivent, ni démarrage ; le son reste visible.
struct Reacteur: View {
    let phase: Conversation.Phase
    let enConversation: Bool
    /// Niveau du son (0…1), lu à chaque image : le micro à l'écoute, la voix d'Alfred quand il parle.
    let niveau: () -> Float
    /// Le rayon de la roue (R de la console) ; le réacteur occupe le centre (jusqu'à 0,57 R).
    let rayon: CGFloat
    let action: ActionHUD?
    let connecte: Bool
    /// Une seule colonne étroite (téléphone) : la console allège alors les particules et les traînées.
    let compact: Bool
    /// Début du démarrage (la console : 2,4 s, sans jamais bloquer).
    let debut: Date
    /// Secteurs de la roue (pour le HUD d'une pièce sur grand écran) et celui de l'action ou de la pièce choisie.
    let geometrie: GeometrieRoue?
    let secteurAction: Int?
    let secteurChoisi: Int?
    let confirmeA: Date?
    /// Le sous-titre du démarrage ; nil : l'état du lien (« MAISON CONNECTÉE », « CONNEXION »).
    let sousTitre: String?

    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.animationsCoupees) private var immobile
    @Environment(\.scenePhase) private var scene
    @State private var memoire = Memoire()

    init(
        phase: Conversation.Phase, enConversation: Bool = false, niveau: @escaping () -> Float, rayon: CGFloat,
        action: ActionHUD? = nil, connecte: Bool = true, compact: Bool = true, debut: Date = .now,
        geometrie: GeometrieRoue? = nil, secteurAction: Int? = nil, secteurChoisi: Int? = nil, confirmeA: Date? = nil,
        sousTitre: String? = nil
    ) {
        self.phase = phase
        self.enConversation = enConversation
        self.niveau = niveau
        self.rayon = rayon
        self.action = action
        self.connecte = connecte
        self.compact = compact
        self.debut = debut
        self.geometrie = geometrie
        self.secteurAction = secteurAction
        self.secteurChoisi = secteurChoisi
        self.confirmeA = confirmeA
        self.sousTitre = sousTitre
    }

    /// Ce qui passe d'une image à l'autre (une boîte : la modifier ne redessine pas la vue).
    private final class Memoire {
        var bandes = [Double](repeating: 0, count: 64)
        var energie = 0.0
        var precedente: Date?
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: intervalle, paused: immobile || scene != .active)) { contexte in
            let etat = Etat(date: contexte.date, debut: debut, fige: immobile || reduire)
            Canvas { c, taille in
                dessiner(c, centre: CGPoint(x: taille.width / 2, y: taille.height / 2), etat: etat, date: contexte.date)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 4 images/s si les animations sont réduites, 30 au repos, toutes sinon (comme la console).
    private var intervalle: Double? {
        if reduire { return 0.25 }
        let actif = phase != .repos || enConversation || action != nil
        return actif ? nil : 1.0 / 30
    }

    struct Etat {
        /// Le démarrage de la console : 2,4 s, sans jamais bloquer.
        static let dureeDemarrage = 2.4
        let t: Double
        let demarrage: Double
        let fige: Bool

        init(date: Date, debut: Date, fige: Bool) {
            self.fige = fige
            t = fige ? 0 : date.timeIntervalSinceReferenceDate
            demarrage = fige ? 1 : min(max(date.timeIntervalSince(debut) / Etat.dureeDemarrage, 0), 1)
        }
    }

    // MARK: - dessin

    private func dessiner(_ c: GraphicsContext, centre: CGPoint, etat: Etat, date: Date) {
        let maintenant = Date.now
        let dt = min(0.1, max(0, maintenant.timeIntervalSince(memoire.precedente ?? maintenant)))
        memoire.precedente = maintenant
        let vivant = phase == .ecoute || phase == .reponse
        mettreAJourBandes(vivant: vivant, t: etat.t, dt: dt)
        let moyenne = memoire.bandes.reduce(0, +) / Double(memoire.bandes.count)
        let cible = etat.fige || phase != .reponse ? 0 : min(1, moyenne * 2.5)
        memoire.energie += (cible - memoire.energie) * (1 - exp(-dt * 12))

        let d = Dessin(c: c, centre: centre, rayon: Double(rayon))
        champInterieur(d)
        ambiance(d, etat)
        anneauSonore(d, etat, vivant: vivant)
        rails(d, etat, vivant: vivant)
        atmosphere(d, etat, vivant: vivant)
        noyau(d, etat)
        texteNoyau(d, etat, date: date)
        pulsationDemarrage(d, etat)
        lienCommande(d, etat)
        hudAction(d, etat)
    }

    /// Le spectre de la console vient de l'analyse du son ; l'app n'a que le niveau : chaque bande le suit avec sa
    /// propre vibration (graves plus forts, comme la voix), montée rapide, retombée douce.
    private func mettreAJourBandes(vivant: Bool, t: Double, dt: Double) {
        let n = vivant ? Double(niveau()) : 0
        for k in memoire.bandes.indices {
            let u = Double(k) / Double(memoire.bandes.count - 1)
            let vibration = 0.72 + 0.28 * sin(t * 8.3 + Double(k) * 0.9) * sin(t * 3.1 + Double(k) * 0.37)
            let cible = min(1, max(0, n * (1.25 - 0.9 * u) * vibration * 1.5))
            let actuelle = memoire.bandes[k]
            memoire.bandes[k] = cible > actuelle ? cible : actuelle + (cible - actuelle) * min(1, dt * 7)
        }
    }

    /// Champ intérieur (statique) : grille radiale et cercle discrets.
    private func champInterieur(_ d: Dessin) {
        let couleur = Color(red: 60 / 255, green: 80 / 255, blue: 95 / 255)
        var grille = Path()
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            grille.move(to: d.point(a, d.rayon * 0.16))
            grille.addLine(to: d.point(a, d.rayon * 0.30))
        }
        d.c.stroke(grille, with: .color(couleur.opacity(0.18)), lineWidth: 1)
        d.arc(d.rayon * 0.225, 0, 2 * .pi, couleur.opacity(0.16), 1)
    }

    /// Couronne de graduations qui tourne lentement, et le satellite sur le bord de la roue.
    private func ambiance(_ d: Dessin, _ e: Etat) {
        guard !e.fige, e.demarrage >= 0.55 else { return }
        var c = d.c
        c.opacity = min(1, (e.demarrage - 0.55) / 0.45)
        let rot = e.t * 0.03
        var longues = Path()
        var courtes = Path()
        for i in 0..<72 {
            let a = rot + Double(i) * .pi / 36
            if i % 6 == 0 {
                longues.move(to: d.point(a, d.rayon * 0.535))
                longues.addLine(to: d.point(a, d.rayon * 0.57))
            } else {
                courtes.move(to: d.point(a, d.rayon * 0.535))
                courtes.addLine(to: d.point(a, d.rayon * 0.555))
            }
        }
        c.stroke(longues, with: .color(Console.graduation.opacity(0.5)), lineWidth: 1.4)
        c.stroke(courtes, with: .color(Console.graduation.opacity(0.28)), lineWidth: 1)
        let sa = -e.t * 0.42
        let sr = d.rayon * 0.985
        var trainee = Path()
        trainee.addArc(
            center: d.centre, radius: sr, startAngle: .radians(sa - 0.5), endAngle: .radians(sa), clockwise: false)
        c.stroke(trainee, with: .color(Console.reacteur.opacity(0.35)), lineWidth: 1.5)
        let p = d.point(sa, sr)
        c.fill(
            Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
            with: .color(Console.lueur.opacity(0.95)))
    }

    /// L'anneau incandescent : 120 traits symétriques ; le son en direct, un balayage ambre pendant la réflexion, une
    /// houle légère au repos. Deux passes additives (halo large, trait vif).
    private func anneauSonore(_ d: Dessin, _ e: Etat, vivant: Bool) {
        let n = 120
        let boot = 0.25 + 0.75 * Dessin.sortie(e.demarrage)
        let s = boot * (phase == .ecoute ? 0.94 : 1)
        let r0 = d.rayon * 0.34 * s
        let ecart = d.rayon * 0.16 * s
        let ambre = phase == .reflexion
        let couleur = ambre ? Console.ambre : Console.reacteur
        // traits regroupés par intensité (20 paliers) : quelques chemins par passe au lieu de 240 traits
        var halos: [Int: (Path, Path)] = [:]
        var traits: [Int: (Path, Path)] = [:]
        for i in 0..<n {
            let a = -Double.pi / 2 + Double(i) / Double(n) * 2 * .pi
            let u = Double(i) / Double(n)
            let k = u < 0.5 ? u * 2 : (1 - u) * 2
            var v: Double
            if vivant {
                v = 0.14 + memoire.bandes[Int(k * Double(memoire.bandes.count - 1))] * 0.86
            } else if ambre {
                let balayage = (u - (e.t * 0.34).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(
                    dividingBy: 1)
                v = 0.16 + pow(1 - balayage, 9) * 0.9 + sin(Double(i) * 0.7 + e.t * 5) * 0.05
            } else {
                v = 0.12 + (sin(Double(i) * 0.35 + e.t * 1.25) * 0.5 + 0.5) * 0.16
            }
            v = min(max(v, 0), 1.2)
            let longue = i % 8 == 0
            let longueur = ecart * v * (longue ? 1.18 : 1)
            let palier = Int((v * 20).rounded())
            var (hl, hc) = halos[palier] ?? (Path(), Path())
            var (tl, tc) = traits[palier] ?? (Path(), Path())
            if longue {
                hl.move(to: d.point(a, r0))
                hl.addLine(to: d.point(a, r0 + longueur))
                tl.move(to: d.point(a, r0))
                tl.addLine(to: d.point(a, r0 + longueur))
            } else {
                hc.move(to: d.point(a, r0))
                hc.addLine(to: d.point(a, r0 + longueur))
                tc.move(to: d.point(a, r0))
                tc.addLine(to: d.point(a, r0 + longueur))
            }
            halos[palier] = (hl, hc)
            traits[palier] = (tl, tc)
        }
        var c = d.c
        c.blendMode = .plusLighter
        for (palier, (longues, courtes)) in halos {
            let v = Double(palier) / 20
            let alpha = (0.05 + v * 0.13) * e.demarrage
            c.stroke(longues, with: .color(couleur.opacity(alpha)), lineWidth: 9)
            c.stroke(courtes, with: .color(couleur.opacity(alpha)), lineWidth: 7)
        }
        for (palier, (longues, courtes)) in traits {
            let v = Double(palier) / 20
            let alpha = (0.3 + v * 0.7) * e.demarrage
            c.stroke(longues, with: .color(couleur.opacity(alpha)), lineWidth: 3)
            c.stroke(courtes, with: .color(couleur.opacity(alpha)), lineWidth: 2.2)
        }
        d.arc(r0 - d.rayon * 0.016 * s, 0, 2 * .pi, Console.reacteur.opacity(0.22 * e.demarrage), 1)
        d.arc(r0 + ecart * 1.28, 0, 2 * .pi, Console.reacteur.opacity(0.14 * e.demarrage), 1)
    }

    /// Les rails lumineux : deux couronnes de trois arcs qui tournent en sens contraires et respirent avec la voix.
    private func rails(_ d: Dessin, _ e: Etat, vivant: Bool) {
        guard !e.fige, e.demarrage >= 0.95 else { return }
        let repos = phase == .repos && !enConversation
        let reflexion = phase == .reflexion
        let signal = vivant ? min(1, memoire.bandes.reduce(0, +) / Double(memoire.bandes.count) * 3) : 0
        let souffle =
            repos ? 0.5 + 0.5 * sin(e.t * 0.85) : reflexion ? 0.5 + 0.5 * sin(e.t * 1.5) : signal
        let vitesse = repos ? 1 : reflexion ? 2.2 : phase == .ecoute ? 1.25 : 1.5
        let couleurs: [Color] =
            reflexion
            ? [Color(.sodium), Color(.champagne)]
            : phase == .ecoute ? [Color(.sarcelle), Color(.faisceau)] : [Color(.faisceau), Color(.champagne)]
        var c = d.c
        c.opacity = min(1, (e.demarrage - 0.95) * 20)
        for rail in 0..<2 {
            let rayonRail = d.rayon * ((rail == 1 ? 0.485 : 0.425) + signal * 0.018)
            let rotation = e.t * vitesse * (rail == 1 ? -0.12 : 0.17)
            let couleur = couleurs[rail]
            for i in 0..<3 {
                let debut = rotation + Double(i) * 2 * .pi / 3
                let longueur = 0.34 + souffle * 0.12
                Dessin(c: c, centre: d.centre, rayon: d.rayon).arc(
                    rayonRail, debut, debut + longueur, couleur.opacity(0.045), compact ? 6 : 9, rond: true)
                Dessin(c: c, centre: d.centre, rayon: d.rayon).arc(
                    rayonRail, debut, debut + longueur, couleur.opacity(0.3 + souffle * 0.25), rail == 1 ? 1.5 : 2,
                    rond: true)
                Dessin(c: c, centre: d.centre, rayon: d.rayon).arc(
                    rayonRail, debut + longueur - 0.05, debut + longueur, couleur.opacity(0.9), 2.5, rond: true)
            }
        }
        if repos || reflexion {
            let duree = reflexion ? 4.5 : 7
            let cycle = e.t.truncatingRemainder(dividingBy: duree) / duree
            Dessin(c: c, centre: d.centre, rayon: d.rayon).arc(
                d.rayon * (0.405 + cycle * 0.13), 0, 2 * .pi, couleurs[0].opacity(sin(cycle * .pi) * 0.16), 1.2)
        } else if signal > 0.01 {
            Dessin(c: c, centre: d.centre, rayon: d.rayon).arc(
                d.rayon * (0.51 + signal * 0.035), 0, 2 * .pi, couleurs[0].opacity(signal * 0.4), 1 + signal)
        }
    }

    /// Les particules : une sphère de points qui tourne lentement, plus vive avec la voix (budget fixe).
    private func atmosphere(_ d: Dessin, _ e: Etat, vivant: Bool) {
        guard e.demarrage >= 0.55 else { return }
        let pas = compact ? 2 : 1
        let reflexion = phase == .reflexion
        let signal = e.fige || !vivant ? 0 : min(1, memoire.bandes.reduce(0, +) / Double(memoire.bandes.count) * 3)
        let t = e.t
        let lacet = t * 0.13
        let tangage = 0.3 + sin(t * 0.17) * 0.15
        let (cy, sy, cp, sp) = (cos(lacet), sin(lacet), cos(tangage), sin(tangage))
        let couleur =
            reflexion
            ? Color(.sodium) : phase == .ecoute ? Color(.sarcelle) : Color(red: 135 / 255, green: 216 / 255, blue: 1)
        var c = d.c
        c.opacity = min(1, (e.demarrage - 0.55) / 0.45)
        var paliers: [Int: (halo: Path, point: Path, champagne: Path)] = [:]
        for i in stride(from: 0, to: Self.particules.count, by: pas) {
            let p = Self.particules[i]
            let x = p.x * cy + p.z * sy
            let z = p.z * cy - p.x * sy
            let y = p.y * cp - z * sp
            let profondeur = p.y * sp + z * cp
            let perspective = 2.8 / (2.8 - profondeur * 0.45)
            let derive = e.fige ? 1 : 1 + 0.035 * sin(t * 0.75 + p.phase) + signal * 0.13
            let echelle = d.rayon * 0.30 * perspective * derive
            let px = d.centre.x + x * echelle
            let py = d.centre.y + y * echelle
            let devant = (profondeur + 1) / 2
            let eclat = 0.8 + 0.2 * sin(t * 0.8 + p.phase)
            let alpha = (0.18 + devant * 0.62) * eclat
            let taille = (compact ? 0.65 : 0.8) + devant * (compact ? 1.05 : 1.45) + signal * 0.65
            let palier = Int((alpha * 10).rounded())
            var lot = paliers[palier] ?? (Path(), Path(), Path())
            if devant > 0.45 {
                let h = taille * 3.2
                lot.halo.addEllipse(in: CGRect(x: px - h, y: py - h, width: h * 2, height: h * 2))
            }
            let point = CGRect(x: px - taille, y: py - taille, width: taille * 2, height: taille * 2)
            if i % 11 == 0, !vivant, !reflexion {
                lot.champagne.addEllipse(in: point)
            } else {
                lot.point.addEllipse(in: point)
            }
            paliers[palier] = lot
        }
        for (palier, lot) in paliers {
            let alpha = Double(palier) / 10
            c.fill(lot.halo, with: .color(couleur.opacity(alpha * 0.09)))
            c.fill(lot.point, with: .color(couleur.opacity(alpha)))
            c.fill(lot.champagne, with: .color(Color(.champagne).opacity(alpha)))
        }
    }

    /// Une sphère de Fibonacci de 120 points (graine fixe, comme la console).
    private static let particules: [(x: Double, y: Double, z: Double, phase: Double)] = (0..<120).map { i in
        let z = 1 - 2 * (Double(i) + 0.5) / 120
        let angle = Double(i) * 2.399963229728653
        let r = (1 - z * z).squareRoot()
        let coquille = 0.67 + 0.33 * (Double(i * 37 % 101) / 100)
        return (cos(angle) * r * coquille, sin(angle) * r * coquille, z * coquille, Double(i) * 1.73)
    }

    /// Le noyau : halo, arcs, disque sombre bordé, et l'arc de progression (secondes au repos, boucle sinon).
    private func noyau(_ d: Dessin, _ e: Etat) {
        var c = d.c
        c.opacity = min(1, e.demarrage * 1.6)
        let rc = max(30, d.rayon * 0.16)
        let souffle = e.fige ? 0.5 : 0.5 + sin(e.t * 1.4) * 0.5
        let energie = memoire.energie
        let rh = d.rayon * 0.31
        c.fill(
            Path(ellipseIn: CGRect(x: d.centre.x - rh, y: d.centre.y - rh, width: rh * 2, height: rh * 2)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Console.reacteur.opacity(0.13 + energie * 0.2), location: 0),
                    .init(color: Console.reacteur.opacity(0.035 + souffle * 0.025), location: 0.65),
                    .init(color: Console.reacteur.opacity(0), location: 1),
                ]), center: d.centre, startRadius: rc * 0.3, endRadius: rh))
        let dc = Dessin(c: c, centre: d.centre, rayon: d.rayon)
        for i in 0..<3 {
            let angle = Double(i) * 2 * .pi / 3 + e.t * 0.08
            dc.arc(d.rayon * (0.255 + energie * 0.025), angle, angle + 1.35, Console.lueur.opacity(0.35), 1)
            dc.arc(d.rayon * (0.275 + energie * 0.015), -angle, -angle + 0.65, Color(.champagne).opacity(0.4), 2)
        }
        let disque = Path(ellipseIn: CGRect(x: d.centre.x - rc, y: d.centre.y - rc, width: rc * 2, height: rc * 2))
        c.fill(disque, with: .color(Color(red: 5 / 255, green: 8 / 255, blue: 12 / 255).opacity(0.92)))
        c.stroke(
            disque, with: .color(enConversation ? Color(.champagne).opacity(0.85) : Console.graduation.opacity(0.4)),
            lineWidth: enConversation ? 1.8 : 1)
        let progression: Double
        if e.demarrage < 1 {
            progression = Dessin.sortie(e.demarrage)
        } else if phase == .repos && !enConversation {
            progression = Double(Calendar.current.component(.second, from: .now)) / 60
        } else {
            progression = (e.t * 0.5).truncatingRemainder(dividingBy: 1)
        }
        dc.arc(
            rc + 7, -.pi / 2, -.pi / 2 + progression * 2 * .pi,
            (phase == .reflexion ? Console.ambre : Console.reacteur).opacity(0.9), 2.5)
    }

    /// Le texte du noyau, dessiné comme dans la console (une partie du dessin, pas un élément d'accessibilité : l'état
    /// se lit sur « Parler à Alfred » et la ligne d'état, l'heure dans la barre d'état) : « ALFRED » qui s'écrit au
    /// démarrage, puis l'heure, ou ce qu'Alfred fait (PARLEZ, ANALYSE…), et le libellé d'une action en cours.
    private func texteNoyau(_ d: Dessin, _ e: Etat, date: Date) {
        var c = d.c
        let rc = max(30, d.rayon * 0.16)
        let centre = d.centre
        func ecrire(_ texte: String, _ police: Font, _ couleur: Color, dy: Double, largeur: Double) {
            let resolu = c.resolve(Text(texte).font(police).foregroundStyle(couleur))
            let mesure = resolu.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
            guard mesure.width > 0 else { return }
            // comme fillText(…, maxWidth) : un texte trop large est resserré, jamais coupé
            let echelle = min(1, largeur / mesure.width)
            var t = c
            t.translateBy(x: centre.x, y: centre.y + dy)
            t.scaleBy(x: echelle, y: echelle)
            t.draw(resolu, at: .zero, anchor: .center)
        }
        c.opacity = min(1, e.demarrage * 1.6)
        if e.demarrage < 0.95 {
            let n = min(6, max(0, Int((e.demarrage / 0.6 * 6).rounded())))
            ecrire(
                String("ALFRED".prefix(n)), .system(size: rc * 0.34, weight: .medium), Console.lueur, dy: -rc * 0.1,
                largeur: rc * 1.8)
            let k = min(1, max(0, (e.demarrage - 0.62) / 0.25))
            if k > 0 {
                c.opacity = k
                ecrire(
                    sousTitre ?? (connecte ? "MAISON CONNECTÉE" : "CONNEXION"),
                    .system(size: max(8, rc * 0.16), weight: .medium),
                    Color(red: 108 / 255, green: 131 / 255, blue: 150 / 255), dy: rc * 0.42, largeur: rc * 1.8)
            }
        } else if let libelle = libelleNoyau(date) {
            let echec = action.map { $0.visible(a: date) && $0.etat == .echec } ?? false
            ecrire(
                libelle, .system(size: max(9, min(12, rc * 0.38)), weight: .semibold),
                echec ? Console.echec : Console.lueur, dy: 0, largeur: rc * 1.8)
        } else {
            let heure = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            ecrire(
                heure, .system(size: max(16, rc * 0.52), weight: .regular, design: .monospaced),
                Color(red: 230 / 255, green: 242 / 255, blue: 251 / 255), dy: -rc * 0.08, largeur: rc * 1.8)
            if d.rayon > 300 {
                ecrire(
                    "à votre service", .system(size: max(11, rc * 0.19), weight: .semibold), Color(.texteSecondaire),
                    dy: rc * 0.48, largeur: rc * 1.8)
            }
        }
        guard let action, action.visible(a: date) else { return }
        let age = date.timeIntervalSince(action.debut)
        let fin = action.fin.map { date.timeIntervalSince($0) / 2.2 } ?? 0
        c.opacity = e.fige ? 1 : max(0, min(1, age * 5) * (1 - fin))
        let couleur =
            action.etat == .echec ? Console.echec : action.etat == .confirmee ? Console.ambre : Console.lueur
        ecrire(
            action.libelle, .system(size: max(11, min(14, d.rayon * 0.043)), weight: .semibold), couleur,
            dy: d.rayon * 0.205, largeur: d.rayon * 0.5)
    }

    /// Ce que dit le noyau à la place de l'heure (la console : EXÉCUTION, CONFIRMÉ, ÉCHEC, PARLEZ, ANALYSE, RÉPONSE).
    private func libelleNoyau(_ date: Date) -> String? {
        if phase == .repos && !enConversation {
            guard let action, action.visible(a: date) else { return nil }
            switch action.etat {
            case .attente: return "EXÉCUTION"
            case .confirmee: return "CONFIRMÉ"
            case .echec: return "ÉCHEC"
            }
        }
        switch phase {
        case .repos: return "UN INSTANT"
        case .ecoute: return "PARLEZ"
        case .reflexion: return "ANALYSE"
        case .reponse: return "RÉPONSE"
        }
    }

    /// Au verrouillage du démarrage, une onde part de l'anneau.
    private func pulsationDemarrage(_ d: Dessin, _ e: Etat) {
        guard !e.fige, e.demarrage >= 0.82, e.demarrage < 1 else { return }
        let k = (e.demarrage - 0.82) / 0.18
        d.arc(d.rayon * (0.5 + k * 0.6), 0, 2 * .pi, Console.lueur.opacity((1 - k) * 0.55), 2 + (1 - k) * 4)
    }

    /// Grand écran : le trait champagne vers la pièce choisie, et l'onde ambre quand la maison confirme.
    private func lienCommande(_ d: Dessin, _ e: Etat) {
        guard !compact, let g = geometrie, let i = secteurChoisi, g.secteurs.indices.contains(i) else { return }
        let s = g.secteurs[i]
        d.ligne(s.milieu, d.rayon * 0.51, s.interieur - 5, Color(.champagne).opacity(0.65), 1)
        if let confirmeA, !e.fige {
            let k = Date.now.timeIntervalSince(confirmeA) / 1.1
            if k >= 0, k < 1 { d.arc(d.rayon * (0.55 + k * 0.48), s.debut, s.fin, Console.ambre.opacity(1 - k), 3) }
        }
    }

    /// Le HUD d'une action : quatre crochets qui se referment sur le noyau, la pièce visée (grand écran), des paquets
    /// qui partent vers elle, et une pulsation segmentée réservée à une VRAIE confirmation de la maison.
    private func hudAction(_ d: Dessin, _ e: Etat) {
        guard let action, action.visible(a: .now) else { return }
        let age = Date.now.timeIntervalSince(action.debut)
        let fin = action.fin.map { Date.now.timeIntervalSince($0) / 2.2 } ?? 0
        let alpha = e.fige ? 1 : min(1, age * 5) * (1 - fin)
        let couleur = action.etat == .echec ? Console.echec : action.etat == .confirmee ? Console.ambre : Console.lueur
        var c = d.c
        c.opacity = max(0, alpha)
        let dc = Dessin(c: c, centre: d.centre, rayon: d.rayon)
        let saisie = e.fige ? 0 : max(0, 1 - age / 0.36)
        let demi = d.rayon * (0.29 + saisie * 0.045)
        let coin = d.rayon * 0.055
        var crochets = Path()
        for x in [-1.0, 1.0] {
            for y in [-1.0, 1.0] {
                crochets.move(to: CGPoint(x: d.centre.x + x * (demi - coin), y: d.centre.y + y * demi))
                crochets.addLine(to: CGPoint(x: d.centre.x + x * demi, y: d.centre.y + y * demi))
                crochets.addLine(to: CGPoint(x: d.centre.x + x * demi, y: d.centre.y + y * (demi - coin)))
            }
        }
        c.stroke(crochets, with: .color(couleur), lineWidth: 1.5)
        if !compact, let g = geometrie, let i = secteurAction, g.secteurs.indices.contains(i) {
            let s = g.secteurs[i]
            dc.arc(s.exterieur + 4, s.debut + 0.025, s.fin - 0.025, couleur, 2.5)
            dc.ligne(s.debut + 0.015, s.interieur, s.exterieur, couleur, 1.5)
            dc.ligne(s.fin - 0.015, s.interieur, s.exterieur, couleur, 1.5)
            if !e.fige, action.fin == nil {
                for j in 0..<3 {
                    let k = (age * 1.15 + Double(j) / 3).truncatingRemainder(dividingBy: 1)
                    let r = d.rayon * 0.39 + k * (s.interieur - d.rayon * 0.39)
                    dc.ligne(s.milieu, r, r + d.rayon * 0.025, couleur, 2)
                }
            }
        }
        if action.etat == .confirmee, !e.fige {
            let r = d.rayon * (0.33 + min(1, fin * 2) * 0.25)
            for j in 0..<8 {
                dc.arc(
                    r, Double(j) * .pi / 4 + 0.04, Double(j + 1) * .pi / 4 - 0.04,
                    Console.ambre.opacity(max(0, 1 - fin * 2)), 2)
            }
        }
    }
}

/// Les gestes de dessin de la console (`arc`, `radial`) sur un contexte SwiftUI.
private struct Dessin {
    let c: GraphicsContext
    let centre: CGPoint
    let rayon: Double

    func point(_ a: Double, _ r: Double) -> CGPoint {
        CGPoint(x: centre.x + cos(a) * r, y: centre.y + sin(a) * r)
    }

    func arc(_ r: Double, _ a0: Double, _ a1: Double, _ couleur: Color, _ largeur: Double, rond: Bool = false) {
        var p = Path()
        p.addArc(center: centre, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
        c.stroke(p, with: .color(couleur), style: StrokeStyle(lineWidth: largeur, lineCap: rond ? .round : .butt))
    }

    func ligne(_ a: Double, _ r0: Double, _ r1: Double, _ couleur: Color, _ largeur: Double) {
        var p = Path()
        p.move(to: point(a, r0))
        p.addLine(to: point(a, r1))
        c.stroke(p, with: .color(couleur), lineWidth: largeur)
    }

    /// easeOut de la console (cubique).
    static func sortie(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }
}
