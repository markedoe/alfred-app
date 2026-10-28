import Foundation
import Testing

@testable import AlfredKit

@Suite("Les connecteurs")
struct ConnecteursTests {
    static func json(_ texte: String) -> Data { Data(texte.utf8) }

    @Test("Exemple réel du relais (28.10) : 5 groupes, 15 cartes, e-mails, veille, liens http(s), historique")
    func exempleReel() throws {
        let l = try #require(ListeConnecteurs.lire(ExempleConnecteurs.json))
        #expect(l.groupes.map(\.nom) == ["Maison", "Voix et cerveau", "Ce qu'Alfred sait", "Agents", "Surveillance"])
        #expect(l.groupes.map(\.connecteurs.count) == [2, 4, 5, 2, 2])
        #expect(
            l.tous.map(\.id) == [
                "home-assistant", "alertes", "modele", "ecoute", "voix", "garde", "memoire", "documents", "emails",
                "agenda", "web", "hermes", "claude", "kuma", "nuit",
            ])
        #expect(l.veille?.hasPrefix("Le PC du bureau est éteint : modèle d'Alfred") == true)
        #expect(l.historique?.absoluteString == "http://surveillance.example:3001/status/alfred")
        let liens = l.tous.compactMap(\.lien)
        #expect(
            liens.map(\.host) == ["maison.example", "documents.example", "recherche.example", "surveillance.example"])
        #expect(liens.allSatisfy { ["http", "https"].contains($0.scheme) })

        let ha = l.tous[0]
        #expect(ha.nom == "Home Assistant" && ha.phrase.hasPrefix("Lumières, Velux"))
        #expect(ha.icone.forme == .marque && !ha.nuage && ha.lieuMot == "À la maison" && ha.modeMot == "Agit")
        #expect(ha.etat.statut == .ok && ha.etat.mot == "En service")
        #expect(
            ha.etat.services == [
                Connecteur.Service(nom: "Home Assistant", statut: .ok, mot: "En service", depuis: "2026-10-28 06:00:00")
            ])
        #expect(ha.etat.dateDepuis == Date(timeIntervalSince1970: 1_793_167_200), "sans fuseau = UTC")
        #expect(ha.etat.services[0].dateDepuis == ha.etat.dateDepuis)
        #expect(
            ha.fiche.essayer == ["Allume le salon", "Quelle température au salon ?", "Combien consomme la maison ?"])
        #expect(ha.fiche.fait.hasPrefix("Allume") && ha.fiche.jamais.hasPrefix("Jamais la serrure"))

        let emails = try #require(l.tous.first { $0.id == "emails" })
        #expect(emails.nom == "E-mails" && emails.etat.services.count == 2 && emails.icone.forme == .marque)

        let modele = l.tous[2]
        #expect(modele.etat.statut == .eteint && modele.etat.mot == "En veille · PC éteint")
        #expect(modele.etat.services.map(\.statut) == [.eteint, .eteint])
        #expect(l.tous.filter { $0.etat.statut == .eteint }.map(\.id) == ["modele", "ecoute", "voix", "web"])

        let claude = l.tous[12]
        #expect(claude.nuage && claude.lieuMot == "Internet" && claude.etat.statut == .demande)
        #expect(claude.etat.services.isEmpty && claude.etat.depuis == nil && claude.etat.dateDepuis == nil)
        #expect(claude.lien == nil)

        #expect(l.tous.allSatisfy { $0.icone.trace != nil }, "tous les logos et pictogrammes se dessinent")
        #expect(
            l.tous.filter { $0.icone.forme == .trait }.map(\.id) == [
                "alertes", "ecoute", "voix", "garde", "memoire", "hermes", "nuit",
            ])
    }

    @Test(
        "Lecture tolérante : statut inconnu, lien javascript:, carte sans id, nom ou statut ignorée, groupe vide retiré"
    )
    func tolerance() throws {
        let l = try #require(
            ListeConnecteurs.lire(
                Self.json(
                    #"{"groupes":[{"nom":"A","connecteurs":[{"id":"x","nom":"X","etat":{"statut":"futur","services":[{"nom":"S","statut":"autre","depuis":"2026-10-28T06:00:00.250Z","message":"lent"},{"statut":"ok"}]},"lien":"javascript:alert(1)","icone":{"forme":"ronde","d":"Q1 2"},"lieu":"cloud","fiche":{"essayer":["",3,"Essaie"]}},{"nom":"Sans id","etat":{"statut":"ok"}},{"id":"n","etat":{"statut":"ok"}},{"id":"s","nom":"Sans statut","etat":{"mot":"?"}},{"id":"nul","nom":"Statut nul","etat":{"statut":null}},{"id":"e","nom":"Sans état"},{"id":"y","nom":"Y","etat":{"statut":"panne","depuis":"2026-10-28 06:00:00+01:00","services":"x"},"lien":"https://y.example/a","fiche":null}]},{"nom":"Vide","connecteurs":[{"nom":"Sans id","etat":{"statut":"ok"}}]},{"nom":"Rien"}],"veille":null,"historique":"file:///etc"}"#
                )))
        #expect(l.groupes.map(\.nom) == ["A"], "un groupe sans carte lisible est retiré")
        #expect(l.tous.map(\.id) == ["x", "y"])
        let x = l.tous[0]
        #expect(x.etat.statut == .inconnu && x.etat.mot == "" && x.etat.depuis == nil)
        #expect(x.etat.services.map(\.nom) == ["S"], "un service sans nom est sauté")
        #expect(x.etat.services[0].statut == .inconnu && x.etat.services[0].message == "lent")
        let fraction = try #require(x.etat.services[0].dateDepuis)
        #expect(abs(fraction.timeIntervalSince1970 - 1_793_167_200.25) < 0.001)
        #expect(x.lien == nil, "jamais un lien autre que http(s)")
        #expect(x.nuage && x.phrase == "" && x.lieuMot == "" && x.modeMot == "")
        #expect(x.icone.forme == .trait && x.icone.d == "Q1 2" && x.icone.trace == nil)
        #expect(x.fiche == Connecteur.Fiche(essayer: ["Essaie"]))
        let y = l.tous[1]
        #expect(y.lien?.host == "y.example" && y.etat.statut == .panne && y.etat.services.isEmpty)
        #expect(y.etat.dateDepuis == Date(timeIntervalSince1970: 1_793_163_600), "un fuseau donné est respecté")
        #expect(y.fiche == Connecteur.Fiche() && y.icone.trace == nil)
        #expect(l.veille == nil && l.historique == nil)
    }

    @Test("Statut : une valeur inconnue ou d'un autre type donne « inconnu », jamais un échec")
    func statut() throws {
        let s = try JSONDecoder().decode(
            [Connecteur.Statut].self,
            from: Self.json(#"["ok","attente","panne","eteint","inconnu","demande","plus tard",4]"#))
        #expect(s == [.ok, .attente, .panne, .eteint, .inconnu, .demande, .inconnu, .inconnu])
    }

    @Test("Une autre réponse que la liste : nil ; une carte seule sans identifiant : refusée")
    func pasUneListe() {
        #expect(ListeConnecteurs.lire(Self.json("HA ne répond pas")) == nil)
        #expect(ListeConnecteurs.lire(Self.json("{}")) == nil)
        #expect(ListeConnecteurs.lire(Self.json("[]")) == nil)
        #expect(ListeConnecteurs.lire(Self.json(#"{"groupes":"x"}"#)) == nil)
        #expect(ListeConnecteurs.lire(Self.json(#"{"groupes":[]}"#)) == ListeConnecteurs(groupes: []))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Connecteur.self, from: Self.json(#"{"nom":"X","etat":{"statut":"ok"}}"#))
        }
    }
}
