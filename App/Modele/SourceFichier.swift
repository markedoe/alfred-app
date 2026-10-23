import Foundation

/// 23.10 (soir) : d'où lire un fichier de « À envoyer » au moment de l'envoi — ses octets (photo convertie, document
/// numérisé, image convertie en JPEG), ou le fichier choisi (lu à l'envoi, l'accès accordé le temps de la lecture).
enum SourceFichier: Sendable, Equatable {
    case donnees(Data)
    case fichier(URL)

    func lire() -> Data? {
        switch self {
        case .donnees(let d):
            return d
        case .fichier(let url):
            let accede = url.startAccessingSecurityScopedResource()
            defer { if accede { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }
    }
}
