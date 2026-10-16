import Foundation
import Testing

@testable import AlfredKit

/// Les règles du tour de conversation, reprises des tests de la console (`test_ux.cjs`).
@Suite("Tour de conversation")
struct AutomateTourTests {
    static func evenement(_ id: Int, _ type: String, _ data: ValeurJSON = [:]) -> MessageEntrant {
        MessageEntrant.lire(
            ValeurJSON.objet([
                "id": .nombre(Double(id)), "type": "event",
                "event": ["type": .texte(type), "data": data],
            ]).enTexte())!
    }

    static func signaux(_ effets: [AutomateTour.Effet]) -> [AutomateTour.Signal] {
        effets.compactMap {
            if case .signal(let s) = $0 { return s }
            return nil
        }
    }

    static func audio(_ effets: [AutomateTour.Effet]) -> [[UInt8]] {
        effets.compactMap {
            if case .envoyerAudio(let d) = $0 { return Array(d) }
            return nil
        }
    }

    @Test("Le message de départ : voix, pipeline, conversation")
    func messageDepartVoix() throws {
        var t = AutomateTour()
        let depart = t.commencer(id: 12, mode: .voix, pipeline: "p1", conversationId: "c9")
        let effets = try #require(depart)
        guard case .envoyer(let texte) = effets.first else {
            Issue.record("pas d'envoi")
            return
        }
        #expect(
            texte
                == #"{"conversation_id":"c9","end_stage":"tts","id":12,"input":{"no_vad":true,"sample_rate":16000},"pipeline":"p1","start_stage":"stt","type":"assist_pipeline/run"}"#
        )
        #expect(effets.last == .armerDelai(.seconds(90)))
    }

    @Test("Le message de départ écrit commence à l'intention")
    func messageDepartTexte() throws {
        var t = AutomateTour()
        let depart = t.commencer(id: 3, mode: .texte("Quelle heure est-il ?"))
        let effets = try #require(depart)
        guard case .envoyer(let texte) = effets.first else {
            Issue.record("pas d'envoi")
            return
        }
        let m = try #require(ValeurJSON.lire(texte))
        #expect(m["start_stage"] == "intent")
        #expect(m["input"]?["text"] == "Quelle heure est-il ?")
        #expect(m["pipeline"] == nil)
    }

    @Test("Une 2e demande pendant un tour est refusée")
    func doublonRefuse() {
        var t = AutomateTour()
        #expect(t.commencer(id: 1, mode: .texte("a")) != nil)
        #expect(t.commencer(id: 2, mode: .texte("b")) == nil)
        #expect(t.actif == 1)
    }

    @Test("Un événement d'un autre tour (périmé) est ignoré")
    func perimeIgnore() {
        var t = AutomateTour()
        _ = t.commencer(id: 900_001, mode: .texte("Test"))
        let e = t.recevoir(
            Self.evenement(
                900_000, "intent-end",
                ["intent_output": ["response": ["speech": ["plain": ["speech": "Événement périmé"]]]]]))
        #expect(e.isEmpty)
        #expect(t.occupe)
    }

    @Test("Un refus de HA pour ce tour le libère, avec son message")
    func refusLibere() {
        var t = AutomateTour()
        _ = t.commencer(id: 900_001, mode: .texte("Test"))
        let m = MessageEntrant.lire(
            #"{"type":"result","id":900001,"success":false,"error":{"message":"Refus simulé"}}"#)!
        let e = t.recevoir(m)
        #expect(e == [.annulerDelai, .signal(.echec("Refus simulé"))])
        #expect(!t.occupe)
    }

    @Test("Le succès du lancement (result success) ne termine pas le tour")
    func succesLancement() {
        var t = AutomateTour()
        _ = t.commencer(id: 5, mode: .texte("Test"))
        #expect(t.recevoir(MessageEntrant.lire(#"{"type":"result","id":5,"success":true,"result":null}"#)!).isEmpty)
        #expect(t.occupe)
    }

    @Test("Parole finie avant run-start : la file part, puis la trame de fin")
    func finAvantDebut() {
        var t = AutomateTour()
        _ = t.commencer(id: 900_001, mode: .voix, amorce: [Data([1, 2])])
        #expect(t.finParole().isEmpty)
        let e = t.recevoir(Self.evenement(900_001, "run-start", ["runner_data": ["stt_binary_handler_id": 7]]))
        #expect(Self.audio(e) == [[7, 1, 2], [7]])
    }

    @Test("L'audio avant run-start est gardé, puis préfixé par le canal")
    func audioEnFile() {
        var t = AutomateTour()
        _ = t.commencer(id: 4, mode: .voix)
        #expect(t.audio(Data([10, 11])).isEmpty)
        #expect(t.audio(Data([12])).isEmpty)
        let e = t.recevoir(Self.evenement(4, "run-start", ["runner_data": ["stt_binary_handler_id": 3]]))
        #expect(Self.audio(e) == [[3, 10, 11], [3, 12]])
        #expect(Self.audio(t.audio(Data([13]))) == [[3, 13]])
        #expect(Self.audio(t.finParole()) == [[3]])
        #expect(t.audio(Data([14])).isEmpty, "rien n'est envoyé après la fin de la parole")
    }

    @Test("Délai dépassé : échec, et un événement tardif ne produit plus rien")
    func delaiDepasse() {
        var t = AutomateTour()
        _ = t.commencer(id: 8, mode: .texte("allume le bureau"))
        #expect(Self.signaux(t.delaiDepasse()) == [.echec(AutomateTour.messageDelai)])
        let tard = t.recevoir(
            Self.evenement(
                8, "intent-end",
                ["intent_output": ["response": ["speech": ["plain": ["speech": "Fait"]]]]]))
        #expect(tard.isEmpty)
        #expect(!t.occupe)
    }

    @Test("Rien de compris : signal à part ; une autre erreur : échec")
    func erreurs() {
        var t = AutomateTour()
        _ = t.commencer(id: 1, mode: .voix)
        let r = t.recevoir(
            Self.evenement(1, "error", ["code": "stt-no-text-recognized", "message": "No text recognized"]))
        #expect(Self.signaux(r) == [.rienSaisi(message: "No text recognized")])
        _ = t.commencer(id: 2, mode: .voix)
        let e = t.recevoir(Self.evenement(2, "error", ["code": "intent-failed"]))
        #expect(Self.signaux(e) == [.echec("intent-failed")])
    }

    @Test("Un tour complet : transcription, outils (2e appel sans role), réponse, voix, fin")
    func tourComplet() {
        var t = AutomateTour()
        _ = t.commencer(id: 1, mode: .voix)
        var s: [AutomateTour.Signal] = []
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "run-start",
                    ["conversation_id": "c1", "runner_data": ["stt_binary_handler_id": 1]])))
        s += Self.signaux(
            t.recevoir(Self.evenement(1, "stt-end", ["stt_output": ["text": "Allume le bureau et la cuisine"]])))
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "intent-progress",
                    [
                        "chat_log_delta": [
                            "role": "assistant",
                            "tool_calls": [["id": "a1", "tool_name": "HassTurnOn", "tool_args": ["name": "Bureau"]]],
                        ]
                    ])))
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "intent-progress",
                    [
                        "chat_log_delta": [
                            "tool_calls": [["id": "a2", "tool_name": "HassTurnOn", "tool_args": ["name": "Cuisine"]]]
                        ]
                    ])))
        // le même appel répété n'est compté qu'une fois
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "intent-progress",
                    [
                        "chat_log_delta": [
                            "tool_calls": [["id": "a2", "tool_name": "HassTurnOn", "tool_args": ["name": "Cuisine"]]]
                        ]
                    ])))
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "intent-progress",
                    [
                        "chat_log_delta": [
                            "role": "tool_result", "tool_call_id": "a1", "tool_name": "HassTurnOn",
                            "tool_result": ["speech": [:]],
                        ]
                    ])))
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "intent-progress",
                    [
                        "chat_log_delta": [
                            "role": "tool_result", "tool_call_id": "a2", "tool_name": "HassTurnOn",
                            "tool_result": ["success": false],
                        ]
                    ])))
        s += Self.signaux(
            t.recevoir(
                Self.evenement(1, "intent-progress", ["chat_log_delta": ["role": "assistant", "content": "C'est "]])))
        s += Self.signaux(t.recevoir(Self.evenement(1, "intent-progress", ["chat_log_delta": ["content": "fait."]])))
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "intent-end",
                    [
                        "processed_locally": false,
                        "intent_output": [
                            "conversation_id": "c1", "continue_conversation": true,
                            "response": ["speech": ["plain": ["speech": "C'est fait. Autre chose ?"]]],
                        ],
                    ])))
        s += Self.signaux(
            t.recevoir(
                Self.evenement(
                    1, "tts-end", ["tts_output": ["url": "/api/tts_proxy/abc123.mp3", "mime_type": "audio/mpeg"]])))
        let fin = t.recevoir(Self.evenement(1, "run-end"))
        s += Self.signaux(fin)
        #expect(
            s == [
                .transcrit("Allume le bureau et la cuisine"), .reflechit,
                .outilCommence(AppelOutil(id: "a1", nom: "HassTurnOn", arguments: ["name": "Bureau"])),
                .outilCommence(AppelOutil(id: "a2", nom: "HassTurnOn", arguments: ["name": "Cuisine"])),
                .outilTermine(appelId: "a1", succes: true),
                .outilTermine(appelId: "a2", succes: false),
                .fragment("C'est "), .fragment("fait."),
                .reponse(FinIntention(conversationId: "c1", continuer: true, texte: "C'est fait. Autre chose ?")),
                .voix(chemin: "/tts/abc123.mp3"),
                .termine(conversationId: "c1", continuer: true),
            ])
        #expect(fin.first == .annulerDelai)
        #expect(!t.occupe)
    }

    @Test("Coupure du lien pendant un tour : échec, tour libéré")
    func coupure() {
        var t = AutomateTour()
        _ = t.commencer(id: 1, mode: .voix)
        #expect(Self.signaux(t.lienCoupe()) == [.echec("Liaison interrompue avec la maison.")])
        #expect(t.lienCoupe().isEmpty)
    }
}
