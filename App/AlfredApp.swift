import SwiftUI

@main
struct AlfredApp: App {
    @State private var alfred = Alfred.surAppareil()
    @Environment(\.scenePhase) private var phaseScene

    /// Tests d'interface (« -sansAnimations ») : aucune animation, ni de SwiftUI ni d'UIKit, et le noyau immobile.
    /// L'audit d'accessibilité lit alors l'état final (et non un écran en pleine transition), et XCTest sait quand
    /// l'app est au repos, ce que le noyau, animé sans fin, empêche sinon.
    static let sansAnimations = ProcessInfo.processInfo.arguments.contains("-sansAnimations")

    init() {
        if Self.sansAnimations { UIView.setAnimationsEnabled(false) }
    }

    var body: some Scene {
        WindowGroup {
            Racine()
                .environment(alfred)
                .environment(alfred.conversation)
                .tint(Color(.champagne))
                // tests d'interface : forcer le mode sombre (« -sombre »)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-sombre") ? .dark : nil)
                .environment(\.animationsCoupees, Self.sansAnimations)
                .transaction { t in
                    if Self.sansAnimations {
                        t.disablesAnimations = true
                        t.animation = nil
                    }
                }
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

extension EnvironmentValues {
    /// Animations coupées pour les tests d'interface (voir `AlfredApp.sansAnimations`).
    @Entry var animationsCoupees = false
}
