import AlfredKit
import SwiftUI

/// La console d'Alfred, en natif : la même interface que la console web, sur iPhone, iPad et Mac.
///
/// Comme la console : au-delà de 1100 pt de large (iPad à l'horizontale, Mac), l'assistant à gauche, la roue au
/// centre, l'environnement à droite, les jauges et la voix en bas ; en dessous (iPhone, iPad à la verticale), trois
/// vues (Alfred, Pièces, Environnement) choisies en bas de l'écran.
struct ConsoleVue: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @State private var vue = VueConsole.pieces
    @State private var choisi: String?
    @State private var ecrire = false
    @State private var reglages = false
    /// Le démarrage de la console (2,4 s), joué une fois par ouverture.
    @State private var debut = Date.now

    enum VueConsole: Hashable, CaseIterable {
        case alfred, pieces, environnement

        var titre: String {
            switch self {
            case .alfred: "Alfred"
            case .pieces: "Pièces"
            case .environnement: "Environnement"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let large = geo.size.width > 1100
            ZStack(alignment: .bottom) {
                Console.fond
                VStack(spacing: 0) {
                    EnTeteConsole(texteLien: geo.size.width >= 600, large: large, reglages: $reglages)
                    Group {
                        if large {
                            dispositionLarge(geo.size)
                        } else {
                            dispositionCompacte
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    BasConsole(large: large, jauges: geo.size.height >= 640 || large, ecrire: $ecrire)
                    if !large {
                        NavConsole(vue: $vue)
                    }
                }
                .ignoresSafeArea(.keyboard)
                if ecrire {
                    // comme la console : la saisie se ferme à l'envoi, et le téléphone montre les échanges
                    SaisieConsole(ouverte: $ecrire) { if !large { vue = .alfred } }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .frame(maxWidth: large ? 640 : .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                AvisConsole()
                    .padding(.top, 84)
            }
        }
        .animation(.smooth(duration: 0.25), value: ecrire)
        .sheet(isPresented: $reglages) { ReglagesVue() }
        .sensoryFeedback(trigger: conversation.enConversation) { _, ouvert in ouvert ? .start : .stop }
        .sensoryFeedback(.success, trigger: conversation.reponses)
        .sensoryFeedback(trigger: alfred.dernierRetour) { _, retour in
            switch retour?.issue {
            case .confirmee: .success
            case .refusee, .sansConfirmation: .error
            case nil: nil
            }
        }
    }

    // MARK: - dispositions

    @ViewBuilder private var dispositionCompacte: some View {
        switch vue {
        case .pieces:
            VuePieces(choisi: $choisi, compact: true, debut: debut)
        case .alfred:
            PanneauAlfred()
                .padding(12)
        case .environnement:
            PanneauEnvironnement()
                .padding(12)
        }
    }

    private func dispositionLarge(_ taille: CGSize) -> some View {
        // la console : 310 et 330 pt ; 270 et 300 jusqu'à 1350 pt de large
        let etroit = taille.width <= 1350
        return HStack(spacing: 0) {
            PanneauAlfred()
                .frame(width: etroit ? 270 : 310)
                .padding(.vertical, etroit ? 12 : 16)
                .padding(.horizontal, etroit ? 8 : 12)
            VuePieces(choisi: $choisi, compact: false, debut: debut)
            PanneauEnvironnement()
                .frame(width: etroit ? 300 : 330)
                .padding(.vertical, etroit ? 12 : 16)
                .padding(.horizontal, etroit ? 8 : 12)
        }
    }
}

// MARK: - la vue des pièces

/// La roue, centrée dans la place qui reste, et la carte de la pièce choisie.
struct VuePieces: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Binding var choisi: String?
    let compact: Bool
    let debut: Date

    var body: some View {
        GeometryReader { geo in
            // la console : R = min(0,485 × largeur, 0,47 × hauteur) sur téléphone, 0,46 sur grand écran
            let r =
                compact
                ? min(geo.size.width * 0.485, geo.size.height * 0.47)
                : min(geo.size.width * 0.46, geo.size.height * 0.46)
            ZStack(alignment: .bottom) {
                Roue(choisi: $choisi, rayon: max(100, r), compact: compact, debut: debut) {
                    Task { await conversation.basculerEcoute() }
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                if let s = alfred.secteurs.first(where: { $0.id == choisi }) {
                    CartePiece(secteur: s) { choisi = nil }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: compact ? .infinity : 560)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: choisi)
        }
        .overlay {
            if alfred.secteurs.isEmpty, alfred.estPret {
                Text("Aucune pièce à montrer.")
                    .font(.callout)
                    .foregroundStyle(Color(.texteSecondaire))
            }
        }
    }
}

// MARK: - en-tête

/// L'en-tête de la console : ALFRED / MANOR COMMAND, le lien avec la maison, les réglages et le compte.
struct EnTeteConsole: View {
    @Environment(Alfred.self) private var alfred
    let texteLien: Bool
    let large: Bool
    @Binding var reglages: Bool
    @State private var quitter = false

    var body: some View {
        HStack(spacing: large ? 20 : 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ALFRED")
                    .font(.title2.weight(.heavy))
                    .tracking(6)
                    .foregroundStyle(Color(.glace))
                Text("MANOR COMMAND")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color(.champagne))
            }
            // la marque ne se resserre jamais : c'est l'espace entre elle et les boutons qui cède
            .fixedSize()
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Alfred")
            .accessibilityAddTraits(.isHeader)
            if large {
                Rectangle().fill(Color(.trait)).frame(width: 1, height: 24).accessibilityHidden(true)
            }
            Lien(texte: texteLien, etiquette: large)
            Spacer(minLength: 8)
            Button {
                reglages = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(StyleIcone())
            .accessibilityLabel("Réglages")
            .accessibilityIdentifier("reglages")
            Button {
                quitter = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(StyleIcone())
            .accessibilityLabel(alfred.demo ? "Quitter la démonstration" : "Se déconnecter")
            .accessibilityIdentifier("compte")
            .confirmationDialog(
                alfred.demo ? "Quitter la démonstration ?" : "Se déconnecter de la maison ?", isPresented: $quitter,
                titleVisibility: .visible
            ) {
                Button(alfred.demo ? "Quitter" : "Se déconnecter", role: .destructive) {
                    Task {
                        if alfred.demo {
                            await alfred.quitterDemo()
                        } else {
                            await alfred.seDeconnecter()
                        }
                    }
                }
            } message: {
                if !alfred.demo {
                    Text(
                        "La connexion de cet appareil est supprimée dans Home Assistant. Vous pourrez vous reconnecter."
                    )
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, large ? 24 : 16)
        .frame(minHeight: 72)
        .background(Console.bandeau.opacity(0.95).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.trait)).frame(height: 2).accessibilityHidden(true)
        }
    }
}

/// Le lien avec la maison : une pastille sarcelle (connecté) ou sodium, et son état en clair sur les grands écrans.
private struct Lien: View {
    @Environment(Alfred.self) private var alfred
    let texte: Bool
    let etiquette: Bool

    var body: some View {
        HStack(spacing: 10) {
            if etiquette {
                Text("Lien").etiquette(Color(.texteSecondaire), espacement: 0.8)
            }
            HStack(spacing: 8) {
                Circle().fill(couleur).frame(width: 9, height: 9)
                if texte {
                    Text(mot)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(couleur)
                }
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lien avec la maison")
        .accessibilityValue(mot)
        .accessibilityIdentifier("lien")
    }

    private var couleur: Color { alfred.estPret ? Color(.sarcelle) : Color(.sodium) }

    private var mot: String {
        switch alfred.liaison {
        case .pret: "Connecté"
        case .connexion, .synchronisation: "Connexion…"
        case .deconnecte: "Déconnecté"
        case .fatal: "Refusé"
        }
    }
}

// MARK: - navigation (téléphone)

/// Les trois vues de la console sur téléphone : capitales espacées, la vue choisie en champagne, soulignée du faisceau.
/// Comme la console, « Environnement » a 1,4 fois la place des deux autres. Le texte garde la taille de la console,
/// comme une barre d'onglets du système ; un appui long le montre en grand (visionneuse de grand contenu).
struct NavConsole: View {
    @Binding var vue: ConsoleVue.VueConsole

    var body: some View {
        GeometryReader { g in
            let unite = (g.size.width - 16) / 3.4
            HStack(spacing: 8) {
                ForEach(ConsoleVue.VueConsole.allCases, id: \.self) { v in
                    bouton(v)
                        .frame(width: unite * (v == .environnement ? 1.4 : 1))
                }
            }
        }
        .frame(height: 50)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Console.bandeau.ignoresSafeArea(edges: .bottom)
                Rectangle().fill(Color(.trait)).frame(height: 1.5)
            }
            .accessibilityHidden(true)
        }
        .animation(.smooth(duration: 0.2), value: vue)
    }

    private func bouton(_ v: ConsoleVue.VueConsole) -> some View {
        Button {
            vue = v
        } label: {
            Text(v.titre)
                .font(.caption2.weight(.heavy))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(vue == v ? Color(.champagne) : Color(.texteSecondaire))
                .frame(maxWidth: .infinity, minHeight: 50)
                .overlay(alignment: .top) {
                    if vue == v {
                        Rectangle()
                            .fill(Color(.faisceau))
                            .frame(height: 2)
                            .shadow(color: Color(.faisceau).opacity(0.55), radius: 5)
                            .padding(.horizontal, 24)
                            .offset(y: -6)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer()
        .accessibilityAddTraits(vue == v ? .isSelected : [])
        .accessibilityIdentifier("onglet-\(v)")
    }
}

// MARK: - le bas : jauges et voix

/// Le bas de la console : les jauges (et la consommation sur grand écran), « Parler à Alfred », « Écrire », le niveau
/// du micro et l'état de la conversation.
struct BasConsole: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    let large: Bool
    let jauges: Bool
    @Binding var ecrire: Bool

    var body: some View {
        Group {
            if large {
                HStack(alignment: .center, spacing: 24) {
                    Jauges()
                    Consommation()
                        .frame(minWidth: 100, maxWidth: .infinity)
                    voix
                        .frame(width: 440)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    if jauges {
                        Jauges()
                    }
                    voix
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Console.bandeau.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(.trait)).frame(height: 2).accessibilityHidden(true)
        }
    }

    private var voix: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(libelleParler) {
                    Task { await conversation.basculerEcoute() }
                }
                .buttonStyle(StyleConsole(genre: conversation.enConversation ? .session : .principal))
                .disabled(!peutParler)
                .accessibilityLabel(conversation.enConversation ? "Terminer la conversation" : libelleParler)
                .accessibilityIdentifier("parler")
                Button("Écrire") { ecrire.toggle() }
                    .buttonStyle(StyleConsole())
                    .disabled(conversation.enConversation)
                    .accessibilityAddTraits(ecrire ? .isSelected : [])
                    .accessibilityIdentifier("ecrire")
            }
            NiveauMicro()
            Text(statut)
                .font(.caption.weight(conversation.phase == .ecoute ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(couleurStatut)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("statut")
        }
        // les commandes grandissent avec le texte jusqu'à la 1re taille d'accessibilité (la roue garde sa place)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var peutParler: Bool {
        if conversation.enConversation { return true }
        return alfred.estPret && conversation.phase != .reflexion
    }

    private var libelleParler: String {
        if conversation.enConversation { return "Terminer" }
        switch conversation.phase {
        case .reflexion: return "Analyse en cours…"
        default: return "Parler à Alfred"
        }
    }

    /// Les mots de la console (`syncControls`).
    private var statut: String {
        switch alfred.liaison {
        case .connexion, .synchronisation: return "Connexion à la maison…"
        case .deconnecte: return "Maison déconnectée · reconnexion automatique"
        case .fatal(let message): return message
        case .pret: break
        }
        let mots: String
        switch conversation.phase {
        case .repos: mots = conversation.enConversation ? "un instant…" : "À votre service"
        case .ecoute: mots = conversation.enConversation ? "je vous écoute, parlez" : "Je vous écoute, parlez"
        case .reflexion: mots = "Alfred prépare sa réponse…"
        case .reponse: mots = "Alfred vous répond"
        }
        return conversation.enConversation ? "Conversation ouverte · " + mots : mots
    }

    private var couleurStatut: Color {
        if case .fatal = alfred.liaison { return Color(.alerte) }
        return conversation.phase == .ecoute ? Color(.sarcelle) : Color(.texteSecondaire)
    }
}

/// Le niveau du micro : une barre fine, sarcelle (lue à chaque image pendant la conversation seulement).
private struct NiveauMicro: View {
    @Environment(Conversation.self) private var conversation
    @Environment(\.animationsCoupees) private var immobile

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !conversation.enConversation || immobile)) { _ in
            GeometryReader { g in
                let n =
                    conversation.enConversation && conversation.phase == .ecoute ? CGFloat(conversation.niveauMicro) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Console.jaugeVide)
                    Capsule().fill(Color(.sarcelle)).frame(width: g.size.width * min(1, n * 2.2))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Les quatre jauges de la console (GPU, PC, MAISON, JOUR) : un anneau sarcelle et la valeur en chiffres fixes.
private struct Jauges: View {
    @Environment(Alfred.self) private var alfred

    var body: some View {
        HStack(spacing: 4) {
            ForEach(alfred.console.jauges) { j in
                let v = alfred.maison[j.entite]?.nombre
                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(
                            Color(red: 60 / 255, green: 80 / 255, blue: 95 / 255).opacity(0.5), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: j.fraction(v))
                            .stroke(Color(.sarcelle), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Color(.sarcelle).opacity(0.6), radius: 4)
                    }
                    .frame(width: 30, height: 30)
                    .padding(1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(j.libelle).etiquette(Color(.texteSecondaire), espacement: 0.4)
                        Text(Format.valeur(v, j.unite, j.decimalesBandeau))
                            .font(.footnote.weight(.semibold).monospaced())
                            .foregroundStyle(Color(.texte))
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(j.description)
                .accessibilityValue(Format.valeur(v, " " + j.unite, j.decimalesBandeau))
            }
        }
        // des instruments, à la taille de la console ; les mêmes valeurs suivent le texte dans Environnement
        .dynamicTypeSize(...DynamicTypeSize.large)
        .animation(.smooth, value: alfred.console.jauges.map { alfred.maison[$0.entite]?.etat })
    }
}

/// La consommation de la maison (grand écran) : la trace des dernières mesures, la dernière valeur et l'écart.
private struct Consommation: View {
    @Environment(Alfred.self) private var alfred

    var body: some View {
        let h = alfred.historiquePuissance
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("consommation").font(.caption).foregroundStyle(Color(.texteSecondaire))
                Spacer(minLength: 8)
                Text(sousTitre(h)).font(.caption).foregroundStyle(Color(.texteSecondaire))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Canvas { c, taille in
                guard h.count >= 2, let bas = h.min(), var haut = h.max() else { return }
                if haut - bas < 20 { haut = bas + 20 }
                let w = taille.width
                let ht = taille.height
                func x(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(h.count - 1) * (w - 6) + 3 }
                func y(_ v: Double) -> CGFloat { ht - 3 - CGFloat((v - bas) / (haut - bas)) * (ht - 8) }
                var trace = Path()
                for (i, v) in h.enumerated() {
                    if i == 0 {
                        trace.move(to: CGPoint(x: x(i), y: y(v)))
                    } else {
                        trace.addLine(to: CGPoint(x: x(i), y: y(v)))
                    }
                }
                var aire = trace
                aire.addLine(to: CGPoint(x: x(h.count - 1), y: ht))
                aire.addLine(to: CGPoint(x: x(0), y: ht))
                aire.closeSubpath()
                c.fill(
                    aire,
                    with: .linearGradient(
                        Gradient(colors: [Console.reacteur.opacity(0.28), Console.reacteur.opacity(0)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: ht)))
                c.stroke(trace, with: .color(Console.lueur.opacity(0.9)), lineWidth: 1.4)
                let fin = CGPoint(x: x(h.count - 1), y: y(h[h.count - 1]))
                c.fill(
                    Path(ellipseIn: CGRect(x: fin.x - 2.5, y: fin.y - 2.5, width: 5, height: 5)),
                    with: .color(Console.lueur))
            }
            .frame(height: 40)
        }
        // un instrument, à la taille de la console, comme les jauges
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consommation de la maison")
        .accessibilityValue(sousTitre(h))
    }

    private func sousTitre(_ h: [Double]) -> String {
        guard let dernier = h.last, let bas = h.min(), let haut = h.max() else { return "Mesure indisponible" }
        guard h.count >= 2 else { return "Collecte de l’historique…" }
        return "\(Format.valeur(dernier, " W")), de \(Format.valeur(bas)) à \(Format.valeur(haut))"
    }
}

// MARK: - écrire

/// La saisie de la console : un champ, « Envoyer », et la croix pour fermer.
struct SaisieConsole: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Binding var ouverte: Bool
    let envoye: () -> Void
    @State private var texte = ""
    @FocusState private var focus: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Écrire à Alfred…", text: $texte, axis: .vertical)
                .lineLimit(1...4)
                .font(.callout)
                .foregroundStyle(Color(.texte))
                .focused($focus)
                .submitLabel(.send)
                .onSubmit(envoyer)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color(red: 8 / 255, green: 18 / 255, blue: 29 / 255), in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.acier), lineWidth: 1.5))
                .accessibilityLabel("Votre message")
                .accessibilityIdentifier("saisie")
            Button("Envoyer", action: envoyer)
                .buttonStyle(StyleConsole(genre: .principal, hauteur: 44))
                .fixedSize()
                .disabled(texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !alfred.estPret)
                .accessibilityIdentifier("envoyer")
            Button {
                ouverte = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(StyleIcone())
            .accessibilityLabel("Fermer la saisie")
        }
        .padding(10)
        .background(Console.carte, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.faisceauSombre), lineWidth: 2))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 16)
        .onAppear { focus = true }
    }

    private func envoyer() {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, alfred.estPret else { return }
        texte = ""
        Task { await conversation.ecrire(t) }
        ouverte = false
        envoye()
    }
}

// MARK: - la pièce choisie

/// La carte de la pièce choisie (`#room-card`) : son nom, l'état de sa lumière, ses mesures, et un seul bouton.
struct CartePiece: View {
    @Environment(Alfred.self) private var alfred
    let secteur: Secteur
    let fermer: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.animationsCoupees) private var immobile

    var body: some View {
        let attente = alfred.enCours(secteur.id)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(secteur.nom)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color(.texte))
                        .accessibilityAddTraits(.isHeader)
                    Text(etat(attente))
                        .font(.footnote)
                        .foregroundStyle(Color(.champagne))
                        .accessibilityIdentifier("etatPiece")
                }
                Spacer()
                Button(action: fermer) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(.glace))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer la pièce")
            }
            HStack(alignment: .top, spacing: 18) {
                mesure("Température", secteur.temperature)
                mesure("Humidité", secteur.humidite)
                mesure("COV", secteur.air)
            }
            Button(secteur.allumee ? "Éteindre" : "Allumer") { alfred.basculer(secteur) }
                .buttonStyle(StyleConsole(genre: .principal))
                .disabled(attente || !secteur.disponible)
                .opacity(attente && pulse ? 0.6 : 1)
                .accessibilityIdentifier("actionPiece")
        }
        .padding(18)
        .background(Console.carte, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Console.bordureCarte, lineWidth: 2))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 16)
        .onChange(of: attente, initial: true) { _, a in
            guard a, !reduire, !immobile else {
                pulse = false
                return
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cartePiece")
    }

    private func etat(_ attente: Bool) -> String {
        if attente { return "Commande envoyée · confirmation attendue" }
        return secteur.allumee ? "Lumière allumée" : secteur.disponible ? "Lumière éteinte" : "Lumière indisponible"
    }

    private func mesure(_ libelle: String, _ m: Mesure?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(libelle).font(.caption).foregroundStyle(Color(.texteSecondaire))
            Text(Format.valeur(m?.valeur, m?.unite ?? "", 1))
                .font(.title3.weight(.semibold).monospaced())
                .foregroundStyle(Color(.texte))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - avis

/// Les avis passagers de la console (« Salon allumé », « Pas de réponse de la maison »), annoncés à VoiceOver.
private struct AvisConsole: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @State private var affiche: (id: UUID, texte: String, alerte: Bool)?

    var body: some View {
        Group {
            if let affiche {
                Text(affiche.texte)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(affiche.alerte ? Color(.alerte) : Color(.glace))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Console.carte, in: .rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(affiche.alerte ? Color(.alerte) : Color(.faisceauSombre), lineWidth: 1.5)
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(affiche.id)
                    .accessibilityIdentifier("avis")
            }
        }
        .animation(.smooth, value: affiche?.id)
        .onChange(of: alfred.dernierRetour) { _, retour in
            guard let retour else { return }
            let nom = alfred.secteurs.first { $0.id == retour.cle }?.nomCourant ?? "La pièce"
            switch retour.issue {
            case .confirmee:
                let allume =
                    alfred.maison[retour.cle]?.etat == "on"
                    || alfred.secteurs.first { $0.id == retour.cle }?.allumee == true
                montrer(nom + (allume ? " allumé" : " éteint"), alerte: false)
            case .refusee(let m): montrer(m, alerte: true)
            case .sansConfirmation: montrer("Pas de réponse de la maison pour \(nom.lowercased()).", alerte: true)
            }
        }
        .onChange(of: conversation.avis) { _, a in
            guard let a else { return }
            montrer(a.texte, alerte: a.genre == .attention)
            conversation.oublierAvis(a)
        }
    }

    private func montrer(_ texte: String, alerte: Bool) {
        let id = UUID()
        affiche = (id, texte, alerte)
        AccessibilityNotification.Announcement(texte).post()
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if affiche?.id == id { affiche = nil }
        }
    }
}
