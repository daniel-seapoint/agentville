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
        emptyState.setVisible(allAgents.isEmpty)
        breakNote.setVisible(!topLevel.isEmpty && working == 0)
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
            // Snow falling at different speeds, drifting a little sideways.
            for _ in 0..<Int(area / 4500) {
                let flake = dot(0.8 + random.unit() * 1.6, NSColor(white: 1, alpha: 0.35 + random.unit() * 0.45))
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
        case .candles:
            // Candles hanging in the air above the floor, each bobbing gently, flames flickering.
            for _ in 0..<Int(frame.width / 55) {
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
                let x: CGFloat = frame.minX + 20 + random.unit() * (frame.width - 40)
                let y: CGFloat = frame.minY + frame.height * (0.42 + random.unit() * 0.5)
                candle.position = CGPoint(x: x, y: y)
                let scale: CGFloat = 0.7 + random.unit() * 0.5
                candle.setScale(scale)
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
