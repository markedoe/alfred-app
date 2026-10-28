import AlfredKit
import Foundation
import SwiftUI
import Testing

@testable import Alfred

/// Les quatre espaces de la console et la page des connecteurs (28.10) : la navigation, les pictogrammes du rail,
/// les connecteurs lus seulement quand SYSTÈME est à l'écran, leurs logos dessinés dans leur cadre, la maison muette.
@MainActor
@Suite("Espaces et connecteurs", .serialized)
struct EspacesTests {
    @Test("Espace par défaut : ALFRED en disposition large, MAISON sur téléphone ; « aller » pose l'ancre")
    func navigation() {
        #expect(Espace.parDefaut(large: true) == .alfred && Espace.parDefaut(large: false) == .maison)
        #expect(Espace.allCases.map(\.titre) == ["Alfred", "Maison", "Moi", "Système"])
        let n = NavigationConsole(espace: .alfred)
        n.aller(.moi, ancre: "notifications")
        #expect(n.espace == .moi && n.ancre == "notifications")
        n.aller(.systeme)
        #expect(n.espace == .systeme && n.ancre == nil)
    }

    @Test("Pictogrammes des espaces : chacun dessiné, dans son cadre")
    func pictogrammes() {
        let cadre = CGRect(x: 0, y: 0, width: 22, height: 22)
        for e in Espace.allCases {
            let b = IconeEspace(espace: e).path(in: cadre).boundingRect
            #expect(!b.isEmpty && cadre.insetBy(dx: -0.5, dy: -0.5).contains(b), "\(e) : \(b)")
        }
    }

    @Test("Connecteurs de la démo : lus seulement dans SYSTÈME ; chaque logo se lit et tient dans son cadre")
    func connecteurs() async throws {
        let a = Annexes(acces: AccesDemo()) { _, _ in }
        a.demarrer(connecte: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(a.connecteurs == nil, "rien n'est lu hors de SYSTÈME")
        a.suivreConnecteurs(true)
        try await AnnexesTests.attendre { a.connecteurs != nil }
        let l = try #require(a.connecteurs)
        #expect(l.groupes.map(\.nom) == ["Maison", "Voix et cerveau", "Ce qu'Alfred sait", "Agents", "Surveillance"])
        #expect(l.tous.count == 15 && l.veille == nil)
        #expect(l.tous.allSatisfy { $0.icone.trace != nil }, "chaque logo se lit")
        let cadre = CGRect(x: 0, y: 0, width: 30, height: 30)
        for c in l.tous {
            let trace = try #require(c.icone.trace)
            let b = FormeTrace(trace: trace).path(in: cadre).boundingRect
            #expect(!b.isEmpty && cadre.insetBy(dx: -1, dy: -1).contains(b), "\(c.id) : \(b)")
        }
        #expect(l.tous.first { $0.id == "claude" }?.nuage == true, "Claude : Internet")
        #expect(l.tous.first { $0.id == "claude" }?.etat.statut == .demande)
        #expect(l.tous.first { $0.id == "home-assistant" }?.lien?.host == "www.home-assistant.io")
        #expect(a.erreurConnecteurs == nil)
        a.suivreConnecteurs(false)
        a.suspendre()
    }

    @Test("Connecteurs : la maison muette (503) est dite en clair, sans liste inventée")
    func maisonMuette() async throws {
        let a = Annexes(acces: RelaisMuet()) { _, _ in }
        a.demarrer(connecte: false)
        a.suivreConnecteurs(true)
        try await AnnexesTests.attendre { a.erreurConnecteurs != nil }
        #expect(a.erreurConnecteurs == "La maison ne répond pas : l’état des connecteurs revient dès qu’elle répond.")
        #expect(a.connecteurs == nil)
        a.suspendre()
    }
}

/// Un relais dont la maison ne répond pas : 503 partout.
private struct RelaisMuet: AccesRelais {
    func ouvrir() async throws -> any Liaison { try await AccesDemo().ouvrir() }
    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) { (503, Data()) }
}
