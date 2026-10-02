import Foundation

/// Turns GitHub Copilot CLI session events into agent events. Pure, so it can be tested with fixtures.
public enum CopilotEventParser {
    public static func events(fromLine data: Data, agentID: String, backlog: Bool = false) -> [AgentEvent] {
        guard let record = parseJSONObject(data), let type = record["type"] as? String else { return [] }
        let payload = record["data"] as? [String: Any] ?? [:]
        func event(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(agentID, kind, isBacklog: backlog) }

        switch type {
        case "user.message":
            let title = (payload["content"] as? String ?? "").titleLine()
            return (title.isEmpty ? [] : [event(.titled(title))]) + [event(.turnStarted)]

        case "assistant.turn_start":
            return [event(.turnStarted)]

        case "tool.execution_start":
            guard let name = payload["toolName"] as? String else { return [] }
            let result = StageClassifier.copilot(tool: name, arguments: payload["arguments"] as? [String: Any] ?? [:])
            return [event(.activity(stage: result.stage, status: result.status, ship: result.ship))]

        case "assistant.message":
            // Copilot marks the end of each model round-trip, not of the whole reply.
            // A message that asks for no tools is the one that hands back to the user.
            let requests = payload["toolRequests"] as? [Any] ?? []
            let text = payload["content"] as? String ?? ""
            return requests.isEmpty && !text.isEmpty ? [event(.turnEnded)] : []

        case "session.idle", "abort":
            return [event(.turnEnded)]

        default:
            return []
        }
    }
}

/// Watches `~/.copilot/session-state/<id>/events.jsonl` for sessions that are being written to.
public final class CopilotSource: AgentEventSource {
    private struct Session {
        var id: String
        var directory: URL
        var tailer: JSONLTailer
        var working: Bool
        var hasSummary: Bool
    }

    private let root: URL
    private var sessions: [String: Session] = [:] // keyed by events.jsonl path
    private var lastScan = Date.distantPast

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot")) {
        self.root = root
    }

    public func poll(now: Date) -> [AgentEvent] {
        var out: [AgentEvent] = []
        if now.timeIntervalSince(lastScan) >= RecentLogs.scanInterval {
            lastScan = now
            scan(now: now, into: &out)
        }
        for path in sessions.keys.sorted() {
            guard var session = sessions[path] else { continue }
            for line in session.tailer.readNewLines() {
                for event in CopilotEventParser.events(fromLine: line, agentID: session.id) {
                    switch event.kind {
                    case .turnStarted, .activity: session.working = true
                    case .turnEnded: session.working = false
                    case .titled: if session.hasSummary { continue }
                    default: break
                    }
                    out.append(event)
                }
            }
            sessions[path] = session
        }
        return out
    }

    private func scan(now: Date, into out: inout [AgentEvent]) {
        var modified: [String: Date] = [:]
        let state = root.appendingPathComponent("session-state")
        for directory in (try? FileManager.default.contentsOfDirectory(at: state, includingPropertiesForKeys: nil)) ?? [] {
            let log = directory.appendingPathComponent("events.jsonl")
            guard let date = JSONLTailer.modificationDate(log),
                  now.timeIntervalSince(date) < RecentLogs.workingWindow else { continue }
            modified[log.path] = date
        }

        for (path, session) in sessions {
            let quiet = modified[path].map { now.timeIntervalSince($0) } ?? .infinity
            if quiet > RecentLogs.quietLimit(working: session.working) {
                out.append(AgentEvent(session.id, .gone))
                sessions[path] = nil
            } else if !session.hasSummary, let summary = Self.workspace(session.directory)["summary"] {
                // Copilot names the session once it has seen enough of it.
                sessions[path]?.hasSummary = true
                out.append(AgentEvent(session.id, .titled(summary.titleLine())))
            }
        }

        for (path, date) in modified where sessions[path] == nil {
            guard now.timeIntervalSince(date) < RecentLogs.idleWindow else { continue }
            let log = URL(fileURLWithPath: path)
            let directory = log.deletingLastPathComponent()
            let id = "copilot:\(directory.lastPathComponent)"
            let workspace = Self.workspace(directory)
            let cwd = workspace["cwd"] ?? ""
            let fallbackTitle = cwd.isEmpty ? "Copilot session" : (cwd as NSString).lastPathComponent

            let tailer = JSONLTailer(url: log, tailBytes: RecentLogs.tailBytes)
            let history = tailer.readNewLines().flatMap {
                CopilotEventParser.events(fromLine: $0, agentID: id, backlog: true)
            }
            let (events, working) = RecentLogs.discovery(
                id: id, source: .copilot, title: workspace["summary"]?.titleLine() ?? fallbackTitle,
                titleIsStored: workspace["summary"] != nil, cwd: cwd,
                history: history, quiet: now.timeIntervalSince(date))
            out.append(contentsOf: events)
            sessions[path] = Session(id: id, directory: directory, tailer: tailer,
                                     working: working, hasSummary: workspace["summary"] != nil)
        }
    }

    /// Top-level `key: value` pairs from the session's `workspace.yaml`. Only flat string
    /// fields are needed (`cwd`, `summary`), so this is not a general YAML parser.
    static func workspace(_ directory: URL) -> [String: String] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("workspace.yaml"), encoding: .utf8) else {
            return [:]
        }
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix(" ") && !line.hasPrefix("#") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { fields[String(line[..<colon])] = value }
        }
        return fields
    }
}
