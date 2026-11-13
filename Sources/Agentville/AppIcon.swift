import AgentvilleCore
import AppKit
import ImageIO

/// Draws the app icon: the crowned orange agent on a square of workshop floor, or dressed as
/// a character of the user's choosing.
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
        if let pills = providerPills() {
            let url = folder.appendingPathComponent("Agentville-providers.png")
            try? NSBitmapImageRep(cgImage: pills).representation(using: .png, properties: [:])?.write(to: url)
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

    /// An animated GIF cycling through the icon dressed as characters from each film and TV
    /// world, for the README.
    static func writeGIF(to url: URL, side: Int = 256) {
        let ids = ["default", "starWars:vader", "simpsons:homer", "middleEarth:gandalf", "harryPotter:harry",
                   "starWars:luke", "simpsons:marge", "middleEarth:legolas", "harryPotter:hagrid",
                   "starWars:chewbacca", "simpsons:bart", "middleEarth:gimli", "harryPotter:dumbledore",
                   "northPole:santa"]
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString,
                                                                ids.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for id in ids {
            guard let frame = render(choice: id, side: side) else { continue }
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.1],
            ] as CFDictionary)
        }
        if CGImageDestinationFinalize(destination) { print(url.path) }
    }

    /// The three provider plates from the header's legend, side by side on a clear background,
    /// for use outside the app (the README).
    static func providerPills() -> CGImage? {
        let scale: CGFloat = 3
        let height: CGFloat = 28, logoSide: CGFloat = 17, inset: CGFloat = 9, gap: CGFloat = 7, spacing: CGFloat = 8
        let sources: [AgentSource] = [.claude, .codex, .copilot]
        let names = sources.map { NSAttributedString.label($0.displayName, size: 12.5, weight: .semibold, color: ProviderLogo.ink) }
        let widths = names.map { (inset + logoSide + gap + $0.size().width + inset).rounded(.up) }
        let total = widths.reduce(0, +) + spacing * CGFloat(sources.count - 1)

        guard let context = CGContext(data: nil, width: Int(total * scale), height: Int(height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }

        var x: CGFloat = 0
        for (index, source) in sources.enumerated() {
            let pill = CGRect(x: x, y: 0, width: widths[index], height: height)
            context.addPath(CGPath(roundedRect: pill, cornerWidth: 7, cornerHeight: 7, transform: nil))
            context.setFillColor(PixelArt.providerColor(source).cgColor)
            context.fillPath()
            if let logo = ProviderLogo.texture(for: source)?.cgImage() {
                context.draw(logo, in: CGRect(x: x + inset, y: (height - logoSide) / 2, width: logoSide, height: logoSide))
            }
            let name = names[index]
            name.draw(at: CGPoint(x: x + inset + logoSide + gap, y: (height - name.size().height) / 2))
            x += widths[index] + spacing
        }
        return context.makeImage()
    }

    /// The default mascot: the orange agent in a crown.
    static let classic = PixelArt.Look(hat: .crown)

    /// The characters a user can pick for the app icon: the default crowned agent, then every
    /// named character, each with the film, TV or seasonal theme it comes from.
    static var choices: [(id: String, name: String, theme: Theme?, look: PixelArt.Look)] {
        var all: [(String, String, Theme?, PixelArt.Look)] = [
            ("default", "Crown (default)", nil, classic),
        ]
        for theme in Theme.costumed {
            guard let key = Cast.key(for: theme) else { continue }
            all += Cast.main(key).map { ("\(key):\($0.id)", $0.name, theme, $0.look) }
        }
        return all
    }

    /// The icon for one of `choices`, by id. Unknown ids fall back to the default.
    static func render(choice id: String, style: PixelArt.Style = .smooth, side: Int = 1024) -> CGImage? {
        let choice = choices.first { $0.id == id } ?? choices[0]
        return render(style: style, look: choice.look, theme: choice.theme, side: side)
    }

    private static var thumbnails: [String: NSImage] = [:]

    /// A small rendering of one of `choices`, for the icon picker. Cached, since the picker
    /// shows them all at once.
    static func thumbnail(_ id: String) -> NSImage {
        if let cached = thumbnails[id] { return cached }
        let choice = choices.first { $0.id == id } ?? choices[0]
        let image = render(style: .smooth, look: choice.look, theme: choice.theme, side: 160, cell: 12)
            .map { NSImage(cgImage: $0, size: NSSize(width: 80, height: 80)) } ?? NSImage()
        thumbnails[id] = image
        return image
    }

    static func render(style: PixelArt.Style) -> CGImage? { render(style: style, look: classic, theme: nil) }

    /// The icon: the orange agent in `look`, standing on a tile of `theme`'s floor (the dark
    /// workshop floor when nil).
    static func render(style: PixelArt.Style, look: PixelArt.Look, theme: Theme?, side outSide: Int = 1024,
                       cell mascotCell: Int = 40) -> CGImage? {
        let side = 1024
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: outSide, height: outSide, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(outSide) / CGFloat(side), y: CGFloat(outSide) / CGFloat(side))

        // The standard macOS icon shape: an 824pt rounded square centred in the canvas,
        // leaving room around it for the system's shadow.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
        context.clip()

        // The floor: dark, lighter towards the top, with its faint grid. A film or TV
        // character stands on its own theme's floor colours instead.
        let floorColors: [CGColor] = theme.map { [$0.colors.background.cgColor, $0.colors.panel.cgColor] } ?? [
            CGColor(srgbRed: 0.05, green: 0.055, blue: 0.075, alpha: 1),
            CGColor(srgbRed: 0.11, green: 0.125, blue: 0.17, alpha: 1),
        ]
        let gradient = CGGradient(colorsSpace: space, colors: floorColors as CFArray, locations: [0, 1])!
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

        // The agent and what it carries, centred together on what is actually drawn rather
        // than on the agent's texture, which has empty rows above its hat.
        let mascot = PixelArt.mascot(style: style, look: look, yellow: theme == .simpsons, cell: mascotCell)
        let cell: CGFloat = 34
        let body = CGFloat(PixelArt.agentColumns) * cell
        let gap = cell * 0.5
        let heldWidth = mascot.held.map { CGFloat($0.columns) * cell + gap } ?? 0
        let width = body + heldWidth
        let height = CGFloat(mascot.rows) * cell
        let heldTop = mascot.held.map { mascot.hand - $0.grip } ?? mascot.emptyRowsOnTop
        let firstRow = min(mascot.emptyRowsOnTop, max(0, heldTop))
        let visible = CGFloat(mascot.rows - firstRow) * cell
        let bottom = 512 - visible / 2 - 8
        let left = 512 - width / 2

        // A soft shadow on the floor under its feet.
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.fillEllipse(in: CGRect(x: left + body * 0.08, y: bottom - 26, width: width - body * 0.16, height: 52))

        context.interpolationQuality = style == .pixel ? .none : .high
        context.draw(mascot.image, in: CGRect(x: left, y: bottom, width: body, height: height))
        if let held = mascot.held {
            // Standing at its right hand: the item's grip row level with the hand.
            let heldHeight = CGFloat(held.rows) * cell
            let topY = bottom + height - CGFloat(mascot.hand - held.grip) * cell
            context.draw(held.image, in: CGRect(x: left + body + gap, y: topY - heldHeight,
                                                width: CGFloat(held.columns) * cell, height: heldHeight))
        }
        return context.makeImage()
    }
}
