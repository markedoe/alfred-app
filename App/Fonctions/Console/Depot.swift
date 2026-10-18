import AlfredKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// « Déposer un document » (`#docs-drop`) : comme le champ de fichier de la console dans Safari sur iPhone, trois
/// sources — la photothèque, l'appareil photo (ici le scanner de documents d'iOS, qui rend un PDF) et les fichiers.
/// Le relais accepte PDF, JPEG, PNG, WebP, texte et e-mail : une photo HEIC part en JPEG, comme Safari l'envoie.
struct Depot: View {
    @Environment(Alfred.self) private var alfred
    let jour: Date?
    @State private var photos = false
    @State private var photo: PhotosPickerItem?
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
        .photosPicker(isPresented: $photos, selection: $photo, matching: .images, preferredItemEncoding: .compatible)
        .fileImporter(isPresented: $fichiers, allowedContentTypes: Self.types) { resultat in
            if case .success(let url) = resultat { Task { await deposer(fichier: url) } }
        }
        .fullScreenCover(isPresented: $scanner) {
            Scanner { pages in
                scanner = false
                Task { await deposer(scan: pages) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photo) { _, element in
            guard let element else { return }
            photo = nil
            Task { await deposer(photo: element) }
        }
    }

    private var zone: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Déposer un document")
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

    // MARK: - les trois sources

    private func deposer(photo element: PhotosPickerItem) async {
        guard let donnees = try? await element.loadTransferable(type: Data.self),
            let jpeg = UIImage(data: donnees)?.jpegData(compressionQuality: 0.9)
        else {
            alfred.conversation.aviser("Cette photo n’a pas pu être lue.", .attention)
            return
        }
        await envoyer(jpeg, nom: "Photo \(Self.horodatage()).jpg", type: "image/jpeg")
    }

    private func deposer(fichier url: URL) async {
        let accede = url.startAccessingSecurityScopedResource()
        defer { if accede { url.stopAccessingSecurityScopedResource() } }
        // la taille d'abord : un fichier trop lourd n'est pas lu en mémoire
        if let taille = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, taille > DepotDocument.tailleMax {
            alfred.conversation.aviser("Document trop lourd : 20 Mo au plus.", .attention)
            return
        }
        guard let donnees = try? Data(contentsOf: url) else {
            alfred.conversation.aviser("Ce fichier n’a pas pu être lu.", .attention)
            return
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        // une image que le relais ne lit pas (HEIC, TIFF…) part en JPEG, sous le même nom
        if type.conforms(to: .image), ![UTType.jpeg, .png, .webP].contains(where: { type.conforms(to: $0) }) {
            guard let jpeg = UIImage(data: donnees)?.jpegData(compressionQuality: 0.9) else {
                alfred.conversation.aviser("Cette image n’a pas pu être lue.", .attention)
                return
            }
            let nom = url.deletingPathExtension().lastPathComponent + ".jpg"
            await envoyer(jpeg, nom: nom, type: "image/jpeg")
            return
        }
        let mime =
            type.conforms(to: .emailMessage) ? "message/rfc822" : type.preferredMIMEType ?? "application/octet-stream"
        await envoyer(donnees, nom: url.lastPathComponent, type: mime)
    }

    private func deposer(scan pages: [UIImage]) async {
        guard !pages.isEmpty else { return }
        await envoyer(Self.pdf(pages), nom: "Document numérisé \(Self.horodatage()).pdf", type: "application/pdf")
    }

    private func envoyer(_ donnees: Data, nom: String, type: String) async {
        let pourLe = jour.map { Self.format("yyyy-MM-dd", $0) }
        await alfred.annexes?.deposer(DepotDocument(fichier: donnees, nomFichier: nom, type: type, pourLe: pourLe))
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
