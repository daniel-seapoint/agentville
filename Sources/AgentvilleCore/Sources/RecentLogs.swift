import Foundation

/// Rules shared by tools that leave one append-only log per session and no registry of what is
/// running (Codex, Copilot): a session is on the floor while its log is being written to.
enum RecentLogs {
    static let tailBytes: UInt64 = 64 * 1024
    static let scanInterval: TimeInterval = 5
    /// A log touched this recently is on the floor.
    static let idleWindow: TimeInterval = 10 * 60
    /// Mid-turn sessions get longer: a single command can run for a while without output.
    static let workingWindow: TimeInterval = 60 * 60
    /// With no turn marker in the recent history, this much quiet means the turn is over.
    static let assumeWorkingWithin: TimeInterval = 60

    /// How long a session may stay quiet before it leaves the floor.
    static func quietLimit(working: Bool) -> TimeInterval { working ? workingWindow : idleWindow }

    /// The events that announce a newly discovered session, and whether a turn is in flight.
    /// - Parameters:
    ///   - history: backlog events parsed from the tail of the log.
    ///   - titleIsStored: the title came from the tool's own records, so prompts must not replace it.
    ///   - quiet: seconds since the log was last written.
    static func discovery(id: String, source: AgentSource, title: String, titleIsStored: Bool, cwd: String,
                          history: [AgentEvent], quiet: TimeInterval) -> (events: [AgentEvent], working: Bool) {
        // Trust the last turn marker in the history; without one, go by recency.
        let lastMarker = history.last { $0.kind == .turnStarted || $0.kind == .turnEnded }
        let working = lastMarker.map { $0.kind == .turnStarted } ?? (quiet < assumeWorkingWithin)

        var events = [AgentEvent(id, .appeared(source: source, title: title, cwd: cwd, parent: nil))]
        if working {
            events.append(AgentEvent(id, .turnStarted))
            // Only the current turn's actions describe where the agent is now.
            let currentTurn = history.lastIndex { $0.kind == .turnStarted }.map { history[($0 + 1)...] } ?? history[...]
            events += currentTurn.filter { if case .activity = $0.kind { return true } else { return false } }
        }
        if !titleIsStored,
           let prompt = history.last(where: { if case .titled = $0.kind { return true } else { return false } }) {
            events.append(AgentEvent(id, prompt.kind))
        }
        return (events, working)
    }
}
