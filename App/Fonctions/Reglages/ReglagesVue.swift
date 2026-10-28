import AlfredKit
import SwiftUI

/// « Réglages & état », dans l'espace SYSTÈME (28.10 : avant, une fenêtre ; décision du 18.10 : le contenu de la
/// console, puis les réglages propres à l'app dessous) : le modèle, les entités, la dernière réponse, le micro (choix, autorisation,
/// essai), la note de la console ; puis le compte, la lecture des réponses écrites, les engagements de confidentialité,
/// la version et le code source.
struct ReglagesSysteme: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @State private var confirmer = false
    @State private var entrees: [EntreeMicro] = []
    @State private var choisie: String?
    @State private var autorise = false

    var body: some View {
        BlocPage(titre: "Réglages & état") {
            VStack(alignment: .leading, spacing: 0) {
                LigneEtat("Modèle", valeur: alfred.moteur ?? "—")
                LigneEtat("Entités", valeur: alfred.nombreEntites.map(String.init) ?? "—")
                LigneEtat("Dernière réponse", valeur: conversation.derniereDuree.map(Self.duree) ?? "—")
                micro
                actionsMicro
                    .padding(.top, 14)
                retourMicro
                    .padding(.top, 12)
                Text(
                    "Le test du micro n’envoie aucune commande à la maison. Avec un clavier : espace pour parler, / pour écrire."
                )
                .font(.footnote)
                .foregroundStyle(Color(.texteSecondaire))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

                compte
                    .padding(.top, 22)
                voix
                    .padding(.top, 22)
                confidentialite
                    .padding(.top, 22)

                HStack(alignment: .firstTextBaseline) {
                    Text("Version \(Self.version)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color(.texteSecondaire))
                        .accessibilityIdentifier("version")
                    Spacer(minLength: 12)
                    if let code = URL(string: "https://github.com/markedoe/alfred-app") {
                        Link(destination: code) {
                            Text("Code source")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.faisceau))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                    }
                }
                .padding(.top, 18)
            }
        }
        .onAppear(perform: lireEntrees)
        // comme la console : l'essai du micro s'arrête quand on quitte SYSTÈME (« Test interrompu »)
        .onDisappear { conversation.arreterEssai() }
        .confirmationDialog("Se déconnecter de la maison ?", isPresented: $confirmer, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) {
                Task { await alfred.seDeconnecter() }
            }
        } message: {
            Text("La connexion de cet appareil est supprimée dans Home Assistant. Vous pourrez vous reconnecter.")
        }
    }

    /// « 1.4s » (la console : `dt.toFixed(1) + "s"`).
    static func duree(_ s: Double) -> String { String(format: "%.1fs", locale: Locale(identifier: "en_US_POSIX"), s) }

    static var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    // MARK: - micro

    private func lireEntrees() {
        entrees = conversation.entreesMicro()
        choisie = conversation.entreeMicroChoisie
    }

    /// « Microphone » et la liste des micros (la console : `#mic`, un menu sur toute la largeur).
    private var micro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Microphone").modifier(EtiquetteEtat())
            Menu {
                Picker("Microphone", selection: $choisie) {
                    Text("Micro d’iOS (par défaut)").tag(String?.none)
                    ForEach(entrees) { e in Text(e.nom).tag(Optional(e.uid)) }
                }
            } label: {
                HStack {
                    Text(nomChoisi)
                        .font(.body)
                        .foregroundStyle(Color(.texte))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.texteSecondaire))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Console.bouton, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.acier), lineWidth: 1.5))
                .contentShape(.rect)
            }
            .disabled(conversation.essai == .ouverture || conversation.enConversation)
            .accessibilityLabel("Périphérique d’entrée audio")
            .accessibilityValue(nomChoisi)
            .accessibilityIdentifier("micro")
            .onChange(of: choisie) { _, uid in
                guard uid != conversation.entreeMicroChoisie else { return }
                conversation.choisirEntreeMicro(uid)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.trait)).frame(height: 1).accessibilityHidden(true)
        }
    }

    private var nomChoisi: String {
        entrees.first { $0.uid == choisie }?.nom ?? "Micro d’iOS (par défaut)"
    }

    private var actionsMicro: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { boutonsMicro }
            VStack(alignment: .leading, spacing: 10) { boutonsMicro }
        }
    }

    @ViewBuilder private var boutonsMicro: some View {
        Button(autorise ? "Vérifier l’accès micro" : "Autoriser le micro") {
            Task {
                await conversation.autoriserMicro()
                autorise = true
                lireEntrees()
            }
        }
        .buttonStyle(StyleConsole())
        .largeurDuTexte()
        .disabled(conversation.essai != .arrete || conversation.enConversation)
        .accessibilityIdentifier("autoriserMicro")
        Button(conversation.essai == .arrete ? "Tester le micro" : "Arrêter le test") {
            Task {
                await conversation.basculerEssai()
                lireEntrees()
            }
        }
        .buttonStyle(StyleConsole())
        .largeurDuTexte()
        .disabled(conversation.essai == .ouverture || conversation.enConversation || conversation.phase != .repos)
        // VoiceOver se tait quand le micro s'ouvre (sinon l'essai l'entend, et dit « Signal reçu » à tort)
        .accessibilityAddTraits(conversation.essai == .arrete ? .startsMediaSession : [])
        .accessibilityIdentifier("testerMicro")
    }

    /// Le retour de l'essai (`#mic-feedback`) : ce qui se passe, et la barre du signal.
    private var retourMicro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(conversation.messageEssai)
                .font(.footnote)
                .foregroundStyle(Color(.texteSecondaire))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityValue(
                    conversation.essai == .actif ? "signal \(JaugeEssai.pourcentage(conversation)) %" : ""
                )
                .accessibilityIdentifier("messageMicro")
            JaugeEssai()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Console.caseMesure, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.trait), lineWidth: 1))
    }

    // MARK: - les réglages de l'app

    private var compte: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Compte").titreSection().padding(.bottom, 4)
            LigneEtat("Connecté en tant que", valeur: alfred.moi?.nom ?? "—", mono: false)
            if !alfred.demo, let hote = alfred.configuration?.relais.hote {
                LigneEtat("Maison", valeur: hote)
            }
            // la démo n'a pas de compte : on la quitte, rien à déconnecter
            if alfred.demo {
                Button("Quitter la démonstration") {
                    Task { await alfred.quitterDemo() }
                }
                .buttonStyle(StyleConsole())
                .largeurDuTexte()
                .padding(.top, 12)
            } else {
                Button("Se déconnecter", role: .destructive) { confirmer = true }
                    .buttonStyle(StyleConsole(genre: .alerte))
                    .largeurDuTexte()
                    .padding(.top, 12)
            }
        }
    }

    private var voix: some View {
        @Bindable var conversation = conversation
        return VStack(alignment: .leading, spacing: 8) {
            Text("Voix").titreSection().padding(.bottom, 4)
            Toggle(isOn: $conversation.lireReponsesEcrites) {
                Text("Lire à voix haute les réponses écrites")
                    .font(.callout)
                    .foregroundStyle(Color(.texte))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Color(.faisceau))
            .frame(minHeight: 44)
            Text(
                "Quand vous parlez, Alfred répond à voix haute. Quand vous écrivez, il répond par écrit, sauf si vous activez ce réglage."
            )
            .font(.footnote)
            .foregroundStyle(Color(.texteSecondaire))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confidentialite: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Confidentialité").titreSection().padding(.bottom, 4)
            Engagement("Votre voix ne va que vers votre maison, jamais sur internet.", icone: "house")
            Engagement(
                "Le micro ne s’ouvre que pendant une conversation, et jamais en arrière-plan.", icone: "mic.slash")
            Engagement("La conversation n’est pas gardée sur cet appareil.", icone: "trash")
        }
    }
}

/// La barre du signal de l'essai (`#mic-test-meter`) : sarcelle, lue à chaque image pendant l'essai seulement.
private struct JaugeEssai: View {
    @Environment(Conversation.self) private var conversation
    @Environment(\.animationsCoupees) private var immobile

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: conversation.essai != .actif || immobile)) { _ in
            GeometryReader { g in
                let n = conversation.essai == .actif ? CGFloat(min(1, conversation.niveauEssai * 1.3)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Console.jaugeVide)
                    Capsule().fill(Color(.sarcelle)).frame(width: g.size.width * n)
                }
            }
        }
        .frame(height: 10)
        // une barre de 10 pt n'est pas une cible : le signal est lu avec le message au-dessus
        .accessibilityHidden(true)
    }

    static func pourcentage(_ c: Conversation) -> Int { Int(min(1, c.niveauEssai * 1.3) * 100) }
}

/// Une ligne d'état de la console (`#system .stat`) : libellé en capitales, valeur à droite en chiffres fixes, un trait
/// dessous ; la valeur passe à la ligne si la place manque.
private struct LigneEtat: View {
    let libelle: String
    let valeur: String
    let mono: Bool

    init(_ libelle: String, valeur: String, mono: Bool = true) {
        self.libelle = libelle
        self.valeur = valeur
        self.mono = mono
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(libelle).modifier(EtiquetteEtat())
                Spacer(minLength: 0)
                texteValeur
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(libelle).modifier(EtiquetteEtat())
                texteValeur
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.trait)).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var texteValeur: some View {
        Text(valeur)
            .font(mono ? .subheadline.weight(.semibold).monospaced() : .subheadline.weight(.semibold))
            .foregroundStyle(Color(.texte))
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
    }
}

/// Le libellé d'une ligne d'état : 12 pt, capitales espacées, brume (`.stat .l`).
private struct EtiquetteEtat: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .tracking(0.85)
            .textCase(.uppercase)
            .foregroundStyle(Color(.texteSecondaire))
    }
}

/// Un engagement de confidentialité. Le texte prend toute la hauteur qu'il lui faut, à toutes les tailles.
private struct Engagement: View {
    let texte: LocalizedStringKey
    let icone: String

    init(_ texte: LocalizedStringKey, icone: String) {
        self.texte = texte
        self.icone = icone
    }

    var body: some View {
        Label {
            Text(texte)
                .foregroundStyle(Color(.texte))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icone).foregroundStyle(Color(.faisceau))
        }
        .font(.subheadline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.trait).opacity(0.7)).frame(height: 1).accessibilityHidden(true)
        }
    }
}
