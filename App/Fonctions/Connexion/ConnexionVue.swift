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
                case .affichee:
                    EmptyView()
                case .echec(let message):
                    ContentUnavailableView {
                        Label("Connexion impossible", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") { etat = .chargement }
                            .buttonStyle(.glass)
                    }
                }
            }
            .navigationTitle("Connexion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { fermer() }
                }
            }
        }
        .animation(.smooth, value: etat)
    }
}
