import Foundation
import Testing

@testable import AlfredKit

@Suite("Les annexes de la console")
struct AnnexesTests {
    static func json(_ texte: String) -> Data { Data(texte.utf8) }

    @Test("Notifications : liste, non lues, champs absents")
    func notifications() throws {
        let l = try JSONDecoder().decode(
            ListeNotifications.self,
            from: Self.json(
                #"{"notifications":[{"id":"a1","t":1792240000.5,"titre":"Alfred","message":"Lessive finie","source":"x","lu":false},{"id":"b2","t":1792230000,"titre":"","message":"Réponse","lu":true}],"non_lues":1}"#
            ))
        #expect(l.nonLues == 1)
        #expect(l.notifications.map(\.id) == ["a1", "b2"])
        #expect(l.notifications[0].date == Date(timeIntervalSince1970: 1_792_240_000.5))
        #expect(!l.notifications[0].lu && l.notifications[1].lu)
        let vide = try JSONDecoder().decode(ListeNotifications.self, from: Self.json("{}"))
        #expect(vide.notifications.isEmpty && vide.nonLues == 0)
    }

    @Test("Documents : états de la console, Paperless (un objet), alerte")
    func documents() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"documents":[{"id":"20261018-101500-devis","nom":"devis","etat":"pret","resume":"Un devis.","depose_le":"2026-10-18T10:15:00+02:00","pour_le":"2026-10-20","paperless":{"tache":"x","le":"y"}},{"id":"b","nom":"lettre","etat":"en cours"},{"id":"c","nom":"photo","etat":"erreur","erreur":"illisible","alerte":"passage suspect"},{"id":"d","etat":"autre"}]}"#
            ))
        let d = l.documents
        #expect(d.map(\.etat) == [.pret, .enCours, .erreur, .enCours])
        #expect(d[0].paperless && !d[1].paperless)
        #expect(d[0].pourLe == "2026-10-20" && d[0].deposeLe == "2026-10-18T10:15:00+02:00")
        #expect(d[2].alerte == "passage suspect" && d[2].erreur == "illisible")
        #expect(d[3].nom == "d")
        #expect(DocumentMaison.vrai(.texte("")) == false && DocumentMaison.vrai(.nombre(0)) == false)
        #expect(DocumentMaison.vrai(.objet([:])) && DocumentMaison.vrai(.booleen(true)))
    }

    @Test("Documents d'un relais plus ancien (23.10) : statut déduit comme l'ancienne console, pastille, boutons")
    func documentsAncienRelais() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"documents":[{"id":"a","nom":"devis","etat":"pret","resume":"Un devis.","paperless":{"tache":"x"}},{"id":"b","nom":"note","etat":"pret","resume":"Une note."},{"id":"c","nom":"photo","etat":"erreur","erreur":"illisible"},{"id":"d","nom":"lettre","etat":"en cours"}]}"#
            ))
        let d = l.documents
        #expect(d.map(\.statut) == [.range, .lu, .refuse, .lecture])
        #expect(l.aTraiter == nil && l.horsPanneau == nil)
        #expect(l.pastille() == 1, "23.10 (soir) : les refusés seulement")
        #expect(l.pastille(refusLocaux: 1) == 2 && l.pastille(aEnvoyer: 2, refusLocaux: 1) == 4)
        #expect(d[0].texteEtat == "Rangé dans Paperless" && d[1].texteEtat == nil)
        #expect(d[2].texteEtat == "Refusé : lecture impossible (illisible)")
        #expect(d[3].texteEtat == "Lecture en cours…" && d[3].resumeAffiche == nil)
        #expect(d[1].resumeAffiche == "Une note.")
        // plus de « Supprimer » sur un document rangé ; un document que Paperless n'a pas peut encore être supprimé
        #expect(!d[0].peutSupprimer && d[1].peutSupprimer && !d[0].peutRetirer)
        #expect(d[2].peutRetirer && !d[2].peutReessayer, "l'ancien relais ne sait pas réessayer")
        #expect(l.delaiRelecture() == .milliseconds(2500))
    }

    @Test("Documents de la boîte d'arrivée (23.10) : verdicts, motifs, lien, attente du résumé, pastille du relais")
    func documentsBoiteArrivee() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"a_traiter":3,"hors_panneau":7,"documents":[{"id":"r","nom":"facture","etat":"pret","statut":"range","lien":"https://paperless.exemple.invalid/documents/12/details","paperless":{"etat":"range","document":12},"resume":null,"resume_attente":"pc","range_le":"2026-10-23T09:00:00+02:00","reessayer":false},{"id":"e","nom":"offre","etat":"pret","statut":"envoye","paperless":{"etat":"envoye","document":null},"resume":"Une offre.","resume_attente":"file"},{"id":"i","nom":"photo floue","etat":"erreur","statut":"refuse","refus":"illisible","motif":"aucun texte lisible","reessayer":true,"erreur":"aucun texte lisible"},{"id":"dv","nom":"facture bis","etat":"pret","statut":"refuse","refus":"doublon","motif":"déjà dans Paperless","lien":"https://paperless.exemple.invalid/documents/12/details","reessayer":false},{"id":"dc","nom":"pièce","etat":"pret","statut":"refuse","refus":"doublon","deja_archive":true,"lien":"javascript:alert(1)"},{"id":"g","nom":"rangement","etat":"pret","statut":"rangement"},{"id":"b","nom":"banc","etat":"pret","statut":"banc","resume":"Banc."},{"id":"x","nom":"futur","etat":"pret","statut":"inconnu","paperless":{"etat":"range"}}]}"#
            ))
        let d = l.documents
        #expect(d.map(\.statut) == [.range, .envoye, .refuse, .refuse, .refuse, .rangement, .banc, .range])
        #expect(l.aTraiter == 3 && l.horsPanneau == 7)
        #expect(l.pastille() == 3, "les trois refusés (sans « a_revoir » : comptés ici)")
        #expect(l.pastille(refusLocaux: 2) == 5)
        #expect(d[0].texteEtat == "Rangé dans Paperless — résumé quand le PC d’Alfred sera allumé")
        #expect(d[0].lien?.host == "paperless.exemple.invalid" && d[0].paperless && d[0].rangeLe != nil)
        #expect(d[1].texteEtat == "Envoyé à Paperless — résumé en cours…" && d[1].resumeAffiche == "Une offre.")
        #expect(d[2].texteEtat == "Refusé : aucun texte lisible" && d[2].peutReessayer && d[2].peutRetirer)
        #expect(d[3].texteEtat == "Refusé : déjà dans Paperless" && !d[3].peutReessayer && d[3].lien != nil)
        #expect(d[4].dejaArchive && d[4].lien == nil, "jamais un lien autre que http(s)")
        #expect(d[4].texteEtat == "Refusé : déjà dans Paperless", "doublon sans motif écrit")
        #expect(d[5].texteEtat == "Rangement dans Paperless…" && d[5].aTraiter)
        #expect(d[6].texteEtat == "Lu (banc : pas rangé dans Paperless)" && d[6].peutSupprimer)
        #expect(!d[0].peutSupprimer && !d[0].peutRetirer && !d[1].peutSupprimer, "rangé : ni Supprimer ni Retirer")
        #expect(d[7].statut == .range, "un statut inconnu : déduit comme l'ancienne console")
        #expect(l.delaiRelecture() == .milliseconds(2500), "une carte en rangement")
        #expect(
            ListeDocuments(documents: [d[1]]).delaiRelecture() == .seconds(60), "23.10 (soir) : plus de 10 s ni 30 s")
        #expect(ListeDocuments(documents: [d[2], d[3]]).delaiRelecture() == .seconds(60))
        // une valeur d'un autre type pour un champ nouveau ne perd jamais la liste
        let tolerant = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(#"{"a_traiter":"x","documents":[{"id":"t","etat":"pret","statut":5,"reessayer":"oui"}]}"#))
        #expect(tolerant.aTraiter == nil && tolerant.documents[0].statut == .lu && tolerant.documents[0].reessayer)
    }

    @Test(
        "Relecture (23.10, soir) : 2,5 s tant qu'un fichier est en cours (lot de l'app ou carte du relais), sinon 60 s")
    func relecture() {
        func d(_ statut: String, _ attente: String? = nil) -> DocumentMaison {
            DocumentMaison(id: statut, nom: statut, etat: "pret", statut: statut, resumeAttente: attente)
        }
        #expect(ListeDocuments(documents: [d("refuse"), d("lecture")]).delaiRelecture() == .milliseconds(2500))
        #expect(ListeDocuments(documents: [d("rangement")]).delaiRelecture() == .milliseconds(2500))
        #expect(ListeDocuments(documents: [d("refuse")]).delaiRelecture(lotEnCours: true) == .milliseconds(2500))
        #expect(ListeDocuments(documents: [d("refuse"), d("banc")]).delaiRelecture() == .seconds(60))
        #expect(ListeDocuments(documents: [d("envoye", "file"), d("range", "pc")]).delaiRelecture() == .seconds(60))
        #expect(ListeDocuments(documents: []).delaiRelecture() == .seconds(60))
    }

    @Test("Liste du soir (23.10) : panneau, récents (range_le, lien), à revoir, liste de Paperless ; ancien format")
    func listeDuSoir() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"documents":[{"id":"r1","nom":"photo","etat":"erreur","statut":"refuse","motif":"aucun texte lisible","reessayer":true},{"id":"c1","nom":"lettre","etat":"en cours","statut":"lecture"},{"id":"b1","nom":"banc","etat":"pret","statut":"banc"}],"recents":[{"id":"g1","nom":"facture","etat":"pret","statut":"range","range_le":"2026-10-23T18:00:00+02:00","lien":"https://paperless.exemple.invalid/documents/7/details"}],"a_revoir":1,"a_traiter":1,"hors_panneau":4,"paperless_liste":"https://paperless.exemple.invalid/documents?sort=added&reverse=1"}"#
            ))
        #expect(l.documents.map(\.id) == ["r1", "c1", "b1"] && l.recents.map(\.id) == ["g1"])
        #expect(
            l.recents[0].rangeLe == "2026-10-23T18:00:00+02:00" && l.recents[0].lien?.path == "/documents/7/details")
        #expect(l.aRevoir == 1 && l.aTraiter == 1 && l.horsPanneau == 4)
        #expect(l.paperlessListe?.host == "paperless.exemple.invalid")
        #expect(l.refuses.map(\.id) == ["r1"] && l.enCours.map(\.id) == ["c1", "b1"])
        #expect(l.pastille(aEnvoyer: 3, refusLocaux: 1) == 5)
        // ancien format : ni récents, ni à revoir, ni liste ; une liste illisible ne perd jamais le panneau
        let ancien = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"documents":[{"id":"a","etat":"pret"}],"recents":"x","paperless_liste":"javascript:alert(1)"}"#))
        #expect(ancien.documents.count == 1 && ancien.recents.isEmpty && ancien.aRevoir == nil)
        #expect(ancien.paperlessListe == nil, "http(s) seulement")
    }

    @Test("À envoyer (23.10, soir) : type par les premiers octets comme le relais, taille écrite, refus immédiats")
    func aEnvoyer() {
        let pdf = Data("%PDF-1.7".utf8)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])
        let webp = Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 ".utf8)
        #expect(TypeDocument.detecter(nom: "a.bin", entete: pdf) == "application/pdf")
        #expect(TypeDocument.detecter(nom: "photo", entete: jpeg) == "image/jpeg")
        #expect(TypeDocument.detecter(nom: "x.png", entete: png) == "image/png")
        #expect(TypeDocument.detecter(nom: "x", entete: webp) == "image/webp")
        #expect(TypeDocument.detecter(nom: "Message.EML", entete: Data("From:".utf8)) == "message/rfc822")
        #expect(TypeDocument.detecter(nom: "x", entete: Data(), typeDeclare: "message/rfc822") == "message/rfc822")
        #expect(TypeDocument.detecter(nom: "notes.md", entete: Data("# a".utf8)) == "text/plain")
        #expect(TypeDocument.detecter(nom: "liste", entete: Data("a".utf8), typeDeclare: "text/csv") == "text/plain")
        #expect(TypeDocument.detecter(nom: "lettre.docx", entete: Data("PK\u{3}\u{4}".utf8)) == nil)
        #expect(TypeDocument.detecter(nom: "a.pdf", entete: Data("PK".utf8)) == nil, "l'extension ne suffit pas")
        #expect(TailleDocument.texte(340 * 1024) == "340 ko" && TailleDocument.texte(10) == "1 ko")
        #expect(TailleDocument.texte(0) == "1 ko" && TailleDocument.texte(1536) == "2 ko")
        #expect(TailleDocument.texte(1_258_291) == "1,2 Mo" && TailleDocument.texte(20 * 1024 * 1024) == "20,0 Mo")
        let ok = FichierAEnvoyer(nom: "devis.pdf", octets: 340 * 1024, entete: pdf)
        #expect(ok.valable && ok.type == "application/pdf" && ok.ligne == "devis.pdf · 340 ko" && ok.texteRefus == nil)
        let gros = FichierAEnvoyer(nom: "plan.pdf", octets: DepotDocument.tailleMax + 1, entete: pdf)
        #expect(!gros.valable && gros.texteRefus == "Refusé : trop lourd (20 Mo au plus)")
        let docx = FichierAEnvoyer(nom: "lettre.docx", octets: 5000, entete: Data("PK".utf8))
        #expect(docx.texteRefus == "Refusé : type non pris en charge (PDF, image, texte ou e-mail)")
        #expect(RefusLocal(nom: "x", motif: .envoiCoupe("HTTP 502")).texte == "Refusé : envoi coupé (HTTP 502)")
    }

    @Test("Suivi d'un lot (23.10, soir) : Envoi…, Rangement…, rangé dans les récents ; confirmation 1 ou N ; refus")
    func suiviLot() {
        let (a, b, c, e) = (UUID(), UUID(), UUID(), UUID())
        var s = SuiviLot()
        s.envoi(a, nom: "a.pdf")
        s.envoi(b, nom: "b.pdf")
        #expect(s.lignes == ["a.pdf — Envoi…", "b.pdf — Envoi…"] && s.enCours)
        s.recu(a, document: "d-a")
        s.recu(b, document: "d-b")
        s.envoi(c, nom: "c.pdf")
        s.echec(c)
        s.envoi(e, nom: "e.pdf")
        s.recu(e, document: nil)
        #expect(s.lignes == ["a.pdf — Rangement…", "b.pdf — Rangement…"] && s.documentsSuivis == ["d-a", "d-b"])
        func carte(_ id: String, _ statut: String, lien: String? = nil) -> DocumentMaison {
            DocumentMaison(id: id, nom: id, etat: "pret", statut: statut, lien: lien.flatMap(URL.init(string:)))
        }
        let liste = URL(string: "https://paperless.exemple.invalid/documents")
        let l1 = ListeDocuments(
            documents: [carte("d-b", "rangement")],
            recents: [carte("d-a", "range", lien: "https://paperless.exemple.invalid/documents/1/details")],
            paperlessListe: liste)
        var nouveau = s.maj(l1)
        #expect(nouveau && s.lignes == ["b.pdf — Rangement…"])
        #expect(s.confirmation(l1)?.ligne == "1 document rangé dans Paperless — voir")
        #expect(s.confirmation(l1)?.lien?.path == "/documents/1/details")
        nouveau = s.maj(l1)
        #expect(!nouveau, "rien de neuf")
        let l2 = ListeDocuments(
            documents: [], recents: [carte("d-b", "range"), carte("d-a", "range")], paperlessListe: liste)
        nouveau = s.maj(l2)
        #expect(nouveau && s.lignes.isEmpty && !s.enCours)
        #expect(s.confirmation(l2) == ConfirmationRangement(texte: "2 documents rangés dans Paperless", lien: liste))
        let sansLien = ConfirmationRangement(texte: "1 document rangé dans Paperless", lien: nil)
        #expect(sansLien.ligne == "1 document rangé dans Paperless", "sans lien : pas de « voir »")
        // refusé au relais : il passe dans « À revoir », plus en cours, pas compté
        var r = SuiviLot()
        r.envoi(a, nom: "a.pdf")
        r.recu(a, document: "d-a")
        r.maj(ListeDocuments(documents: [carte("d-a", "refuse")]))
        #expect(r.lignes.isEmpty && r.confirmation(ListeDocuments(documents: [])) == nil)
        r.nouveau()
        #expect(r.fichiers.isEmpty)
        // 23.10 : une liste demandée AVANT la réception d'un fichier revient après, sans lui : il reste en cours (le
        // compter « disparu » donnait « 1 document rangé » au lieu de 2) ; une liste demandée après le range
        var c2 = SuiviLot()
        c2.envoi(a, nom: "a.pdf")
        c2.recu(a, document: "d-a")
        c2.envoi(b, nom: "b.pdf")
        let ancienne = c2.lectureLancee()
        c2.recu(b, document: "d-b")
        c2.maj(ListeDocuments(documents: [], recents: [carte("d-a", "range")]), lecture: ancienne)
        #expect(
            c2.lignes == ["b.pdf — Rangement…"] && c2.enCours, "liste partie avant la réception : absence sans effet")
        let recente = c2.lectureLancee()
        c2.maj(
            ListeDocuments(documents: [], recents: [carte("d-b", "range"), carte("d-a", "range")]), lecture: recente)
        #expect(c2.confirmation(ListeDocuments(documents: []))?.texte == "2 documents rangés dans Paperless")
        // absent d'une liste demandée APRÈS la réception : fini (comme avant)
        var c3 = SuiviLot()
        c3.envoi(a, nom: "a.pdf")
        c3.recu(a, document: "d-a")
        let apres = c3.lectureLancee()
        c3.maj(ListeDocuments(documents: []), lecture: apres)
        #expect(c3.lignes.isEmpty && !c3.enCours)
    }

    @Test(
        "Deux temps (23.10) : armer, confirmer dans les 3,5 s ; autre document ou autre action : réarme ; délai passé")
    func deuxTemps() {
        let t0 = Date(timeIntervalSince1970: 1_792_300_000)
        var b = DeuxTemps()
        // un toucher modifie l'état : son résultat est lu avant le #expect (la macro n'accepte pas un appel « mutating »)
        var confirme = b.toucher("retirer", id: "a", maintenant: t0)
        #expect(!confirme, "le premier toucher arme")
        #expect(b.estArme("retirer", id: "a", maintenant: t0 + 3) && !b.estArme("retirer", id: "b", maintenant: t0))
        confirme = b.toucher("retirer", id: "a", maintenant: t0 + 3)
        #expect(confirme, "le second, dans le délai, confirme")
        #expect(!b.estArme("retirer", id: "a", maintenant: t0 + 3), "puis plus rien d'armé")
        confirme = b.toucher("retirer", id: "a", maintenant: t0 + 10)
        #expect(!confirme)
        confirme = b.toucher("supprimer", id: "a", maintenant: t0 + 11)
        #expect(!confirme, "une autre action réarme")
        confirme = b.toucher("supprimer", id: "b", maintenant: t0 + 12)
        #expect(!confirme, "un autre document réarme")
        #expect(!b.estArme("supprimer", id: "a", maintenant: t0 + 12), "une seule action armée à la fois")
        confirme = b.toucher("supprimer", id: "b", maintenant: t0 + 15.6)
        #expect(!confirme, "délai passé : réarme au lieu de confirmer")
        b.expirer(maintenant: t0 + 16)
        #expect(b.estArme("supprimer", id: "b", maintenant: t0 + 16), "pas encore expiré")
        b.expirer(maintenant: t0 + 19.1)
        #expect(!b.estArme("supprimer", id: "b", maintenant: t0 + 15.7), "expiré : plus rien d'armé")
    }

    @Test(
        "Refus de Paperless (23.10) : « paperless_refus », motif tel quel, Réessayer ; un code inconnu reste un refus")
    func refusPaperless() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"a_traiter":3,"documents":[{"id":"p","nom":"devis","etat":"pret","statut":"refuse","refus":"paperless_refus","motif":"Paperless n'a pas pu ranger ce fichier","reessayer":true,"resume":"Un devis."},{"id":"a","nom":"lettre","etat":"pret","statut":"refuse","refus":"paperless_absent","motif":"pas encore rangé dans Paperless","reessayer":true},{"id":"x","nom":"note","etat":"pret","statut":"refuse","refus":"code_futur","motif":"un motif nouveau","reessayer":true}]}"#
            ))
        let d = l.documents
        #expect(d.map(\.statut) == [.refuse, .refuse, .refuse])
        #expect(d[0].refus == "paperless_refus" && d[0].texteEtat == "Refusé : Paperless n'a pas pu ranger ce fichier")
        #expect(d[0].peutReessayer && d[0].peutRetirer && !d[0].peutSupprimer && d[0].resumeAffiche == "Un devis.")
        #expect(d[1].texteEtat == "Refusé : pas encore rangé dans Paperless" && d[1].peutReessayer)
        #expect(d[2].texteEtat == "Refusé : un motif nouveau" && d[2].peutReessayer, "code inconnu : un simple refus")
        #expect(l.pastille() == 3)
    }

    @Test("Doublon (23.10, soir) : un avertissement, pas un refus — décodé, hors pastille, sans bouton")
    func doublon() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"documents":[{"id":"r","etat":"erreur","statut":"refuse","motif":"aucun texte lisible","reessayer":true},{"id":"x","etat":"pret","statut":"doublon"}],"recents":[{"id":"d","nom":"facture","etat":"pret","statut":"doublon","refus":null,"reessayer":false,"range_le":"2026-10-23T18:00:00+02:00","avertissement":"déjà présent dans Paperless — étiquette « Assurances » ajoutée","etiquettes_ajoutees":["Assurances"],"etiquettes_non_ajoutees":["Banque"],"lien":"https://paperless.exemple.invalid/documents/3/details","deja_archive":false}],"a_revoir":1}"#
            ))
        let d = l.recents[0]
        #expect(d.statut == .doublon && !d.aTraiter && !d.peutRetirer && !d.peutReessayer && !d.peutSupprimer)
        #expect(d.avertissement == "déjà présent dans Paperless — étiquette « Assurances » ajoutée")
        #expect(d.etiquettesAjoutees == ["Assurances"] && d.etiquettesNonAjoutees == ["Banque"] && d.rangeLe != nil)
        #expect(l.refuses.map(\.id) == ["r"], "« À revoir » : les vrais échecs seulement")
        #expect(
            l.pastille() == 1 && ListeDocuments(documents: [l.documents[1]]).pastille() == 0, "pas dans la pastille")
        #expect(!l.enCours.contains { $0.id == "x" })
    }

    @Test("Confirmation (23.10, soir) : rangés R, déjà présents D — chaque forme de la ligne, et son « voir »")
    func confirmationFormes() {
        let liste = URL(string: "https://paperless.exemple.invalid/documents")
        func fiche(_ i: Int) -> URL? { URL(string: "https://paperless.exemple.invalid/documents/\(i)/details") }
        let ajoutee = "déjà présent dans Paperless — étiquette « X » ajoutée"
        func ligne(ranges: Int, doublons: [String?], liens: Bool = true) -> ConfirmationRangement? {
            var s = SuiviLot()
            var recents: [DocumentMaison] = []
            for i in 0..<ranges {
                let cle = UUID()
                s.envoi(cle, nom: "r\(i)")
                s.recu(cle, document: "r\(i)")
                recents.append(
                    DocumentMaison(
                        id: "r\(i)", nom: "r\(i)", etat: "pret", statut: i == 1 ? "envoye" : "range",
                        lien: liens ? fiche(i) : nil))
            }
            for (i, avertissement) in doublons.enumerated() {
                let cle = UUID()
                s.envoi(cle, nom: "d\(i)")
                s.recu(cle, document: "d\(i)")
                recents.append(
                    DocumentMaison(
                        id: "d\(i)", nom: "d\(i)", etat: "pret", statut: "doublon",
                        lien: liens ? fiche(100 + i) : nil, avertissement: avertissement))
            }
            let l = ListeDocuments(documents: [], recents: recents, paperlessListe: liste)
            s.maj(l)
            return s.confirmation(l)
        }
        #expect(ligne(ranges: 0, doublons: []) == nil)
        #expect(ligne(ranges: 1, doublons: [])?.ligne == "1 document rangé dans Paperless — voir")
        #expect(ligne(ranges: 1, doublons: [])?.lien == fiche(0))
        #expect(ligne(ranges: 1, doublons: [], liens: false)?.ligne == "1 document rangé dans Paperless")
        #expect(ligne(ranges: 3, doublons: [])?.ligne == "3 documents rangés dans Paperless — voir")
        #expect(ligne(ranges: 3, doublons: [])?.lien == liste)
        #expect(
            ligne(ranges: 1, doublons: ["déjà présent dans Paperless"])?.texte
                == "1 document rangé dans Paperless, 1 déjà présent")
        #expect(
            ligne(ranges: 1, doublons: [ajoutee])?.texte
                == "1 document rangé dans Paperless, 1 déjà présent (étiquette « X » ajoutée)")
        #expect(
            ligne(ranges: 3, doublons: [ajoutee, nil])?.texte == "3 documents rangés dans Paperless, 2 déjà présents")
        #expect(ligne(ranges: 3, doublons: [ajoutee, nil])?.lien == liste)
        #expect(
            ligne(ranges: 0, doublons: [ajoutee])?.ligne
                == "1 document déjà présent dans Paperless — étiquette « X » ajoutée — voir")
        #expect(ligne(ranges: 0, doublons: [ajoutee])?.lien == fiche(100), "un seul : sa fiche")
        #expect(ligne(ranges: 0, doublons: ["déjà archivé"], liens: false)?.ligne == "1 document déjà archivé")
        #expect(ligne(ranges: 0, doublons: [nil])?.texte == "1 document déjà présent dans Paperless")
        #expect(ligne(ranges: 0, doublons: [nil, ajoutee])?.ligne == "2 documents déjà présents dans Paperless — voir")
    }

    @Test("Étiquettes (23.10) : liste du relais, tolérante ; nettoyage d'un nom tapé ; clé sans casse ni accents")
    func etiquettesListeEtNettoyage() throws {
        let l = try JSONDecoder().decode(
            ListeEtiquettes.self,
            from: Self.json(
                #"{"etiquettes":[{"id":3,"nom":"Assurance"},{"id":"x","nom":"Faux"},{"id":7,"nom":""},{"id":9,"nom":"Électricité"}],"disponible":true}"#
            ))
        #expect(
            l.etiquettes == [EtiquetteDocument(id: 3, nom: "Assurance"), EtiquetteDocument(id: 9, nom: "Électricité")])
        #expect(l.disponible)
        let muette = try JSONDecoder().decode(
            ListeEtiquettes.self, from: Self.json(#"{"etiquettes":[],"disponible":false}"#))
        #expect(muette.etiquettes.isEmpty && !muette.disponible)
        #expect(try JSONDecoder().decode(ListeEtiquettes.self, from: Self.json("{}")).disponible == false)
        // contrôle, format (invisible), séparateurs → espace ; espaces réduits ; bords retirés ; 40 au plus ; NFC
        #expect(Etiquettes.nettoyer("  Impôts\t2026\n ") == "Impôts 2026")
        #expect(Etiquettes.nettoyer("Mai\u{200B}son\u{00A0}\u{00A0}neuve\u{2028}") == "Mai son neuve")
        #expect(
            Etiquettes.nettoyer("Cafe\u{0301}") == "Café"
                && Etiquettes.nettoyer("Cafe\u{0301}")?.unicodeScalars.count == 4)
        #expect(Etiquettes.nettoyer(String(repeating: "a", count: 50))?.count == 40)
        #expect(Etiquettes.nettoyer(String(repeating: "a", count: 39) + " b") == String(repeating: "a", count: 39))
        #expect(Etiquettes.nettoyer(" \u{200B}\n\t ") == nil && Etiquettes.nettoyer("") == nil)
        #expect(Etiquettes.cle("Électricité") == Etiquettes.cle("electricite"))
        #expect(Etiquettes.cle("ÉCOLE") == "ecole")
    }

    @Test("Étiquettes (23.10) : propositions par les premières lettres (nom ou mot), 8 au plus, nouvelle en dernier")
    func etiquettesPropositions() {
        let liste = [
            "Assurance", "Assurance maladie", "Banque", "Électricité", "Facture électricité", "Impôts", "Maison",
            "Voiture", "Assignation", "Astuce", "Asile", "Asperge", "Aster", "Asphalte", "Assiette",
        ].enumerated().map { EtiquetteDocument(id: $0.offset + 1, nom: $0.element) }
        let elec = Etiquettes.propositions("elec", liste: liste, choisies: [])
        #expect(elec.map(\.texte) == ["Électricité", "Facture électricité", "Nouvelle étiquette : elec"])
        // la saisie nettoyée correspond à une étiquette (sans casse ni accents) : pas de « nouvelle »
        let exacte = Etiquettes.propositions("ELECTRICITE ", liste: liste, choisies: [])
        #expect(exacte.map(\.texte) == ["Électricité", "Facture électricité"])
        // celles déjà choisies sont exclues, et une nouvelle déjà choisie n'est pas reproposée
        let choisies: [ChoixEtiquette] = [.existante(liste[3]), .nouvelle("Électroménager")]
        #expect(
            Etiquettes.propositions("élec", liste: liste, choisies: choisies).map(\.texte) == [
                "Facture électricité", "Nouvelle étiquette : élec",
            ])
        #expect(Etiquettes.propositions("electromenager", liste: liste, choisies: choisies).isEmpty)
        // 8 au plus, puis la nouvelle
        let parAs = Etiquettes.propositions("as", liste: liste, choisies: [])
        #expect(
            parAs.count == 9 && parAs.last == .nouvelle("as")
                && parAs.dropLast().allSatisfy { $0.texte.lowercased().contains("as") })
        // saisie vide (champ touché) : les 8 premières dans l'ordre du relais, choisies exclues, sans « nouvelle »
        #expect(
            Etiquettes.propositions("  ", liste: liste, choisies: []).map(\.texte) == Array(liste.prefix(8).map(\.nom)))
        #expect(
            Etiquettes.propositions("", liste: liste, choisies: [.existante(liste[0])]).map(\.texte)
                == Array(liste.dropFirst().prefix(8).map(\.nom)))
        #expect(Etiquettes.propositions("", liste: [], choisies: []).isEmpty)
        #expect(
            Etiquettes.propositions("mal", liste: liste, choisies: []).first?.texte == "Assurance maladie",
            "un mot du nom")
        #expect(Etiquettes.choixDirect("maison", liste: liste, choisies: []) == .existante(liste[6]))
        #expect(Etiquettes.choixDirect(" Jardin\u{200B} ", liste: liste, choisies: []) == .nouvelle("Jardin"))
        #expect(Etiquettes.choixDirect("électroménager", liste: liste, choisies: choisies) == nil, "déjà choisie")
        #expect(
            ChoixEtiquette.existante(liste[0]).valeur == "1" && ChoixEtiquette.nouvelle("Jardin").valeur == "Jardin")
    }

    @Test("Étiquettes (23.10) : un champ « etiquette » par étiquette, les mêmes pour tout le lot ; 10 au plus")
    func etiquettesMultipart() throws {
        let lot = LotDepot(pourLe: nil, total: 2, etiquettes: ["3", "Jardin"])
        // un fichier sans « F » majuscule : la frontière « F » reste telle quelle
        for nom in ["a.pdf", "b.pdf"] {
            let r = lot.depot(fichier: Data("%pdf".utf8), nomFichier: nom, type: "application/pdf").requete(
                frontiere: "F")
            let texte = String(decoding: try #require(r.corps), as: UTF8.self)
            #expect(texte.contains("--F\r\nContent-Disposition: form-data; name=\"etiquette\"\r\n\r\n3\r\n"))
            #expect(texte.contains("name=\"etiquette\"\r\n\r\nJardin\r\n--F--\r\n"))
            #expect(texte.components(separatedBy: "name=\"etiquette\"").count == 3)
        }
        let trop = DepotDocument(
            fichier: Data(), nomFichier: "c.pdf", type: "application/pdf", etiquettes: (1...12).map(String.init))
        #expect(trop.etiquettes.count == 10)
        let sans = DepotDocument(fichier: Data(), nomFichier: "d.pdf", type: "application/pdf")
        #expect(!String(decoding: sans.requete(frontiere: "F").corps!, as: UTF8.self).contains("etiquette"))
        // la frontière n'apparaît jamais dans une étiquette
        let piege = DepotDocument(fichier: Data(), nomFichier: "e.pdf", type: "application/pdf", etiquettes: ["xFy"])
        #expect(piege.requete(frontiere: "F").type != "multipart/form-data; boundary=F")
    }

    @Test(
        "Étiquettes d'une carte (23.10) : posées et non posées après la date ; ancien relais : rien ; refus 400 lisible"
    )
    func etiquettesCarte() throws {
        let l = try JSONDecoder().decode(
            ListeDocuments.self,
            from: Self.json(
                #"{"documents":[{"id":"a","etat":"pret","statut":"range","etiquettes":["Maison","Jardin"],"etiquettes_non_posees":["Jardin"]},{"id":"b","etat":"pret","statut":"range","etiquettes":["Impôts"],"etiquettes_non_posees":["A","B"]},{"id":"c","etat":"pret"},{"id":"d","etat":"pret","etiquettes":"x","etiquettes_non_posees":[1,""]}]}"#
            ))
        let d = l.documents
        #expect(d[0].etiquettes == ["Maison", "Jardin"] && d[0].etiquettesNonPosees == ["Jardin"])
        #expect(d[0].texteEtiquettes == " · étiquettes : Maison, Jardin · non posée : Jardin")
        #expect(d[1].texteEtiquettes == " · étiquettes : Impôts · non posées : A, B")
        #expect(d[2].etiquettes.isEmpty && d[2].texteEtiquettes.isEmpty, "ancien relais")
        #expect(d[3].etiquettes.isEmpty && d[3].etiquettesNonPosees.isEmpty, "valeurs d'un autre type : sautées")
        let refus = RefusLocal(
            nom: "devis.pdf", statut: 400,
            corps: Data("étiquette inconnue (n° 12) : rechoisissez-la dans la liste".utf8))
        #expect(refus?.texte == "Refusé : étiquette inconnue (n° 12) : rechoisissez-la dans la liste")
        #expect(RefusLocal(nom: "x", statut: 400) == nil, "400 sans texte : un échec ordinaire")
    }

    @Test("Réessayer et retirer (23.10) : les requêtes du relais, l'identifiant échappé")
    func reessayer() {
        let d = DocumentMaison(id: "20261023-101500-devis-ab12", nom: "devis", etat: "erreur", statut: "refuse")
        #expect(d.requeteReessayer == RequeteRelais(.post, "/docs/20261023-101500-devis-ab12/reessayer"))
        #expect(d.requeteReessayer.corps == nil && d.requeteReessayer.type == nil)
        #expect(d.requeteRetirer == RequeteRelais(.delete, "/docs/20261023-101500-devis-ab12"))
        let piege = DocumentMaison(id: "../notifications/effacer", nom: "x", etat: "erreur")
        #expect(piege.requeteReessayer.chemin == "/docs/..%2Fnotifications%2Feffacer/reessayer")
        #expect(DocumentMaison.segment("42") == "42")
    }

    @Test("Lot (23.10) : « Pour le » vaut pour tout le lot ; lignes d'état ; refus de l'appareil")
    func lot() {
        let lot = LotDepot(pourLe: "2026-10-24", total: 3)
        let a = lot.depot(fichier: Data("%PDF".utf8), nomFichier: "a.pdf", type: "application/pdf")
        let b = lot.depot(fichier: Data("x".utf8), nomFichier: "b.txt", type: "text/plain")
        #expect(a.pourLe == "2026-10-24" && b.pourLe == "2026-10-24")
        #expect(String(decoding: b.requete(frontiere: "F").corps!, as: UTF8.self).contains("2026-10-24"))
        #expect(
            LotDepot(pourLe: nil, total: 1).depot(fichier: Data(), nomFichier: "c.png", type: "image/png").pourLe == nil
        )
        #expect(lot.etatEnvoi("a.pdf", rang: 2) == "Envoi de a.pdf (2 sur 3)…")
        #expect(LotDepot(pourLe: nil, total: 1).etatEnvoi("a.pdf", rang: 1) == "Envoi de a.pdf…")
        #expect(LotDepot.recus(0) == nil && LotDepot.recus(1) == "Reçu. Alfred le lit…")
        #expect(LotDepot.recus(3) == "3 reçus. Alfred les lit…")
        #expect(RefusLocal(nom: "gros.pdf", statut: 413)?.texte == "Refusé : trop lourd (20 Mo au plus)")
        #expect(
            RefusLocal(nom: "x.docx", statut: 415)?.texte
                == "Refusé : type non pris en charge (PDF, image, texte ou e-mail)")
        #expect(RefusLocal(nom: "x", statut: 500) == nil && RefusLocal(nom: "x", statut: 202) == nil)
    }

    @Test("Dépôt : le corps multipart de la console (fichier, nom, pour le)")
    func depot() throws {
        let fichier = Data([0x25, 0x50, 0x44, 0x46, 0x0D, 0x0A, 0x00, 0xFF])
        let d = DepotDocument(
            fichier: fichier, nomFichier: "devis_toiture-2026.pdf", type: "application/pdf", pourLe: "2026-10-20")
        #expect(d.nom == "devis toiture 2026")
        let r = d.requete(frontiere: "FRONTIERE")
        #expect(r.methode == .post && r.chemin == "/docs")
        #expect(r.type == "multipart/form-data; boundary=FRONTIERE")
        var attendu = Data(
            ("--FRONTIERE\r\nContent-Disposition: form-data; name=\"fichier\"; filename=\"devis_toiture-2026.pdf\"\r\n"
                + "Content-Type: application/pdf\r\n\r\n").utf8)
        attendu.append(fichier)
        attendu.append(
            Data(
                ("\r\n--FRONTIERE\r\nContent-Disposition: form-data; name=\"nom\"\r\n\r\ndevis toiture 2026\r\n"
                    + "--FRONTIERE\r\nContent-Disposition: form-data; name=\"pour_le\"\r\n\r\n2026-10-20\r\n"
                    + "--FRONTIERE--\r\n").utf8))
        #expect(r.corps == attendu)
        let sansJour = DepotDocument(fichier: fichier, nomFichier: "a.pdf", type: "application/pdf")
        #expect(!String(decoding: sansJour.requete(frontiere: "F").corps!, as: UTF8.self).contains("pour_le"))
    }

    @Test("Dépôt : la frontière n'apparaît jamais dans le fichier ; un nom ne casse pas l'en-tête")
    func frontiere() {
        let piege = DepotDocument(fichier: Data("--F\r\n".utf8), nomFichier: "a\"b\nc.txt", type: "text/plain")
        let r = piege.requete(frontiere: "F")
        let frontiere = String(r.type!.split(separator: "=").last!)
        #expect(frontiere != "F" && frontiere.hasPrefix("F-"))
        #expect(piege.fichier.range(of: Data(frontiere.utf8)) == nil)
        #expect(String(decoding: r.corps!, as: UTF8.self).contains("filename=\"a%22b%0Ac.txt\""))
    }

    @Test("Liens : http(s) seulement")
    func liens() throws {
        let l = try #require(
            LienSysteme.lire(
                Self.json(
                    #"[{"nom":"Maison","url":"http://maison.example:8123","note":"la maison"},{"nom":"Faux","url":"javascript:alert(1)","note":""},{"nom":"Docs","url":"https://docs.example","note":null}]"#
                )))
        #expect(l.map(\.nom) == ["Maison", "Docs"])
        #expect(LienSysteme.lire(Self.json("{}")) == nil)
        #expect(LienSysteme.lire(Self.json("[]")) == [])
    }

    @Test("État des services : groupes, mots et noms courts de la console, panne, lien d'historique")
    func etat() throws {
        let e = try JSONDecoder().decode(
            EtatServices.self,
            from: Self.json(
                #"{"groupes":[{"nom":"Maison","services":[{"nom":"HA","statut":"ok","message":"","depuis":"2026-10-18 06:00:00.123"}]},{"nom":"Voix d'Alfred","services":[{"nom":"Modèle","statut":"eteint","message":null,"depuis":null},{"nom":"Garde","statut":"panne","message":"timeout","depuis":"2026-10-18T06:00:00Z"}]}],"kuma":"http://surveillance.example:3001/status/x"}"#
            ))
        #expect(e.groupes.map(\.nomCourt) == ["maison", "voix"])
        #expect(e.groupes[1].services.map(\.mot) == ["éteint (normal)", "EN PANNE"])
        #expect(e.panne)
        #expect(e.kuma?.host == "surveillance.example")
        // sans fuseau = UTC, comme la console
        let depuis = try #require(e.groupes[0].services[0].dateDepuis)
        #expect(abs(depuis.timeIntervalSince1970 - 1_792_303_200.123) < 0.001)
        #expect(e.groupes[1].services[1].dateDepuis == Date(timeIntervalSince1970: 1_792_303_200))
        let sansLien = try JSONDecoder().decode(EtatServices.self, from: Self.json(#"{"kuma":"file:///etc"}"#))
        #expect(sansLien.kuma == nil && sansLien.groupes.isEmpty && !sansLien.panne)
    }

    @Test("Réponse d'Hermes à lire (22.10) : champs lus, choisie si récente et pas réclamée, voix sûre seulement")
    func reponseHermes() throws {
        let l = try JSONDecoder().decode(
            ListeNotifications.self,
            from: Self.json(
                #"{"notifications":[{"id":"h2","t":1792240100,"titre":"Hermes","message":"Prise","source":"hermes","a_lire":true,"livree":true,"lu":true},{"id":"h1","t":1792240050,"titre":"Hermes","message":"La facture est arrivée.","source":"hermes","a_lire":true,"livree":false,"lu":false},{"id":"n1","t":1792240000,"message":"Lessive","source":"notify.mobile_app_m","lu":false}],"non_lues":2}"#
            ))
        let h1 = l.notifications[1]
        #expect(h1.aLire == true && h1.livree == false && l.notifications[2].aLire == nil)
        let question = Date(timeIntervalSince1970: 1_792_240_000)
        #expect(l.reponseHermes(depuis: question)?.id == "h1", "la déjà réclamée et l'ordinaire sont sautées")
        let apres = Date(timeIntervalSince1970: 1_792_240_200)
        #expect(l.reponseHermes(depuis: apres) == nil, "plus ancienne que la question")
        // 23.10 : deux questions de suite, deux réponses prêtes (le relais les range la plus récente d'abord) : la plus
        // ancienne d'abord, dans l'ordre des questions
        let deux = try JSONDecoder().decode(
            ListeNotifications.self,
            from: Self.json(
                #"{"notifications":[{"id":"h4","t":1792240090,"titre":"Hermes","message":"Seconde","source":"hermes","a_lire":true,"livree":false,"lu":false},{"id":"h3","t":1792240060,"titre":"Hermes","message":"Première","source":"hermes","a_lire":true,"livree":false,"lu":false}],"non_lues":2}"#
            ))
        #expect(deux.reponseHermes(depuis: question)?.id == "h3")
        let r = try JSONDecoder().decode(
            ReponseLivree.self, from: Self.json(#"{"ok":true,"message":"La facture est arrivée.","tts":"ab_12.mp3"}"#))
        #expect(r.ok && r.cheminVoix == "/tts/ab_12.mp3")
        #expect(ReponseLivree(ok: true, message: "x", tts: "../etat").cheminVoix == nil, "jamais une autre route")
        #expect(ReponseLivree(ok: true, message: "x", tts: nil).cheminVoix == nil)
        let non = try JSONDecoder().decode(ReponseLivree.self, from: Self.json(#"{"ok":false}"#))
        #expect(!non.ok && non.message == nil)
    }

    @Test("Heure d'une notification : comme la console")
    func quand() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
        let maintenant = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9)))
        func a(_ jour: Int, _ h: Int, _ m: Int) throws -> Date {
            try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: jour, hour: h, minute: m)))
        }
        #expect(Quand.texte(try a(18, 7, 5), maintenant: maintenant, calendrier: cal) == "07:05")
        #expect(Quand.texte(try a(17, 22, 40), maintenant: maintenant, calendrier: cal) == "hier 22:40")
        #expect(Quand.texte(try a(3, 14, 0), maintenant: maintenant, calendrier: cal) == "3.10 14:00")
    }

    @Test("Pièces citées dans une réponse, mode invités et voix (champs facultatifs)")
    func citees() throws {
        let c = try #require(
            ConsoleMaison.lire([
                "version": 1,
                "pieces": [
                    ["nom": "SALON", "etage": "rdc", "lumiere": "light.a", "mots": #"\bsalon\b"#],
                    ["nom": "BUREAU", "etage": "1er", "lumiere": "light.b", "mots": #"\bbureau\b(?! d.[ée]tude)"#],
                    ["nom": "ÉTUDE", "etage": "2e", "lumiere": "light.c", "mots": #"bureau d.[ée]tude"#],
                    ["nom": "CAVE", "etage": "ss", "lumiere": "light.d"],
                    ["nom": "CASSÉ", "etage": "ss", "lumiere": "light.e", "mots": "(["],
                ],
                "invites": "input_boolean.invites", "voix": "sensor.voix",
            ]))
        #expect(c.citees("Le Salon est allumé, le bureau aussi.").map(\.nom) == ["SALON", "BUREAU"])
        #expect(c.citees("J'ai éteint le bureau d'étude.").map(\.nom) == ["ÉTUDE"])
        #expect(c.citees("Rien ici, ni salons.").isEmpty)
        #expect(c.invites == "input_boolean.invites" && c.voix == "sensor.voix")
        #expect(c.entites.isSuperset(of: ["input_boolean.invites", "sensor.voix"]))
        let ancien = try #require(ConsoleMaison.lire(["version": 1, "pieces": [["nom": "A", "lumiere": "light.a"]]]))
        #expect(ancien.invites == nil && ancien.voix == nil && ancien.pieces[0].mots == nil)
    }

    @Test("Détails techniques : les arguments d'un outil, comme la console")
    func arguments() {
        let a = AppelOutil(
            id: "1", nom: "homeassistant__HassTurnOn",
            arguments: ["name": "Salon", "domain": ["light"], "brightness": 40, "ratio": 0.5, "seul": true])
        #expect(a.nomCourt == "HassTurnOn")
        #expect(a.argumentsEnTexte == #"40, ["light"], Salon, 0.5, true"#)
        #expect(AppelOutil(id: "2", nom: "x").argumentsEnTexte == "")
    }

    @Test("Modèle de la console : l'agent du pipeline préféré")
    func moteur() {
        let liste: ValeurJSON = [
            "pipelines": [
                ["id": "p1", "conversation_engine": "conversation.autre"],
                ["id": "p2", "conversation_engine": "conversation.gemma4_12b"],
            ]
        ]
        #expect(ClientRelais.moteur(liste, pipeline: "p2") == "gemma4_12b")
        #expect(ClientRelais.moteur(liste, pipeline: "p3") == nil)
        #expect(ClientRelais.moteur(liste, pipeline: nil) == nil)
        #expect(
            ClientRelais.moteur(["pipelines": [["id": "p", "conversation_engine": "agent"]]], pipeline: "p") == "agent")
    }
}
