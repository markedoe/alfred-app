import SwiftUI
import Testing

@testable import Alfred

/// L'en-tête du téléphone : les boutons Documents et Notifications, dessinés pour de vrai (ImageRenderer).
@MainActor
@Suite("En-tête")
struct EnTeteTests {
    /// Le rectangle (en points) des pixels dessinés d'une vue posée dans une cible de 44 × 44 sur fond transparent.
    static func dessine(_ vue: some View) throws -> CGRect {
        let echelle: CGFloat = 3
        let rendu = ImageRenderer(content: vue.frame(width: 44, height: 44))
        rendu.scale = echelle
        rendu.isOpaque = false
        let image = try #require(rendu.cgImage)
        let l = image.width
        let h = image.height
        var octets = [UInt8](repeating: 0, count: l * h * 4)
        let contexte = try #require(
            CGContext(
                data: &octets, width: l, height: h, bitsPerComponent: 8, bytesPerRow: l * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        contexte.draw(image, in: CGRect(x: 0, y: 0, width: l, height: h))
        var x0 = l
        var y0 = h
        var x1 = -1
        var y1 = -1
        for y in 0..<h {
            for x in 0..<l where octets[(y * l + x) * 4 + 3] > 24 {
                x0 = min(x0, x)
                x1 = max(x1, x)
                y0 = min(y0, y)
                y1 = max(y1, y)
            }
        }
        return CGRect(
            x: CGFloat(x0) / echelle, y: CGFloat(y0) / echelle,
            width: CGFloat(x1 - x0 + 1) / echelle, height: CGFloat(y1 - y0 + 1) / echelle)
    }

    /// 22.10 (retour d’essai : les compteurs dépassaient du bouton) : le compteur se pose sur le coin de l'icône,
    /// et rien ne sort du cadre de 38 × 34 du bouton (à un demi-point près, l'anticrénelage).
    @Test("Téléphone : icône et compteur restent dans le cadre du bouton", arguments: [0, 1, 12, 99, 999])
    func compteurDansLeCadre(nombre: Int) throws {
        let bouton = BoutonFenetre(
            titre: "Notifications", icone: "bell", texte: false, nombre: nombre, fondCompteur: .orange,
            texteCompteur: .black, libelle: "Notifications", action: {})
        let dessin = try Self.dessine(bouton)
        let cadre = CGRect(
            x: (44 - BoutonFenetre.cadre.width) / 2, y: (44 - BoutonFenetre.cadre.height) / 2,
            width: BoutonFenetre.cadre.width, height: BoutonFenetre.cadre.height)
        #expect(cadre.insetBy(dx: -0.5, dy: -0.5).contains(dessin), "dessiné \(dessin), cadre \(cadre)")
        #expect(dessin.height <= 34.5, "même hauteur que les boutons-icônes de l'en-tête")
    }
}
