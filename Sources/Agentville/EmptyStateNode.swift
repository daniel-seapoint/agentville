import AgentvilleCore
import SpriteKit

/// A provider tag on a coloured tile: the logo, optionally with the name centred underneath.
/// Its origin is the centre of the tile.
final class BadgeNode: SKShapeNode {
    let width: CGFloat
    let height: CGFloat

    /// - Parameters:
    ///   - logoSide: edge of the logo in points; the tile's padding and corners scale with it.
    ///   - fontSize: size of the name.
    ///   - showsName: false for an icon-only tile. Ignored if the logo file is missing, since
    ///     the name is then all there is to show.
    init(source: AgentSource, logoSide: CGFloat = 16, fontSize: CGFloat = 9, showsName: Bool = true) {
        let label = SKLabelNode()
        label.attributedText = .label(source.displayName, size: fontSize, weight: .bold, color: ProviderLogo.ink)
        // Baseline, not centre: centring shifts names with descenders ("Copilot") upward.
        label.verticalAlignmentMode = .baseline
        label.horizontalAlignmentMode = .center

        // Without a logo file the tag is just the name.
        let logo = ProviderLogo.texture(for: source).map {
            SKSpriteNode(texture: $0, size: CGSize(width: logoSide, height: logoSide))
        }
        let pad = max(4, (logoSide * 0.28).rounded())
        let gap = max(2, (logoSide * 0.14).rounded())
        let textHeight = fontSize + 1
        let bottomPad = (pad * 0.75).rounded()
        let named = showsName || logo == nil
        width = named ? (max(label.frame.width, logoSide) + pad * 2 + 2).rounded() : logoSide + pad * 2
        if logo == nil {
            height = textHeight + pad * 1.5
        } else {
            height = named ? pad + logoSide + gap + textHeight + bottomPad : logoSide + pad * 2
        }
        super.init()
        let corner = min(10, max(5, logoSide * 0.3))
        path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                      cornerWidth: corner, cornerHeight: corner, transform: nil)
        fillColor = PixelArt.providerColor(source)
        strokeColor = .clear
        // Lift the baseline a little so descenders stay inside the padding.
        label.position = CGPoint(x: 0, y: -height / 2 + bottomPad + fontSize * 0.2)
        if named { addChild(label) }
        if let logo {
            logo.position = CGPoint(x: 0, y: height / 2 - pad - logoSide / 2)
            addChild(logo)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The plate under an agent: a box in the provider's colour holding its logo and name.
/// Its origin is the centre of the box.
final class ProviderPlate: SKNode {
    let width: CGFloat
    let height: CGFloat

    /// - Parameter height: the plate's height; its logo, text and padding scale with it.
    init(source: AgentSource, height: CGFloat = 20) {
        self.height = height
        let name = SKLabelNode()
        name.attributedText = .label(source.displayName, size: (height * 0.44).rounded(), weight: .semibold,
                                     color: ProviderLogo.ink)
        name.verticalAlignmentMode = .center
        name.horizontalAlignmentMode = .left

        // Without a logo file the plate is just the name.
        let logoSide = (height * 0.6).rounded()
        let logo = ProviderLogo.texture(for: source).map {
            SKSpriteNode(texture: $0, size: CGSize(width: logoSide, height: logoSide))
        }
        let inset = (height * 0.3).rounded()
        let gap = (height * 0.25).rounded()
        let leading = logo == nil ? inset : inset + logoSide + gap
        width = (leading + name.frame.width + inset + 1).rounded()
        super.init()

        let box = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                              cornerRadius: (height * 0.25).rounded())
        box.fillColor = PixelArt.providerColor(source)
        box.strokeColor = .clear
        addChild(box)
        if let logo {
            logo.position = CGPoint(x: -width / 2 + inset + logoSide / 2, y: 0)
            addChild(logo)
        }
        name.position = CGPoint(x: -width / 2 + leading, y: 0)
        addChild(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A node that fades in and out rather than popping, since agents come and go on their own schedule.
class FadingNode: SKNode {
    private var shown: Bool?

    func setVisible(_ visible: Bool) {
        guard visible != shown else { return }
        let isFirstCall = shown == nil
        shown = visible
        removeAction(forKey: "fade")
        if isFirstCall {
            isHidden = !visible
            alpha = visible ? 1 : 0
        } else if visible {
            isHidden = false
            run(.fadeIn(withDuration: 0.4), withKey: "fade")
        } else {
            run(.sequence([.fadeOut(withDuration: 0.2), .hide()]), withKey: "fade")
        }
    }
}

/// Steam: one puff per starting point, each rising, fading and starting again, out of step
/// with the others and drifting apart as they go.
private func addSteam(to node: SKNode, from points: [CGPoint]) {
    for (index, start) in points.enumerated() {
        let puff = SKShapeNode(circleOfRadius: 1.6)
        puff.fillColor = Theme.colors.ink.withAlphaComponent(0.7)
        puff.strokeColor = .clear
        puff.position = start
        puff.alpha = 0
        let drift = (CGFloat(index) - CGFloat(points.count - 1) / 2) * 3
        let rise = SKAction.group([
            .moveBy(x: drift, y: 16, duration: 1.6),
            .sequence([.fadeAlpha(to: 0.6, duration: 0.4), .fadeOut(withDuration: 1.2)]),
        ])
        puff.run(.sequence([
            .wait(forDuration: Double(index) * 0.7),
            .repeatForever(.sequence([rise, .move(to: start, duration: 0), .wait(forDuration: 0.5)])),
        ]))
        node.addChild(puff)
    }
}

/// The note in the middle of the floor while every agent is idle: a steaming mug of coffee
/// over a line saying where everyone went.
final class BreakNoteNode: FadingNode {
    /// How far the mug and its steam rise above the node's origin, for centring the note.
    static let headroom: CGFloat = 54

    override init() {
        super.init()
        let cells = PixelArt.mugSize
        let pixel: CGFloat = 3
        let mug = SKSpriteNode(texture: PixelArt.mug())
        mug.size = PixelArt.spriteSize(cells, pixel: pixel)
        mug.position = CGPoint(x: 3, y: 29)
        addChild(mug)
        // A slow rock, as if someone just put it down.
        let tilt = SKAction.rotate(toAngle: 0.07, duration: 1.4)
        tilt.timingMode = .easeInEaseOut
        let back = SKAction.rotate(toAngle: -0.07, duration: 1.4)
        back.timingMode = .easeInEaseOut
        mug.run(.repeatForever(.sequence([tilt, back])))

        let rim = mug.position.y + CGFloat(cells.rows) * pixel / 2 + 1
        addSteam(to: self, from: [CGPoint(x: -6, y: rim), CGPoint(x: -1, y: rim), CGPoint(x: 4, y: rim)])

        let headline = SKLabelNode()
        headline.attributedText = .label("Everyone's on a break", size: 16, weight: .semibold,
                                         color: Theme.colors.ink.withAlphaComponent(0.88))
        headline.position = CGPoint(x: 0, y: 2)
        addChild(headline)

        let hint = SKLabelNode()
        hint.attributedText = .label("They'll get back to work when you send them something.",
                                     size: 12, color: Theme.colors.ink.withAlphaComponent(0.5))
        hint.position = CGPoint(x: 0, y: -18)
        addChild(hint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// What the floor shows when there are no agents at all: a workbench with the lamp left on
/// and a mug still steaming, a robot vacuum doing its rounds, a dog keeping an eye on it, and a
/// line on how to get someone in.
final class EmptyStateNode: FadingNode {
    private static let pixel: CGFloat = 4

    /// A link to the demo, for someone with nothing running who wants to see what this does.
    /// Hidden when the demo is already on.
    let demoLink = SKLabelNode()

    override init() {
        super.init()
        let bench = SKSpriteNode(texture: PixelArt.workbench())
        let cells = PixelArt.workbenchSize
        bench.size = PixelArt.spriteSize(cells, pixel: Self.pixel)
        bench.position = CGPoint(x: 0, y: 52)
        addChild(bench)
        // The bench as drawn, leaving out any margin the art style puts round its texture.
        let benchArea = CGSize(width: CGFloat(cells.columns) * Self.pixel, height: CGFloat(cells.rows) * Self.pixel)

        // Positions below are in bench pixels from its top-left corner, converted to points.
        let left = bench.position.x - benchArea.width / 2
        let top = bench.position.y + benchArea.height / 2
        func point(_ column: CGFloat, _ row: CGFloat) -> CGPoint {
            CGPoint(x: left + column * Self.pixel, y: top - row * Self.pixel)
        }

        // Light falling from the lamp shade onto the table.
        let cone = CGMutablePath()
        cone.addLines(between: [point(2, 3), point(11, 3), point(13, 8), point(0, 8)])
        cone.closeSubpath()
        let light = SKShapeNode(path: cone)
        light.fillColor = NSColor(srgbRed: 0.98, green: 0.80, blue: 0.25, alpha: 1)
        light.strokeColor = .clear
        light.alpha = 0.22
        light.zPosition = -1
        // A slow pulse, with the bulb stuttering every few breaths.
        let pulse = SKAction.sequence([.fadeAlpha(to: 0.14, duration: 1.8), .fadeAlpha(to: 0.24, duration: 1.8)])
        let flicker = SKAction.sequence([
            .fadeAlpha(to: 0.06, duration: 0.05), .fadeAlpha(to: 0.24, duration: 0.07),
            .fadeAlpha(to: 0.10, duration: 0.05), .fadeAlpha(to: 0.24, duration: 0.10),
        ])
        light.run(.repeatForever(.sequence([.repeat(pulse, count: 2), flicker])))
        addChild(light)

        // A moth that cannot leave the lamp alone.
        let moth = SKShapeNode(circleOfRadius: 1.4)
        moth.fillColor = NSColor(srgbRed: 1, green: 0.93, blue: 0.7, alpha: 1)
        moth.strokeColor = .clear
        let shade = point(6.5, 1.5)
        let orbit = CGPath(ellipseIn: CGRect(x: shade.x - 22, y: shade.y - 9, width: 44, height: 22), transform: nil)
        moth.run(.repeatForever(.follow(orbit, asOffset: false, orientToPath: false, duration: 3.4)))
        moth.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.18), .fadeAlpha(to: 1, duration: 0.18)])))
        addChild(moth)

        // A robot vacuum patrolling the floor behind the bench, turning round at each end.
        let vacuumCells = PixelArt.vacuumSize
        let vacuum = SKSpriteNode(texture: PixelArt.vacuum())
        vacuum.size = PixelArt.spriteSize(vacuumCells, pixel: 3)
        let floorY = bench.position.y - benchArea.height / 2 + CGFloat(vacuumCells.rows) * 3 / 2
        let reach: CGFloat = 170
        vacuum.position = CGPoint(x: -reach, y: floorY)
        vacuum.zPosition = -2
        let cross = SKAction.moveBy(x: reach * 2, y: 0, duration: 7)
        cross.timingMode = .easeInEaseOut
        vacuum.run(.repeatForever(.sequence([
            cross, .wait(forDuration: 0.5), .scaleX(to: -1, duration: 0.25),
            cross.reversed(), .wait(forDuration: 0.5), .scaleX(to: 1, duration: 0.25),
        ])))
        addChild(vacuum)

        // A dog sitting by the bench, wagging its tail. It turns to watch the vacuum go by and
        // gives a little jump when it comes close.
        let dogCells = PixelArt.dogSize
        let dogFrames = PixelArt.dog()
        let dog = SKSpriteNode(texture: dogFrames[0])
        dog.size = PixelArt.spriteSize(dogCells, pixel: 3)
        dog.position = CGPoint(x: benchArea.width / 2 + 34,
                               y: bench.position.y - benchArea.height / 2 + CGFloat(dogCells.rows) * 3 / 2)
        dog.run(.repeatForever(.animate(with: dogFrames, timePerFrame: 0.2)))
        let home = dog.position
        dog.run(.repeatForever(.sequence([
            .run { [unowned dog, unowned vacuum] in
                let offset = vacuum.position.x - home.x
                if abs(offset) > 6 { dog.xScale = offset < 0 ? -1 : 1 }
                if abs(offset) < 26, dog.action(forKey: "startle") == nil {
                    let hop = SKAction.moveBy(x: 0, y: 6, duration: 0.11)
                    hop.timingMode = .easeOut
                    dog.run(.sequence([hop, hop.reversed(), .wait(forDuration: 1.5)]), withKey: "startle")
                }
            },
            .wait(forDuration: 0.15),
        ])))
        addChild(dog)

        addSteam(to: self, from: [point(19, 3.5), point(20, 3.5), point(21, 3.5)])

        let headline = SKLabelNode()
        headline.attributedText = .label("It's quiet in here", size: 16, weight: .semibold,
                                         color: Theme.colors.ink.withAlphaComponent(0.9))
        headline.position = CGPoint(x: 0, y: -8)
        addChild(headline)

        let hint = SKLabelNode()
        hint.attributedText = .label("Start a session and your agent will walk right in.",
                                     size: 12, color: Theme.colors.ink.withAlphaComponent(0.55))
        hint.position = CGPoint(x: 0, y: -30)
        addChild(hint)

        // The tools that count as "a session".
        let badges = [AgentSource.claude, .codex, .copilot].map { BadgeNode(source: $0, logoSide: 32, fontSize: 11) }
        let gap: CGFloat = 14
        var x = -(badges.reduce(0) { $0 + $1.width } + gap * CGFloat(badges.count - 1)) / 2
        for badge in badges {
            // Whole points only; a pill on a half point renders a pixel off from its neighbours.
            badge.position = CGPoint(x: (x + badge.width / 2).rounded(), y: -50 - badge.height / 2)
            x += badge.width + gap
            addChild(badge)
        }
        demoLink.attributedText = .label("See a demo  ›", size: 12, weight: .medium,
                                         color: Theme.colors.link)
        demoLink.position = CGPoint(x: 0, y: -50 - (badges.first?.height ?? 0) - 28)
        addChild(demoLink)

        // The tiles bob one after another, like a slow wave.
        for (index, badge) in badges.enumerated() {
            let up = SKAction.moveBy(x: 0, y: 4, duration: 1.1)
            up.timingMode = .easeInEaseOut
            badge.run(.sequence([
                .wait(forDuration: Double(index) * 0.35),
                .repeatForever(.sequence([up, up.reversed()])),
            ]))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
