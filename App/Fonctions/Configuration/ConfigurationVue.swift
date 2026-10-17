import SwiftUI

/// Seulement pour une fabrication sans configuration de la maison : l'adresse du relais, une fois.
struct ConfigurationVue: View {
    @Environment(Alfred.self) private var alfred
    @State private var adresse = ""
    @State private var invalide = false
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("relais.maison.example", text: $adresse)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus)
                        .submitLabel(.continue)
                        .onSubmit(continuer)
                        .accessibilityIdentifier("adresseRelais")
                } header: {
                    Text("Adresse de la maison")
                } footer: {
                    if invalide {
                        Text("Une adresse https est attendue, sans chemin (par exemple relais.maison.example).")
                            .foregroundStyle(Color(.alerte))
                    } else {
                        Text("L’adresse du relais d’Alfred dans votre maison. Elle ne vous sera demandée qu’une fois.")
                    }
                }
                Section {
                    BoutonDemo()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Bienvenue")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continuer", action: continuer)
                        .disabled(adresse.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focus = true }
        }
    }

    private func continuer() {
        invalide = !alfred.configurer(adresse: adresse)
    }
}
