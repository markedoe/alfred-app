import SwiftUI

/// Seulement pour une fabrication sans configuration de la maison : l'adresse du relais, une fois.
struct ConfigurationVue: View {
    @Environment(Alfred.self) private var alfred
    @State private var adresse = ""
    @State private var invalide = false
    @FocusState private var focus: Bool

    var body: some View {
        ZStack {
            Console.fond
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Marque()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .padding(.bottom, 12)
                    Text("Adresse de la maison").titreSection()
                    TextField("relais.maison.example", text: $adresse)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus)
                        .submitLabel(.continue)
                        .onSubmit(continuer)
                        .font(.callout)
                        .foregroundStyle(Color(.texte))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(Console.caseMesure, in: .rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.acier), lineWidth: 1.5))
                        .accessibilityLabel("Adresse de la maison")
                        .accessibilityIdentifier("adresseRelais")
                    Text(
                        invalide
                            ? "Une adresse https est attendue, sans chemin (par exemple relais.maison.example)."
                            : "L’adresse du relais d’Alfred dans votre maison. Elle ne vous sera demandée qu’une fois."
                    )
                    .font(.footnote)
                    .foregroundStyle(invalide ? Color(.alerte) : Color(.texteSecondaire))
                    Button("Continuer", action: continuer)
                        .buttonStyle(StyleConsole(genre: .principal))
                        .disabled(adresse.trimmingCharacters(in: .whitespaces).isEmpty)
                    BoutonDemo()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focus = true }
    }

    private func continuer() {
        invalide = !alfred.configurer(adresse: adresse)
    }
}
