import AlfredKit
import SwiftUI

/// La roue de la console : un secteur épais par pièce (nom, température), ambre quand la lumière est allumée, autour
/// du réacteur. Toucher un secteur ouvre la pièce ; toucher le noyau ouvre la conversation.
///
/// Chaque secteur est une vraie forme : la zone sensible EST le secteur (comme les formes SVG de la console), un
/// élément VoiceOver par pièce, et ses animations sont natives (apparition en cascade, attente, confirmation).
struct Roue: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Binding var choisi: String?
    let rayon: CGFloat
    let compact: Bool
    /// Le démarrage de la console : une fois par ouverture, pas à chaque retour sur la vue des pièces.
    let debut: Date
    let parler: () -> Void
    @State private var apparue = false
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.animationsCoupees) private var immobile

    init(
        choisi: Binding<String?>, rayon: CGFloat, compact: Bool = true, debut: Date, parler: @escaping () -> Void
    ) {
        _choisi = choisi
        self.rayon = rayon
        self.compact = compact
        self.debut = debut
        self.parler = parler
    }

    var body: some View {
        let secteurs = alfred.secteurs
        let g = GeometrieRoue(nombre: secteurs.count, rayon: Double(rayon))
        ZStack {
            CadreRoue(rayon: rayon)
            ForEach(Array(secteurs.enumerated()), id: \.element.id) { i, s in
                if g.secteurs.indices.contains(i) {
                    Plaque(
                        secteur: s, forme: g.secteurs[i], rayon: rayon, nombre: secteurs.count,
                        choisi: choisi == s.id, enAttente: alfred.enCours(s.id), mouvement: alfred.mouvements[s.id]
                    ) {
                        choisi = s.id
                    }
                    .opacity(apparue ? 1 : 0)
                    .animation(
                        reduire || immobile ? nil : .easeOut(duration: 0.53).delay(0.43 + Double(i) * 0.077),
                        value: apparue)
                }
            }
            Reacteur(
                phase: conversation.phaseAffichee, enConversation: conversation.enConversation,
                niveau: { conversation.phase == .reponse ? conversation.niveauVoix : conversation.niveauMicro },
                rayon: rayon, action: alfred.action, connecte: alfred.estPret, compact: compact, debut: debut,
                geometrie: g, secteurAction: secteurs.firstIndex { $0.id == alfred.action?.secteur },
                secteurChoisi: secteurs.firstIndex { $0.id == choisi },
                confirmeA: alfred.action?.etat == .confirmee && alfred.action?.secteur == choisi
                    ? alfred.action?.fin : nil)
            BoutonNoyau(rayon: rayon, parler: parler)
        }
        .frame(width: rayon * 2, height: rayon * 2)
        .onAppear {
            // démarrage déjà joué : les secteurs sont là tout de suite
            var t = Transaction()
            t.disablesAnimations = Date.now.timeIntervalSince(debut) > Reacteur.Etat.dureeDemarrage
            withTransaction(t) { apparue = true }
        }
    }
}

/// Le cadre fixe sous les secteurs : couronne brisée et amas de graduations (graine fixe), dessiné une fois par taille.
private struct CadreRoue: View {
    let rayon: CGFloat

    var body: some View {
        Canvas { c, taille in
            let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
            let r = Double(rayon)
            func arc(_ r: Double, _ a0: Double, _ a1: Double, _ couleur: Color, _ largeur: Double) {
                var p = Path()
                p.addArc(center: centre, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                c.stroke(p, with: .color(couleur), lineWidth: largeur)
            }
            arc(r * 0.985, 0, 2 * .pi, Color(red: 60 / 255, green: 78 / 255, blue: 92 / 255).opacity(0.35), 1)
            arc(r * 0.965, -1.9, -0.55, Console.graduation.opacity(0.5), 3)
            arc(r * 0.965, 1.25, 2.45, Console.graduation.opacity(0.32), 3)
            var graine: UInt32 = 7
            func hasard() -> Double {
                graine = (graine &* 1_103_515_245 &+ 12345) & 0x7fff_ffff
                return Double(graine) / Double(0x7fff_ffff)
            }
            var traits = Path()
            for _ in 0..<40 {
                let a = hasard() * 2 * .pi
                let n = 2 + Int(hasard() * 4)
                for k in 0..<n {
                    let ak = a + Double(k) * 0.011
                    let r1 = r * (0.945 + 0.008 + hasard() * 0.014)
                    traits.move(to: CGPoint(x: centre.x + cos(ak) * r * 0.945, y: centre.y + sin(ak) * r * 0.945))
                    traits.addLine(to: CGPoint(x: centre.x + cos(ak) * r1, y: centre.y + sin(ak) * r1))
                }
            }
            c.stroke(
                traits, with: .color(Color(red: 150 / 255, green: 175 / 255, blue: 195 / 255).opacity(0.5)),
                lineWidth: 1.4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// La forme d'un secteur (couronne entre deux rayons, entre deux angles), dans le carré de la roue.
struct FormeSecteur: Shape {
    let debut: Double
    let fin: Double
    let interieur: Double
    let exterieur: Double

    init(_ s: GeometrieRoue.Secteur) {
        debut = s.debut
        fin = s.fin
        interieur = s.interieur
        exterieur = s.exterieur
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: exterieur, startAngle: .radians(debut), endAngle: .radians(fin), clockwise: false)
        p.addArc(center: c, radius: interieur, startAngle: .radians(fin), endAngle: .radians(debut), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Un secteur de la roue, comme `plates()` de la console : face en dégradé, bord extrudé, liseré, et l'ambre d'une
/// pièce allumée. Le dessin couvre le carré de la roue ; la cible (et le cadre VoiceOver) est le secteur seul.
private struct Plaque: View {
    let secteur: Secteur
    let forme: GeometrieRoue.Secteur
    let rayon: CGFloat
    let nombre: Int
    let choisi: Bool
    let enAttente: Bool
    /// Le dernier mouvement du secteur : sa lumière a changé (d'ici, d'un interrupteur, d'Alfred), ou Alfred l'a nommé ;
    /// il bondit vers l'extérieur s'il est allumé, vers l'intérieur sinon (la console : `animateRoom`).
    let mouvement: Mouvement?
    let ouvrir: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.animationsCoupees) private var immobile
    @State private var marche: CGFloat = 0
    @State private var bonds = 0

    var body: some View {
        let allume = secteur.allumee
        let f = FormeSecteur(forme)
        let carre = CGRect(x: 0, y: 0, width: rayon * 2, height: rayon * 2)
        let boite = f.path(in: carre).boundingRect
        // le bond : vers l'extérieur si la pièce est allumée, vers l'intérieur sinon
        let milieu = forme.milieu
        let amplitude = Double(min(14, rayon * 0.045)) * ((mouvement?.allume ?? allume) ? 1 : -0.65)
        ZStack {
            Group {
                // bord extrudé (5 pt plus bas)
                f.fill(Color(red: 2 / 255, green: 6 / 255, blue: 11 / 255))
                    .overlay(f.stroke(allume ? Self.bordAllume : Self.bordEteint, lineWidth: 2))
                    .offset(y: 5)
                f.fill(face(allume))
                f.stroke(allume ? Console.ambre.opacity(0.9) : Self.contour.opacity(0.9), lineWidth: 2)
                    .shadow(color: allume ? Console.ambre.opacity(0.45) : .clear, radius: 8)
                Habillage(secteur: secteur, forme: forme, rayon: rayon, nombre: nombre, choisi: choisi)
                if choisi {
                    ArcSecteur(rayon: forme.exterieur + 4, debut: forme.debut, fin: forme.fin)
                        .stroke(Color(.champagne), lineWidth: 3)
                }
                if enAttente {
                    f.stroke(Color(.sodium), style: StrokeStyle(lineWidth: 2, dash: [7, 5], dashPhase: marche))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Button(action: ouvrir) { Color.clear }
                .buttonStyle(StyleSecteur(forme: FormeDecalee(forme: forme, rayon: rayon, origine: boite.origin)))
                .frame(width: boite.width, height: boite.height)
                .position(x: boite.midX, y: boite.midY)
                .accessibilityLabel(secteur.nomCourant)
                .accessibilityValue(valeur)
                .accessibilityHint("Ouvre la pièce")
                .accessibilityAddTraits(choisi ? .isSelected : [])
                .accessibilityIdentifier("piece-" + secteur.nomCourant)
        }
        .frame(width: rayon * 2, height: rayon * 2)
        .keyframeAnimator(initialValue: 0.0, trigger: bonds) { vue, k in
            vue.offset(x: cos(milieu) * amplitude * k, y: sin(milieu) * amplitude * k)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.22)
                CubicKeyframe(0, duration: 0.56)
            }
        }
        .onChange(of: mouvement) { _, m in
            if m != nil, !reduire, !immobile { bonds += 1 }
        }
        .onChange(of: enAttente, initial: true) { _, attente in
            guard attente, !reduire, !immobile else { return }
            marche = 0
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { marche = -24 }
        }
    }

    private static let bordAllume = Color(red: 101 / 255, green: 73 / 255, blue: 35 / 255)
    private static let bordEteint = Color(red: 33 / 255, green: 50 / 255, blue: 66 / 255)
    private static let contour = Color(red: 74 / 255, green: 96 / 255, blue: 112 / 255)

    private func face(_ allume: Bool) -> LinearGradient {
        let couleurs: [Color] =
            allume
            ? [
                Color(red: 102 / 255, green: 80 / 255, blue: 50 / 255),
                Color(red: 59 / 255, green: 46 / 255, blue: 32 / 255),
                Color(red: 36 / 255, green: 30 / 255, blue: 24 / 255),
                Color(red: 23 / 255, green: 20 / 255, blue: 15 / 255),
            ]
            : [
                Color(red: 49 / 255, green: 73 / 255, blue: 91 / 255),
                Color(red: 27 / 255, green: 43 / 255, blue: 57 / 255),
                Color(red: 14 / 255, green: 25 / 255, blue: 36 / 255),
                Color(red: 8 / 255, green: 15 / 255, blue: 24 / 255),
            ]
        // le dégradé de la console est vertical, centré sur le secteur, sur ± 0,22 R
        let cy = 0.5 + sin(forme.milieu) * forme.rayonMoyen / (2 * Double(rayon))
        let e = 0.22 / 2
        return LinearGradient(
            stops: [
                .init(color: couleurs[0], location: 0), .init(color: couleurs[1], location: 0.16),
                .init(color: couleurs[2], location: 0.55), .init(color: couleurs[3], location: 1),
            ], startPoint: UnitPoint(x: 0.5, y: cy - e), endPoint: UnitPoint(x: 0.5, y: cy + e))
    }

    private var valeur: String {
        var parties = [
            enAttente
                ? "commande envoyée, confirmation attendue"
                : secteur.allumee ? "allumée" : secteur.disponible ? "éteinte" : "indisponible"
        ]
        if let t = secteur.temperature?.valeur { parties.append(Format.valeur(t, " degrés", 1)) }
        return parties.joined(separator: ", ")
    }
}

/// Le secteur dans son propre cadre (la boîte qui l'entoure) : la cible exacte du toucher.
private struct FormeDecalee: Shape {
    let forme: GeometrieRoue.Secteur
    let rayon: CGFloat
    let origine: CGPoint

    func path(in rect: CGRect) -> Path {
        FormeSecteur(forme).path(in: CGRect(x: -origine.x, y: -origine.y, width: rayon * 2, height: rayon * 2))
    }
}

/// Le toucher d'un secteur : il s'éclaire du faisceau (le survol de la console).
private struct StyleSecteur: ButtonStyle {
    let forme: FormeDecalee

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(forme.fill(Color(.faisceau).opacity(configuration.isPressed ? 0.18 : 0)))
            .contentShape(forme)
    }
}

/// Un arc seul (le liseré, la sélection).
private struct ArcSecteur: Shape {
    let rayon: Double
    let debut: Double
    let fin: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: rayon, startAngle: .radians(debut),
            endAngle: .radians(fin), clockwise: false)
        return p
    }
}

/// L'habillage d'un secteur, dessiné comme dans la console (`plates()`) : ombre intérieure, arête claire à gauche,
/// arête sombre à droite, filet extérieur, puis le nom (en capitales, sur deux lignes si besoin) et la température.
/// Le texte fait partie du dessin, comme dans la console ; la pièce, son état et sa température se lisent sur le
/// bouton du secteur (VoiceOver).
private struct Habillage: View {
    let secteur: Secteur
    let forme: GeometrieRoue.Secteur
    let rayon: CGFloat
    let nombre: Int
    let choisi: Bool

    var body: some View {
        Canvas { c, taille in
            let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
            let allume = secteur.allumee
            func arc(_ r: Double, _ a0: Double, _ a1: Double, _ couleur: Color, _ largeur: Double) {
                var p = Path()
                p.addArc(center: centre, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                c.stroke(p, with: .color(couleur), lineWidth: largeur)
            }
            func trait(_ a: Double, _ r0: Double, _ r1: Double, _ couleur: Color, _ largeur: Double) {
                var p = Path()
                p.move(to: CGPoint(x: centre.x + cos(a) * r0, y: centre.y + sin(a) * r0))
                p.addLine(to: CGPoint(x: centre.x + cos(a) * r1, y: centre.y + sin(a) * r1))
                c.stroke(p, with: .color(couleur), lineWidth: largeur)
            }
            let s = forme
            arc(s.interieur + 2, s.debut + 0.012, s.fin - 0.012, .black.opacity(0.75), 3)
            trait(
                s.debut + 0.008, s.interieur + 3, s.exterieur - 3,
                allume
                    ? Color(red: 185 / 255, green: 154 / 255, blue: 102 / 255)
                    : Color(red: 110 / 255, green: 137 / 255, blue: 154 / 255), 1)
            trait(s.fin - 0.008, s.interieur + 3, s.exterieur - 3, .black.opacity(0.65), 2)
            arc(
                s.exterieur - 3, s.debut + 0.01, s.fin - 0.01,
                allume ? Console.ambre.opacity(0.6) : Console.reacteur.opacity(0.28), 2)

            // le nom et la température, comme la console : taille selon R, retour à la ligne par mots
            let petit = rayon < 300
            let fs: CGFloat = petit ? max(10, (rayon * 0.058).rounded()) : 13
            let k = fs / 13
            let largeur: CGFloat = max(
                petit ? 40 : 56, 2 * s.rayonMoyen * sin(.pi / Double(max(nombre, 1))) - (petit ? 8 : 14))
            let tx: CGFloat = centre.x + cos(s.milieu) * s.rayonMoyen
            let ty: CGFloat = centre.y + sin(s.milieu) * s.rayonMoyen
            let couleurNom =
                choisi
                ? Color(red: 1, green: 243 / 255, blue: 217 / 255)
                : allume
                    ? Color(red: 1, green: 211 / 255, blue: 148 / 255)
                    : Color(red: 200 / 255, green: 213 / 255, blue: 224 / 255)
            let police = Font.system(size: fs, weight: .bold)
            func resoudre(_ texte: String, _ police: Font, _ couleur: Color) -> GraphicsContext.ResolvedText {
                c.resolve(Text(texte).font(police).foregroundStyle(couleur))
            }
            func longueur(_ texte: String) -> CGFloat {
                resoudre(texte, police, couleurNom).measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
                    .width
            }
            var lignes = [""]
            for mot in secteur.nom.split(separator: " ") {
                let essai = (lignes[lignes.count - 1] + " " + mot).trimmingCharacters(in: .whitespaces)
                if !lignes[lignes.count - 1].isEmpty, longueur(essai) > largeur {
                    lignes.append(String(mot))
                } else {
                    lignes[lignes.count - 1] = essai
                }
            }
            func ecrire(_ r: GraphicsContext.ResolvedText, x: CGFloat, y: CGFloat) {
                let w = r.measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).width
                var t = c
                t.translateBy(x: x, y: y)
                if w > largeur { t.scaleBy(x: largeur / w, y: 1) }  // fillText(…, maxWidth) : resserré, jamais coupé
                t.draw(r, at: .zero, anchor: .center)
            }
            let n = CGFloat(lignes.count - 1)
            for (j, ligne) in lignes.enumerated() {
                ecrire(resoudre(ligne, police, couleurNom), x: tx, y: ty - 8 * k - n * 8 * k + CGFloat(j) * 15 * k)
            }
            ecrire(
                resoudre(
                    Format.valeur(secteur.temperature?.valeur, "°", 1),
                    .system(size: fs, weight: .semibold, design: .monospaced),
                    Color(red: 179 / 255, green: 203 / 255, blue: 220 / 255)),
                x: tx, y: ty + 9 * k + n * 7 * k)
        }
        .allowsHitTesting(false)
    }
}

/// Le noyau, touchable : parler à Alfred, terminer la conversation, ou faire taire Alfred (la cible de la console :
/// 0,3 R ; ses règles : `voiceAction`, désactivé pendant la réflexion hors conversation).
private struct BoutonNoyau: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    let rayon: CGFloat
    let parler: () -> Void

    var body: some View {
        Button(action: parler) {
            Circle().fill(.clear).frame(width: rayon * 0.6, height: rayon * 0.6).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!conversation.enConversation && (!alfred.estPret || conversation.phase == .reflexion))
        .accessibilityLabel(libelle)
        // VoiceOver se tait quand le micro s'ouvre (sinon le micro l'entend)
        .accessibilityAddTraits(ouvreLeMicro ? .startsMediaSession : [])
        .accessibilityIdentifier("noyau")
    }

    private var ouvreLeMicro: Bool { !conversation.enConversation && conversation.phase == .repos }

    private var libelle: String {
        if conversation.enConversation { return "Terminer la conversation" }
        return conversation.phase == .reponse ? "Interrompre Alfred" : "Parler à Alfred"
    }
}
