import SwiftUI

/// Un message : le vôtre à droite (bulle champagne), celui d'Alfred à gauche (texte libre, ses actions dessous).
/// Le contenu reste du contenu : pas de verre ici (le verre est réservé aux commandes).
struct BulleMessage: View {
    let message: Conversation.Message

    var body: some View {
        switch message.auteur {
        case .moi:
            HStack {
                Spacer(minLength: 48)
                Text(message.texte)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.champagne).opacity(0.18), in: .rect(cornerRadius: 20, style: .continuous))
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Vous : \(message.texte)")
        case .alfred:
            VStack(alignment: .leading, spacing: 10) {
                if !message.outils.isEmpty {
                    FlowOutils(outils: message.outils)
                }
                if message.texte.isEmpty, message.enCours {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .foregroundStyle(Color(.sodium))
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .accessibilityLabel("Alfred réfléchit")
                } else if message.erreur {
                    Label(message.texte, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color(.alerte))
                } else {
                    Text(message.texte)
                        .textSelection(.enabled)
                        .contentTransition(.opacity)
                }
                if message.comprisLocalement, !message.enCours {
                    Text("Compris par la maison, sans le modèle")
                        .font(.caption)
                        .foregroundStyle(Color(.texteSecondaire))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Ce qu'Alfred a fait, en petites étiquettes : en cours, fait, échoué.
private struct FlowOutils: View {
    let outils: [Conversation.Outil]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { etiquettes }
            VStack(alignment: .leading, spacing: 6) { etiquettes }
        }
    }

    @ViewBuilder private var etiquettes: some View {
        ForEach(outils) { o in
            HStack(spacing: 6) {
                switch o.etat {
                case .enCours: ProgressView().controlSize(.mini)
                case .fait: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(.sarcelle))
                case .echec: Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.alerte))
                }
                Text(o.libelle)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.surface), in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.trait), lineWidth: 0.5))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.description(o))
        }
    }

    private static func description(_ o: Conversation.Outil) -> String {
        switch o.etat {
        case .enCours: "\(o.libelle), en cours"
        case .fait: "\(o.libelle), fait"
        case .echec: "\(o.libelle), échec"
        }
    }
}
