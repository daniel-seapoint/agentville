import AgentvilleCore
import AppKit
import Observation
import SpriteKit
import SwiftUI

/// Owns the event sources, the store and the scene, and pumps one into the next on a timer.
@Observable
final class WorkshopController {
    struct Selection: Identifiable {
        let id: String
    }

    /// Which scene the scripted demo shows. Chosen with the picker in the title bar.
    enum DemoMode: String, CaseIterable, Identifiable {
        case working, idle, empty

        var id: Self { self }
        var label: String {
            switch self {
            case .working: return "Working"
            case .idle: return "Idle"
            case .empty: return "None"
            }
        }
    }

    let store = FloorStore()
    let scene = FloorScene()
    var selection: Selection?
    var selectionAnchor = CGRect.zero
    var showingAgentList = false
    /// Providers switched off in the legend. Applies to the floor and to the agent list.
    var hiddenProviders: Set<AgentSource> = [] {
        didSet { scene.hiddenSources = hiddenProviders }
    }
    var floatOnTop = false {
        didSet { applyWindowLevel() }
    }
    /// How the agents and furniture are drawn: smooth, pixel art, outlined or glowing.
    var artStyle = PixelArt.style {
        didSet {
            guard artStyle != oldValue else { return }
            PixelArt.style = artStyle
            scene.restyle()
        }
    }
    /// The floor's colours and ambience.
    var theme = Theme.current {
        didSet {
            guard theme != oldValue else { return }
            Theme.current = theme
            applyAppearance()
            scene.restyle()
        }
    }
    /// The demo scene on show, or nil when showing real sessions. The demo is there for people
    /// to play with; it never touches real sessions and switching back picks them up afresh.
    var demoMode: DemoMode? {
        didSet {
            guard demoMode != oldValue else { return }
            if let demoMode { lastDemoMode = demoMode }
            restartSources()
        }
    }
    /// Live or demo, as a switch. Turning the demo on returns to the scene last looked at.
    var isDemo: Bool {
        get { demoMode != nil }
        set { demoMode = newValue ? lastDemoMode : nil }
    }
    private var lastDemoMode = DemoMode.working

    @ObservationIgnored private var sources: [AgentEventSource] = []
    /// Builds the real sources from scratch. They remember which sessions they have already
    /// announced, so coming back from the demo needs new ones.
    @ObservationIgnored private var makeLiveSources: () -> [AgentEventSource] = {
        [ClaudeSource(), CodexSource(), CopilotSource()]
    }
    @ObservationIgnored private var timer: Timer?

    /// Flags: `--demo [working|idle|empty]` to open on the demo, `--replay <file> [--speed N]` to
    /// play back a recorded session in place of live ones, `--snapshot <png> [--after seconds]` to save the floor and
    /// quit (with `--list-snapshot <png>` and `--detail-snapshot <png>` to save the agent list and
    /// the first agent's popover as well).
    init(arguments: [String] = CommandLine.arguments) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        // `--icon <folder>` writes the app icon artwork there and quits.
        if let folder = value(after: "--icon") {
            AppIcon.write(to: URL(fileURLWithPath: folder))
            exit(0)
        }
        // `--wardrobe <png>` draws every hat, accessory, pattern, colour and art style and quits.
        if let path = value(after: "--wardrobe") {
            Wardrobe.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
        if let path = value(after: "--replay") {
            let speed = value(after: "--speed").flatMap(Double.init) ?? 1
            makeLiveSources = { [ReplaySource(url: URL(fileURLWithPath: path), speed: speed)] }
        }
        if arguments.contains("--demo") || arguments.contains("--demo-idle") {
            let mode = value(after: "--demo").flatMap(DemoMode.init)
                ?? (arguments.contains("--demo-idle") ? .idle : .working)
            demoMode = mode
            lastDemoMode = mode
        }
        // Setting the mode above already started the demo; otherwise start the live sources.
        if demoMode == nil { restartSources() }

        scene.onStartDemo = { [weak self] in self?.isDemo = true }
        scene.onShowAgentList = { [weak self] in self?.showingAgentList = true }
        scene.onToggleProvider = { [weak self] source in
            guard let self else { return }
            hiddenProviders.formSymmetricDifference([source])
        }
        scene.onSelect = { [weak self] id, point in
            self?.selectionAnchor = CGRect(x: point.x - 14, y: point.y - 18, width: 28, height: 36)
            self?.selection = Selection(id: id)
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.pump() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        pump()

        // `--hide codex,copilot` starts with those providers filtered out.
        if let names = value(after: "--hide") {
            hiddenProviders = Set(names.split(separator: ",").compactMap { AgentSource(rawValue: String($0)) })
            scene.hiddenSources = hiddenProviders // observers do not run during init
        }

        // `--record <folder> [--after s] [--seconds s]` saves the floor ten times a second as
        // numbered PNGs, for turning into a GIF, then quits.
        if let folder = value(after: "--record") {
            let delay = value(after: "--after").flatMap(Double.init) ?? 5
            let frames = Int((value(after: "--seconds").flatMap(Double.init) ?? 6) * 10)
            let url = URL(fileURLWithPath: folder)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                var frame = 0
                let recorder = Timer(timeInterval: 0.1, repeats: true) { timer in
                    self?.saveSnapshot(to: url.appendingPathComponent(String(format: "frame_%03d.png", frame)))
                    frame += 1
                    if frame >= frames {
                        timer.invalidate()
                        NSApp.terminate(nil)
                    }
                }
                RunLoop.main.add(recorder, forMode: .common)
            }
        }

        if let path = value(after: "--snapshot") {
            let delay = value(after: "--after").flatMap(Double.init) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.saveSnapshot(to: URL(fileURLWithPath: path))
                if let detailPath = value(after: "--detail-snapshot"), let first = self?.store.agents.first {
                    MainActor.assumeIsolated { self?.saveDetailSnapshot(of: first.id, to: URL(fileURLWithPath: detailPath)) }
                }
                if let listPath = value(after: "--list-snapshot") {
                    MainActor.assumeIsolated { self?.saveListSnapshot(to: URL(fileURLWithPath: listPath)) }
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// Clears the floor and starts over with the sources for the current mode.
    private func restartSources() {
        store.reset()
        switch demoMode {
        case nil: sources = makeLiveSources()
        case .working: sources = [DemoSource()]
        case .idle: sources = [DemoSource(idle: true)]
        case .empty: sources = []
        }
        selection = nil
        scene.isDemo = demoMode != nil
        pump()
    }

    private func pump() {
        let now = Date()
        for source in sources {
            store.ingest(source.poll(now: now), now: now)
        }
        store.tick(now: now)
        scene.sync(store.agents)
    }

    /// Light themes get light window chrome and popovers; the rest stay dark.
    func applyAppearance() {
        let appearance = NSAppearance(named: Theme.colors.isLight ? .aqua : .darkAqua)
        for window in NSApp.windows where window.canBecomeMain {
            window.appearance = appearance
        }
    }

    private func applyWindowLevel() {
        for window in NSApp.windows where window.canBecomeMain {
            window.level = floatOnTop ? .floating : .normal
        }
    }

    /// One agent's popover, for checking it without clicking.
    @MainActor private func saveDetailSnapshot(of agentID: String, to url: URL) {
        let renderer = ImageRenderer(content: AgentDetailPopover(store: store, agentID: agentID)
            .background(Color(white: Theme.colors.isLight ? 0.95 : 0.13))
            .environment(\.colorScheme, Theme.colors.isLight ? .light : .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The agent list as it appears in its popover, for checking it without clicking.
    @MainActor private func saveListSnapshot(to url: URL) {
        let renderer = ImageRenderer(content: AgentListPopover(store: store, hidden: hiddenProviders)
            .background(Color(white: Theme.colors.isLight ? 0.95 : 0.13))
            .environment(\.colorScheme, Theme.colors.isLight ? .light : .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    private func saveSnapshot(to url: URL) {
        guard let image = scene.view?.texture(from: scene)?.cgImage() else {
            FileHandle.standardError.write(Data("snapshot failed: the scene is not on screen\n".utf8))
            return
        }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? png?.write(to: url)
    }
}
