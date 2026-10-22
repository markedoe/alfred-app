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

    /// La conversation contre un relais de test, reliée comme dans `Alfred.traiter` : les signaux du tour vont à la
    /// conversation ; la liaison perdue après « prêt » la coupe.
    static func monter(_ relais: RelaisDeTest) async throws -> (Conversation, ClientRelais, VoixMuette) {
        let voix = VoixMuette()
        let reglages = UserDefaults(suiteName: "tests.conversation")!
        reglages.removePersistentDomain(forName: "tests.conversation")
        let c = Conversation(voix: voix, reglages: reglages)
        var r = ClientRelais.Reglages()
        r.reconnexionInitiale = .milliseconds(50)
        r.reconnexionMaximale = .milliseconds(100)
        let client = ClientRelais(acces: relais, reglages: r)
        c.client = client
        let ecoute = Task { @MainActor in
            var etaitPret = false
            for await n in client.nouvelles {
                switch n {
                case .tour(let s): c.recevoir(s)
                case .etat(let e):
                    if case .pret = e {
                        etaitPret = true
                    } else if etaitPret {
                        etaitPret = false
                        await c.couper()
                    }
                default: break
                }
            }
        }
        _ = ecoute
        await client.demarrer()
        try await attendrePret(client)
        return (c, client, voix)
    }

    static func attendrePret(_ client: ClientRelais) async throws {
        for _ in 0..<300 {
            if case .pret = await client.etat { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("maison jamais prête")
    }

    /// Ouvre une conversation et commence une phrase sans la finir : le tour à la voix est en vol.
    static func parlerSansFinir(_ c: Conversation, _ voix: VoixMuette, _ relais: RelaisDeTest) async throws {
        await c.basculerEcoute()
        #expect(c.enConversation)
        // 100 ms de quasi-silence (le plancher de bruit descend), puis 400 ms de voix : une attaque
        voix.entendre([Float](repeating: 0.001, count: 1600))
        for _ in 0..<20 { voix.entendre([Float](repeating: 0.3, count: 320)) }
        for _ in 0..<300 {
            if await !relais.tours().isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("aucun tour à la voix")
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

    @Test("Demande lente : le clip d'accueil part dès la transcription, micro ouvert seulement")
    func accueil() async throws {
        let (c, client, voix) = try await Self.pret()
        await c.basculerEcoute()
        c.recevoir(.transcrit("Cherche la recette de la fondue"))
        #expect(voix.accueils == 1)
        c.recevoir(.transcrit("Allume le salon"))
        #expect(voix.accueils == 1)
        // la conversation fermée pendant la réflexion : plus de clip (la session audio n'est plus active)
        await c.couper()
        c.recevoir(.transcrit("Cherche la recette de la fondue"))
        #expect(voix.accueils == 1)
        await client.arreter()
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

    @Test("Un fil neuf à chaque conversation, et pour chaque question écrite hors conversation (le fil ENVOYÉ)")
    func filNeuf() async throws {
        let relais = RelaisDeTest()
        let (c, client, _) = try await Self.monter(relais)
        #expect(await c.ecrire("Quelle heure est-il ?"))
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 2 }
        #expect(c.conversationId == RelaisDeTest.fil, "le fil rendu par la maison")
        // une 2e question écrite, hors conversation : sans fil, malgré celui que la maison vient de rendre
        #expect(await c.ecrire("Et demain ?"))
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 4 }
        // une conversation : un fil neuf, que l'écrit garde ensuite
        await c.basculerEcoute()
        #expect(await c.ecrire("Allume la cuisine"))
        try await Self.attendre(c) { $0.phase == .ecoute && $0.messages.count == 6 }
        #expect(await c.ecrire("Et le salon ?"))
        try await Self.attendre(c) { $0.phase == .ecoute && $0.messages.count == 8 }
        await c.couper()
        #expect(await relais.tours().map(\.fil) == [nil, nil, nil, RelaisDeTest.fil])
        await client.arreter()
    }

    @Test("Écran allumé pendant une conversation, verrouillage d'iOS au repos (22.10 : il coupait tout)")
    func ecranAllume() async throws {
        let relais = RelaisDeTest()
        let (c, client, _) = try await Self.monter(relais)
        #expect(!c.ecranAllume, "au repos, l'iPhone se verrouille comme d'habitude")
        await c.basculerEcoute()
        #expect(c.enConversation && c.ecranAllume, "micro ouvert : pas de verrouillage")
        #expect(await c.ecrire("Quelle heure est-il ?"))
        try await Self.attendre(c) { $0.phase == .ecoute && $0.messages.count == 2 }
        #expect(c.ecranAllume, "après la réponse, Alfred réécoute : toujours allumé")
        await c.couper()
        try await Self.attendre(c) { $0.phase == .repos && !$0.enConversation }
        #expect(!c.ecranAllume, "conversation finie : le verrouillage reprend")
        await client.arreter()
    }

    @Test("Réponse d'Hermes au repos (22.10) : affichée comme une réponse d'Alfred, lue ; écran allumé jusque-là")
    func hermesAuRepos() async throws {
        let (c, client, voix) = try await Self.monter(RelaisDeTest())
        c.lireReponsesEcrites = true
        c.attendreHermes()
        #expect(c.ecranAllume, "l'attente de la réponse garde l'écran allumé")
        c.recevoirDifferee(texte: "La facture est arrivée.", chemin: "/tts/hermes.mp3")
        try await Self.attendre(c) { $0.phase == .repos && !$0.ecranAllume }
        #expect(c.messages.last?.auteur == .alfred && c.messages.last?.texte == "La facture est arrivée.")
        #expect(voix.lues == ["/tts/hermes.mp3"])
        #expect(c.attenteHermes == nil && c.differees.isEmpty)
        await client.arreter()
    }

    @Test("Réponse d'Hermes micro ouvert (22.10) : lue pendant que le micro n'écoute pas, puis Alfred réécoute")
    func hermesEnConversation() async throws {
        let (c, client, voix) = try await Self.monter(RelaisDeTest())
        await c.basculerEcoute()
        c.attendreHermes()
        c.recevoirDifferee(texte: "Réponse d’Hermes.", chemin: "/tts/hermes.mp3")
        try await Self.attendre(c) { $0.phase == .ecoute && !voix.lues.isEmpty }
        #expect(voix.lues == ["/tts/hermes.mp3"])
        #expect(c.enConversation && c.messages.last?.texte == "Réponse d’Hermes.")
        await c.couper()
        await client.arreter()
    }

    @Test("Réponse d'Hermes pendant un tour (22.10) : elle attend sa fin ; question écrite : affichée, pas lue")
    func hermesPendantUnTour() async throws {
        let (c, client, voix) = try await Self.monter(RelaisDeTest())
        c.attendreHermes()
        #expect(await c.ecrire("Quelle heure est-il ?"))
        c.recevoirDifferee(texte: "Plus tard.", chemin: "/tts/hermes.mp3")
        if c.phase == .reflexion {
            #expect(c.differees.count == 1, "un tour est en cours : la réponse d'Hermes attend")
        }
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count >= 3 }
        c.livrerDifferees()
        #expect(c.messages.contains { $0.auteur == .alfred && $0.texte == "Plus tard." })
        #expect(c.differees.isEmpty)
        #expect(voix.lues.isEmpty, "question écrite, réponses écrites non lues : affichée seulement")
        await client.arreter()
    }

    @Test("Attente d'Hermes : elle se ferme au bout de 5 min (le téléphone a pris le relais)")
    func hermesAttenteExpiree() async throws {
        let (c, client, _) = try await Self.monter(RelaisDeTest())
        c.attendreHermes()
        c.expirerAttenteHermes(maintenant: .now.addingTimeInterval(60))
        #expect(c.attenteHermes != nil)
        c.expirerAttenteHermes(maintenant: .now.addingTimeInterval(Conversation.attenteHermesMax + 1))
        #expect(c.attenteHermes == nil && !c.ecranAllume)
        await client.arreter()
    }

    @Test("Écrire dans une conversation : elle reste ouverte, la réponse est lue, puis Alfred réécoute (21.10)")
    func ecrireEnConversation() async throws {
        let relais = RelaisDeTest()
        let (c, client, voix) = try await Self.monter(relais)
        await c.basculerEcoute()
        #expect(c.enConversation && c.phase == .ecoute)
        #expect(await c.ecrire("Quelle heure est-il ?"))
        #expect(c.enConversation, "la conversation reste ouverte (la console : talk)")
        try await Self.attendre(c) { $0.phase == .ecoute && $0.messages.count == 2 }
        #expect(c.enConversation)
        #expect(c.messages[1].texte == RelaisDeTest.reponse)
        #expect(voix.lues == ["/tts/test.mp3"], "dans une conversation, la réponse est lue")
        #expect(c.annonce == nil, "micro ouvert : rien n'est annoncé à VoiceOver")
        await c.couper()
        await client.arreter()
    }

    @Test("Double appui sur « Envoyer » : une seule question part, sans faux avis")
    func doubleEnvoi() async throws {
        let relais = RelaisDeTest()
        let (c, client, _) = try await Self.monter(relais)
        async let premier = c.ecrire("Quelle heure est-il ?")
        async let second = c.ecrire("Quelle heure est-il ?")
        let partis = await [premier, second].filter { $0 }
        #expect(partis.count == 1)
        #expect(c.avis == nil, "pas de « Alfred termine la demande précédente »")
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 2 }
        #expect(await relais.tours().count == 1)
        await client.arreter()
    }

    @Test("VoiceOver : la réponse écrite non lue est annoncée ; lue à voix haute, elle ne l'est pas")
    func annonceVoiceOver() async throws {
        let relais = RelaisDeTest()
        let (c, client, voix) = try await Self.monter(relais)
        #expect(await c.ecrire("Quelle heure est-il ?"))
        try await Self.attendre(c) { $0.phase == .repos && $0.annonce != nil }
        #expect(c.annonce?.texte == RelaisDeTest.reponse)
        #expect(voix.lues.isEmpty)
        let premiere = c.annonce
        c.lireReponsesEcrites = true
        #expect(await c.ecrire("Et demain ?"))
        try await Self.attendre(c) { $0.phase == .repos && $0.messages.count == 4 }
        #expect(c.annonce == premiere, "lue à voix haute : pas annoncée")
        #expect(voix.lues.count == 1)
        await client.arreter()
    }

    @Test("Coupure en pleine phrase : la conversation se ferme et l'app revient au repos ; le noyau répond (21.10)")
    func coupureEnPleinePhrase() async throws {
        let relais = RelaisDeTest()
        let (c, client, voix) = try await Self.monter(relais)
        try await Self.parlerSansFinir(c, voix, relais)
        await relais.liaisons.last?.fermer()
        // avant la correction : la fermeture remettait la réflexion, pour toujours
        try await Self.attendre(c) { !$0.enConversation && $0.phase == .repos }
        #expect(c.messages.last?.erreur == true)
        try await Self.attendrePret(client)
        #expect(c.phase == .repos && c.peutEcrire)
        await c.basculerEcoute()
        #expect(c.enConversation, "le noyau rouvre une conversation")
        await c.couper()
        await client.arreter()
    }

    @Test("Tour refusé en pleine phrase : même retour au repos, sans coupure")
    func refusEnPleinePhrase() async throws {
        let relais = RelaisDeTest()
        relais.refuserTours = true
        let (c, client, voix) = try await Self.monter(relais)
        try await Self.parlerSansFinir(c, voix, relais)
        try await Self.attendre(c) { !$0.enConversation && $0.phase == .repos }
        #expect(c.peutEcrire)
        #expect(c.annonce != nil, "l'échec est annoncé une fois le micro fermé")
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

    @Test("Écouteurs branchés en pleine conversation : elle se ferme, et le dit")
    func materielChange() async throws {
        let (c, client, voix) = try await Self.pret()
        await c.basculerEcoute()
        #expect(c.enConversation)
        voix.simulerInterruption(VoixSysteme.motifMateriel)
        try await Self.attendre(c) { !$0.enConversation && $0.avis?.texte == VoixSysteme.motifMateriel }
        let avis = try #require(c.avis)
        c.oublierAvis(avis)
        // un appel (sans motif) : fermée aussi, sans rien dire de plus
        await c.basculerEcoute()
        #expect(c.enConversation, "rouverte")
        voix.simulerInterruption(nil)
        try await Self.attendre(c) { !$0.enConversation }
        #expect(c.avis == nil)
        await client.arreter()
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
