import AgentvilleCore
import SpriteKit
import SwiftUI

struct FloorView: View {
    @Bindable var controller: WorkshopController

    var body: some View {
        SpriteView(scene: controller.scene, preferredFramesPerSecond: 60)
            .popover(item: $controller.selection,
                     attachmentAnchor: .rect(.rect(controller.selectionAnchor)),
                     arrowEdge: .top) { selection in
                AgentDetailPopover(store: controller.store, agentID: selection.id)
            }
            // The agent list hangs off the count in the top-right corner. It gets its own
            // anchor view because one view cannot host two popovers.
            .overlay(alignment: .topTrailing) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .padding(.top, 46)
                    .padding(.trailing, 84)
                    .allowsHitTesting(false)
                    .popover(isPresented: $controller.showingAgentList, arrowEdge: .bottom) {
                        AgentListPopover(store: controller.store, hidden: controller.hiddenProviders)
                    }
            }
            .ignoresSafeArea()
    }
}

/// Title bar controls: the demo's scene picker (while the demo is on), the Live / Demo switch,
/// the appearance menu (theme and art style), and the button that keeps the window above everything.
struct TitleBarControls: View {
    @Bindable var controller: WorkshopController
    @State private var showingIconPicker = false

    var body: some View {
        HStack(spacing: 10) {
            // The title bar gives this view a fixed width, so the scene picker keeps its place
            // and is only hidden while live. It sits first so the gap it leaves is at the edge.
            Picker("Demo scene", selection: Binding(get: { controller.demoMode ?? .working },
                                                    set: { controller.demoMode = $0 })) {
                ForEach(WorkshopController.DemoMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Choose what the demo shows")
            .opacity(controller.isDemo ? 1 : 0)
            .allowsHitTesting(controller.isDemo)

            Picker("Source", selection: $controller.isDemo) {
                Text("Live").tag(false)
                Text("Demo").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Live shows your real agents. Demo shows scripted ones to play with.")
            // One menu for both, so the title bar does not grow with every theme and style.
            Menu {
                Section("Theme") { themePicker(Theme.everyday, label: "Theme") }
                Section("Film & TV") {
                    // Lord of the Rings is one entry; picking it returns to the scene last used.
                    Picker("Film & TV", selection: Binding<Theme?>(
                        get: { controller.theme.isMiddleEarth ? .lordOfTheRings
                               : (Theme.filmAndTV.contains(controller.theme) ? controller.theme : nil) },
                        set: { picked in
                            guard let picked else { return }
                            if picked.isMiddleEarth {
                                if !controller.theme.isMiddleEarth { controller.theme = controller.lastMiddleEarth }
                            } else {
                                controller.theme = picked
                            }
                        })) {
                        ForEach(Theme.filmAndTV) { Text($0.menuLabel).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if controller.theme.isMiddleEarth {
                    Section("Lord of the Rings") {
                        Picker("Lord of the Rings", selection: $controller.theme) {
                            ForEach(Theme.middleEarthScenes) { Text($0.sceneLabel).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                // Only the styles this theme offers.
                Section("Agent style") {
                    Picker("Agent style", selection: $controller.artStyle) {
                        ForEach(controller.theme.styles) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                // On themes with named characters, star favourites: they are cast first, in the
                // order starred. The rest of the cast still appears after them.
                if let key = Cast.key(for: controller.theme) {
                    Section("Characters") {
                        Menu("Favourite characters") {
                            let _ = controller.charactersVersion
                            let favourites = Cast.favourites(key)
                            ForEach(Cast.main(key)) { member in
                                Toggle(member.name, isOn: Binding(
                                    get: { favourites.contains(member.id) },
                                    set: { controller.setFavourite(member.id, in: key, to: $0) }))
                            }
                            Divider()
                            Button("Clear Favourites") { controller.clearFavourites(in: key) }
                                .disabled(favourites.isEmpty)
                            Text("Favourites are shown first")
                        }
                    }
                }
            } label: {
                // Named, so it is clear this is where the look of the floor is changed. The title
                // bar's controls are sized once, when the window opens, so the name sits in a
                // space wide enough for the longest one; otherwise a long name would push the
                // demo picker out of view.
                Label {
                    ZStack(alignment: .leading) {
                        ForEach(Theme.allCases) { Text(title(for: $0)).hidden() }
                        Text(themeTitle)
                    }
                } icon: {
                    Image(systemName: "paintpalette.fill")
                }
                .labelStyle(.titleAndIcon)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Theme, agent style and favourite characters")
            // The app's own icon, picked from a previewer of every character.
            Button { showingIconPicker.toggle() } label: {
                Label("App Icon", systemImage: "app.badge")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .help("Dress the app icon as a character")
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                AppIconPicker(controller: controller)
            }
            Toggle(isOn: $controller.floatOnTop) {
                Image(systemName: controller.floatOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Keep Agentville above other windows")
        }
        .padding(.trailing, 10)
    }
}

extension TitleBarControls {
    /// The theme button's title: the theme, and for Lord of the Rings which scene.
    var themeTitle: String { title(for: controller.theme) }

    func title(for theme: Theme) -> String {
        theme.isMiddleEarth ? "\(theme.menuLabel) · \(theme.sceneLabel)" : theme.menuLabel
    }

    /// One section's worth of themes. Two of these share the theme setting, so each shows a
    /// tick only when the current theme is one of its own.
    private func themePicker(_ themes: [Theme], label: String) -> some View {
        Picker(label, selection: Binding<Theme?>(
            get: { themes.contains(controller.theme) ? controller.theme : nil },
            set: { if let theme = $0 { controller.theme = theme } })) {
            ForEach(themes) { Text($0.label).tag(Optional($0)) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

/// Picks the app icon: a large preview of the one being looked at, and every choice below it
/// as a thumbnail, grouped by film or show. Clicking a thumbnail previews it; the button makes
/// it the app's icon.
struct AppIconPicker: View {
    @Bindable var controller: WorkshopController
    /// Off when drawing the picker to an image, which leaves a scroll view's contents out.
    var scrolls = true
    @State private var previewing: String?

    private var shown: String { previewing ?? controller.appIcon }

    var body: some View {
        let choices = AppIcon.choices
        let current = choices.first { $0.id == shown } ?? choices[0]
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(nsImage: AppIcon.thumbnail(current.id))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.name)
                        .font(.title2.bold())
                    Text(current.theme?.menuLabel ?? "Agentville")
                        .foregroundStyle(.secondary)
                    Spacer().frame(height: 6)
                    if current.id == controller.appIcon {
                        Label("Current app icon", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Use as App Icon") { controller.appIcon = current.id }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Divider()
            let groups = VStack(alignment: .leading, spacing: 10) {
                group(nil, title: "Agentville", choices)
                ForEach(Theme.filmAndTV) { theme in group(theme, title: theme.menuLabel, choices) }
            }
            .padding(.bottom, 4)
            if scrolls { ScrollView { groups } } else { groups }
        }
        .padding(16)
        .frame(width: 460, height: scrolls ? 560 : nil)
    }

    private func group(_ theme: Theme?, title: String,
                       _ choices: [(id: String, name: String, theme: Theme?, look: PixelArt.Look)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(choices.filter { $0.theme == theme }, id: \.id) { choice in
                    Button { previewing = choice.id } label: {
                        Image(nsImage: AppIcon.thumbnail(choice.id))
                            .resizable()
                            .frame(width: 60, height: 60)
                            .padding(2)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .stroke(choice.id == shown ? Color.accentColor : .clear, lineWidth: 2.5))
                            .overlay(alignment: .bottomTrailing) {
                                if choice.id == controller.appIcon {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.white, .green)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(choice.name)
                }
            }
        }
    }
}

/// Every agent on the floor, opened from the count in the header. Subagents are listed under
/// the agent that spawned them. Reads the store directly so it stays live.
struct AgentListPopover: View {
    let store: FloorStore
    /// Providers filtered out with the legend; their agents are left off the list too.
    var hidden: Set<AgentSource> = []

    var body: some View {
        let agents = store.agents.filter { !hidden.contains($0.source) }
        let topLevel = agents.filter { !$0.isSubagent }
        VStack(alignment: .leading, spacing: 10) {
            Text(heading(topLevel))
                .font(.headline)
            if !hidden.isEmpty {
                Text("Hiding " + hidden.map(\.displayName).sorted().joined(separator: ", ")
                     + ". Click a provider in the legend to show it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(topLevel) { agent in
                row(agent)
                ForEach(agents.filter { $0.parentID == agent.id }) { child in
                    row(child).padding(.leading, 30)
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private func heading(_ topLevel: [AgentSnapshot]) -> String {
        if topLevel.isEmpty { return store.agents.isEmpty ? "No agents running" : "No agents shown" }
        return "\(topLevel.filter(\.isWorking).count) of \(topLevel.count) working"
    }

    /// The agent as it appears on the floor, then what it is doing, then whose it is.
    private func row(_ agent: AgentSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            AgentPortrait(agent: agent, height: agent.isSubagent ? 24 : 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.title)
                    .font(agent.isSubagent ? .callout : .body)
                    .lineLimit(1)
                Text(detail(agent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !agent.isSubagent {
                ProviderIcon(source: agent.source)
            }
        }
        .opacity(agent.isWorking ? 1 : 0.6)
    }

    private func detail(_ agent: AgentSnapshot) -> String {
        let who = agent.isSubagent ? "Subagent" : agent.source.displayName
        guard agent.isWorking else { return "\(who) · \(agent.status)" }
        return "\(who) · \(agent.stage?.title ?? "Thinking") · \(agent.status)"
    }
}

/// The agent's agent exactly as drawn on the floor: same colour, hat and accessory.
struct AgentPortrait: View {
    let agent: AgentSnapshot
    let height: CGFloat

    var body: some View {
        let image = PixelArt.agentImage(source: agent.source, colorIndex: agent.colorIndex,
                                        look: Persona(agentID: agent.id).look(for: Theme.current), height: height)
        Image(nsImage: image)
            // Pixel art must stay hard-edged when scaled up; the smooth style is already large.
            .interpolation(PixelArt.style == .pixel ? .none : .high)
            .resizable()
            .frame(width: image.size.width, height: image.size.height)
    }
}

/// A provider's logo on its colour, matching the tile beside each agent.
struct ProviderIcon: View {
    let source: AgentSource
    var side: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.23)
            .fill(Color(nsColor: PixelArt.providerColor(source)))
            .frame(width: side, height: side)
            .overlay {
                if let image = ProviderLogo.image(for: source, side: side * 0.64) {
                    Image(nsImage: image)
                }
            }
    }
}

/// Shown when a agent is clicked: the agent as drawn on the floor, and the last few things it
/// did. Reads the store directly so it stays live.
struct AgentDetailPopover: View {
    let store: FloorStore
    let agentID: String

    var body: some View {
        if let agent = store.agent(agentID) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    AgentPortrait(agent: agent, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.title)
                            .font(.headline)
                            .lineLimit(3)
                        HStack(spacing: 6) {
                            if !agent.isSubagent { ProviderIcon(source: agent.source, side: 16) }
                            Text("\(agent.source.displayName)\(agent.isSubagent ? " subagent" : "") · \(agent.isWorking ? (agent.stage?.title ?? "Thinking") : "Idle")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        // The character this agent is playing, on themes with named characters.
                        if !agent.isSubagent, let member = Casting.shared.member(for: agent.id, theme: Theme.current) {
                            Text("as \(member.name)")
                                .font(.subheadline.italic())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Text("Recent tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if agent.recent.isEmpty {
                    Text("Nothing yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                // Newest first; the one on top is what it is doing now, or did last.
                ForEach(Array(agent.recent.suffix(6).reversed().enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(width: 290, alignment: .leading)
        } else {
            Text("This agent has left the floor.")
                .foregroundStyle(.secondary)
                .padding(14)
        }
    }
}
