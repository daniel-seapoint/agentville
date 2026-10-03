import AgentvilleCore
import AppKit

/// A sheet of every way an agent can look: each hat, accessory, pattern, colour and thing to
/// carry, the costumes of the storybook themes, and the cast drawn in each art style. Drawn
/// offscreen, for the README.
enum Wardrobe {
    private struct Item {
        var label: String
        var source: AgentSource
        var color: Int
        var look: PixelArt.Look
        var style: PixelArt.Style = .smooth
    }

    /// Points per map cell, and the slot each agent gets.
    private static let cell: CGFloat = 4
    private static let slotWidth: CGFloat = 80
    private static let slotHeight: CGFloat = 112
    private static let columns = 12
    private static let margin: CGFloat = 28
    private static let titleHeight: CGFloat = 30
    /// Space above each section's title after the first.
    private static let sectionGap: CGFloat = 26
    private static let scale: CGFloat = 2

    static func write(to url: URL) {
        guard let image = render(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        print(url.path)
    }

    /// "topHat" becomes "Top hat".
    private static func name(_ value: Any) -> String {
        var words = ""
        for character in String(describing: value) {
            if character.isUppercase { words += " " + character.lowercased() } else { words.append(character) }
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static var sections: [(title: String, items: [Item])] {
        let sources: [AgentSource] = [.claude, .codex, .copilot]
        let hats = PixelArt.Hat.allCases.enumerated().map { index, hat in
            Item(label: name(hat), source: sources[index % 3], color: index, look: PixelArt.Look(hat: hat))
        }
        let accessories = PixelArt.Accessory.allCases.enumerated().map { index, accessory in
            Item(label: name(accessory), source: sources[(index + 1) % 3], color: index + 3,
                 look: PixelArt.Look(accessories: [accessory]))
        }
        let patterns = PixelArt.Pattern.allCases.enumerated().map { index, pattern in
            Item(label: name(pattern), source: sources[index % 3], color: index * 3 + 1,
                 look: PixelArt.Look(pattern: pattern))
        }
        let carried = PixelArt.Held.allCases.enumerated().map { index, held in
            Item(label: name(held), source: sources[index % 3], color: index + 5, look: PixelArt.Look(held: held))
        }
        // Three agents from each storybook theme, in the costume that theme dresses them in.
        let costumed: [(Theme, [String])] = [
            (.hyperspace, ["demo:1", "demo:2", "demo:5"]), (.spellhall, ["demo:1", "demo:3", "demo:4"]),
            (.hearthland, ["demo:2", "demo:4", "demo:5"]), (.suburbia, ["demo:1", "demo:2", "demo:3"]),
        ]
        var costumes: [Item] = []
        for (theme, ids) in costumed {
            for (index, id) in ids.enumerated() {
                costumes.append(Item(label: index == 1 ? theme.label : "", source: sources[index], color: index * 4 + 2,
                                     look: Persona(agentID: id).look(for: theme)))
            }
        }
        let colors = PixelArt.palette.indices.map { index in
            Item(label: "", source: sources[index % 3], color: index, look: PixelArt.Look())
        }
        // Each style gets a little group of three, with the style's name under the middle one.
        let cast: [(AgentSource, Int, PixelArt.Look)] = [
            (.claude, 1, PixelArt.Look(hat: .crown, pattern: .belly)),
            (.codex, 4, PixelArt.Look(hat: .wizard, accessories: [.sunglasses])),
            (.copilot, 6, PixelArt.Look(hat: .bunnyEars, accessories: [.bowTie], pattern: .overalls)),
        ]
        var styles: [Item] = []
        for style in PixelArt.Style.allCases {
            for (index, member) in cast.enumerated() {
                styles.append(Item(label: index == 1 ? style.label : "", source: member.0, color: member.1,
                                   look: member.2, style: style))
            }
        }
        return [
            ("Hats, hair and helmets", hats),
            ("Glasses, faces and neckwear", accessories),
            ("Patterns and outfits", patterns),
            ("Things to carry", carried),
            ("Costumes", costumes),
            ("Colours", colors),
            ("Agent styles", styles),
        ]
    }

    static func render() -> CGImage? {
        let sections = Self.sections
        let rowsPerSection = sections.map { ($0.items.count + columns - 1) / columns }
        let width = margin * 2 + CGFloat(columns) * slotWidth
        let height = margin * 2 + sectionGap * CGFloat(sections.count - 1)
            + rowsPerSection.reduce(0) { $0 + titleHeight + CGFloat($1) * slotHeight }
        guard let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let previousStyle = PixelArt.style
        PixelArt.savesStyle = false
        defer {
            PixelArt.style = previousStyle
            PixelArt.savesStyle = true
            NSGraphicsContext.restoreGraphicsState()
        }

        let colors = Theme.colors
        context.setFillColor(colors.panel.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Laid out from the top down; Core Graphics counts from the bottom.
        var top = margin
        for (sectionIndex, section) in sections.enumerated() {
            if sectionIndex > 0 { top += sectionGap }
            let title = NSAttributedString.label(section.title.uppercased(), size: 11, weight: .semibold,
                                                 color: colors.ink.withAlphaComponent(0.55))
            title.draw(at: CGPoint(x: margin + 6, y: height - top - 18))
            top += titleHeight
            for (index, item) in section.items.enumerated() {
                let column = CGFloat(index % columns)
                let row = CGFloat(index / columns)
                let slotTop = top + row * slotHeight
                let centerX = margin + (column + 0.5) * slotWidth
                draw(item, in: context, centerX: centerX, feetY: height - slotTop - slotHeight + 26)
                if !item.label.isEmpty {
                    let label = NSAttributedString.label(item.label, size: 10, weight: .medium,
                                                         color: colors.ink.withAlphaComponent(0.8))
                    label.draw(at: CGPoint(x: centerX - label.size().width / 2, y: height - slotTop - slotHeight + 6))
                }
            }
            top += CGFloat(rowsPerSection[sectionIndex]) * slotHeight
        }
        return context.makeImage()
    }

    /// Draws one agent standing on `feetY`, centred on `centerX`.
    private static func draw(_ item: Item, in context: CGContext, centerX: CGFloat, feetY: CGFloat) {
        PixelArt.style = item.style
        let texture = PixelArt.agentTextures(source: item.source, colorIndex: item.color, look: item.look).walk[0]
        let size = PixelArt.spriteSize((PixelArt.agentColumns, PixelArt.canvasRows), pixel: cell)
        let margin = CGFloat(item.style.margin) * cell
        context.interpolationQuality = item.style == .pixel ? .none : .high
        context.draw(texture.cgImage(), in: CGRect(x: centerX - size.width / 2, y: feetY - margin,
                                                   width: size.width, height: size.height))
        if let held = item.look.held {
            // In the free hand, at the agent's side, three and a half rows up from its feet.
            let heldSize = PixelArt.spriteSize(held.size, pixel: cell)
            let below: CGFloat = CGFloat(held.size.rows - held.grip) - 0.5
            let handX: CGFloat = centerX - CGFloat(PixelArt.agentColumns) * cell / 2 - cell / 2
            let handY: CGFloat = feetY + 3.5 * cell
            let rect = CGRect(x: handX - heldSize.width / 2, y: handY - below * cell - margin,
                              width: heldSize.width, height: heldSize.height)
            context.draw(PixelArt.heldTexture(held).cgImage(), in: rect)
        }
    }
}
