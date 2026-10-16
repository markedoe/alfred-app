import Foundation
import Testing

@testable import AlfredKit

@Suite("Messages du relais")
struct MessagesTests {
    @Test("ready, fatal, result, event")
    func types() {
        #expect(MessageEntrant.lire(#"{"type":"ready","ha_version":"2026.9.4"}"#) == .pret(versionHA: "2026.9.4"))
        #expect(MessageEntrant.lire(#"{"type":"fatal","message":"jeton refusé"}"#) == .fatal("jeton refusé"))
        #expect(MessageEntrant.lire("pas du JSON") == nil)
        #expect(MessageEntrant.lire("[1,2]") == nil)
        guard
            case .resultat(let r) = MessageEntrant.lire(
                #"{"id":4,"type":"result","success":false,"error":{"code":"refuse","message":"action non permise"}}"#)
        else {
            Issue.record("result illisible")
            return
        }
        #expect(r.id == 4 && !r.succes && r.erreur == .init(code: "refuse", message: "action non permise"))
    }

    @Test("state_changed : nouvel état, et entité supprimée")
    func etatChange() {
        let m = MessageEntrant.lire(
            #"{"id":2,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.exemple","new_state":{"entity_id":"light.exemple","state":"on","attributes":{"friendly_name":"Exemple","brightness":128},"last_changed":"2026-10-16T10:00:00+00:00"}}}}"#
        )
        guard case .evenement(2, .etatChange(let id, let e?)) = m else {
            Issue.record("\(String(describing: m))")
            return
        }
        #expect(id == "light.exemple" && e.etat == "on" && e.nom == "Exemple" && e.domaine == "light")
        #expect(e.attributs["brightness"]?.entier == 128)
        let s = MessageEntrant.lire(
            #"{"id":2,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.exemple","new_state":null}}}"#
        )
        #expect(s == .evenement(id: 2, .etatChange(entite: "light.exemple", nouvelEtat: nil)))
    }

    @Test("Un état numérique invalide n'est pas un nombre")
    func nombres() {
        #expect(EtatEntite(id: "sensor.t", etat: "21.5").nombre == 21.5)
        #expect(EtatEntite(id: "sensor.t", etat: "23oops").nombre == nil)
        #expect(EtatEntite(id: "sensor.t", etat: "unavailable").nombre == nil)
        #expect(EtatEntite(id: "sensor.t", etat: "nan").nombre == nil)
    }

    @Test("La voix arrive par le relais, sous /tts/<jeton>")
    func voix() {
        let e = EvenementPipeline(
            type: "tts-end", donnees: ["tts_output": ["url": "http://ha.exemple:8123/api/tts_proxy/x_y-z.mp3"]])
        #expect(e == .voix(chemin: "/tts/x_y-z.mp3"))
        #expect(EvenementPipeline(type: "tts-end", donnees: ["tts_output": [:]]) == .autre("tts-end"))
    }

    @Test("Le canal audio est un octet")
    func canal() {
        #expect(
            EvenementPipeline(type: "run-start", donnees: ["runner_data": ["stt_binary_handler_id": 1]])
                == .debut(canalAudio: 1, conversationId: nil))
        #expect(
            EvenementPipeline(type: "run-start", donnees: ["runner_data": ["stt_binary_handler_id": 300]])
                == .debut(canalAudio: nil, conversationId: nil))
    }

    @Test("Nom court d'un outil et entités visées")
    func outil() {
        let a = AppelOutil(
            id: "1", nom: "homeassistant__HassTurnOn",
            arguments: ["domain": ["light"], "entity_id": ["light.b", "light.a"], "brightness": 50])
        #expect(a.nomCourt == "HassTurnOn")
        #expect(a.entitesVisees == ["light.b", "light.a"])
    }

    @Test("JSON : aller-retour stable, entiers sans virgule")
    func json() {
        let v: ValeurJSON = ["b": 1, "a": [true, nil, 1.5, "x/y"]]
        #expect(v.enTexte() == #"{"a":[true,null,1.5,"x/y"],"b":1}"#)
        #expect(ValeurJSON.lire(v.enTexte()) == v)
        #expect(ValeurJSON.lire("true") == .booleen(true))
        #expect(ValeurJSON.lire("1") == .nombre(1))
    }

    @Test("Demandes lentes (clip d'accueil tout de suite)")
    func lentes() {
        #expect(DemandeLente.estLente("Cherche la météo à Lausanne"))
        #expect(DemandeLente.estLente("Alfred, recette de la fondue"))
        #expect(DemandeLente.estLente("ok demande à Claude pourquoi le ciel est bleu"))
        #expect(DemandeLente.estLente("Actualités"))
        #expect(!DemandeLente.estLente("Allume le salon"))
        #expect(!DemandeLente.estLente("Je cherche mes clés"))
    }

    @Test("Clips d'accueil selon le titre")
    func clips() {
        #expect(ClipsAlfred.accueil(3, titre: "Monsieur") == "/static/ack/ack-3.mp3")
        #expect(ClipsAlfred.accueil(1, titre: "Madame") == "/static/ack/ack-1-madame.mp3")
        #expect(ClipsAlfred.accueil(2, titre: "") == "/static/ack/ack-2-neutre.mp3")
        #expect(ClipsAlfred.accueil(2, titre: "Majesté") == "/static/ack/ack-2.mp3")
        for dernier in 1...6 {
            for tirage in 0..<12 {
                let n = ClipsAlfred.prochainAccueil(apres: dernier, tirage: tirage)
                #expect((1...6).contains(n) && n != dernier)
            }
        }
    }

    @Test("Adresse du relais : https seulement, sans chemin")
    func relais() throws {
        let r = try #require(Relais(adresse: "relais.exemple.ch/"))
        #expect(r.base.absoluteString == "https://relais.exemple.ch")
        #expect(r.webSocket.absoluteString == "wss://relais.exemple.ch/ws")
        #expect(r.url("/tts/a.mp3").absoluteString == "https://relais.exemple.ch/tts/a.mp3")
        #expect(Relais(adresse: "http://relais.exemple.ch") == nil)
        #expect(Relais(adresse: "https://relais.exemple.ch/console") == nil)
        let c = try #require(SessionRelais(valeur: "abc").cookie(pour: r))
        #expect(c.name == "alfred_session" && c.domain == "relais.exemple.ch" && c.isSecure)
    }

    @Test("/moi")
    func moi() throws {
        let m = try JSONDecoder().decode(
            Moi.self, from: Data(#"{"connecte":true,"nom":"Personne","user_id":"u1","titre":"Madame"}"#.utf8))
        #expect(m == Moi(connecte: true, nom: "Personne", userId: "u1", titre: "Madame"))
    }
}
