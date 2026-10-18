import SwiftUI

/// La console d'Alfred (« Manor Command »), en natif : ses couleurs, ses textes, ses panneaux et ses boutons, repris
/// de `manor.css` valeur par valeur. L'app est sombre seulement, comme la console.
enum Console {
    // MARK: couleurs de la console qui n'ont pas de jeton (dégradés, bordures, états)

    /// L'en-tête et le bas (#08111a).
    static let bandeau = Color(red: 8 / 255, green: 17 / 255, blue: 26 / 255)
    /// Un bouton (#142638) ; enfoncé (#29506d).
    static let bouton = Color(red: 20 / 255, green: 38 / 255, blue: 56 / 255)
    static let boutonEnfonce = Color(red: 41 / 255, green: 80 / 255, blue: 109 / 255)
    /// Le bouton principal (#143850, texte #f1faff).
    static let boutonPrincipal = Color(red: 20 / 255, green: 56 / 255, blue: 80 / 255)
    static let textePrincipal = Color(red: 241 / 255, green: 250 / 255, blue: 1)
    /// Le bouton pendant une conversation (#3a2f1c, texte #ffe9c4).
    static let boutonSession = Color(red: 58 / 255, green: 47 / 255, blue: 28 / 255)
    static let texteSession = Color(red: 1, green: 233 / 255, blue: 196 / 255)
    /// Un bouton désactivé (#18222c, bordure #425261, texte #b1bec8).
    static let boutonInactif = Color(red: 24 / 255, green: 34 / 255, blue: 44 / 255)
    static let bordureInactive = Color(red: 66 / 255, green: 82 / 255, blue: 97 / 255)
    static let texteInactif = Color(red: 177 / 255, green: 190 / 255, blue: 200 / 255)
    /// Les cartes flottantes (#101f2f) et leur bordure (#577186).
    static let carte = Color(red: 16 / 255, green: 31 / 255, blue: 47 / 255)
    static let bordureCarte = Color(red: 87 / 255, green: 113 / 255, blue: 134 / 255)
    /// Le fond d'une mesure (#08121d).
    static let caseMesure = Color(red: 8 / 255, green: 18 / 255, blue: 29 / 255)
    /// La jauge vide (#2a3f50).
    static let jaugeVide = Color(red: 42 / 255, green: 63 / 255, blue: 80 / 255)
    /// Le bleu du réacteur (63, 184, 255) et sa lueur glacée (191, 230, 255).
    static let reacteur = Color(red: 63 / 255, green: 184 / 255, blue: 1)
    static let lueur = Color(red: 191 / 255, green: 230 / 255, blue: 1)
    /// L'ambre d'une pièce allumée et d'une confirmation (255, 176, 84).
    static let ambre = Color(red: 1, green: 176 / 255, blue: 84 / 255)
    /// Le rouge d'un échec dans le HUD (#ff4d5e).
    static let echec = Color(red: 1, green: 77 / 255, blue: 94 / 255)
    /// Le gris des graduations (120, 150, 170).
    static let graduation = Color(red: 120 / 255, green: 150 / 255, blue: 170 / 255)

    /// Le fond de la console : un halo bleu au centre (#12334a55), sur un dégradé #08111a → #050a10.
    static var fond: some View {
        ZStack {
            LinearGradient(
                colors: [bandeau, Color(.fond)], startPoint: UnitPoint(x: 0.15, y: 0),
                endPoint: UnitPoint(x: 0.85, y: 1))
            EllipticalGradient(
                colors: [Color(red: 18 / 255, green: 51 / 255, blue: 74 / 255).opacity(0.33), .clear],
                center: UnitPoint(x: 0.5, y: 0.45), startRadiusFraction: 0, endRadiusFraction: 0.65)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - textes

extension View {
    /// Un titre de section de la console (h2) : capitales espacées, champagne, suivi d'un trait qui s'efface.
    func titreSection() -> some View { modifier(TitreSection()) }

    /// Une petite étiquette de la console : capitales espacées (.gl, .who, onglets).
    func etiquette(_ couleur: Color = Color(.texteSecondaire), espacement: CGFloat = 1.2) -> some View {
        font(.caption2.weight(.heavy)).tracking(espacement).textCase(.uppercase).foregroundStyle(couleur)
    }
}

private struct TitreSection: ViewModifier {
    func body(content: Content) -> some View {
        HStack(spacing: 12) {
            content
                .font(.footnote.weight(.heavy))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color(.champagne))
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            LinearGradient(colors: [Color(.trait), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: 2)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - panneaux

/// Un panneau de verre de la console : dégradé bleu nuit, bordure, et la petite barre lumineuse en haut à gauche, qui
/// respire au repos, devient sarcelle à l'écoute et ambre pendant la réflexion (comme `.glass::before`).
struct PanneauVerre<Contenu: View>: View {
    let phase: Conversation.Phase
    let energie: Double
    let contenu: Contenu
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.animationsCoupees) private var immobile
    @State private var respire = false

    init(phase: Conversation.Phase = .repos, energie: Double = 0, @ViewBuilder contenu: () -> Contenu) {
        self.phase = phase
        self.energie = energie
        self.contenu = contenu()
    }

    var body: some View {
        contenu
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 18 / 255, green: 35 / 255, blue: 50 / 255).opacity(0.94),
                        Color(red: 11 / 255, green: 22 / 255, blue: 34 / 255).opacity(0.96),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.trait), lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(couleurBarre)
                    .frame(width: 60 + (phase == .reponse ? energie * 80 : 0), height: 3)
                    .opacity(phase == .repos && respire ? 0.45 : 1)
                    .offset(x: 20, y: -1)
                    .accessibilityHidden(true)
            }
            .onAppear {
                guard !reduire, !immobile else { return }
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { respire = true }
            }
    }

    private var couleurBarre: Color {
        switch phase {
        case .ecoute: Color(.sarcelle)
        case .reflexion: Color(.sodium)
        case .repos, .reponse: Color(.faisceau)
        }
    }
}

// MARK: - boutons

/// Un bouton de la console : fond bleu nuit, bordure acier, texte glacé, en gras (650 dans la console, entre le
/// demi-gras et le gras du système : le gras est le plus proche à l'œil, comparé aux captures) ; la variante principale
/// (« Parler à Alfred ») a la bordure du faisceau, la variante « session » est champagne, « alerte » rouge (une action
/// qui défait, comme « Se déconnecter »), « pièce » un bouton ordinaire bordé du faisceau (`#room-action`). Au moins
/// 44 pt de haut.
struct StyleConsole: ButtonStyle {
    enum Genre { case normal, principal, session, sodium, alerte, piece }
    var genre: Genre
    var hauteur: CGFloat
    @Environment(\.isEnabled) private var actif

    init(genre: Genre = .normal, hauteur: CGFloat = 46) {
        self.genre = genre
        self.hauteur = hauteur
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .padding(.vertical, 6)
            .foregroundStyle(actif ? texte : Console.texteInactif)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: max(44, hauteur))
            .background(fond(configuration.isPressed), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    actif ? bordure : Console.bordureInactive, lineWidth: 1.5)
            )
            .contentShape(.rect(cornerRadius: 8))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var texte: Color {
        switch genre {
        case .normal: Color(.glace)
        case .principal: Console.textePrincipal
        case .session: Console.texteSession
        case .sodium: Color(.sodium)
        case .alerte: Color(.alerte)
        case .piece: Color(.glace)
        }
    }

    private var bordure: Color {
        switch genre {
        case .normal: Color(.acier)
        case .principal: Color(.faisceau)
        case .session: Color(.champagne)
        case .sodium: Color(.sodium)
        case .alerte: Color(.alerte)
        case .piece: Color(.faisceau)
        }
    }

    private func fond(_ enfonce: Bool) -> Color {
        guard actif else { return Console.boutonInactif }
        if enfonce { return Console.boutonEnfonce }
        switch genre {
        case .normal, .sodium, .alerte, .piece: return Console.bouton
        case .principal: return Console.boutonPrincipal
        case .session: return Console.boutonSession
        }
    }
}

/// Un bouton-icône carré de la console (réglages, compte) : 44 pt, bordure acier.
struct StyleIcone: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color(.glace))
            .frame(width: 44, height: 44)
            .background(configuration.isPressed ? Console.boutonEnfonce : Console.bouton, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.acier), lineWidth: 1.5))
            .contentShape(.rect(cornerRadius: 8))
    }
}

/// « Bonjour, Monsieur. » / « Bonsoir, Madame. » (l'accueil d'Alfred, selon l'heure).
enum Salutation {
    static func texte(titre: String?, date: Date, calendrier: Calendar = .current) -> String {
        let heure = calendrier.component(.hour, from: date)
        let mot = (5..<18).contains(heure) ? "Bonjour" : "Bonsoir"
        guard let titre, !titre.isEmpty else { return "\(mot)." }
        return "\(mot), \(titre)."
    }
}
