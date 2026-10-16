import AlfredKit
import SwiftUI

/// Une pièce : toutes ses lampes, avec la luminosité pour celles qui la règlent.
struct PieceVue: View {
    @Environment(Alfred.self) private var alfred
    let id: String

    private var piece: VuePiece? { alfred.etages.flatMap(\.pieces).first { $0.id == id } }

    var body: some View {
        Group {
            if let piece {
                List {
                    Section {
                        HStack(spacing: 16) {
                            BoutonAmpoule(
                                allumee: piece.allumee, enCours: alfred.enCours("piece:" + piece.id),
                                disponible: piece.disponible
                            ) {
                                alfred.basculer(piece: piece)
                            }
                            .accessibilityLabel(piece.allumee ? "Tout éteindre" : "Tout allumer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(piece.allumee ? "Tout éteindre" : "Tout allumer").font(.headline)
                                if let climat = climat(piece) {
                                    Text(climat).font(.subheadline).foregroundStyle(Color(.texteSecondaire))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section("Lumières") {
                        ForEach(piece.lumieres, id: \.id) { l in
                            LigneLumiere(lumiere: l)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(.fond).ignoresSafeArea())
                .navigationTitle(piece.piece.nom)
            } else {
                ContentUnavailableView("Pièce introuvable", systemImage: "questionmark.square.dashed")
            }
        }
        .overlay(alignment: .top) { EtatLiaison() }
    }

    private func climat(_ p: VuePiece) -> String? {
        let t = p.temperature?.nombre.map { $0.formatted(.number.precision(.fractionLength(1))) + " °C" }
        let h = p.humidite?.nombre.map { $0.formatted(.number.precision(.fractionLength(0))) + " % d’humidité" }
        let parts = [t, h].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Une lampe : son nom, son interrupteur, et sa luminosité (réglée au relâchement du curseur).
struct LigneLumiere: View {
    @Environment(Alfred.self) private var alfred
    let lumiere: EtatEntite
    @State private var luminosite: Double = 0
    @State private var glisse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                BoutonAmpoule(
                    allumee: lumiere.etat == "on", enCours: alfred.enCours(lumiere.id),
                    disponible: lumiere.etat == "on" || lumiere.etat == "off"
                ) {
                    alfred.basculer(lumiere: lumiere)
                }
                .accessibilityLabel(lumiere.etat == "on" ? "Éteindre \(lumiere.nom)" : "Allumer \(lumiere.nom)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(lumiere.nom).font(.body)
                    Text(etat).font(.subheadline).foregroundStyle(Color(.texteSecondaire))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            if lumiere.variable, lumiere.etat == "on" {
                Slider(value: $luminosite, in: 1...100, step: 1) {
                    Text("Luminosité de \(lumiere.nom)")
                } minimumValueLabel: {
                    Image(systemName: "sun.min").accessibilityHidden(true)
                } maximumValueLabel: {
                    Image(systemName: "sun.max.fill").accessibilityHidden(true)
                } onEditingChanged: {
                    glisse = $0
                }
                .onChange(of: glisse) { _, enCours in
                    if !enCours { alfred.regler(lumiere: lumiere, pourcent: Int(luminosite)) }
                }
                .accessibilityValue("\(Int(luminosite)) pour cent")
            }
        }
        .onAppear { luminosite = Double(lumiere.luminosite ?? 100) }
        .onChange(of: lumiere.luminosite) { _, l in
            if !glisse, let l { luminosite = Double(l) }
        }
    }

    private var etat: String {
        switch lumiere.etat {
        case "on": lumiere.luminosite.map { String(localized: "Allumée · \($0) %") } ?? String(localized: "Allumée")
        case "off": String(localized: "Éteinte")
        default: String(localized: "Indisponible")
        }
    }
}
