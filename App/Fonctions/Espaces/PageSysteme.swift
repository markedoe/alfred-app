import AlfredKit
import SwiftUI

/// L'espace SYSTÈME (28.10, retour d'essai : « une page avec tous les connecteurs d'Alfred, un peu style Grok », puis
/// « oui 4 espaces, oui pour les pastilles ») : les connecteurs (une carte chacun, son état en mots, sa fiche), les
/// réglages et les autres systèmes. Comme la console : les textes viennent du relais (`GET /connecteurs`), communs aux
/// deux ; aucune action ici, seulement lire, ouvrir le système (selon le compte) et voir l'historique.
struct PageSysteme: View {
    @Environment(Alfred.self) private var alfred
    let large: Bool
    @State private var fiche: Connecteur?
    /// La largeur des blocs (la grille en tire son nombre de colonnes).
    @State private var largeur: CGFloat = 0

    var body: some View {
        PageConsole(
            titre: "Connecteurs",
            phrase:
                "Tout ce à quoi Alfred est relié, son état en ce moment et ce qu’il en fait. Tout reste à la maison, sauf Claude.",
            large: large, identifiant: "page-systeme"
        ) {
            Button("Revérifier") { alfred.annexes?.relireConnecteurs() }
                .buttonStyle(StyleConsole())
                .largeurDuTexte()
                .disabled(alfred.annexes?.lectureConnecteurs == true)
                .accessibilityIdentifier("reverifier")
        } contenu: {
            VStack(alignment: .leading, spacing: 0) {
                if let texte = alfred.annexes?.connecteurs?.veille {
                    Bandeau(texte: texte, alerte: false)
                }
                if let texte = alfred.annexes?.erreurConnecteurs {
                    Bandeau(texte: texte, alerte: true)
                }
                if let liste = alfred.annexes?.connecteurs {
                    GrilleConnecteurs(liste: liste, largeur: largeur, fiche: $fiche)
                } else if alfred.annexes?.erreurConnecteurs == nil {
                    ProgressView()
                        .tint(Color(.faisceau))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityLabel("Lecture des connecteurs")
                }
                ReglagesSysteme()
                    .padding(.top, 36)
                if let liens = alfred.annexes?.liens, !liens.isEmpty {
                    AutresSystemes(liens: liens)
                        .padding(.top, 36)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                largeur = $0
            }
        }
        .onAppear { alfred.annexes?.suivreConnecteurs(true) }
        .onDisappear { alfred.annexes?.suivreConnecteurs(false) }
        .fullScreenCover(item: $fiche) { c in
            FicheConnecteur(connecteur: c, historique: alfred.annexes?.connecteurs?.historique) { fermerFiche() }
                .presentationBackground(.clear)
                .environment(alfred)
        }
    }

    /// La fiche se ferme d'un coup, comme une fenêtre de la console.
    private func fermerFiche() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { fiche = nil }
    }
}

/// Le bandeau « PC éteint » (sodium) ou d'erreur (rouge) : `.page-bandeau`.
private struct Bandeau: View {
    let texte: String
    let alerte: Bool

    var body: some View {
        Text(texte)
            .font(.subheadline)
            .foregroundStyle(
                alerte
                    ? Color(red: 1, green: 209 / 255, blue: 214 / 255)
                    : Color(red: 1, green: 226 / 255, blue: 189 / 255)
            )
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 1240, alignment: .leading)
            .background(
                (alerte
                    ? Color(red: 42 / 255, green: 20 / 255, blue: 24 / 255)
                    : Color(red: 42 / 255, green: 32 / 255, blue: 20 / 255))
                    .opacity(0.8),
                in: .rect(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    alerte
                        ? Color(red: 138 / 255, green: 58 / 255, blue: 68 / 255)
                        : Color(red: 138 / 255, green: 106 / 255, blue: 60 / 255),
                    lineWidth: 1.5)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                    .fill(alerte ? Color(.alerte) : Color(.sodium))
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 18)
            .accessibilityAddTraits(alerte ? [] : .updatesFrequently)
            .accessibilityIdentifier(alerte ? "connecteursErreur" : "connecteursVeille")
    }
}

// MARK: - la grille

/// Les groupes et leurs cartes, comme la grille de la console (`repeat(auto-fill, minmax(212px, 1fr))`, 14 pt) : autant
/// de colonnes de 212 pt au moins que la largeur en tient, les cartes d'une ligne à la même hauteur ; sous 600 pt, une
/// carte par ligne, le logo à gauche (comme une liste d'iOS).
private struct GrilleConnecteurs: View {
    let liste: ListeConnecteurs
    let largeur: CGFloat
    @Binding var fiche: Connecteur?

    private var compact: Bool { largeur < 600 }
    private var colonnes: Int { max(1, Int((min(largeur, 1240) + 14) / (212 + 14))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(liste.groupes) { g in
                VStack(alignment: .leading, spacing: 14) {
                    Text(g.nom).titreSection()
                    if compact {
                        VStack(spacing: 10) {
                            ForEach(g.connecteurs) { c in
                                CarteConnecteur(connecteur: c, compact: true) { fiche = c }
                            }
                        }
                    } else {
                        let n = colonnes
                        let largeurCarte = (min(largeur, 1240) - CGFloat(n - 1) * 14) / CGFloat(n)
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(stride(from: 0, to: g.connecteurs.count, by: n)), id: \.self) { debut in
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(g.connecteurs[debut..<min(debut + n, g.connecteurs.count)]) { c in
                                        CarteConnecteur(connecteur: c, compact: false) { fiche = c }
                                            .frame(width: max(0, largeurCarte))
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                                // les cartes d'une ligne à la hauteur de la plus haute
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 1240, alignment: .leading)
    }
}

// MARK: - une carte

/// La couleur d'un état (`.cx-etat`) : sarcelle en service, sodium en veille ou en attente, rouge en panne,
/// champagne « à la demande », acier sinon.
@MainActor
func couleurEtat(_ s: Connecteur.Statut) -> Color {
    switch s {
    case .ok: Color(.sarcelle)
    case .eteint, .attente: Color(.sodium)
    case .panne: Color(.alerte)
    case .demande: Color(.champagne)
    case .inconnu: Color(.texteSecondaire)
    }
}

/// La barre en haut à gauche d'une carte (`.cx::before`) : faisceau, sodium, rouge, acier.
@MainActor
private func couleurBarre(_ s: Connecteur.Statut) -> Color {
    switch s {
    case .ok: Color(.faisceau)
    case .eteint, .attente: Color(.sodium)
    case .panne: Color(.alerte)
    case .demande, .inconnu: Color(.acier)
    }
}

/// L'état en mots, en capitales à chasse fixe, avec son point (`.cx-etat`) ; « depuis 14:05 » hors service.
struct EtatConnecteur: View {
    let statut: Connecteur.Statut
    let mot: String
    let depuis: Date?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statut == .inconnu ? Color(.acier) : couleurEtat(statut))
                .frame(width: 8, height: 8)
                .shadow(color: statut == .ok || statut == .panne ? couleurEtat(statut) : .clear, radius: 4)
            Text(texte)
                .font(.caption.weight(.semibold).monospaced())
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(couleurEtat(statut))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texte)
    }

    private var texte: String {
        guard let d = depuis, statut != .ok, statut != .demande else { return mot }
        return mot + " · depuis " + Quand.texte(d)
    }
}

/// « À la maison » / « Internet » et ce qu'Alfred en fait (`.cx-tags`) : des capsules à chasse fixe ; Internet en
/// sodium.
private struct EtiquettesConnecteur: View {
    let connecteur: Connecteur
    let alignement: HorizontalAlignment

    var body: some View {
        HStack(spacing: 6) {
            capsule(connecteur.lieuMot, nuage: connecteur.nuage)
            capsule(connecteur.modeMot, nuage: false)
        }
        .frame(maxWidth: .infinity, alignment: alignement == .center ? .center : .leading)
    }

    private func capsule(_ t: String, nuage: Bool) -> some View {
        Text(t)
            .font(.caption2.weight(.semibold).monospaced())
            .tracking(1)
            .textCase(.uppercase)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .foregroundStyle(nuage ? Color(.sodium) : Color(.texteSecondaire))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay(
                Capsule().strokeBorder(
                    nuage ? Color(red: 138 / 255, green: 106 / 255, blue: 60 / 255) : Color(.trait), lineWidth: 1))
    }
}

/// Le logo d'un connecteur dans son cercle (`.cx-icone-cadre`) : faisceau, sodium en veille, rouge en panne.
struct LogoConnecteur: View {
    let icone: Connecteur.Icone
    let statut: Connecteur.Statut
    var cadre: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [teinte.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: cadre * 0.5)
                )
            Circle().strokeBorder(bord, lineWidth: 1.5)
            TraceConnecteur(icone: icone)
                .foregroundStyle(teinte)
                .frame(width: cadre / 2, height: cadre / 2)
        }
        .frame(width: cadre, height: cadre)
        .accessibilityHidden(true)
    }

    private var teinte: Color {
        switch statut {
        case .eteint, .attente: Color(.sodium)
        case .panne: Color(.alerte)
        default: Color(.faisceau)
        }
    }

    private var bord: Color {
        switch statut {
        case .eteint, .attente: Color(red: 138 / 255, green: 106 / 255, blue: 60 / 255)
        case .panne: Color(red: 138 / 255, green: 58 / 255, blue: 68 / 255)
        default: Color(.faisceauSombre)
        }
    }
}

/// Le tracé d'un logo (24 × 24) : plein pour une marque, au trait (1,6) pour un pictogramme d'Alfred.
private struct TraceConnecteur: View {
    let icone: Connecteur.Icone

    var body: some View {
        if let trace = icone.trace {
            GeometryReader { g in
                let forme = FormeTrace(trace: trace)
                if icone.forme == .marque {
                    forme.fill()
                } else {
                    forme.stroke(
                        style: StrokeStyle(
                            lineWidth: 1.6 * min(g.size.width, g.size.height) / 24, lineCap: .round, lineJoin: .round))
                }
            }
        } else {
            Image(systemName: "puzzlepiece.extension")
                .resizable()
                .scaledToFit()
        }
    }
}

/// Un tracé SVG (lu par AlfredKit, en coordonnées 24 × 24) posé dans le cadre.
struct FormeTrace: Shape {
    let trace: TraceSVG

    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        let o = CGPoint(x: r.midX - 12 * k, y: r.midY - 12 * k)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }
        var c = Path()
        for s in trace.segments {
            switch s {
            case .deplacer(let x, let y): c.move(to: p(x, y))
            case .ligne(let x, let y): c.addLine(to: p(x, y))
            case .courbe(let x1, let y1, let x2, let y2, let x, let y):
                c.addCurve(to: p(x, y), control1: p(x1, y1), control2: p(x2, y2))
            case .fermer: c.closeSubpath()
            }
        }
        return c
    }
}

/// Une carte (`.cx`) : le logo, le nom, une ligne, l'état en mots, « à la maison » ou « Internet », ce qu'Alfred en
/// fait, « Détails » et « Ouvrir » (selon le compte). Toute la carte ouvre sa fiche.
private struct CarteConnecteur: View {
    let connecteur: Connecteur
    let compact: Bool
    let details: () -> Void
    @Environment(\.openURL) private var ouvrir

    var body: some View {
        Group {
            if compact {
                HStack(alignment: .top, spacing: 14) {
                    LogoConnecteur(icone: connecteur.icone, statut: connecteur.etat.statut, cadre: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        // le nom, la phrase, l'état et les étiquettes : un seul élément pour VoiceOver (lu d'un trait)
                        VStack(alignment: .leading, spacing: 6) {
                            nom
                            phrase(.leading)
                            EtatConnecteur(
                                statut: connecteur.etat.statut, mot: connecteur.etat.mot,
                                depuis: connecteur.etat.dateDepuis)
                            EtiquettesConnecteur(connecteur: connecteur, alignement: .leading)
                        }
                        .accessibilityElement(children: .combine)
                        actions.padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 14)
            } else {
                VStack(spacing: 9) {
                    LogoConnecteur(icone: connecteur.icone, statut: connecteur.etat.statut)
                    // le nom, la phrase, l'état et les étiquettes : un seul élément pour VoiceOver (lu d'un trait)
                    VStack(spacing: 9) {
                        nom.padding(.top, 2)
                        phrase(.center)
                        Spacer(minLength: 0)
                        EtatConnecteur(
                            statut: connecteur.etat.statut, mot: connecteur.etat.mot,
                            depuis: connecteur.etat.dateDepuis)
                        EtiquettesConnecteur(connecteur: connecteur, alignement: .center)
                    }
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                    actions.padding(.top, 4)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 18 / 255, green: 35 / 255, blue: 50 / 255).opacity(0.94),
                    Color(red: 11 / 255, green: 22 / 255, blue: 34 / 255).opacity(0.96),
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(
                connecteur.etat.statut == .panne
                    ? Color(red: 138 / 255, green: 58 / 255, blue: 68 / 255) : Color(.trait),
                lineWidth: 1.5)
        )
        .overlay(alignment: .topLeading) {
            Rectangle().fill(couleurBarre(connecteur.etat.statut))
                .frame(width: 44, height: 3)
                .offset(x: 18, y: -1)
                .accessibilityHidden(true)
        }
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture(perform: details)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connecteur-\(connecteur.id)")
    }

    private var nom: some View {
        Text(connecteur.nom)
            .font(.headline.weight(.bold))
            .foregroundStyle(Color(.glace))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func phrase(_ a: TextAlignment) -> some View {
        Text(connecteur.phrase)
            .font(.footnote)
            .foregroundStyle(Color(.texteSecondaire))
            .lineSpacing(2)
            .multilineTextAlignment(a)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Détails", action: details)
                .buttonStyle(StyleConsole(hauteur: 44))
                .largeurDuTexte()
                .accessibilityLabel("Détails : \(connecteur.nom)")
                .accessibilityIdentifier("details-\(connecteur.id)")
            if let lien = connecteur.lien {
                Button {
                    ouvrir(lien)
                } label: {
                    HStack(spacing: 6) {
                        Text("Ouvrir")
                        Text("↗").foregroundStyle(Color(.faisceau)).accessibilityHidden(true)
                    }
                }
                .buttonStyle(StyleConsole(hauteur: 44))
                .largeurDuTexte()
                .accessibilityLabel("Ouvrir \(connecteur.nom)")
                .accessibilityHint("S’ouvre dans Safari")
                .accessibilityIdentifier("ouvrir-\(connecteur.id)")
            }
        }
    }
}

// MARK: - la fiche

/// La fiche d'un connecteur (`#fiche`) : le logo, le nom et l'état ; sa phrase ; les services surveillés par Uptime
/// Kuma ; ce qu'Alfred en fait, ce qu'il ne fait jamais, où vont les données, qui y a accès, à essayer ; « Ouvrir » et
/// « Historique (Uptime Kuma) » selon le compte. Une fenêtre de la console : le voile, la croix, Échap.
struct FicheConnecteur: View {
    let connecteur: Connecteur
    let historique: URL?
    let fermer: () -> Void
    @Environment(\.openURL) private var ouvrir
    @AccessibilityFocusState private var focusNom: Bool

    var body: some View {
        ZStack {
            Color(red: 2 / 255, green: 8 / 255, blue: 13 / 255).opacity(0.8)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .onTapGesture(perform: fermer)
            // 29.10 (retour d’essai sur iPhone : « plus grand que l'écran, impossible de refermer ») : la tête (et sa
            // croix) reste FIXE, seul le corps défile ; la fiche tient dans la zone sûre (ni sous la barre d'état ni sous
            // l'indicateur d'accueil) et laisse le voile autour, qui ferme d'un toucher comme dans la console.
            VStack(alignment: .leading, spacing: 0) {
                tete
                    .padding([.horizontal, .top], 24)
                    .padding(.bottom, 4)
                ViewThatFits(in: .vertical) {
                    corps
                    ScrollView { corps }
                        .scrollBounceBehavior(.basedOnSize)
                        .accessibilityIdentifier("ficheCorps")
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 16 / 255, green: 30 / 255, blue: 44 / 255))
                    .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.acier), lineWidth: 2))
            .contentShape(.rect(cornerRadius: 14))
            .frame(maxWidth: 560)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ficheCarte")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, fermer)
        .accessibilityIdentifier("fiche")
        .onAppear { focusNom = true }
    }

    /// Tout ce qui suit la tête : défile si la fiche dépasse l'écran.
    private var corps: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(connecteur.phrase)
                .font(.subheadline)
                .foregroundStyle(Color(.texteSecondaire))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            EtiquettesConnecteur(connecteur: connecteur, alignement: .leading)
                .padding(.top, 12)
            if !connecteur.etat.services.isEmpty {
                sousTitre("Surveillé par Uptime Kuma")
                VStack(spacing: 0) {
                    ForEach(connecteur.etat.services) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(s.nom).font(.subheadline).foregroundStyle(Color(.texte))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            EtatConnecteur(statut: s.statut, mot: s.mot, depuis: s.dateDepuis)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color(.trait)).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            bloc("Ce qu’Alfred en fait", connecteur.fiche.fait)
            bloc("Jamais", connecteur.fiche.jamais)
            bloc("Où vont les données", connecteur.fiche.donnees)
            bloc("Qui y a accès", connecteur.fiche.acces)
            if !connecteur.fiche.essayer.isEmpty {
                sousTitre("À essayer")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(connecteur.fiche.essayer, id: \.self) { e in
                        Text("« \(e) »").font(.subheadline).foregroundStyle(Color(.glace))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            liens.padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tete: some View {
        HStack(alignment: .center, spacing: 16) {
            LogoConnecteur(icone: connecteur.icone, statut: connecteur.etat.statut)
            VStack(alignment: .leading, spacing: 6) {
                Text(connecteur.nom)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(.glace))
                    .fixedSize(horizontal: false, vertical: true)
                EtatConnecteur(
                    statut: connecteur.etat.statut, mot: connecteur.etat.mot, depuis: connecteur.etat.dateDepuis)
            }
            // le nom et l'état : un seul élément, un titre ; VoiceOver y arrive à l'ouverture
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focusNom)
            Spacer(minLength: 0)
            Button(action: fermer) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.glace))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.acier), lineWidth: 1.5))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Fermer la fiche")
            .accessibilityIdentifier("fermerFiche")
        }
    }

    private func sousTitre(_ t: String) -> some View {
        Text(t)
            .font(.caption.weight(.heavy))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Color(.champagne))
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func bloc(_ titre: String, _ texte: String) -> some View {
        if !texte.isEmpty {
            sousTitre(titre)
            Text(texte)
                .font(.subheadline)
                .foregroundStyle(Color(.texte))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Côte à côte s'ils tiennent, l'un sous l'autre sinon (iPhone : « Ouvrir Home Assistant » + « Historique (Uptime
    /// Kuma) » ≈ 460 pt pour 318 pt de fiche).
    private var liens: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { boutonsLiens }
            VStack(alignment: .leading, spacing: 8) { boutonsLiens }
        }
    }

    @ViewBuilder
    private var boutonsLiens: some View {
        if let l = connecteur.lien {
            lienSysteme("Ouvrir \(connecteur.nom)", l, identifiant: "ficheOuvrir")
        }
        if let h = historique, !connecteur.etat.services.isEmpty {
            lienSysteme("Historique (Uptime Kuma)", h, identifiant: "ficheHistorique")
        }
    }

    private func lienSysteme(_ titre: String, _ url: URL, identifiant: String) -> some View {
        Button {
            ouvrir(url)
        } label: {
            HStack(spacing: 6) {
                Text(titre)
                Text("↗").foregroundStyle(Color(.faisceau)).accessibilityHidden(true)
            }
        }
        .buttonStyle(StyleConsole(hauteur: 44))
        .largeurDuTexte()
        .accessibilityHint("S’ouvre dans Safari")
        .accessibilityIdentifier(identifiant)
    }
}

// MARK: - autres systèmes

/// Les autres systèmes (`#autres-systemes`), selon le compte : une grille de liens (nom et note), chacun s'ouvre dans
/// Safari.
private struct AutresSystemes: View {
    let liens: [LienSysteme]
    @Environment(\.openURL) private var ouvrir

    var body: some View {
        BlocPage(titre: "Autres systèmes", largeurMax: 1240) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(liens) { l in
                    Button {
                        ouvrir(l.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.nom).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.glace))
                            if let note = l.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(Color(.texteSecondaire))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(Color(red: 12 / 255, green: 22 / 255, blue: 33 / 255), in: .rect(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.trait), lineWidth: 1.5))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("S’ouvre dans Safari")
                }
            }
        }
        .accessibilityIdentifier("autresSystemes")
    }
}
