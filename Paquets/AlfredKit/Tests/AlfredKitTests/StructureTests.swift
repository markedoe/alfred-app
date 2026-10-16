import Foundation
import Testing

@testable import AlfredKit

@Suite("Étages et pièces")
struct StructureTests {
    static let structure = StructureMaison.lire([
        "version": 1,
        "etages": [
            ["id": "sous_sol", "nom": "Sous-sol", "niveau": -1],
            ["id": "rez", "nom": "Rez", "niveau": 0],
            ["id": "combles", "nom": "Combles", "niveau": nil],
            ["id": "etage", "nom": "Étage", "niveau": 1],
        ],
        "pieces": [
            ["id": "salon", "nom": "Salon", "etage": "rez", "temperature": "sensor.t_salon"],
            ["id": "cave", "nom": "Cave", "etage": "sous_sol"],
            ["id": "atelier", "nom": "Atelier", "etage": nil],
            ["id": "vide", "nom": "Pièce sans lumière", "etage": "rez"],
        ],
        "lumieres": [
            "light.salon_groupe": "salon", "light.salon_lampe_1": "salon", "light.salon_lampe_2": "salon",
            "light.cave_groupe": "cave", "light.atelier": "atelier",
        ],
    ])!

    static let maison: Maison = {
        var m = Maison()
        m.charger([
            [
                "entity_id": "light.salon_groupe", "state": "on",
                "attributes": ["friendly_name": "Salon", "entity_id": ["light.salon_lampe_1", "light.salon_lampe_2"]],
            ],
            [
                "entity_id": "light.salon_lampe_1", "state": "on",
                "attributes": [
                    "friendly_name": "Lampadaire", "brightness": 128, "supported_color_modes": ["color_temp"],
                ],
            ],
            [
                "entity_id": "light.salon_lampe_2", "state": "off",
                "attributes": ["friendly_name": "Applique", "supported_color_modes": ["onoff"]],
            ],
            ["entity_id": "light.salon_cachee", "state": "off", "attributes": [:]],
            ["entity_id": "light.cave_groupe", "state": "unavailable", "attributes": ["is_hue_group": true]],
            ["entity_id": "light.atelier", "state": "off", "attributes": ["friendly_name": "Établi"]],
            ["entity_id": "light.sans_piece", "state": "on", "attributes": [:]],
            ["entity_id": "sensor.t_salon", "state": "21.4", "attributes": ["unit_of_measurement": "°C"]],
        ])
        return m
    }()

    @Test("Étages du plus haut au plus bas, ceux sans niveau à la fin")
    func ordreEtages() {
        #expect(Self.structure.etages.map(\.id) == ["etage", "rez", "sous_sol", "combles"])
    }

    @Test("Contrat v1 seulement")
    func contrat() {
        #expect(Self.structure.pieceDe["light.salon_lampe_1"] == "salon")
        #expect(StructureMaison.lire(["version": 2, "pieces": []]) == nil)
        #expect(StructureMaison.lire("pas un objet") == nil)
    }

    @Test("Vue : lampes seules plutôt que groupes ; groupe seul s'il n'y a qu'un groupe ; pièces sans étage à la fin")
    func vue() throws {
        let v = Self.maison.vue(Self.structure)
        #expect(v.map(\.id) == ["rez", "sous_sol", "_sans_etage"])
        let salon = try #require(v.first?.pieces.first)
        #expect(salon.lumieres.map(\.nom) == ["Applique", "Lampadaire"])
        #expect(salon.toutes.count == 3)
        #expect(salon.allumee && salon.disponible && salon.nombreAllumees == 1)
        #expect(salon.temperature?.nombre == 21.4)
        let cave = try #require(v[1].pieces.first)
        #expect(cave.lumieres.map(\.id) == ["light.cave_groupe"])
        #expect(!cave.disponible)
        #expect(v[2].pieces.map(\.id) == ["atelier"])
        #expect(!v.flatMap(\.pieces).contains { $0.id == "vide" })
    }

    @Test("Variateur et luminosité")
    func luminosite() throws {
        let l = try #require(Self.maison["light.salon_lampe_1"])
        #expect(l.variable && l.luminosite == 50)
        #expect(Self.maison["light.salon_lampe_2"]?.variable == false)
        #expect(Self.maison["light.salon_lampe_2"]?.luminosite == nil)
        let c = CommandeLuminosite(entite: "light.salon_lampe_1", pourcent: 140)
        #expect(c.pourcent == 100)
        #expect(c.message["service_data"]?["brightness_pct"] == 100)
        #expect(CommandeLuminosite(entite: l.id, pourcent: 51).confirmee(par: l))
        #expect(!CommandeLuminosite(entite: l.id, pourcent: 80).confirmee(par: l))
    }

    @Test("Commande de pièce : éteindre si une lumière est allumée ; message par area_id")
    func commandePiece() throws {
        let salon = try #require(Self.maison.vue(Self.structure).first?.pieces.first)
        let c = CommandePiece(salon)
        #expect(!c.allumer)
        #expect(
            c.message == [
                "type": "call_service", "domain": "light", "service": "turn_off",
                "target": ["area_id": "salon"],
            ])
        #expect(!c.confirmee(par: salon))
    }

    @Test("Structure vide : rien à montrer par pièce")
    func vide() {
        #expect(StructureMaison().vide)
        #expect(Self.maison.vue(StructureMaison()).isEmpty)
    }

    @Test("Ne garder que les lumières et les capteurs des pièces")
    func garder() {
        var m = Self.maison
        m.charger([
            ["entity_id": "light.a", "state": "on", "attributes": [:]],
            ["entity_id": "sensor.t_salon", "state": "20", "attributes": [:]],
            ["entity_id": "sensor.puissance", "state": "300", "attributes": [:]],
            ["entity_id": "switch.prise", "state": "on", "attributes": [:]],
        ])
        m.garder(Self.structure.utile)
        #expect(Set(m.etats.keys) == ["light.a", "sensor.t_salon"])
    }
}
