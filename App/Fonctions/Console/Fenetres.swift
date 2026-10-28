import AlfredKit
import SwiftUI

// MARK: - documents

/// Les documents de l'espace MOI (28.10 : avant, une fenêtre ouverte depuis l'en-tête). 23.10, soir, retour d'essai :
/// « ajouter les docs, choisir le tag et cliquer sur envoyer pour envoyer sur Paperless, et une fois dans Paperless ils
/// ne doivent plus apparaître » : « Ajouter des documents »
/// remplit « À envoyer » (rien ne part) ; « Étiquettes » et « Pour le » valent pour le lot ; « Envoyer à Paperless »
/// l'envoie ; « En cours » suit chaque fichier jusqu'à son rangement, puis une ligne confirme (« 3 documents rangés
/// dans Paperless — voir », 60 s) ; « À revoir » garde les vrais échecs (« Réessayer », « Retirer »). Un document rangé,
/// ou déjà présent dans Paperless (un avertissement), quitte la liste.
struct DocumentsMoi: View {
    @Environment(Alfred.self) private var alfred
    /// Le jour que le document concerne : aucun par défaut (le champ vide de la console).
    @State private var avecJour = false
    @State private var jour = Calendar.current.startOfDay(for: .now)
    /// 23.10 : les étiquettes du prochain lot (aucune par défaut), vidées une fois le lot envoyé.
    @State private var etiquettes: [ChoixEtiquette] = []

    var body: some View {
        BlocPage(titre: "Documents", largeurMax: 560) {
            VStack(alignment: .leading, spacing: 10) {
                Depot()
                if case .reserve(let texte)? = alfred.annexes?.accesDocuments {
                    Text(texte).font(.caption).foregroundStyle(Color(.texteSecondaire))
                } else {
                    aEnvoyer
                    // un relais plus ancien ne connaît pas les étiquettes : le champ n'apparaît pas
                    if alfred.annexes?.etiquettes != nil {
                        ChampEtiquettes(choisies: $etiquettes)
                    }
                    quand
                    boutonEnvoyer
                    confirmation
                    Group {
                        enCours
                        aRevoir
                    }
                    .masqueInvites(alfred.modeInvites)
                }
            }
        }
        .onAppear {
            alfred.annexes?.relireDocuments()
            alfred.annexes?.relireEtiquettes()
        }
        .onDisappear { alfred.annexes?.oublierErreurDepot() }
    }

    /// « Pour le » : le jour que le document concerne (facultatif), et la ligne d'état du dépôt.
    private var quand: some View {
        HStack(spacing: 8) {
            Text("Pour le").font(.caption).foregroundStyle(Color(.texteSecondaire))
            if avecJour {
                DatePicker("Pour le", selection: $jour, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "fr_CH"))
                Button {
                    avecJour = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.texteSecondaire))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retirer le jour")
            } else {
                Button {
                    jour = Calendar.current.startOfDay(for: .now)
                    avecJour = true
                } label: {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(Color(.glace))
                        .frame(width: 46, height: 30)
                        .background(Color(red: 14 / 255, green: 34 / 255, blue: 51 / 255), in: .rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.trait), lineWidth: 1.5))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pour le : aucun jour")
                .accessibilityHint("Choisir le jour que le document concerne")
            }
            if let etat = alfred.annexes?.etatDepot {
                Text(etat).font(.caption).foregroundStyle(Color(.sarcelle))
                    .accessibilityAddTraits(.updatesFrequently)
            } else if let erreur = alfred.annexes?.erreurDepot {
                // dans la fenêtre même : l'avis de la console resterait caché dessous
                Text(erreur)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 210 / 255, blue: 201 / 255))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("erreurDepot")
            }
        }
    }

    /// « À envoyer » : une ligne par fichier choisi, « <nom> · <taille> », son refus immédiat s'il y en a un, et sa
    /// croix (« Retirer <nom> de la liste », un toucher : rien n'était parti).
    @ViewBuilder private var aEnvoyer: some View {
        let lignes = alfred.annexes?.aEnvoyer ?? []
        Intertitre(texte: "À envoyer")
        if lignes.isEmpty {
            Text("Aucun document à envoyer.").font(.caption).foregroundStyle(Color(.texteSecondaire))
        } else {
            VStack(spacing: 6) {
                ForEach(lignes) { LigneAEnvoyer(fichier: $0) }
            }
            .masqueInvites(alfred.modeInvites)
        }
    }

    /// « Envoyer à Paperless (n) » : les fichiers valables, avec les étiquettes et le jour ; désactivé sans fichier
    /// valable ou pendant un envoi. Ensuite « À envoyer » et les étiquettes sont vidées (« Pour le » reste).
    private var boutonEnvoyer: some View {
        let annexes = alfred.annexes
        let n = annexes?.aEnvoyer.filter(\.valable).count ?? 0
        return Button("Envoyer à Paperless (\(n))") {
            let choisies = etiquettes
            let pourLe = avecJour ? Depot.format("yyyy-MM-dd", jour) : nil
            Task {
                await annexes?.envoyer(etiquettes: choisies.map(\.valeur), pourLe: pourLe)
                // vidées, sauf si on les a déjà changées pour le lot suivant pendant l'envoi
                if etiquettes == choisies { etiquettes = [] }
            }
        }
        .buttonStyle(StyleConsole(genre: .principal, hauteur: 44))
        .largeurDuTexte()
        .disabled(n == 0 || annexes?.envoiEnCours != false)
        .accessibilityIdentifier("envoyerPaperless")
    }

    /// « 1 document rangé dans Paperless — voir » (60 s, ou jusqu'au prochain ajout) : « voir » ouvre sa fiche, ou la
    /// liste de Paperless pour plusieurs.
    @ViewBuilder private var confirmation: some View {
        if let c = alfred.annexes?.confirmation {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(c.texte)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.sarcelle))
                    .fixedSize(horizontal: false, vertical: true)
                if let lien = c.lien {
                    Text("—").font(.caption).foregroundStyle(Color(.texteSecondaire)).accessibilityHidden(true)
                    Link(destination: lien) {
                        Text("voir").font(.caption.weight(.semibold)).underline().frame(minHeight: 44)
                    }
                    .accessibilityLabel("Voir dans Paperless")
                    .accessibilityHint("S’ouvre dans Safari")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("confirmationRangement")
        }
    }

    /// « En cours » : les fichiers du lot (« <nom> — Envoi… », puis « — Rangement… »), les autres cartes du relais en
    /// lecture ou en rangement, et les documents de banc (comme avant : « Supprimer »).
    @ViewBuilder private var enCours: some View {
        let annexes = alfred.annexes
        let suivi = annexes?.suivi ?? SuiviLot()
        let suivis = suivi.documentsSuivis
        let cartes = (annexes?.documents ?? []).filter {
            [.lecture, .rangement].contains($0.statut) && !suivis.contains($0.id)
        }
        let banc = (annexes?.documents ?? []).filter { $0.statut == .banc }
        let lignes = suivi.lignes + cartes.map { $0.nom + " — Rangement…" }
        if !lignes.isEmpty || !banc.isEmpty {
            Intertitre(texte: "En cours")
            ForEach(Array(lignes.enumerated()), id: \.offset) { _, ligne in
                Text(ligne)
                    .font(.caption)
                    .foregroundStyle(Color(.sodium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ForEach(banc.prefix(30)) { CarteDocument(document: $0) }
        }
    }

    /// « À revoir » : les vrais échecs — refusés par le relais (« Réessayer », « Retirer » en deux temps) et refus au
    /// dépôt (400, 413, 415, envoi coupé, illisible : « Retirer »).
    @ViewBuilder private var aRevoir: some View {
        let annexes = alfred.annexes
        let refus = annexes?.refusLocaux ?? []
        let refuses = (annexes?.documents ?? []).filter { $0.statut == .refuse }
        if !refus.isEmpty || !refuses.isEmpty {
            Intertitre(texte: "À revoir")
            VStack(spacing: 8) {
                ForEach(refus) { CarteRefusLocal(refus: $0) }
                // 30 cartes au plus, comme la console
                ForEach(refuses.prefix(30)) { CarteDocument(document: $0) }
            }
        }
    }
}

/// Un intertitre de la fenêtre Documents (« À envoyer », « En cours », « À revoir »).
private struct Intertitre: View {
    let texte: String

    var body: some View {
        Text(texte)
            .font(.caption.weight(.heavy))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Color(.champagne))
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Une ligne de « À envoyer » : « devis.pdf · 340 ko », son refus immédiat (« Refusé : trop lourd… »), sa croix.
private struct LigneAEnvoyer: View {
    @Environment(Alfred.self) private var alfred
    let fichier: FichierAEnvoyer

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fichier.ligne)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.glace))
                    .fixedSize(horizontal: false, vertical: true)
                if let refus = fichier.texteRefus {
                    Text(refus)
                        .font(.caption)
                        .foregroundStyle(CarteDocument.roseRefus)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                alfred.annexes?.retirerAEnvoyer(fichier.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.texteSecondaire))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer \(fichier.nom) de la liste")
        }
        .padding(.leading, 10)
        .background(Color(red: 12 / 255, green: 27 / 255, blue: 40 / 255), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(
                fichier.valable ? Color(.trait) : CarteDocument.rouge, lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Un document déposé (`.doc`) : son nom, sa date (et le jour qu'il concerne), son verdict (23.10 : lecture,
/// rangement, rangé, envoyé, refusé), son résumé ; la bordure est sodium pendant la lecture et le rangement, rouge pour
/// un refus. Boutons : « ouvrir dans Paperless » (si la maison donne le lien), « Réessayer » et « Retirer » (en deux
/// temps) sur un refus, « Supprimer » en deux temps sur un document que Paperless n'a pas (banc) ; plus de « Supprimer »
/// sur un document rangé (23.10, soir : il quitte le panneau aussitôt, sa fiche reste à la maison).
private struct CarteDocument: View {
    @Environment(Alfred.self) private var alfred
    @Environment(\.openURL) private var ouvrir
    let document: DocumentMaison
    @State private var occupe = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.nom)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(.glace))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meta).font(.caption2).foregroundStyle(Color(.texteSecondaire))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let arme = alfred.annexes?.deuxTemps.estArme("supprimer", id: document.id) == true
                if document.peutSupprimer {
                    // le cadre et la cible DANS le libellé : hors du bouton, seule la surface du texte se touchait
                    Button {
                        enDeuxTemps("supprimer") { await alfred.annexes?.supprimer(document) }
                    } label: {
                        Self.etiquette(arme ? "Confirmer" : "Supprimer", rouge: arme)
                    }
                    .buttonStyle(.plain)
                    .disabled(occupe)
                    .accessibilityLabel(
                        arme ? "Confirmer : supprimer \(document.nom)" : "Supprimer \(document.nom)")
                }
            }
            if let etat = document.texteEtat {
                Text(etat)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(couleurEtat)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("etatDocument")
            }
            // le résumé du relais tient en trois lignes (sa consigne) : jamais coupé, à toutes les tailles de texte
            if let resume = document.resumeAffiche {
                Text(resume)
                    .font(.caption)
                    .foregroundStyle(Color(red: 201 / 255, green: 216 / 255, blue: 228 / 255))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if document.alerte != nil {
                Text("Passage suspect : il s’adresse à un assistant. Alfred et Hermes ne le suivront pas.")
                    .font(.caption)
                    .foregroundStyle(Color(red: 1, green: 210 / 255, blue: 201 / 255))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Self.rouge).frame(width: 3) }
            }
            actions
        }
        .padding(.leading, 12)
        .padding([.vertical, .trailing], 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 12 / 255, green: 27 / 255, blue: 40 / 255), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(bordure, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    /// Le lien vers Paperless, « déjà archivé », « Réessayer », « Retirer ».
    @ViewBuilder private var actions: some View {
        let lien = document.lien
        if lien != nil || document.dejaArchive || document.peutReessayer || document.peutRetirer {
            HStack(spacing: 8) {
                if let lien {
                    Button {
                        ouvrir(lien)
                    } label: {
                        Self.etiquette("ouvrir dans Paperless")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ouvrir \(document.nom) dans Paperless")
                    .accessibilityHint("S’ouvre dans Safari")
                } else if document.dejaArchive {
                    Text("déjà archivé").font(.caption).foregroundStyle(Color(.texteSecondaire))
                }
                if document.peutReessayer {
                    Button {
                        agir { await alfred.annexes?.reessayer(document) }
                    } label: {
                        Self.etiquette("Réessayer")
                    }
                    .buttonStyle(.plain)
                    .disabled(occupe)
                    .accessibilityLabel("Réessayer \(document.nom)")
                }
                if document.peutRetirer {
                    let arme = alfred.annexes?.deuxTemps.estArme("retirer", id: document.id) == true
                    Button {
                        enDeuxTemps("retirer") { await alfred.annexes?.retirer(document) }
                    } label: {
                        Self.etiquette(arme ? "Confirmer" : "Retirer", rouge: arme)
                    }
                    .buttonStyle(.plain)
                    .disabled(occupe)
                    .accessibilityLabel(
                        arme ? "Confirmer : retirer \(document.nom)" : "Retirer \(document.nom)"
                    )
                    .accessibilityHint("Le document refusé quitte la maison")
                }
            }
        }
    }

    static let rouge = Color(red: 216 / 255, green: 106 / 255, blue: 90 / 255)
    static let roseRefus = Color(red: 1, green: 210 / 255, blue: 201 / 255)

    /// Un petit bouton de carte (`.doc-del`) : 30 pt de haut, sa cible de 44 pt au moins.
    static func etiquette(_ texte: String, rouge: Bool = false) -> some View {
        Text(texte)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(rouge ? roseRefus : Color(.glace))
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(Console.bouton, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(rouge ? Self.rouge : Color(.acier), lineWidth: 1.5))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }

    private var bordure: Color {
        switch document.statut {
        case .lecture, .rangement: Color(.sodium)
        case .refuse: Self.rouge
        case .range, .envoye, .banc, .lu, .doublon: Color(.trait)
        }
    }

    private var couleurEtat: Color {
        switch document.statut {
        case .refuse: Self.roseRefus
        case .lecture, .rangement: Color(.sodium)
        case .range, .envoye, .banc, .lu, .doublon: Color(.sarcelle)
        }
    }

    /// « dim. 18 oct. · pour ven. 31 oct. » (la console : `docDate`).
    private var meta: String {
        var parties: [String] = []
        if let d = document.deposeLe.flatMap(DateDocument.lire) { parties.append(DateDocument.texte(d)) }
        var texte = parties.joined()
        if let p = document.pourLe.flatMap(DateDocument.lire) { texte += " · pour " + DateDocument.texte(p) }
        return texte + document.texteEtiquettes
    }

    private func agir(_ action: @escaping @MainActor () async -> Void) {
        occupe = true
        Task {
            await action()
            occupe = false
        }
    }

    /// La console : un premier toucher arme (« Confirmer », 3,5 s), le second agit (supprimer, et retirer depuis le
    /// 23.10). L'état armé vit dans les annexes (`DeuxTemps`), pas dans la carte : il survit aux relectures de la liste.
    private func enDeuxTemps(_ action: String, _ faire: @escaping @MainActor () async -> Void) {
        guard alfred.annexes?.toucherEnDeuxTemps(action, document) == true else { return }
        agir(faire)
    }
}

/// 23.10 (« on doit pouvoir mettre un tag quand on upload ») : les étiquettes du prochain dépôt, comme la console —
/// les puces choisies (chacune retirable), le champ « Ajouter une étiquette… » et ses propositions (premières lettres
/// du nom ou d'un de ses mots, sans casse ni accents, 8 au plus, puis « Nouvelle étiquette : <nom> » ; le champ touché
/// sans rien taper : les 8 premières) ; 10 au plus.
private struct ChampEtiquettes: View {
    @Environment(Alfred.self) private var alfred
    @Binding var choisies: [ChoixEtiquette]
    @State private var saisie = ""
    /// Le champ touché : la liste s'ouvre, saisie vide comprise (les 8 premières), comme la console.
    @FocusState private var focus: Bool

    var body: some View {
        let liste = alfred.annexes?.etiquettes
        let propositions = Etiquettes.propositions(saisie, liste: liste?.etiquettes ?? [], choisies: choisies)
        VStack(alignment: .leading, spacing: 6) {
            Text("Étiquettes").font(.caption).foregroundStyle(Color(.texteSecondaire))
            if !choisies.isEmpty {
                FluxPastilles(espacement: 6, interligne: 6) {
                    ForEach(choisies) { c in
                        Puce(nom: c.nom) { choisies.removeAll { $0 == c } }
                    }
                }
            }
            if choisies.count < Etiquettes.max {
                TextField("Ajouter une étiquette…", text: $saisie)
                    .focused($focus)
                    // comme « Écrire à Alfred… » (audit d'accessibilité d'Apple, 23.10 : en .caption sans marge verticale,
                    // le texte du champ risquait d'être coupé aux grandes tailles de caractères)
                    .font(.callout)
                    .foregroundStyle(Color(.texte))
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        if let c = Etiquettes.choixDirect(saisie, liste: liste?.etiquettes ?? [], choisies: choisies) {
                            ajouter(c)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color(red: 14 / 255, green: 34 / 255, blue: 51 / 255), in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.trait), lineWidth: 1.5))
                    .accessibilityLabel("Ajouter une étiquette")
                    .accessibilityIdentifier("etiquette")
                if (focus || !saisie.isEmpty) && !propositions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(propositions) { p in
                            Button {
                                ajouter(p.choix)
                            } label: {
                                Text(p.texte)
                                    .font(.caption)
                                    .foregroundStyle(Color(.glace))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color(red: 12 / 255, green: 27 / 255, blue: 40 / 255), in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.acier), lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Propositions d’étiquettes")
                }
            }
            if liste?.disponible == false {
                Text("Liste des étiquettes indisponible : un nom nouveau sera vérifié au rangement.")
                    .font(.caption)
                    .foregroundStyle(Color(.texteSecondaire))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ajouter(_ c: ChoixEtiquette) {
        if choisies.count < Etiquettes.max, !choisies.contains(where: { $0.id == c.id }) { choisies.append(c) }
        saisie = ""
    }

    /// Une étiquette choisie : son nom et sa croix (« Retirer l'étiquette <nom> »).
    private struct Puce: View {
        let nom: String
        let retirer: () -> Void

        var body: some View {
            HStack(spacing: 2) {
                Text(nom).font(.caption.weight(.semibold)).foregroundStyle(Color(.glace))
                Button(action: retirer) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(.texteSecondaire))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retirer l’étiquette \(nom)")
            }
            .padding(.leading, 10)
            .background(Console.bouton, in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.acier), lineWidth: 1))
        }
    }
}

/// 23.10 : un fichier refusé par l'appareil ou au dépôt (trop lourd, type) : son nom, « Refusé : … », « Retirer ».
private struct CarteRefusLocal: View {
    @Environment(Alfred.self) private var alfred
    let refus: RefusLocal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(refus.nom)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(.glace))
                .fixedSize(horizontal: false, vertical: true)
            Text(refus.texte)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CarteDocument.roseRefus)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                alfred.annexes?.retirer(refus)
            } label: {
                CarteDocument.etiquette("Retirer")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer \(refus.nom)")
        }
        .padding(.leading, 12)
        .padding([.vertical, .trailing], 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 12 / 255, green: 27 / 255, blue: 40 / 255), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CarteDocument.rouge, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }
}

/// Les dates d'un document comme la console les écrit (« dim. 18 oct. »).
enum DateDocument {
    static func lire(_ iso: String) -> Date? {
        if iso.count == 10 {
            // un jour seul : à midi, pour ne jamais changer de jour avec le fuseau
            let p = iso.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
        }
        return try? Date(iso, strategy: .iso8601)
    }

    static func texte(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_CH")))
    }
}

// MARK: - notifications

/// Les notifications de l'espace MOI (28.10 : avant, une fenêtre) : la copie de celles des téléphones et les réponses
/// d'Hermes annoncées, les nouvelles bordées du faisceau ; tout est marqué lu à l'arrivée dans MOI ; « Tout effacer ».
struct NotificationsMoi: View {
    @Environment(Alfred.self) private var alfred

    var body: some View {
        BlocPage(titre: "Notifications", largeurMax: 560) {
            let liste = alfred.annexes?.notifications ?? []
            VStack(alignment: .leading, spacing: 14) {
                if liste.isEmpty {
                    Text("Aucune notification.").font(.subheadline).foregroundStyle(Color(.texteSecondaire))
                } else {
                    VStack(spacing: 8) {
                        ForEach(liste.prefix(50)) { CarteNotification(notification: $0) }
                    }
                    .masqueInvites(alfred.modeInvites)
                    Button("Tout effacer") { Task { await alfred.annexes?.effacerNotifications() } }
                        .buttonStyle(StyleConsole())
                        .largeurDuTexte()
                        .accessibilityIdentifier("effacerNotifications")
                }
            }
        }
        .task {
            // comme la console : marquées lues seulement si MOI est encore à l'écran une fois la liste chargée
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await alfred.annexes?.marquerLues()
        }
    }
}

private struct CarteNotification: View {
    let notification: NotificationConsole

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(notification.titre.flatMap { $0.isEmpty ? nil : $0 } ?? "Notification")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.glace))
                Spacer(minLength: 0)
                Text(Quand.texte(notification.date)).font(.caption).foregroundStyle(Color(.texteSecondaire))
            }
            Text(notification.message)
                .font(.subheadline)
                .foregroundStyle(Color(.texte))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 14 / 255, green: 34 / 255, blue: 51 / 255), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(
                notification.lu ? Color(.trait) : Color(.faisceau), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(notification.lu ? "" : "nouvelle")
    }
}

// MARK: - mode invités

extension View {
    /// Le mode invités de la console : flou de 7 pt, ni sélection ni toucher, et rien pour VoiceOver. Hors du mode
    /// invités, la vue reste telle quelle (aucun filtre posé).
    func masqueInvites(_ actif: Bool) -> some View { modifier(MasqueInvites(actif: actif)) }
}

private struct MasqueInvites: ViewModifier {
    let actif: Bool

    func body(content: Content) -> some View {
        if actif {
            content.blur(radius: 7).allowsHitTesting(false).accessibilityHidden(true)
        } else {
            content
        }
    }
}
