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
        #expect(r.texte.localizedCaseInsensitiveContains("cuisine"))
        // « Détails techniques », comme la console : le nom court de l'outil et ses arguments
        #expect(r.outils.map(\.nom) == ["HassTurnOn"])
        #expect(r.outils.map(\.arguments) == ["Cuisine"])
        #expect(r.outils.first?.etat == .fait)
        // le badge de durée, et « Dernière réponse » dans Réglages & état
        let duree = try #require(r.duree)
        #expect(duree > 0 && duree < 5)
        #expect(c.derniereDuree == duree)
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

    @Test("Détails techniques : un outil annoncé deux fois n'apparaît qu'une fois ; son échec se voit")
    func outils() {
        let c = Conversation(voix: VoixMuette())
        c.recevoir(.reflechit)
        let appel = AppelOutil(id: "t1", nom: "homeassistant__HassTurnOff", arguments: ["name": "Bureau"])
        c.recevoir(.outilCommence(appel))
        c.recevoir(.outilCommence(appel))
        c.recevoir(.outilTermine(appelId: "t1", succes: false))
        let o = c.messages.last?.outils
        #expect(o?.map(\.nom) == ["HassTurnOff"])
        #expect(o?.first?.arguments == "Bureau" && o?.first?.etat == .echec)
    }

    @Test("Essai du micro : le niveau s'affiche, aucun tour ne part ; arrêté, le micro est libéré")
    func essai() async throws {
        let (c, client, voix) = try await Self.pret()
        await c.basculerEssai()
        #expect(c.essai == .actif)
        voix.entendre([Float](repeating: 0.3, count: 320))
        try await Self.attendre(c) { $0.niveauEssai > 0 }
        #expect(c.messages.isEmpty && c.phase == .repos && !c.enConversation)
        // une conversation ne s'ouvre pas pendant l'essai
        await c.basculerEcoute()
        #expect(!c.enConversation)
        c.arreterEssai()
        #expect(c.essai == .arrete && c.niveauEssai == 0)
        #expect(c.messageEssai == "Test arrêté · microphone libéré.")
        await client.arreter()
    }

    @Test("Micro choisi disparu : retour au micro d'iOS, et on le dit")
    func entreeOubliee() async throws {
        let (c, client, voix) = try await Self.pret()
        voix.entreeOubliee = true
        await c.basculerEcoute()
        #expect(c.avis?.texte == "Le micro choisi n’est plus là : retour au micro par défaut.")
        #expect(!voix.entreeOubliee)
        await c.terminer()
        await client.arreter()
    }

    /// Une conversation hors maison, avec ses propres réglages (lecture des réponses écrites activée).
    static func seule(_ voix: VoixMuette) -> Conversation {
        let reglages = UserDefaults(suiteName: "tests.reponse")!
        reglages.removePersistentDomain(forName: "tests.reponse")
        let c = Conversation(voix: voix, reglages: reglages)
        c.lireReponsesEcrites = true
        return c
    }

    @Test("Noyau pendant une réponse : rien pendant la réflexion ; Alfred qui parle se tait, le micro reste fermé")
    func noyauPendantUneReponse() async throws {
        let voix = VoixMuette()
        voix.lectureTenue = true
        let c = Self.seule(voix)
        c.recevoir(.reflechit)
        await c.basculerEcoute()
        #expect(!c.enConversation && c.phase == .reflexion)
        c.recevoir(.voix(chemin: "/tts/exemple.mp3"))
        try await Self.attendre(c) { _ in voix.lues.count == 1 }
        #expect(c.phase == .reponse)
        await c.basculerEcoute()
        #expect(!c.enConversation && voix.interruptions == 1)
        c.recevoir(.termine(conversationId: "fil", continuer: false))
        try await Self.attendre(c) { $0.phase == .repos }
    }

    @Test("Écrit pendant une réponse : refusé pendant la réflexion (rien ne se perd) ; pendant la voix, Alfred se tait")
    func ecritPendantUneReponse() async throws {
        let (c, client, voix) = try await Self.pret()
        voix.lectureTenue = true
        c.lireReponsesEcrites = true
        c.recevoir(.reflechit)
        #expect(!c.peutEcrire)
        #expect(await c.ecrire("Quelle heure est-il ?") == false)
        #expect(c.messages.count == 1)
        c.recevoir(.voix(chemin: "/tts/exemple.mp3"))
        try await Self.attendre(c) { _ in voix.lues.count == 1 }
        #expect(!c.peutEcrire, "le tour de la maison n'est pas fini")
        c.recevoir(.termine(conversationId: "demo", continuer: false))
        #expect(c.peutEcrire)
        #expect(await c.ecrire("Quelle heure est-il ?"))
        #expect(voix.interruptions >= 1)
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 3 }
        #expect(c.messages[1].auteur == .moi && c.messages[2].texte.hasPrefix("Il est "))
        await client.arreter()
    }

    @Test("Un fil neuf à chaque conversation, et pour une question écrite hors conversation")
    func filNeuf() async throws {
        let (c, client, _) = try await Self.pret()
        #expect(await c.ecrire("Quelle heure est-il ?"))
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 2 }
        #expect(c.conversationId == "demo", "le fil rendu par la maison")
        await c.basculerEcoute()
        #expect(c.enConversation && c.conversationId == nil)
        await c.terminer()
        #expect(await c.ecrire("Allume la cuisine"))
        #expect(c.conversationId == nil, "hors conversation : la question part sans fil")
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 4 }
        await client.arreter()
    }

    @Test("À la voix : une phrase ouvre un tour ; rien saisi, Alfred réécoute ; couper ferme tout")
    func cycleALaVoix() async throws {
        let (c, client, voix) = try await Self.pret()
        await c.basculerEcoute()
        #expect(c.enConversation && c.phase == .ecoute)
        // 100 ms de quasi-silence (le plancher de bruit descend), puis 400 ms de voix : une attaque
        voix.entendre([Float](repeating: 0.001, count: 1600))
        for _ in 0..<20 { voix.entendre([Float](repeating: 0.3, count: 320)) }
        // la démo n'a pas de transcription : « rien saisi », et la conversation réécoute
        try await Self.attendre(c) { $0.avis?.texte == "Je n’ai rien saisi." }
        #expect(c.enConversation && c.phase == .ecoute)
        await c.couper()
        #expect(!c.enConversation)
        // une 2e phrase a pu partir avec la fin de la voix : elle se clôt, puis le repos
        try await Self.attendre(c) { $0.phase == .repos }
        await client.arreter()
    }

    @Test("Couper (appel, app cachée) : l'essai du micro s'arrête et Alfred se tait")
    func couper() async throws {
        let voix = VoixMuette()
        voix.lectureTenue = true
        let c = Self.seule(voix)
        c.recevoir(.reflechit)
        c.recevoir(.voix(chemin: "/tts/exemple.mp3"))
        try await Self.attendre(c) { _ in voix.lues.count == 1 }
        await c.couper()
        #expect(voix.interruptions == 1)
        c.recevoir(.termine(conversationId: nil, continuer: false))
        try await Self.attendre(c) { $0.phase == .repos }
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
