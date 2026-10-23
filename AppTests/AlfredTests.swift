import AVFAudio
import AlfredKit
import Foundation
import Security
import Testing

@testable import Alfred

/// L'app contre un relais de test (aucun réseau) : la coupure, la session expirée, la déconnexion, la démo.
@MainActor
@Suite("Alfred", .serialized)
struct AlfredTests {
    static func attendre(_ quoi: String, _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("attente dépassée : \(quoi)")
    }

    static let salonAllume: ValeurJSON = [["entity_id": "light.salon", "state": "on", "attributes": [:]]]

    @Test("Coupure : rien de la maison n'est plus montré comme actuel (point 10)")
    func coupure() async throws {
        let relais = RelaisDeTest(etats: Self.salonAllume)
        let a = Alfred.essai(acces: relais)
        try await Self.attendre("prêt") { a.estPret && a.maison["light.salon"] != nil }
        await relais.liaisons.last?.fermer()
        try await Self.attendre("maison effacée") { !a.estPret && a.maison["light.salon"] == nil }
        #expect(a.historiquePuissance.isEmpty && a.lumieresAllumees == 0)
        try await Self.attendre("reconnectée") { a.estPret && a.maison["light.salon"] != nil }
        await a.seDeconnecter()
    }

    @Test("Coupure pendant la synchronisation : les états déjà chargés ne restent pas affichés")
    func coupurePendantLaSynchronisation() async throws {
        let relais = RelaisDeTest(etats: Self.salonAllume)
        let porte = PorteDeTest()
        relais.avantStructure = { await porte.passer() }
        let a = Alfred.essai(acces: relais)
        try await Self.attendre("états chargés") { a.maison["light.salon"] != nil }
        #expect(!a.estPret)
        // la 1re synchronisation attend à la porte ; la suivante n'y attendra pas
        relais.avantStructure = nil
        await relais.liaisons.last?.fermer()
        try await Self.attendre("maison effacée") { a.maison["light.salon"] == nil }
        await porte.ouvrir()
        try await Self.attendre("reconnectée") { a.estPret }
        await a.seDeconnecter()
    }

    @Test("Session expirée : la conversation et le fil disparaissent, la voix redevient muette (point 8)")
    func sessionExpiree() async throws {
        let relais = RelaisDeTest()
        let a = Alfred.essai(acces: relais, voix: VoixDeTest())
        try await Self.attendre("prêt") { a.estPret }
        #expect(await a.conversation.ecrire("Quelle heure est-il ?"))
        try await Self.attendre("réponse") { a.conversation.phase == .repos && a.conversation.messages.count == 2 }
        #expect(a.conversation.conversationId == RelaisDeTest.fil)
        // 23.10 : une question à Hermes encore attendue, et une réponse réclamée pendant un autre tour, qui attend sa
        // fin (sans ce tour, les annexes la montreraient avant l'expiration, et le test ne prouverait rien)
        let attendue = a.conversation.attendreHermes()
        let reclamee = a.conversation.attendreHermes()
        a.conversation.recevoir(.reflechit)
        a.conversation.recevoirDifferee(texte: "Réponse privée.", chemin: nil, attente: reclamee.numero, livrer: false)
        // la maison ne connaît plus la personne : à la reconnexion, `/moi` le dit
        relais.connecte = false
        await relais.liaisons.last?.fermer()
        try await Self.attendre("accueil") { a.etape == .accueil }
        #expect(a.motifAccueil == "Votre connexion à la maison a expiré. Reconnectez-vous.")
        #expect(a.conversation.vide && a.conversation.conversationId == nil)
        #expect(a.conversation.attentesHermes.isEmpty && a.conversation.differees.isEmpty)
        #expect(!a.conversation.ecranAllume, "l'écran d'accueil se verrouille de nouveau")
        // la réponse d'une réclamation partie avant : ignorée
        a.conversation.recevoirDifferee(texte: "Réponse tardive.", chemin: nil, attente: attendue.numero)
        #expect(a.conversation.vide)
        #expect(a.conversation.voix is VoixMuette)
        #expect(!a.estPret && a.maison["light.salon"] == nil)
    }

    @Test(
        "Déconnexion : la conversation est vidée, la maison prévenue ; la démo ouverte ensuite n'a pas de micro (point 9)"
    )
    func deconnexion() async throws {
        let relais = RelaisDeTest()
        let a = Alfred.essai(acces: relais, voix: VoixDeTest())
        try await Self.attendre("prêt") { a.estPret }
        #expect(await a.conversation.ecrire("Quelle heure est-il ?"))
        try await Self.attendre("réponse") { a.conversation.phase == .repos && a.conversation.messages.count == 2 }
        // 23.10 : une question à Hermes encore attendue, et une réponse réclamée pas encore montrée
        let attendue = a.conversation.attendreHermes()
        let reclamee = a.conversation.attendreHermes()
        a.conversation.recevoirDifferee(texte: "Réponse privée.", chemin: nil, attente: reclamee.numero, livrer: false)
        #expect(a.conversation.ecranAllume && a.conversation.differees.count == 1)
        await a.seDeconnecter()
        #expect(a.conversation.vide)
        #expect(a.conversation.attentesHermes.isEmpty && a.conversation.differees.isEmpty)
        #expect(!a.conversation.ecranAllume, "l'écran d'accueil se verrouille de nouveau")
        #expect(relais.deconnexions == 1 && a.motifAccueil == nil)
        #expect(a.conversation.voix is VoixMuette)
        // la réponse d'une réclamation partie avant la déconnexion : ignorée
        a.conversation.recevoirDifferee(texte: "Réponse tardive.", chemin: nil, attente: attendue.numero)
        #expect(a.conversation.vide)
        a.essayerDemo()
        try await Self.attendre("démo prête") { a.estPret && a.annexes?.notificationsPermises == true }
        #expect(a.demo && a.conversation.voix is VoixMuette, "la démo : sans réseau ni micro")
        #expect(a.conversation.vide, "rien de la personne précédente n'arrive à la session suivante")
        await a.quitterDemo()
    }
}

/// La session dans le trousseau : la logique sur un trousseau simulé (la CI fabrique sans signature : le vrai lui est
/// fermé, -34018), et le vrai trousseau là où il est accessible.
@Suite("Trousseau", .serialized)
struct TrousseauTests {
    @Test(
        "Écrire : ajout la 1re fois (propre à l'appareil, jamais synchronisé), mise à jour ensuite, sans effacer d'abord"
    )
    func ecrire() throws {
        let t = TrousseauSimule()
        try Trousseau.ecrire("premiere", compte: "c", acces: t.acces)
        #expect(t.appels == ["modifier", "ajouter"])
        #expect(t.synchronisable == false)
        #expect(t.accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        try Trousseau.ecrire("seconde", compte: "c", acces: t.acces)
        #expect(t.appels == ["modifier", "ajouter", "modifier"], "une mise à jour : rien n'est effacé d'abord")
        #expect(Trousseau.lire(compte: "c", acces: t.acces) == "seconde")
        Trousseau.effacer(compte: "c", acces: t.acces)
        #expect(Trousseau.lire(compte: "c", acces: t.acces) == nil)
    }

    @Test("Un ajout refusé est une erreur : l'app le dit (la session n'a pas pu être gardée)")
    func ajoutRefuse() {
        let t = TrousseauSimule()
        t.refusAjout = errSecInteractionNotAllowed
        #expect(throws: Trousseau.Erreur(statut: errSecInteractionNotAllowed)) {
            try Trousseau.ecrire("x", compte: "c", acces: t.acces)
        }
    }

    @Test("Le vrai trousseau : écrire, remplacer, lire, effacer", .enabled(if: TrousseauTests.accessible))
    func vrai() throws {
        let compte = "tests.trousseau.\(UUID().uuidString)"
        defer { Trousseau.effacer(compte: compte) }
        #expect(Trousseau.lire(compte: compte) == nil)
        try Trousseau.ecrire("premiere", compte: compte)
        try Trousseau.ecrire("seconde", compte: compte)
        #expect(Trousseau.lire(compte: compte) == "seconde")
        Trousseau.effacer(compte: compte)
        #expect(Trousseau.lire(compte: compte) == nil)
    }

    /// Le vrai trousseau répond (une fabrication signée) : un essai, aussitôt effacé.
    static var accessible: Bool {
        let element: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: "tests.sonde", kSecAttrAccount: "sonde",
        ]
        let statut = SecItemAdd(element.merging([kSecValueData: Data()]) { $1 } as CFDictionary, nil)
        SecItemDelete(element as CFDictionary)
        return statut != errSecMissingEntitlement
    }
}

/// Un trousseau en mémoire : ce que l'app y fait, appel par appel.
final class TrousseauSimule: @unchecked Sendable {
    private let verrou = NSLock()
    private var _valeur: Data?
    private var _appels: [String] = []
    private var _synchronisable: Bool?
    private var _accessible: String?
    private var _refusAjout: OSStatus?

    var appels: [String] { verrou.withLock { _appels } }
    var synchronisable: Bool? { verrou.withLock { _synchronisable } }
    var accessible: String? { verrou.withLock { _accessible } }
    var refusAjout: OSStatus? {
        get { verrou.withLock { _refusAjout } }
        set { verrou.withLock { _refusAjout = newValue } }
    }

    var acces: Trousseau.Acces {
        Trousseau.Acces(
            copier: { [self] _, resultat in
                verrou.withLock {
                    _appels.append("copier")
                    guard let v = _valeur else { return errSecItemNotFound }
                    resultat?.pointee = v as CFData
                    return errSecSuccess
                }
            },
            ajouter: { [self] requete, _ in
                let d = requete as NSDictionary
                return verrou.withLock {
                    _appels.append("ajouter")
                    if let refus = _refusAjout { return refus }
                    _synchronisable = d[kSecAttrSynchronizable] as? Bool
                    _accessible = d[kSecAttrAccessible] as? String
                    _valeur = d[kSecValueData] as? Data
                    return errSecSuccess
                }
            },
            modifier: { [self] _, attributs in
                let d = attributs as NSDictionary
                return verrou.withLock {
                    _appels.append("modifier")
                    guard _valeur != nil else { return errSecItemNotFound }
                    _valeur = d[kSecValueData] as? Data
                    _accessible = d[kSecAttrAccessible] as? String
                    return errSecSuccess
                }
            },
            supprimer: { [self] _ in
                verrou.withLock {
                    _appels.append("supprimer")
                    _valeur = nil
                    return errSecSuccess
                }
            })
    }
}

/// Les décisions du son, sans matériel.
@Suite("Son")
struct SonTests {
    @Test("Changement de matériel : seul notre moteur compte, et seulement s'il s'est arrêté")
    func changementDeMateriel() {
        let micro = NSObject()
        let lecteur = NSObject()
        let autre = NSObject()
        let m = ObjectIdentifier(micro)
        let l = ObjectIdentifier(lecteur)
        let o = ObjectIdentifier(autre)
        #expect(
            VoixSysteme.suite(moteur: m, micro: (id: m, tourne: false), lecteur: (id: l, tourne: true))
                == .fermerConversation)
        #expect(
            VoixSysteme.suite(moteur: m, micro: (id: m, tourne: true), lecteur: (id: l, tourne: true)) == .rien,
            "voix activée, en marche")
        #expect(
            VoixSysteme.suite(moteur: o, micro: (id: m, tourne: false), lecteur: (id: l, tourne: false)) == .rien,
            "un autre moteur")
        #expect(VoixSysteme.suite(moteur: l, micro: nil, lecteur: (id: l, tourne: false)) == .taireAlfred)
        #expect(VoixSysteme.suite(moteur: l, micro: nil, lecteur: (id: l, tourne: true)) == .rien)
    }

    @Test("Écouteurs retirés : Alfred se tait ; un appareil branché, non")
    func routeChange() {
        #expect(VoixSysteme.seTaire(apres: .oldDeviceUnavailable))
        #expect(!VoixSysteme.seTaire(apres: .newDeviceAvailable))
        #expect(!VoixSysteme.seTaire(apres: .categoryChange))
        #expect(!VoixSysteme.seTaire(apres: nil))
    }
}
