import SwiftUI

/// Les réglages, comme la fenêtre « Réglages & état » de la console : le compte, la voix, la confidentialité, l'app.
/// Des titres de section de la console et des cartes, plutôt que la liste groupée du système (son en-tête de section
/// atténue la couleur des titres sous le contraste AA, mesuré par l'audit d'accessibilité d'Apple).
struct ReglagesVue: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Environment(\.dismiss) private var fermer
    @State private var confirmer = false

    var body: some View {
        @Bindable var conversation = conversation
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Compte").titreSection()
                    Carte {
                        Ligne("Connecté en tant que", valeur: alfred.moi?.nom ?? "—")
                        if !alfred.demo, let hote = alfred.configuration?.relais.hote {
                            Separateur()
                            Ligne("Maison", valeur: hote)
                        }
                        Separateur()
                        // la démo n'a pas de compte : on la quitte, rien à déconnecter
                        if alfred.demo {
                            Button("Quitter la démonstration") {
                                Task {
                                    await alfred.quitterDemo()
                                    fermer()
                                }
                            }
                            .buttonStyle(StyleLien())
                        } else {
                            Button("Se déconnecter", role: .destructive) { confirmer = true }
                                .buttonStyle(StyleLien(alerte: true))
                                .confirmationDialog(
                                    "Se déconnecter de la maison ?", isPresented: $confirmer,
                                    titleVisibility: .visible
                                ) {
                                    Button("Se déconnecter", role: .destructive) {
                                        Task {
                                            await alfred.seDeconnecter()
                                            fermer()
                                        }
                                    }
                                } message: {
                                    Text(
                                        "La connexion de cet appareil est supprimée dans Home Assistant. Vous pourrez vous reconnecter."
                                    )
                                }
                        }
                    }

                    Text("Voix").titreSection().padding(.top, 16)
                    Carte {
                        Toggle(isOn: $conversation.lireReponsesEcrites) {
                            Text("Lire à voix haute les réponses écrites")
                                .font(.callout)
                                .foregroundStyle(Color(.texte))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(Color(.faisceau))
                        .padding(.vertical, 6)
                    }
                    Note(
                        "Quand vous parlez, Alfred répond à voix haute. Quand vous écrivez, il répond par écrit, sauf si vous activez ce réglage."
                    )

                    Text("Confidentialité").titreSection().padding(.top, 16)
                    Carte {
                        Engagement("Votre voix ne va que vers votre maison, jamais sur internet.", icone: "house")
                        Separateur()
                        Engagement(
                            "Le micro ne s’ouvre que pendant une conversation, et jamais en arrière-plan.",
                            icone: "mic.slash")
                        Separateur()
                        Engagement("La conversation n’est pas gardée sur cet appareil.", icone: "trash")
                    }

                    Text("À propos").titreSection().padding(.top, 16)
                    Carte {
                        Ligne("Version", valeur: Self.version)
                        if let code = URL(string: "https://github.com/markedoe/alfred-app") {
                            Separateur()
                            Link("Code source", destination: code)
                                .buttonStyle(StyleLien())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .background(Console.fond)
            .navigationTitle("Réglages & état")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Console.bandeau, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

/// Une carte de la console : fond bleu nuit, bordure, ses lignes l'une sous l'autre.
private struct Carte<Contenu: View>: View {
    @ViewBuilder let contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { contenu }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Console.carte, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.trait), lineWidth: 1.5))
    }
}

private struct Separateur: View {
    var body: some View {
        Rectangle().fill(Color(.trait).opacity(0.7)).frame(height: 1).accessibilityHidden(true)
    }
}

/// Une ligne « libellé · valeur » (la valeur en chiffres fixes, comme les mesures de la console).
private struct Ligne: View {
    let libelle: LocalizedStringKey
    let valeur: String

    init(_ libelle: LocalizedStringKey, valeur: String) {
        self.libelle = libelle
        self.valeur = valeur
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(libelle).foregroundStyle(Color(.texte))
                Spacer(minLength: 12)
                Text(valeur).foregroundStyle(Color(.texteSecondaire))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(libelle).foregroundStyle(Color(.texte))
                Text(valeur).foregroundStyle(Color(.texteSecondaire))
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
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
            Text(texte)
                .foregroundStyle(Color(.texte))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icone).foregroundStyle(Color(.faisceau))
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}

/// Une note sous une carte.
private struct Note: View {
    let texte: LocalizedStringKey
    init(_ texte: LocalizedStringKey) { self.texte = texte }
    var body: some View {
        Text(texte)
            .font(.footnote)
            .foregroundStyle(Color(.texteSecondaire))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

/// Un bouton-lien dans une carte : texte du faisceau (ou rouge pour une action destructrice), 48 pt de haut.
private struct StyleLien: ButtonStyle {
    var alerte = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(alerte ? Color(.alerte) : Color(.faisceau))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(.rect)
    }
}
