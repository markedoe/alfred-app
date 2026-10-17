import AlfredKit
import SwiftUI

/// L'état du lien avec la maison, en haut de l'écran, seulement quand il n'est pas bon.
struct EtatLiaison: View {
    @Environment(Alfred.self) private var alfred
    /// L'état affiché : un état passager (connexion rapide, reconnexion réussie aussitôt) ne s'affiche pas.
    @State private var affiche: ClientRelais.Etat = .pret

    var body: some View {
        Group {
            switch affiche {
            case .pret:
                EmptyView()
            case .connexion, .synchronisation:
                capsule {
                    ProgressView().controlSize(.small)
                    Text("Connexion à la maison…")
                }
            case .deconnecte:
                capsule {
                    Image(systemName: "wifi.slash")
                    Text("Maison injoignable, nouvel essai…")
                }
            case .fatal(let message):
                capsule {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(.alerte))
                    Text(message).lineLimit(2)
                }
            }
        }
        .animation(.smooth, value: affiche)
        .task(id: alfred.liaison) {
            let etat = alfred.liaison
            if case .pret = etat {
                affiche = etat
                return
            }
            // une seconde de grâce : seul ce qui dure mérite d'interrompre
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { affiche = etat }
        }
    }

    private func capsule(@ViewBuilder _ contenu: () -> some View) -> some View {
        HStack(spacing: 8) { contenu() }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
    }
}

/// Le bouton des réglages (l'initiale de la personne).
struct BoutonReglages: View {
    @Environment(Alfred.self) private var alfred
    @Binding var ouvert: Bool

    var body: some View {
        Button {
            ouvert = true
        } label: {
            if let initiale = alfred.moi?.nom?.first {
                Text(String(initiale).uppercased())
                    .font(.headline)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "person.crop.circle")
            }
        }
        .accessibilityLabel("Réglages")
        .accessibilityIdentifier("reglages")
    }
}

/// Un avis passager en haut de l'écran (3 s), annoncé à VoiceOver, avec un retour haptique.
private struct AvisModificateur<A: Identifiable & Equatable>: ViewModifier {
    let avis: A?
    let texte: (A) -> String
    let attention: (A) -> Bool
    let oublier: (A) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let avis {
                    Label(texte(avis), systemImage: attention(avis) ? "exclamationmark.circle" : "info.circle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(attention(avis) ? Color(.alerte) : Color(.texte))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: avis.id) {
                            AccessibilityNotification.Announcement(texte(avis)).post()
                            try? await Task.sleep(for: .seconds(3))
                            oublier(avis)
                        }
                }
            }
            .animation(.smooth, value: avis)
            .sensoryFeedback(trigger: avis) { _, nouveau in
                guard let nouveau else { return nil }
                return attention(nouveau) ? .warning : .impact(weight: .light)
            }
    }
}

extension View {
    func avis(_ avis: Conversation.Avis?, oublier: @escaping (Conversation.Avis) -> Void) -> some View {
        modifier(
            AvisModificateur(avis: avis, texte: { $0.texte }, attention: { $0.genre == .attention }, oublier: oublier))
    }
}

/// Une suggestion de l'écran d'accueil : du contenu, donc sur une surface pleine et non sur verre (le Liquid Glass
/// est réservé aux commandes qui flottent au-dessus du contenu). 44 pt de haut au moins.
struct StyleSuggestion: ButtonStyle {
    @Environment(\.isEnabled) private var actif

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(.champagne))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(Color(.surface), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.trait).opacity(0.6), lineWidth: 0.5))
            .contentShape(.capsule)
            .opacity(actif ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
