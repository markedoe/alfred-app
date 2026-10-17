import AlfredKit
import SwiftUI

/// La maison, étage par étage : une tuile par pièce. Toucher l'ampoule bascule toute la pièce ; toucher la tuile
/// ouvre ses lampes. Ce qui s'affiche est l'état que la maison CONFIRME, jamais un état supposé.
struct MaisonVue: View {
    @Environment(Alfred.self) private var alfred
    @State private var recherche = ""
    @State private var reglages = false
    @Environment(\.dynamicTypeSize) private var tailleTexte

    /// Deux colonnes (ou plus) ; une seule aux tailles de texte d'accessibilité, où deux colonnes coupaient les noms
    /// de pièce et les températures au milieu (« Bu-reau », « 20. / 9° »).
    private var colonnes: [GridItem] {
        tailleTexte.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)] : [GridItem(.adaptive(minimum: 158), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Resume()
                    if alfred.structure.vide {
                        ListeSimple(recherche: recherche)
                    } else {
                        ForEach(etages) { etage in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(etage.etage?.nom ?? String(localized: "Autres pièces"))
                                    .font(.title3.bold())
                                    .fontDesign(.serif)
                                    .accessibilityAddTraits(.isHeader)
                                LazyVGrid(columns: colonnes, spacing: 12) {
                                    ForEach(etage.pieces) { piece in
                                        TuilePiece(piece: piece)
                                    }
                                }
                            }
                        }
                        if etages.isEmpty {
                            ContentUnavailableView.search(text: recherche)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.fond).ignoresSafeArea())
            .overlay(alignment: .top) { EtatLiaison() }
            .navigationTitle("Maison")
            .searchable(text: $recherche, prompt: "Pièce ou lumière")
            .navigationDestination(for: String.self) { id in
                PieceVue(id: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BoutonReglages(ouvert: $reglages)
                }
            }
            .sheet(isPresented: $reglages) { ReglagesVue() }
        }
        .sensoryFeedback(trigger: alfred.dernierRetour) { _, retour in
            switch retour?.issue {
            case .confirmee: .success
            case .refusee, .sansConfirmation: .error
            case nil: nil
            }
        }
    }

    /// Les étages, filtrés par la recherche (nom de pièce ou de lumière).
    private var etages: [VueEtage] {
        let q = recherche.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return alfred.etages }
        return alfred.etages.compactMap { e in
            let pieces = e.pieces.filter { p in
                p.piece.nom.localizedStandardContains(q) || p.lumieres.contains { $0.nom.localizedStandardContains(q) }
            }
            return pieces.isEmpty ? nil : VueEtage(etage: e.etage, pieces: pieces)
        }
    }
}

/// « 3 lumières allumées » et la dernière commande refusée, s'il y en a une.
private struct Resume: View {
    @Environment(Alfred.self) private var alfred

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let n = alfred.lumieresAllumees
            Text(
                n == 0
                    ? "Toutes les lumières sont éteintes." : n == 1 ? "1 lumière allumée." : "\(n) lumières allumées."
            )
            .font(.headline)
            .contentTransition(.numericText())
            .animation(.smooth, value: n)
            if let retour = alfred.dernierRetour, let texte = Self.texte(retour.issue) {
                Label(texte, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Color(.alerte))
                    .id(retour.id)
                    .transition(.opacity)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    static func texte(_ issue: IssueCommande) -> String? {
        switch issue {
        case .confirmee: nil
        case .refusee(let m): m
        case .sansConfirmation: String(localized: "La maison n’a pas confirmé. Vérifiez avant de réessayer.")
        }
    }
}

/// Une pièce : son ampoule (bascule toute la pièce), son nom, ce qui est allumé, sa température.
/// Deux cibles distinctes : l'ampoule (bouton) et le reste de la tuile (lien vers les lampes) ; jamais un bouton
/// dans un bouton.
struct TuilePiece: View {
    @Environment(Alfred.self) private var alfred
    let piece: VuePiece
    /// La place de l'ampoule (même mesure que `BoutonAmpoule`).
    @ScaledMetric(relativeTo: .title3) private var coteAmpoule: CGFloat = 44

    var body: some View {
        ZStack(alignment: .topLeading) {
            NavigationLink(value: piece.id) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Color.clear.frame(width: coteAmpoule, height: coteAmpoule)
                        Spacer()
                        if let t = piece.temperature?.nombre {
                            Text(t.formatted(.number.precision(.fractionLength(1))) + "°")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color(.texteSecondaire))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(piece.piece.nom)
                            .font(.headline)
                            .foregroundStyle(Color(.texte))
                            .lineLimit(2)
                        Text(sousTitre)
                            .font(.subheadline)
                            .foregroundStyle(Color(.texteSecondaire))
                            .contentTransition(.numericText())
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                .background(fond, in: .rect(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(.trait).opacity(0.6), lineWidth: 0.5)
                )
                .contentShape(.rect(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(piece.piece.nom)
            .accessibilityValue(accessibilite)
            .accessibilityHint("Ouvre les lumières de la pièce")

            BoutonAmpoule(
                allumee: piece.allumee, enCours: alfred.enCours("piece:" + piece.id),
                disponible: piece.disponible
            ) {
                alfred.basculer(piece: piece)
            }
            .accessibilityLabel(piece.allumee ? "Éteindre \(piece.piece.nom)" : "Allumer \(piece.piece.nom)")
            .padding(14)
        }
        .animation(.smooth, value: piece.allumee)
    }

    private var sousTitre: String {
        guard piece.disponible else { return String(localized: "Indisponible") }
        let n = piece.nombreAllumees
        return n == 0
            ? String(localized: "Éteinte")
            : n == piece.lumieres.count
                ? String(localized: "Allumée")
                : String(localized: "\(n) sur \(piece.lumieres.count) allumées")
    }

    private var accessibilite: String {
        guard let t = piece.temperature?.nombre else { return sousTitre }
        return sousTitre + ", " + String(localized: "\(t.formatted(.number.precision(.fractionLength(1)))) degrés")
    }

    private var fond: some ShapeStyle {
        piece.allumee ? AnyShapeStyle(Color(.champagne).opacity(0.16)) : AnyShapeStyle(Color(.surface))
    }
}

/// L'ampoule : allumée (champagne), éteinte, en attente de confirmation (rotation douce), indisponible.
struct BoutonAmpoule: View {
    let allumee: Bool
    let enCours: Bool
    let disponible: Bool
    let action: () -> Void
    /// 44 pt à la taille de texte par défaut ; le cercle grandit avec l'icône (sinon elle en déborde en grand texte).
    @ScaledMetric(relativeTo: .title3) private var cote: CGFloat = 44

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(allumee ? Color(.champagne) : Color(.trait).opacity(0.5))
                if enCours {
                    ProgressView().tint(allumee ? Color(.fond) : Color(.texte))
                } else {
                    Image(systemName: allumee ? "lightbulb.fill" : "lightbulb")
                        .font(.title3)
                        .foregroundStyle(allumee ? Color(.fond) : Color(.texteSecondaire))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: cote, height: cote)
        }
        .buttonStyle(.plain)
        .disabled(!disponible || enCours)
        .accessibilityValue(enCours ? "En attente de la maison" : allumee ? "Allumée" : "Éteinte")
    }
}

/// Sans étages ni pièces (relais d'avant `/maison/structure`) : les lumières, par ordre alphabétique.
private struct ListeSimple: View {
    @Environment(Alfred.self) private var alfred
    let recherche: String

    var body: some View {
        let lumieres = alfred.maison.lumieres.filter {
            !$0.estGroupe && (recherche.isEmpty || $0.nom.localizedStandardContains(recherche))
        }
        VStack(spacing: 0) {
            ForEach(lumieres, id: \.id) { l in
                LigneLumiere(lumiere: l)
                    .padding(.vertical, 10)
                Divider()
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.surface), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    MaisonVue()
        .environment(Alfred.demonstration())
}
