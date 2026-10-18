import AlfredKit
import SwiftUI

/// Une fenêtre de la console (`<dialog>` : Réglages & état, Documents, Notifications) : au centre, sur un voile sombre
/// et flou, 560 pt de large au plus (470 pour les réglages), son titre champagne et sa croix. Comme la console, elle ne
/// se ferme que par la croix (ou Échap, ou le geste « retour » de VoiceOver) ; son contenu défile s'il est trop haut.
struct Fenetre<Contenu: View>: View {
    let titre: String
    var largeurMax: CGFloat = 560
    let fermer: () -> Void
    @ViewBuilder let contenu: Contenu
    @AccessibilityFocusState private var focusTitre: Bool

    var body: some View {
        ZStack {
            // le voile (#02080dcc, flou de 4 pt) : il ne ferme rien, comme celui de la console
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(red: 2 / 255, green: 8 / 255, blue: 13 / 255).opacity(0.8))
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .onTapGesture {}
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(titre)
                                .font(.callout.weight(.heavy))
                                .tracking(1.9)
                                .textCase(.uppercase)
                                .foregroundStyle(Color(.champagne))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($focusTitre)
                                .padding(.top, 11)
                            LinearGradient(colors: [Color(.trait), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(height: 2)
                                .padding(.top, 21)
                                .accessibilityHidden(true)
                            Button(action: fermer) {
                                Image(systemName: "xmark")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color(.glace))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.acier), lineWidth: 1.5)
                                    )
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                            .accessibilityLabel("Fermer")
                            .accessibilityIdentifier("fermerFenetre")
                        }
                        .padding(.bottom, 14)
                        contenu
                    }
                    .padding(.leading, 24)
                    .padding([.trailing, .top], 12)
                    .padding(.bottom, 24)
                    .background(
                        Color(red: 16 / 255, green: 30 / 255, blue: 44 / 255), in: .rect(cornerRadius: 14)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.acier), lineWidth: 2))
                    .shadow(color: .black.opacity(0.55), radius: 50, y: 24)
                    .frame(maxWidth: largeurMax)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.automatic)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, fermer)
        .onAppear { focusTitre = true }
    }
}

// MARK: - documents

/// La fenêtre « Documents » : déposer un document (photothèque, scanner, fichiers), le jour qu'il concerne, et la
/// liste des documents déposés (leur fiche : résumé, alerte, archivage), chacun supprimable en deux temps.
struct FenetreDocuments: View {
    @Environment(Alfred.self) private var alfred
    let fermer: () -> Void
    /// Le jour que le document concerne : aucun par défaut (le champ vide de la console).
    @State private var avecJour = false
    @State private var jour = Calendar.current.startOfDay(for: .now)

    var body: some View {
        Fenetre(titre: "Documents", fermer: fermer) {
            VStack(alignment: .leading, spacing: 10) {
                Depot(jour: avecJour ? jour : nil)
                quand
                liste
            }
        }
        .onAppear { alfred.annexes?.relireDocuments() }
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
            }
        }
    }

    @ViewBuilder private var liste: some View {
        let annexes = alfred.annexes
        if case .reserve(let texte)? = annexes?.accesDocuments {
            Text(texte).font(.caption).foregroundStyle(Color(.texteSecondaire))
        } else if let docs = annexes?.documents, !docs.isEmpty {
            VStack(spacing: 8) {
                ForEach(docs.prefix(12)) { d in
                    CarteDocument(document: d)
                }
            }
            .masqueInvites(alfred.modeInvites)
        } else {
            Text("Aucun document pour l’instant.").font(.caption).foregroundStyle(Color(.texteSecondaire))
        }
    }
}

/// Un document déposé (`.doc`) : son nom, sa date (et le jour qu'il concerne, son archivage), son résumé ou son état ;
/// la bordure est sodium pendant la lecture, rouge en cas d'échec.
private struct CarteDocument: View {
    @Environment(Alfred.self) private var alfred
    let document: DocumentMaison
    @State private var arme = false
    @State private var suppression = false

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
                Button(arme ? "Confirmer" : "Supprimer") { supprimer() }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(arme ? Color(red: 1, green: 210 / 255, blue: 201 / 255) : Color(.glace))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 30)
                    .background(Console.bouton, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).strokeBorder(
                            arme ? Self.rouge : Color(.acier), lineWidth: 1.5)
                    )
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .disabled(suppression)
                    .accessibilityLabel(
                        arme ? "Confirmer la suppression de \(document.nom)" : "Supprimer \(document.nom)")
            }
            Text(resume)
                .font(.caption)
                .foregroundStyle(Color(red: 201 / 255, green: 216 / 255, blue: 228 / 255))
                .lineSpacing(2)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if document.alerte != nil {
                Text("Passage suspect : il s’adresse à un assistant. Alfred et Hermes ne le suivront pas.")
                    .font(.caption)
                    .foregroundStyle(Color(red: 1, green: 210 / 255, blue: 201 / 255))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Self.rouge).frame(width: 3) }
            }
        }
        .padding(.leading, 12)
        .padding([.vertical, .trailing], 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 12 / 255, green: 27 / 255, blue: 40 / 255), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(bordure, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    static let rouge = Color(red: 216 / 255, green: 106 / 255, blue: 90 / 255)

    private var bordure: Color {
        switch document.etat {
        case .pret: Color(.trait)
        case .enCours: Color(.sodium)
        case .erreur: Self.rouge
        }
    }

    private var resume: String {
        switch document.etat {
        case .pret: document.resume ?? ""
        case .erreur: "Lecture impossible : " + (document.erreur ?? "")
        case .enCours: "Lecture en cours…"
        }
    }

    /// « dim. 18 oct. · pour ven. 31 oct. · archivé » (la console : `docDate`).
    private var meta: String {
        var parties: [String] = []
        if let d = document.deposeLe.flatMap(DateDocument.lire) { parties.append(DateDocument.texte(d)) }
        var texte = parties.joined()
        if let p = document.pourLe.flatMap(DateDocument.lire) { texte += " · pour " + DateDocument.texte(p) }
        if document.paperless { texte += " · archivé" }
        return texte
    }

    /// La console : un premier toucher arme (« Confirmer », 3,5 s), le second supprime.
    private func supprimer() {
        guard arme else {
            arme = true
            Task {
                try? await Task.sleep(for: .seconds(3.5))
                arme = false
            }
            return
        }
        suppression = true
        Task {
            await alfred.annexes?.supprimer(document)
            suppression = false
            arme = false
        }
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

/// La fenêtre « Notifications » : la copie de celles des téléphones et les réponses d'Hermes annoncées, les nouvelles
/// bordées du faisceau ; tout est marqué lu à l'ouverture ; « Tout effacer ».
struct FenetreNotifications: View {
    @Environment(Alfred.self) private var alfred
    let fermer: () -> Void

    var body: some View {
        Fenetre(titre: "Notifications", fermer: fermer) {
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
                        .fixedSize()
                        .accessibilityIdentifier("effacerNotifications")
                }
            }
        }
        .task {
            // comme la console : marquées lues seulement si la fenêtre est encore ouverte une fois la liste chargée
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
    /// Le mode invités de la console : flou de 7 pt, ni sélection ni toucher, et rien pour VoiceOver.
    func masqueInvites(_ actif: Bool) -> some View {
        blur(radius: actif ? 7 : 0)
            .allowsHitTesting(!actif)
            .accessibilityHidden(actif)
            .animation(.easeInOut(duration: 0.3), value: actif)
    }
}
