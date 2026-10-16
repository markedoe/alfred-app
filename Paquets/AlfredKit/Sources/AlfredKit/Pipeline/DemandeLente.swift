import Foundation

/// Les demandes lentes (recherche sur le web, recette, actualités, Claude) ne répondent qu'à la fin : 4 à 10 s de
/// silence. Dès la transcription, l'app joue un court clip d'accueil avec la voix d'Alfred (« Bien, Monsieur »),
/// coupé dès que la vraie réponse arrive. Même règle que la console (`SLOW_RE`).
public enum DemandeLente {
    private static let motif = try! NSRegularExpression(
        pattern:
            #"^\s*(?:(?:bonjour|salut|dis|hé|ok)\s+)?(?:alfred[,\s]+)?(?:cherches?\b|recette (?:de|du|des|d')\b|actualit[ée]s?\b|demande[sz]? (?:à|a) claude\b)"#,
        options: [.caseInsensitive])

    public static func estLente(_ texte: String) -> Bool {
        motif.firstMatch(in: texte, range: NSRange(texte.startIndex..., in: texte)) != nil
    }
}

/// Les clips préenregistrés d'Alfred (`/static/ack/` du relais), selon le titre de la personne connectée (`/moi`).
public enum ClipsAlfred {
    public static let nombreAccueils = 6

    /// « Monsieur » = clips d'origine ; « Madame », « Mademoiselle » ; titre vide = clips neutres (invité).
    /// Un titre inconnu garde les clips d'origine, comme la console.
    public static func suffixe(titre: String?) -> String {
        switch titre {
        case "Madame": "-madame"
        case "Mademoiselle": "-mademoiselle"
        case "": "-neutre"
        default: ""
        }
    }

    public static func accueil(_ n: Int, titre: String?) -> String {
        "/static/ack/ack-\(n)\(suffixe(titre: titre)).mp3"
    }

    /// Un numéro au hasard, jamais deux fois le même de suite.
    public static func prochainAccueil(apres dernier: Int, tirage: Int) -> Int {
        let n = 1 + ((tirage % nombreAccueils) + nombreAccueils) % nombreAccueils
        return n == dernier ? 1 + (n % nombreAccueils) : n
    }
}
