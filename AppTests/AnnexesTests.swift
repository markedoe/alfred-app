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

    @Test("Un document de plus de 20 Mo n'est pas envoyé : l'erreur est dans la fenêtre, puis oubliée à sa fermeture")
    func tropLourd() async throws {
        let avis = Recueil()
        let a = Annexes(acces: AccesDemo()) { texte, _ in avis.textes.append(texte) }
        a.demarrer(connecte: true)
        try await Self.attendre { !a.documents.isEmpty }
        // le refus est immédiat (rien ne part) : vérifié dès le retour, sans attente
        await a.deposer(
            DepotDocument(
                fichier: Data(count: DepotDocument.tailleMax + 1), nomFichier: "gros.pdf", type: "application/pdf"))
        #expect(a.documents.count == 1 && a.etatDepot == nil)
        #expect(a.erreurDepot == "Document trop lourd : 20 Mo au plus.", "dans la fenêtre Documents (point 11)")
        #expect(avis.textes == ["Document trop lourd : 20 Mo au plus."])
        a.oublierErreurDepot()
        #expect(a.erreurDepot == nil)
        a.suspendre()
    }

    @Test("L'identifiant d'un document ne vise jamais une autre route")
    func segment() {
        #expect(Annexes.segment("42") == "42")
        #expect(Annexes.segment("../notifications/effacer") == "..%2Fnotifications%2Feffacer")
    }

    @Test("Notifications : lues, puis effacées")
    func notifications() async throws {
        let a = try await Self.pretes()
        await a.marquerLues()
        try await Self.attendre { a.nonLues == 0 }
        let toutesLues = a.notifications.allSatisfy { $0.lu }
        #expect(toutesLues)
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

/// Les avis reçus (une boîte : la fonction des avis est isolée sur l'acteur principal, donc envoyable).
@MainActor
final class Recueil {
    var textes: [String] = []
}
