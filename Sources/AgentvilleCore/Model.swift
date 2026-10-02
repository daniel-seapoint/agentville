import Foundation

/// Which tool an agent belongs to.
public enum AgentSource: String, Equatable, Sendable {
    case claude
    case codex
    case copilot

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .copilot: return "Copilot"
        }
    }
}

/// The stations on the workshop floor, in display order.
public enum Stage: String, CaseIterable, Equatable, Sendable {
    case plan, research, build, verify, review, ship

    public var title: String {
        switch self {
        case .plan: return "Plan"
        case .research: return "Research"
        case .build: return "Build"
        case .verify: return "Verify"
        case .review: return "Review"
        case .ship: return "Ship"
        }
    }

    public var emoji: String {
        switch self {
        case .plan: return "🗺️"
        case .research: return "🔎"
        case .build: return "🔨"
        case .verify: return "🧪"
        case .review: return "✅"
        case .ship: return "🚀"
        }
    }
}

/// One normalised thing that happened to an agent, whatever tool produced it.
public struct AgentEvent: Equatable {
    public enum Kind: Equatable {
        case appeared(source: AgentSource, title: String, cwd: String, parent: String?)
        case titled(String)
        case turnStarted
        /// `stage == nil` means "keep the robot where it is, just update the status line".
        case activity(stage: Stage?, status: String, ship: Bool)
        case turnEnded
        case gone
    }

    public var agentID: String
    public var kind: Kind
    /// True for events recovered from history when a session is first discovered.
    /// They establish current state but must not trigger one-off effects.
    public var isBacklog: Bool

    public init(_ agentID: String, _ kind: Kind, isBacklog: Bool = false) {
        self.agentID = agentID
        self.kind = kind
        self.isBacklog = isBacklog
    }
}

/// What the UI renders for one agent.
public struct AgentSnapshot: Identifiable, Equatable {
    public let id: String
    public var source: AgentSource
    public var title: String
    public var cwd: String
    public var parentID: String?
    /// Station the robot stands at. `nil` while idle or before the first classified action.
    public var stage: Stage?
    public var status: String
    public var isWorking: Bool
    /// Most recent status lines, newest last.
    public var recent: [String]
    /// Incremented each time the agent ships something; the UI fires confetti on change.
    public var shipCount: Int
    public var colorIndex: Int
    public var lastActivity: Date

    var pendingStage: Stage?
    var pendingSince: Date?

    public var isSubagent: Bool { parentID != nil }
}

/// Anything that can report agent activity. `poll` is called on the main thread
/// roughly twice a second and returns whatever happened since the last call.
public protocol AgentEventSource: AnyObject {
    func poll(now: Date) -> [AgentEvent]
}

extension String {
    /// First non-empty line, whitespace collapsed, capped at `limit` characters.
    func titleLine(limit: Int = 80) -> String {
        let line = split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let collapsed = line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }
}
