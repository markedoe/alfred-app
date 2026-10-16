import Foundation
import Testing

@testable import Alfred

@Suite("Configuration de la maison")
struct ConfigurationTests {
    static func plist(_ d: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
    }

    @Test("Relais et autorité embarqués")
    func complete() throws {
        let c = try #require(
            ConfigurationMaison.lire(Self.plist(["Relais": "relais.test", "Autorite": Data([1, 2, 3])])))
        #expect(c.relais.hote == "relais.test")
        #expect(c.autorite == Data([1, 2, 3]))
    }

    @Test("Sans autorité : les autorités du système")
    func sansAutorite() throws {
        let c = try #require(ConfigurationMaison.lire(Self.plist(["Relais": "relais.test"])))
        #expect(c.autorite == nil)
    }

    @Test("Adresse invalide ou absente : pas de configuration")
    func invalide() {
        #expect(ConfigurationMaison.lire(Self.plist(["Relais": "http://relais.test"])) == nil)
        #expect(ConfigurationMaison.lire(Self.plist(["Autre": "x"])) == nil)
        #expect(ConfigurationMaison.lire(Data("pas un plist".utf8)) == nil)
    }

    @Test("Adresse saisie au premier lancement")
    func saisie() throws {
        let r = try #require(UserDefaults(suiteName: "tests.configuration"))
        r.removePersistentDomain(forName: "tests.configuration")
        #expect(ConfigurationMaison.saisie(reglages: r) == nil)
        r.set("relais.test", forKey: ConfigurationMaison.cleAdresseSaisie)
        #expect(ConfigurationMaison.saisie(reglages: r)?.relais.hote == "relais.test")
        r.removePersistentDomain(forName: "tests.configuration")
    }
}

@Suite("Salutation")
struct SalutationTests {
    static func date(_ heure: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .gmt
        return c.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: heure))!
    }

    @Test("Bonjour le jour, bonsoir le soir, avec le titre")
    func salutations() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .gmt
        #expect(Salutation.texte(titre: "Monsieur", date: Self.date(9), calendrier: c) == "Bonjour, Monsieur.")
        #expect(Salutation.texte(titre: "Madame", date: Self.date(20), calendrier: c) == "Bonsoir, Madame.")
        #expect(Salutation.texte(titre: "", date: Self.date(3), calendrier: c) == "Bonsoir.")
        #expect(Salutation.texte(titre: nil, date: Self.date(17), calendrier: c) == "Bonjour.")
    }
}
