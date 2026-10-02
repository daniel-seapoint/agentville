import AgentvilleCore
import SpriteKit

/// The workshop floor: a row of stations along the top with working robots beneath the station
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
    private var robots: [String: RobotNode] = [:]
    private var stations: [Stage: StationNode] = [:]

    private let panel = SKShapeNode()
    private let grid = SKShapeNode()
    private let titleLabel = SKLabelNode()
    private let countLabel = SKLabelNode()
    private let demoTag = SKShapeNode()
    /// Drawn behind the count so it reads as a button: it opens the list of agents.
    private let countButton = SKShapeNode()
    private var emptyState = EmptyStateNode()
    /// Where rebuilt robots should reappear; only set during `restyle`.
    private var respawn: [String: CGPoint] = [:]
    private let breakNote = BreakNoteNode()
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
        static let firstRowY: CGFloat = 198     // first robot row, from the top
        static let rowStep: CGFloat = 80
        static let loungeTop: CGFloat = 206     // top edge of the lounge, from the bottom
        static let loungeSeatY: CGFloat = 64    // where a resting robot sits, from the bottom
    }

    override init() {
        super.init(size: CGSize(width: 1000, height: 560))
        scaleMode = .resizeFill
        backgroundColor = NSColor(srgbRed: 0.04, green: 0.045, blue: 0.055, alpha: 1)

        panel.fillColor = NSColor(srgbRed: 0.063, green: 0.07, blue: 0.09, alpha: 1)
        panel.strokeColor = NSColor(white: 1, alpha: 0.08)
        panel.zPosition = -3
        grid.strokeColor = NSColor(white: 1, alpha: 0.035)
        grid.lineWidth = 1
        grid.zPosition = -2
        countButton.fillColor = NSColor(srgbRed: 0.16, green: 0.28, blue: 0.52, alpha: 1)
        countButton.strokeColor = NSColor(srgbRed: 0.30, green: 0.50, blue: 0.90, alpha: 1)
        countButton.lineWidth = 1
        lounge.fillColor = NSColor(white: 1, alpha: 0.03)
        lounge.strokeColor = NSColor(white: 1, alpha: 0.09)
        lounge.lineWidth = 1
        lounge.zPosition = -1
        loungeLabel.horizontalAlignmentMode = .left
        loungeLabel.verticalAlignmentMode = .top
        loungeLabel.attributedText = .label("LOUNGE", size: 9, weight: .semibold, color: NSColor(white: 1, alpha: 0.35))
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
        [panel, grid, lounge, loungeLabel, furniture, titleLabel, demoTag, countButton, countLabel, legend, emptyState, breakNote].forEach(addChild)
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
        titleLabel.attributedText = .label("Agentville", size: 14, weight: .semibold, color: .white)
        countLabel.horizontalAlignmentMode = .right

        for stage in Stage.allCases {
            let node = StationNode(stage: stage)
            stations[stage] = node
            addChild(node)
        }
        isSetUp = true
        layoutStatic()
        refreshHeader()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didChangeSize(_ oldSize: CGSize) {
        guard isSetUp else { return }
        layoutStatic()
        layoutRobots(animated: false)
    }

    // MARK: Updating

    func sync(_ everyone: [AgentSnapshot]) {
        allAgents = everyone
        let newAgents = everyone.filter { !hiddenSources.contains($0.source) }
        agents = newAgents
        let ids = Set(newAgents.map(\.id))
        for (id, robot) in robots where !ids.contains(id) {
            robot.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            robots[id] = nil
        }
        for agent in newAgents {
            if let robot = robots[agent.id] {
                robot.update(agent)
            } else {
                // Subagents pop out of their parent; everyone else walks in from the door.
                let origin = respawn[agent.id] ?? agent.parentID.flatMap { robots[$0]?.position }
                    ?? CGPoint(x: -20, y: Metrics.loungeSeatY)
                let robot = RobotNode(agent: agent, at: origin)
                robots[agent.id] = robot
                addChild(robot)
            }
        }
        layoutRobots(animated: true)
        refreshHeader()
    }

    /// Rebuilds everything drawn from the character maps after `PixelArt.style` changes.
    /// Robots come back where they were standing rather than walking in again.
    func restyle() {
        respawn = robots.mapValues(\.position)
        robots.values.forEach { $0.removeFromParent() }
        robots.removeAll()
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
                                           color: NSColor(white: 1, alpha: 0.92))
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

    /// Where a robot sits on each of the lounge's couches: one at either end and one in the
    /// middle, listed left to right.
    private var loungeCouches: [CGPoint] {
        [120, size.width / 2, size.width - 120].map { CGPoint(x: $0, y: Metrics.loungeSeatY) }
    }

    /// Puts the lounge's furniture in place: the couches, a lamp at the left end, a plant at
    /// the right, and a lamp and a plant either side of the middle couch. Only rebuilt when the floor changes size or style.
    private func furnishLounge() {
        let key = "\(size)-\(PixelArt.style)"
        guard key != furnishedFor else { return }
        furnishedFor = key
        furniture.removeAllChildren()

        /// Stands a piece on the floor line the lounge's robots stand on.
        func place(_ item: PixelArt.Furniture, x: CGFloat) {
            let node = SKSpriteNode(texture: PixelArt.furniture(item))
            node.size = CGSize(width: CGFloat(item.size.columns) * RobotNode.pixel,
                               height: CGFloat(item.size.rows) * RobotNode.pixel)
            node.position = CGPoint(x: x, y: Metrics.loungeSeatY - RobotNode.feet + node.size.height / 2)
            furniture.addChild(node)
        }
        for couch in loungeCouches { place(.couch, x: couch.x) }
        place(.lamp, x: 44)
        place(.plant, x: size.width - 44)
        // The middle couch has one of each beside it, just outside its sitter's things.
        place(.lamp, x: size.width / 2 - 62)
        place(.plant, x: size.width / 2 + 62)
    }

    private func layoutRobots(animated: Bool) {
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
            robots[agent.id]?.hasCouch = true
        }
        let sitters = resting.filter { robots[$0.id]?.persona.sleepsInBed == false }
        let bedSleepers = resting.filter { robots[$0.id]?.persona.sleepsInBed != false }
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
        onTheFloor.forEach { robots[$0.id]?.hasCouch = false }

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
            guard let robot = robots[id] else { continue }
            robot.move(to: point, heading: name, animated: animated)
            robot.zPosition = 100 - point.y / 10
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
        guard let robot = nodes(at: point).lazy.compactMap({ node -> RobotNode? in
            var current: SKNode? = node
            while let candidate = current {
                if let robot = candidate as? RobotNode { return robot }
                current = candidate.parent
            }
            return nil
        }).first, let view else { return }
        let inView = view.convert(robot.position, from: self)
        onSelect?(robot.agentID, CGPoint(x: inView.x, y: view.bounds.height - inView.y))
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

    private func applyState() {
        tile.fillColor = isActive
            ? NSColor(srgbRed: 0.12, green: 0.22, blue: 0.43, alpha: 1)
            : NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)
        tile.strokeColor = isActive
            ? NSColor(srgbRed: 0.25, green: 0.45, blue: 0.85, alpha: 1)
            : NSColor(white: 1, alpha: 0.07)
        icon.alpha = isActive ? 1 : 0.4
        nameLabel.attributedText = .label(stage.title, size: 10, weight: .medium,
                                     color: NSColor(white: 1, alpha: isActive ? 0.95 : 0.35))
    }
}
