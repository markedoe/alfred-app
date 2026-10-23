import Foundation
import Testing

@testable import AlfredKit

@Suite("Les annexes de la console")
struct AnnexesTests {
    static func json(_ texte: String) -> Data { Data(texte.utf8) }

    @Test("Notifications : liste, non lues, champs absents")
    func notifications() throws {
        let l = try JSONDecoder().decode(
            ListeNotifications.self,
            from: Self.json(
                #"{"notifications":[{"id":"a1","t":1792240000.5,"titre":"Alfred","message":"Lessive finie","source":"x","lu":false},{"id":"b2","t":1792230000,"titre":"","message":"Réponse","lu":true}],"non_lues":1}"#
            ))
        #expect(l.nonLues == 1)
        #expect(l.notifications.map(\.id) == ["a1", "b2"])
        #expect(l.notifications[0].date == Date(timeIntervalSince1970: 1_792_240_000.5))
        #expect(!l.notifications[0].lu && l.notifications[1].lu)
        let vide = try JSONDecoder().decode(ListeNotifications.self, from: Self.json("{}"))
        #expect(vide.notifications.isEmpty && vide.nonLues == 0)
    }

    @Test("Documents : états de la console, Paperless (un objet), alerte")
    func documents() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"documents":[{"id":"20261018-101500-devis","nom":"devis","etat":"pret","resume":"Un devis.","depose_le":"2026-10-18T10:15:00+02:00","pour_le":"2026-10-20","paperless":{"tache":"x","le":"y"}},{"id":"b","nom":"lettre","etat":"en cours"},{"id":"c","nom":"photo","etat":"erreur","erreur":"illisible","alerte":"passage suspect"},{"id":"d","etat":"autre"}]}"#
            ))
        let d = l.documents
        #expect(d.map(\.etat) == [.pret, .enCours, .erreur, .enCours])
        #expect(d[0].paperless && !d[1].paperless)
        #expect(d[0].pourLe == "2026-10-20" && d[0].deposeLe == "2026-10-18T10:15:00+02:00")
        #expect(d[2].alerte == "passage suspect" && d[2].erreur == "illisible")
        #expect(d[3].nom == "d")
        #expect(DocumentMaison.vrai(.texte("")) == false && DocumentMaison.vrai(.nombre(0)) == false)
        #expect(DocumentMaison.vrai(.objet([:])) && DocumentMaison.vrai(.booleen(true)))
    }

    @Test("Dépôt : le corps multipart de la console (fichier, nom, pour le)")
    func depot() throws {
        let fichier = Data([0x25, 0x50, 0x44, 0x46, 0x0D, 0x0A, 0x00, 0xFF])
        let d = DepotDocument(
            fichier: fichier, nomFichier: "devis_toiture-2026.pdf", type: "application/pdf", pourLe: "2026-10-20")
        #expect(d.nom == "devis toiture 2026")
        let r = d.requete(frontiere: "FRONTIERE")
        #expect(r.methode == .post && r.chemin == "/docs")
        #expect(r.type == "multipart/form-data; boundary=FRONTIERE")
        var attendu = Data(
            ("--FRONTIERE\r\nContent-Disposition: form-data; name=\"fichier\"; filename=\"devis_toiture-2026.pdf\"\r\n"
                + "Content-Type: application/pdf\r\n\r\n").utf8)
        attendu.append(fichier)
        attendu.append(
            Data(
                ("\r\n--FRONTIERE\r\nContent-Disposition: form-data; name=\"nom\"\r\n\r\ndevis toiture 2026\r\n"
                    + "--FRONTIERE\r\nContent-Disposition: form-data; name=\"pour_le\"\r\n\r\n2026-10-20\r\n"
                    + "--FRONTIERE--\r\n").utf8))
        #expect(r.corps == attendu)
        let sansJour = DepotDocument(fichier: fichier, nomFichier: "a.pdf", type: "application/pdf")
        #expect(!String(decoding: sansJour.requete(frontiere: "F").corps!, as: UTF8.self).contains("pour_le"))
    }

    @Test("Dépôt : la frontière n'apparaît jamais dans le fichier ; un nom ne casse pas l'en-tête")
    func frontiere() {
        let piege = DepotDocument(fichier: Data("--F\r\n".utf8), nomFichier: "a\"b\nc.txt", type: "text/plain")
        let r = piege.requete(frontiere: "F")
        let frontiere = String(r.type!.split(separator: "=").last!)
        #expect(frontiere != "F" && frontiere.hasPrefix("F-"))
        #expect(piege.fichier.range(of: Data(frontiere.utf8)) == nil)
        #expect(String(decoding: r.corps!, as: UTF8.self).contains("filename=\"a%22b%0Ac.txt\""))
    }

    @Test("Liens : http(s) seulement")
    func liens() throws {
        let l = try #require(
            LienSysteme.lire(
                Self.json(
                    #"[{"nom":"Maison","url":"http://maison.example:8123","note":"la maison"},{"nom":"Faux","url":"javascript:alert(1)","note":""},{"nom":"Docs","url":"https://docs.example","note":null}]"#
                )))
        #expect(l.map(\.nom) == ["Maison", "Docs"])
        #expect(LienSysteme.lire(Self.json("{}")) == nil)
        #expect(LienSysteme.lire(Self.json("[]")) == [])
    }

    @Test("État des services : groupes, mots et noms courts de la console, panne, lien d'historique")
    func etat() throws {
        let e = try JSONDecoder().decode(
            EtatServices.self,
            from: Self.json(
                #"{"groupes":[{"nom":"Maison","services":[{"nom":"HA","statut":"ok","message":"","depuis":"2026-10-18 06:00:00.123"}]},{"nom":"Voix d'Alfred","services":[{"nom":"Modèle","statut":"eteint","message":null,"depuis":null},{"nom":"Garde","statut":"panne","message":"timeout","depuis":"2026-10-18T06:00:00Z"}]}],"kuma":"http://surveillance.example:3001/status/x"}"#
            ))
        #expect(e.groupes.map(\.nomCourt) == ["maison", "voix"])
        #expect(e.groupes[1].services.map(\.mot) == ["éteint (normal)", "EN PANNE"])
        #expect(e.panne)
        #expect(e.kuma?.host == "surveillance.example")
        // sans fuseau = UTC, comme la console
        let depuis = try #require(e.groupes[0].services[0].dateDepuis)
        #expect(abs(depuis.timeIntervalSince1970 - 1_792_303_200.123) < 0.001)
        #expect(e.groupes[1].services[1].dateDepuis == Date(timeIntervalSince1970: 1_792_303_200))
        let sansLien = try JSONDecoder().decode(EtatServices.self, from: Self.json(#"{"kuma":"file:///etc"}"#))
        #expect(sansLien.kuma == nil && sansLien.groupes.isEmpty && !sansLien.panne)
    }

    @Test("Réponse d'Hermes à lire (22.10) : champs lus, choisie si récente et pas réclamée, voix sûre seulement")
    func reponseHermes() throws {
        let l = try JSONDecoder().decode(
            ListeNotifications.self,
            from: Self.json(
                #"{"notifications":[{"id":"h2","t":1792240100,"titre":"Hermes","message":"Prise","source":"hermes","a_lire":true,"livree":true,"lu":true},{"id":"h1","t":1792240050,"titre":"Hermes","message":"La facture est arrivée.","source":"hermes","a_lire":true,"livree":false,"lu":false},{"id":"n1","t":1792240000,"message":"Lessive","source":"notify.mobile_app_m","lu":false}],"non_lues":2}"#
            ))
        let h1 = l.notifications[1]
        #expect(h1.aLire == true && h1.livree == false && l.notifications[2].aLire == nil)
        let question = Date(timeIntervalSince1970: 1_792_240_000)
        #expect(l.reponseHermes(depuis: question)?.id == "h1", "la déjà réclamée et l'ordinaire sont sautées")
        let apres = Date(timeIntervalSince1970: 1_792_240_200)
        #expect(l.reponseHermes(depuis: apres) == nil, "plus ancienne que la question")
        // 23.10 : deux questions de suite, deux réponses prêtes (le relais les range la plus récente d'abord) : la plus
        // ancienne d'abord, dans l'ordre des questions
        let deux = try JSONDecoder().decode(
            ListeNotifications.self,
            from: Self.json(
                #"{"notifications":[{"id":"h4","t":1792240090,"titre":"Hermes","message":"Seconde","source":"hermes","a_lire":true,"livree":false,"lu":false},{"id":"h3","t":1792240060,"titre":"Hermes","message":"Première","source":"hermes","a_lire":true,"livree":false,"lu":false}],"non_lues":2}"#
            ))
        #expect(deux.reponseHermes(depuis: question)?.id == "h3")
        let r = try JSONDecoder().decode(
            ReponseLivree.self, from: Self.json(#"{"ok":true,"message":"La facture est arrivée.","tts":"ab_12.mp3"}"#))
        #expect(r.ok && r.cheminVoix == "/tts/ab_12.mp3")
        #expect(ReponseLivree(ok: true, message: "x", tts: "../etat").cheminVoix == nil, "jamais une autre route")
        #expect(ReponseLivree(ok: true, message: "x", tts: nil).cheminVoix == nil)
        let non = try JSONDecoder().decode(ReponseLivree.self, from: Self.json(#"{"ok":false}"#))
        #expect(!non.ok && non.message == nil)
    }

    @Test("Heure d'une notification : comme la console")
    func quand() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
        let maintenant = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9)))
        func a(_ jour: Int, _ h: Int, _ m: Int) throws -> Date {
            try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: jour, hour: h, minute: m)))
        }
        #expect(Quand.texte(try a(18, 7, 5), maintenant: maintenant, calendrier: cal) == "07:05")
        #expect(Quand.texte(try a(17, 22, 40), maintenant: maintenant, calendrier: cal) == "hier 22:40")
        #expect(Quand.texte(try a(3, 14, 0), maintenant: maintenant, calendrier: cal) == "3.10 14:00")
    }

    @Test("Pièces citées dans une réponse, mode invités et voix (champs facultatifs)")
    func citees() throws {
        let c = try #require(
            ConsoleMaison.lire([
                "version": 1,
                "pieces": [
                    ["nom": "SALON", "etage": "rdc", "lumiere": "light.a", "mots": #"\bsalon\b"#],
                    ["nom": "BUREAU", "etage": "1er", "lumiere": "light.b", "mots": #"\bbureau\b(?! d.[ée]tude)"#],
                    ["nom": "ÉTUDE", "etage": "2e", "lumiere": "light.c", "mots": #"bureau d.[ée]tude"#],
                    ["nom": "CAVE", "etage": "ss", "lumiere": "light.d"],
                    ["nom": "CASSÉ", "etage": "ss", "lumiere": "light.e", "mots": "(["],
                ],
                "invites": "input_boolean.invites", "voix": "sensor.voix",
            ]))
        #expect(c.citees("Le Salon est allumé, le bureau aussi.").map(\.nom) == ["SALON", "BUREAU"])
        #expect(c.citees("J'ai éteint le bureau d'étude.").map(\.nom) == ["ÉTUDE"])
        #expect(c.citees("Rien ici, ni salons.").isEmpty)
        #expect(c.invites == "input_boolean.invites" && c.voix == "sensor.voix")
        #expect(c.entites.isSuperset(of: ["input_boolean.invites", "sensor.voix"]))
        let ancien = try #require(ConsoleMaison.lire(["version": 1, "pieces": [["nom": "A", "lumiere": "light.a"]]]))
        #expect(ancien.invites == nil && ancien.voix == nil && ancien.pieces[0].mots == nil)
    }

    @Test("Détails techniques : les arguments d'un outil, comme la console")
    func arguments() {
        let a = AppelOutil(
            id: "1", nom: "homeassistant__HassTurnOn",
            arguments: ["name": "Salon", "domain": ["light"], "brightness": 40, "ratio": 0.5, "seul": true])
        #expect(a.nomCourt == "HassTurnOn")
        #expect(a.argumentsEnTexte == #"40, ["light"], Salon, 0.5, true"#)
        #expect(AppelOutil(id: "2", nom: "x").argumentsEnTexte == "")
    }

    @Test("Modèle de la console : l'agent du pipeline préféré")
    func moteur() {
        let liste: ValeurJSON = [
            "pipelines": [
                ["id": "p1", "conversation_engine": "conversation.autre"],
                ["id": "p2", "conversation_engine": "conversation.gemma4_12b"],
            ]
        ]
        #expect(ClientRelais.moteur(liste, pipeline: "p2") == "gemma4_12b")
        #expect(ClientRelais.moteur(liste, pipeline: "p3") == nil)
        #expect(ClientRelais.moteur(liste, pipeline: nil) == nil)
        #expect(
            ClientRelais.moteur(["pipelines": [["id": "p", "conversation_engine": "agent"]]], pipeline: "p") == "agent")
    }
}
