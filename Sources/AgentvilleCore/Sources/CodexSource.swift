import Foundation
import SQLite3

/// Turns Codex rollout lines into events. Pure, so it can be tested with fixtures.
public enum CodexRolloutParser {
    public static func events(fromLine data: Data, agentID: String, backlog: Bool = false) -> [AgentEvent] {
        guard let record = parseJSONObject(data), let type = record["type"] as? String,
              let payload = record["payload"] as? [String: Any] else { return [] }
        let payloadType = payload["type"] as? String
        func event(_ kind: AgentEvent.Kind) -> AgentEvent { AgentEvent(agentID, kind, isBacklog: backlog) }
        func activity(_ result: Classification) -> AgentEvent {
            event(.activity(stage: result.stage, status: result.status, ship: result.ship))
        }

        switch (type, payloadType) {
        case ("event_msg", "task_started"):
            return [event(.turnStarted)]
        case ("event_msg", "task_complete"), ("event_msg", "turn_aborted"):
            return [event(.turnEnded)]
        case ("event_msg", "user_message"):
            guard let message = payload["message"] as? String else { return [] }
            let title = request(in: message).titleLine()
            return title.isEmpty ? [] : [event(.titled(title))]

        case ("response_item", "function_call"):
            guard let name = payload["name"] as? String else { return [] }
            return [activity(StageClassifier.codex(tool: name, command: command(fromArguments: payload["arguments"])))]
        case ("response_item", "custom_tool_call"):
            guard let name = payload["name"] as? String else { return [] }
            return [activity(StageClassifier.codex(tool: name, command: nil))]
        case ("response_item", "local_shell_call"):
            let action = payload["action"] as? [String: Any]
            return [activity(StageClassifier.codex(tool: "local_shell", command: commandString(action?["command"])))]
        case ("response_item", "web_search_call"):
            return [activity(StageClassifier.codex(tool: "web_search", command: nil))]
        case ("response_item", "reasoning"):
            return [event(.activity(stage: nil, status: "Thinking…", ship: false))]

        case ("turn_context", _):
            guard isPlanMode(payload["collaboration_mode"]) else { return [] }
            return [event(.activity(stage: .plan, status: "Planning…", ship: false))]

        default:
            return []
        }
    }

    /// The IDE extension wraps prompts in editor context; what the user typed follows this heading.
    private static func request(in message: String) -> String {
        guard let marker = message.range(of: "## My request for Codex:") else { return message }
        return String(message[marker.upperBound...])
    }

    /// `arguments` is a JSON string. Newer builds use `cmd` (string); older ones `command` (argv array).
    private static func command(fromArguments arguments: Any?) -> String? {
        guard let text = arguments as? String, let args = parseJSONObject(Data(text.utf8)) else { return nil }
        return commandString(args["cmd"] ?? args["command"])
    }

    private static func commandString(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let argv = value as? [String] else { return nil }
        // ["bash", "-lc", "<script>"] — the script is what matters.
        if argv.count >= 3, argv[1].hasPrefix("-"), argv[1].contains("c") { return argv[2...].joined(separator: " ") }
        return argv.joined(separator: " ")
    }

    private static func isPlanMode(_ value: Any?) -> Bool {
        if let string = value as? String { return string.lowercased() == "plan" }
        if let dict = value as? [String: Any] { return (dict["mode"] as? String)?.lowercased() == "plan" }
        return false
    }
}

/// Watches `~/.codex/sessions` for rollout files that are being written to.
public final class CodexSource: AgentEventSource {
    private struct Thread {
        var id: String
        var threadID: String
        var tailer: JSONLTailer
        var working: Bool
        var hasStoredTitle: Bool
    }

    private let root: URL
    private var threads: [String: Thread] = [:] // keyed by rollout path
    private var lastScan = Date.distantPast

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.root = root
    }

    public func poll(now: Date) -> [AgentEvent] {
        var out: [AgentEvent] = []
        if now.timeIntervalSince(lastScan) >= RecentLogs.scanInterval {
            lastScan = now
            scan(now: now, into: &out)
        }
        for path in threads.keys.sorted() {
            guard var thread = threads[path] else { continue }
            for line in thread.tailer.readNewLines() {
                for event in CodexRolloutParser.events(fromLine: line, agentID: thread.id) {
                    switch event.kind {
                    case .turnStarted, .activity: thread.working = true
                    case .turnEnded: thread.working = false
                    case .titled: if thread.hasStoredTitle { continue }
                    default: break
                    }
                    out.append(event)
                }
            }
            threads[path] = thread
        }
        return out
    }

    private func scan(now: Date, into out: inout [AgentEvent]) {
        var modified: [String: Date] = [:]
        let sessions = root.appendingPathComponent("sessions")
        if let walker = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      now.timeIntervalSince(date) < RecentLogs.workingWindow else { continue }
                modified[url.path] = date
            }
        }

        for (path, thread) in threads {
            let quiet = modified[path].map { now.timeIntervalSince($0) } ?? .infinity
            if quiet > RecentLogs.quietLimit(working: thread.working) {
                out.append(AgentEvent(thread.id, .gone))
                threads[path] = nil
            } else if !thread.hasStoredTitle, let title = storedTitle(threadID: thread.threadID) {
                threads[path]?.hasStoredTitle = true
                out.append(AgentEvent(thread.id, .titled(title)))
            }
        }

        for (path, date) in modified where threads[path] == nil {
            guard now.timeIntervalSince(date) < RecentLogs.idleWindow else { continue }
            track(URL(fileURLWithPath: path), modified: date, now: now, into: &out)
        }
    }

    private func track(_ url: URL, modified: Date, now: Date, into out: inout [AgentEvent]) {
        let threadID = Self.threadID(fromRolloutName: url.deletingPathExtension().lastPathComponent)
        let id = "codex:\(threadID)"
        let stored = storedTitle(threadID: threadID)
        let cwd = Self.sessionMeta(url)?["cwd"] as? String ?? ""
        let fallbackTitle = cwd.isEmpty ? "Codex session" : (cwd as NSString).lastPathComponent

        let tailer = JSONLTailer(url: url, tailBytes: RecentLogs.tailBytes)
        let history = tailer.readNewLines().flatMap {
            CodexRolloutParser.events(fromLine: $0, agentID: id, backlog: true)
        }
        let (events, working) = RecentLogs.discovery(
            id: id, source: .codex, title: stored ?? fallbackTitle, titleIsStored: stored != nil, cwd: cwd,
            history: history, quiet: now.timeIntervalSince(modified))
        out.append(contentsOf: events)
        threads[url.path] = Thread(id: id, threadID: threadID, tailer: tailer,
                                   working: working, hasStoredTitle: stored != nil)
    }

    /// `rollout-2026-04-02T16-08-07-<uuid>` → `<uuid>`.
    static func threadID(fromRolloutName name: String) -> String {
        let parts = name.split(separator: "-")
        return parts.count >= 5 ? parts.suffix(5).joined(separator: "-") : name
    }

    /// The `session_meta` payload from the first line. That line embeds the full system
    /// prompt, so read in chunks up to the first newline rather than assuming a size.
    private static func sessionMeta(_ url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while line.count < 4 * 1024 * 1024, let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let newline = chunk.firstIndex(of: 0x0A) {
                line.append(chunk[chunk.startIndex..<newline])
                break
            }
            line.append(chunk)
        }
        guard let record = parseJSONObject(line), record["type"] as? String == "session_meta" else { return nil }
        return record["payload"] as? [String: Any]
    }

    // MARK: Titles

    /// The thread's name as Codex shows it: from the state database, else the session index.
    private func storedTitle(threadID: String) -> String? {
        let title = databaseTitle(threadID: threadID) ?? indexTitle(threadID: threadID)
        guard let line = title?.titleLine(), !line.isEmpty else { return nil }
        return line
    }

    private func databaseTitle(threadID: String) -> String? {
        let candidates = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.hasPrefix("state_") && $0.hasSuffix(".sqlite") }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        guard let name = candidates.first else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(root.appendingPathComponent(name).path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 50)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT title FROM threads WHERE id = ?1", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, threadID, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }

    private func indexTitle(threadID: String) -> String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("session_index.jsonl")) else { return nil }
        var title: String?
        for line in data.split(separator: 0x0A) {
            guard let record = parseJSONObject(Data(line)), record["id"] as? String == threadID else { continue }
            title = record["thread_name"] as? String ?? title
        }
        return title
    }
}
