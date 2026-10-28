import AlfredKit
import Foundation

/// Une maison simulée (noms génériques) qui parle comme le relais : la démo, les tests d'interface et les aperçus.
/// Aucune donnée réelle, aucun réseau.
final class AccesDemo: AccesRelais, @unchecked Sendable {
    private let maison = MaisonDemo()
    private let annexes = AnnexesDemo()

    func ouvrir() async throws -> any Liaison {
        let l = LiaisonDemo(maison: maison)
        await l.pousser(["type": "ready", "ha_version": "démo"])
        return l
    }

    func lire(_ chemin: String) async throws -> (statut: Int, corps: Data) {
        let corps: ValeurJSON
        switch chemin {
        case "/maison/console": corps = MaisonDemo.console
        case "/maison/structure": corps = MaisonDemo.structure
        case "/moi": corps = ["connecte": true, "nom": "Démo", "user_id": .nul, "titre": "Monsieur"]
        case "/etat": corps = AnnexesDemo.etat
        case "/liens": corps = AnnexesDemo.liens
        case "/docs": corps = await annexes.documents()
        case "/docs/etiquettes": corps = AnnexesDemo.etiquettes
        case "/notifications": corps = await annexes.notifications()
        case "/connecteurs":
            // 28.10 : la réponse du relais (textes, logos, états), liens vers les sites publics des projets
            guard let url = Bundle.main.url(forResource: "connecteurs-demo", withExtension: "json"),
                let donnees = try? Data(contentsOf: url)
            else { return (404, Data()) }
            return (200, donnees)
        default: return (404, Data())
        }
        return (200, Data(corps.enTexte().utf8))
    }

    /// Les écritures de la démo restent dans la démo (rien ne part, rien n'est gardé).
    func envoyer(_ r: RequeteRelais) async throws -> (statut: Int, corps: Data) {
        switch (r.methode, r.chemin) {
        case (.post, "/docs"):
            // 23.10 (soir) : 202 et la fiche (son identifiant), comme le relais
            guard let fiche = await annexes.deposer(r.corps ?? Data()) else { return (400, Data()) }
            return (202, Data(fiche.enTexte().utf8))
        case (.post, "/notifications/lues"):
            await annexes.toutLire()
            return (200, Data())
        case (.post, "/notifications/effacer"):
            await annexes.toutEffacer()
            return (200, Data())
        case (.post, let c) where c.hasPrefix("/docs/") && c.hasSuffix("/reessayer"):
            let id = String(c.dropFirst("/docs/".count).dropLast("/reessayer".count))
            return (await annexes.reessayer(id), Data())
        case (.delete, let c) where c.hasPrefix("/docs/"):
            return (await annexes.supprimer(String(c.dropFirst("/docs/".count))) ? 200 : 404, Data())
        default:
            return (404, Data())
        }
    }
}

/// Documents, notifications, liens et état des services de la démonstration : génériques, aucune donnée réelle.
actor AnnexesDemo {
    static let etat: ValeurJSON = [
        "groupes": [
            [
                "nom": "Maison",
                "services": [["nom": "Home Assistant", "statut": "ok"], ["nom": "Alertes", "statut": "ok"]],
            ],
            [
                "nom": "Voix d'Alfred",
                "services": [
                    ["nom": "Relais", "statut": "ok"], ["nom": "Garde", "statut": "ok"],
                    ["nom": "Modèle", "statut": "eteint"], ["nom": "Transcription", "statut": "eteint"],
                ],
            ],
            ["nom": "Surveillance", "services": [["nom": "Revue de nuit", "statut": "ok"]]],
        ],
        "kuma": .nul,
    ]

    /// 23.10 : des étiquettes inventées, triées par nom, comme le relais.
    static let etiquettes: ValeurJSON = [
        "etiquettes": [
            ["id": 1, "nom": "Assurance"], ["id": 2, "nom": "Électricité"], ["id": 3, "nom": "Impôts"],
            ["id": 4, "nom": "Maison"], ["id": 5, "nom": "Voiture"],
        ],
        "disponible": true,
    ]

    static let liens: ValeurJSON = [
        ["nom": "Home Assistant", "url": "https://www.home-assistant.io", "note": "la maison"],
        ["nom": "Paperless", "url": "https://docs.paperless-ngx.com", "note": "les documents"],
    ]

    /// 23.10 : la boîte d'arrivée, comme le relais : un document rangé dans Paperless il y a longtemps (hors du panneau ;
    /// lien vers le site de Paperless, public) et un refusé (aucun texte lisible), à réessayer ou retirer.
    private var docs: [ValeurJSON] = [
        [
            "id": "demo-1", "nom": "Facture d’exemple", "etat": "pret", "statut": "range",
            "resume": "Une facture de démonstration : 120 francs, à payer d’ici la fin du mois.",
            "depose_le": "2026-10-17T09:30:00+02:00", "pour_le": "2026-10-31",
            "paperless": ["etat": "range", "document": 1], "lien": "https://docs.paperless-ngx.com",
            "etiquettes": ["Maison"], "range_le": "2026-10-17T09:31:00+02:00",
        ],
        [
            "id": "demo-2", "nom": "Photo floue d’exemple", "etat": "erreur", "statut": "refuse",
            "refus": "illisible", "motif": "aucun texte lisible", "reessayer": true,
            "depose_le": "2026-10-17T09:31:00+02:00",
        ],
    ]
    private var notifs: [ValeurJSON] = [
        [
            "id": "n1", "titre": "Alfred", "message": "Exemple : la lessive est terminée.", "t": 1_792_220_000,
            "lu": false,
        ],
        [
            "id": "n2", "titre": "Hermes", "message": "Exemple : votre réponse est prête.", "t": 1_792_200_000,
            "lu": true,
        ],
    ]
    private var depots = 0

    /// 23.10 (soir) : comme le relais — le panneau (lecture, rangement, refusés, banc), les récents (rangés il y a
    /// moins de 15 min), les refusés comptés, la liste de Paperless.
    func documents() -> ValeurJSON {
        let panneau = docs.filter { ["lecture", "rangement", "refuse", "banc"].contains($0["statut"]?.texte ?? "") }
        let ranges = docs.filter { ["range", "envoye", "doublon"].contains($0["statut"]?.texte ?? "") }
        let iso = ISO8601DateFormatter()
        let recents = ranges.filter { d in
            d["range_le"]?.texte.flatMap(iso.date(from:)).map { Date.now.timeIntervalSince($0) < 15 * 60 } ?? false
        }
        let aRevoir = Double(panneau.filter { $0["statut"] == "refuse" }.count)
        return [
            "documents": .liste(panneau), "recents": .liste(recents), "a_revoir": .nombre(aRevoir),
            "a_traiter": .nombre(aRevoir), "hors_panneau": .nombre(Double(ranges.count - recents.count)),
            "paperless_liste": "https://docs.paperless-ngx.com",
        ]
    }

    func notifications() -> ValeurJSON {
        ["notifications": .liste(notifs), "non_lues": .nombre(Double(notifs.filter { $0["lu"] == false }.count))]
    }

    /// Un dépôt de la démo : le nom du fichier est relu dans le corps ; la fiche est « rangée » d'emblée (dans les
    /// récents, avec son lien) ; rend la fiche (202).
    func deposer(_ corps: Data) -> ValeurJSON? {
        let texte = String(decoding: corps.prefix(4096), as: UTF8.self)
        guard let r = texte.range(of: #"filename="([^"]+)""#, options: .regularExpression) else { return nil }
        let nom = texte[r].dropFirst("filename=\"".count).dropLast()
        depots += 1
        // 23.10 : les étiquettes du dépôt (un n° de la liste, ou un nom nouveau), posées d'emblée dans la démo
        let noms = Dictionary(
            uniqueKeysWithValues: (Self.etiquettes["etiquettes"]?.liste ?? []).compactMap { e -> (String, String)? in
                guard case .nombre(let n)? = e["id"], let nom = e["nom"]?.texte else { return nil }
                return (String(Int(n)), nom)
            })
        let marque = "name=\"etiquette\"\r\n\r\n"
        // les champs viennent après le fichier : lus dans la fin du corps
        let fin = String(decoding: corps.suffix(4096), as: UTF8.self)
        let etiquettes = fin.components(separatedBy: marque).dropFirst().compactMap { bout -> ValeurJSON? in
            guard let valeur = bout.components(separatedBy: "\r\n").first, !valeur.isEmpty else { return nil }
            return .texte(noms[valeur] ?? valeur)
        }
        let maintenant = ISO8601DateFormatter().string(from: .now)
        let fiche: ValeurJSON = [
            "id": .texte("demo-depot-\(depots)"), "nom": .texte(String(nom)), "etat": "pret", "statut": "range",
            "resume": "Document de démonstration : rien n’a quitté l’appareil.",
            "paperless": ["etat": "range", "document": .nombre(Double(depots + 1))],
            "etiquettes": .liste(etiquettes), "lien": "https://docs.paperless-ngx.com",
            "depose_le": .texte(maintenant), "range_le": .texte(maintenant),
        ]
        docs.insert(fiche, at: 0)
        return fiche
    }

    /// « Réessayer » : le refus de la démo devient un document rangé (202) ; 409 s'il n'y a rien à réessayer.
    func reessayer(_ id: String) -> Int {
        guard let i = docs.firstIndex(where: { $0["id"]?.texte == id }), docs[i]["statut"] == "refuse",
            case .objet(var o) = docs[i]
        else { return docs.contains { $0["id"]?.texte == id } ? 409 : 404 }
        o["etat"] = "pret"
        o["statut"] = "range"
        o["range_le"] = .texte(ISO8601DateFormatter().string(from: .now))
        o["resume"] = "Document de démonstration : lu au deuxième essai."
        for cle in ["refus", "motif", "reessayer"] { o[cle] = nil }
        docs[i] = .objet(o)
        return 202
    }

    func supprimer(_ id: String) -> Bool {
        let avant = docs.count
        docs.removeAll { $0["id"]?.texte == id }
        return docs.count < avant
    }

    func toutLire() {
        notifs = notifs.map { n in
            guard case .objet(var o) = n else { return n }
            o["lu"] = true
            return .objet(o)
        }
    }

    func toutEffacer() { notifs = [] }
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

    // une maison inventée (19.10 : rien qui décrive une vraie maison) : trois niveaux, des pièces de partout
    static let pieces: [Piece] = [
        Piece(
            id: "garage", nom: "GARAGE", mot: "garage", etage: "ss", allumee: false, temperature: "14.8", humidite: "62"
        ),
        Piece(
            id: "fitness", nom: "FITNESS", mot: "fitness", etage: "ss", allumee: false, temperature: "18.9",
            humidite: nil),
        Piece(
            id: "salon", nom: "SALON", mot: "salon", etage: "rdc", allumee: true, temperature: "21.4", humidite: "52"),
        Piece(
            id: "cuisine", nom: "CUISINE", mot: "cuisine", etage: "rdc", allumee: true, temperature: "22.1",
            humidite: nil),
        Piece(
            id: "veranda", nom: "VÉRANDA", mot: "veranda", etage: "rdc", allumee: false, temperature: "18.6",
            humidite: "55"),
        Piece(
            id: "atelier", nom: "ATELIER", mot: "atelier", etage: "rdc", allumee: false, temperature: nil, humidite: nil
        ),
        Piece(
            id: "bibliotheque", nom: "BIBLIOTHÈQUE", mot: "bibliotheque", etage: "rdc", allumee: false,
            temperature: "20.7", humidite: nil),
        Piece(
            id: "jardin", nom: "JARDIN", mot: "jardin", etage: "rdc", allumee: false, temperature: nil, humidite: nil),
        Piece(
            id: "mezzanine", nom: "MEZZANINE", mot: "mezzanine", etage: "1er", allumee: true, temperature: "20.9",
            humidite: "48"),
        Piece(
            id: "suite", nom: "SUITE", mot: "suite", etage: "1er", allumee: false, temperature: "19.5", humidite: "50"),
        Piece(
            id: "bleue", nom: "CH. BLEUE", mot: "chambre bleue", etage: "1er", allumee: false, temperature: "19.8",
            humidite: "49"),
        Piece(
            id: "eau", nom: "SALLE D’EAU", mot: "salle d'eau", etage: "1er", allumee: false, temperature: "22.6",
            humidite: "64"),
        Piece(
            id: "studio", nom: "STUDIO", mot: "studio", etage: "1er", allumee: false, temperature: "20.3",
            humidite: "47"),
        Piece(
            id: "palier", nom: "PALIER", mot: "palier", etage: "1er", allumee: false, temperature: nil, humidite: nil),
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
                    "mots": .texte(#"\b"# + NSRegularExpression.escapedPattern(for: p.mot) + #"\b"#),
                ]
            }),
        "autres": [
            [
                "nom": "CELLIER", "etage": "ss", "temperature": "sensor.demo_cellier_t",
                "humidite": "sensor.demo_cellier_h",
            ],
            ["nom": "SERRE", "etage": "rdc", "temperature": "sensor.demo_serre_t", "humidite": "sensor.demo_serre_h"],
        ],
        "jauges": [
            ["entite": "sensor.demo_gpu", "libelle": "gpu", "unite": "°", "max": 100],
            ["entite": "sensor.demo_pc", "libelle": "pc", "unite": "W", "max": 400],
            ["entite": "sensor.demo_maison", "libelle": "maison", "unite": "W", "max": 6000],
            ["entite": "sensor.demo_jour", "libelle": "jour", "unite": "kWh", "max": 10],
        ],
        "meteo": "weather.demo", "puissance": "sensor.demo_maison",
        "invites": "input_boolean.demo_invites", "voix": "sensor.demo_voix",
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
        capteur("sensor.demo_cellier_t", "16.4", "°C")
        capteur("sensor.demo_cellier_h", "63", "%")
        capteur("sensor.demo_serre_t", "24.2", "°C")
        capteur("sensor.demo_serre_h", "71", "%")
        capteur("sensor.demo_gpu", "41", "°C")
        capteur("sensor.demo_pc", "86", "W")
        capteur("sensor.demo_maison", "640", "W")
        capteur("sensor.demo_jour", "1.42", "kWh")
        e["input_boolean.demo_invites"] = [
            "entity_id": "input_boolean.demo_invites", "state": "off", "attributes": [:],
        ]
        e["sensor.demo_voix"] = ["entity_id": "sensor.demo_voix", "state": "unknown", "attributes": [:]]
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
                "result": m["type"] == "subscribe_events"
                    ? .nul
                    : [
                        "pipelines": [["id": "demo", "conversation_engine": "conversation.demo"]],
                        "preferred_pipeline": "demo",
                    ],
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
