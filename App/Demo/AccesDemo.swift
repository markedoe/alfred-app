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
        case "/maison/console": (200, Data(MaisonDemo.console.enTexte().utf8))
        case "/maison/structure": (200, Data(MaisonDemo.structure.enTexte().utf8))
        case "/moi": (200, Data(#"{"connecte":true,"nom":"Démo","user_id":null,"titre":"Monsieur"}"#.utf8))
        default: (404, Data())
        }
    }
}

/// L'état de la maison de démonstration : une roue de console de 14 pièces aux noms génériques, des mesures, la météo
/// et les jauges, comme la vraie (aucune donnée réelle).
actor MaisonDemo {
    struct Piece {
        let id: String
        let nom: String
        let mot: String
        let etage: String
        let allumee: Bool
        let temperature: String?
        let humidite: String?
    }

    static let pieces: [Piece] = [
        Piece(
            id: "cinema", nom: "CINÉMA", mot: "cinema", etage: "ss", allumee: false, temperature: "19.2", humidite: "58"
        ),
        Piece(
            id: "salon", nom: "SALON", mot: "salon", etage: "rdc", allumee: true, temperature: "21.4", humidite: "52"),
        Piece(
            id: "cuisine", nom: "CUISINE", mot: "cuisine", etage: "rdc", allumee: true, temperature: "22.1",
            humidite: nil),
        Piece(
            id: "manger", nom: "S. À MANGER", mot: "salle a manger", etage: "rdc", allumee: false, temperature: "21",
            humidite: nil),
        Piece(
            id: "entree", nom: "ENTRÉE", mot: "entree", etage: "rdc", allumee: false, temperature: nil, humidite: nil),
        Piece(
            id: "terrasse", nom: "TERRASSE", mot: "terrasse", etage: "rdc", allumee: false, temperature: nil,
            humidite: nil),
        Piece(
            id: "bureau", nom: "BUREAU", mot: "bureau", etage: "1er", allumee: true, temperature: "20.9", humidite: "48"
        ),
        Piece(
            id: "chambre", nom: "CHAMBRE", mot: "chambre", etage: "1er", allumee: false, temperature: "19.5",
            humidite: "50"),
        Piece(
            id: "sdb1", nom: "SDB 1ER", mot: "salle de bain", etage: "1er", allumee: false, temperature: "22.6",
            humidite: "64"),
        Piece(
            id: "escalier", nom: "ESCALIER", mot: "escalier", etage: "1-2", allumee: false, temperature: nil,
            humidite: nil),
        Piece(id: "jeux", nom: "JEUX", mot: "jeux", etage: "2e", allumee: false, temperature: "20.3", humidite: "47"),
        Piece(
            id: "amis", nom: "CH. AMIS", mot: "chambre d'amis", etage: "2e", allumee: false, temperature: nil,
            humidite: nil),
        Piece(
            id: "sdb2", nom: "SDB 2E", mot: "salle de bain du 2e", etage: "2e", allumee: false, temperature: "21.8",
            humidite: "61"),
        Piece(
            id: "couloir", nom: "COULOIR 2E", mot: "couloir", etage: "2e", allumee: false, temperature: nil,
            humidite: nil),
    ]

    static let console: ValeurJSON = [
        "version": 1,
        "pieces": .liste(
            pieces.map { p in
                [
                    "nom": .texte(p.nom), "etage": .texte(p.etage), "lumiere": .texte("light.demo_\(p.id)"),
                    "temperature": p.temperature == nil ? .nul : .texte("sensor.demo_\(p.id)_t"),
                    "humidite": p.humidite == nil ? .nul : .texte("sensor.demo_\(p.id)_h"),
                    "air": p.id == "salon" ? "sensor.demo_salon_cov" : .nul,
                ]
            }),
        "autres": [
            [
                "nom": "BUANDERIE", "etage": "ss", "temperature": "sensor.demo_buanderie_t",
                "humidite": "sensor.demo_buanderie_h",
            ],
            ["nom": "CAVE", "etage": "ss", "temperature": "sensor.demo_cave_t", "humidite": "sensor.demo_cave_h"],
        ],
        "jauges": [
            ["entite": "sensor.demo_gpu", "libelle": "gpu", "unite": "°", "max": 100],
            ["entite": "sensor.demo_pc", "libelle": "pc", "unite": "W", "max": 400],
            ["entite": "sensor.demo_maison", "libelle": "maison", "unite": "W", "max": 6000],
            ["entite": "sensor.demo_jour", "libelle": "jour", "unite": "kWh", "max": 10],
        ],
        "meteo": "weather.demo", "puissance": "sensor.demo_maison",
    ]

    /// Les pièces de HA (relais d'avant `/maison/console`) : une lumière par pièce.
    static let structure: ValeurJSON = [
        "version": 1,
        "etages": [["id": "rdc", "nom": "Rez-de-chaussée", "niveau": 0]],
        "pieces": .liste(pieces.map { ["id": .texte($0.id), "nom": .texte($0.nom.capitalized), "etage": "rdc"] }),
        "lumieres": .objet(
            Dictionary(uniqueKeysWithValues: pieces.map { ("light.demo_\($0.id)", ValeurJSON.texte($0.id)) })),
    ]

    private var etats: [String: ValeurJSON] = {
        var e: [String: ValeurJSON] = [:]
        func capteur(_ id: String, _ valeur: String, _ unite: String) {
            e[id] = [
                "entity_id": .texte(id), "state": .texte(valeur), "attributes": ["unit_of_measurement": .texte(unite)],
            ]
        }
        for p in MaisonDemo.pieces {
            let id = "light.demo_\(p.id)"
            e[id] = [
                "entity_id": .texte(id), "state": p.allumee ? "on" : "off",
                "attributes": ["friendly_name": .texte(p.nom.capitalized), "supported_color_modes": ["brightness"]],
            ]
            if let t = p.temperature { capteur("sensor.demo_\(p.id)_t", t, "°C") }
            if let h = p.humidite { capteur("sensor.demo_\(p.id)_h", h, "%") }
        }
        capteur("sensor.demo_salon_cov", "182", "µg/m³")
        capteur("sensor.demo_buanderie_t", "20.5", "°C")
        capteur("sensor.demo_buanderie_h", "59", "%")
        capteur("sensor.demo_cave_t", "17.8", "°C")
        capteur("sensor.demo_cave_h", "66", "%")
        capteur("sensor.demo_gpu", "41", "°C")
        capteur("sensor.demo_pc", "86", "W")
        capteur("sensor.demo_maison", "640", "W")
        capteur("sensor.demo_jour", "1.42", "kWh")
        e["weather.demo"] = [
            "entity_id": "weather.demo", "state": "partlycloudy",
            "attributes": [
                "temperature": 14.5, "temperature_unit": "°C", "humidity": 72, "wind_speed": 9,
                "wind_speed_unit": "km/h", "wind_bearing": 250, "pressure": 1018, "pressure_unit": "hPa",
                "uv_index": 2.1, "cloud_coverage": 40,
            ],
        ]
        return e
    }()

    var tous: ValeurJSON { .liste(Array(etats.values)) }

    /// Applique un service de lumière (par entité, ou par pièce) ; rend les nouveaux états.
    func service(_ service: String, cible: ValeurJSON?, donnees: ValeurJSON?) -> [ValeurJSON] {
        var ids: [String] = []
        if let e = cible?["entity_id"]?.texte { ids = [e] }
        if let e = cible?["entity_id"]?.liste { ids = e.compactMap(\.texte) }
        if let area = cible?["area_id"]?.texte { ids = ["light.demo_\(area)"] }
        return ids.compactMap { id in
            guard case .objet(var o)? = etats[id] else { return nil }
            let allumer = service == "turn_on" || (service == "toggle" && o["state"] == "off")
            o["state"] = allumer ? "on" : "off"
            etats[id] = .objet(o)
            return .objet(o)
        }
    }

    /// La réponse de démonstration à une phrase.
    func repondre(_ texte: String) -> (outil: AppelOutil?, service: (String, String)?, reponse: String) {
        let t = texte.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_CH"))
        // le nom le plus long d'abord (« salle de bain du 2e » avant « salle de bain »)
        let piece = Self.pieces.sorted { $0.mot.count > $1.mot.count }.first { t.contains($0.mot) }
        let nom = piece.map { String($0.nom.prefix(1)) + $0.nom.dropFirst().lowercased() } ?? ""
        if let piece, t.contains("allume") {
            return (
                AppelOutil(id: UUID().uuidString, nom: "HassTurnOn", arguments: ["area": .texte(nom)]),
                ("turn_on", piece.id), "C’est fait : j’ai allumé la pièce \(nom)."
            )
        }
        if let piece, t.contains("eteins") || t.contains("eteint") {
            return (
                AppelOutil(id: UUID().uuidString, nom: "HassTurnOff", arguments: ["area": .texte(nom)]),
                ("turn_off", piece.id), "C’est fait : j’ai éteint la pièce \(nom)."
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
