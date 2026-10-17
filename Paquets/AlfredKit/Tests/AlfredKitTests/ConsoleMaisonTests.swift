import Foundation
import Testing

@testable import AlfredKit

@Suite("La maison de la console")
struct ConsoleMaisonTests {
    static let console = ConsoleMaison.lire([
        "version": 1,
        "pieces": [
            [
                "nom": "SALON", "etage": "rdc", "lumiere": "light.salon", "temperature": "sensor.t_salon",
                "humidite": "sensor.h_salon", "air": nil,
            ],
            [
                "nom": "BUREAU", "etage": "1er", "lumiere": "light.bureau", "temperature": "sensor.t_bureau",
                "humidite": nil, "air": "sensor.cov",
            ],
            [
                "nom": "ENTRÉE", "etage": "rdc", "lumiere": "light.entree", "temperature": nil, "humidite": nil,
                "air": nil,
            ],
        ],
        "autres": [["nom": "CAVE", "etage": "ss", "temperature": "sensor.t_cave", "humidite": nil]],
        "jauges": [
            ["entite": "sensor.puissance_pc", "libelle": "pc", "unite": "W", "max": 400],
            ["entite": "sensor.energie_jour", "libelle": "jour", "unite": "kWh", "max": 10],
        ],
        "meteo": "weather.maison", "puissance": "sensor.puissance_maison",
    ])!

    static func maison(_ etats: [String: String]) -> Maison {
        Maison(etats: etats.map { EtatEntite(id: $0.key, etat: $0.value) })
    }

    @Test("Contrat v1 lu ; une autre version est refusée")
    func contrat() {
        #expect(Self.console.pieces.map(\.nom) == ["SALON", "BUREAU", "ENTRÉE"])
        #expect(Self.console.pieces[1].air == "sensor.cov")
        #expect(Self.console.autres.map(\.nom) == ["CAVE"])
        #expect(Self.console.jauges.map(\.libelle) == ["pc", "jour"])
        #expect(Self.console.meteo == "weather.maison")
        #expect(ConsoleMaison.lire(["version": 2, "pieces": []]) == nil)
    }

    @Test("Toutes les entités montrées, et seulement elles")
    func entites() {
        #expect(
            Self.console.entites == [
                "light.salon", "light.bureau", "light.entree", "sensor.t_salon", "sensor.h_salon", "sensor.t_bureau",
                "sensor.cov", "sensor.t_cave", "sensor.puissance_pc", "sensor.energie_jour", "weather.maison",
                "sensor.puissance_maison",
            ])
    }

    @Test("Intérieur : les pièces mesurées, du sous-sol au 2e, ordre de la roue gardé dans un étage")
    func interieur() {
        #expect(Self.console.interieur.map(\.nom) == ["CAVE", "SALON", "BUREAU"])
    }

    @Test("Résumé de la console, au mot près (pluriels, disponibles, températures)")
    func resume() {
        let tout = Self.maison([
            "light.salon": "on", "light.bureau": "off", "light.entree": "unavailable", "sensor.t_salon": "20",
            "sensor.t_bureau": "23.46", "sensor.t_cave": "19.04",
        ])
        #expect(
            Self.console.resume(tout)
                == "1 groupe allumé · 2/3 groupes disponibles · 19° à 23.5° dans les pièces mesurées")
        let deux = Self.maison(["light.salon": "on", "light.bureau": "on"])
        #expect(Self.console.resume(deux) == "2 groupes allumés · 2/3 groupes disponibles · Températures indisponibles")
        #expect(Self.console.resume(Maison()) == "Mesures indisponibles · En attente de la maison")
    }

    @Test("Nombres comme la console : arrondis, sans zéro inutile, « — » sans mesure")
    func format() {
        #expect(Format.valeur(19.0, "°", 1) == "19°")
        #expect(Format.valeur(19.54, "°", 1) == "19.5°")
        #expect(Format.valeur(19.96, "°", 1) == "20°")
        #expect(Format.valeur(2.5, "W") == "3W")
        #expect(Format.valeur(-2.5, "") == "-2")
        #expect(Format.valeur(0.3, "", 1) == "0.3")
        #expect(Format.valeur(1021, " hPa") == "1021 hPa")
        #expect(Format.valeur(1.234, "kWh", 2) == "1.23kWh")
        #expect(Format.valeur(nil, "°", 1) == "—")
        #expect(Format.valeur(.nan, "°", 1) == "—")
    }

    @Test("Boussole et météo en français")
    func meteo() {
        #expect(Format.boussole(270) == "O")
        #expect(Format.boussole(-45) == "NO")
        #expect(Format.boussole(359) == "N")
        #expect(Format.boussole(nil) == "")
        #expect(Format.meteo("rainy") == "pluie")
        #expect(Format.meteo("inconnu") == "inconnu")
    }

    @Test("Jauges : remplissage borné, décimales du bandeau et du panneau")
    func jauges() {
        let pc = Self.console.jauges[0]
        let jour = Self.console.jauges[1]
        #expect(pc.fraction(200) == 0.5)
        #expect(pc.fraction(900) == 1)
        #expect(pc.fraction(-5) == 0)
        #expect(pc.fraction(nil) == 0)
        #expect(pc.decimalesBandeau == 0 && jour.decimalesBandeau == 1 && jour.decimalesPanneau == 2)
        #expect(jour.description == "Ordinateur · énergie du jour")
    }

    @Test("Roue : un secteur par pièce, le 1er en haut, écarts réguliers, rayons de la console")
    func geometrie() {
        let g = GeometrieRoue(nombre: 14, rayon: 200)
        #expect(g.secteurs.count == 14)
        #expect(abs(g.secteurs[0].debut - (-Double.pi / 2 + 0.016)) < 1e-9)
        let pas = 2 * Double.pi / 14
        #expect(abs((g.secteurs[0].fin - g.secteurs[0].debut) - (pas - 0.032)) < 1e-9)
        #expect(abs(g.secteurs[1].debut - g.secteurs[0].debut - pas) < 1e-9)
        #expect(g.secteurs[0].interieur == 120 && g.secteurs[0].exterieur == 196)
        #expect(GeometrieRoue(nombre: 14, rayon: 400).secteurs[0].interieur == 264)
        #expect(g.rayonNoyau == 32)
        #expect(GeometrieRoue(nombre: 0, rayon: 200).secteurs.isEmpty)
    }
}
