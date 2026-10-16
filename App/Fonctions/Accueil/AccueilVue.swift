import SwiftUI

/// Le premier écran : ce qu'est Alfred, en trois lignes, puis la connexion avec le compte Home Assistant.
struct AccueilVue: View {
    @Environment(Alfred.self) private var alfred
    @State private var connexion = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Noyau(phase: .repos) { 0 }
                    .frame(width: 180, height: 180)
                    .padding(.top, 48)

                VStack(spacing: 8) {
                    Text("Alfred")
                        .font(.largeTitle.bold())
                        .fontDesign(.serif)
                    Text("Votre maison, à votre voix.")
                        .font(.title3)
                        .foregroundStyle(Color(.texteSecondaire))
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 20) {
                    Ligne(
                        symbole: "waveform", titre: "Parlez-lui",
                        texte: "Touchez le noyau et demandez : les lumières, l’heure, la météo, vos rappels.")
                    Ligne(
                        symbole: "house", titre: "Votre maison, pièce par pièce",
                        texte:
                            "Allumez ou éteignez une pièce d’un geste ; l’état affiché est celui que la maison confirme."
                    )
                    Ligne(
                        symbole: "lock.shield", titre: "Tout reste chez vous",
                        texte:
                            "Votre voix ne va que vers votre maison, jamais sur internet. Le micro n’écoute que quand vous lui parlez."
                    )
                }
                .padding(.horizontal, 8)

                if let motif = alfred.motifAccueil {
                    Label(motif, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(Color(.alerte))
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    connexion = true
                } label: {
                    Text("Se connecter")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("seConnecter")
                Text(
                    "Avec votre compte Home Assistant. iOS vous demandera l’accès au réseau local : c’est par là qu’Alfred joint la maison."
                )
                .font(.footnote)
                .foregroundStyle(Color(.texteSecondaire))
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: 560)
        }
        .background(Color(.fond).ignoresSafeArea())
        .sheet(isPresented: $connexion) {
            ConnexionVue()
        }
    }

    private struct Ligne: View {
        let symbole: String
        let titre: LocalizedStringKey
        let texte: LocalizedStringKey

        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbole)
                    .font(.title2)
                    .foregroundStyle(Color(.champagne))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titre).font(.headline)
                    Text(texte).font(.subheadline).foregroundStyle(Color(.texteSecondaire))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    AccueilVue().environment(Alfred.demonstration())
}
