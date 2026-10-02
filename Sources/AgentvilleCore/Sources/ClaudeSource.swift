import Foundation

/// Turns Claude Code transcript lines into events. Pure, so it can be tested with fixtures.
public enum ClaudeTranscriptParser {
    /// - Parameter inferTurns: derive turn start/end from the transcript itself. Used when
    ///   there is no session status file to say whether the agent is busy (subagents, replay).
    public static func events(fromLine data: Data, agentID: String,
                              inferTurns: Bool, backlog: Bool = false) -> [AgentEvent] {
        guard let record = parseJSONObject(data), let type = record["type"] as? String else { return [] }
        func event(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(agentID, kind, isBacklog: backlog) }

        switch type {
        case "assistant":
            guard let message = record["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return [] }
            var out: [AgentEvent] = []
            var usedTool = false
            for block in content where block["type"] as? String == "tool_use" {
                guard let name = block["name"] as? String else { continue }
                usedTool = true
                let result = StageClassifier.claude(tool: name, input: block["input"] as? [String: Any] ?? [:])
                out.append(event(.activity(stage: result.stage, status: result.status, ship: result.ship)))
            }
            if inferTurns {
                let hasText = content.contains { $0["type"] as? String == "text" }
                if usedTool {
                    out.insert(event(.turnStarted), at: 0)
                } else if hasText && message["stop_reason"] as? String != "tool_use" {
                    // A text-only reply is the agent handing back.
                    out.append(event(.turnEnded))
                }
            }
            return out

        case "permission-mode":
            guard record["permissionMode"] as? String == "plan" else { return [] }
            return [event(.activity(stage: .plan, status: "Planning…", ship: false))]

        case "last-prompt":
            guard let prompt = record["lastPrompt"] as? String, let title = promptTitle(prompt) else { return [] }
            return [event(.titled(title))]

        case "user":
            guard record["isMeta"] as? Bool != true, record["isSidechain"] as? Bool != true,
                  let message = record["message"] as? [String: Any],
                  let text = message["content"] as? String, let title = promptTitle(text) else { return [] }
            var out = [event(.titled(title))]
            if inferTurns { out.append(event(.turnStarted)) }
            return out

        case "system":
            guard inferTurns, record["subtype"] as? String == "turn_duration" else { return [] }
            return [event(.turnEnded)]

        default:
            return []
        }
    }

    /// A user prompt as a short title, or nil for harness-generated text (`<command-name>…`).
    static func promptTitle(_ prompt: String) -> String? {
        let title = prompt.titleLine()
        return title.isEmpty || title.hasPrefix("<") ? nil : title
    }
}

/// Watches `~/.claude`: the live session registry for who is running and whether they are busy,
/// and each session's transcript (plus its subagents') for what they are doing.
public final class ClaudeSource: AgentEventSource {
    private struct Session {
        var sessionID: String
        var name: String?
        var promptTitle: String?
        var working: Bool?
        var transcript: URL?
        var tailer: JSONLTailer?
        var backlogPending = true
        var subagents: [String: Subagent] = [:]
        var finishedSubagents: Set<String> = []
    }

    private struct Subagent {
        var id: String
        var tailer: JSONLTailer
        var backlogPending = true
        var endedAt: Date?
    }

    private struct RosterEntry {
        var key: String
        var sessionID: String
        var cwd: String
        var name: String?
        var nameIsDerived: Bool
        var working: Bool?
    }

    private let root: URL
    private let isAlive: (Int32) -> Bool
    private var sessions: [String: Session] = [:]
    private var lastRoster = Date.distantPast

    static let tailBytes: UInt64 = 64 * 1024
    static let rosterInterval: TimeInterval = 2
    /// Without the registry, a transcript touched this recently counts as a running session.
    static let fallbackWindow: TimeInterval = 5 * 60
    static let subagentDiscoveryWindow: TimeInterval = 2 * 60
    static let subagentQuietLimit: TimeInterval = 3 * 60
    static let subagentLingerAfterEnd: TimeInterval = 8

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
                isAlive: @escaping (Int32) -> Bool = ClaudeSource.processIsAlive) {
        self.root = root
        self.isAlive = isAlive
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public func poll(now: Date) -> [AgentEvent] {
        var out: [AgentEvent] = []
        if now.timeIntervalSince(lastRoster) >= Self.rosterInterval {
            lastRoster = now
            refreshRoster(now: now, into: &out)
        }
        for key in sessions.keys.sorted() {
            readTranscripts(key: key, now: now, into: &out)
        }
        return out
    }

    // MARK: Roster

    private func refreshRoster(now: Date, into out: inout [AgentEvent]) {
        let entries = registryEntries() ?? fallbackEntries(now: now)
        var seen: Set<String> = []

        for entry in entries {
            seen.insert(entry.key)
            var session = sessions[entry.key]
            let isNew = session == nil
            if session == nil {
                session = Session(sessionID: entry.sessionID)
            } else if session!.sessionID != entry.sessionID {
                // Same process, new conversation (/clear or resume): follow the new transcript.
                for sub in session!.subagents.values { out.append(AgentEvent(sub.id, .gone)) }
                session = Session(sessionID: entry.sessionID, working: session!.working)
            }
            var current = session!
            current.name = entry.nameIsDerived ? nil : entry.name

            if isNew {
                let title = current.name ?? entry.name ?? (entry.cwd as NSString).lastPathComponent
                out.append(AgentEvent(entry.key, .appeared(source: .claude, title: title, cwd: entry.cwd, parent: nil)))
            }
            if let working = entry.working, working != current.working || isNew {
                current.working = working
                out.append(AgentEvent(entry.key, working ? .turnStarted : .turnEnded))
            }
            if entry.working == nil { current.working = nil }

            if current.transcript == nil, let url = locateTranscript(sessionID: entry.sessionID) {
                current.transcript = url
                current.tailer = JSONLTailer(url: url, tailBytes: Self.tailBytes)
            }
            sessions[entry.key] = current
            refreshSubagents(key: entry.key, now: now, into: &out)
        }

        for key in Array(sessions.keys) where !seen.contains(key) {
            out.append(AgentEvent(key, .gone))
            sessions[key] = nil
        }
    }

    /// Live sessions from `sessions/<pid>.json`. Returns nil when the registry is missing or
    /// unreadable, which is the signal to fall back to transcript modification times.
    private func registryEntries() -> [RosterEntry]? {
        let dir = root.appendingPathComponent("sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        var entries: [RosterEntry] = []
        var parsedAny = false
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let record = parseJSONObject(data),
                  let pid = (record["pid"] as? NSNumber)?.int32Value,
                  let sessionID = record["sessionId"] as? String else { continue }
            parsedAny = true
            guard isAlive(pid) else { continue }
            let status = record["status"] as? String
            entries.append(RosterEntry(
                key: "claude:\(pid)",
                sessionID: sessionID,
                cwd: record["cwd"] as? String ?? "",
                name: record["name"] as? String,
                nameIsDerived: record["nameSource"] as? String == "derived",
                working: status.map { $0 == "busy" }))
        }
        let hasJSON = files.contains { $0.pathExtension == "json" }
        // JSON files exist but none had the fields we need: the format changed under us.
        return hasJSON && !parsedAny ? nil : entries
    }

    private func fallbackEntries(now: Date) -> [RosterEntry] {
        var entries: [RosterEntry] = []
        for transcript in allTranscripts() {
            guard let modified = JSONLTailer.modificationDate(transcript),
                  now.timeIntervalSince(modified) < Self.fallbackWindow else { continue }
            let sessionID = transcript.deletingPathExtension().lastPathComponent
            entries.append(RosterEntry(key: "claude:\(sessionID)", sessionID: sessionID,
                                       cwd: "", name: nil, nameIsDerived: true, working: nil))
        }
        return entries
    }

    private func allTranscripts() -> [URL] {
        let projects = root.appendingPathComponent("projects")
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
    }

    private func locateTranscript(sessionID: String) -> URL? {
        let projects = root.appendingPathComponent("projects")
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: Subagents

    private func refreshSubagents(key: String, now: Date, into out: inout [AgentEvent]) {
        guard var session = sessions[key], let transcript = session.transcript else { return }
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            guard let modified = JSONLTailer.modificationDate(file) else { continue }
            let quiet = now.timeIntervalSince(modified)

            if let sub = session.subagents[name] {
                let ended = sub.endedAt.map { now.timeIntervalSince($0) >= Self.subagentLingerAfterEnd } ?? false
                if ended || quiet > Self.subagentQuietLimit {
                    out.append(AgentEvent(sub.id, .gone))
                    session.subagents[name] = nil
                    session.finishedSubagents.insert(name)
                }
            } else if !session.finishedSubagents.contains(name), quiet < Self.subagentDiscoveryWindow {
                let id = "\(key)/\(name)"
                let meta = (try? Data(contentsOf: dir.appendingPathComponent("\(name).meta.json")))
                    .flatMap(parseJSONObject)
                let title = (meta?["description"] as? String) ?? (meta?["agentType"] as? String) ?? "Subagent"
                out.append(AgentEvent(id, .appeared(source: .claude, title: title.titleLine(),
                                                    cwd: "", parent: key)))
                out.append(AgentEvent(id, .turnStarted))
                session.subagents[name] = Subagent(id: id, tailer: JSONLTailer(url: file, tailBytes: Self.tailBytes))
            }
        }
        sessions[key] = session
    }

    // MARK: Transcripts

    private func readTranscripts(key: String, now: Date, into out: inout [AgentEvent]) {
        guard var session = sessions[key] else { return }

        if let tailer = session.tailer {
            let backlog = session.backlogPending
            let inferTurns = session.working == nil
            for line in tailer.readNewLines() {
                for event in ClaudeTranscriptParser.events(fromLine: line, agentID: key,
                                                          inferTurns: inferTurns, backlog: backlog) {
                    if case .titled(let title) = event.kind {
                        // A name the user gave the session beats the last prompt.
                        guard session.name == nil, title != session.promptTitle else { continue }
                        session.promptTitle = title
                    }
                    out.append(event)
                }
            }
            session.backlogPending = false
        }

        for name in session.subagents.keys.sorted() {
            guard var sub = session.subagents[name] else { continue }
            for line in sub.tailer.readNewLines() {
                for event in ClaudeTranscriptParser.events(fromLine: line, agentID: sub.id,
                                                          inferTurns: true, backlog: sub.backlogPending) {
                    switch event.kind {
                    case .titled:
                        continue // keep the description from meta.json
                    case .turnEnded:
                        sub.endedAt = now
                    case .turnStarted, .activity:
                        sub.endedAt = nil
                    default:
                        break
                    }
                    out.append(event)
                }
            }
            sub.backlogPending = false
            session.subagents[name] = sub
        }
        sessions[key] = session
    }
}
