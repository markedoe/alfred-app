import AlfredKit
import SwiftUI

/// Le panneau « Assistant personnel » de la console : ce qu'Alfred fait, le résumé de la maison, et les échanges.
/// Comme la console, seuls les échanges défilent ; aux tailles de texte d'accessibilité, tout le panneau défile (le
/// titre et le résumé ne sont jamais coupés).
struct PanneauAlfred: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        PanneauVerre(phase: conversation.phaseAffichee) {
            if tailleTexte.isAccessibilitySize {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        entete
                        Echanges()
                    }
                }
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .scrollEdgeEffectHidden(true, for: .all)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    entete
                    ScrollView {
                        Echanges()
                    }
                    .defaultScrollAnchor(.bottom, for: .sizeChanges)
                    .scrollEdgeEffectHidden(true, for: .all)
                    .accessibilityIdentifier("journal")
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: briefing)
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Assistant personnel").titreSection()
                .padding(.bottom, 16)
            if alfred.modeInvites {
                Text("Mode invités : l’historique est masqué.")
                    .font(.caption)
                    .foregroundStyle(Color(.champagne))
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("modeInvites")
            }
            Text(briefing)
                .font(.title.weight(.bold))
                .foregroundStyle(Color(.glace))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
                .contentTransition(.opacity)
                .masqueInvites(alfred.modeInvites)
                .accessibilityIdentifier("briefing")
            Text(alfred.resume)
                .font(.subheadline)
                .foregroundStyle(Color(.texteSecondaire))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
                .masqueInvites(alfred.modeInvites)
                .accessibilityIdentifier("resume")
            Rectangle().fill(Color(.trait)).frame(height: 1).padding(.bottom, 20).accessibilityHidden(true)
            Text("Échanges").titreSection()
                .padding(.bottom, 16)
        }
    }

    /// Comme la console : « À votre service. », l'action en cours, ou une action qui demande votre attention.
    private var briefing: String {
        guard let a = alfred.action, a.visible(a: .now) || a.etat == .echec else { return "À votre service." }
        switch a.etat {
        case .attente:
            let nom = alfred.secteurs.first { $0.id == a.secteur }?.nom ?? ""
            return "\(nom) · \(a.libelle.lowercased())"
        case .confirmee: return "À votre service."
        case .echec: return "Une action demande votre attention."
        }
    }
}

/// Les échanges : VOUS (sarcelle) et ALFRED (champagne), ce qu'il a fait ; le panneau suit la dernière réponse.
private struct Echanges: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation

    var body: some View {
        contenu.masqueInvites(alfred.modeInvites)
    }

    @ViewBuilder private var contenu: some View {
        if conversation.vide {
            Text("Votre conversation apparaîtra ici. Touchez « Parler » ou écrivez à Alfred.")
                .font(.callout)
                .foregroundStyle(Color(.texteSecondaire))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 3)
        } else {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(conversation.messages) { m in
                    MessageConsole(message: m, dernier: m.id == conversation.messages.last?.id)
                        .id(m.id)
                }
            }
            .padding(3)
            .scrollTargetLayout()
        }
    }
}

private struct MessageConsole: View {
    let message: Conversation.Message
    let dernier: Bool

    var body: some View {
        let alfred = message.auteur == .alfred
        VStack(alignment: .leading, spacing: 6) {
            Text(alfred ? "Alfred" : "Vous")
                .etiquette(alfred ? Color(.champagne) : Color(.sarcelle), espacement: 1.1)
            if alfred {
                DetailsTechniques(outils: message.outils)
            }
            if message.texte.isEmpty, message.enCours {
                Text("▌")
                    .font(.callout)
                    .foregroundStyle(Color(.faisceau))
                    .accessibilityLabel("Alfred réfléchit")
            } else {
                Text(message.texte)
                    .font(.callout)
                    .foregroundStyle(message.erreur ? Color(.alerte) : Color(.texte))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .contentTransition(.opacity)
            }
            if alfred, let duree = message.duree, !message.enCours {
                Badges(duree: duree, local: message.comprisLocalement, outils: message.outils.count)
            }
        }
        .padding(.leading, alfred ? 12 : 0)
        .overlay(alignment: .leading) {
            if alfred {
                Rectangle().fill(dernier ? Color(.champagne) : Color(.trait)).frame(width: 3).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// « Détails techniques » (la console : un `<details>` replié) : chaque outil appelé, son nom court, ses arguments et son
/// état (… en cours, ✓ fait, ✕ échec), bordé du faisceau, de la sarcelle ou du rouge. Jamais le contenu d'un résultat.
private struct DetailsTechniques: View {
    let outils: [Conversation.Outil]
    @State private var ouverts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                ouverts.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .imageScale(.small)
                        .rotationEffect(.degrees(ouverts ? 90 : 0))
                    Text("Détails techniques")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.texteSecondaire))
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Détails techniques")
            .accessibilityValue(ouverts ? "ouverts" : "repliés")
            .accessibilityHint(outils.isEmpty ? "Aucun outil" : "\(outils.count) outil\(outils.count > 1 ? "s" : "")")
            if ouverts {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(outils) { LigneOutil(outil: $0) }
                }
            }
        }
    }
}

private struct LigneOutil: View {
    let outil: Conversation.Outil

    var body: some View {
        HStack(spacing: 6) {
            Text(outil.nom).foregroundStyle(Color(.texte))
            Text(outil.arguments)
                .foregroundStyle(Color(.texteSecondaire))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(outil.etat == .enCours ? "…" : outil.etat == .fait ? "✓" : "✕")
                .foregroundStyle(Color(.texte))
        }
        .font(.caption.monospaced())
        .padding(6)
        .background(Color(.faisceau).opacity(0.045))
        .overlay(alignment: .leading) { Rectangle().fill(bord).frame(width: 2) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(outil.nom + (outil.arguments.isEmpty ? "" : ", " + outil.arguments))
        .accessibilityValue(outil.etat == .enCours ? "en cours" : outil.etat == .fait ? "fait" : "échec")
    }

    private var bord: Color {
        switch outil.etat {
        case .enCours: Color(.faisceau)
        case .fait: Color(.sarcelle)
        case .echec: Color(.alerte)
        }
    }
}

/// Les badges sous une réponse (`.meta`) : sa durée, « intent local » ou « llm », le nombre d'outils.
private struct Badges: View {
    let duree: Double
    let local: Bool
    let outils: Int

    var body: some View {
        HStack(spacing: 6) {
            badge(ReglagesSysteme.duree(duree))
            badge(local ? "intent local" : "llm")
            if outils > 0 { badge("\(outils) outil\(outils > 1 ? "s" : "")") }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func badge(_ texte: String) -> some View {
        // le texte (et non la brume de la console) : dans un cadre si petit, l'audit d'Apple compare la brume au trait
        Text(texte)
            .font(.caption2)
            .foregroundStyle(Color(.texte))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.trait), lineWidth: 1))
    }
}

// MARK: - environnement

/// Le panneau « Environnement » de la console : l'extérieur, les pièces mesurées, l'énergie.
struct PanneauEnvironnement: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Environment(\.dynamicTypeSize) private var tailleTexte
    /// La disposition large montre l'état des services sous les jauges, pas ici.
    var large = false
    @ScaledMetric(relativeTo: .subheadline) private var colonneHumidite: CGFloat = 40
    /// 46 pt comme la console, avec la taille du texte, plafonnée (« 14.5°C » tient sur une ligne).
    @ScaledMetric(relativeTo: .largeTitle) private var tailleMesuree: CGFloat = 46
    private var tailleTemperature: CGFloat { min(tailleMesuree, 72) }

    var body: some View {
        PanneauVerre(phase: conversation.phaseAffichee) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Extérieur").titreSection()
                        .padding(.bottom, 16)
                    exterieur
                    Text("Intérieur").titreSection()
                        .padding(.top, 24)
                        .padding(.bottom, 16)
                    interieur
                    if !alfred.console.jauges.isEmpty {
                        Text("Énergie & système").titreSection()
                            .padding(.top, 24)
                            .padding(.bottom, 16)
                        energie
                    }
                    if !large {
                        // sur téléphone et iPad à la verticale, l'état des services est au bas de ce panneau
                        PastillesEtat()
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .scrollEdgeEffectHidden(true, for: .all)
        }
        .accessibilityIdentifier("environnement")
    }

    @ViewBuilder private var exterieur: some View {
        let m = alfred.console.meteo.flatMap { alfred.maison[$0] }
        if let m, m.disponible {
            let a = m.attributs
            Text(Format.valeur(a["temperature"]?.nombre, a["temperature_unit"]?.texte ?? "", 1))
                .font(.system(size: tailleTemperature, weight: .semibold, design: .monospaced))
                .tracking(-2)
                .foregroundStyle(Color(.glace))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Température extérieure")
                .accessibilityValue(Format.valeur(a["temperature"]?.nombre, " degrés", 1))
            Text(Format.meteo(m.etat))
                .font(.callout)
                .foregroundStyle(Color(.texteSecondaire))
                .padding(.top, 3)
                .padding(.bottom, 14)
            VStack(spacing: 0) {
                ligne("humidité", Format.valeur(a["humidity"]?.nombre, " %"))
                ligne("vent", vent(a))
                ligne("pression", Format.valeur(a["pressure"]?.nombre, " " + (a["pressure_unit"]?.texte ?? "")))
                ligne("uv", Format.valeur(a["uv_index"]?.nombre, "", 1))
                ligne("nuages", Format.valeur(a["cloud_coverage"]?.nombre, " %"))
            }
        } else {
            Text("—")
                .font(.system(size: tailleTemperature, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(.glace))
            Text("Météo indisponible")
                .font(.callout)
                .foregroundStyle(Color(.texteSecondaire))
        }
    }

    private func vent(_ a: [String: ValeurJSON]) -> String {
        guard let v = a["wind_speed"]?.nombre else { return "—" }
        let sens = Format.boussole(a["wind_bearing"]?.nombre)
        return Format.valeur(v, " " + (a["wind_speed_unit"]?.texte ?? "")) + (sens.isEmpty ? "" : " " + sens)
    }

    private func ligne(_ cle: String, _ valeur: String) -> some View {
        HStack {
            Text(cle).foregroundStyle(Color(.texteSecondaire))
            Spacer(minLength: 12)
            Text(valeur).fontWeight(.semibold).foregroundStyle(Color(.texte))
        }
        .font(.footnote)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.trait).opacity(0.55)).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Toutes les pièces mesurées, du sous-sol au 2e : nom et étage, température, humidité.
    @ViewBuilder private var interieur: some View {
        let pieces = lignesInterieur
        if pieces.isEmpty {
            Text("Aucune mesure").font(.subheadline).foregroundStyle(Color(.texteSecondaire))
        } else {
            VStack(spacing: 4) {
                ForEach(pieces) { p in
                    // aux tailles d'accessibilité, les valeurs passent sous le nom (qui n'est jamais coupé au milieu)
                    let empile = tailleTexte.isAccessibilitySize
                    let disposition =
                        empile
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 10))
                    disposition {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.nom).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.texte))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(p.etage).font(.caption.weight(.semibold)).foregroundStyle(Color(.texteSecondaire))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 10) {
                            Text(Format.valeur(p.temperature, "°", 1))
                                .font(.subheadline.weight(.semibold).monospaced())
                                .foregroundStyle(Color(.texte))
                            Text(Format.valeur(p.humidite, "%"))
                                .font(.subheadline.weight(.semibold).monospaced())
                                .foregroundStyle(Color(.texteSecondaire))
                                .frame(minWidth: empile ? nil : colonneHumidite, alignment: .trailing)
                        }
                        .fixedSize()
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(p.nom.capitalized)
                    .accessibilityValue(
                        Format.valeur(p.temperature, " degrés", 1)
                            + (p.humidite == nil ? "" : ", humidité " + Format.valeur(p.humidite, " %")))
                }
            }
        }
    }

    private struct LigneInterieur: Identifiable {
        let nom: String
        let etage: String
        let temperature: Double?
        let humidite: Double?
        var id: String { nom + "·" + etage }
    }

    private var lignesInterieur: [LigneInterieur] {
        if !alfred.console.vide {
            return alfred.console.interieur.map { p in
                LigneInterieur(
                    nom: p.nom, etage: p.etage, temperature: p.temperature.flatMap { alfred.maison[$0]?.nombre },
                    humidite: p.humidite.flatMap { alfred.maison[$0]?.nombre })
            }
        }
        return alfred.secteurs.filter { $0.temperature != nil }.map {
            LigneInterieur(
                nom: $0.nom, etage: $0.etage, temperature: $0.temperature?.valeur, humidite: $0.humidite?.valeur)
        }
    }

    private var energie: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(alfred.console.jauges) { j in
                let v = alfred.maison[j.entite]?.nombre
                VStack(alignment: .leading, spacing: 4) {
                    Text(j.description).font(.caption).foregroundStyle(Color(.texteSecondaire))
                    Text(Format.valeur(v, j.unite, j.decimalesPanneau))
                        .font(.headline.monospaced())
                        .foregroundStyle(Color(.texte))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Console.caseMesure, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.trait), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - état des services

/// Les pastilles de l'état des services (`.etat-services`, Uptime Kuma lu par le relais) : un groupe par nom court
/// (MAISON, VOIX, CABINET, NUIT), une pastille par service, vert en service, sodium en attente, rouge en panne, gris
/// éteint (normal) ou pas encore mesuré. Un toucher ouvre l'historique dans Safari, si le relais en donne l'adresse.
struct PastillesEtat: View {
    @Environment(Alfred.self) private var alfred
    /// 28.10 (« oui pour les pastilles ») : un toucher mène à SYSTÈME (les connecteurs) ; l'historique d'Uptime Kuma est
    /// dans la fiche de chaque connecteur.
    @Environment(NavigationConsole.self) private var navigation: NavigationConsole?

    var body: some View {
        if let etat = alfred.annexes?.etat, !etat.groupes.isEmpty {
            let contenu = FluxPastilles(espacement: 14, interligne: 4) {
                ForEach(etat.groupes) { g in
                    HStack(spacing: 4) {
                        NomGroupe(nom: g.nomCourt)
                        ForEach(g.services) { s in
                            Circle()
                                .fill(Self.couleur(s.statut))
                                .opacity(Self.opacite(s.statut))
                                .frame(width: 9, height: 9)
                                .shadow(color: s.statut == "panne" ? Self.rouge : .clear, radius: 3)
                        }
                    }
                    .fixedSize()
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.large)
            if let navigation {
                Button {
                    navigation.aller(.systeme)
                } label: {
                    contenu.frame(minHeight: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("État des services")
                .accessibilityValue(Self.resume(etat))
                .accessibilityHint("Les connecteurs, dans Système")
                .accessibilityIdentifier("etatServices")
            } else {
                // un seul élément pour VoiceOver, de 44 pt de haut (le cadre d'un élément se calcule sur son contenu :
                // des pastilles de 9 pt donneraient une cible de 12 pt)
                contenu
                    .accessibilityHidden(true)
                    .overlay(alignment: .leading) {
                        Color.clear
                            .frame(minHeight: 44)
                            .accessibilityElement()
                            .accessibilityLabel("État des services")
                            .accessibilityValue(Self.resume(etat))
                            .accessibilityIdentifier("etatServices")
                    }
            }
        }
    }

    static let vert = Color(red: 62 / 255, green: 207 / 255, blue: 142 / 255)
    static let rouge = Color(red: 1, green: 84 / 255, blue: 112 / 255)

    static func couleur(_ statut: String) -> Color {
        switch statut {
        case "ok": vert
        case "attente": Color(.sodium)
        case "panne": rouge
        default: Color(.texteSecondaire)
        }
    }

    static func opacite(_ statut: String) -> Double {
        switch statut {
        case "ok", "attente", "panne": 1
        case "eteint", "inconnu": 0.45
        default: 0.55
        }
    }

    /// Pour VoiceOver : les services qui ne sont pas en service, nommés ; sinon « tout est en service ».
    static func resume(_ e: EtatServices) -> String {
        let autres = e.groupes.flatMap(\.services).filter { $0.statut != "ok" }
        guard !autres.isEmpty else { return "tout est en service" }
        return autres.map { "\($0.nom) : \($0.mot)" }.joined(separator: " ; ")
    }
}

/// Le nom d'un groupe de pastilles : 10 pt comme la console, avec la taille du texte plafonnée des pastilles (une vue
/// à part, pour que sa mesure lise la taille d'après le plafond).
private struct NomGroupe: View {
    let nom: String
    @ScaledMetric(relativeTo: .caption2) private var taille: CGFloat = 10

    var body: some View {
        Text(nom)
            .font(.system(size: taille, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color(.texteSecondaire))
            .padding(.trailing, 2)
    }
}

/// Une disposition qui passe à la ligne (les groupes de pastilles, comme le `flex-wrap` de la console).
struct FluxPastilles: Layout {
    var espacement: CGFloat
    var interligne: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lignes = ranger(subviews, largeur: proposal.width ?? .infinity)
        let largeur = lignes.map(\.largeur).max() ?? 0
        let hauteur = lignes.map(\.hauteur).reduce(0, +) + interligne * CGFloat(max(0, lignes.count - 1))
        return CGSize(width: largeur, height: hauteur)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for ligne in ranger(subviews, largeur: bounds.width) {
            var x = bounds.minX
            for i in ligne.indices {
                let t = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (ligne.hauteur - t.height) / 2), proposal: .unspecified)
                x += t.width + espacement
            }
            y += ligne.hauteur + interligne
        }
    }

    private struct Ligne {
        var indices: [Int] = []
        var largeur: CGFloat = 0
        var hauteur: CGFloat = 0
    }

    private func ranger(_ subviews: Subviews, largeur: CGFloat) -> [Ligne] {
        var lignes: [Ligne] = []
        var l = Ligne()
        for (i, v) in subviews.enumerated() {
            let t = v.sizeThatFits(.unspecified)
            let ajout = l.indices.isEmpty ? t.width : l.largeur + espacement + t.width
            if !l.indices.isEmpty, ajout > largeur {
                lignes.append(l)
                l = Ligne()
            }
            l.largeur = l.indices.isEmpty ? t.width : l.largeur + espacement + t.width
            l.hauteur = max(l.hauteur, t.height)
            l.indices.append(i)
        }
        if !l.indices.isEmpty { lignes.append(l) }
        return lignes
    }
}
