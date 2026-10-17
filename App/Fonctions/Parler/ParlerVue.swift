import AlfredKit
import SwiftUI

/// Parler à Alfred : le fil de la conversation, le noyau, l'écrit.
struct ParlerVue: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @State private var texte = ""
    @State private var reglages = false
    @State private var hauteurVisible: CGFloat = 0
    @FocusState private var saisie: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                if conversation.vide {
                    // centré dans la partie visible quand il y tient ; sinon (grandes tailles de texte), il défile
                    Bienvenue { suggestion in
                        Task { await conversation.ecrire(suggestion) }
                    }
                    .frame(maxWidth: .infinity, minHeight: hauteurVisible)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(conversation.messages) { message in
                            BulleMessage(message: message)
                                .id(message.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .scrollTargetLayout()
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { g in
                g.containerSize.height - g.contentInsets.top - g.contentInsets.bottom
            } action: { _, hauteur in
                hauteurVisible = max(hauteur, 0)
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.fond).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                BarreParole(texte: $texte, saisie: $saisie)
            }
            .overlay(alignment: .top) {
                EtatLiaison()
            }
            .avis(conversation.avis) { conversation.oublierAvis($0) }
            .navigationTitle(conversation.vide ? "" : "Alfred")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await conversation.nouvelle() }
                    } label: {
                        Label("Nouvelle conversation", systemImage: "square.and.pencil")
                    }
                    .disabled(conversation.vide)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    BoutonReglages(ouvert: $reglages)
                }
            }
            .sheet(isPresented: $reglages) { ReglagesVue() }
        }
        .sensoryFeedback(trigger: conversation.enConversation) { _, ouvert in ouvert ? .start : .stop }
        .sensoryFeedback(.success, trigger: conversation.reponses)
    }
}

/// L'écran vide : le noyau, la salutation, quelques idées.
private struct Bienvenue: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    let suggerer: (String) -> Void

    static let suggestions = [
        "Quelle heure est-il ?", "Quel temps fera-t-il demain ?", "Quelles lumières sont allumées ?",
    ]

    var body: some View {
        VStack(spacing: 28) {
            Noyau(phase: conversation.phase) { conversation.niveauMicro }
                .frame(width: 200, height: 200)
            VStack(spacing: 6) {
                Text(Salutation.texte(titre: alfred.moi?.titre, date: .now))
                    .font(.title.bold())
                    .fontDesign(.serif)
                Text(conversation.enConversation ? "Je vous écoute." : "Touchez le noyau, en bas, pour me parler.")
                    .font(.callout)
                    .foregroundStyle(Color(.texteSecondaire))
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            VStack(spacing: 10) {
                ForEach(Self.suggestions, id: \.self) { s in
                    Button(s) { suggerer(s) }
                        .buttonStyle(StyleSuggestion())
                        .disabled(!estPret)
                }
            }
        }
        .padding(24)
    }

    private var estPret: Bool {
        if case .pret = alfred.liaison { return true }
        return false
    }
}

/// « Bonjour, Monsieur. » / « Bonsoir, Madame. »
enum Salutation {
    static func texte(titre: String?, date: Date, calendrier: Calendar = .current) -> String {
        let heure = calendrier.component(.hour, from: date)
        let mot = (5..<18).contains(heure) ? "Bonjour" : "Bonsoir"
        guard let titre, !titre.isEmpty else { return "\(mot)." }
        return "\(mot), \(titre)."
    }
}
