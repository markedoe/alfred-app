import SwiftUI

/// Les réglages : le compte, la voix, la confidentialité, l'app.
struct ReglagesVue: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Environment(\.dismiss) private var fermer
    @State private var confirmer = false

    var body: some View {
        @Bindable var conversation = conversation
        NavigationStack {
            Form {
                Section("Compte") {
                    LabeledContent("Connecté en tant que", value: alfred.moi?.nom ?? "—")
                    if let hote = alfred.configuration?.relais.hote {
                        LabeledContent("Maison", value: hote)
                    }
                    Button("Se déconnecter", role: .destructive) { confirmer = true }
                        .confirmationDialog(
                            "Se déconnecter de la maison ?", isPresented: $confirmer, titleVisibility: .visible
                        ) {
                            Button("Se déconnecter", role: .destructive) {
                                Task {
                                    await alfred.seDeconnecter()
                                    fermer()
                                }
                            }
                        } message: {
                            Text(
                                "La connexion de cet iPhone est supprimée dans Home Assistant. Vous pourrez vous reconnecter."
                            )
                        }
                        .disabled(alfred.demo)
                }
                Section {
                    Toggle("Lire à voix haute les réponses écrites", isOn: $conversation.lireReponsesEcrites)
                } header: {
                    Text("Voix")
                } footer: {
                    Text(
                        "Quand vous parlez, Alfred répond à voix haute. Quand vous écrivez, il répond par écrit, sauf si vous activez ce réglage."
                    )
                }
                Section("Confidentialité") {
                    Label("Votre voix ne va que vers votre maison, jamais sur internet.", systemImage: "house")
                    Label(
                        "Le micro n’est ouvert que pendant une conversation ; il se ferme quand l’app passe en arrière-plan.",
                        systemImage: "mic.slash")
                    Label("La conversation n’est pas gardée sur cet iPhone.", systemImage: "trash")
                }
                .font(.subheadline)
                Section("À propos") {
                    LabeledContent("Version", value: Self.version)
                    if let code = URL(string: "https://github.com/markedoe/alfred-app") {
                        Link("Code source", destination: code)
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { fermer() }
                }
            }
        }
    }

    static var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
