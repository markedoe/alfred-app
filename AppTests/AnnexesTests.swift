import AlfredKit
import Foundation
import Testing

@testable import Alfred

/// Les annexes de la console contre la maison de démonstration (aucun réseau) : documents, notifications, liens, état.
@MainActor
@Suite("Annexes", .serialized)
struct AnnexesTests {
    static func pretes() async throws -> Annexes {
        let a = Annexes(acces: AccesDemo()) { _, _ in }
        a.demarrer(connecte: true)
        try await attendre { a.etat != nil && !a.documents.isEmpty && !a.liens.isEmpty && a.notificationsPermises }
        return a
    }

    static func attendre(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("attente dépassée")
    }

    @Test("Au démarrage : documents, notifications, liens et état des services")
    func demarrage() async throws {
        let a = try await Self.pretes()
        #expect(a.documents.map(\.nom) == ["Facture d’exemple"])
        #expect(a.documents.first?.paperless == true)
        #expect(a.nonLues == 1 && a.notifications.count == 2)
        #expect(a.liens.map(\.nom) == ["Home Assistant", "Paperless"])
        #expect(a.etat?.groupes.map(\.nomCourt) == ["maison", "voix", "nuit"])
        #expect(a.etat?.kuma == nil)
        a.suspendre()
    }

    @Test("Dépôt puis suppression d'un document : la liste suit")
    func depot() async throws {
        let a = try await Self.pretes()
        await a.deposer(
            DepotDocument(fichier: Data("%PDF-1.7".utf8), nomFichier: "devis.pdf", type: "application/pdf"))
        try await Self.attendre { a.documents.count == 2 }
        #expect(a.documents.first?.nom == "devis.pdf")
        #expect(a.etatDepot == "Reçu. Alfred le lit…")
        let depose = try #require(a.documents.first)
        await a.supprimer(depose)
        try await Self.attendre { a.documents.count == 1 }
        a.suspendre()
    }

    @Test("Un document de plus de 20 Mo n'est pas envoyé")
    func tropLourd() async throws {
        let a = try await Self.pretes()
        await a.deposer(
            DepotDocument(
                fichier: Data(count: DepotDocument.tailleMax + 1), nomFichier: "gros.pdf", type: "application/pdf"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(a.documents.count == 1 && a.etatDepot == nil)
        a.suspendre()
    }

    @Test("Notifications : lues, puis effacées")
    func notifications() async throws {
        let a = try await Self.pretes()
        await a.marquerLues()
        try await Self.attendre { a.nonLues == 0 }
        #expect(a.notifications.allSatisfy(\.lu))
        await a.effacerNotifications()
        try await Self.attendre { a.notifications.isEmpty }
        a.suspendre()
    }

    @Test("Invité (non connecté) : ni notifications ni liens")
    func invite() async throws {
        let a = Annexes(acces: AccesDemo()) { _, _ in }
        a.demarrer(connecte: false)
        try await Self.attendre { a.etat != nil }
        #expect(!a.notificationsPermises && a.liens.isEmpty)
        a.suspendre()
    }
}
