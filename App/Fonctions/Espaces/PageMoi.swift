import AlfredKit
import SwiftUI

/// L'espace MOI (28.10, « oui 4 espaces ») : les documents et les notifications de la personne connectée (avant, deux
/// fenêtres de l'en-tête). Notifications (en-tête) y mène, la liste en vue.
struct PageMoi: View {
    @Environment(Alfred.self) private var alfred
    @Environment(NavigationConsole.self) private var navigation: NavigationConsole?
    let large: Bool

    var body: some View {
        ScrollViewReader { lecteur in
            PageConsole(
                titre: "Moi", phrase: "Vos documents et vos notifications.", large: large, identifiant: "page-moi"
            ) {
                EmptyView()
            } contenu: {
                VStack(alignment: .leading, spacing: 36) {
                    DocumentsMoi()
                        .id("documents")
                    if alfred.annexes?.notificationsPermises == true {
                        NotificationsMoi()
                            .id("notifications")
                    }
                }
            }
            .onAppear { montrer(navigation?.ancre, lecteur) }
            // déjà dans MOI : Notifications (en-tête) amène encore la liste en vue
            .onChange(of: navigation?.ancre) { _, a in montrer(a, lecteur) }
        }
    }

    private func montrer(_ ancre: String?, _ lecteur: ScrollViewProxy) {
        guard let ancre else { return }
        navigation?.ancre = nil
        // après la mise en page de la liste
        Task { @MainActor in lecteur.scrollTo(ancre, anchor: .top) }
    }
}
