import AgentvilleCore
import AppKit
import Metal
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
            if !switchingTheme { scene.restyle() }
        }
    }
    /// The floor's colours and ambience.
    var theme = Theme.current {
        didSet {
            guard theme != oldValue else { return }
            Theme.current = theme
            if theme.isMiddleEarth { lastMiddleEarth = theme }
            // Picking a film or TV theme switches to its own agent style. Leaving one for an
            // everyday theme puts back the style that was in use before it.
            switchingTheme = true
            if let style = theme.agentStyle {
                if !oldValue.isTribute { styleBeforeTheme = artStyle }
                artStyle = style
            } else if oldValue.isTribute {
                artStyle = styleBeforeTheme ?? .smooth
                styleBeforeTheme = nil
            }
            switchingTheme = false
            // Outlines are drawn in the theme's ink.
            PixelArt.clearCaches()
            applyAppearance()
            scene.restyle()
        }
    }
    /// The Lord of the Rings scene picked last, so choosing Lord of the Rings again goes back to it.
    var lastMiddleEarth: Theme = Theme.current.isMiddleEarth ? Theme.current : .lordOfTheRings
    /// The character the app icon is dressed as: an id from `AppIcon.choices`. Saved.
    var appIcon = UserDefaults.standard.string(forKey: "appIcon") ?? "default" {
        didSet {
            guard appIcon != oldValue else { return }
            UserDefaults.standard.set(appIcon, forKey: "appIcon")
            applyAppIcon()
        }
    }

    /// Shows the chosen icon in the Dock, and gives the app's bundle the same icon so Finder and
    /// the Dock show it when the app is not running too. The default puts the bundle's own back.
    func applyAppIcon() {
        let bundle = Bundle.main.bundleURL
        let isApp = bundle.pathExtension == "app"
        if appIcon == "default" && isApp {
            NSApp.applicationIconImage = nil
            NSWorkspace.shared.setIcon(nil, forFile: bundle.path, options: [])
            return
        }
        guard let icon = AppIcon.render(choice: appIcon) else { return }
        let image = NSImage(cgImage: icon, size: NSSize(width: 512, height: 512))
        NSApp.applicationIconImage = image
        if isApp { NSWorkspace.shared.setIcon(image, forFile: bundle.path, options: []) }
    }

    /// Bumped when favourite characters change, so the menu shows the new ticks.
    var charactersVersion = 0

    /// Stars or unstars a favourite character and recasts the floor to match.
    func setFavourite(_ id: String, in key: String, to on: Bool) {
        Cast.setFavourite(id, in: key, to: on)
        charactersVersion += 1
        scene.restyle()
    }

    func clearFavourites(in key: String) {
        Cast.clearFavourites(in: key)
        charactersVersion += 1
        scene.restyle()
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
    /// Set while a theme change is also changing the style, so the floor is redrawn only once.
    @ObservationIgnored private var switchingTheme = false
    /// The style in use before a film or TV theme replaced it with its own. Saved, so it can be
    /// put back even after a relaunch.
    @ObservationIgnored private var styleBeforeTheme: PixelArt.Style? =
        UserDefaults.standard.string(forKey: "styleBeforeTheme").flatMap(PixelArt.Style.init) {
        didSet { UserDefaults.standard.set(styleBeforeTheme?.rawValue, forKey: "styleBeforeTheme") }
    }
    /// Pixels per point for `--snapshot`, set with `--snapshot-scale`. Above 1 the floor is drawn
    /// offscreen at that resolution, whatever the screen's own. `--record` always uses the
    /// screen, since the offscreen renderer stops the floor moving.
    @ObservationIgnored private var snapshotScale: CGFloat = 1
    @ObservationIgnored private var offscreen: OffscreenRenderer?

    /// Flags: `--demo [working|idle|empty]` to open on the demo, `--replay <file> [--speed N]` to
    /// play back a recorded session in place of live ones, `--snapshot <png> [--after seconds]` to save the floor and
    /// quit (with `--list-snapshot <png>` and `--detail-snapshot <png>` to save the agent list and
    /// the first agent's popover as well).
    init(arguments: [String] = CommandLine.arguments) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        // Each theme offers its own set of styles (`Theme.styles`).
        // Settings saved by an older version, or a `-theme`/`-artStyle` pair that does not
        // match, are put right here.
        if let saved = styleBeforeTheme, !saved.fits(.workshop) { styleBeforeTheme = nil }
        if !artStyle.fits(theme) {
            artStyle = theme.agentStyle ?? styleBeforeTheme ?? .smooth
        }

        // `--icon <folder>` writes the app icon artwork there and quits.
        if let folder = value(after: "--icon") {
            AppIcon.write(to: URL(fileURLWithPath: folder))
            exit(0)
        }
        // `--icon-gif <gif>` writes the README's animated icon and quits.
        if let path = value(after: "--icon-gif") {
            AppIcon.writeGIF(to: URL(fileURLWithPath: path))
            exit(0)
        }
        // `--casts <folder>` draws each film or TV theme's cast, named, and quits.
        if let folder = value(after: "--casts") {
            Wardrobe.writeCasts(to: URL(fileURLWithPath: folder))
            exit(0)
        }
        // `--wardrobe <png>` draws every hat, accessory, pattern, colour and art style and quits.
        if let path = value(after: "--wardrobe") {
            Wardrobe.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
        snapshotScale = value(after: "--snapshot-scale").flatMap(Double.init).map { CGFloat($0) } ?? 1
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
                    self?.saveSnapshot(to: url.appendingPathComponent(String(format: "frame_%03d.png", frame)),
                                       offscreen: false)
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
                if let pickerPath = value(after: "--icon-picker-snapshot") {
                    MainActor.assumeIsolated { self?.savePickerSnapshot(to: URL(fileURLWithPath: pickerPath)) }
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

    /// The app icon picker, for checking it without clicking.
    @MainActor private func savePickerSnapshot(to url: URL) {
        let renderer = ImageRenderer(content: AppIconPicker(controller: self, scrolls: false)
            .background(Color(white: 0.13))
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
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

    private func saveSnapshot(to url: URL, offscreen useOffscreen: Bool = true) {
        if useOffscreen, snapshotScale > 1 {
            if offscreen == nil { offscreen = OffscreenRenderer(scene: scene) }
            if let image = offscreen?.render(scale: snapshotScale) {
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                try? png?.write(to: url)
                return
            }
            FileHandle.standardError.write(Data("offscreen snapshot failed; using the window\n".utf8))
        }
        guard let image = scene.view?.texture(from: scene)?.cgImage() else {
            FileHandle.standardError.write(Data("snapshot failed: the scene is not on screen\n".utf8))
            return
        }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? png?.write(to: url)
    }
}

/// Draws the scene into a Metal texture of any size, for snapshots sharper than the screen.
/// Once it has the scene it also keeps it moving, since the scene is then no longer driven by
/// its view.
private final class OffscreenRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let renderer: SKRenderer

    init?(scene: SKScene) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        size = scene.size
        guard size.width > 0, size.height > 0 else { return nil }
        renderer = SKRenderer(device: device)
        renderer.scene = scene
        // From here on this renderer drives the scene, so the view must not advance it too.
        scene.view?.isPaused = true
        // Keep the floor laid out at the window's size and scale it up to fill the texture,
        // rather than letting it resize to the texture's pixels.
        scene.scaleMode = .fill
        scene.size = size
    }

    /// The scene's size in points, as it was in the window.
    private let size: CGSize

    func render(scale: CGFloat) -> CGImage? {
        guard let scene = renderer.scene else { return nil }
        if scene.size != size { scene.size = size }
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        renderer.update(atTime: CACurrentMediaTime())
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height),
                        commandBuffer: buffer, renderPassDescriptor: pass)
        buffer.commit()
        buffer.waitUntilCompleted()

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
