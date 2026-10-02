import AppKit

/// Draws the app icon: the crowned orange agent on a square of workshop floor.
enum AppIcon {
    /// Writes a 1024×1024 PNG for each art style into `folder`.
    static func write(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for style in [PixelArt.Style.smooth, .pixel] {
            guard let image = render(style: style) else { continue }
            let url = folder.appendingPathComponent("Agentville-icon-\(style.rawValue).png")
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            print(url.path)
        }
        // The menu bar icon too, enlarged on white, so it can be looked at.
        let icon = PixelArt.menuBarIcon()
        var rect = CGRect(origin: .zero, size: icon.size)
        if let small = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
           let context = CGContext(data: nil, width: small.width * 4 + 80, height: small.height * 4 + 80,
                                   bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
            context.interpolationQuality = .none
            context.draw(small, in: CGRect(x: 40, y: 40, width: small.width * 4, height: small.height * 4))
            let url = folder.appendingPathComponent("Agentville-menubar-preview.png")
            if let image = context.makeImage() {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
                print(url.path)
            }
        }
    }

    static func render(style: PixelArt.Style) -> CGImage? {
        let side = 1024
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // The standard macOS icon shape: an 824pt rounded square centred in the canvas,
        // leaving room around it for the system's shadow.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
        context.clip()

        // The workshop floor: dark, lighter towards the top, with its faint grid.
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.05, green: 0.055, blue: 0.075, alpha: 1),
            CGColor(srgbRed: 0.11, green: 0.125, blue: 0.17, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.045))
        context.setLineWidth(3)
        for offset in stride(from: CGFloat(0), through: tile.width, by: 103) {
            context.move(to: CGPoint(x: tile.minX + offset, y: tile.minY))
            context.addLine(to: CGPoint(x: tile.minX + offset, y: tile.maxY))
            context.move(to: CGPoint(x: tile.minX, y: tile.minY + offset))
            context.addLine(to: CGPoint(x: tile.maxX, y: tile.minY + offset))
        }
        context.strokePath()

        // A warm glow behind the agent, in its own orange.
        let glow = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.94, green: 0.54, blue: 0.24, alpha: 0.30),
            CGColor(srgbRed: 0.94, green: 0.54, blue: 0.24, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
                                   endCenter: CGPoint(x: 512, y: 500), endRadius: 420, options: [])

        // The agent, centred on what is actually drawn rather than on its texture, which has
        // empty rows above the crown.
        let mascot = PixelArt.mascot(style: style)
        let cell: CGFloat = 36
        let width = CGFloat(PixelArt.agentColumns) * cell
        let height = CGFloat(mascot.rows) * cell
        let visible = CGFloat(mascot.rows - mascot.emptyRowsOnTop) * cell
        let bottom = 512 - visible / 2 - 8

        // A soft shadow on the floor under its feet.
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.fillEllipse(in: CGRect(x: 512 - width * 0.42, y: bottom - 26, width: width * 0.84, height: 52))

        context.interpolationQuality = style == .pixel ? .none : .high
        context.draw(mascot.image, in: CGRect(x: 512 - width / 2, y: bottom, width: width, height: height))
        return context.makeImage()
    }
}
