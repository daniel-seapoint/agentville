import AgentvilleCore
import SwiftUI

@main
struct AgentvilleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: appDelegate.controller, showWindow: appDelegate.showWindow)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: PixelArt.menuBarIcon())
                Text("\(appDelegate.controller.store.workingCount)")
            }
        }
    }
}

private struct MenuContent: View {
    let controller: WorkshopController
    let showWindow: () -> Void

    var body: some View {
        let agents = controller.store.agents.filter { !$0.isSubagent }
        if agents.isEmpty {
            Text("No agents running")
        }
        ForEach(agents) { agent in
            Text("\(agent.source.displayName) · \(agent.title.truncated(40)) — \(agent.status)")
        }
        Divider()
        Button("Show Agentville", action: showWindow)
        Button("Quit Agentville") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Owns the main window. It is created with AppKit rather than a SwiftUI `Window` scene
/// because SwiftUI does not open its window when the app runs as a bare executable.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = WorkshopController()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // The icon the user picked, or for a bare executable (`swift run`), which has no icon of
        // its own, the default one.
        controller.applyAppIcon()
        showWindow()
    }

    /// The menu bar item keeps counting after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showWindow() }
        return true
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Agentville"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: Theme.colors.isLight ? .aqua : .darkAqua)
            window.contentMinSize = NSSize(width: 780, height: 400)
            window.contentView = NSHostingView(rootView: FloorView(controller: controller))

            let pin = NSTitlebarAccessoryViewController()
            pin.layoutAttribute = .trailing
            pin.view = NSHostingView(rootView: TitleBarControls(controller: controller))
            pin.view.frame.size = pin.view.fittingSize
            window.addTitlebarAccessoryViewController(pin)

            window.setFrameAutosaveName("AgentvilleMain")
            if window.frame.origin == .zero { window.center() }
            self.window = window
        }
        window?.level = controller.floatOnTop ? .floating : .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
