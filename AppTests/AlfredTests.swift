import AVFAudio
import AlfredKit
import Foundation
import Testing

@testable import Alfred

/// L'app contre un relais de test (aucun réseau) : la coupure, la session expirée, la déconnexion, la démo.
@MainActor
@Suite("Alfred", .serialized)
struct AlfredTests {
    static func attendre(_ quoi: String, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("attente dépassée : \(quoi)")
    }

    static let salonAllume: ValeurJSON = [["entity_id": "light.salon", "state": "on", "attributes": [:]]]

    @Test("Coupure : rien de la maison n'est plus montré comme actuel (point 10)")
    func coupure() async throws {
        let relais = RelaisDeTest(etats: Self.salonAllume)
        let a = Alfred.essai(acces: relais)
        try await Self.attendre("prêt") { a.estPret && a.maison["light.salon"] != nil }
        await relais.liaisons.last?.fermer()
        try await Self.attendre("maison effacée") { !a.estPret && a.maison["light.salon"] == nil }
        #expect(a.historiquePuissance.isEmpty && a.lumieresAllumees == 0)
        try await Self.attendre("reconnectée") { a.estPret && a.maison["light.salon"] != nil }
        await a.seDeconnecter()
    }

    @Test("Coupure pendant la synchronisation : les états déjà chargés ne restent pas affichés")
    func coupurePendantLaSynchronisation() async throws {
        let relais = RelaisDeTest(etats: Self.salonAllume)
        let porte = PorteDeTest()
        relais.avantStructure = { await porte.passer() }
        let a = Alfred.essai(acces: relais)
        try await Self.attendre("états chargés") { a.maison["light.salon"] != nil }
        #expect(!a.estPret)
        // la 1re synchronisation attend à la porte ; la suivante n'y attendra pas
        relais.avantStructure = nil
        await relais.liaisons.last?.fermer()
        try await Self.attendre("maison effacée") { a.maison["light.salon"] == nil }
        await porte.ouvrir()
        try await Self.attendre("reconnectée") { a.estPret }
        await a.seDeconnecter()
    }

    @Test("Session expirée : la conversation et le fil disparaissent, la voix redevient muette (point 8)")
    func sessionExpiree() async throws {
        let relais = RelaisDeTest()
        let a = Alfred.essai(acces: relais, voix: VoixDeTest())
        try await Self.attendre("prêt") { a.estPret }
        #expect(await a.conversation.ecrire("Quelle heure est-il ?"))
        try await Self.attendre("réponse") { a.conversation.phase == .repos && a.conversation.messages.count == 2 }
        #expect(a.conversation.conversationId == RelaisDeTest.fil)
        // la maison ne connaît plus la personne : à la reconnexion, `/moi` le dit
        relais.connecte = false
        await relais.liaisons.last?.fermer()
        try await Self.attendre("accueil") { a.etape == .accueil }
        #expect(a.motifAccueil == "Votre connexion à la maison a expiré. Reconnectez-vous.")
        #expect(a.conversation.vide && a.conversation.conversationId == nil)
        #expect(a.conversation.voix is VoixMuette)
        #expect(!a.estPret && a.maison["light.salon"] == nil)
    }

    @Test(
        "Déconnexion : la conversation est vidée, la maison prévenue ; la démo ouverte ensuite n'a pas de micro (point 9)"
    )
    func deconnexion() async throws {
        let relais = RelaisDeTest()
        let a = Alfred.essai(acces: relais, voix: VoixDeTest())
        try await Self.attendre("prêt") { a.estPret }
        #expect(await a.conversation.ecrire("Quelle heure est-il ?"))
        try await Self.attendre("réponse") { a.conversation.phase == .repos && a.conversation.messages.count == 2 }
        await a.seDeconnecter()
        #expect(a.conversation.vide)
        #expect(relais.deconnexions == 1 && a.motifAccueil == nil)
        #expect(a.conversation.voix is VoixMuette)
        a.essayerDemo()
        try await Self.attendre("démo prête") { a.estPret }
        #expect(a.demo && a.conversation.voix is VoixMuette, "la démo : sans réseau ni micro")
        await a.quitterDemo()
    }
}

/// La session dans le trousseau de l'appareil (le simulateur en a un).
@Suite("Trousseau", .serialized)
struct TrousseauTests {
    @Test("Écrire, remplacer (mise à jour, jamais d'effacement d'abord), lire, effacer")
    func cycle() throws {
        let compte = "tests.trousseau.\(UUID().uuidString)"
        defer { Trousseau.effacer(compte: compte) }
        #expect(Trousseau.lire(compte: compte) == nil)
        try Trousseau.ecrire("premiere", compte: compte)
        #expect(Trousseau.lire(compte: compte) == "premiere")
        try Trousseau.ecrire("seconde", compte: compte)
        #expect(Trousseau.lire(compte: compte) == "seconde")
        Trousseau.effacer(compte: compte)
        #expect(Trousseau.lire(compte: compte) == nil)
    }
}

/// Les décisions du son, sans matériel.
@Suite("Son")
struct SonTests {
    @Test("Changement de matériel : seul notre moteur compte, et seulement s'il s'est arrêté")
    func changementDeMateriel() {
        let micro = NSObject()
        let lecteur = NSObject()
        let autre = NSObject()
        let m = ObjectIdentifier(micro)
        let l = ObjectIdentifier(lecteur)
        let o = ObjectIdentifier(autre)
        #expect(
            VoixSysteme.suite(moteur: m, micro: (id: m, tourne: false), lecteur: (id: l, tourne: true))
                == .fermerConversation)
        #expect(
            VoixSysteme.suite(moteur: m, micro: (id: m, tourne: true), lecteur: (id: l, tourne: true)) == .rien,
            "voix activée, en marche")
        #expect(
            VoixSysteme.suite(moteur: o, micro: (id: m, tourne: false), lecteur: (id: l, tourne: false)) == .rien,
            "un autre moteur")
        #expect(VoixSysteme.suite(moteur: l, micro: nil, lecteur: (id: l, tourne: false)) == .taireAlfred)
        #expect(VoixSysteme.suite(moteur: l, micro: nil, lecteur: (id: l, tourne: true)) == .rien)
    }

    @Test("Écouteurs retirés : Alfred se tait ; un appareil branché, non")
    func routeChange() {
        #expect(VoixSysteme.seTaire(apres: .oldDeviceUnavailable))
        #expect(!VoixSysteme.seTaire(apres: .newDeviceAvailable))
        #expect(!VoixSysteme.seTaire(apres: .categoryChange))
        #expect(!VoixSysteme.seTaire(apres: nil))
    }
}
