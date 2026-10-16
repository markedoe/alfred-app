import AlfredKit
import Foundation
import Testing

@testable import Alfred

/// La conversation contre la maison de démonstration (aucun réseau, aucun micro).
@MainActor
@Suite("Conversation", .serialized)
struct ConversationTests {
    static func pret() async throws -> (Conversation, ClientRelais, VoixMuette) {
        let voix = VoixMuette()
        let reglages = UserDefaults(suiteName: "tests.conversation")!
        reglages.removePersistentDomain(forName: "tests.conversation")
        let c = Conversation(voix: voix, reglages: reglages)
        let client = ClientRelais(acces: AccesDemo())
        await client.demarrer()
        for _ in 0..<200 {
            if case .pret = await client.etat { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        c.client = client
        let ecoute = Task { @MainActor in
            for await n in client.nouvelles { if case .tour(let s) = n { c.recevoir(s) } }
        }
        _ = ecoute
        return (c, client, voix)
    }

    static func attendre(_ c: Conversation, _ condition: @MainActor (Conversation) -> Bool) async throws {
        for _ in 0..<300 {
            if condition(c) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("attente dépassée")
    }

    @Test("Une demande écrite : la question, l'action d'Alfred (faite), la réponse ; puis le repos")
    func ecrite() async throws {
        let (c, client, voix) = try await Self.pret()
        await c.ecrire("Allume la cuisine")
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 2 }
        #expect(c.messages[0].auteur == .moi && c.messages[0].texte == "Allume la cuisine")
        let r = c.messages[1]
        #expect(r.auteur == .alfred && !r.enCours && !r.erreur)
        #expect(r.texte.contains("cuisine"))
        #expect(r.outils.map(\.libelle) == ["Allumer · Cuisine"])
        #expect(r.outils.first?.etat == .fait)
        #expect(voix.lues.isEmpty, "réponse écrite : pas lue à voix haute par défaut")
        #expect(c.reponses == 1)
        await client.arreter()
    }

    @Test("Écrite, avec la lecture à voix haute activée")
    func ecriteLue() async throws {
        let (c, client, _) = try await Self.pret()
        c.lireReponsesEcrites = true
        await c.ecrire("Quelle heure est-il ?")
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 2 }
        // la démo n'envoie pas de voix (tts-end) : rien à lire, et le tour se termine quand même
        #expect(c.messages[1].texte.hasPrefix("Il est "))
        await client.arreter()
    }

    @Test("Échec : le message d'erreur s'affiche, rien n'est renvoyé")
    func echec() async throws {
        let c = Conversation(voix: VoixMuette())
        c.recevoir(.reflechit)
        c.recevoir(.echec(AutomateTour.messageDelai))
        #expect(c.messages.last?.erreur == true)
        #expect(c.messages.last?.texte == AutomateTour.messageDelai)
        #expect(c.phase == .repos)
    }

    @Test("Rien de compris hors conversation : la bulle vide disparaît")
    func rienSaisi() {
        let c = Conversation(voix: VoixMuette())
        c.recevoir(.reflechit)
        #expect(c.messages.count == 1)
        c.recevoir(.rienSaisi(message: "x"))
        #expect(c.messages.isEmpty && c.phase == .repos)
    }

    @Test("Demande lente : le clip d'accueil part dès la transcription")
    func accueil() {
        let voix = VoixMuette()
        let c = Conversation(voix: voix)
        c.recevoir(.transcrit("Cherche la recette de la fondue"))
        #expect(voix.accueils == 1)
        c.recevoir(.transcrit("Allume le salon"))
        #expect(voix.accueils == 1)
    }

    @Test("Libellés des actions, sans jamais le contenu des résultats")
    func libelles() {
        #expect(
            Conversation.libelle(AppelOutil(id: "1", nom: "HassTurnOff", arguments: ["name": "Bureau"]))
                == "Éteindre · Bureau")
        #expect(
            Conversation.libelle(AppelOutil(id: "1", nom: "homeassistant__GetLiveContext"))
                == "Lire l’état de la maison")
        #expect(Conversation.libelle(AppelOutil(id: "1", nom: "script__rappel_du_soir")) == "Rappel Du Soir")
    }

    @Test("Nouvelle conversation : le fil est oublié")
    func nouvelle() async throws {
        let (c, client, _) = try await Self.pret()
        await c.ecrire("Quelle heure est-il ?")
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 2 }
        await c.nouvelle()
        #expect(c.vide && c.phase == .repos)
        await client.arreter()
    }
}
