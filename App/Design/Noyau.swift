import SwiftUI

/// Le noyau d'Alfred : il respire au repos, écoute (arcs bleus qui suivent la voix), réfléchit (arc ambre qui tourne)
/// et parle (ondes champagne au rythme de sa voix). Dessiné à chaque image (jusqu'à 120 Hz sur ProMotion).
/// Avec « Réduire les animations » : aucune rotation ni onde, seule l'intensité change.
struct Noyau: View {
    let phase: Conversation.Phase
    /// Niveau du son (0…1), lu à chaque image : le micro à l'écoute, la voix d'Alfred quand il parle.
    let niveau: () -> Float

    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.colorScheme) private var schema
    /// Le niveau lissé, d'une image à l'autre (une boîte : la modifier ne redessine pas la vue).
    @State private var memoire = Memoire()

    private final class Memoire {
        var niveau: Double = 0
    }

    var body: some View {
        TimelineView(.animation(paused: reduire && phase == .repos)) { contexte in
            Canvas { c, taille in
                let t = contexte.date.timeIntervalSinceReferenceDate
                dessiner(c, taille: taille, t: t)
            }
        }
        .accessibilityHidden(true)
    }

    private var couleur: Color {
        switch phase {
        case .repos: Color(.champagne)
        case .ecoute: Color(.faisceau)
        case .reflexion: Color(.sodium)
        case .reponse: Color(.champagne)
        }
    }

    private func dessiner(_ c: GraphicsContext, taille: CGSize, t: TimeInterval) {
        let cote = min(taille.width, taille.height)
        let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
        let brut = Double(phase == .ecoute || phase == .reponse ? niveau() : 0)
        // lissage : monte vite, retombe doucement (comme le spectre de la console)
        let precedent = memoire.niveau
        let n = brut > precedent ? brut : precedent * 0.86 + brut * 0.14
        memoire.niveau = n

        let respiration = reduire ? 0 : sin(t * 2 * .pi / 4.2) * 0.025
        let rayon = cote * 0.25 * (1 + respiration + n * 0.22)

        // halo
        let halo = Path(
            ellipseIn: CGRect(x: centre.x - rayon * 2, y: centre.y - rayon * 2, width: rayon * 4, height: rayon * 4))
        c.fill(
            halo,
            with: .radialGradient(
                Gradient(colors: [couleur.opacity(0.28 + n * 0.3), couleur.opacity(0)]),
                center: centre, startRadius: rayon * 0.8, endRadius: rayon * 2))

        // anneaux selon la phase
        var anneau = c
        anneau.translateBy(x: centre.x, y: centre.y)
        let r = cote * 0.4
        switch phase {
        case .repos:
            trait(anneau, rayon: r, debut: 0, fin: 360, largeur: 1.2, couleur: Color(.champagne).opacity(0.35))
        case .ecoute:
            for i in 0..<3 {
                let vitesse = reduire ? 0 : [38.0, -26.0, 17.0][i]
                let debut = t * vitesse + Double(i) * 120
                let longueur = 70 + n * 90
                trait(
                    anneau, rayon: r - CGFloat(i) * cote * 0.035, debut: debut, fin: debut + longueur,
                    largeur: 2.2, couleur: Color(.faisceau).opacity(0.9 - Double(i) * 0.22))
            }
        case .reflexion:
            let debut = reduire ? 0 : t * 220
            trait(anneau, rayon: r, debut: debut, fin: debut + 100, largeur: 2.6, couleur: Color(.sodium))
            trait(anneau, rayon: r, debut: 0, fin: 360, largeur: 1, couleur: Color(.sodium).opacity(0.25))
        case .reponse:
            if reduire {
                trait(
                    anneau, rayon: r, debut: 0, fin: 360, largeur: 1.5,
                    couleur: Color(.champagne).opacity(0.4 + n * 0.5))
            } else {
                for i in 0..<3 {
                    let p = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    trait(
                        anneau, rayon: rayon + (r - rayon) * p * 1.2, debut: 0, fin: 360, largeur: 1.5,
                        couleur: Color(.champagne).opacity((1 - p) * (0.35 + n * 0.6)))
                }
            }
        }

        // le noyau : une sphère éclairée en haut à gauche
        let disque = Path(
            ellipseIn: CGRect(x: centre.x - rayon, y: centre.y - rayon, width: rayon * 2, height: rayon * 2))
        let clair = schema == .dark ? Color(white: 1, opacity: 0.95) : Color(white: 1, opacity: 0.9)
        c.fill(
            disque,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: clair, location: 0), .init(color: Color(.champagne), location: 0.45),
                    .init(color: Color(.champagne).mix(with: .black, by: 0.45), location: 1),
                ]),
                center: CGPoint(x: centre.x - rayon * 0.35, y: centre.y - rayon * 0.4),
                startRadius: 0, endRadius: rayon * 1.7))
        if phase != .repos {
            c.stroke(disque, with: .color(couleur.opacity(0.55)), lineWidth: 1)
        }
    }

    private func trait(
        _ c: GraphicsContext, rayon: CGFloat, debut: Double, fin: Double, largeur: CGFloat, couleur: Color
    ) {
        var p = Path()
        p.addArc(center: .zero, radius: rayon, startAngle: .degrees(debut), endAngle: .degrees(fin), clockwise: false)
        c.stroke(p, with: .color(couleur), style: StrokeStyle(lineWidth: largeur, lineCap: .round))
    }
}

#Preview("Phases") {
    VStack(spacing: 24) {
        ForEach([Conversation.Phase.repos, .ecoute, .reflexion, .reponse], id: \.self) { phase in
            Noyau(phase: phase) { 0.4 }.frame(width: 140, height: 140)
        }
    }
    .padding()
    .background(Color(.fond))
}
