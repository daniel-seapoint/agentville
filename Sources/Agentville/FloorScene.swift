import AgentvilleCore
import SpriteKit

/// The workshop floor: a row of stations along the top with working agents beneath the station
/// they are at, and a lounge along the bottom where agents waiting on the user go to sleep.
final class FloorScene: SKScene {
    /// Called with the agent's id and the click position in view coordinates (origin top-left).
    var onSelect: ((String, CGPoint) -> Void)?
    /// Called when the agent count in the header is clicked.
    var onShowAgentList: (() -> Void)?
    /// Called when "See a demo" is clicked in the empty state.
    var onStartDemo: (() -> Void)?
    /// Whether the agents on show are the scripted demo rather than real sessions. Marked in
    /// the header so the two are never confused.
    var isDemo = false {
        didSet {
            demoTag.isHidden = !isDemo
            emptyState.demoLink.isHidden = isDemo
        }
    }
    /// Called with the provider whose legend plate was clicked.
    var onToggleProvider: ((AgentSource) -> Void)?
    /// Providers filtered out with the legend. Their agents are left off the floor.
    var hiddenSources: Set<AgentSource> = [] {
        didSet {
            guard hiddenSources != oldValue else { return }
            for (source, plate) in legendPlates {
                plate.alpha = hiddenSources.contains(source) ? 0.28 : 1
            }
            sync(allAgents)
        }
    }

    /// Everything the store knows about; `agents` is what is left after the legend's filter.
    private var allAgents: [AgentSnapshot] = []

    private var agents: [AgentSnapshot] = []
    private var agentNodes: [String: AgentNode] = [:]
    private var stations: [Stage: StationNode] = [:]

    private let panel = SKShapeNode()
    private let grid = SKShapeNode()
    private let titleLabel = SKLabelNode()
    private let countLabel = SKLabelNode()
    private let demoTag = SKShapeNode()
    /// Drawn behind the count so it reads as a button: it opens the list of agents.
    private let countButton = SKShapeNode()
    private var emptyState = EmptyStateNode()
    /// Where rebuilt agents should reappear; only set during `restyle`.
    private var respawn: [String: CGPoint] = [:]
    private var breakNote = BreakNoteNode()
    /// The theme's weather: stars, bubbles, fireflies and so on, behind everything else.
    /// Cropped to the floor, so clouds and streaks do not spill past its rounded edge.
    private let ambience = SKCropNode()
    private var ambienceFor = ""
    private let lounge = SKShapeNode()
    private let loungeLabel = SKLabelNode()
    /// The lounge's furniture: three couches, two lamps and two plants. It is always there,
    /// whether or not anyone is using it.
    private let furniture = SKNode()
    private var furnishedFor = ""
    /// Which icon is which provider: one plate each, in a row to the left of the agent count.
    /// Clicking a plate filters that provider's agents out, or back in.
    private let legend = SKNode()
    private var legendWidth: CGFloat = 0
    private var legendPlates: [(AgentSource, ProviderPlate)] = []
    private var isSetUp = false

    private enum Metrics {
        static let margin: CGFloat = 24
        static let headerButtonHeight: CGFloat = 28  // the count button and the legend plates
        static let stationY: CGFloat = 88       // station centre, from the top
        static let firstRowY: CGFloat = 198     // first agent row, from the top
        static let rowStep: CGFloat = 80
        static let loungeTop: CGFloat = 206     // top edge of the lounge, from the bottom
        static let loungeSeatY: CGFloat = 64    // where a resting agent sits, from the bottom
    }

    override init() {
        super.init(size: CGSize(width: 1000, height: 560))
        scaleMode = .resizeFill

        panel.zPosition = -3
        grid.lineWidth = 1
        grid.zPosition = -2
        ambience.zPosition = -1.5
        countButton.lineWidth = 1
        lounge.lineWidth = 1
        lounge.zPosition = -1
        loungeLabel.horizontalAlignmentMode = .left
        loungeLabel.verticalAlignmentMode = .top
        let demoText = SKLabelNode()
        demoText.attributedText = .label("DEMO", size: 9, weight: .bold,
                                         color: NSColor(srgbRed: 0.10, green: 0.08, blue: 0.02, alpha: 1))
        demoText.verticalAlignmentMode = .center
        demoText.horizontalAlignmentMode = .center
        let tagWidth = demoText.frame.width + 12
        demoTag.path = CGPath(roundedRect: CGRect(x: -tagWidth / 2, y: -8, width: tagWidth, height: 16),
                              cornerWidth: 4, cornerHeight: 4, transform: nil)
        demoTag.fillColor = NSColor(srgbRed: 0.98, green: 0.80, blue: 0.25, alpha: 1)
        demoTag.strokeColor = .clear
        demoTag.isHidden = true
        demoTag.addChild(demoText)
        [panel, grid, ambience, lounge, loungeLabel, furniture, titleLabel, demoTag, countButton, countLabel, legend, emptyState, breakNote].forEach(addChild)
        var legendX: CGFloat = 0
        for source in [AgentSource.claude, .codex, .copilot] {
            let plate = ProviderPlate(source: source, height: Metrics.headerButtonHeight)
            plate.position = CGPoint(x: legendX + plate.width / 2, y: 0)
            legendX += plate.width + 6
            legend.addChild(plate)
            legendPlates.append((source, plate))
        }
        legendWidth = legendX - 6

        titleLabel.horizontalAlignmentMode = .left
        countLabel.horizontalAlignmentMode = .right

        for stage in Stage.allCases {
            let node = StationNode(stage: stage)
            stations[stage] = node
            addChild(node)
        }
        isSetUp = true
        applyTheme()
        layoutStatic()
        refreshHeader()
    }

    /// Colours everything that is not rebuilt by `restyle`.
    private func applyTheme() {
        let colors = Theme.colors
        backgroundColor = colors.background
        panel.fillColor = colors.panel
        panel.strokeColor = colors.panelStroke
        grid.strokeColor = colors.grid
        countButton.fillColor = colors.button
        countButton.strokeColor = colors.buttonStroke
        lounge.fillColor = colors.lounge
        lounge.strokeColor = colors.loungeStroke
        loungeLabel.attributedText = .label("LOUNGE", size: 9, weight: .semibold,
                                            color: colors.ink.withAlphaComponent(0.4))
        titleLabel.attributedText = .label("Agentville", size: 14, weight: .semibold, color: colors.ink)
        stations.values.forEach { $0.applyState() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didChangeSize(_ oldSize: CGSize) {
        guard isSetUp else { return }
        layoutStatic()
        layoutAgents(animated: false)
    }

    // MARK: Updating

    func sync(_ everyone: [AgentSnapshot]) {
        allAgents = everyone
        Casting.shared.release(keeping: Set(everyone.map(\.id)))
        let newAgents = everyone.filter { !hiddenSources.contains($0.source) }
        agents = newAgents
        let ids = Set(newAgents.map(\.id))
        for (id, agentNode) in agentNodes where !ids.contains(id) {
            agentNode.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            agentNodes[id] = nil
        }
        for agent in newAgents {
            if let agentNode = agentNodes[agent.id] {
                agentNode.update(agent)
            } else {
                // Subagents pop out of their parent; everyone else walks in from the door.
                let origin = respawn[agent.id] ?? agent.parentID.flatMap { agentNodes[$0]?.position }
                    ?? CGPoint(x: -20, y: Metrics.loungeSeatY)
                let agentNode = AgentNode(agent: agent, at: origin)
                agentNodes[agent.id] = agentNode
                addChild(agentNode)
            }
        }
        layoutAgents(animated: true)
        refreshHeader()
    }

    /// Rebuilds everything drawn from the character maps after `PixelArt.style` or `Theme.current`
    /// changes. Agents come back where they were standing rather than walking in again.
    func restyle() {
        applyTheme()
        let noteShown = !breakNote.isHidden
        breakNote.removeFromParent()
        breakNote = BreakNoteNode()
        breakNote.setVisible(noteShown)
        addChild(breakNote)
        ambienceFor = ""
        respawn = agentNodes.mapValues(\.position)
        agentNodes.values.forEach { $0.removeFromParent() }
        agentNodes.removeAll()
        emptyState.removeFromParent()
        emptyState = EmptyStateNode()
        emptyState.demoLink.isHidden = isDemo
        addChild(emptyState)
        furnishedFor = ""
        furnishLounge()
        layoutStatic()
        sync(allAgents)
        respawn.removeAll()
    }

    /// The count's label, padded out sideways and given the header's fixed button height.
    private var countButtonFrame: CGRect {
        let label = countLabel.frame
        return CGRect(x: label.minX - 10, y: label.midY - Metrics.headerButtonHeight / 2,
                      width: label.width + 20, height: Metrics.headerButtonHeight)
    }

    /// The count's width changes with its text, so its button outline and the legend beside
    /// it are fitted to it each time.
    private func positionLegend() {
        let button = countButtonFrame
        countButton.path = CGPath(roundedRect: button, cornerWidth: 7, cornerHeight: 7, transform: nil)
        // Same height as the button, and level with it.
        legend.position = CGPoint(x: button.minX - 12 - legendWidth, y: button.midY)
    }

    /// Names the ambience's still decorations (candles, windows, stars), which are cleared from
    /// round the break note and the empty state so their text is easy to read.
    static let fixedDecor = "fixedDecor"
    private var clearedFor = ""

    /// Hides the still decorations behind whichever message is showing: the break note while
    /// everyone is idle, the empty state while nobody is here.
    private func clearAroundMessages(onBreak: Bool, empty: Bool) {
        let key = "\(onBreak)-\(empty)-\(ambienceFor)-\(breakNote.position)-\(emptyState.position)"
        guard key != clearedFor else { return }
        clearedFor = key
        var zones: [CGRect] = []
        if onBreak { zones.append(breakNote.calculateAccumulatedFrame().insetBy(dx: -22, dy: -14)) }
        if empty { zones.append(emptyState.calculateAccumulatedFrame().insetBy(dx: -22, dy: -14)) }
        for node in ambience.children where node.name == Self.fixedDecor {
            let frame = node.calculateAccumulatedFrame()
            node.isHidden = zones.contains { $0.intersects(frame) }
        }
    }

    private func refreshHeader() {
        let topLevel = agents.filter { !$0.isSubagent }
        let working = topLevel.filter(\.isWorking).count
        let text: String
        if topLevel.isEmpty {
            // Either nobody is here, or the legend's filter has hidden everyone who is.
            text = allAgents.isEmpty ? "No agents running" : "No agents shown"
        } else if working == 0 {
            text = "All agents idle"
        } else {
            text = working == 1 ? "1 agent working" : "\(working) agents working"
        }
        // A button, with a chevron to say it drops down.
        countLabel.attributedText = .label(text + "  ▾", size: 12, weight: .semibold,
                                           color: Theme.colors.buttonInk.withAlphaComponent(0.95))
        positionLegend()
        let empty = allAgents.isEmpty
        emptyState.setVisible(empty)
        let onBreak = !topLevel.isEmpty && working == 0
        breakNote.setVisible(onBreak)
        clearAroundMessages(onBreak: onBreak, empty: empty)
        for (stage, node) in stations {
            node.isActive = agents.contains { $0.isWorking && $0.stage == stage }
        }
    }

    // MARK: Layout

    private func stationX(_ stage: Stage) -> CGFloat {
        let index = CGFloat(Stage.allCases.firstIndex(of: stage) ?? 0)
        let inset = Metrics.margin + 86
        let span = max(size.width - inset * 2, 100)
        return inset + span * index / CGFloat(Stage.allCases.count - 1)
    }

    private func layoutStatic() {
        let frame = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        panel.path = CGPath(roundedRect: frame, cornerWidth: 10, cornerHeight: 10, transform: nil)

        let lines = CGMutablePath()
        var x = frame.minX + 30
        while x < frame.maxX {
            lines.move(to: CGPoint(x: x, y: frame.minY))
            lines.addLine(to: CGPoint(x: x, y: frame.maxY))
            x += 30
        }
        var y = frame.minY + 30
        while y < frame.maxY {
            lines.move(to: CGPoint(x: frame.minX, y: y))
            lines.addLine(to: CGPoint(x: frame.maxX, y: y))
            y += 30
        }
        grid.path = lines
        fillAmbience(in: frame)

        titleLabel.position = CGPoint(x: Metrics.margin, y: size.height - 38)
        demoTag.position = CGPoint(x: titleLabel.frame.maxX + 12 + demoTag.frame.width / 2, y: titleLabel.frame.midY)
        countLabel.position = CGPoint(x: size.width - Metrics.margin - 10, y: size.height - 38)
        positionLegend()
        // The lounge is a rug-coloured strip along the bottom of the floor.
        let rug = CGRect(x: frame.minX + 10, y: frame.minY + 10, width: frame.width - 20,
                         height: Metrics.loungeTop - frame.minY - 10)
        lounge.path = CGPath(roundedRect: rug, cornerWidth: 8, cornerHeight: 8, transform: nil)
        loungeLabel.position = CGPoint(x: rug.minX + 10, y: rug.maxY - 8)

        // Both messages sit in the open floor between the stations and the lounge. The empty
        // state is the taller of the two, so it shrinks to fit when the window is short.
        let stationsBottom = size.height - Metrics.stationY - 28
        let openMiddle = (stationsBottom + Metrics.loungeTop) / 2
        let emptyScale = min(1, (stationsBottom - Metrics.loungeTop) / 236)
        emptyState.setScale(emptyScale)
        emptyState.position = CGPoint(x: size.width / 2, y: openMiddle + 26 * emptyScale)
        // The note's text hangs about 24pt below its origin and its mug rises above it.
        let noteMiddle = (BreakNoteNode.headroom - 24) / 2
        breakNote.position = CGPoint(x: size.width / 2, y: openMiddle - noteMiddle)
        for (stage, node) in stations {
            node.position = CGPoint(x: stationX(stage), y: size.height - Metrics.stationY)
        }
    }

    /// Where a agent sits on each of the lounge's couches: one at either end and one in the
    /// middle, listed left to right.
    private var loungeCouches: [CGPoint] {
        [120, size.width / 2, size.width - 120].map { CGPoint(x: $0, y: Metrics.loungeSeatY) }
    }

    /// Puts the lounge's furniture in place: the couches, a lamp at the left end, a plant at
    /// the right, and a lamp and a plant either side of the middle couch. Only rebuilt when the floor changes size or style.
    private func furnishLounge() {
        let key = "\(size)-\(PixelArt.style)-\(Theme.current)"
        guard key != furnishedFor else { return }
        furnishedFor = key
        furniture.removeAllChildren()

        /// Stands a piece on the floor line the lounge's agents stand on.
        func place(_ item: PixelArt.Furniture, x: CGFloat) {
            let node = SKSpriteNode(texture: PixelArt.furniture(item))
            node.size = PixelArt.spriteSize(item.size, pixel: AgentNode.pixel)
            let height = CGFloat(item.size.rows) * AgentNode.pixel
            node.position = CGPoint(x: x, y: Metrics.loungeSeatY - AgentNode.feet + height / 2)
            furniture.addChild(node)
        }
        for couch in loungeCouches { place(.couch, x: couch.x) }
        place(.lamp, x: 44)
        place(.plant, x: size.width - 44)
        // The middle couch has one of each beside it, just outside its sitter's things.
        place(.lamp, x: size.width / 2 - 62)
        place(.plant, x: size.width / 2 + 62)
        if Theme.current == .shire { buildHillHouses() }
        if Theme.current == .santaClaude { buildChristmasLounge() }
    }

    /// The Shire's lounge: a grassy hill along its back, dug into with round-doored houses with
    /// plastered fronts, brick arches, round windows, lanterns and flower pots, and chimneys
    /// puffing on the hilltop. Behind the furniture and the agents.
    private func buildHillHouses() {
        let hill = SKNode()
        hill.zPosition = -0.5
        furniture.addChild(hill)
        let top = Metrics.loungeTop - 10
        let base: CGFloat = 92
        let left: CGFloat = 26
        let right = size.width - 26

        // The hill: a long mound whose top rolls in gentle humps.
        let mound = CGMutablePath()
        mound.move(to: CGPoint(x: left, y: base))
        let humps = max(3, Int((right - left) / 220))
        for hump in 0..<humps {
            let x0 = left + (right - left) * CGFloat(hump) / CGFloat(humps)
            let x1 = left + (right - left) * CGFloat(hump + 1) / CGFloat(humps)
            let peak = top - (hump.isMultiple(of: 2) ? 0 : 14)
            mound.addLine(to: CGPoint(x: x0, y: top - 26))
            mound.addQuadCurve(to: CGPoint(x: x1, y: top - 26), control: CGPoint(x: (x0 + x1) / 2, y: peak + 20))
        }
        mound.addLine(to: CGPoint(x: right, y: base))
        mound.closeSubpath()
        let grass = SKShapeNode(path: mound)
        grass.fillColor = NSColor(srgbRed: 0.36, green: 0.58, blue: 0.24, alpha: 1)
        grass.strokeColor = NSColor(srgbRed: 0.24, green: 0.42, blue: 0.15, alpha: 1)
        grass.lineWidth = 2
        hill.addChild(grass)

        // The houses, built into the hillside: a yellow plastered front under a curved wooden
        // eave with grass growing over it, a round door in a brick arch standing a little
        // open, round leaded windows either side, a lantern over the door, flower pots and
        // bushes round the step, and a chimney up on the grass.
        let doors: [NSColor] = [
            NSColor(srgbRed: 0.20, green: 0.46, blue: 0.24, alpha: 1), // green
            NSColor(srgbRed: 0.86, green: 0.68, blue: 0.20, alpha: 1), // yellow
            NSColor(srgbRed: 0.62, green: 0.18, blue: 0.14, alpha: 1), // red
            NSColor(srgbRed: 0.20, green: 0.34, blue: 0.60, alpha: 1), // blue
        ]
        let plaster = NSColor(srgbRed: 0.88, green: 0.74, blue: 0.42, alpha: 1)
        let wood = NSColor(srgbRed: 0.42, green: 0.27, blue: 0.13, alpha: 1)
        let brick = NSColor(srgbRed: 0.72, green: 0.38, blue: 0.25, alpha: 1)
        let mortar = NSColor(srgbRed: 0.52, green: 0.30, blue: 0.20, alpha: 1)
        let leaf = NSColor(srgbRed: 0.22, green: 0.42, blue: 0.16, alpha: 1)
        let blooms: [NSColor] = [
            NSColor(srgbRed: 0.95, green: 0.45, blue: 0.55, alpha: 1), NSColor(srgbRed: 0.98, green: 0.92, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.70, green: 0.62, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.98, green: 0.62, blue: 0.25, alpha: 1),
        ]
        func ring(_ radius: CGFloat, at centre: CGPoint, color: NSColor, width: CGFloat, bricks: Bool = false) {
            let circle = CGPath(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2),
                                transform: nil)
            let under = SKShapeNode(path: circle)
            under.strokeColor = bricks ? mortar : color
            under.lineWidth = width
            hill.addChild(under)
            guard bricks else { return }
            // Bricks: the ring broken into short lengths, mortar showing between them.
            let laid = SKShapeNode(path: circle.copy(dashingWithPhase: 0, lengths: [5, 1.5]))
            laid.strokeColor = color
            laid.lineWidth = width - 1
            hill.addChild(laid)
        }
        let spots: [CGFloat] = [0.20, 0.40, 0.60, 0.80].map { left + (right - left) * $0 }
        for (index, x) in spots.enumerated() {
            let doorY = base + 26
            let doorRadius: CGFloat = 19

            // The plastered front, round-topped, set into the hill.
            let front = CGMutablePath()
            front.move(to: CGPoint(x: x - 58, y: base))
            front.addLine(to: CGPoint(x: x - 58, y: doorY + 14))
            front.addQuadCurve(to: CGPoint(x: x + 58, y: doorY + 14), control: CGPoint(x: x, y: doorY + 62))
            front.addLine(to: CGPoint(x: x + 58, y: base))
            front.closeSubpath()
            let wall = SKShapeNode(path: front)
            wall.fillColor = plaster
            wall.strokeColor = .clear
            hill.addChild(wall)

            // The eave: a curved wooden beam over the front, on posts, with grass on top.
            let eavePath = CGMutablePath()
            eavePath.move(to: CGPoint(x: x - 62, y: doorY + 14))
            eavePath.addQuadCurve(to: CGPoint(x: x + 62, y: doorY + 14), control: CGPoint(x: x, y: doorY + 64))
            let turf = SKShapeNode(path: eavePath)
            turf.strokeColor = NSColor(srgbRed: 0.34, green: 0.56, blue: 0.22, alpha: 1)
            turf.lineWidth = 9
            turf.lineCap = .round
            turf.position = CGPoint(x: 0, y: 5)
            hill.addChild(turf)
            let eave = SKShapeNode(path: eavePath)
            eave.strokeColor = wood
            eave.lineWidth = 4
            eave.lineCap = .round
            hill.addChild(eave)
            for postX: CGFloat in [-50, -20, 20, 50] {
                let rise = 50 * (1 - (postX / 62) * (postX / 62)) * 0.5
                let post = SKShapeNode(rect: CGRect(x: x + postX - 2, y: doorY + 14 + rise - 10, width: 4, height: 10))
                post.fillColor = wood
                post.strokeColor = .clear
                hill.addChild(post)
            }

            // The door: dark inside, the door itself swung a little open, in a brick arch.
            let inside = SKShapeNode(circleOfRadius: doorRadius)
            inside.fillColor = NSColor(srgbRed: 0.12, green: 0.08, blue: 0.05, alpha: 1)
            inside.strokeColor = .clear
            inside.position = CGPoint(x: x, y: doorY)
            hill.addChild(inside)
            let door = SKShapeNode(ellipseOf: CGSize(width: doorRadius * 1.7, height: doorRadius * 2))
            door.fillColor = doors[index % doors.count]
            door.strokeColor = .clear
            door.position = CGPoint(x: x + 4, y: doorY)
            hill.addChild(door)
            let planks = CGMutablePath()
            for offset: CGFloat in [-8, -2.7, 2.7, 8] {
                let half = sqrt(max(0, 1 - (offset / (doorRadius * 0.85)) * (offset / (doorRadius * 0.85)))) * doorRadius
                planks.move(to: CGPoint(x: x + 4 + offset, y: doorY - half))
                planks.addLine(to: CGPoint(x: x + 4 + offset, y: doorY + half))
            }
            let plankLines = SKShapeNode(path: planks)
            plankLines.strokeColor = NSColor(white: 0, alpha: 0.22)
            plankLines.lineWidth = 1
            hill.addChild(plankLines)
            let knob = SKShapeNode(circleOfRadius: 2.2)
            knob.fillColor = NSColor(srgbRed: 0.98, green: 0.82, blue: 0.35, alpha: 1)
            knob.strokeColor = .clear
            knob.position = CGPoint(x: x + 4, y: doorY)
            hill.addChild(knob)
            ring(doorRadius + 4, at: CGPoint(x: x, y: doorY), color: brick, width: 6, bricks: true)

            // Two stone steps up to the door.
            for (step, width) in [(0, 46), (1, 36)] as [(Int, CGFloat)] {
                let slab = SKShapeNode(rect: CGRect(x: x - width / 2, y: base - 7 + CGFloat(step) * 5, width: width, height: 5),
                                       cornerRadius: 2)
                slab.fillColor = NSColor(srgbRed: 0.66, green: 0.62, blue: 0.54, alpha: 1)
                slab.strokeColor = NSColor(srgbRed: 0.45, green: 0.42, blue: 0.36, alpha: 1)
                slab.lineWidth = 0.8
                hill.addChild(slab)
            }

            // A lantern hanging over the door, glowing.
            let lantern = SKShapeNode(rect: CGRect(x: x - 3, y: doorY + doorRadius + 11, width: 6, height: 7), cornerRadius: 1.5)
            lantern.fillColor = NSColor(srgbRed: 1, green: 0.86, blue: 0.48, alpha: 1)
            lantern.strokeColor = NSColor(white: 0.15, alpha: 1)
            lantern.lineWidth = 1
            hill.addChild(lantern)
            let shine = SKShapeNode(circleOfRadius: 9)
            shine.fillColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.45, alpha: 0.18)
            shine.strokeColor = .clear
            shine.position = CGPoint(x: x, y: doorY + doorRadius + 14)
            hill.addChild(shine)
            shine.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 1.4 + Double(index) * 0.2), .fadeAlpha(to: 1, duration: 1.2)])))

            // Round windows either side, in brick, with leaded panes and a warm glow.
            for side: CGFloat in [-1, 1] {
                let centre = CGPoint(x: x + side * 40, y: doorY + 7)
                let pane = SKShapeNode(circleOfRadius: 8)
                pane.fillColor = NSColor(srgbRed: 1, green: 0.84, blue: 0.50, alpha: 1)
                pane.strokeColor = NSColor(srgbRed: 0.20, green: 0.42, blue: 0.24, alpha: 1)
                pane.lineWidth = 2
                pane.position = centre
                hill.addChild(pane)
                let lattice = CGMutablePath()
                for d: CGFloat in [-4, 0, 4] {
                    lattice.move(to: CGPoint(x: centre.x + d - 5, y: centre.y - 5))
                    lattice.addLine(to: CGPoint(x: centre.x + d + 5, y: centre.y + 5))
                    lattice.move(to: CGPoint(x: centre.x + d - 5, y: centre.y + 5))
                    lattice.addLine(to: CGPoint(x: centre.x + d + 5, y: centre.y - 5))
                }
                let leading = SKShapeNode(path: lattice)
                leading.strokeColor = NSColor(white: 0.2, alpha: 0.55)
                leading.lineWidth = 0.7
                hill.addChild(leading)
                ring(11, at: centre, color: brick, width: 4, bricks: true)
            }

            // Bushes and flower pots round the step.
            for side: CGFloat in [-1, 1] {
                for (dx, radius) in [(52, 10), (61, 8), (44, 7)] as [(CGFloat, CGFloat)] {
                    let bush = SKShapeNode(circleOfRadius: radius)
                    bush.fillColor = leaf
                    bush.strokeColor = .clear
                    bush.position = CGPoint(x: x + side * dx, y: base + radius - 3)
                    hill.addChild(bush)
                }
                let pot = CGMutablePath()
                pot.addLines(between: [CGPoint(x: -6, y: 9), CGPoint(x: 6, y: 9), CGPoint(x: 4.5, y: 0), CGPoint(x: -4.5, y: 0)])
                pot.closeSubpath()
                let planter = SKShapeNode(path: pot)
                planter.fillColor = NSColor(srgbRed: 0.78, green: 0.44, blue: 0.28, alpha: 1)
                planter.strokeColor = .clear
                planter.position = CGPoint(x: x + side * 30, y: base - 2)
                hill.addChild(planter)
                for flower in 0..<4 {
                    let bloom = SKShapeNode(circleOfRadius: 2.4)
                    bloom.fillColor = blooms[(flower + index + (side > 0 ? 2 : 0)) % blooms.count]
                    bloom.strokeColor = .clear
                    bloom.position = CGPoint(x: x + side * 30 + CGFloat(flower - 2) * 3 + 1.5, y: base + 9 + CGFloat(flower % 2) * 3)
                    hill.addChild(bloom)
                }
            }

            // A chimney up on the grass, with smoke curling up.
            let side: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let chimneyX = x - side * 30
            let chimneyTop = top - 16
            let chimney = SKShapeNode(rect: CGRect(x: chimneyX - 5, y: chimneyTop - 14, width: 10, height: 18), cornerRadius: 1.5)
            chimney.fillColor = NSColor(srgbRed: 0.55, green: 0.40, blue: 0.30, alpha: 1)
            chimney.strokeColor = NSColor(srgbRed: 0.35, green: 0.24, blue: 0.16, alpha: 1)
            hill.addChild(chimney)
            for puffIndex in 0..<3 {
                let puff = SKShapeNode(circleOfRadius: 4)
                puff.fillColor = NSColor(white: 0.92, alpha: 0.7)
                puff.strokeColor = .clear
                let home = CGPoint(x: chimneyX, y: chimneyTop + 6)
                puff.position = home
                puff.alpha = 0
                puff.run(.sequence([
                    .wait(forDuration: Double(puffIndex) * 1.1 + Double(index) * 0.4),
                    .repeatForever(.sequence([
                        .group([.move(to: home, duration: 0), .scale(to: 0.6, duration: 0)]),
                        .group([.moveBy(x: 14, y: 34, duration: 3.3), .scale(to: 1.8, duration: 3.3),
                                .sequence([.fadeAlpha(to: 0.8, duration: 0.6), .fadeOut(withDuration: 2.7)])]),
                    ])),
                ]))
                hill.addChild(puff)
            }
        }
    }

    private func layoutAgents(animated: Bool) {
        let topLevel = agents.filter { !$0.isSubagent }
        var targets: [String: (CGPoint, String)] = [:]

        for (stageIndex, stage) in Stage.allCases.enumerated() {
            let here = topLevel.filter { $0.isWorking && $0.stage == stage }
            // Neighbouring stations start half a row apart so their labels interleave.
            let top = size.height - Metrics.firstRowY - (stageIndex.isMultiple(of: 2) ? 0 : Metrics.rowStep / 2)
            let floor = Metrics.loungeTop + 34
            let step = here.count > 1 ? min(Metrics.rowStep, max(18, (top - floor) / CGFloat(here.count - 1))) : 0
            for (row, agent) in here.enumerated() {
                targets[agent.id] = (CGPoint(x: stationX(stage), y: top - CGFloat(row) * step), stage.title)
            }
        }

        // Everyone not at a station rests in the lounge. Sitters take the couches; bed sleepers
        // take the floor between them. If the floor is full and a couch is free, a bed sleeper
        // makes do with the couch. Only when there is no room anywhere do they bunch up.
        let resting = topLevel.filter { !($0.isWorking && $0.stage != nil) }
        furnishLounge()
        let couches = loungeCouches
        let gaps = zip(couches, couches.dropFirst()).map { ($0.x + 100, max($1.x - 100, $0.x + 200)) }
        let floorRoom = gaps.reduce(0) { $0 + max(1, Int(($1.1 - $1.0) / 165)) }

        var freeCouches = couches
        var onTheFloor: [AgentSnapshot] = []
        func sit(_ agent: AgentSnapshot) {
            targets[agent.id] = (freeCouches.removeFirst(), "the lounge")
            agentNodes[agent.id]?.hasCouch = true
        }
        let sitters = resting.filter { agentNodes[$0.id]?.persona.sleepsInBed == false }
        let bedSleepers = resting.filter { agentNodes[$0.id]?.persona.sleepsInBed != false }
        var crowdedOut: [AgentSnapshot] = []
        for agent in sitters {
            if freeCouches.isEmpty { crowdedOut.append(agent) } else { sit(agent) }
        }
        for agent in bedSleepers {
            if onTheFloor.count < floorRoom {
                onTheFloor.append(agent)
            } else if !freeCouches.isEmpty {
                sit(agent)
            } else {
                crowdedOut.append(agent)
            }
        }
        onTheFloor += crowdedOut
        onTheFloor.forEach { agentNodes[$0.id]?.hasCouch = false }

        // The floor is shared out evenly between the gaps, left to right. In a crowded gap
        // every other one sits further back so neighbouring thought bubbles do not collide.
        var next = 0
        for (gapIndex, gap) in gaps.enumerated() {
            let remainingGaps = gaps.count - gapIndex
            let share = (onTheFloor.count - next + remainingGaps - 1) / remainingGaps
            let column = (gap.1 - gap.0) / CGFloat(max(share, 1))
            let crowded = column < 165
            for index in 0..<share {
                let x = gap.0 + column * (CGFloat(index) + 0.5)
                let y = Metrics.loungeSeatY + (crowded && !index.isMultiple(of: 2) ? 46 : 0)
                targets[onTheFloor[next].id] = (CGPoint(x: x, y: y), "the lounge")
                next += 1
            }
        }

        // Subagents trail just behind whoever spawned them.
        var siblings: [String: Int] = [:]
        for agent in agents where agent.isSubagent {
            guard let parent = agent.parentID, let (point, name) = targets[parent] else { continue }
            let slot = siblings[parent, default: 0]
            siblings[parent] = slot + 1
            targets[agent.id] = (CGPoint(x: point.x + 46 + CGFloat(slot) * 24, y: point.y - 14), name)
        }

        for (id, (point, name)) in targets {
            guard let agentNode = agentNodes[id] else { continue }
            agentNode.move(to: point, heading: name, animated: animated)
            agentNode.zPosition = 100 - point.y / 10
        }
    }

    // MARK: Ambience

    /// A battered pointed hat with a crumpled face in its folds. Its tip flops over,
    /// it rocks a little, and every few seconds the fold that is its mouth opens and closes.
    private func addSortingHat(at base: CGPoint) {
        let felt = NSColor(srgbRed: 0.42, green: 0.28, blue: 0.16, alpha: 1)
        let shadow = NSColor(srgbRed: 0.24, green: 0.15, blue: 0.08, alpha: 1)
        let hat = SKNode()
        hat.position = base

        let cone = CGMutablePath()
        cone.addLines(between: [
            CGPoint(x: -21, y: 6), CGPoint(x: -17, y: 22), CGPoint(x: -13, y: 34), CGPoint(x: -7, y: 46),
            CGPoint(x: 0, y: 55), CGPoint(x: 9, y: 60), CGPoint(x: 19, y: 55), CGPoint(x: 13, y: 50),
            CGPoint(x: 10, y: 41), CGPoint(x: 15, y: 27), CGPoint(x: 21, y: 6),
        ])
        cone.closeSubpath()
        let body = SKShapeNode(path: cone)
        body.fillColor = felt
        body.strokeColor = shadow
        body.lineWidth = 1.5
        body.lineJoin = .round
        hat.addChild(body)

        let brim = SKShapeNode(ellipseOf: CGSize(width: 60, height: 13))
        brim.fillColor = shadow
        brim.strokeColor = NSColor(srgbRed: 0.16, green: 0.10, blue: 0.05, alpha: 1)
        brim.position = CGPoint(x: 0, y: 4)
        hat.addChild(brim)

        // The face: two creased brows and a mouth fold.
        for side: CGFloat in [-1, 1] {
            let brow = CGMutablePath()
            brow.move(to: CGPoint(x: side * 10, y: 25))
            brow.addQuadCurve(to: CGPoint(x: side * 3, y: 23), control: CGPoint(x: side * 7, y: 28))
            let crease = SKShapeNode(path: brow)
            crease.strokeColor = shadow
            crease.lineWidth = 2
            crease.lineCap = .round
            hat.addChild(crease)
        }
        let mouth = SKShapeNode(ellipseOf: CGSize(width: 14, height: 3))
        mouth.fillColor = NSColor(srgbRed: 0.10, green: 0.06, blue: 0.03, alpha: 1)
        mouth.strokeColor = .clear
        mouth.position = CGPoint(x: 0, y: 14)
        hat.addChild(mouth)

        ambience.addChild(hat)
        let rock = SKAction.sequence([.rotate(toAngle: 0.05, duration: 1.8), .rotate(toAngle: -0.05, duration: 1.8)])
        rock.timingMode = .easeInEaseOut
        hat.run(.repeatForever(rock))
        let word = SKAction.sequence([.scaleY(to: 2.6, duration: 0.12), .scaleY(to: 1, duration: 0.12)])
        mouth.run(.repeatForever(.sequence([.wait(forDuration: 4), .repeat(word, count: 4), .wait(forDuration: 1)])))
    }

    /// One floating candle, bobbing gently with its flame flickering.
    private func addCandle(at position: CGPoint, scale: CGFloat, random: inout StableRandom) {
        let candle = SKNode()
        let wax = SKShapeNode(rect: CGRect(x: -2.5, y: -9, width: 5, height: 14), cornerRadius: 1)
        wax.fillColor = NSColor(srgbRed: 0.96, green: 0.93, blue: 0.84, alpha: 1)
        wax.strokeColor = .clear
        candle.addChild(wax)
        let glow = SKShapeNode(circleOfRadius: 9)
        glow.fillColor = NSColor(srgbRed: 1, green: 0.75, blue: 0.3, alpha: 0.16)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: 0, y: 9)
        candle.addChild(glow)
        let flame = SKShapeNode(ellipseOf: CGSize(width: 3.6, height: 6))
        flame.fillColor = NSColor(srgbRed: 1, green: 0.82, blue: 0.35, alpha: 1)
        flame.strokeColor = .clear
        flame.position = CGPoint(x: 0, y: 8.5)
        candle.addChild(flame)
        candle.position = position
        candle.setScale(scale)
        candle.name = Self.fixedDecor
        ambience.addChild(candle)
        let bob = SKAction.sequence([.moveBy(x: 0, y: 5, duration: 1.6 + Double(random.unit())),
                                     .moveBy(x: 0, y: -5, duration: 1.6 + Double(random.unit()))])
        bob.timingMode = .easeInEaseOut
        candle.run(.repeatForever(bob))
        let flicker = SKAction.sequence([
            .scaleY(to: 1.25, duration: 0.12), .scaleY(to: 0.9, duration: 0.09),
            .scaleY(to: 1.1, duration: 0.15), .scaleY(to: 1, duration: 0.1),
        ])
        flame.run(.repeatForever(.sequence([flicker, .wait(forDuration: 0.2 + Double(random.unit()) * 0.6)])))
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.3), .fadeAlpha(to: 1, duration: 0.4)])))
    }

    /// The great hall: stars twinkling overhead with a crescent moon, house banners and the
    /// sorting hat hanging between the stations, floating candles lining the swimlanes with a
    /// tall arched window under each file, and an owl gliding across every so often.
    private func fillGreatHall(in frame: CGRect, random: inout StableRandom) {
        let ground = Metrics.loungeTop + 2
        let stone = NSColor(srgbRed: 0.16, green: 0.14, blue: 0.17, alpha: 1)
        let warm = NSColor(srgbRed: 1, green: 0.78, blue: 0.42, alpha: 1)

        // The enchanted ceiling: stars over the whole hall.
        let skyBottom = ground
        if frame.maxY > skyBottom {
            for _ in 0..<Int(frame.width * (frame.maxY - skyBottom) / 2200) {
                let star = SKShapeNode(circleOfRadius: 0.6 + random.unit() * 1.1)
                star.fillColor = NSColor(white: 1, alpha: 1)
                star.strokeColor = .clear
                star.position = CGPoint(x: frame.minX + random.unit() * frame.width,
                                        y: skyBottom + random.unit() * (frame.maxY - skyBottom))
                star.alpha = 0.2 + random.unit() * 0.6
                let pace = 1.2 + Double(random.unit()) * 2.4
                star.run(.repeatForever(.sequence([.fadeAlpha(to: 0.08, duration: pace),
                                                   .fadeAlpha(to: star.alpha, duration: pace)])))
                star.name = Self.fixedDecor
                ambience.addChild(star)
            }
        }
        // A crescent moon: a pale disc with a sky-coloured one laid over it.
        let moonAt = CGPoint(x: frame.midX + frame.width * 0.28, y: min(frame.maxY - 150, ground + 260))
        let moon = SKShapeNode(circleOfRadius: 13)
        moon.fillColor = NSColor(srgbRed: 1, green: 0.96, blue: 0.82, alpha: 0.9)
        moon.strokeColor = .clear
        moon.position = moonAt
        ambience.addChild(moon)
        let bite = SKShapeNode(circleOfRadius: 12)
        bite.fillColor = Theme.colors.panel
        bite.strokeColor = .clear
        bite.position = CGPoint(x: moonAt.x + 6, y: moonAt.y + 4)
        ambience.addChild(bite)

        // The swimlanes: one column per station. Their edges are where the candles hang, with a
        // window below each file of candles.
        let stages = Stage.allCases
        let spacing = stages.count > 1 ? stationX(stages[1]) - stationX(stages[0]) : 160
        var laneEdges = [stationX(stages[0]) - spacing / 2]
        laneEdges += (0..<(stages.count - 1)).map { (stationX(stages[$0]) + stationX(stages[$0 + 1])) / 2 }
        laneEdges.append(stationX(stages[stages.count - 1]) + spacing / 2)
        let windowWidth = min(48, spacing * 0.32)
        laneEdges = laneEdges.filter { $0 - windowWidth / 2 > frame.minX + 8 && $0 + windowWidth / 2 < frame.maxX - 8 }

        // A tall arched window glowing with firelight in each file of candles, halfway up the
        // lane between the lounge and the stations.
        let stationTop = size.height - Metrics.stationY + 28
        let windowHeight: CGFloat = 100
        let windowBase = (ground + stationTop) / 2 - windowHeight / 2
        for centre in laneEdges {
            let width = windowWidth
            let height = windowHeight
            let window = CGMutablePath()
            window.move(to: CGPoint(x: centre - width / 2, y: windowBase))
            window.addLine(to: CGPoint(x: centre - width / 2, y: windowBase + height - width / 2))
            window.addArc(center: CGPoint(x: centre, y: windowBase + height - width / 2), radius: width / 2,
                          startAngle: .pi, endAngle: 0, clockwise: true)
            window.addLine(to: CGPoint(x: centre + width / 2, y: windowBase))
            window.closeSubpath()
            let frameNode = SKShapeNode(path: window)
            frameNode.fillColor = warm.withAlphaComponent(0.16)
            frameNode.strokeColor = stone.blended(withFraction: 0.5, of: warm) ?? stone
            frameNode.lineWidth = 3
            frameNode.name = Self.fixedDecor
            ambience.addChild(frameNode)
            // Leading between the panes.
            let leading = CGMutablePath()
            leading.move(to: CGPoint(x: centre, y: windowBase))
            leading.addLine(to: CGPoint(x: centre, y: windowBase + height))
            for pane in 1...3 {
                let y = windowBase + (height - width / 2) * CGFloat(pane) / 4
                leading.move(to: CGPoint(x: centre - width / 2, y: y))
                leading.addLine(to: CGPoint(x: centre + width / 2, y: y))
            }
            let lines = SKShapeNode(path: leading)
            lines.strokeColor = stone
            lines.lineWidth = 1.5
            lines.name = Self.fixedDecor
            ambience.addChild(lines)
            frameNode.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.75, duration: 1.8 + Double(random.unit())), .fadeAlpha(to: 1, duration: 1.6),
            ])))
        }

        // The four house banners hang in the gaps between the stations, leaving the middle gap
        // empty so they sit in pairs either side. Each has a trim stripe, a crest and a
        // swallowtail hem, on a gold rod level with the tops of the station tiles.
        let banners = Theme.colors.banners.isEmpty ? [Theme.colors.activeStation] : Theme.colors.banners
        let trims: [NSColor] = [
            NSColor(srgbRed: 0.95, green: 0.78, blue: 0.30, alpha: 1), // gold
            NSColor(srgbRed: 0.80, green: 0.82, blue: 0.86, alpha: 1), // silver
            NSColor(srgbRed: 0.80, green: 0.55, blue: 0.30, alpha: 1), // bronze
            NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1), // black
        ]
        let middle = (stages.count - 1) / 2
        let gaps = (0..<(stages.count - 1)).filter { $0 != middle }
        let bannerLength: CGFloat = 104
        for (house, gap) in gaps.prefix(4).enumerated() {
            let a = stationX(stages[gap]), b = stationX(stages[gap + 1])
            let width = max(14, min(32, (b - a) - 84 - 14))
            // Drawn round the middle of its rod, so it sways from there.
            let banner = SKNode()
            banner.position = CGPoint(x: (a + b) / 2, y: stationTop)
            let cloth = CGMutablePath()
            cloth.addLines(between: [
                CGPoint(x: -width / 2, y: 0), CGPoint(x: width / 2, y: 0), CGPoint(x: width / 2, y: -bannerLength),
                CGPoint(x: 0, y: -bannerLength + 12), CGPoint(x: -width / 2, y: -bannerLength),
            ])
            cloth.closeSubpath()
            let fabric = SKShapeNode(path: cloth)
            fabric.fillColor = banners[house % banners.count]
            fabric.strokeColor = trims[house % trims.count]
            fabric.lineWidth = 2
            banner.addChild(fabric)
            let stripe = SKShapeNode(rect: CGRect(x: -width / 2, y: -16, width: width, height: 4))
            stripe.fillColor = trims[house % trims.count]
            stripe.strokeColor = .clear
            banner.addChild(stripe)
            let crest = SKShapeNode(circleOfRadius: width * 0.2)
            crest.fillColor = trims[house % trims.count]
            crest.strokeColor = .clear
            crest.position = CGPoint(x: 0, y: -34)
            banner.addChild(crest)
            let rod = SKShapeNode(rect: CGRect(x: -width / 2 - 4, y: 0, width: width + 8, height: 3), cornerRadius: 1.5)
            rod.fillColor = warm
            rod.strokeColor = .clear
            banner.addChild(rod)
            ambience.addChild(banner)
            // A slow sway, as if in a draught.
            let sway = SKAction.sequence([.rotate(toAngle: 0.03, duration: 2.2), .rotate(toAngle: -0.03, duration: 2.2)])
            sway.timingMode = .easeInEaseOut
            banner.run(.repeatForever(sway))
        }

        // In the middle gap, where there is no banner, the old patched hat that sorts the
        // pupils into their houses, rocking gently and now and then muttering.
        let hatGap = (stationX(stages[middle]) + stationX(stages[middle + 1])) / 2
        addSortingHat(at: CGPoint(x: hatGap, y: stationTop - 62))

        // The floating candles line the swimlanes: a file of them down each gap between the
        // stations' columns and along both outer edges, so they frame the agents' lanes
        // without hanging in front of anyone.
        let highest = stationTop - bannerLength - 26
        let lowest = ground + 22
        let rows = max(1, Int((highest - lowest) / 52) + 1)
        for (column, x) in laneEdges.enumerated() {
            for row in 0..<rows {
                let y = rows == 1 ? highest : highest - (highest - lowest) * CGFloat(row) / CGFloat(rows - 1)
                // Every other column sits half a step lower, so the files do not line up in rows.
                let stagger: CGFloat = column.isMultiple(of: 2) ? 0 : 14
                let at = y - stagger
                // The window takes the middle of the file.
                if at > windowBase - 22 && at < windowBase + windowHeight + 8 { continue }
                addCandle(at: CGPoint(x: x, y: at), scale: 0.85, random: &random)
            }
        }

        // An owl gliding across the hall now and then, wings beating.
        let owl = SKNode()
        let body = SKShapeNode(ellipseOf: CGSize(width: 12, height: 9))
        body.fillColor = NSColor(srgbRed: 0.93, green: 0.92, blue: 0.88, alpha: 1)
        body.strokeColor = .clear
        owl.addChild(body)
        for side: CGFloat in [-1, 1] {
            let wing = SKShapeNode(ellipseOf: CGSize(width: 14, height: 4))
            wing.fillColor = NSColor(srgbRed: 0.86, green: 0.84, blue: 0.80, alpha: 1)
            wing.strokeColor = .clear
            wing.position = CGPoint(x: side * 9, y: 2)
            let up = SKAction.rotate(toAngle: side * 0.6, duration: 0.18)
            let down = SKAction.rotate(toAngle: -side * 0.3, duration: 0.18)
            wing.run(.repeatForever(.sequence([up, down])))
            owl.addChild(wing)
        }
        owl.alpha = 0
        let flightY = min(frame.maxY - 120, ground + 230)
        owl.position = CGPoint(x: frame.minX - 30, y: flightY)
        ambience.addChild(owl)
        let glide = SKAction.moveBy(x: frame.width + 60, y: -30, duration: 7)
        owl.run(.repeatForever(.sequence([
            .wait(forDuration: 6),
            .move(to: CGPoint(x: frame.minX - 30, y: flightY), duration: 0),
            .fadeIn(withDuration: 0.2),
            .group([glide, .sequence([.moveBy(x: 0, y: 12, duration: 3.5), .moveBy(x: 0, y: -12, duration: 3.5)])]),
            .fadeOut(withDuration: 0.2),
        ])))
    }

    /// The Shire: rolling hills the whole way up the floor, wildflowers dotted through the
    /// grass, and butterflies flitting about.
    private func fillShire(in frame: CGRect, random: inout StableRandom) {
        // Rolling hills the whole way up the floor: ridge after ridge, the far ones paler and
        // the near ones a deeper green, each covering the foot of the one behind it.
        let ground = Metrics.loungeTop + 2
        let layers = 3
        let far = (r: CGFloat(0.60), g: CGFloat(0.78), b: CGFloat(0.40))
        let near = (r: CGFloat(0.34), g: CGFloat(0.54), b: CGFloat(0.22))
        for layer in 0..<layers {
            let depth = CGFloat(layer) / CGFloat(max(layers - 1, 1))
            let ridge = frame.maxY - 26 - (frame.maxY - 26 - ground - 30) * depth
            let path = CGMutablePath()
            path.move(to: CGPoint(x: frame.minX, y: ground))
            var y = ridge + (random.unit() - 0.5) * 20
            path.addLine(to: CGPoint(x: frame.minX, y: y))
            let humps = 1 + Int(random.unit() * 2)
            let width = frame.width / CGFloat(humps)
            for hump in 0..<humps {
                let x0 = frame.minX + width * CGFloat(hump)
                let next = ridge + (random.unit() - 0.5) * 20
                let lift = 18 + random.unit() * 22
                path.addQuadCurve(to: CGPoint(x: x0 + width, y: next),
                                  control: CGPoint(x: x0 + width * (0.35 + random.unit() * 0.3), y: max(y, next) + lift))
                y = next
            }
            path.addLine(to: CGPoint(x: frame.maxX, y: ground))
            path.closeSubpath()
            let hill = SKShapeNode(path: path)
            hill.fillColor = NSColor(srgbRed: far.r + (near.r - far.r) * depth, green: far.g + (near.g - far.g) * depth,
                                     blue: far.b + (near.b - far.b) * depth, alpha: 1)
            hill.strokeColor = NSColor(srgbRed: 0.26, green: 0.44, blue: 0.16, alpha: 0.6)
            hill.lineWidth = 1.5
            ambience.addChild(hill)
        }

        let petals: [NSColor] = [
            NSColor(srgbRed: 1, green: 0.95, blue: 0.55, alpha: 1), NSColor(white: 1, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.55, blue: 0.70, alpha: 1), NSColor(srgbRed: 0.65, green: 0.70, blue: 1, alpha: 1),
        ]
        for index in 0..<Int(frame.width * frame.height / 5200) {
            let flower = SKShapeNode(circleOfRadius: 1.4 + random.unit())
            flower.fillColor = petals[index % petals.count]
            flower.strokeColor = .clear
            flower.alpha = 0.8
            flower.position = CGPoint(x: frame.minX + random.unit() * frame.width,
                                      y: Metrics.loungeTop + 6 + random.unit() * (frame.maxY - Metrics.loungeTop - 6))
            flower.name = Self.fixedDecor
            ambience.addChild(flower)
        }
        let wings: [NSColor] = [
            NSColor(srgbRed: 1, green: 0.85, blue: 0.30, alpha: 1), NSColor(white: 1, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.55, blue: 0.25, alpha: 1),
        ]
        for index in 0..<max(4, Int(frame.width / 160)) {
            let butterfly = SKNode()
            for side: CGFloat in [-1, 1] {
                let wing = SKShapeNode(ellipseOf: CGSize(width: 6, height: 7))
                wing.fillColor = wings[index % wings.count]
                wing.strokeColor = .clear
                wing.position = CGPoint(x: side * 3, y: 0)
                wing.run(.repeatForever(.sequence([.scaleX(to: 0.2, duration: 0.12), .scaleX(to: 1, duration: 0.12)])))
                butterfly.addChild(wing)
            }
            butterfly.position = CGPoint(x: frame.minX + random.unit() * frame.width,
                                         y: Metrics.loungeTop + 20 + random.unit() * (frame.maxY - Metrics.loungeTop - 80))
            ambience.addChild(butterfly)
            var moves: [SKAction] = []
            for _ in 0..<4 {
                let move = SKAction.moveBy(x: (random.unit() - 0.5) * 120, y: (random.unit() - 0.5) * 60,
                                           duration: 2.5 + Double(random.unit()) * 2)
                move.timingMode = .easeInEaseOut
                moves += [move, move.reversed()]
            }
            butterfly.run(.repeatForever(.sequence(moves)))
        }
    }

    /// Mordor: a smouldering mountain on the right, a dark tower on the left with a burning eye
    /// at its top, ash drifting down and embers rising. Everything stands on the lounge's roof
    /// line, behind the agents.
    private func fillMordor(in frame: CGRect, random: inout StableRandom) {
        let ground = Metrics.loungeTop + 2
        let rock = NSColor(srgbRed: 0.10, green: 0.045, blue: 0.035, alpha: 1)
        let fire = NSColor(srgbRed: 1, green: 0.50, blue: 0.12, alpha: 1)

        // A red glow along the horizon, as if the whole land were smouldering. Stacked bands,
        // each fainter than the one below, so it fades out softly.
        let horizon = SKNode()
        for band in 0..<8 {
            let strip = SKShapeNode(rect: CGRect(x: frame.minX, y: ground + CGFloat(band) * 14, width: frame.width, height: 14))
            strip.fillColor = NSColor(srgbRed: 0.85, green: 0.18, blue: 0.04, alpha: 0.12 * (1 - CGFloat(band) / 8))
            strip.strokeColor = .clear
            horizon.addChild(strip)
        }
        horizon.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 2.4), .fadeAlpha(to: 1, duration: 2.4)])))
        ambience.addChild(horizon)

        // The mountain, with lava glowing in its crater and running down one flank.
        let peakX = frame.maxX - min(230, frame.width * 0.2)
        let mountain = CGMutablePath()
        mountain.addLines(between: [
            CGPoint(x: peakX - 170, y: ground), CGPoint(x: peakX - 70, y: ground + 92), CGPoint(x: peakX - 24, y: ground + 142),
            CGPoint(x: peakX + 22, y: ground + 140), CGPoint(x: peakX + 64, y: ground + 96), CGPoint(x: peakX + 180, y: ground),
        ])
        mountain.closeSubpath()
        let peak = SKShapeNode(path: mountain)
        peak.fillColor = rock
        peak.strokeColor = NSColor(srgbRed: 0.40, green: 0.10, blue: 0.04, alpha: 1)
        peak.lineWidth = 1.5
        ambience.addChild(peak)
        let crater = SKShapeNode(ellipseOf: CGSize(width: 40, height: 9))
        crater.fillColor = fire
        crater.strokeColor = .clear
        crater.position = CGPoint(x: peakX - 1, y: ground + 141)
        ambience.addChild(crater)
        let lava = CGMutablePath()
        lava.addLines(between: [CGPoint(x: peakX + 8, y: ground + 138), CGPoint(x: peakX + 20, y: ground + 110),
                                CGPoint(x: peakX + 12, y: ground + 84), CGPoint(x: peakX + 34, y: ground + 52),
                                CGPoint(x: peakX + 28, y: ground + 24), CGPoint(x: peakX + 46, y: ground)])
        let flow = SKShapeNode(path: lava)
        flow.strokeColor = fire
        flow.lineWidth = 3
        flow.lineJoin = .round
        ambience.addChild(flow)
        for node in [crater, flow] {
            node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 1.3), .fadeAlpha(to: 1, duration: 1.1)])))
        }
        // Smoke rising from the crater.
        for index in 0..<6 {
            let puff = SKShapeNode(circleOfRadius: 9)
            puff.fillColor = NSColor(srgbRed: 0.25, green: 0.18, blue: 0.16, alpha: 0.55)
            puff.strokeColor = .clear
            let home = CGPoint(x: peakX, y: ground + 150)
            puff.position = home
            puff.alpha = 0
            puff.run(.sequence([
                .wait(forDuration: Double(index) * 0.9),
                .repeatForever(.sequence([
                    .group([.move(to: home, duration: 0), .scale(to: 0.6, duration: 0)]),
                    .group([.moveBy(x: -30 + random.unit() * 20, y: 90, duration: 5.4), .scale(to: 2.4, duration: 5.4),
                            .sequence([.fadeAlpha(to: 0.8, duration: 1), .fadeOut(withDuration: 4.4)])]),
                ])),
            ]))
            ambience.addChild(puff)
        }

        // The tower: a tall jagged spire whose two horns hold the eye between them.
        let towerX = frame.minX + min(150, frame.width * 0.13)
        let spire = CGMutablePath()
        spire.addLines(between: [
            CGPoint(x: towerX - 34, y: ground), CGPoint(x: towerX - 20, y: ground + 70), CGPoint(x: towerX - 15, y: ground + 150),
            CGPoint(x: towerX - 22, y: ground + 196), CGPoint(x: towerX - 6, y: ground + 168), CGPoint(x: towerX + 6, y: ground + 168),
            CGPoint(x: towerX + 22, y: ground + 196), CGPoint(x: towerX + 15, y: ground + 150), CGPoint(x: towerX + 20, y: ground + 70),
            CGPoint(x: towerX + 34, y: ground),
        ])
        spire.closeSubpath()
        let tower = SKShapeNode(path: spire)
        tower.fillColor = rock
        tower.strokeColor = NSColor(srgbRed: 0.30, green: 0.08, blue: 0.04, alpha: 1)
        tower.lineWidth = 1.5
        ambience.addChild(tower)

        let eye = SKNode()
        eye.position = CGPoint(x: towerX, y: ground + 184)
        let halo = SKShapeNode(circleOfRadius: 30)
        halo.fillColor = NSColor(srgbRed: 1, green: 0.35, blue: 0.05, alpha: 0.18)
        halo.strokeColor = .clear
        eye.addChild(halo)
        let iris = SKShapeNode(ellipseOf: CGSize(width: 30, height: 14))
        iris.fillColor = fire
        iris.strokeColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.40, alpha: 1)
        iris.lineWidth = 1.5
        eye.addChild(iris)
        let pupil = SKShapeNode(ellipseOf: CGSize(width: 3.5, height: 12))
        pupil.fillColor = NSColor(srgbRed: 0.05, green: 0.01, blue: 0, alpha: 1)
        pupil.strokeColor = .clear
        eye.addChild(pupil)
        ambience.addChild(eye)
        halo.run(.repeatForever(.sequence([.scale(to: 1.25, duration: 1.6), .scale(to: 1, duration: 1.6)])))
        // The eye sweeps slowly across the floor, keeping watch on the agents.
        let look = SKAction.sequence([
            .moveTo(x: -8, duration: 2.5), .wait(forDuration: 1.2), .moveTo(x: 8, duration: 3), .wait(forDuration: 1.5),
            .moveTo(x: 0, duration: 1.5), .wait(forDuration: 2),
        ])
        look.timingMode = .easeInEaseOut
        pupil.run(.repeatForever(look))

        // Ash drifting down over everything, and embers rising from the ground.
        for _ in 0..<Int(frame.width * frame.height / 9000) {
            let flake = SKShapeNode(circleOfRadius: 0.7 + random.unit() * 1.1)
            flake.fillColor = NSColor(white: 0.62 + random.unit() * 0.2, alpha: 0.35 + random.unit() * 0.35)
            flake.strokeColor = .clear
            let y = frame.minY + random.unit() * frame.height
            flake.position = CGPoint(x: frame.minX + random.unit() * frame.width, y: y)
            ambience.addChild(flake)
            let speed = 8 + random.unit() * 12
            let sway = SKAction.sequence([.moveBy(x: 10, y: 0, duration: 2.2), .moveBy(x: -10, y: 0, duration: 2.2)])
            sway.timingMode = .easeInEaseOut
            flake.run(.repeatForever(sway))
            flake.run(.sequence([
                .moveTo(y: frame.minY, duration: Double((y - frame.minY) / speed)),
                .repeatForever(.sequence([.moveTo(y: frame.maxY, duration: 0),
                                          .moveTo(y: frame.minY, duration: Double(frame.height / speed))])),
            ]))
        }
        for index in 0..<Int(frame.width / 45) {
            let ember = SKShapeNode(circleOfRadius: 1 + random.unit())
            ember.fillColor = NSColor(srgbRed: 1, green: 0.45 + random.unit() * 0.3, blue: 0.1, alpha: 1)
            ember.strokeColor = .clear
            let home = CGPoint(x: frame.minX + random.unit() * frame.width, y: ground + random.unit() * 40)
            ember.position = home
            ember.alpha = 0
            let duration = 4 + Double(random.unit()) * 4
            ember.run(.sequence([
                .wait(forDuration: Double(index % 8) * 0.5),
                .repeatForever(.sequence([
                    .move(to: home, duration: 0),
                    .group([.moveBy(x: (random.unit() - 0.5) * 50, y: 120 + random.unit() * 120, duration: duration),
                            .sequence([.fadeAlpha(to: 0.9, duration: duration * 0.25), .fadeOut(withDuration: duration * 0.75)])]),
                ])),
            ]))
            ambience.addChild(ember)
        }
    }

    /// Fills the floor with the theme's ambience. Placed from a fixed seed, so it looks the same
    /// every time, and only rebuilt when the floor changes size or theme.
    private func fillAmbience(in frame: CGRect) {
        let key = "\(frame.size)-\(Theme.current)"
        guard key != ambienceFor else { return }
        ambienceFor = key
        ambience.removeAllChildren()
        let mask = SKShapeNode(rect: frame, cornerRadius: 10)
        mask.fillColor = .white
        mask.strokeColor = .clear
        ambience.maskNode = mask
        var random = StableRandom(seed: key)
        func point() -> CGPoint {
            CGPoint(x: frame.minX + random.unit() * frame.width, y: frame.minY + random.unit() * frame.height)
        }
        func dot(_ radius: CGFloat, _ color: NSColor) -> SKShapeNode {
            let node = SKShapeNode(circleOfRadius: radius)
            node.fillColor = color
            node.strokeColor = .clear
            ambience.addChild(node)
            return node
        }
        let area = frame.width * frame.height

        switch Theme.colors.ambience {
        case .none:
            break
        case .stars:
            // Stars of a few sizes, each twinkling at its own pace.
            for _ in 0..<Int(area / 2600) {
                let star = dot(0.6 + random.unit() * 1.1, NSColor(white: 1, alpha: 1))
                star.position = point()
                star.name = Self.fixedDecor
                star.alpha = 0.25 + random.unit() * 0.6
                let pace = 1.2 + Double(random.unit()) * 2.4
                star.run(.repeatForever(.sequence([.fadeAlpha(to: 0.1, duration: pace),
                                                   .fadeAlpha(to: star.alpha, duration: pace)])))
            }
            // Now and then a shooting star.
            let streak = SKShapeNode(rectOf: CGSize(width: 46, height: 1.4), cornerRadius: 0.7)
            streak.fillColor = NSColor(white: 1, alpha: 0.8)
            streak.strokeColor = .clear
            streak.zRotation = -0.35
            streak.alpha = 0
            ambience.addChild(streak)
            let start = CGPoint(x: frame.minX + frame.width * 0.25, y: frame.maxY - 60)
            streak.run(.repeatForever(.sequence([
                .wait(forDuration: 5),
                .move(to: start, duration: 0),
                .group([.sequence([.fadeIn(withDuration: 0.1), .wait(forDuration: 0.4), .fadeOut(withDuration: 0.2)]),
                        .moveBy(x: 260, y: -95, duration: 0.7)]),
            ])))
        case .bubbles:
            // Bubbles rising from the sea floor and wobbling as they go.
            for index in 0..<Int(frame.width / 28) {
                let bubble = dot(1.5 + random.unit() * 3, NSColor(srgbRed: 0.6, green: 0.88, blue: 1, alpha: 0.05))
                bubble.strokeColor = NSColor(srgbRed: 0.6, green: 0.88, blue: 1, alpha: 0.35)
                bubble.lineWidth = 1
                let x = frame.minX + random.unit() * frame.width
                let rise = Double(frame.height / (24 + random.unit() * 30))
                bubble.position = CGPoint(x: x, y: frame.minY)
                let wobble = SKAction.sequence([.moveBy(x: 6, y: 0, duration: 0.9), .moveBy(x: -6, y: 0, duration: 0.9)])
                bubble.run(.repeatForever(wobble))
                // Start partway up, so the floor is full of bubbles from the first frame.
                let head = CGFloat(index % 7) / 7
                bubble.position.y = frame.minY + frame.height * head
                bubble.run(.sequence([
                    .moveTo(y: frame.maxY, duration: rise * Double(1 - head)),
                    .repeatForever(.sequence([.moveTo(y: frame.minY, duration: 0), .moveTo(y: frame.maxY, duration: rise)])),
                ]))
            }
        case .fireflies:
            // Fireflies drifting about, glowing and fading.
            for _ in 0..<Int(area / 26000) {
                let fly = dot(1.8, NSColor(srgbRed: 0.85, green: 1, blue: 0.45, alpha: 1))
                let halo = SKShapeNode(circleOfRadius: 6)
                halo.fillColor = NSColor(srgbRed: 0.85, green: 1, blue: 0.45, alpha: 0.18)
                halo.strokeColor = .clear
                fly.addChild(halo)
                fly.position = point()
                let pace = 1 + Double(random.unit()) * 1.5
                fly.alpha = random.unit()
                fly.run(.repeatForever(.sequence([.fadeAlpha(to: 0.05, duration: pace), .fadeAlpha(to: 0.9, duration: pace)])))
                var moves: [SKAction] = []
                for _ in 0..<4 {
                    let move = SKAction.moveBy(x: (random.unit() - 0.5) * 70, y: (random.unit() - 0.5) * 40,
                                               duration: 2 + Double(random.unit()) * 2)
                    move.timingMode = .easeInEaseOut
                    moves += [move, move.reversed()]
                }
                fly.run(.repeatForever(.sequence(moves)))
            }
        case .embers:
            // Warm sparks drifting up and fading out.
            for index in 0..<Int(frame.width / 30) {
                let ember = dot(1 + random.unit() * 1.2, NSColor(srgbRed: 1, green: 0.62 + random.unit() * 0.25, blue: 0.3, alpha: 1))
                let x = frame.minX + random.unit() * frame.width
                let duration = 5 + Double(random.unit()) * 5
                let climb = frame.height * (0.35 + random.unit() * 0.4)
                ember.position = CGPoint(x: x, y: frame.minY + random.unit() * frame.height * 0.3)
                let home = ember.position
                ember.alpha = 0
                ember.run(.sequence([
                    .wait(forDuration: Double(index % 9) * 0.6),
                    .repeatForever(.sequence([
                        .move(to: home, duration: 0),
                        .group([.moveBy(x: (random.unit() - 0.5) * 60, y: climb, duration: duration),
                                .sequence([.fadeAlpha(to: 0.8, duration: duration * 0.3),
                                           .fadeOut(withDuration: duration * 0.7)])]),
                    ])),
                ]))
            }
        case .snow:
            addSnowfall(in: frame, areaPerFlake: 4500, random: &random)
        case .clouds:
            // Fat cartoon clouds, white with a dark outline, drifting slowly across the sky.
            let cloudCount = max(3, Int(frame.width / 220))
            for index in 0..<cloudCount {
                let cloud = SKNode()
                let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-26, 0, 15), (-8, 9, 20), (14, 6, 17), (30, -2, 12), (2, -6, 14)]
                for outline in [true, false] {
                    for (x, y, radius) in puffs {
                        let puff = SKShapeNode(circleOfRadius: radius + (outline ? 2 : 0))
                        puff.fillColor = outline ? Theme.colors.ink : .white
                        puff.strokeColor = .clear
                        puff.position = CGPoint(x: x, y: y)
                        cloud.addChild(puff)
                    }
                }
                let scale: CGFloat = 0.7 + random.unit() * 0.6
                cloud.setScale(scale)
                cloud.alpha = 0.95
                let y: CGFloat = frame.minY + frame.height * (0.30 + random.unit() * 0.62)
                let span: CGFloat = frame.width + 140
                let share: CGFloat = CGFloat(index) / CGFloat(cloudCount)
                let start: CGFloat = frame.minX - 70 + span * share
                cloud.position = CGPoint(x: start, y: y)
                ambience.addChild(cloud)
                let speed: CGFloat = 9 + random.unit() * 8
                let exit: CGFloat = frame.maxX + 70
                cloud.run(.sequence([
                    .moveTo(x: exit, duration: Double((exit - start) / speed)),
                    .repeatForever(.sequence([.moveTo(x: frame.minX - 70, duration: 0),
                                              .moveTo(x: exit, duration: Double(span / speed))])),
                ]))
            }
        case .hyperspace:
            for _ in 0..<Int(area / 3200) {
                let star = dot(0.5 + random.unit() * 1, NSColor(white: 1, alpha: 1))
                star.position = point()
                star.name = Self.fixedDecor
                star.alpha = 0.3 + random.unit() * 0.6
            }
            // Every so often the stars stretch into streaks flying out from the middle, as if
            // the whole floor had made the jump to lightspeed.
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            let reach = hypot(frame.width, frame.height) / 2
            for _ in 0..<70 {
                let angle: CGFloat = random.unit() * 2 * CGFloat.pi
                let dx: CGFloat = cos(angle)
                let dy: CGFloat = sin(angle)
                let streak = SKSpriteNode(color: NSColor(srgbRed: 0.85, green: 0.92, blue: 1, alpha: 1),
                                          size: CGSize(width: 2, height: 1.2))
                streak.anchorPoint = CGPoint(x: 0, y: 0.5)
                streak.zRotation = angle
                let near: CGFloat = reach * (0.05 + random.unit() * 0.25)
                let home = CGPoint(x: centre.x + dx * near, y: centre.y + dy * near)
                streak.position = home
                streak.alpha = 0
                let distance: CGFloat = reach * 1.1
                let far = CGPoint(x: centre.x + dx * distance, y: centre.y + dy * distance)
                let jump = SKAction.group([
                    .move(to: far, duration: 0.9),
                    .scaleX(to: 30 + random.unit() * 50, duration: 0.9),
                    .sequence([.fadeAlpha(to: 0.9, duration: 0.25), .wait(forDuration: 0.4), .fadeOut(withDuration: 0.25)]),
                ])
                jump.timingMode = .easeIn
                // A jump about every five seconds, all streaks together give or take a moment.
                let lag = Double(random.unit()) * 0.2
                streak.run(.sequence([
                    .wait(forDuration: 2 + lag),
                    .repeatForever(.sequence([
                        jump,
                        .move(to: home, duration: 0), .scaleX(to: 1, duration: 0),
                        .wait(forDuration: 4),
                    ])),
                ]))
                ambience.addChild(streak)
            }
        case .leaves:
            // Leaves in autumn colours, tumbling down and drifting with the wind.
            let shades: [NSColor] = [
                NSColor(srgbRed: 0.90, green: 0.55, blue: 0.15, alpha: 1),
                NSColor(srgbRed: 0.80, green: 0.30, blue: 0.12, alpha: 1),
                NSColor(srgbRed: 0.95, green: 0.78, blue: 0.25, alpha: 1),
                NSColor(srgbRed: 0.55, green: 0.65, blue: 0.20, alpha: 1),
            ]
            for index in 0..<Int(frame.width / 40) {
                let leaf = SKShapeNode(ellipseOf: CGSize(width: 7, height: 3.5))
                leaf.fillColor = shades[index % shades.count]
                leaf.strokeColor = .clear
                leaf.alpha = 0.85
                let x: CGFloat = frame.minX + random.unit() * frame.width
                let y: CGFloat = frame.minY + random.unit() * frame.height
                leaf.position = CGPoint(x: x, y: y)
                ambience.addChild(leaf)
                let speed: CGFloat = 16 + random.unit() * 18
                let fall: CGFloat = frame.height + 20
                let drift: CGFloat = 60 + random.unit() * 80
                // The first fall starts wherever the leaf is; after that, from the top.
                let firstShare: CGFloat = (y - frame.minY + 10) / fall
                leaf.run(.repeatForever(.rotate(byAngle: random.chance(0.5) ? 6.3 : -6.3,
                                                duration: 2 + Double(random.unit()) * 2)))
                let sway = SKAction.sequence([.moveBy(x: 14, y: 0, duration: 1.3), .moveBy(x: -14, y: 0, duration: 1.3)])
                sway.timingMode = .easeInEaseOut
                leaf.run(.repeatForever(sway))
                leaf.run(.sequence([
                    .moveBy(x: drift * firstShare, y: -(y - frame.minY + 10), duration: Double(fall * firstShare / speed)),
                    .repeatForever(.sequence([
                        .move(to: CGPoint(x: frame.minX + random.unit() * frame.width, y: frame.maxY + 10), duration: 0),
                        .moveBy(x: drift, y: -fall, duration: Double(fall / speed)),
                    ])),
                ]))
            }
        case .mordor:
            fillMordor(in: frame, random: &random)
        case .shire:
            fillShire(in: frame, random: &random)
        case .greatHall:
            fillGreatHall(in: frame, random: &random)
        case .northPole:
            fillNorthPole(in: frame, random: &random)
        case .candles:
            // Candles hanging in the air above the floor, each bobbing gently, flames flickering.
            for _ in 0..<Int(frame.width / 55) {
                let x: CGFloat = frame.minX + 20 + random.unit() * (frame.width - 40)
                let y: CGFloat = frame.minY + frame.height * (0.42 + random.unit() * 0.5)
                addCandle(at: CGPoint(x: x, y: y), scale: 0.7 + random.unit() * 0.5, random: &random)
            }
        case .scanlines:
            // Faint CRT lines, with a brighter band rolling slowly down the screen.
            let lines = CGMutablePath()
            var y = frame.minY
            while y < frame.maxY {
                lines.move(to: CGPoint(x: frame.minX, y: y))
                lines.addLine(to: CGPoint(x: frame.maxX, y: y))
                y += 3
            }
            let scan = SKShapeNode(path: lines)
            scan.strokeColor = NSColor(white: 0, alpha: 0.35)
            scan.lineWidth = 1
            ambience.addChild(scan)
            let band = SKShapeNode(rect: CGRect(x: frame.minX, y: -20, width: frame.width, height: 40))
            band.fillColor = NSColor(srgbRed: 0.3, green: 1, blue: 0.45, alpha: 0.035)
            band.strokeColor = .clear
            ambience.addChild(band)
            band.run(.repeatForever(.sequence([.moveTo(y: frame.maxY + 20, duration: 0),
                                               .moveTo(y: frame.minY - 20, duration: 6)])))
        }
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        if countButtonFrame.contains(point) {
            onShowAgentList?()
            return
        }
        if !emptyState.isHidden, !emptyState.demoLink.isHidden,
           emptyState.demoLink.frame.insetBy(dx: -10, dy: -8).contains(convert(point, to: emptyState)) {
            onStartDemo?()
            return
        }
        // The legend doubles as a filter: click a provider to hide or show its agents.
        let inLegend = convert(point, to: legend)
        for (source, plate) in legendPlates {
            let frame = CGRect(x: plate.position.x - plate.width / 2, y: plate.position.y - plate.height / 2,
                               width: plate.width, height: plate.height)
            if frame.insetBy(dx: -3, dy: -4).contains(inLegend) {
                onToggleProvider?(source)
                return
            }
        }
        guard let agentNode = nodes(at: point).lazy.compactMap({ node -> AgentNode? in
            var current: SKNode? = node
            while let candidate = current {
                if let agentNode = candidate as? AgentNode { return agentNode }
                current = candidate.parent
            }
            return nil
        }).first, let view else { return }
        let inView = view.convert(agentNode.position, from: self)
        onSelect?(agentNode.agentID, CGPoint(x: inView.x, y: view.bounds.height - inView.y))
    }
}

/// A station tile: lit while at least one agent is working there.
private final class StationNode: SKNode {
    private let tile = SKShapeNode(rectOf: CGSize(width: 84, height: 56), cornerRadius: 7)
    private let icon = SKLabelNode()
    private let nameLabel = SKLabelNode()
    private let stage: Stage

    var isActive = false {
        didSet { if oldValue != isActive { applyState() } }
    }

    init(stage: Stage) {
        self.stage = stage
        super.init()
        tile.lineWidth = 1
        addChild(tile)
        icon.text = stage.emoji
        icon.fontSize = 20
        icon.verticalAlignmentMode = .center
        icon.position = CGPoint(x: 0, y: 8)
        addChild(icon)
        nameLabel.verticalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: -15)
        addChild(nameLabel)
        applyState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyState() {
        let colors = Theme.colors
        var lit = colors.activeStation
        if !colors.banners.isEmpty {
            let index = Stage.allCases.firstIndex(of: stage) ?? 0
            lit = colors.banners[index % colors.banners.count]
        }
        tile.fillColor = isActive ? lit : colors.station
        tile.strokeColor = isActive ? colors.activeStationStroke : colors.stationStroke
        icon.alpha = isActive ? 1 : 0.4
        nameLabel.attributedText = .label(stage.title, size: 10, weight: .medium,
                                          color: (colors.stationInk ?? colors.ink).withAlphaComponent(isActive ? 0.95 : 0.45))
    }
}

// MARK: The North Pole

extension FloorScene {
    private enum Yuletide {
        static let snow = NSColor(srgbRed: 0.93, green: 0.96, blue: 1, alpha: 1)
        static let snowShade = NSColor(srgbRed: 0.70, green: 0.80, blue: 0.94, alpha: 1)
        static let fir = NSColor(srgbRed: 0.07, green: 0.32, blue: 0.19, alpha: 1)
        static let firShade = NSColor(srgbRed: 0.03, green: 0.19, blue: 0.11, alpha: 1)
        static let bark = NSColor(srgbRed: 0.32, green: 0.19, blue: 0.10, alpha: 1)
        static let gold = NSColor(srgbRed: 1, green: 0.84, blue: 0.34, alpha: 1)
        static let red = NSColor(srgbRed: 0.80, green: 0.14, blue: 0.16, alpha: 1)
        static let green = NSColor(srgbRed: 0.13, green: 0.55, blue: 0.27, alpha: 1)
        /// Fairy-light colours, taken in turn along a string.
        static let bulbs: [NSColor] = [
            NSColor(srgbRed: 1, green: 0.32, blue: 0.30, alpha: 1),
            NSColor(srgbRed: 1, green: 0.84, blue: 0.32, alpha: 1),
            NSColor(srgbRed: 0.38, green: 0.88, blue: 0.48, alpha: 1),
            NSColor(srgbRed: 0.42, green: 0.72, blue: 1, alpha: 1),
        ]
    }

    private func shape(_ path: CGPath, fill: NSColor, stroke: NSColor = .clear, width: CGFloat = 1) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = width
        return node
    }

    /// A five-pointed star of `radius`, point up, centred on the origin.
    private func starPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<10 {
            let reach = index.isMultiple(of: 2) ? radius : radius * 0.45
            let angle = Double.pi / 2 + Double(index) * Double.pi / 5
            let point = CGPoint(x: CGFloat(cos(angle)) * reach, y: CGFloat(sin(angle)) * reach)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// One fairy light, twinkling at its own pace.
    private func bulb(_ color: NSColor, radius: CGFloat, random: inout StableRandom) -> SKShapeNode {
        let light = SKShapeNode(circleOfRadius: radius)
        light.fillColor = color
        light.strokeColor = .clear
        let halo = SKShapeNode(circleOfRadius: radius * 2.6)
        halo.fillColor = color.withAlphaComponent(0.18)
        halo.strokeColor = .clear
        light.addChild(halo)
        let pace = 0.5 + Double(random.unit()) * 0.9
        light.run(.sequence([
            .wait(forDuration: Double(random.unit()) * 1.2),
            .repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: pace), .fadeAlpha(to: 1, duration: pace)])),
        ]))
        return light
    }

    /// A fir tree `height` tall standing on its origin: three tiers of boughs with snow along
    /// their edges and on the tip. A decorated one has fairy lights, baubles and a gold star.
    private func firTree(height: CGFloat, decorated: Bool, random: inout StableRandom) -> SKNode {
        let tree = SKNode()
        let width = height * 0.62
        let trunk = SKShapeNode(rect: CGRect(x: -width * 0.07, y: 0, width: width * 0.14, height: height * 0.16))
        trunk.fillColor = Yuletide.bark
        trunk.strokeColor = .clear
        tree.addChild(trunk)
        var tiers: [(bottom: CGFloat, top: CGFloat, half: CGFloat)] = []
        for tier in 0..<3 {
            let step = CGFloat(tier)
            let bottom = height * (0.12 + step * 0.24)
            let top = min(height, bottom + height * 0.42)
            let half = width / 2 * (1 - step * 0.24)
            tiers.append((bottom, top, half))
            let boughs = CGMutablePath()
            boughs.addLines(between: [CGPoint(x: -half, y: bottom), CGPoint(x: half, y: bottom), CGPoint(x: 0, y: top)])
            boughs.closeSubpath()
            tree.addChild(shape(boughs, fill: Yuletide.fir, stroke: Yuletide.firShade))
            // Snow lying along the lower edge of the boughs.
            let ledge = CGMutablePath()
            ledge.addRoundedRect(in: CGRect(x: -half * 0.86, y: bottom - 0.5, width: half * 1.72, height: max(1.5, height * 0.03)),
                                 cornerWidth: 1, cornerHeight: 1)
            tree.addChild(shape(ledge, fill: Yuletide.snow.withAlphaComponent(0.9)))
        }
        let cap = CGMutablePath()
        cap.addLines(between: [CGPoint(x: 0, y: height), CGPoint(x: -width * 0.09, y: height * 0.86),
                               CGPoint(x: width * 0.09, y: height * 0.86)])
        cap.closeSubpath()
        tree.addChild(shape(cap, fill: Yuletide.snow))
        guard decorated else { return tree }

        // Baubles hanging on the boughs, and fairy lights twinkling among them.
        let baubles = [Yuletide.red, Yuletide.gold, NSColor(srgbRed: 0.35, green: 0.55, blue: 0.95, alpha: 1)]
        for (index, tier) in tiers.enumerated() {
            let count = max(2, Int(tier.half / 5))
            for item in 0..<count {
                let rise = 0.12 + random.unit() * 0.55
                let y = tier.bottom + (tier.top - tier.bottom) * rise
                let reach = tier.half * (1 - rise) * 0.8
                let x = (random.unit() * 2 - 1) * reach
                if item.isMultiple(of: 3) {
                    let bauble = SKShapeNode(circleOfRadius: max(1.6, height * 0.022))
                    bauble.fillColor = baubles[(index + item) % baubles.count]
                    bauble.strokeColor = .clear
                    bauble.position = CGPoint(x: x, y: y)
                    tree.addChild(bauble)
                } else {
                    let light = bulb(Yuletide.bulbs[(index + item) % Yuletide.bulbs.count],
                                     radius: max(1, height * 0.012), random: &random)
                    light.position = CGPoint(x: x, y: y)
                    tree.addChild(light)
                }
            }
        }
        // A gold star on the top, glowing softly.
        let glow = SKShapeNode(circleOfRadius: height * 0.09)
        glow.fillColor = Yuletide.gold.withAlphaComponent(0.22)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: 0, y: height + 2)
        tree.addChild(glow)
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 1.2), .fadeAlpha(to: 1, duration: 1.2)])))
        let star = shape(starPath(radius: max(4, height * 0.06)), fill: Yuletide.gold)
        star.position = CGPoint(x: 0, y: height + 2)
        tree.addChild(star)
        return tree
    }

    /// Snow falling at different speeds, drifting a little sideways. One flake for every
    /// `areaPerFlake` square points of `frame`.
    func addSnowfall(in frame: CGRect, areaPerFlake: CGFloat, random: inout StableRandom) {
        for _ in 0..<Int(frame.width * frame.height / areaPerFlake) {
            let flake = SKShapeNode(circleOfRadius: 0.8 + random.unit() * 1.6)
            flake.fillColor = NSColor(white: 1, alpha: 0.35 + random.unit() * 0.45)
            flake.strokeColor = .clear
            ambience.addChild(flake)
            let x = frame.minX + random.unit() * frame.width
            let y = frame.minY + random.unit() * frame.height
            flake.position = CGPoint(x: x, y: y)
            let speed = 14 + random.unit() * 22
            let first = Double((y - frame.minY) / speed)
            let full = Double(frame.height / speed)
            let sway = SKAction.sequence([.moveBy(x: 7, y: 0, duration: 1.6), .moveBy(x: -7, y: 0, duration: 1.6)])
            sway.timingMode = .easeInEaseOut
            flake.run(.repeatForever(sway))
            flake.run(.sequence([
                .moveTo(y: frame.minY, duration: first),
                .repeatForever(.sequence([.moveTo(y: frame.maxY, duration: 0), .moveTo(y: frame.minY, duration: full)])),
            ]))
        }
    }

    /// The North Pole at night: the northern lights rippling over a starry sky, snowy drifts
    /// along the lounge's roof line dotted with fir trees, a big decorated tree at either end,
    /// fairy lights strung between the stations, snow falling over everything, and Santa
    /// Claude's sleigh flying across now and then.
    func fillNorthPole(in frame: CGRect, random: inout StableRandom) {
        let ground = Metrics.loungeTop + 2
        let stationTop = size.height - Metrics.stationY + 28

        // Stars over the whole sky, twinkling.
        if frame.maxY > ground {
            for _ in 0..<Int(frame.width * (frame.maxY - ground) / 3200) {
                let star = SKShapeNode(circleOfRadius: 0.5 + random.unit() * 1.0)
                star.fillColor = .white
                star.strokeColor = .clear
                star.position = CGPoint(x: frame.minX + random.unit() * frame.width,
                                        y: ground + random.unit() * (frame.maxY - ground))
                star.alpha = 0.2 + random.unit() * 0.6
                let pace = 1.2 + Double(random.unit()) * 2.4
                star.run(.repeatForever(.sequence([.fadeAlpha(to: 0.08, duration: pace),
                                                   .fadeAlpha(to: star.alpha, duration: pace)])))
                star.name = Self.fixedDecor
                ambience.addChild(star)
            }
        }

        // The northern lights: three ribbons of green, teal and violet rippling across the top
        // of the sky, each brightening and fading, and swaying slowly.
        let auroras: [NSColor] = [
            NSColor(srgbRed: 0.30, green: 1, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.30, green: 0.86, blue: 1, alpha: 1),
            NSColor(srgbRed: 0.72, green: 0.48, blue: 1, alpha: 1),
        ]
        for (index, color) in auroras.enumerated() {
            let baseY = frame.maxY - 64 - CGFloat(index) * 34
            let phase = Double(random.unit()) * Double.pi * 2
            let waves = 1.2 + Double(random.unit())
            let steps = 32
            var crest: [CGPoint] = []
            for step in 0...steps {
                let share = CGFloat(step) / CGFloat(steps)
                let x = frame.minX - 40 + (frame.width + 80) * share
                let rise = CGFloat(sin(Double(share) * Double.pi * 2 * waves + phase)) * 16
                crest.append(CGPoint(x: x, y: baseY + rise))
            }
            let ribbon = SKNode()
            // A faint curtain hanging below a brighter crest.
            for (depth, alpha) in [(CGFloat(34), CGFloat(0.05)), (CGFloat(20), CGFloat(0.07)), (CGFloat(9), CGFloat(0.10))] {
                let curtain = CGMutablePath()
                curtain.addLines(between: crest + crest.reversed().map { CGPoint(x: $0.x, y: $0.y - depth) })
                curtain.closeSubpath()
                ribbon.addChild(shape(curtain, fill: color.withAlphaComponent(alpha)))
            }
            let line = CGMutablePath()
            line.addLines(between: crest)
            let glow = shape(line, fill: .clear, stroke: color.withAlphaComponent(0.35), width: 2)
            ribbon.addChild(glow)
            ambience.addChild(ribbon)
            let pace = 2.5 + Double(random.unit()) * 2
            ribbon.alpha = 0.8
            ribbon.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: pace), .fadeAlpha(to: 1, duration: pace)])))
            let sway = SKAction.sequence([.moveBy(x: 26, y: 0, duration: 5 + Double(index)),
                                          .moveBy(x: -26, y: 0, duration: 5 + Double(index))])
            sway.timingMode = .easeInEaseOut
            ribbon.run(.repeatForever(sway))
        }

        // Snowy drifts along the lounge's roof line, rolling in low humps.
        let drifts = CGMutablePath()
        drifts.move(to: CGPoint(x: frame.minX, y: ground - 4))
        var x = frame.minX
        drifts.addLine(to: CGPoint(x: x, y: ground + 6))
        while x < frame.maxX {
            let span = 90 + random.unit() * 110
            let next = min(frame.maxX, x + span)
            drifts.addQuadCurve(to: CGPoint(x: next, y: ground + 4 + random.unit() * 6),
                                control: CGPoint(x: (x + next) / 2, y: ground + 16 + random.unit() * 22))
            x = next
        }
        drifts.addLine(to: CGPoint(x: frame.maxX, y: ground - 4))
        drifts.closeSubpath()
        ambience.addChild(shape(drifts, fill: Yuletide.snow.withAlphaComponent(0.92), stroke: Yuletide.snowShade, width: 1.5))

        // A big decorated tree at either end, and smaller firs scattered along the drifts
        // between them.
        let bigLeft = frame.minX + 54
        let bigRight = frame.maxX - 54
        for (at, height) in [(bigLeft, CGFloat(150)), (bigRight, CGFloat(124))] {
            let tree = firTree(height: height, decorated: true, random: &random)
            tree.position = CGPoint(x: at, y: ground + 6)
            ambience.addChild(tree)
        }
        let firs = max(3, Int(frame.width / 110))
        for index in 0..<firs {
            let share = (CGFloat(index) + 0.5 + (random.unit() - 0.5) * 0.6) / CGFloat(firs)
            let at = frame.minX + 120 + (frame.width - 240) * share
            let tree = firTree(height: 28 + random.unit() * 34, decorated: false, random: &random)
            tree.position = CGPoint(x: at, y: ground + 8 + random.unit() * 6)
            tree.alpha = 0.85
            ambience.addChild(tree)
        }

        // Fairy lights strung between the tops of the station tiles, sagging in the middle.
        let stages = Stage.allCases
        for index in 0..<(stages.count - 1) {
            let from = CGPoint(x: stationX(stages[index]) + 40, y: stationTop - 5)
            let to = CGPoint(x: stationX(stages[index + 1]) - 40, y: stationTop - 5)
            guard to.x - from.x > 24 else { continue }
            let sag = CGPoint(x: (from.x + to.x) / 2, y: stationTop - 5 - min(34, (to.x - from.x) * 0.4))
            let wire = CGMutablePath()
            wire.move(to: from)
            wire.addQuadCurve(to: to, control: sag)
            ambience.addChild(shape(wire, fill: .clear, stroke: Yuletide.firShade.blended(withFraction: 0.3, of: .white) ?? Yuletide.firShade,
                                    width: 1.2))
            let count = max(3, Int((to.x - from.x) / 11))
            for bead in 1..<count {
                let t = CGFloat(bead) / CGFloat(count)
                let point = CGPoint(x: (1 - t) * (1 - t) * from.x + 2 * (1 - t) * t * sag.x + t * t * to.x,
                                    y: (1 - t) * (1 - t) * from.y + 2 * (1 - t) * t * sag.y + t * t * to.y)
                let light = bulb(Yuletide.bulbs[(bead + index) % Yuletide.bulbs.count], radius: 2.2, random: &random)
                light.position = CGPoint(x: point.x, y: point.y - 2.5)
                ambience.addChild(light)
            }
        }

        addSnowfall(in: frame, areaPerFlake: 5200, random: &random)
        addSleigh(in: frame, flightY: min(frame.maxY - 125, ground + 214))
    }

    /// Santa Claude's sleigh, piled with presents and pulled by four reindeer, flying across
    /// the sky every so often and leaving a trail of sparkles.
    private func addSleigh(in frame: CGRect, flightY: CGFloat) {
        let team = SKNode()
        let fur = NSColor(srgbRed: 0.52, green: 0.33, blue: 0.18, alpha: 1)
        let antler = NSColor(srgbRed: 0.86, green: 0.76, blue: 0.58, alpha: 1)

        // The sleigh: a red body with gold trim on a curling gold runner.
        let runner = CGMutablePath()
        runner.move(to: CGPoint(x: -20, y: -1))
        runner.addLine(to: CGPoint(x: 10, y: -1))
        runner.addQuadCurve(to: CGPoint(x: 14, y: 8), control: CGPoint(x: 18, y: -2))
        team.addChild(shape(runner, fill: .clear, stroke: Yuletide.gold, width: 1.6))
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -18, y: 2))
        body.addLine(to: CGPoint(x: 8, y: 2))
        body.addQuadCurve(to: CGPoint(x: 11, y: 11), control: CGPoint(x: 13, y: 4))
        body.addLine(to: CGPoint(x: 2, y: 9))
        body.addLine(to: CGPoint(x: -14, y: 9))
        body.addQuadCurve(to: CGPoint(x: -18, y: 2), control: CGPoint(x: -20, y: 9))
        body.closeSubpath()
        team.addChild(shape(body, fill: Yuletide.red, stroke: Yuletide.gold, width: 1))
        // The sack of presents behind, and Santa Claude in his red coat and hat.
        let sack = SKShapeNode(ellipseOf: CGSize(width: 10, height: 11))
        sack.fillColor = NSColor(srgbRed: 0.55, green: 0.38, blue: 0.22, alpha: 1)
        sack.strokeColor = .clear
        sack.position = CGPoint(x: -12, y: 13)
        team.addChild(sack)
        let coat = SKShapeNode(ellipseOf: CGSize(width: 9, height: 10))
        coat.fillColor = Yuletide.red
        coat.strokeColor = .clear
        coat.position = CGPoint(x: -2, y: 13)
        team.addChild(coat)
        let face = SKShapeNode(circleOfRadius: 2.8)
        face.fillColor = NSColor(srgbRed: 1, green: 0.84, blue: 0.72, alpha: 1)
        face.strokeColor = .clear
        face.position = CGPoint(x: -1, y: 20)
        team.addChild(face)
        let beard = SKShapeNode(ellipseOf: CGSize(width: 5, height: 4))
        beard.fillColor = Yuletide.snow
        beard.strokeColor = .clear
        beard.position = CGPoint(x: 0, y: 17.5)
        team.addChild(beard)
        let hat = CGMutablePath()
        hat.addLines(between: [CGPoint(x: -4, y: 21.5), CGPoint(x: 2, y: 21.5), CGPoint(x: -5, y: 27)])
        hat.closeSubpath()
        team.addChild(shape(hat, fill: Yuletide.red))
        let bobble = SKShapeNode(circleOfRadius: 1.2)
        bobble.fillColor = Yuletide.snow
        bobble.strokeColor = .clear
        bobble.position = CGPoint(x: -5, y: 27)
        team.addChild(bobble)

        // The reindeer, in a line ahead, each on the harness with its legs galloping.
        let reins = CGMutablePath()
        reins.move(to: CGPoint(x: 11, y: 10))
        reins.addLine(to: CGPoint(x: 92, y: 12))
        team.addChild(shape(reins, fill: .clear, stroke: Yuletide.gold.withAlphaComponent(0.8), width: 0.8))
        for index in 0..<4 {
            let deer = SKNode()
            deer.position = CGPoint(x: 28 + CGFloat(index) * 19, y: 6)
            for (leg, front) in [(-4, false), (-2, false), (3, true), (5, true)] {
                let limb = SKShapeNode(rect: CGRect(x: -0.7, y: -6, width: 1.4, height: 6))
                limb.fillColor = fur.blended(withFraction: 0.3, of: .black) ?? fur
                limb.strokeColor = .clear
                limb.position = CGPoint(x: CGFloat(leg), y: 1)
                let reach: CGFloat = front ? 0.6 : -0.6
                limb.run(.repeatForever(.sequence([.rotate(toAngle: reach, duration: 0.18),
                                                   .rotate(toAngle: -reach, duration: 0.18)])))
                deer.addChild(limb)
            }
            let torso = SKShapeNode(ellipseOf: CGSize(width: 13, height: 6))
            torso.fillColor = fur
            torso.strokeColor = .clear
            torso.position = CGPoint(x: 0, y: 2)
            deer.addChild(torso)
            let neck = SKShapeNode(rect: CGRect(x: 4, y: 2, width: 2.4, height: 6), cornerRadius: 1)
            neck.fillColor = fur
            neck.strokeColor = .clear
            neck.zRotation = -0.4
            deer.addChild(neck)
            let head = SKShapeNode(ellipseOf: CGSize(width: 5, height: 3.6))
            head.fillColor = fur
            head.strokeColor = .clear
            head.position = CGPoint(x: 8.5, y: 8)
            deer.addChild(head)
            let antlers = CGMutablePath()
            antlers.move(to: CGPoint(x: 7.5, y: 9.5))
            antlers.addLine(to: CGPoint(x: 6, y: 14))
            antlers.move(to: CGPoint(x: 6.6, y: 12))
            antlers.addLine(to: CGPoint(x: 4.5, y: 13))
            antlers.move(to: CGPoint(x: 9, y: 9.5))
            antlers.addLine(to: CGPoint(x: 9.5, y: 14))
            deer.addChild(shape(antlers, fill: .clear, stroke: antler, width: 1))
            // Each bobs a little out of step with the one in front.
            let bob = SKAction.sequence([.moveBy(x: 0, y: 1.5, duration: 0.36), .moveBy(x: 0, y: -1.5, duration: 0.36)])
            deer.run(.sequence([.wait(forDuration: Double(index) * 0.09), .repeatForever(bob)]))
            team.addChild(deer)
        }

        team.alpha = 0
        team.position = CGPoint(x: frame.minX - 120, y: flightY)
        ambience.addChild(team)
        // About ten seconds to cross, taking off ten seconds after the floor is drawn and then
        // every twenty or so, so it is over the middle of the floor at around sixteen seconds.
        let crossing = Double(frame.width + 240) / 120
        team.run(.sequence([
            .wait(forDuration: 10),
            .repeatForever(.sequence([
                .move(to: CGPoint(x: frame.minX - 120, y: flightY), duration: 0),
                .fadeIn(withDuration: 0.3),
                .group([
                    .moveBy(x: frame.width + 240, y: 26, duration: crossing),
                    .sequence([.moveBy(x: 0, y: 8, duration: crossing / 4), .moveBy(x: 0, y: -8, duration: crossing / 4),
                               .moveBy(x: 0, y: 8, duration: crossing / 4), .moveBy(x: 0, y: -8, duration: crossing / 4)]),
                ]),
                .fadeOut(withDuration: 0.3),
                .wait(forDuration: 10),
            ])),
        ]))

        // Sparkles shed behind the sleigh, fading as they fall.
        let sparkle = SKAction.run { [weak self, weak team] in
            guard let self, let team, team.alpha > 0.5 else { return }
            let spark = SKShapeNode(circleOfRadius: 1 + CGFloat.random(in: 0...0.8))
            spark.fillColor = Yuletide.bulbs[Int.random(in: 0..<Yuletide.bulbs.count)].blended(withFraction: 0.5, of: .white) ?? .white
            spark.strokeColor = .clear
            spark.position = CGPoint(x: team.position.x - 22, y: team.position.y + CGFloat.random(in: -2...6))
            self.ambience.addChild(spark)
            spark.run(.sequence([
                .group([.moveBy(x: CGFloat.random(in: -6...6), y: -18, duration: 1.2), .fadeOut(withDuration: 1.2)]),
                .removeFromParent(),
            ]))
        }
        team.run(.repeatForever(.sequence([sparkle, .wait(forDuration: 0.08)])))
    }

    /// The lounge at Christmas: a brick fireplace with a crackling fire and stockings hung from
    /// the mantel in the gap left of the middle couch, and a decorated tree with presents piled
    /// under it in the gap to the right. Behind the furniture and the agents.
    func buildChristmasLounge() {
        let decor = SKNode()
        decor.zPosition = -0.5
        furniture.addChild(decor)
        var random = StableRandom(seed: "christmas-\(size)")
        let floor = Metrics.loungeSeatY - AgentNode.feet
        let left = loungeCouches[0].x + 30
        let right = size.width / 2 - 72
        guard right - left > 86 else { return }
        let fireX = (left + right) / 2
        let treeX = size.width - fireX

        // The fireplace: brick, with a dark wooden mantel and an arched firebox.
        let brick = NSColor(srgbRed: 0.62, green: 0.26, blue: 0.20, alpha: 1)
        let mortar = NSColor(srgbRed: 0.42, green: 0.17, blue: 0.14, alpha: 1)
        let wood = NSColor(srgbRed: 0.36, green: 0.22, blue: 0.12, alpha: 1)
        let width: CGFloat = 84
        let height: CGFloat = 66
        let chimney = SKShapeNode(rect: CGRect(x: fireX - width / 2, y: floor, width: width, height: height))
        chimney.fillColor = brick
        chimney.strokeColor = mortar
        chimney.lineWidth = 1.5
        decor.addChild(chimney)
        let courses = CGMutablePath()
        var row = 0
        var y = floor + 8
        while y < floor + height - 2 {
            courses.move(to: CGPoint(x: fireX - width / 2, y: y))
            courses.addLine(to: CGPoint(x: fireX + width / 2, y: y))
            var joint = fireX - width / 2 + (row.isMultiple(of: 2) ? 7 : 14)
            while joint < fireX + width / 2 {
                courses.move(to: CGPoint(x: joint, y: y))
                courses.addLine(to: CGPoint(x: joint, y: y + 8))
                joint += 14
            }
            y += 8
            row += 1
        }
        decor.addChild(shape(courses, fill: .clear, stroke: mortar, width: 1))
        let opening = CGMutablePath()
        opening.move(to: CGPoint(x: fireX - 22, y: floor))
        opening.addLine(to: CGPoint(x: fireX - 22, y: floor + 24))
        opening.addArc(center: CGPoint(x: fireX, y: floor + 24), radius: 22, startAngle: .pi, endAngle: 0, clockwise: true)
        opening.addLine(to: CGPoint(x: fireX + 22, y: floor))
        opening.closeSubpath()
        decor.addChild(shape(opening, fill: NSColor(srgbRed: 0.08, green: 0.04, blue: 0.03, alpha: 1), stroke: mortar, width: 2))
        // The fire: a warm glow, two logs and flames licking up and flickering.
        let glow = SKShapeNode(ellipseOf: CGSize(width: 40, height: 30))
        glow.fillColor = NSColor(srgbRed: 1, green: 0.55, blue: 0.15, alpha: 0.25)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: fireX, y: floor + 12)
        decor.addChild(glow)
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.5), .fadeAlpha(to: 1, duration: 0.6)])))
        for (offset, tilt) in [(CGFloat(-5), CGFloat(0.25)), (CGFloat(5), CGFloat(-0.25))] {
            let log = SKShapeNode(rectOf: CGSize(width: 22, height: 5), cornerRadius: 2.5)
            log.fillColor = wood
            log.strokeColor = .clear
            log.position = CGPoint(x: fireX + offset, y: floor + 4)
            log.zRotation = tilt
            decor.addChild(log)
        }
        let flames: [(CGFloat, CGFloat, NSColor)] = [
            (-7, 15, NSColor(srgbRed: 1, green: 0.42, blue: 0.10, alpha: 1)),
            (6, 17, NSColor(srgbRed: 1, green: 0.42, blue: 0.10, alpha: 1)),
            (0, 22, NSColor(srgbRed: 1, green: 0.62, blue: 0.16, alpha: 1)),
            (0, 12, NSColor(srgbRed: 1, green: 0.88, blue: 0.40, alpha: 1)),
        ]
        for (offset, tall, color) in flames {
            let flame = CGMutablePath()
            flame.move(to: CGPoint(x: -5, y: 0))
            flame.addQuadCurve(to: CGPoint(x: 0, y: tall), control: CGPoint(x: -6, y: tall * 0.6))
            flame.addQuadCurve(to: CGPoint(x: 5, y: 0), control: CGPoint(x: 6, y: tall * 0.6))
            flame.closeSubpath()
            let node = shape(flame, fill: color)
            node.position = CGPoint(x: fireX + offset, y: floor + 5)
            decor.addChild(node)
            let pace = 0.12 + Double(random.unit()) * 0.12
            node.run(.repeatForever(.sequence([.scaleY(to: 0.75, duration: pace), .scaleY(to: 1.1, duration: pace),
                                               .scaleY(to: 0.9, duration: pace), .scaleY(to: 1, duration: pace)])))
        }
        let mantel = SKShapeNode(rect: CGRect(x: fireX - width / 2 - 7, y: floor + height, width: width + 14, height: 7),
                                 cornerRadius: 2)
        mantel.fillColor = wood
        mantel.strokeColor = .clear
        decor.addChild(mantel)
        // A garland of fir along the mantel, with a few lights in it.
        let garland = SKShapeNode(rect: CGRect(x: fireX - width / 2 - 4, y: floor + height + 6, width: width + 8, height: 4),
                                  cornerRadius: 2)
        garland.fillColor = Yuletide.fir
        garland.strokeColor = .clear
        decor.addChild(garland)
        for index in 0..<7 {
            let light = bulb(Yuletide.bulbs[index % Yuletide.bulbs.count], radius: 1.4, random: &random)
            light.position = CGPoint(x: fireX - width / 2 + CGFloat(index) * (width / 6), y: floor + height + 8)
            decor.addChild(light)
        }
        // Three stockings hanging from the mantel, red and green with white cuffs.
        for (index, offset) in [CGFloat(-26), 0, 26].enumerated() {
            let top = floor + height
            let sock = CGMutablePath()
            sock.addLines(between: [
                CGPoint(x: offset - 5, y: top), CGPoint(x: offset + 5, y: top), CGPoint(x: offset + 5, y: top - 14),
                CGPoint(x: offset + 9, y: top - 16), CGPoint(x: offset + 9, y: top - 21), CGPoint(x: offset - 2, y: top - 21),
                CGPoint(x: offset - 5, y: top - 17),
            ])
            sock.closeSubpath()
            let stocking = shape(sock, fill: index == 1 ? Yuletide.green : Yuletide.red)
            stocking.position.x = fireX
            decor.addChild(stocking)
            let cuff = SKShapeNode(rect: CGRect(x: fireX + offset - 6, y: top - 5, width: 12, height: 5), cornerRadius: 1.5)
            cuff.fillColor = Yuletide.snow
            cuff.strokeColor = .clear
            decor.addChild(cuff)
        }

        // The tree, with presents piled round its foot.
        let tree = firTree(height: 104, decorated: true, random: &random)
        tree.position = CGPoint(x: treeX, y: floor)
        decor.addChild(tree)
        let wrapping: [(CGFloat, CGFloat, CGFloat, NSColor, NSColor)] = [
            (-30, 16, 13, Yuletide.red, Yuletide.gold),
            (-14, 12, 9, NSColor(srgbRed: 0.30, green: 0.50, blue: 0.92, alpha: 1), Yuletide.snow),
            (18, 18, 11, Yuletide.green, Yuletide.red),
            (33, 11, 15, Yuletide.gold, Yuletide.red),
        ]
        for (offset, wide, tall, paper, ribbon) in wrapping {
            let box = SKShapeNode(rect: CGRect(x: treeX + offset - wide / 2, y: floor, width: wide, height: tall), cornerRadius: 1)
            box.fillColor = paper
            box.strokeColor = paper.blended(withFraction: 0.35, of: .black) ?? paper
            decor.addChild(box)
            let tie = CGMutablePath()
            tie.move(to: CGPoint(x: treeX + offset, y: floor))
            tie.addLine(to: CGPoint(x: treeX + offset, y: floor + tall))
            tie.move(to: CGPoint(x: treeX + offset - wide / 2, y: floor + tall / 2))
            tie.addLine(to: CGPoint(x: treeX + offset + wide / 2, y: floor + tall / 2))
            decor.addChild(shape(tie, fill: .clear, stroke: ribbon, width: 2))
            let bow = SKShapeNode(ellipseOf: CGSize(width: 7, height: 3.5))
            bow.fillColor = ribbon
            bow.strokeColor = .clear
            bow.position = CGPoint(x: treeX + offset, y: floor + tall + 1)
            decor.addChild(bow)
        }
    }
}
