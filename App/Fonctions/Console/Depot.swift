import AlfredKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// « Ajouter des documents » (`#docs-drop`) : comme le champ de fichier de la console dans Safari sur iPhone, trois
/// sources — la photothèque, l'appareil photo (ici le scanner de documents d'iOS, qui rend un PDF) et les fichiers.
/// Le relais accepte PDF, JPEG, PNG, WebP, texte et e-mail : une photo HEIC part en JPEG, comme Safari l'envoie.
/// 23.10 (retour d’essai : un seul document à la fois, et des documents qui restaient affichés) : photothèque et
/// fichiers en sélection MULTIPLE ; chaque fichier part à son tour (une requête chacun, comme la console), « Pour le »
/// vaut pour le lot. Le scanner reste un document de plusieurs pages (un PDF).
/// 23.10 (soir, retour d'essai : « ajouter les docs, choisir le tag et cliquer sur envoyer ») : rien ne part d'ici —
/// chaque fichier choisi rejoint « À envoyer » (son nom, sa taille ; refusé d'emblée s'il est trop lourd ou d'un type
/// que le relais refuserait, reconnu à ses premiers octets) ; « Envoyer à Paperless » envoie le lot.
struct Depot: View {
    @Environment(Alfred.self) private var alfred
    @State private var photos = false
    @State private var photosChoisies: [PhotosPickerItem] = []
    @State private var fichiers = false
    @State private var scanner = false

    var body: some View {
        Menu {
            Button {
                photos = true
            } label: {
                Label("Photothèque", systemImage: "photo.on.rectangle")
            }
            if VNDocumentCameraViewController.isSupported {
                Button {
                    scanner = true
                } label: {
                    Label("Numériser un document", systemImage: "doc.viewfinder")
                }
            }
            Button {
                fichiers = true
            } label: {
                Label("Choisir un fichier", systemImage: "folder")
            }
        } label: {
            zone
        }
        .menuOrder(.fixed)
        .disabled(alfred.annexes?.envoiEnCours == true)
        .accessibilityIdentifier("deposer")
        // 23.10 : photosPicker(isPresented:selection:maxSelectionCount:selectionBehavior:matching:preferredItemEncoding:)
        // et fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:) → Result<[URL], any Error>
        // (déclarations relues dans la documentation d'Apple ; « selectionBehavior » garde sa valeur par défaut)
        .photosPicker(
            isPresented: $photos, selection: $photosChoisies, maxSelectionCount: Self.maxPhotos, matching: .images,
            preferredItemEncoding: .compatible
        )
        .fileImporter(isPresented: $fichiers, allowedContentTypes: Self.types, allowsMultipleSelection: true) {
            resultat in
            if case .success(let urls) = resultat, !urls.isEmpty { ajouter(fichiers: urls) }
        }
        .fullScreenCover(isPresented: $scanner) {
            Scanner { pages in
                scanner = false
                ajouter(scan: pages)
            }
            .ignoresSafeArea()
            // comme les fenêtres de la console : l'environnement redonné à la présentation (Mac, 23.10)
            .environment(alfred)
        }
        .onChange(of: photosChoisies) { _, elements in
            guard !elements.isEmpty else { return }
            photosChoisies = []
            Task { await ajouter(photos: elements) }
        }
    }

    private var zone: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ajouter des documents")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color(.glace))
            Text(
                "Offre, devis, facture ou courrier, en PDF ou en photo. Il reste à la maison ; Claude ne le voit que si vous le lui demandez."
            )
            .font(.caption)
            .foregroundStyle(Color(.texteSecondaire))
            .lineSpacing(1)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 14 / 255, green: 34 / 255, blue: 51 / 255), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(.faisceauSombre), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(.rect)
    }

    static let types: [UTType] = [.pdf, .image, .plainText, .emailMessage]
    /// 23.10 : au plus 20 photos d'un coup (chacune convertie en JPEG au choix, envoyée à son tour).
    static let maxPhotos = 20

    // MARK: - les trois sources

    /// Les photos choisies : chacune lue et convertie en JPEG (comme Safari l'envoie), puis dans « À envoyer ».
    private func ajouter(photos elements: [PhotosPickerItem]) async {
        // un même horodatage (à la minute) pour tout le choix : le numéro distingue les photos (« Photo … 2.jpg »)
        let horodatage = Self.horodatage()
        for (rang, element) in elements.enumerated() {
            guard let donnees = try? await element.loadTransferable(type: Data.self),
                let jpeg = UIImage(data: donnees)?.jpegData(compressionQuality: 0.9)
            else {
                alfred.annexes?.signaler("Cette photo n’a pas pu être lue.")
                continue
            }
            let suffixe = elements.count > 1 ? " \(rang + 1)" : ""
            ajouter(jpeg, nom: "Photo \(horodatage)\(suffixe).jpg", type: "image/jpeg")
        }
    }

    private func ajouter(fichiers urls: [URL]) {
        for url in urls { ajouter(fichier: url) }
    }

    /// Un fichier choisi : sa taille et ses premiers octets (accès accordé le temps de la lecture) ; il sera lu en
    /// entier à l'envoi. Une image que le relais ne lit pas (HEIC, TIFF…) est convertie en JPEG tout de suite, sous le
    /// même nom ; un fichier trop lourd n'est jamais lu (sa ligne dit « Refusé : trop lourd »).
    private func ajouter(fichier url: URL) {
        let accede = url.startAccessingSecurityScopedResource()
        defer { if accede { url.stopAccessingSecurityScopedResource() } }
        let nom = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let taille = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if taille > DepotDocument.tailleMax {
            alfred.annexes?.ajouter(
                FichierAEnvoyer(nom: nom, octets: taille, entete: Data()), source: .fichier(url))
            return
        }
        if type.conforms(to: .image), ![UTType.jpeg, .png, .webP].contains(where: { type.conforms(to: $0) }) {
            guard let donnees = try? Data(contentsOf: url),
                let jpeg = UIImage(data: donnees)?.jpegData(compressionQuality: 0.9)
            else {
                alfred.annexes?.signaler("Cette image n’a pas pu être lue.")
                return
            }
            ajouter(jpeg, nom: url.deletingPathExtension().lastPathComponent + ".jpg", type: "image/jpeg")
            return
        }
        guard let lecteur = try? FileHandle(forReadingFrom: url) else {
            alfred.annexes?.signaler("Ce fichier n’a pas pu être lu.")
            return
        }
        let entete = (try? lecteur.read(upToCount: 16)) ?? Data()
        try? lecteur.close()
        let mime =
            type.conforms(to: .emailMessage) ? "message/rfc822" : type.preferredMIMEType ?? "application/octet-stream"
        alfred.annexes?.ajouter(
            FichierAEnvoyer(nom: nom, octets: taille, entete: entete, typeDeclare: mime), source: .fichier(url))
    }

    private func ajouter(scan pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        ajouter(Self.pdf(pages), nom: "Document numérisé \(Self.horodatage()).pdf", type: "application/pdf")
    }

    /// Des octets prêts (photo, image convertie, document numérisé) : dans « À envoyer ».
    private func ajouter(_ donnees: Data, nom: String, type: String) {
        alfred.annexes?.ajouter(
            FichierAEnvoyer(nom: nom, octets: donnees.count, entete: donnees.prefix(16), typeDeclare: type),
            source: .donnees(donnees))
    }

    /// « 2026-10-18 1405 » : le nom d'une photo ou d'un document numérisé (heure de l'appareil).
    static func horodatage(_ d: Date = .now) -> String { format("yyyy-MM-dd HHmm", d) }

    /// Une date au format fixe, dans le fuseau de l'appareil (jamais en UTC : le jour choisi reste ce jour-là).
    static func format(_ modele: String, _ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = modele
        return f.string(from: d)
    }

    /// Les pages numérisées en un PDF : une page par image, à 200 points par pouce au plus (lisible, et léger par le VPN).
    static func pdf(_ pages: [UIImage]) -> Data {
        let largeurMax: CGFloat = 1700
        let rendu = UIGraphicsPDFRenderer(bounds: .zero)
        return rendu.pdfData { contexte in
            for page in pages {
                let k = min(1, largeurMax / max(page.size.width, page.size.height))
                let cadre = CGRect(
                    origin: .zero, size: CGSize(width: page.size.width * k, height: page.size.height * k))
                contexte.beginPage(withBounds: cadre, pageInfo: [:])
                // en JPEG dans le PDF (une photo de page, pas un dessin)
                let image = page.jpegData(compressionQuality: 0.7).flatMap(UIImage.init(data:)) ?? page
                image.draw(in: cadre)
            }
        }
    }
}

/// Le scanner de documents d'iOS (VisionKit) : rend les pages numérisées, ou rien si on annule.
private struct Scanner: UIViewControllerRepresentable {
    let fin: @MainActor ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let v = VNDocumentCameraViewController()
        v.delegate = context.coordinator
        return v
    }

    func updateUIViewController(_ v: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(fin: fin) }

    /// Le délégué de VisionKit n'est pas isolé (déclaration d'Apple) mais le scanner, un contrôleur de vue d'UIKit,
    /// l'appelle sur le fil principal : les pages sont lues ici, puis remises à l'app sur l'acteur principal.
    @MainActor
    final class Coordinateur: NSObject, VNDocumentCameraViewControllerDelegate {
        let fin: @MainActor ([UIImage]) -> Void
        init(fin: @escaping @MainActor ([UIImage]) -> Void) { self.fin = fin }

        nonisolated func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            MainActor.assumeIsolated { fin(pages) }
        }

        nonisolated func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            MainActor.assumeIsolated { fin([]) }
        }

        nonisolated func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
        ) {
            MainActor.assumeIsolated { fin([]) }
        }
    }
}
