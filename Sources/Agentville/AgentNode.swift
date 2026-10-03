import AgentvilleCore
import SpriteKit

/// One agent on the floor. While working it is a pixel agent with a prop and a label; once it
/// is idle and has reached the lounge it goes to sleep under a thought bubble: in a bed, sitting
/// on one of the lounge's couches if it was given one, or on its feet.
final class AgentNode: SKNode {
    let agentID: String
    let persona: Persona
    private(set) var target: CGPoint
    /// Set by the floor when this agent has been given one of the lounge's couches.
    var hasCouch = false {
        didSet { if hasCouch != oldValue { refresh() } }
    }

    private let sprite: SKSpriteNode
    private let textures: PixelArt.AgentTextures
    private let prop = SKLabelNode()
    private let icon: BadgeNode

    // Awake: a rectangular label with the task and what is happening.
    private let bubble = SKShapeNode()
    private let titleLabel = SKLabelNode()
    private let statusLabel = SKLabelNode()

    // Asleep: a bed (for those who use one), a thought bubble, and the task underneath.
    private let bed: SKSpriteNode
    private let dream = SKNode()
    private let dreamPill = SKShapeNode()
    private let dreamLabel = SKLabelNode()
    private let snoreLabel = SKLabelNode()
    private let dreamDots = [SKShapeNode(circleOfRadius: 1.8), SKShapeNode(circleOfRadius: 3)]
    private let caption = SKLabelNode()
    private var napProp: SKLabelNode?
    /// How far to either side of a sleeper its bedside things sit.
    private var napReach: CGFloat = 0

    private var agent: AgentSnapshot
    private let color: NSColor
    private let compact: Bool
    private var heading: String?
    private var destination: String?
    private var standingAt: String?
    private var confettiPending = false
    private var shownText = ""
    /// Holds the provider icon; it is moved as the agent stands, walks or goes to bed, while
    /// the icon inside keeps bobbing.
    private let iconAnchor = SKNode()
    private var propMotion = ""
    private var propHome = CGPoint.zero

    /// Half the height of the agent's body, and how far a hat rises above it.
    private let bodyHalf: CGFloat
    private let hatHeight: CGFloat
    /// Half the width of the agent as drawn, without any margin round its texture.
    private let halfWidth: CGFloat
    /// The bed as drawn, without any margin its texture has round it.
    private let bedArea: CGSize

    static let pixel: CGFloat = 2.5
    /// Distance from a full-size agent's centre down to the floor it stands on.
    static var feet: CGFloat { CGFloat(PixelArt.bodyRows) * pixel / 2 }
    private static let walkSpeed: CGFloat = 170
    /// How far a agent is lifted when it sits on one of the lounge's couches.
    private static let couchSeat: CGFloat = 6

    init(agent: AgentSnapshot, at point: CGPoint) {
        self.agent = agent
        agentID = agent.id
        target = point
        compact = agent.isSubagent
        persona = Persona(agentID: agent.id)
        color = PixelArt.color(agent.colorIndex)
        textures = PixelArt.agentTextures(source: agent.source, colorIndex: agent.colorIndex, look: persona.look)
        sprite = SKSpriteNode(texture: textures.walk[0])
        bed = SKSpriteNode(texture: PixelArt.bed(colorIndex: agent.colorIndex))
        icon = BadgeNode(source: agent.source, logoSide: 13, showsName: false)

        let scale = Self.pixel * (compact ? 0.6 : 1)
        halfWidth = CGFloat(PixelArt.agentColumns) * scale / 2
        bedArea = CGSize(width: CGFloat(PixelArt.bedSize.columns) * Self.pixel,
                         height: CGFloat(PixelArt.bedSize.rows) * Self.pixel)
        bodyHalf = CGFloat(PixelArt.bodyRows) * scale / 2
        hatHeight = CGFloat(PixelArt.rowsAboveBody(source: agent.source, hat: persona.look.hat)) * scale
        super.init()
        position = point

        // The texture has spare rows on top for hats; anchor on the middle of the body below them.
        // Some styles leave a margin round the texture too, which the anchor has to allow for.
        sprite.size = PixelArt.spriteSize((PixelArt.agentColumns, PixelArt.canvasRows), pixel: scale)
        let margin = CGFloat(PixelArt.style.margin)
        let anchorRow: CGFloat = CGFloat(PixelArt.bodyRows) / 2 + margin
        let textureRows: CGFloat = CGFloat(PixelArt.canvasRows) + 2 * margin
        sprite.anchorPoint = CGPoint(x: 0.5, y: anchorRow / textureRows)
        addChild(sprite)
        if PixelArt.style == .hologram {
            // A projection never quite holds steady: a soft waver, and now and then a glitch.
            let waver = SKAction.sequence([.fadeAlpha(to: 0.82, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])
            let glitch = SKAction.sequence([.fadeAlpha(to: 0.35, duration: 0.04), .fadeAlpha(to: 1, duration: 0.05),
                                            .fadeAlpha(to: 0.6, duration: 0.04), .fadeAlpha(to: 1, duration: 0.06)])
            sprite.run(.sequence([
                .wait(forDuration: Double((persona.jitter.y + 1) * 1.5)),
                .repeatForever(.sequence([.repeat(waver, count: 3), glitch])),
            ]))
        }

        prop.fontSize = compact ? 10 : 15
        prop.verticalAlignmentMode = .center
        propHome = CGPoint(x: halfWidth + (compact ? 6 : 10), y: -2)
        prop.position = propHome
        addChild(prop)

        bubble.lineWidth = 1
        bubble.fillColor = Theme.colors.bubble
        bubble.strokeColor = color.withAlphaComponent(0.55)
        // Subagents stand beside their parent, so their label hangs below to stay clear of it.
        bubble.position = CGPoint(x: 0, y: compact ? -bodyHalf - 25 : bodyHalf + hatHeight + 7)
        addChild(bubble)
        for label in [titleLabel, statusLabel] {
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            bubble.addChild(label)
        }
        statusLabel.isHidden = compact

        // Provider icon, floating beside the agent on the side away from its tool; the legend
        // in the header says which is which. Subagents have no icon.
        iconAnchor.isHidden = compact
        iconAnchor.addChild(icon)
        addChild(iconAnchor)
        let rise = SKAction.moveBy(x: 0, y: 3, duration: 1.1)
        rise.timingMode = .easeInEaseOut
        icon.run(.sequence([
            // Start each agent's icon at a different point in the bob.
            .wait(forDuration: Double((persona.jitter.x + 1) / 2)),
            .repeatForever(.sequence([rise, rise.reversed()])),
        ]))
        caption.position = CGPoint(x: 0, y: -bodyHalf - 4)

        setUpSleep()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUpSleep() {
        bed.size = PixelArt.spriteSize(PixelArt.bedSize, pixel: Self.pixel)
        bed.position = CGPoint(x: 0, y: -bodyHalf + bedArea.height / 2) // legs on the floor
        addChild(bed)

        // One keepsake on the right of a sleeper; the provider icon takes the spot on the left.
        // Beds and the lounge's couches are the same width, so either way things sit this far out.
        napReach = bedArea.width / 2 + 13
        if let emoji = persona.props.last {
            let node = SKLabelNode(text: emoji)
            node.fontSize = 14
            node.verticalAlignmentMode = .bottom
            node.position = CGPoint(x: napReach, y: -bodyHalf)
            napProp = node
            addChild(node)
        }

        dreamPill.lineWidth = 1
        // Same box as the working label, so an agent's label keeps its shape when it nods off.
        dreamPill.fillColor = Theme.colors.bubble
        dreamPill.strokeColor = color.withAlphaComponent(0.55)
        dream.addChild(dreamPill)
        for dot in dreamDots {
            dot.lineWidth = 1
            dot.fillColor = dreamPill.fillColor
            dot.strokeColor = dreamPill.strokeColor
            dream.addChild(dot)
        }
        for label in [dreamLabel, snoreLabel] {
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            dream.addChild(label)
        }
        dreamLabel.attributedText = .label("Dreaming of \(persona.dream)…", size: 10, weight: .semibold,
                                           color: Theme.colors.bubbleInk.withAlphaComponent(0.92))
        snoreLabel.attributedText = .label("z z z", size: 9.5, weight: .medium,
                                           color: Theme.colors.bubbleInk.withAlphaComponent(0.6))
        let breathe = SKAction.sequence([.fadeAlpha(to: 0.25, duration: 1.1), .fadeAlpha(to: 1, duration: 1.1)])
        snoreLabel.run(.repeatForever(breathe))

        // The thought bubble rises from the top of whatever is asleep under it.
        // Laid out for this sleeper's usual spot; `refresh` slides it if they end up elsewhere.
        let top = dreamBase(inBed: persona.sleepsInBed, onCouch: false)
        let width = dreamLabel.frame.width + 16
        let height: CGFloat = 36
        let bottom = top + 19
        dreamDots[0].position = CGPoint(x: 5, y: top + 5)
        dreamDots[1].position = CGPoint(x: 1, y: top + 12)
        dreamPill.path = CGPath(roundedRect: CGRect(x: -width / 2, y: bottom, width: width, height: height),
                                cornerWidth: 5, cornerHeight: 5, transform: nil)
        dreamLabel.position = CGPoint(x: 0, y: bottom + 25)
        snoreLabel.position = CGPoint(x: 0, y: bottom + 11)
        addChild(dream)

        caption.verticalAlignmentMode = .top
        caption.horizontalAlignmentMode = .center
        addChild(caption)
    }

    /// Height of the top of a sleeper: the bed, or the agent's head (and hat), which is higher
    /// still when it is sitting up on a couch.
    private func dreamBase(inBed: Bool, onCouch: Bool) -> CGFloat {
        inBed ? bed.position.y + bedArea.height / 2 : bodyHalf + hatHeight + (onCouch ? Self.couchSeat : 0)
    }

    func update(_ newAgent: AgentSnapshot) {
        if newAgent.shipCount > agent.shipCount { confettiPending = true }
        agent = newAgent
        celebrateIfReady()
        refresh()
    }

    /// - Parameter heading: name of the destination, shown as "Heading to …" on the way.
    func move(to point: CGPoint, heading: String?, animated: Bool) {
        guard hypot(point.x - target.x, point.y - target.y) > 1 else { return }
        target = point
        destination = heading
        removeAction(forKey: "move")
        guard animated else {
            position = point
            arrive()
            return
        }
        let distance = hypot(point.x - position.x, point.y - position.y)
        self.heading = heading
        sprite.xScale = point.x < position.x ? -1 : 1
        sprite.removeAction(forKey: "bob")
        sprite.position = .zero
        sprite.run(.repeatForever(.animate(with: textures.walk, timePerFrame: 0.14)), withKey: "walk")

        let move = SKAction.move(to: point, duration: max(0.35, Double(distance / Self.walkSpeed)))
        move.timingMode = .easeInEaseOut
        run(.sequence([move, .run { [weak self] in self?.arrive() }]), withKey: "move")
        refresh()
    }

    private func arrive() {
        heading = nil
        standingAt = destination
        sprite.removeAction(forKey: "walk")
        sprite.xScale = 1
        celebrateIfReady()
        refresh()
    }

    /// Confetti waits until the agent is standing at Ship. The status line changes the moment
    /// a commit happens, but the walk there only starts once the stage has held for a moment.
    /// If the turn ends first, celebrate where it stands.
    private func celebrateIfReady() {
        guard confettiPending, heading == nil,
              standingAt == Stage.ship.title || !agent.isWorking, let parent else { return }
        confettiPending = false
        Confetti.burst(in: parent, at: CGPoint(x: position.x, y: position.y + 6))
    }

    /// Each tool is used the way you would expect: the hammer hammers, the test tube is shaken,
    /// the magnifying glass sweeps, and so on. Restarted only when the tool changes.
    private func animateProp(for stage: Stage?, thinking: Bool) {
        let motion = stage?.rawValue ?? (thinking ? "thinking" : "")
        guard motion != propMotion else { return }
        propMotion = motion
        prop.removeAllActions()
        prop.zRotation = 0
        prop.setScale(1)
        prop.alpha = 1
        prop.position = propHome

        func eased(_ action: SKAction, _ mode: SKActionTimingMode = .easeInEaseOut) -> SKAction {
            action.timingMode = mode
            return action
        }
        let action: SKAction
        switch stage {
        case .plan:
            // Turning the map this way and that.
            action = .sequence([eased(.rotate(toAngle: 0.14, duration: 0.9)), eased(.rotate(toAngle: -0.14, duration: 0.9))])
        case .research:
            // Sweeping the magnifying glass across the page.
            action = .sequence([
                eased(.group([.moveBy(x: 5, y: 2, duration: 0.7), .rotate(toAngle: -0.25, duration: 0.7)])),
                eased(.group([.moveBy(x: -5, y: -2, duration: 0.7), .rotate(toAngle: 0.1, duration: 0.7)])),
            ])
        case .build:
            // Wind up, strike, recoil.
            action = .sequence([
                eased(.rotate(toAngle: 0.6, duration: 0.28), .easeOut),
                eased(.rotate(toAngle: -0.45, duration: 0.09), .easeIn),
                eased(.rotate(toAngle: -0.2, duration: 0.08), .easeOut),
                .wait(forDuration: 0.12),
            ])
        case .verify:
            // A quick shake of the test tube, then a look at the result.
            let shake = SKAction.sequence([.rotate(toAngle: 0.22, duration: 0.07), .rotate(toAngle: -0.22, duration: 0.07)])
            action = .sequence([.repeat(shake, count: 4), .rotate(toAngle: 0, duration: 0.07), .wait(forDuration: 0.9)])
        case .review:
            // Ticking things off.
            action = .sequence([
                eased(.scale(to: 1.25, duration: 0.14), .easeOut), eased(.scale(to: 1, duration: 0.2)),
                .wait(forDuration: 0.9),
            ])
        case .ship:
            // The rocket straining to lift off.
            let tremble = SKAction.sequence([.moveBy(x: 1, y: 0, duration: 0.04), .moveBy(x: -1, y: 0, duration: 0.04)])
            action = .sequence([
                .group([eased(.moveBy(x: 3, y: 7, duration: 0.5), .easeOut), .repeat(tremble, count: 6)]),
                eased(.moveBy(x: -3, y: -7, duration: 0.5), .easeIn),
            ])
        case nil:
            guard thinking else { return }
            action = .sequence([.fadeAlpha(to: 0.45, duration: 0.7), .fadeAlpha(to: 1, duration: 0.7)])
        }
        prop.run(.repeatForever(action))
    }

    private func refresh() {
        let walking = heading != nil
        let atStation = agent.isWorking && agent.stage != nil
        // Sleep starts on arrival, not on the walk over. Subagents are only briefly idle.
        let asleep = !agent.isWorking && !walking && !compact
        // A bed sleeper given a couch (the floor was full) sits up on it like anyone else.
        let inBed = asleep && persona.sleepsInBed && !hasCouch

        bubble.isHidden = asleep
        dream.isHidden = !asleep
        caption.isHidden = !asleep
        let onCouch = asleep && hasCouch
        // The thought bubble rises from the top of whatever the sleeper is actually on.
        dream.position = CGPoint(x: 0, y: dreamBase(inBed: inBed, onCouch: onCouch)
                                 - dreamBase(inBed: persona.sleepsInBed, onCouch: false))
        bed.isHidden = !inBed
        sprite.isHidden = inBed
        napProp?.isHidden = !asleep
        if !walking { sprite.texture = asleep ? textures.asleep : textures.walk[0] }
        // Awake, the icon floats at the agent's shoulder. Asleep, it is set down on the floor
        // on the left, opposite the keepsake.
        if asleep {
            iconAnchor.position = CGPoint(x: -napReach - 2, y: -bodyHalf + icon.height / 2)
        } else {
            iconAnchor.position = CGPoint(x: -halfWidth - 5 - icon.width / 2, y: 1)
        }
        prop.text = walking || !agent.isWorking ? "" : (agent.stage?.emoji ?? "💭")
        animateProp(for: walking || !agent.isWorking ? nil : agent.stage, thinking: agent.isWorking && agent.stage == nil)

        if atStation && !walking {
            if sprite.action(forKey: "bob") == nil {
                let up = SKAction.moveBy(x: 0, y: 2, duration: 0.35)
                up.timingMode = .easeInEaseOut
                sprite.run(.repeatForever(.sequence([up, up.reversed()])), withKey: "bob")
            }
        } else if sprite.action(forKey: "bob") != nil {
            sprite.removeAction(forKey: "bob")
            sprite.position = .zero
        }
        if !walking, sprite.action(forKey: "bob") == nil {
            sprite.position = CGPoint(x: 0, y: onCouch ? Self.couchSeat : 0)
        }

        let title = agent.title.truncated(compact ? 20 : 26)
        let onTheWay = heading.map { agent.isWorking ? "Heading to \($0)…" : "Off to the lounge…" }
        let status = (onTheWay ?? agent.status).truncated(30)
        let text = "\(title)\n\(status)\n\(agent.isWorking)\n\(asleep)"
        guard text != shownText else { return }
        shownText = text

        if asleep {
            caption.attributedText = .label(agent.title.truncated(22), size: 9, color: Theme.colors.ink.withAlphaComponent(0.5))
            return
        }

        let ink = Theme.colors.bubbleInk
        let titleColor = ink.withAlphaComponent(agent.isWorking ? 0.95 : 0.55)
        // On a light bubble the agent's colour is darkened so the status stays readable.
        let statusColor = Theme.colors.isLight ? (color.blended(withFraction: 0.4, of: .black) ?? color) : color
        titleLabel.attributedText = .label(title, size: compact ? 9 : 11, weight: .medium, color: titleColor)
        statusLabel.attributedText = .label(status, size: 10,
                                            color: agent.isWorking ? statusColor : ink.withAlphaComponent(0.4))

        let lineHeight: CGFloat = 14
        let width = max(titleLabel.frame.width, compact ? 0 : statusLabel.frame.width) + 16
        let height = compact ? lineHeight + 6 : lineHeight * 2 + 8
        bubble.path = CGPath(roundedRect: CGRect(x: -width / 2, y: 0, width: width, height: height),
                             cornerWidth: 5, cornerHeight: 5, transform: nil)
        titleLabel.position = CGPoint(x: 0, y: compact ? height / 2 : height - 4 - lineHeight / 2)
        statusLabel.position = CGPoint(x: 0, y: 4 + lineHeight / 2)
    }
}
