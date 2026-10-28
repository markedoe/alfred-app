import AlfredKit
import SwiftUI

/// Les quatre espaces de la console (28.10, retour d'essai : « oui 4 espaces ») : ALFRED (la console d'avant), MAISON
/// (la maison seule), MOI (documents et notifications), SYSTÈME (connecteurs, réglages, autres systèmes). Au-delà de
/// 1100 pt : un rail à gauche, sous l'en-tête et au-dessus de la barre de la voix ; en dessous : la barre du bas.
enum Espace: String, CaseIterable, Identifiable, Sendable {
    case alfred, maison, moi, systeme

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .alfred: "Alfred"
        case .maison: "Maison"
        case .moi: "Moi"
        case .systeme: "Système"
        }
    }

    /// Par défaut : ALFRED en disposition large, MAISON (la roue) sur téléphone, comme avant.
    static func parDefaut(large: Bool) -> Espace { large ? .alfred : .maison }
}

/// MAISON sur téléphone et iPad à la verticale : Pièces | Environnement.
enum VueMaison: String, CaseIterable, Identifiable, Sendable {
    case pieces, environnement

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .pieces: "Pièces"
        case .environnement: "Environnement"
        }
    }
}

/// L'espace affiché, partagé avec les vues qui y mènent (Notifications de l'en-tête → MOI, pastilles d'état →
/// SYSTÈME). Absent de l'environnement (aperçus, accueil), ces vues ne changent rien.
@Observable @MainActor
final class NavigationConsole {
    var espace: Espace
    var vueMaison = VueMaison.pieces
    /// La partie de la page à montrer en arrivant (« notifications » depuis l'en-tête) ; lue une fois par la page.
    var ancre: String?

    init(espace: Espace) {
        self.espace = espace
    }

    func aller(_ e: Espace, ancre: String? = nil) {
        self.ancre = ancre
        espace = e
    }
}

// MARK: - icônes des espaces

/// Les pictogrammes de la console (`#espaces svg`, 24 × 24, trait de 1,8, bouts ronds), dessinés ici à l'identique.
struct IconeEspace: Shape {
    let espace: Espace

    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        let o = CGPoint(x: r.midX - 12 * k, y: r.midY - 12 * k)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }
        func cercle(_ x: Double, _ y: Double, _ rayon: Double) -> CGRect {
            CGRect(x: o.x + (x - rayon) * k, y: o.y + (y - rayon) * k, width: 2 * rayon * k, height: 2 * rayon * k)
        }
        func carre(_ x: Double, _ y: Double) -> Path {
            Path(
                roundedRect: CGRect(x: o.x + x * k, y: o.y + y * k, width: 7 * k, height: 7 * k), cornerRadius: 1.2 * k)
        }
        var c = Path()
        switch espace {
        case .alfred:
            c.addEllipse(in: cercle(12, 12, 3.2))
            // l'anneau en tirets (3,4 / 2,2) est ajouté par `IconeEspaceVue` : un Shape ne porte pas son tireté
            for (a, b) in [
                ((12.0, 1.8), (12.0, 4.2)), ((12, 19.8), (12, 22.2)), ((1.8, 12), (4.2, 12)), ((19.8, 12), (22.2, 12)),
            ] {
                c.move(to: p(a.0, a.1))
                c.addLine(to: p(b.0, b.1))
            }
        case .maison:
            c.move(to: p(3.5, 11.2))
            c.addLine(to: p(12, 4))
            c.addLine(to: p(20.5, 11.2))
            c.move(to: p(5.8, 9.6))
            c.addLine(to: p(5.8, 20))
            c.addLine(to: p(18.2, 20))
            c.addLine(to: p(18.2, 9.6))
            c.move(to: p(10, 20))
            c.addLine(to: p(10, 14.8))
            c.addLine(to: p(14, 14.8))
            c.addLine(to: p(14, 20))
        case .moi:
            c.addEllipse(in: cercle(12, 8.2, 3.7))
            c.move(to: p(4.6, 20.2))
            c.addCurve(to: p(12, 14.2), control1: p(5.5, 16.3), control2: p(8.5, 14.2))
            c.addCurve(to: p(19.4, 20.2), control1: p(15.5, 14.2), control2: p(18.5, 16.3))
        case .systeme:
            c.addPath(carre(3.5, 3.5))
            c.addPath(carre(13.5, 3.5))
            c.addPath(carre(3.5, 13.5))
            c.move(to: p(17, 13.8))
            c.addLine(to: p(17, 20.2))
            c.move(to: p(13.8, 17))
            c.addLine(to: p(20.2, 17))
        }
        return c
    }
}

/// Le pictogramme d'un espace, au trait de la console ; ALFRED ajoute son anneau en tirets.
struct IconeEspaceVue: View {
    let espace: Espace
    var taille: CGFloat = 22

    var body: some View {
        ZStack {
            IconeEspace(espace: espace)
                .stroke(style: StrokeStyle(lineWidth: 1.8 * taille / 24, lineCap: .round, lineJoin: .round))
            if espace == .alfred {
                Circle()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: 1.8 * taille / 24, lineCap: .round, dash: [3.4 * taille / 24, 2.2 * taille / 24])
                    )
                    .frame(width: 15 * taille / 24, height: 15 * taille / 24)
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

// MARK: - rail (grand écran) et barre du bas (téléphone)

/// Une pastille sur l'espace : MOI = les documents qui demandent une action (sodium) ; SYSTÈME = un service en panne
/// (point rouge).
private struct MarqueEspace: View {
    @Environment(Alfred.self) private var alfred
    let espace: Espace

    var body: some View {
        switch espace {
        case .moi:
            if let n = alfred.annexes?.pastilleDocuments, n > 0 {
                Text("\(n)")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Console.bandeau)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color(.sodium), in: .capsule)
                    .fixedSize()
            }
        case .systeme:
            if alfred.annexes?.etat?.panne == true {
                Circle().fill(Color(.alerte)).frame(width: 9, height: 9)
                    .shadow(color: Color(.alerte), radius: 4)
            }
        default:
            EmptyView()
        }
    }
}

/// Ce que VoiceOver dit d'un espace : son nom, et ce qui l'attend (« Moi, 2 documents à traiter »).
@MainActor
private func libelleEspace(_ e: Espace, _ alfred: Alfred) -> String {
    switch e {
    case .moi:
        let n = alfred.annexes?.pastilleDocuments ?? 0
        return n > 0 ? "Moi, \(n) document\(n > 1 ? "s" : "") à traiter" : "Moi"
    case .systeme:
        return alfred.annexes?.etat?.panne == true ? "Système, un service en panne" : "Système"
    default:
        return e.titre
    }
}

/// Le rail de la console (`#espaces`, au-delà de 1100 pt) : 84 pt de large, les quatre espaces en colonne
/// (pictogramme et mot en capitales), l'actif en champagne sur fond bleu, souligné à gauche d'un trait du faisceau.
struct RailEspaces: View {
    @Environment(Alfred.self) private var alfred
    @Bindable var navigation: NavigationConsole

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Espace.allCases) { e in
                let actif = navigation.espace == e
                Button {
                    navigation.aller(e)
                } label: {
                    VStack(spacing: 6) {
                        IconeEspaceVue(espace: e)
                            .foregroundStyle(actif ? Color(.glace) : Color(.texteSecondaire))
                            .shadow(color: actif ? Color(.faisceau).opacity(0.4) : .clear, radius: 3)
                        Text(e.titre)
                            .font(.caption2.weight(.heavy))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(actif ? Color(.champagne) : Color(.texteSecondaire))
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background(
                        actif ? Color(red: 22 / 255, green: 51 / 255, blue: 74 / 255).opacity(0.55) : .clear,
                        in: .rect(cornerRadius: 8)
                    )
                    .overlay(alignment: .topTrailing) { MarqueEspace(espace: e).offset(x: -14, y: 6) }
                    .overlay(alignment: .leading) {
                        if actif {
                            GeometryReader { g in
                                Rectangle().fill(Color(.faisceau))
                                    .frame(width: 2, height: g.size.height * 0.6)
                                    .shadow(color: Color(.faisceau).opacity(0.55), radius: 5)
                                    .offset(x: -8, y: g.size.height * 0.2)
                            }
                            .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(libelleEspace(e, alfred))
                .accessibilityAddTraits(actif ? .isSelected : [])
                .accessibilityIdentifier("espace-\(e.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(width: 84)
        .frame(maxHeight: .infinity)
        .background(Console.bandeau.opacity(0.95))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(.trait)).frame(width: 2).accessibilityHidden(true)
        }
        // une barre de l'app, comme celles du système : un appui long montre l'espace en grand
        .dynamicTypeSize(...DynamicTypeSize.large)
        .animation(.smooth(duration: 0.2), value: navigation.espace)
    }
}

/// La barre du bas (téléphone, iPad à la verticale) : les quatre espaces, pictogramme au-dessus du mot, l'actif en
/// champagne, souligné en haut du faisceau (comme les trois vues d'avant).
struct BarreEspaces: View {
    @Environment(Alfred.self) private var alfred
    @Bindable var navigation: NavigationConsole

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Espace.allCases) { e in
                let actif = navigation.espace == e
                Button {
                    navigation.aller(e)
                } label: {
                    VStack(spacing: 5) {
                        IconeEspaceVue(espace: e)
                            .foregroundStyle(actif ? Color(.glace) : Color(.texteSecondaire))
                        Text(e.titre)
                            .font(.caption2.weight(.heavy))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(actif ? Color(.champagne) : Color(.texteSecondaire))
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(alignment: .topTrailing) {
                        GeometryReader { g in
                            MarqueEspace(espace: e).position(x: g.size.width / 2 + 18, y: 9)
                        }
                    }
                    .overlay(alignment: .top) {
                        if actif {
                            Rectangle().fill(Color(.faisceau))
                                .frame(height: 2)
                                .shadow(color: Color(.faisceau).opacity(0.55), radius: 5)
                                .padding(.horizontal, 20)
                                .offset(y: -5)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(libelleEspace(e, alfred))
                .accessibilityAddTraits(actif ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
                .accessibilityIdentifier("espace-\(e.rawValue)")
            }
        }
        .frame(height: 58)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Console.bandeau.ignoresSafeArea(edges: .bottom)
                Rectangle().fill(Color(.trait)).frame(height: 1.5)
            }
            .accessibilityHidden(true)
        }
        .animation(.smooth(duration: 0.2), value: navigation.espace)
    }
}

/// MAISON sur téléphone : Pièces | Environnement (`#maison-vues`), sous l'en-tête.
struct SegmentMaison: View {
    @Bindable var navigation: NavigationConsole

    var body: some View {
        HStack(spacing: 3) {
            ForEach(VueMaison.allCases) { v in
                let actif = navigation.vueMaison == v
                Button {
                    navigation.vueMaison = v
                } label: {
                    Text(v.titre)
                        .font(.caption2.weight(.heavy))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(actif ? Color(.glace) : Color(.texteSecondaire))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            actif ? Color(red: 22 / 255, green: 51 / 255, blue: 74 / 255) : .clear,
                            in: .rect(cornerRadius: 7)
                        )
                        .overlay {
                            if actif {
                                RoundedRectangle(cornerRadius: 7).strokeBorder(Color(.faisceauSombre), lineWidth: 1.5)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(actif ? .isSelected : [])
                .accessibilityIdentifier("vue-\(v.rawValue)")
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .background(Console.bandeau.opacity(0.9), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.trait), lineWidth: 1.5))
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vue de la maison")
    }
}

// MARK: - pages (MOI, SYSTÈME)

/// Une page de la console (`.page`) : un grand titre, une phrase, un bouton à droite du titre au besoin, puis des
/// blocs ; 1240 pt de large au plus ; elle défile. Le titre reçoit le focus de VoiceOver à l'arrivée.
struct PageConsole<Bouton: View, Contenu: View>: View {
    let titre: String
    let phrase: String
    let large: Bool
    var identifiant: String
    @ViewBuilder let bouton: Bouton
    @ViewBuilder let contenu: Contenu
    @AccessibilityFocusState private var focusTitre: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var tailleTitre: CGFloat = 34

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 20) {
                    Text(titre)
                        .font(.system(size: large ? tailleTitre : tailleTitre * 0.78, weight: .bold))
                        .foregroundStyle(Color(.glace))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusTitre)
                    Spacer(minLength: 0)
                    bouton
                }
                Text(phrase)
                    .font(.subheadline)
                    .foregroundStyle(Color(.texteSecondaire))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.top, 8)
                contenu
                    .padding(.top, 22)
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .padding(.horizontal, large ? 40 : 16)
            .padding(.top, large ? 30 : 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .background(Color(.fond).opacity(0.94))
        .accessibilityIdentifier(identifiant)
        .onAppear { focusTitre = true }
    }
}

/// Un bloc d'une page (Documents, Notifications, Réglages & état, Autres systèmes) : le titre de section de la console
/// (champagne, capitales, trait qui s'efface), puis son contenu ; 760 pt de large au plus, comme la console.
struct BlocPage<Contenu: View>: View {
    let titre: String
    var largeurMax: CGFloat = 760
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(titre).titreSection()
            contenu
        }
        .frame(maxWidth: largeurMax, alignment: .leading)
    }
}
