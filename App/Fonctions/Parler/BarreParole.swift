import SwiftUI

/// La barre du bas, sur verre : écrire à Alfred, et le noyau pour lui parler.
/// Pendant une conversation, elle dit ce qu'Alfred fait (« À l'écoute », « Il réfléchit », « Il parle »).
struct BarreParole: View {
    @Environment(Alfred.self) private var alfred
    @Environment(Conversation.self) private var conversation
    @Binding var texte: String
    var saisie: FocusState<Bool>.Binding

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                if conversation.enConversation {
                    Text(etatParole)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.texteSecondaire))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .glassEffect(.regular, in: .capsule)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Écrire à Alfred", text: $texte, axis: .vertical)
                            .lineLimit(1...5)
                            .focused(saisie)
                            .submitLabel(.send)
                            .onSubmit(envoyer)
                            .padding(.vertical, 15)
                            .padding(.leading, 18)
                            .accessibilityIdentifier("saisie")
                        if !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: envoyer) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color(.champagne))
                            }
                            .padding(.bottom, 8)
                            .padding(.trailing, 8)
                            .accessibilityLabel("Envoyer")
                            .accessibilityIdentifier("envoyer")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
                }
                boutonNoyau
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .animation(.smooth(duration: 0.25), value: conversation.enConversation)
        .animation(.smooth(duration: 0.2), value: texte.isEmpty)
    }

    private var boutonNoyau: some View {
        Button {
            saisie.wrappedValue = false
            Task { await conversation.basculerEcoute() }
        } label: {
            Noyau(phase: conversation.phase) {
                conversation.phase == .reponse ? conversation.niveauVoix : conversation.niveauMicro
            }
            .frame(width: 52, height: 52)
            .overlay {
                if conversation.enConversation {
                    Image(systemName: "stop.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color(.fond))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 52, height: 52)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(!pret && !conversation.enConversation)
        .accessibilityLabel(conversation.enConversation ? "Terminer la conversation" : "Parler à Alfred")
        .accessibilityValue(etatParole)
        .accessibilityHint(
            conversation.enConversation ? "" : "Ouvre le micro ; Alfred vous écoute jusqu’à ce que vous terminiez."
        )
        .accessibilityIdentifier("noyau")
    }

    private var pret: Bool {
        if case .pret = alfred.liaison { return true }
        return false
    }

    private var etatParole: String {
        switch conversation.phase {
        case .repos: conversation.enConversation ? "À l’écoute" : "Au repos"
        case .ecoute: "À l’écoute"
        case .reflexion: "Alfred réfléchit"
        case .reponse: "Alfred parle"
        }
    }

    private func envoyer() {
        let t = texte
        texte = ""
        Task { await conversation.ecrire(t) }
    }
}
