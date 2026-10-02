import Foundation

/// Plays a recorded Claude transcript or Codex rollout back as if it were happening now,
/// keeping the original gaps between records (divided by `speed`).
public final class ReplaySource: AgentEventSource {
    private var queue: [(at: TimeInterval, events: [AgentEvent])] = []
    private var next = 0
    private var start: Date?
    private var finished = false
    private let agentID: String
    private let intro: AgentEvent
    private let speed: Double

    public init(url: URL, speed: Double = 1) {
        self.speed = max(speed, 0.01)
        agentID = "replay:\(url.deletingPathExtension().lastPathComponent)"

        let data = (try? Data(contentsOf: url)) ?? Data()
        let lines = data.split(separator: 0x0A).map { Data($0) }
        // Each tool's records have a distinct envelope: Codex `payload`, Copilot `data`.
        let first = lines.first.flatMap(parseJSONObject)
        let source: AgentSource = first?["payload"] != nil ? .codex : first?["data"] != nil ? .copilot : .claude
        intro = AgentEvent(agentID, .appeared(source: source,
                                              title: url.deletingPathExtension().lastPathComponent.titleLine(limit: 40),
                                              cwd: url.deletingLastPathComponent().path, parent: nil))

        var began: Date?
        var latest: TimeInterval = 0
        for line in lines {
            if let stamp = parseJSONObject(line)?["timestamp"] as? String, let date = Self.date(stamp) {
                if began == nil { began = date }
                latest = max(latest, date.timeIntervalSince(began!))
            }
            let events: [AgentEvent]
            switch source {
            case .codex: events = CodexRolloutParser.events(fromLine: line, agentID: agentID)
            case .copilot: events = CopilotEventParser.events(fromLine: line, agentID: agentID)
            case .claude: events = ClaudeTranscriptParser.events(fromLine: line, agentID: agentID, inferTurns: true)
            }
            if !events.isEmpty { queue.append((latest, events)) }
        }
    }

    public func poll(now: Date) -> [AgentEvent] {
        var out: [AgentEvent] = []
        if start == nil {
            start = now
            out.append(intro)
        }
        let position = now.timeIntervalSince(start!) * speed
        while next < queue.count, queue[next].at <= position {
            out.append(contentsOf: queue[next].events)
            next += 1
        }
        if next == queue.count, !finished {
            finished = true
            out.append(AgentEvent(agentID, .turnEnded))
        }
        return out
    }

    private static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
