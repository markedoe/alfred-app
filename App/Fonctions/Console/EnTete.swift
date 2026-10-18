import AlfredKit
import SwiftUI

/// Les fenêtres de la console, ouvertes depuis l'en-tête (une à la fois, comme les `<dialog>` de la console).
enum FenetreConsole: String, Identifiable, Sendable {
    case documents, notifications, reglages
    var id: String { rawValue }
}

/// L'en-tête de la console telle qu'on la voit connecté : ALFRED / MANOR COMMAND, le lien avec la maison, Documents,
/// Notifications (la personne connectée), la voix reconnue ; à droite les réglages, les autres systèmes et le compte,
/// le nom de la personne dessous.
///
/// Comme la console : jusqu'à 560 pt, les boutons sont des icônes (et le lien un point de couleur) ; au-delà, « Documents »
/// et « Notifications » s'écrivent ; au-delà de 1100 pt, « LIEN » au-dessus de « Connecté ». Chaque bouton garde une
/// cible de 44 pt ; quand la place manque (les plus petits iPhone), la marque se resserre.
struct EnTeteConsole: View {
    @Environment(Alfred.self) private var alfred
    let largeur: CGFloat
    @Binding var fenetre: FenetreConsole?
    @Binding var liensOuverts: Bool
    @State private var quitter = false

    private var large: Bool { largeur > 1100 }
    private var textes: Bool { largeur > 560 }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ligne(serre: false)
            ligne(serre: true)
        }
        // une barre de l'app, comme celles du système : à la taille de la console ; un appui long montre un bouton en
        // grand (visionneuse de grand contenu)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.horizontal, large ? 24 : 16)
        .frame(minHeight: textes ? 76 : 68)
        .background(Console.bandeau.opacity(0.95).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.trait)).frame(height: 2).accessibilityHidden(true)
        }
        // le téléphone (jusqu'à 760 pt) : le badge de la voix flotte sous l'en-tête, sans capter les touchers
        .overlay(alignment: .bottom) {
            if largeur <= 760, let v = alfred.voixReconnue {
                BadgeVoix(voix: v, flottant: true)
                    // son haut 6 pt sous l'en-tête (la console : top: calc(100% + 6px))
                    .alignmentGuide(.bottom) { d in d[.top] - 6 }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: alfred.voixReconnue)
        .confirmationDialog(
            alfred.demo ? "Quitter la démonstration ?" : "Se déconnecter de la maison ?", isPresented: $quitter,
            titleVisibility: .visible
        ) {
            Button(alfred.demo ? "Quitter" : "Se déconnecter", role: .destructive) {
                Task {
                    if alfred.demo {
                        await alfred.quitterDemo()
                    } else {
                        await alfred.seDeconnecter()
                    }
                }
            }
        } message: {
            if !alfred.demo {
                Text("La connexion de cet appareil est supprimée dans Home Assistant. Vous pourrez vous reconnecter.")
            }
        }
    }

    private func ligne(serre: Bool) -> some View {
        HStack(spacing: large ? 20 : textes ? 12 : 8) {
            marque(serre: serre)
            if large {
                Rectangle().fill(Color(.trait)).frame(width: 1, height: 24).accessibilityHidden(true)
            }
            LienMaison(texte: textes, etiquette: large)
            HStack(spacing: textes ? 10 : 0) {
                BoutonDocuments(texte: textes) { fenetre = .documents }
                if alfred.annexes?.notificationsPermises == true {
                    BoutonNotifications(texte: textes) { fenetre = .notifications }
                }
            }
            if largeur > 760, let v = alfred.voixReconnue {
                BadgeVoix(voix: v, flottant: false)
            }
            Spacer(minLength: serre ? 0 : 6)
            HStack(spacing: textes ? 8 : 0) {
                BoutonEnTete(icone: "gearshape", libelle: "Réglages", actif: fenetre == .reglages) {
                    fenetre = .reglages
                }
                .accessibilityIdentifier("reglages")
                if let liens = alfred.annexes?.liens, !liens.isEmpty {
                    BoutonEnTete(icone: "square.grid.2x2", libelle: "Autres systèmes", actif: liensOuverts) {
                        liensOuverts.toggle()
                    }
                    .accessibilityIdentifier("liens")
                    .accessibilityAddTraits(liensOuverts ? .isSelected : [])
                }
                compte
            }
        }
    }

    private func marque(serre: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ALFRED")
                .font(.title2.weight(.heavy))
                .tracking(serre ? 2.2 : textes ? 6 : 4)
                .foregroundStyle(Color(.glace))
            Text("MANOR COMMAND")
                .font(.system(size: textes ? 11 : 9, weight: .semibold))
                .tracking(serre ? 1 : 1.6)
                .foregroundStyle(Color(.champagne))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alfred")
        .accessibilityAddTraits(.isHeader)
    }

    /// Le compte : l'icône de sortie (sarcelle, comme la console connectée) et le nom de la personne dessous.
    private var compte: some View {
        Button {
            quitter = true
        } label: {
            VStack(spacing: 3) {
                CadreIcone(actif: false, couleur: Color(.sarcelle)) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                if let nom = alfred.moi?.nom, !nom.isEmpty {
                    Text(nom)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.sarcelle))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            alfred.demo ? "Quitter la démonstration" : "Se déconnecter" + (alfred.moi?.nom.map { " (\($0))" } ?? "")
        )
        .accessibilityShowsLargeContentViewer {
            Image(systemName: "rectangle.portrait.and.arrow.right")
            Text(alfred.demo ? "Quitter la démonstration" : "Se déconnecter")
        }
        .accessibilityIdentifier("compte")
    }
}

// MARK: - éléments de l'en-tête

/// Le cadre d'un bouton-icône de l'en-tête (`#system-toggle`, `#qui-lien`) : 34 pt, bordure du trait, sans fond ;
/// bordure du faisceau quand sa fenêtre est ouverte.
private struct CadreIcone<Contenu: View>: View {
    let actif: Bool
    var couleur = Color(.texteSecondaire)
    @ViewBuilder let contenu: Contenu

    var body: some View {
        contenu
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(actif ? Color(.glace) : couleur)
            .frame(width: 34, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    actif ? Color(.faisceau) : Color(.trait), lineWidth: 1.5))
    }
}

/// Un bouton-icône de l'en-tête : le cadre de 34 pt dans une cible de 44 pt.
private struct BoutonEnTete: View {
    let icone: String
    let libelle: String
    let actif: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CadreIcone(actif: actif) { Image(systemName: icone) }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(libelle)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: icone)
            Text(libelle)
        }
    }
}

/// Un compteur rond de la console (`#docs-count`, `#notifs-count`) : chiffres mono, 20 pt de haut.
private struct Compteur: View {
    let nombre: Int
    let fond: Color
    let texte: Color

    var body: some View {
        Text("\(nombre)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(texte)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(fond, in: .capsule)
            .accessibilityHidden(true)
    }
}

/// Un bouton de fenêtre de l'en-tête (Documents, Notifications) : un bouton de la console (fond, bordure acier) ; son
/// texte et son compteur au-delà de 560 pt, son icône et son compteur en dessous.
private struct BoutonFenetre: View {
    let titre: String
    let icone: String
    let texte: Bool
    let nombre: Int
    let fondCompteur: Color
    let texteCompteur: Color
    let libelle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: texte ? 8 : 4) {
                if texte {
                    Text(titre).font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: icone).font(.system(size: 15, weight: .medium))
                }
                if nombre > 0 {
                    Compteur(nombre: nombre, fond: fondCompteur, texte: texteCompteur)
                }
            }
            .foregroundStyle(Color(.glace))
            .padding(.horizontal, texte ? 12 : 4)
            .frame(minWidth: texte ? nil : 38, minHeight: 34)
            .background(Console.bouton, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.acier), lineWidth: 1.5))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(libelle)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: icone)
            Text(libelle)
        }
    }
}

private struct BoutonDocuments: View {
    @Environment(Alfred.self) private var alfred
    let texte: Bool
    let action: () -> Void

    var body: some View {
        let n = alfred.annexes?.documents.count ?? 0
        BoutonFenetre(
            titre: "Documents", icone: "doc", texte: texte, nombre: n, fondCompteur: Color(.faisceauSombre),
            texteCompteur: Color(.glace),
            libelle: n > 0 ? "Documents, \(n) déposé\(n > 1 ? "s" : "")" : "Documents", action: action
        )
        .accessibilityIdentifier("documents")
    }
}

private struct BoutonNotifications: View {
    @Environment(Alfred.self) private var alfred
    let texte: Bool
    let action: () -> Void

    var body: some View {
        let n = alfred.annexes?.nonLues ?? 0
        BoutonFenetre(
            titre: "Notifications", icone: "bell", texte: texte, nombre: n, fondCompteur: Color(.sodium),
            texteCompteur: Console.bandeau,
            libelle: n > 0 ? "Notifications, \(n) non lue\(n > 1 ? "s" : "")" : "Notifications", action: action
        )
        .accessibilityIdentifier("notifications")
    }
}

/// « voix : <prénom> » (sarcelle) ou « voix non reconnue » (sodium), 8 s après chaque reconnaissance.
struct BadgeVoix: View {
    let voix: VoixReconnue
    let flottant: Bool

    var body: some View {
        Text(voix.texte)
            .font(.system(size: flottant ? 12 : 13))
            .foregroundStyle(voix.incertaine ? Color(.sodium) : Color(.sarcelle))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, flottant ? 10 : 0)
            .padding(.vertical, flottant ? 3 : 0)
            .background {
                if flottant {
                    Capsule().fill(Console.bandeau.opacity(0.95))
                        .overlay(Capsule().strokeBorder(Color(.trait), lineWidth: 1))
                }
            }
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("voix")
    }
}

/// Le lien avec la maison : une pastille sarcelle (connecté) ou sodium ; son état en clair au-delà de 560 pt, et
/// « LIEN » au-dessus au-delà de 1100 pt.
struct LienMaison: View {
    @Environment(Alfred.self) private var alfred
    let texte: Bool
    let etiquette: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if etiquette {
                Text("Lien").etiquette(Color(.texteSecondaire), espacement: 0.8)
            }
            HStack(spacing: 6) {
                Circle().fill(couleur).frame(width: texte ? 8 : 10, height: texte ? 8 : 10)
                if texte {
                    Text(mot)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(couleur)
                        .fixedSize()
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lien avec la maison")
        .accessibilityValue(mot)
        .accessibilityIdentifier("lien")
    }

    private var couleur: Color { alfred.estPret ? Color(.sarcelle) : Color(.sodium) }

    private var mot: String {
        switch alfred.liaison {
        case .pret: "Connecté"
        case .connexion: "…"
        case .synchronisation: "Synchronisation…"
        case .deconnecte: "Déconnecté"
        case .fatal: "!"
        }
    }
}

// MARK: - autres systèmes

/// La liste des autres systèmes (`#liens`), sous l'icône : leur nom et une note ; chacun s'ouvre dans Safari.
struct ListeLiens: View {
    @Environment(Alfred.self) private var alfred
    @Environment(\.openURL) private var ouvrir
    @Binding var ouverte: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(alfred.annexes?.liens ?? []) { l in
                Button {
                    ouverte = false
                    ouvrir(l.url)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.nom).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.glace))
                        if let note = l.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(Color(.texteSecondaire))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(StyleLigneLien())
                .accessibilityHint("S’ouvre dans Safari")
            }
        }
        .padding(6)
        .frame(minWidth: 230, maxWidth: 320)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color(red: 16 / 255, green: 30 / 255, blue: 44 / 255), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.acier), lineWidth: 2))
        .shadow(color: .black.opacity(0.7), radius: 17, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autres systèmes")
        .accessibilityAction(.escape) { ouverte = false }
        .accessibilityIdentifier("listeLiens")
    }
}

/// Une ligne de la liste des liens : éclairée au toucher (#183047), comme au survol dans la console.
private struct StyleLigneLien: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color(red: 24 / 255, green: 48 / 255, blue: 71 / 255) : .clear,
                in: .rect(cornerRadius: 6))
    }
}
