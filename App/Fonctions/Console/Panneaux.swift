import AlfredKit
import SwiftUI

/// Le panneau « Assistant personnel » de la console : ce qu'Alfred fait, le résumé de la maison, et les échanges.
struct PanneauAlfred: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation

    var body: some View {
        PanneauVerre(phase: conversation.phase) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Assistant personnel").titreSection()
                    .padding(.bottom, 16)
                Text(briefing)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color(.glace))
                    .padding(.bottom, 12)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("briefing")
                Text(alfred.resume)
                    .font(.subheadline)
                    .foregroundStyle(Color(.texteSecondaire))
                    .lineSpacing(4)
                    .padding(.bottom, 20)
                    .accessibilityIdentifier("resume")
                Rectangle().fill(Color(.trait)).frame(height: 1).padding(.bottom, 20).accessibilityHidden(true)
                HStack(spacing: 12) {
                    Text("Échanges").titreSection()
                    if !conversation.vide {
                        Button {
                            Task { await conversation.nouvelle() }
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color(.glace))
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nouvelle conversation")
                        .accessibilityIdentifier("nouvelle")
                    }
                }
                .frame(minHeight: 44)
                .padding(.bottom, 8)
                Journal()
            }
        }
        .animation(.smooth(duration: 0.25), value: briefing)
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

/// Les échanges : VOUS (sarcelle) et ALFRED (champagne), ce qu'il a fait, en suivant la dernière réponse.
private struct Journal: View {
    @Environment(Conversation.self) private var conversation

    var body: some View {
        ScrollView {
            if conversation.vide {
                Text("Votre conversation apparaîtra ici. Touchez « Parler » ou écrivez à Alfred.")
                    .font(.callout)
                    .foregroundStyle(Color(.texteSecondaire))
                    .lineSpacing(5)
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
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollIndicators(.automatic)
        .accessibilityIdentifier("journal")
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
            if !message.outils.isEmpty {
                Outils(outils: message.outils)
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
            if message.comprisLocalement, !message.enCours {
                Text("Compris par la maison, sans le modèle")
                    .font(.caption)
                    .foregroundStyle(Color(.texteSecondaire))
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

/// Ce qu'Alfred a fait, en petites étiquettes mono : en cours, fait, échoué (jamais le contenu d'un résultat).
private struct Outils: View {
    let outils: [Conversation.Outil]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { etiquettes }
            VStack(alignment: .leading, spacing: 6) { etiquettes }
        }
    }

    @ViewBuilder private var etiquettes: some View {
        ForEach(outils) { o in
            HStack(spacing: 6) {
                switch o.etat {
                case .enCours: ProgressView().controlSize(.mini).tint(Color(.sodium))
                case .fait: Image(systemName: "checkmark").foregroundStyle(Color(.sarcelle))
                case .echec: Image(systemName: "xmark").foregroundStyle(Color(.alerte))
                }
                Text(o.libelle)
            }
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(Color(.texte))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Console.caseMesure, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.trait), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                o.libelle + ", " + (o.etat == .enCours ? "en cours" : o.etat == .fait ? "fait" : "échec"))
        }
    }
}

// MARK: - environnement

/// Le panneau « Environnement » de la console : l'extérieur, les pièces mesurées, l'énergie.
struct PanneauEnvironnement: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @ScaledMetric(relativeTo: .largeTitle) private var tailleTemperature: CGFloat = 46

    var body: some View {
        PanneauVerre(phase: conversation.phase) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
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
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 16) {
                ForEach(pieces) { p in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.nom).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.texte))
                            Text(p.etage).font(.caption).foregroundStyle(Color(.texteSecondaire))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.valeur(p.temperature, "°", 1))
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(Color(.texte))
                            .gridColumnAlignment(.trailing)
                        Text(Format.valeur(p.humidite, "%"))
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(Color(.texteSecondaire))
                            .gridColumnAlignment(.trailing)
                    }
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
