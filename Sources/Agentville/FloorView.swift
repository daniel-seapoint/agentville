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
                Section("Theme") {
                    Picker("Theme", selection: $controller.theme) {
                        ForEach(Theme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Agent style") {
                    Picker("Agent style", selection: $controller.artStyle) {
                        ForEach(PixelArt.Style.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme and agent style")
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
                                        look: Persona(agentID: agent.id).look, height: height)
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
