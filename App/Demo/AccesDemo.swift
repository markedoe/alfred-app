import AlfredKit
import Foundation

/// Une maison simulée (noms génériques) qui parle comme le relais : la démo, les tests d'interface et les aperçus.
/// Aucune donnée réelle, aucun réseau.
final class AccesDemo: AccesRelais, @unchecked Sendable {
    private let maison = MaisonDemo()

    func ouvrir() async throws -> any Liaison {
        let l = LiaisonDemo(maison: maison)
        await l.pousser(["type": "ready", "ha_version": "démo"])
        return l
    }

    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) {
        switch chemin {
        case "/maison/structure": (200, Data(MaisonDemo.structure.enTexte().utf8))
        case "/moi": (200, Data(#"{"connecte":true,"nom":"Démo","user_id":null,"titre":"Monsieur"}"#.utf8))
        default: (404, Data())
        }
    }
}

/// L'état de la maison de démonstration.
actor MaisonDemo {
    static let pieces: [(id: String, nom: String, etage: String, lumieres: [(String, String, Bool)])] = [
        (
            "salon", "Salon", "rez",
            [("light.salon_lampadaire", "Lampadaire", true), ("light.salon_plafond", "Plafonnier", false)]
        ),
        ("cuisine", "Cuisine", "rez", [("light.cuisine_plan", "Plan de travail", true)]),
        ("entree", "Entrée", "rez", [("light.entree", "Entrée", false)]),
        (
            "chambre", "Chambre", "etage",
            [("light.chambre_chevet", "Chevet", false), ("light.chambre_plafond", "Plafonnier", false)]
        ),
        ("bureau", "Bureau", "etage", [("light.bureau", "Lampe de bureau", true)]),
        ("terrasse", "Terrasse", "jardin", [("light.terrasse", "Guirlande", false)]),
    ]

    static let structure: ValeurJSON = [
        "version": 1,
        "etages": [
            ["id": "etage", "nom": "Étage", "niveau": 1], ["id": "rez", "nom": "Rez-de-chaussée", "niveau": 0],
            ["id": "jardin", "nom": "Jardin", "niveau": -1],
        ],
        "pieces": .liste(
            pieces.map { p in
                [
                    "id": .texte(p.id), "nom": .texte(p.nom), "etage": .texte(p.etage),
                    "temperature": p.id == "terrasse" ? .nul : .texte("sensor.\(p.id)_temperature"), "humidite": .nul,
                ]
            }),
        "lumieres": .objet(
            Dictionary(uniqueKeysWithValues: pieces.flatMap { p in p.lumieres.map { ($0.0, ValeurJSON.texte(p.id)) } })),
    ]

    private var etats: [String: ValeurJSON] = {
        var e: [String: ValeurJSON] = [:]
        for p in MaisonDemo.pieces {
            for (id, nom, allumee) in p.lumieres {
                e[id] = [
                    "entity_id": .texte(id), "state": allumee ? "on" : "off",
                    "attributes": [
                        "friendly_name": .texte(nom), "supported_color_modes": ["brightness"],
                        "brightness": allumee ? 180 : .nul,
                    ],
                ]
            }
            if p.id != "terrasse" {
                let t =
                    ["salon": "21.4", "cuisine": "22.1", "entree": "19.8", "chambre": "19.5", "bureau": "20.9"][p.id]
                    ?? "20"
                e["sensor.\(p.id)_temperature"] = [
                    "entity_id": .texte("sensor.\(p.id)_temperature"), "state": .texte(t),
                    "attributes": ["unit_of_measurement": "°C", "device_class": "temperature"],
                ]
            }
        }
        return e
    }()

    var tous: ValeurJSON { .liste(Array(etats.values)) }

    /// Applique un service de lumière ; rend les nouveaux états.
    func service(_ service: String, cible: ValeurJSON?, donnees: ValeurJSON?) -> [ValeurJSON] {
        var ids: [String] = []
        if let e = cible?["entity_id"]?.texte { ids = [e] }
        if let e = cible?["entity_id"]?.liste { ids = e.compactMap(\.texte) }
        if let area = cible?["area_id"]?.texte {
            ids = Self.pieces.first { $0.id == area }?.lumieres.map(\.0) ?? []
        }
        return ids.compactMap { id in
            guard case .objet(var o)? = etats[id] else { return nil }
            let allumer = service == "turn_on" || (service == "toggle" && o["state"] == "off")
            o["state"] = allumer ? "on" : "off"
            if case .objet(var a)? = o["attributes"] {
                let pct = donnees?["brightness_pct"]?.nombre
                a["brightness"] = allumer ? .nombre(((pct ?? 70) * 255 / 100).rounded()) : .nul
                o["attributes"] = .objet(a)
            }
            etats[id] = .objet(o)
            return .objet(o)
        }
    }

    /// La réponse de démonstration à une phrase.
    func repondre(_ texte: String) -> (outil: AppelOutil?, service: (String, String)?, reponse: String) {
        let t = texte.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_CH"))
        let piece = Self.pieces.first {
            t.contains($0.nom.lowercased().folding(options: .diacriticInsensitive, locale: nil))
        }
        if let piece, t.contains("allume") {
            return (
                AppelOutil(id: UUID().uuidString, nom: "HassTurnOn", arguments: ["area": .texte(piece.nom)]),
                ("turn_on", piece.id), "C’est fait : \(piece.nom.lowercased()) allumé."
            )
        }
        if let piece, t.contains("eteins") || t.contains("eteint") {
            return (
                AppelOutil(id: UUID().uuidString, nom: "HassTurnOff", arguments: ["area": .texte(piece.nom)]),
                ("turn_off", piece.id), "C’est fait : \(piece.nom.lowercased()) éteint."
            )
        }
        if t.contains("heure") {
            return (nil, nil, "Il est \(Date.now.formatted(date: .omitted, time: .shortened)).")
        }
        return (nil, nil, "Je suis la démonstration d’Alfred. Essayez « allume le salon ».")
    }
}

/// La WebSocket simulée : répond comme HA à travers le relais.
actor LiaisonDemo: Liaison {
    private let maison: MaisonDemo
    private var file: [Trame] = []
    private var attente: CheckedContinuation<Trame, Error>?
    private var fermee = false

    init(maison: MaisonDemo) {
        self.maison = maison
    }

    func pousser(_ m: ValeurJSON) {
        let t = Trame.texte(m.enTexte())
        if let a = attente {
            attente = nil
            a.resume(returning: t)
        } else {
            file.append(t)
        }
    }

    func recevoir() async throws -> Trame {
        if !file.isEmpty { return file.removeFirst() }
        if fermee { throw ErreurRelais.lienCoupe }
        return try await withCheckedThrowingContinuation { attente = $0 }
    }

    func fermer() async {
        fermee = true
        attente?.resume(throwing: ErreurRelais.lienCoupe)
        attente = nil
    }

    func envoyer(_ trame: Trame) async throws {
        guard case .texte(let t) = trame, let m = ValeurJSON.lire(t), let id = m["id"] else { return }
        switch m["type"]?.texte {
        case "get_states":
            pousser(["id": id, "type": "result", "success": true, "result": await maison.tous])
        case "subscribe_events", "assist_pipeline/pipeline/list":
            pousser([
                "id": id, "type": "result", "success": true,
                "result": m["type"] == "subscribe_events" ? .nul : ["pipelines": [], "preferred_pipeline": "demo"],
            ])
        case "call_service":
            pousser(["id": id, "type": "result", "success": true, "result": .nul])
            let nouveaux = await maison.service(
                m["service"]?.texte ?? "", cible: m["target"], donnees: m["service_data"])
            try? await Task.sleep(for: .milliseconds(250))
            for e in nouveaux { pousser(changement(e)) }
        case "assist_pipeline/run":
            await tour(id: id, texte: m["input"]?["text"]?.texte)
        default:
            pousser([
                "id": id, "type": "result", "success": false, "error": ["code": "refuse", "message": "non permis"],
            ])
        }
    }

    private func changement(_ e: ValeurJSON) -> ValeurJSON {
        [
            "id": 0, "type": "event",
            "event": ["event_type": "state_changed", "data": ["entity_id": e["entity_id"] ?? .nul, "new_state": e]],
        ]
    }

    private func evenement(_ id: ValeurJSON, _ type: String, _ data: ValeurJSON = [:]) -> ValeurJSON {
        ["id": id, "type": "event", "event": ["type": .texte(type), "data": data]]
    }

    /// Un tour écrit (la démo n'a pas de micro).
    private func tour(id: ValeurJSON, texte: String?) async {
        pousser(["id": id, "type": "result", "success": true, "result": .nul])
        pousser(evenement(id, "run-start", ["conversation_id": "demo", "runner_data": [:]]))
        guard let texte else {
            pousser(
                evenement(id, "error", ["code": "stt-no-text-recognized", "message": "Aucun son en démonstration."]))
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        let r = await maison.repondre(texte)
        if let outil = r.outil {
            pousser(
                evenement(
                    id, "intent-progress",
                    [
                        "chat_log_delta": [
                            "role": "assistant",
                            "tool_calls": [
                                ["id": .texte(outil.id), "tool_name": .texte(outil.nom), "tool_args": outil.arguments]
                            ],
                        ]
                    ]))
            if let (service, piece) = r.service {
                for e in await maison.service(service, cible: ["area_id": .texte(piece)], donnees: nil) {
                    pousser(changement(e))
                }
            }
            try? await Task.sleep(for: .milliseconds(300))
            pousser(
                evenement(
                    id, "intent-progress",
                    [
                        "chat_log_delta": [
                            "role": "tool_result", "tool_call_id": .texte(outil.id), "tool_name": .texte(outil.nom),
                            "tool_result": [:],
                        ]
                    ]))
        }
        pousser(
            evenement(
                id, "intent-end",
                [
                    "processed_locally": false,
                    "intent_output": [
                        "conversation_id": "demo", "continue_conversation": false,
                        "response": ["speech": ["plain": ["speech": .texte(r.reponse)]]],
                    ],
                ]))
        pousser(evenement(id, "run-end"))
    }
}
