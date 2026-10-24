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
    @Environment(\.animationsCoupees) private var immobile
    @State private var vue = VueConsole.pieces
    @State private var choisi: String?
    @State private var ecrire = false
    @State private var fenetre: FenetreConsole?
    @State private var liensOuverts = false
    /// Les panneaux de côté de la disposition large, masqués par leur poignée (choix gardé sur l'appareil, comme la
    /// console le garde dans le navigateur).
    @AppStorage("console.assistantMasque") private var assistantMasque = false
    @AppStorage("console.environnementMasque") private var environnementMasque = false
    /// Le démarrage de la console (2,4 s), joué une fois par ouverture.
    @State private var debut = Date.now
    /// La hauteur de la console sans le clavier, mesurée sur la pile qui l'ignore : elle ne bouge ni quand le clavier
    /// s'ouvre, ni pendant qu'il se ferme ; les jauges ne disparaissent pas et la roue ne saute pas (revues du 18.10 et
    /// du 21.10 : mesurée sur la place laissée par le clavier, les jauges disparaissaient et la roue descendait).
    @State private var hauteurSansClavier: CGFloat = 0

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
                echapConversation
                VStack(spacing: 0) {
                    EnTeteConsole(largeur: geo.size.width, fenetre: $fenetre, liensOuverts: $liensOuverts)
                        .zIndex(1)
                    Group {
                        if large {
                            dispositionLarge(geo.size)
                        } else {
                            dispositionCompacte
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    BasConsole(
                        large: large,
                        jauges: (hauteurSansClavier > 0 ? hauteurSansClavier : geo.size.height) >= 640 || large,
                        ecrire: $ecrire,
                        raccourcis: fenetre == nil && !liensOuverts)
                    if !large {
                        NavConsole(vue: $vue)
                    }
                }
                // mesurée sur la pile elle-même, AVANT « ignoresSafeArea » : après, c'est le cadre réduit par le
                // clavier (CI du 21.10 : les jauges disparaissaient, la roue descendait de 22 pt)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    hauteurSansClavier = $0
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
            .overlay(alignment: .topTrailing) {
                if liensOuverts {
                    ZStack(alignment: .topTrailing) {
                        // un toucher ailleurs referme la liste (la console : un clic ailleurs)
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture { liensOuverts = false }
                            .accessibilityHidden(true)
                        ListeLiens(ouverte: $liensOuverts)
                            .padding(.top, geo.size.width > 560 ? 70 : 62)
                            .padding(.trailing, 12)
                    }
                    .transition(.opacity)
                }
            }
            .fullScreenCover(item: $fenetre) { f in
                Group {
                    switch f {
                    case .documents: FenetreDocuments { fermerFenetre() }
                    case .notifications: FenetreNotifications { fermerFenetre() }
                    case .reglages: FenetreReglages { fermerFenetre() }
                    }
                }
                // la console reste devinée sous le voile de la fenêtre
                .presentationBackground(.clear)
                // sur Mac (app iPad), la présentation n'hérite pas toujours de l'environnement : Réglages plantait en
                // lisant la conversation (retour d'essai, 23.10) ; les deux objets sont donc redonnés ici
                .environment(alfred)
                .environment(conversation)
            }
            .onChange(of: fenetre) { _, f in
                if f != nil {
                    liensOuverts = false
                    ecrire = false
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: ecrire)
        // tests d'interface : aucune transition (l'audit juge l'écran final, pas un fondu)
        .animation(immobile ? nil : .smooth(duration: 0.15), value: liensOuverts)
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

    /// Échap revient à la pièce (ni liste des liens, ni saisie, ni fenêtre au-dessus) ; la console, dans l'ordre :
    /// la liste des liens, la saisie, la pièce, puis la conversation (`keydown`).
    private var echapLibre: Bool { !liensOuverts && !ecrire && fenetre == nil }

    /// Échap ferme la conversation quand rien d'autre n'est ouvert (un bouton sans surface : seul son raccourci compte).
    @ViewBuilder private var echapConversation: some View {
        if echapLibre, choisi == nil, conversation.enConversation {
            Button("Terminer la conversation") { Task { await conversation.terminer() } }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    /// Une fenêtre se ferme d'un coup, comme elle s'est ouverte.
    private func fermerFenetre() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { fenetre = nil }
    }

    // MARK: - dispositions

    @ViewBuilder private var dispositionCompacte: some View {
        switch vue {
        case .pieces:
            VuePieces(choisi: $choisi, compact: true, debut: debut, echap: echapLibre)
        case .alfred:
            PanneauAlfred()
                .padding(12)
        case .environnement:
            PanneauEnvironnement()
                .padding(12)
        }
    }

    private func dispositionLarge(_ taille: CGSize) -> some View {
        // la console : 310 et 330 pt ; 270 et 300 jusqu'à 1350 pt de large ; un panneau masqué rend sa place à la roue
        let etroit = taille.width <= 1350
        return HStack(spacing: 0) {
            if !assistantMasque {
                PanneauAlfred()
                    .padding(.vertical, etroit ? 12 : 16)
                    .padding(.horizontal, etroit ? 8 : 12)
                    .frame(width: (etroit ? 270 : 310))
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VuePieces(choisi: $choisi, compact: false, debut: debut, echap: echapLibre)
                .overlay(alignment: .leading) {
                    PoigneePanneau(cote: .assistant, masque: $assistantMasque)
                }
                .overlay(alignment: .trailing) {
                    PoigneePanneau(cote: .environnement, masque: $environnementMasque)
                }
            if !environnementMasque {
                PanneauEnvironnement(large: true)
                    .padding(.vertical, etroit ? 12 : 16)
                    .padding(.horizontal, etroit ? 8 : 12)
                    .frame(width: (etroit ? 300 : 330))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: assistantMasque)
        .animation(.smooth(duration: 0.3), value: environnementMasque)
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
    /// Échap ferme la pièce (rien d'autre n'est ouvert au-dessus).
    var echap = false

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
                    // la console : sur toute la largeur de la roue, 16 pt des bords en disposition large
                    CartePiece(secteur: s, large: !compact, echap: echap) { choisi = nil }
                        .padding(.horizontal, compact ? 12 : 16)
                        .padding(.bottom, compact ? 8 : 16)
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
    /// Les raccourcis du clavier (espace pour parler, / pour écrire), coupés quand une fenêtre ou la saisie est
    /// ouverte (comme la console : « des raccourcis qui respectent les champs »).
    let raccourcis: Bool

    var body: some View {
        Group {
            if large {
                HStack(alignment: .center, spacing: 24) {
                    // la console : les pastilles de l'état des services sous les jauges
                    VStack(alignment: .leading, spacing: 10) {
                        Jauges()
                        PastillesEtat()
                    }
                    .fixedSize(horizontal: true, vertical: false)
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
                .keyboardShortcut(raccourcis && !ecrire ? KeyboardShortcut(.space, modifiers: []) : nil)
                .accessibilityLabel(conversation.enConversation ? "Terminer la conversation" : libelleParler)
                // VoiceOver se tait quand le micro s'ouvre (sinon le micro l'entend)
                .accessibilityAddTraits(
                    !conversation.enConversation && conversation.phase == .repos ? .startsMediaSession : []
                )
                .accessibilityIdentifier("parler")
                if conversation.enConversation {
                    // 24.10 (la console : #mic-mute) : couper le micro sans fermer la conversation
                    Button {
                        conversation.basculerMicro()
                    } label: {
                        Image(systemName: conversation.microCoupe ? "mic.slash" : "mic")
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(StyleConsole(genre: conversation.microCoupe ? .sodium : .normal, largeur: 48))
                    .keyboardShortcut(raccourcis && !ecrire ? KeyboardShortcut("m", modifiers: []) : nil)
                    .accessibilityLabel(conversation.microCoupe ? "Rouvrir le micro" : "Couper le micro")
                    .accessibilityAddTraits(conversation.microCoupe ? .isSelected : [])
                    .help(conversation.microCoupe ? "Rouvrir le micro (m)" : "Couper le micro (m)")
                    .accessibilityIdentifier("micro")
                }
                // jamais grisé, comme la console : dans une conversation, l'écrit en garde le fil (un nom mal compris)
                Button("Écrire") { ecrire.toggle() }
                    .buttonStyle(StyleConsole())
                    .keyboardShortcut(raccourcis && !ecrire ? KeyboardShortcut("/", modifiers: []) : nil)
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
        return alfred.estPret && conversation.phase != .reflexion && conversation.essai == .arrete
    }

    private var libelleParler: String {
        if conversation.enConversation { return "Terminer" }
        switch conversation.phase {
        case .reflexion: return "Analyse en cours…"
        case .reponse: return "Interrompre"
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
        if conversation.enConversation, conversation.microCoupe, [.ecoute, .repos].contains(conversation.phase) {
            return "Conversation ouverte · micro coupé"
        }
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
        if conversation.enConversation, conversation.microCoupe { return Color(.sodium) }
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
                .accessibilityIdentifier("jauge")
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

/// La saisie de la console (`#entry`) : un champ d'une ligne (4000 caractères, la touche « envoyer » du clavier
/// envoie), « Envoyer », et la croix pour fermer (Échap). Le texte ne quitte le champ qu'une fois parti : pendant la
/// réflexion d'Alfred, l'envoi attend (la console : `talk` rend false et le texte reste).
struct SaisieConsole: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Binding var ouverte: Bool
    let envoye: () -> Void
    @State private var texte = ""
    @FocusState private var focus: Bool
    @Environment(\.dynamicTypeSize) private var taille

    var body: some View {
        Group {
            // aux tailles d'accessibilité, « Envoyer » prendrait toute la ligne : le champ seul, les boutons dessous
            if taille.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    champ
                    HStack(spacing: 8) {
                        boutonEnvoyer
                        Spacer(minLength: 0)
                        boutonFermer
                    }
                }
            } else {
                HStack(spacing: 8) {
                    champ
                    boutonEnvoyer
                    boutonFermer
                }
            }
        }
        .padding(10)
        .background {
            // l'ombre portée par le fond seul (posée sur la carte, chaque texte porterait la sienne)
            RoundedRectangle(cornerRadius: 10).fill(Console.carte).shadow(color: .black.opacity(0.5), radius: 20, y: 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.faisceauSombre), lineWidth: 2))
        .onAppear { focus = true }
    }

    private var champ: some View {
        TextField("Écrire à Alfred…", text: $texte)
            .font(.callout)
            .foregroundStyle(Color(.texte))
            .focused($focus)
            .submitLabel(.send)
            .onSubmit(envoyer)
            .onChange(of: texte) { _, t in
                if t.count > Self.longueurMax { texte = String(t.prefix(Self.longueurMax)) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color(red: 8 / 255, green: 18 / 255, blue: 29 / 255), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.acier), lineWidth: 1.5))
            .accessibilityLabel("Votre message")
            .accessibilityIdentifier("saisie")
    }

    private var boutonEnvoyer: some View {
        Button("Envoyer", action: envoyer)
            .buttonStyle(StyleConsole(genre: .principal, hauteur: 44))
            .largeurDuTexte()
            .disabled(
                texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !alfred.estPret
                    || !conversation.peutEcrire
            )
            .accessibilityIdentifier("envoyer")
    }

    private var boutonFermer: some View {
        Button {
            ouverte = false
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(StyleIcone())
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Fermer la saisie")
    }

    /// La console : `maxlength="4000"`.
    static let longueurMax = 4000

    private func envoyer() {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, alfred.estPret, conversation.peutEcrire else { return }
        Task {
            guard await conversation.ecrire(t) else { return }
            texte = ""
            ouverte = false
            envoye()
        }
    }
}

// MARK: - la pièce choisie

/// La carte de la pièce choisie (`#room-card`) : son nom, l'état de sa lumière, ses mesures, et un seul bouton ; en
/// disposition large, le bouton se range à droite des mesures (la console : une grille à deux colonnes).
struct CartePiece: View {
    @Environment(Alfred.self) private var alfred
    let secteur: Secteur
    var large = false
    var echap = false
    let fermer: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.animationsCoupees) private var immobile

    var body: some View {
        let attente = alfred.enCours(secteur.id)
        // aux tailles d'accessibilité, la carte ne passe plus sous l'en-tête : elle défile
        ViewThatFits(in: .vertical) {
            contenu(attente)
            ScrollView { contenu(attente) }
                .scrollBounceBehavior(.basedOnSize)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 12).fill(Console.carte).shadow(color: .black.opacity(0.5), radius: 20, y: 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Console.bordureCarte, lineWidth: 2))
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

    /// Le contenu de la carte : son nom et son état, la croix, les mesures et le bouton.
    private func contenu(_ attente: Bool) -> some View {
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
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.acier), lineWidth: 1.5))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(echap ? .cancelAction : nil)
                .accessibilityLabel("Fermer la pièce")
            }
            if large {
                HStack(alignment: .bottom, spacing: 16) {
                    mesures
                    Spacer(minLength: 0)
                    action(attente)
                        .frame(minWidth: 110)
                        .fixedSize()
                }
            } else {
                mesures
                action(attente)
            }
        }
    }

    /// Température, humidité, COV : 22 pt en chiffres fixes (20 sur téléphone), 24 pt d'écart (18).
    private var mesures: some View {
        // côte à côte comme la console ; empilées quand elles ne tiennent plus (très grand texte)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: large ? 24 : 18) { lesMesures }
            VStack(alignment: .leading, spacing: 10) { lesMesures }
        }
    }

    @ViewBuilder private var lesMesures: some View {
        mesure("Température", secteur.temperature)
        mesure("Humidité", secteur.humidite)
        mesure("COV", secteur.air)
    }

    /// Le bouton de la console (`#room-action`) : un bouton ordinaire, bordé du faisceau.
    private func action(_ attente: Bool) -> some View {
        Button(secteur.allumee ? "Éteindre" : "Allumer") { alfred.basculer(secteur) }
            .buttonStyle(StyleConsole(genre: .piece))
            .disabled(attente || !secteur.disponible)
            .opacity(attente && pulse ? 0.6 : 1)
            .accessibilityIdentifier("actionPiece")
    }

    private func etat(_ attente: Bool) -> String {
        if attente { return "Commande envoyée · confirmation attendue" }
        return secteur.allumee ? "Lumière allumée" : secteur.disponible ? "Lumière éteinte" : "Lumière indisponible"
    }

    private func mesure(_ libelle: String, _ m: Mesure?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(libelle).font(.caption.weight(.medium)).foregroundStyle(Color(.texteSecondaire))
            Text(Format.valeur(m?.valeur, m?.unite ?? "", 1))
                .font((large ? Font.title2 : .title3).weight(.semibold).monospaced())
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
    /// La liaison est tombée (pour annoncer son retour).
    @State private var liaisonPerdue = false

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
        // VoiceOver dit la réponse d'une question écrite et l'échec d'une demande (la console : le journal en
        // `aria-live`), et la liaison qui tombe puis revient (la ligne d'état en `role="status"`)
        .onChange(of: conversation.annonce) { _, a in
            if let a { annoncer(a.texte) }
        }
        .onChange(of: alfred.estPret) { _, pret in
            if !pret, case .deconnecte = alfred.liaison {
                liaisonPerdue = true
                annoncer("Maison déconnectée · reconnexion automatique")
            } else if pret, liaisonPerdue {
                liaisonPerdue = false
                annoncer("Maison reconnectée")
            }
        }
    }

    /// Jamais micro ouvert (conversation, essai du micro) : le micro entendrait VoiceOver.
    private func annoncer(_ texte: String) {
        guard !conversation.enConversation, conversation.essai == .arrete else { return }
        AccessibilityNotification.Announcement(texte).post()
    }

    private func montrer(_ texte: String, alerte: Bool) {
        let id = UUID()
        affiche = (id, texte, alerte)
        annoncer(texte)
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if affiche?.id == id { affiche = nil }
        }
    }
}

// MARK: - poignées des panneaux (disposition large)

/// La poignée d'un panneau de côté (`#assistant-toggle`, `#environment-toggle`) : 28 × 88 pt, accrochée au bord du
/// panneau, deux traits et un chevron champagne ; elle masque le panneau (la roue prend sa place) ou le rend.
struct PoigneePanneau: View {
    enum Cote { case assistant, environnement }
    let cote: Cote
    @Binding var masque: Bool

    var body: some View {
        Button {
            masque.toggle()
        } label: {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Rectangle().frame(width: 12, height: 2)
                    Rectangle().frame(width: 12, height: 2)
                }
                .opacity(0.7)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .rotationEffect(.degrees(pointeAGauche ? 180 : 0))
            }
            .foregroundStyle(Color(.champagne))
            .frame(width: 28, height: 88)
            .background {
                forme.fill(Console.bouton).shadow(
                    color: .black.opacity(0.27), radius: 9, x: cote == .assistant ? 5 : -5)
            }
            .overlay(forme.stroke(Color(.acier), lineWidth: 1.5))
            // la cible déborde de 8 pt de chaque côté (la console : ::after), 44 pt en tout
            .frame(width: 44, height: 88)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .offset(x: cote == .assistant ? -8 : 8)
        .accessibilityLabel(libelle)
        .accessibilityIdentifier(cote == .assistant ? "poigneeAssistant" : "poigneeEnvironnement")
    }

    /// L'assistant : chevron vers la gauche quand il est ouvert ; l'environnement : vers la gauche quand il est masqué.
    private var pointeAGauche: Bool { cote == .assistant ? !masque : masque }

    private var libelle: String {
        switch cote {
        case .assistant: masque ? "Afficher l’assistant personnel" : "Masquer l’assistant personnel"
        case .environnement: masque ? "Afficher l’environnement" : "Masquer l’environnement"
        }
    }

    /// Arrondie du côté de la roue, droite du côté du panneau.
    private var forme: UnevenRoundedRectangle {
        cote == .assistant
            ? UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10)
            : UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
    }
}
