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
                Section {
                    LabeledContent("Connecté en tant que") { Valeur(alfred.moi?.nom ?? "—") }
                    if !alfred.demo, let hote = alfred.configuration?.relais.hote {
                        LabeledContent("Maison") { Valeur(hote) }
                    }
                    // la démo n'a pas de compte : on la quitte, rien à déconnecter
                    if alfred.demo {
                        Button("Quitter la démonstration") {
                            Task {
                                await alfred.quitterDemo()
                                fermer()
                            }
                        }
                    } else {
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
                    }
                }
                Section {
                    Toggle("Lire à voix haute les réponses écrites", isOn: $conversation.lireReponsesEcrites)
                } header: {
                    EnTete("Voix")
                } footer: {
                    Text(
                        "Quand vous parlez, Alfred répond à voix haute. Quand vous écrivez, il répond par écrit, sauf si vous activez ce réglage."
                    )
                    .foregroundStyle(Color(.texteSecondaire))
                }
                Section {
                    Engagement("Votre voix ne va que vers votre maison, jamais sur internet.", icone: "house")
                    Engagement(
                        "Le micro ne s’ouvre que pendant une conversation, et jamais en arrière-plan.",
                        icone: "mic.slash")
                    Engagement("La conversation n’est pas gardée sur cet iPhone.", icone: "trash")
                } header: {
                    EnTete("Confidentialité")
                }
                Section {
                    LabeledContent("Version") { Valeur(Self.version) }
                    if let code = URL(string: "https://github.com/markedoe/alfred-app") {
                        Link("Code source", destination: code)
                    }
                } header: {
                    EnTete("À propos")
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

    /// En-tête de section aux couleurs de l'app : le gris du système n'atteint pas le contraste AA sur le fond
    /// groupé (audit d'accessibilité d'Apple).
    private struct EnTete: View {
        let texte: LocalizedStringKey
        init(_ texte: LocalizedStringKey) { self.texte = texte }
        var body: some View { Text(texte).foregroundStyle(Color(.texteSecondaire)) }
    }

    /// Un engagement de confidentialité. Le texte prend toute la hauteur qu'il lui faut, à toutes les tailles.
    private struct Engagement: View {
        let texte: LocalizedStringKey
        let icone: String
        init(_ texte: LocalizedStringKey, icone: String) {
            self.texte = texte
            self.icone = icone
        }
        var body: some View {
            Label {
                Text(texte).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: icone)
            }
            .font(.subheadline)
        }
    }

    /// La valeur d'une ligne (même raison).
    private struct Valeur: View {
        let texte: String
        init(_ texte: String) { self.texte = texte }
        var body: some View { Text(texte).foregroundStyle(Color(.texteSecondaire)) }
    }

    static var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
