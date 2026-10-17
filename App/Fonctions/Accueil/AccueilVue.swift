import SwiftUI

/// Le premier écran, aux couleurs de la console : le réacteur qui démarre, ce qu'est Alfred en trois lignes, puis la
/// connexion avec le compte Home Assistant (ou la maison de démonstration).
struct AccueilVue: View {
    @Environment(Alfred.self) private var alfred
    @State private var connexion = false
    @State private var debut = Date.now

    var body: some View {
        ZStack {
            Console.fond
            ScrollView {
                VStack(spacing: 28) {
                    Marque()
                        .padding(.top, 32)
                    Reacteur(phase: .repos, niveau: { 0 }, rayon: 150, debut: debut, sousTitre: "À VOTRE SERVICE")
                        .frame(width: 300, height: 300)
                    VStack(alignment: .leading, spacing: 18) {
                        Ligne(
                            titre: "Parlez-lui",
                            texte: "Touchez le noyau et demandez : les lumières, l’heure, la météo, vos rappels.")
                        Ligne(
                            titre: "Votre maison, pièce par pièce",
                            texte:
                                "La roue de la console : allumez une pièce d’un geste ; l’état affiché est celui que la maison confirme."
                        )
                        Ligne(
                            titre: "Tout reste chez vous",
                            texte:
                                "Votre voix ne va que vers votre maison, jamais sur internet. Le micro n’écoute que quand vous lui parlez."
                        )
                    }
                    if let motif = alfred.motifAccueil {
                        Text(motif)
                            .font(.callout)
                            .foregroundStyle(Color(.alerte))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color(.alerte)).frame(width: 3)
                            }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button("Se connecter") { connexion = true }
                    .buttonStyle(StyleConsole(genre: .principal))
                    .accessibilityIdentifier("seConnecter")
                Text(
                    "Avec votre compte Home Assistant, sur le réseau de la maison (ou son VPN). L’appareil vous demandera l’accès au réseau local : c’est par là qu’Alfred joint la maison."
                )
                .font(.footnote)
                .foregroundStyle(Color(.texteSecondaire))
                .multilineTextAlignment(.center)
                BoutonDemo()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Console.bandeau.opacity(0.96).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(Color(.trait)).frame(height: 2).accessibilityHidden(true)
            }
        }
        .sheet(isPresented: $connexion) {
            ConnexionVue()
        }
    }

    private struct Ligne: View {
        let titre: LocalizedStringKey
        let texte: LocalizedStringKey

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(titre).titreSection()
                Text(texte)
                    .font(.subheadline)
                    .foregroundStyle(Color(.texte))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// ALFRED / MANOR COMMAND, comme l'en-tête de la console.
struct Marque: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("ALFRED")
                .font(.largeTitle.weight(.heavy))
                .tracking(9)
                .foregroundStyle(Color(.glace))
            Text("MANOR COMMAND")
                .font(.caption.weight(.semibold))
                .tracking(2.4)
                .foregroundStyle(Color(.champagne))
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alfred")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Découvrir l'app sans être à la maison : une maison simulée, sans réseau ni micro.
struct BoutonDemo: View {
    @Environment(Alfred.self) private var alfred

    var body: some View {
        Button("Essayer avec une maison de démonstration") { alfred.essayerDemo() }
            .buttonStyle(StyleConsole())
            .accessibilityIdentifier("essayerDemo")
    }
}

#Preview {
    AccueilVue().environment(Alfred.demonstration())
}
