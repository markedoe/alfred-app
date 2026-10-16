import SwiftUI

@main
struct AlfredApp: App {
    @State private var alfred = Alfred.surAppareil()
    @Environment(\.scenePhase) private var phaseScene

    var body: some Scene {
        WindowGroup {
            Racine()
                .environment(alfred)
                .environment(alfred.conversation)
                .tint(Color(.champagne))
                // tests d'interface : forcer le mode sombre (« -sombre »)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-sombre") ? .dark : nil)
        }
        .onChange(of: phaseScene) { _, phase in
            // le micro ne reste jamais ouvert écran caché
            if phase == .background { Task { await alfred.arrierePlan() } }
        }
    }
}

/// L'écran racine : configuration, accueil ou l'app.
struct Racine: View {
    @Environment(Alfred.self) private var alfred

    var body: some View {
        Group {
            switch alfred.etape {
            case .configuration: ConfigurationVue()
            case .accueil: AccueilVue()
            case .connecte: Principale()
            }
        }
        .animation(.smooth, value: alfred.etape)
    }
}

/// Les deux onglets : parler à Alfred, la maison.
struct Principale: View {
    @State private var onglet = Onglet.alfred

    enum Onglet: Hashable {
        case alfred, maison
    }

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Alfred", systemImage: "waveform", value: .alfred) {
                ParlerVue()
            }
            Tab("Maison", systemImage: "house", value: .maison) {
                MaisonVue()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
