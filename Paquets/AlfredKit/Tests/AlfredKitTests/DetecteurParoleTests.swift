import Foundation
import Testing

@testable import AlfredKit

@Suite("Détection de la parole")
struct DetecteurParoleTests {
    static let silence: Float = 0.001
    static let voix: Float = 0.2

    /// Joue `ms` millisecondes au niveau donné ; rend les décisions avec leur temps audio.
    static func jouer(_ d: inout DetecteurParole, _ niveau: Float, ms: Double) -> [(Double, DetecteurParole.Decision)] {
        var sortie: [(Double, DetecteurParole.Decision)] = []
        for _ in 0..<Int(ms / DetecteurParole.msParTrame) {
            for decision in d.trame(rms: niveau) { sortie.append((d.tempsMs, decision)) }
        }
        return sortie
    }

    @Test("Appui : la fin vient 1 s après la dernière parole")
    func finApresSilence() throws {
        var d = DetecteurParole(conversation: false)
        var vues = Self.jouer(&d, Self.silence, ms: 400)
        vues += Self.jouer(&d, Self.voix, ms: 800)
        vues += Self.jouer(&d, Self.silence, ms: 3000)
        let (t, decision) = try #require(vues.first)
        #expect(decision == .fin(.silenceApresParole))
        #expect(t > 2200 && t < 2240, "fin à \(t) ms")
        #expect(d.termine)
    }

    @Test("Appui : une phrase très courte attend 1,5 s de tour au moins")
    func dureeMinimale() throws {
        var d = DetecteurParole(conversation: false)
        var vues = Self.jouer(&d, Self.silence, ms: 200)  // un micro s'ouvre sur un instant de silence
        vues += Self.jouer(&d, Self.voix, ms: 100)
        vues += Self.jouer(&d, Self.silence, ms: 3000)
        let (t, decision) = try #require(vues.first)
        #expect(decision == .fin(.silenceApresParole))
        #expect(t > 1500 && t < 1520, "fin à \(t) ms")
    }

    @Test("15 s au plus")
    func dureeMaximale() throws {
        var d = DetecteurParole(conversation: false)
        var vues = Self.jouer(&d, Self.silence, ms: 200)
        vues += Self.jouer(&d, Self.voix, ms: 20_000)
        let (t, decision) = try #require(vues.first)
        #expect(decision == .fin(.dureeMaximale))
        #expect(t > 15_000 && t < 15_020)
    }

    @Test("Appui sans parole : fermé après 10 s")
    func sansParole() throws {
        var d = DetecteurParole(conversation: false)
        let vues = Self.jouer(&d, Self.silence, ms: 12_000)
        let (t, decision) = try #require(vues.first)
        #expect(decision == .fin(.aucuneParole))
        #expect(t > 10_000 && t < 10_020)
    }

    @Test("Conversation : le silence ne ferme jamais le tour à lui seul")
    func conversationSilence() {
        var d = DetecteurParole(conversation: true)
        #expect(Self.jouer(&d, Self.silence, ms: 30_000).isEmpty)
    }

    @Test("Conversation : un bruit de 150 ms est ignoré, aucun tour")
    func bruitCourt() {
        var d = DetecteurParole(conversation: true)
        var vues = Self.jouer(&d, Self.silence, ms: 400)
        vues += Self.jouer(&d, Self.voix, ms: 150)
        vues += Self.jouer(&d, Self.silence, ms: 1000)
        #expect(vues.map(\.1) == [.bruitIgnore])
        #expect(!d.parole)
    }

    @Test("Conversation : une phrase de 254 ms ouvre le tour, au début du son")
    func attaque() throws {
        var d = DetecteurParole(conversation: true)
        var vues = Self.jouer(&d, Self.silence, ms: 400)
        vues += Self.jouer(&d, Self.voix, ms: 256)
        let (t, decision) = try #require(vues.first)
        guard case .attaque(let depuis) = decision else {
            Issue.record("pas d'attaque : \(decision)")
            return
        }
        #expect(abs(depuis - 400) <= 8, "le tour commence au début du son (\(depuis) ms)")
        #expect(t >= 600 && t <= 610)
        vues = Self.jouer(&d, Self.silence, ms: 3000)
        #expect(vues.map(\.1) == [.fin(.silenceApresParole)])
    }

    @Test("Le plancher ne monte pas pendant la parole")
    func plancherFixePendantParole() {
        var d = DetecteurParole(conversation: false)
        _ = Self.jouer(&d, Self.silence, ms: 400)
        _ = Self.jouer(&d, Self.voix, ms: 100)  // la parole est reconnue (4 trames)
        let avant = d.plancher
        _ = Self.jouer(&d, Self.voix, ms: 2900)
        #expect(d.plancher == avant)
        #expect(avant < 0.0013, "seules les 4 trames de l'attaque comptent (\(avant))")
        // une fin de phrase plus douce reste de la parole (le seuil n'a pas suivi la voix)
        let vues = Self.jouer(&d, 0.05, ms: 2000)
        #expect(vues.isEmpty)
    }

    @Test("Les paquets de toute taille sont découpés en trames de 8 ms")
    func decoupage() {
        var d = DetecteurParole(conversation: false)
        _ = d.analyser([Float](repeating: 0.001, count: 100))
        #expect(d.tempsMs == 0)
        _ = d.analyser([Float](repeating: 0.001, count: 300))
        #expect(d.tempsMs == 24)
    }

    @Test("Amorce : garde les ~0,48 dernières secondes")
    func amorce() {
        var a = Amorce()
        for i in 0..<200 { a.ajouter(Data(repeating: UInt8(i % 256), count: 256)) }
        let m = a.prendre()
        let total = m.reduce(0) { $0 + $1.count }
        #expect(total >= a.capacite && total < a.capacite + 256)
        #expect(m.last == Data(repeating: 199, count: 256))
        #expect(a.prendre().isEmpty)
    }

    @Test("PCM 16 bits petit-boutiste, saturé proprement")
    func pcm() {
        let d = PCM.enOctets([0, 1, -1, 2, -2, 0.5])
        #expect(Array(d) == [0, 0, 0xFF, 0x7F, 0x00, 0x80, 0xFF, 0x7F, 0x00, 0x80, 0xFF, 0x3F])
    }

    @Test("Conversation : le plancher passe d'un tour à l'autre ; la marge mesure sans détecter")
    func plancherEtMarge() {
        var d = DetecteurParole(conversation: true)
        _ = Self.jouer(&d, Self.silence, ms: 400)
        var suivant = DetecteurParole(conversation: true, plancher: d.plancher)
        #expect(suivant.plancher == d.plancher)
        // la queue de la voix d'Alfred, forte, pendant la marge : aucun tour, aucun temps écoulé
        suivant.mesurer([Float](repeating: 0.2, count: 128 * 50))
        #expect(suivant.tempsMs == 0 && !suivant.parole)
        #expect(suivant.plancher < 0.01, "le plancher monte très lentement (\(suivant.plancher))")
    }
}
