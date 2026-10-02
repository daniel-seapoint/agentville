import AgentvilleCore
import SpriteKit

/// The providers' own logo marks, redrawn in one ink colour so they sit on a coloured badge.
/// The files live in `Resources/Logos`; each is a trademark of its owner.
enum ProviderLogo {
    /// The dark colour used for badge text and marks.
    static let ink = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)

    private static var cache: [AgentSource: SKTexture] = [:]
    private static let pixels = 128

    static func texture(for source: AgentSource) -> SKTexture? {
        if let cached = cache[source] { return cached }
        let file: (name: String, ext: String, keyOutWhite: Bool)
        switch source {
        case .claude: file = ("claude", "svg", false)
        case .codex: file = ("codex", "svg", false)
        // The Copilot mark is a dark outline around opaque white, so white has to become clear.
        case .copilot: file = ("copilot", "png", true)
        }
        guard let url = locate(file.name, file.ext), let image = NSImage(contentsOf: url),
              let mark = inked(image, keyOutWhite: file.keyOutWhite) else { return nil }
        let texture = SKTexture(cgImage: mark)
        cache[source] = texture
        return texture
    }

    /// The same mark for SwiftUI views.
    static func image(for source: AgentSource, side: CGFloat) -> NSImage? {
        texture(for: source).map { NSImage(cgImage: $0.cgImage(), size: NSSize(width: side, height: side)) }
    }

    /// In the app bundle the logos are in `Contents/Resources`; under `swift run` they are in
    /// the package's resource bundle.
    private static func locate(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Logos")
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Logos")
    }

    /// Rasterises the image and repaints every pixel in `ink`, keeping only its coverage.
    private static func inked(_ image: NSImage, keyOutWhite: Bool) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: pixels * pixels * 4)
        let inkRGB = [ink.redComponent, ink.greenComponent, ink.blueComponent]
        var minX = pixels, minY = pixels, maxX = -1, maxY = -1
        for offset in stride(from: 0, to: pixels * pixels * 4, by: 4) {
            var coverage = CGFloat(buffer[offset + 3]) / 255
            if keyOutWhite, coverage > 0 {
                // Premultiplied, so dividing by alpha recovers the colour. Lighter means clearer.
                let brightness = (CGFloat(buffer[offset]) + CGFloat(buffer[offset + 1]) + CGFloat(buffer[offset + 2]))
                    / (3 * 255 * coverage)
                coverage *= 1 - min(brightness, 1)
            }
            for channel in 0..<3 {
                buffer[offset + channel] = UInt8((inkRGB[channel] * coverage * 255).rounded())
            }
            buffer[offset + 3] = UInt8((coverage * 255).rounded())
            if coverage > 0.05 {
                let x = (offset / 4) % pixels, y = (offset / 4) / pixels
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, let image = context.makeImage() else { return nil }

        // Some files pad the mark generously. Crop to a square around what was actually drawn
        // so every logo fills its slot in the badge.
        let side = max(maxX - minX, maxY - minY) + 1
        let originX = max(0, min(pixels - side, (minX + maxX + 1 - side) / 2))
        let originY = max(0, min(pixels - side, (minY + maxY + 1 - side) / 2))
        return image.cropping(to: CGRect(x: originX, y: originY, width: side, height: side))
    }
}
