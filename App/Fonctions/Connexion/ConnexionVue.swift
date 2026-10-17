import AlfredKit
import SwiftUI

/// La connexion : la page de Home Assistant dans une feuille, avec un état clair (chargement, échec, réessai).
struct ConnexionVue: View {
    @Environment(Alfred.self) private var alfred
    @Environment(\.dismiss) private var fermer
    @State private var etat = PageConnexion.EtatPage.chargement

    var body: some View {
        NavigationStack {
            ZStack {
                Console.fond
                if let configuration = alfred.configuration {
                    PageConnexion(configuration: configuration, etat: $etat) { session in
                        alfred.connexionReussie(session)
                        fermer()
                    }
                    .opacity(etat == .affichee ? 1 : 0)
                }
                switch etat {
                case .chargement:
                    ProgressView("Connexion à la maison…")
                        .controlSize(.large)
                        .tint(Color(.faisceau))
                        .foregroundStyle(Color(.texteSecondaire))
                case .affichee:
                    EmptyView()
                case .echec(let message):
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connexion impossible").titreSection()
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(Color(.texte))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("messageConnexion")
                        Button("Réessayer") { etat = .chargement }
                            .buttonStyle(StyleConsole(genre: .principal))
                    }
                    .padding(24)
                    .frame(maxWidth: 520)
                }
            }
            .navigationTitle("Connexion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Console.bandeau, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { fermer() }
                }
            }
        }
        .animation(.smooth, value: etat)
    }
}
