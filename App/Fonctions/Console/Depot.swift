import AlfredKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// « Déposer un document » (`#docs-drop`) : comme le champ de fichier de la console dans Safari sur iPhone, trois
/// sources — la photothèque, l'appareil photo (ici le scanner de documents d'iOS, qui rend un PDF) et les fichiers.
/// Le relais accepte PDF, JPEG, PNG, WebP, texte et e-mail : une photo HEIC part en JPEG, comme Safari l'envoie.
/// 23.10 (retour d’essai : un seul document à la fois, et des documents qui restaient affichés) : photothèque et
/// fichiers en sélection MULTIPLE ; chaque fichier part à son tour (une requête chacun, comme la console), « Pour le »
/// vaut pour le lot. Le scanner reste un document de plusieurs pages (un PDF).
struct Depot: View {
    @Environment(Alfred.self) private var alfred
    let jour: Date?
    /// 23.10 : les étiquettes choisies (les mêmes pour tout le lot), vidées une fois le lot envoyé.
    @Binding var etiquettes: [ChoixEtiquette]
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
            if case .success(let urls) = resultat, !urls.isEmpty { Task { await deposer(fichiers: urls) } }
        }
        .fullScreenCover(isPresented: $scanner) {
            Scanner { pages in
                scanner = false
                Task { await deposer(scan: pages) }
            }
            .ignoresSafeArea()
            // comme les fenêtres de la console : l'environnement redonné à la présentation (Mac, 23.10)
            .environment(alfred)
        }
        .onChange(of: photosChoisies) { _, elements in
            guard !elements.isEmpty else { return }
            photosChoisies = []
            Task { await deposer(photos: elements) }
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
    /// 23.10 : au plus 20 photos d'un coup (chacune lue puis envoyée à son tour, par le VPN au besoin).
    static let maxPhotos = 20

    // MARK: - les trois sources

    /// Le lot : « Pour le » et les étiquettes lus UNE fois, au choix (les changer pendant l'envoi ne touche pas ce
    /// lot) ; les étiquettes sont vidées ensuite, si personne ne les a changées entre-temps (« Pour le » reste).
    private func envoyerLot(
        _ total: Int, _ preparer: @MainActor (LotDepot, Int) async -> DepotDocument?
    ) async {
        let choisies = etiquettes
        let lot = LotDepot(
            pourLe: jour.map { Self.format("yyyy-MM-dd", $0) }, total: total, etiquettes: choisies.map(\.valeur))
        await alfred.annexes?.deposer(lot: lot) { rang in await preparer(lot, rang) }
        if etiquettes == choisies { etiquettes = [] }
    }

    private func deposer(photos elements: [PhotosPickerItem]) async {
        // un même horodatage (à la minute) pour tout le lot : le numéro distingue les photos (« Photo … 2.jpg »)
        let horodatage = Self.horodatage()
        await envoyerLot(elements.count) { lot, rang in
            guard let donnees = try? await elements[rang].loadTransferable(type: Data.self),
                let jpeg = UIImage(data: donnees)?.jpegData(compressionQuality: 0.9)
            else {
                alfred.annexes?.signaler("Cette photo n’a pas pu être lue.")
                return nil
            }
            let suffixe = elements.count > 1 ? " \(rang + 1)" : ""
            return lot.depot(fichier: jpeg, nomFichier: "Photo \(horodatage)\(suffixe).jpg", type: "image/jpeg")
        }
    }

    private func deposer(fichiers urls: [URL]) async {
        await envoyerLot(urls.count) { lot, rang in preparer(fichier: urls[rang], lot: lot) }
    }

    /// Un fichier choisi : lu (accès accordé le temps de la lecture), une image que le relais ne lit pas convertie ;
    /// nil s'il est illisible ou trop lourd (déjà signalé).
    private func preparer(fichier url: URL, lot: LotDepot) -> DepotDocument? {
        let accede = url.startAccessingSecurityScopedResource()
        defer { if accede { url.stopAccessingSecurityScopedResource() } }
        // la taille d'abord : un fichier trop lourd n'est pas lu en mémoire (23.10 : une carte « Refusé »)
        if let taille = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, taille > DepotDocument.tailleMax {
            alfred.annexes?.refuserLocalement(RefusLocal(nom: url.lastPathComponent, motif: .taille))
            return nil
        }
        guard let donnees = try? Data(contentsOf: url) else {
            alfred.annexes?.signaler("Ce fichier n’a pas pu être lu.")
            return nil
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        // une image que le relais ne lit pas (HEIC, TIFF…) part en JPEG, sous le même nom
        if type.conforms(to: .image), ![UTType.jpeg, .png, .webP].contains(where: { type.conforms(to: $0) }) {
            guard let jpeg = UIImage(data: donnees)?.jpegData(compressionQuality: 0.9) else {
                alfred.annexes?.signaler("Cette image n’a pas pu être lue.")
                return nil
            }
            let nom = url.deletingPathExtension().lastPathComponent + ".jpg"
            return lot.depot(fichier: jpeg, nomFichier: nom, type: "image/jpeg")
        }
        let mime =
            type.conforms(to: .emailMessage) ? "message/rfc822" : type.preferredMIMEType ?? "application/octet-stream"
        return lot.depot(fichier: donnees, nomFichier: url.lastPathComponent, type: mime)
    }

    private func deposer(scan pages: [UIImage]) async {
        guard !pages.isEmpty else { return }
        let pdf = Self.pdf(pages)
        let nom = "Document numérisé \(Self.horodatage()).pdf"
        await envoyerLot(1) { lot, _ in lot.depot(fichier: pdf, nomFichier: nom, type: "application/pdf") }
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
