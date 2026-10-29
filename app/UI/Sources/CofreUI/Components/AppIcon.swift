import ImageIO
import SwiftUI

/// §2 #17 AppIcon: placeholder chest (`cofre-design/icons/01-vanilla.png`). Decorative.
public struct AppIcon: View {
    let size: CGFloat
    public init(size: CGFloat = 30) { self.size = size }
    /// Decoded once; the rail and sidebar re-render on every store change.
    private static let image: CGImage? = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Images")
        .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }

    public var body: some View {
        Group {
            if let img = Self.image {
                Image(decorative: img, scale: 1).interpolation(.none).resizable()
            } else {
                PixelIcon(.chest, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).stroke(Color.cofre.outline, lineWidth: 2) }
        .accessibilityIgnoresInvertColors()
        .accessibilityHidden(true)
    }
}
