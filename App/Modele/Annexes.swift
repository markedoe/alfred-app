import AlfredKit
import Foundation
import Observation

/// Les annexes de la console, autour de la conversation : documents, notifications, liens vers les autres systèmes
/// et état des services. Mêmes routes et mêmes rythmes que la console :
/// - documents : toutes les 60 s, toutes les 2,5 s tant qu'un document est en lecture, 30 s après un échec ;
/// - notifications : toutes les 15 s (la personne connectée seulement) ;
/// - liens : une fois (redemandés toutes les 15 s si la maison ne répond pas) ;
/// - état des services : toutes les 30 s.
/// Rien ne tourne app cachée : `suspendre()` arrête tout, `reprendre()` relit tout de suite.
@Observable @MainActor
final class Annexes {
    /// Ce qu'un document peut montrer à la place de la liste (accès refusé, liste indisponible).
    enum AccesDocuments: Equatable, Sendable {
        case ouvert
        case reserve(String)
    }

    private(set) var documents: [DocumentMaison] = []
    private(set) var accesDocuments = AccesDocuments.ouvert
    /// « Envoi de devis.pdf… », « Reçu. Alfred le lit… » (la ligne d'état de la console, sous le dépôt).
    private(set) var etatDepot: String?
    private(set) var envoiEnCours = false
    private(set) var notifications: [NotificationConsole] = []
    private(set) var nonLues = 0
    /// Les notifications existent pour la personne connectée (le bouton de l'en-tête n'apparaît qu'alors).
    private(set) var notificationsPermises = false
    private(set) var liens: [LienSysteme] = []
    private(set) var etat: EtatServices?

    @ObservationIgnored private let acces: any AccesRelais
    @ObservationIgnored private let aviser: @MainActor (String, Conversation.Avis.Genre) -> Void
    @ObservationIgnored private var taches: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var connecte = false
    @ObservationIgnored private var actif = false

    init(acces: any AccesRelais, aviser: @escaping @MainActor (String, Conversation.Avis.Genre) -> Void) {
        self.acces = acces
        self.aviser = aviser
    }

    // MARK: - cycle

    /// La personne est connectée (`/moi`) : notifications et liens ; l'état et les documents tournent dans tous les cas.
    func demarrer(connecte: Bool) {
        self.connecte = connecte
        actif = true
        relancerTout()
    }

    func reprendre() {
        guard !actif else { return }
        actif = true
        relancerTout()
    }

    func suspendre() {
        actif = false
        for t in taches.values { t.cancel() }
        taches = [:]
    }

    private func relancerTout() {
        suspendre()
        actif = true
        boucle("etat") { [weak self] in await self?.chargerEtat() ?? .seconds(30) }
        boucle("documents") { [weak self] in await self?.chargerDocuments() ?? .seconds(60) }
        if connecte {
            boucle("notifications") { [weak self] in await self?.chargerNotifications() ?? .seconds(15) }
            boucle("liens") { [weak self] in await self?.chargerLiens() }
        } else {
            notificationsPermises = false
            liens = []
        }
    }

    /// Une lecture, puis la suivante après le délai qu'elle rend (nil : plus de relecture).
    private func boucle(_ nom: String, _ lire: @escaping @MainActor () async -> Duration?) {
        taches[nom]?.cancel()
        taches[nom] = Task { [weak self] in
            while !Task.isCancelled {
                guard let delai = await lire() else { return }
                try? await Task.sleep(for: delai)
                guard self?.actif == true else { return }
            }
        }
    }

    /// Relire les documents tout de suite (après un dépôt, une suppression, à l'ouverture de la fenêtre).
    func relireDocuments() {
        boucle("documents") { [weak self] in await self?.chargerDocuments() ?? .seconds(60) }
    }

    func relireNotifications() {
        guard connecte else { return }
        boucle("notifications") { [weak self] in await self?.chargerNotifications() ?? .seconds(15) }
    }

    // MARK: - lectures

    private func chargerEtat() async -> Duration {
        if let (statut, corps) = try? await acces.lire("/etat"), statut == 200,
            let e = try? JSONDecoder().decode(EtatServices.self, from: corps)
        {
            if e != etat { etat = e }
        }
        return .seconds(30)
    }

    private func chargerDocuments() async -> Duration {
        do {
            let (statut, corps) = try await acces.lire("/docs")
            switch statut {
            case 200:
                let l = try JSONDecoder().decode(ListeDocuments.self, from: corps).documents
                if accesDocuments != .ouvert { accesDocuments = .ouvert }
                if l != documents { documents = l }
                return l.contains { $0.etat == .enCours } ? .milliseconds(2500) : .seconds(60)
            case 401:
                documents = []
                accesDocuments = .reserve("Les documents sont réservés aux personnes connectées.")
                return .seconds(60)
            case 403:
                documents = []
                accesDocuments = .reserve(
                    String(decoding: corps.prefix(200), as: UTF8.self).nonVide ?? "Les documents vous sont fermés.")
                return .seconds(60)
            default:
                throw ErreurRelais("HTTP \(statut)")
            }
        } catch is CancellationError {
            return .seconds(60)
        } catch {
            accesDocuments = .reserve("Liste indisponible : " + Self.motif(error))
            return .seconds(30)
        }
    }

    private func chargerNotifications() async -> Duration {
        guard let (statut, corps) = try? await acces.lire("/notifications") else { return .seconds(15) }
        if statut == 401 {
            if notificationsPermises { notificationsPermises = false }
            return .seconds(15)
        }
        guard statut == 200, let l = try? JSONDecoder().decode(ListeNotifications.self, from: corps) else {
            return .seconds(15)
        }
        if !notificationsPermises { notificationsPermises = true }
        if l.notifications != notifications { notifications = l.notifications }
        if l.nonLues != nonLues { nonLues = l.nonLues }
        return .seconds(15)
    }

    /// Comme la console : maison muette (5xx) → redemandée toutes les 15 s ; une liste vide n'est pas redemandée.
    private func chargerLiens() async -> Duration? {
        guard let (statut, corps) = try? await acces.lire("/liens") else { return .seconds(15) }
        if statut >= 500 { return .seconds(15) }
        let l = statut == 200 ? LienSysteme.lire(corps) ?? [] : []
        if l != liens { liens = l }
        return nil
    }

    // MARK: - actions

    /// Dépose un document (20 Mo au plus) ; la liste se relit ensuite.
    func deposer(_ depot: DepotDocument) async {
        guard !envoiEnCours else { return }
        guard depot.fichier.count <= DepotDocument.tailleMax else {
            aviser("Document trop lourd : 20 Mo au plus.", .attention)
            return
        }
        envoiEnCours = true
        etatDepot = "Envoi de \(depot.nomFichier)…"
        defer { envoiEnCours = false }
        do {
            let (statut, _) = try await acces.envoyer(depot.requete())
            guard (200..<300).contains(statut) else {
                throw ErreurRelais(statut == 415 ? "type non pris en charge (PDF, image, texte)" : "HTTP \(statut)")
            }
            etatDepot = "Reçu. Alfred le lit…"
            aviser("Document reçu.", .info)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                if self?.etatDepot?.hasPrefix("Reçu") == true { self?.etatDepot = nil }
            }
        } catch {
            etatDepot = nil
            aviser("Envoi impossible : " + Self.motif(error), .attention)
        }
        relireDocuments()
    }

    func supprimer(_ document: DocumentMaison) async {
        let chemin =
            "/docs/" + (document.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? document.id)
        do {
            let (statut, _) = try await acces.envoyer(RequeteRelais(.delete, chemin))
            guard (200..<300).contains(statut) else { throw ErreurRelais("HTTP \(statut)") }
            aviser("Document supprimé.", .info)
        } catch {
            aviser("Suppression impossible : " + Self.motif(error), .attention)
        }
        relireDocuments()
    }

    /// À l'ouverture de la fenêtre : tout est marqué lu (si elle est encore ouverte une fois la liste chargée).
    func marquerLues() async {
        guard nonLues > 0 else { return }
        _ = try? await acces.envoyer(RequeteRelais(.post, "/notifications/lues"))
        relireNotifications()
    }

    func effacerNotifications() async {
        _ = try? await acces.envoyer(RequeteRelais(.post, "/notifications/effacer"))
        relireNotifications()
    }

    private static func motif(_ e: any Error) -> String {
        (e as? ErreurRelais)?.message ?? (e as NSError).localizedDescription
    }
}

extension String {
    fileprivate var nonVide: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
