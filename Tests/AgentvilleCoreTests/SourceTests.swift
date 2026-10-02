import XCTest
@testable import AgentvilleCore

/// Fixtures are hand-written with the record shapes Claude Code and Codex produce,
/// not copied from real sessions.
final class SourceTests: XCTestCase {
    private var root: URL!
    private let t0 = Date()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("aw-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func toolUse(_ name: String, _ input: String) -> String {
        #"{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"# + "\n"
    }

    // MARK: Tailer

    func testTailerReturnsOnlyCompleteNewLines() throws {
        let url = try write("one\ntwo\npart", to: "log.jsonl")
        let tailer = JSONLTailer(url: url)
        XCTAssertEqual(tailer.readNewLines().map { String(decoding: $0, as: UTF8.self) }, ["one", "two"])
        XCTAssertEqual(tailer.readNewLines(), [])
        try append("ial\nthree\n", to: url)
        XCTAssertEqual(tailer.readNewLines().map { String(decoding: $0, as: UTF8.self) }, ["partial", "three"])
    }

    func testTailerStartsNearTheEndAndDropsTheCutLine() throws {
        let url = try write("aaaaaaaaaa\nbbbbbbbbbb\ncccc\n", to: "log.jsonl")
        let tailer = JSONLTailer(url: url, tailBytes: 8)
        XCTAssertEqual(tailer.readNewLines().map { String(decoding: $0, as: UTF8.self) }, ["cccc"])
    }

    func testTailerRecoversFromTruncation() throws {
        let url = try write("one\ntwo\n", to: "log.jsonl")
        let tailer = JSONLTailer(url: url)
        _ = tailer.readNewLines()
        try Data("new\n".utf8).write(to: url)
        XCTAssertEqual(tailer.readNewLines().map { String(decoding: $0, as: UTF8.self) }, ["new"])
    }

    func testTailerOnMissingFile() {
        XCTAssertEqual(JSONLTailer(url: root.appendingPathComponent("nope.jsonl")).readNewLines(), [])
    }

    // MARK: Claude

    func testClaudeParser() {
        func parse(_ line: String, inferTurns: Bool = false) -> [AgentEvent.Kind] {
            ClaudeTranscriptParser.events(fromLine: Data(line.utf8), agentID: "x", inferTurns: inferTurns).map(\.kind)
        }
        XCTAssertEqual(parse(toolUse("Edit", #"{"file_path":"/r/A.swift"}"#)),
                       [.activity(stage: .build, status: "Editing A.swift…", ship: false)])
        XCTAssertEqual(parse(#"{"type":"permission-mode","permissionMode":"plan"}"#),
                       [.activity(stage: .plan, status: "Planning…", ship: false)])
        XCTAssertEqual(parse(#"{"type":"permission-mode","permissionMode":"auto"}"#), [])
        XCTAssertEqual(parse(#"{"type":"last-prompt","lastPrompt":"  fix the\tlogin   bug\nmore"}"#), [.titled("fix the\tlogin bug")])
        XCTAssertEqual(parse(#"{"type":"last-prompt","leafUuid":"abc"}"#), [])
        XCTAssertEqual(parse(#"{"type":"user","message":{"content":"<command-name>/plan</command-name>"}}"#), [])
        XCTAssertEqual(parse(#"{"type":"user","message":{"content":"add tests"}}"#), [.titled("add tests")])
        XCTAssertEqual(parse(#"{"type":"something-new","payload":1}"#), [])
        XCTAssertEqual(parse("not json at all"), [])
        XCTAssertEqual(parse(#"[1,2,3]"#), [])

        // Turn inference, for transcripts with no status file alongside.
        XCTAssertEqual(parse(toolUse("Read", "{}"), inferTurns: true).first, .turnStarted)
        XCTAssertEqual(parse(#"{"type":"assistant","message":{"stop_reason":null,"content":[{"type":"text","text":"done"}]}}"#, inferTurns: true),
                       [.turnEnded])
        XCTAssertEqual(parse(#"{"type":"assistant","message":{"content":[{"type":"thinking"}]}}"#, inferTurns: true), [])
        XCTAssertEqual(parse(#"{"type":"system","subtype":"turn_duration"}"#, inferTurns: true), [.turnEnded])
    }

    func testClaudeSourceFollowsALiveSession() throws {
        _ = try write(#"{"pid":111,"sessionId":"s1","cwd":"/repo/app","name":"app-1","nameSource":"derived","status":"busy"}"#,
                      to: "sessions/111.json")
        _ = try write(#"{"pid":222,"sessionId":"s2","cwd":"/repo/old","status":"busy"}"#, to: "sessions/222.json")
        let transcript = try write(
            #"{"type":"last-prompt","lastPrompt":"ship the export"}"# + "\n" + toolUse("Read", #"{"file_path":"/repo/app/a.ts"}"#),
            to: "projects/-repo-app/s1.jsonl")

        let source = ClaudeSource(root: root, isAlive: { $0 == 111 })
        let store = FloorStore()
        store.ingest(source.poll(now: t0), now: t0)

        XCTAssertEqual(store.agents.map(\.id), ["claude:111"], "dead pid 222 is skipped")
        var agent = try XCTUnwrap(store.agent("claude:111"))
        XCTAssertEqual(agent.title, "ship the export")
        XCTAssertEqual(agent.cwd, "/repo/app")
        XCTAssertTrue(agent.isWorking)
        XCTAssertEqual(agent.stage, .research, "history places a busy agent")

        try append(toolUse("Bash", #"{"command":"git commit -m x"}"#), to: transcript)
        store.ingest(source.poll(now: t0.addingTimeInterval(0.5)), now: t0.addingTimeInterval(0.5))
        agent = try XCTUnwrap(store.agent("claude:111"))
        XCTAssertEqual(agent.status, "Committing…")
        XCTAssertEqual(agent.shipCount, 1)

        // Status flips to idle, then the process exits.
        _ = try write(#"{"pid":111,"sessionId":"s1","cwd":"/repo/app","status":"idle"}"#, to: "sessions/111.json")
        store.ingest(source.poll(now: t0.addingTimeInterval(3)), now: t0.addingTimeInterval(3))
        XCTAssertEqual(store.agent("claude:111")?.isWorking, false)

        try FileManager.default.removeItem(at: root.appendingPathComponent("sessions/111.json"))
        store.ingest(source.poll(now: t0.addingTimeInterval(6)), now: t0.addingTimeInterval(6))
        XCTAssertTrue(store.agents.isEmpty)
    }

    func testClaudeSourceTracksSubagents() throws {
        _ = try write(#"{"pid":7,"sessionId":"s1","cwd":"/repo","status":"busy"}"#, to: "sessions/7.json")
        _ = try write(toolUse("Agent", #"{"subagent_type":"Explore"}"#), to: "projects/-repo/s1.jsonl")
        _ = try write(#"{"agentType":"Explore","description":"Find the auth code"}"#,
                      to: "projects/-repo/s1/subagents/agent-a1.meta.json")
        let subTranscript = try write(toolUse("Grep", "{}"), to: "projects/-repo/s1/subagents/agent-a1.jsonl")

        let source = ClaudeSource(root: root, isAlive: { _ in true })
        let store = FloorStore()
        store.ingest(source.poll(now: t0), now: t0)

        let sub = try XCTUnwrap(store.agent("claude:7/agent-a1"))
        XCTAssertEqual(sub.title, "Find the auth code")
        XCTAssertEqual(sub.parentID, "claude:7")
        XCTAssertEqual(sub.stage, .research)

        // A text-only reply ends the subagent; it leaves shortly after.
        try append(#"{"type":"assistant","message":{"content":[{"type":"text","text":"found it"}]}}"# + "\n", to: subTranscript)
        store.ingest(source.poll(now: t0.addingTimeInterval(0.5)), now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(store.agent("claude:7/agent-a1")?.status, "Done")
        store.ingest(source.poll(now: t0.addingTimeInterval(12)), now: t0.addingTimeInterval(12))
        XCTAssertNil(store.agent("claude:7/agent-a1"))
        store.ingest(source.poll(now: t0.addingTimeInterval(15)), now: t0.addingTimeInterval(15))
        XCTAssertNil(store.agent("claude:7/agent-a1"), "a finished subagent does not come back")
    }

    func testClaudeSourceFallsBackToRecentTranscriptsWithoutARegistry() throws {
        _ = try write(toolUse("Edit", #"{"file_path":"/r/a.swift"}"#), to: "projects/-r/s9.jsonl")
        let source = ClaudeSource(root: root, isAlive: { _ in false })
        let store = FloorStore()
        store.ingest(source.poll(now: t0), now: t0)
        XCTAssertEqual(store.agents.map(\.id), ["claude:s9"])
        XCTAssertEqual(store.agent("claude:s9")?.stage, .build)
    }

    func testSourcesSurviveEmptyAndGarbageInput() throws {
        XCTAssertEqual(ClaudeSource(root: root, isAlive: { _ in true }).poll(now: t0), [])
        XCTAssertEqual(CodexSource(root: root).poll(now: t0), [])
        XCTAssertEqual(CopilotSource(root: root).poll(now: t0), [])

        _ = try write("{{{ nope", to: "sessions/1.json")
        _ = try write("\u{0}\u{1}garbage\n{\"type\":5}\n[]\n", to: "projects/-x/s.jsonl")
        _ = try write("garbage\n{\"type\":\"event_msg\"}\n{\"payload\":3}\n",
                      to: "sessions/2026/01/01/rollout-2026-01-01T00-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl")
        _ = try write("not a database", to: "state_5.sqlite")
        _ = try write("garbage\n{\"type\":7}\n{\"type\":\"tool.execution_start\",\"data\":[]}\n", to: "session-state/x/events.jsonl")
        _ = try write(":::\n\u{0}", to: "session-state/x/workspace.yaml")

        let store = FloorStore()
        store.ingest(ClaudeSource(root: root, isAlive: { _ in true }).poll(now: t0), now: t0)
        store.ingest(CodexSource(root: root).poll(now: t0), now: t0)
        store.ingest(CopilotSource(root: root).poll(now: t0), now: t0)
        XCTAssertEqual(store.agents.count, 3)
        // The recent files show up as idle agents; nothing crashes and nothing is misread as work.
        XCTAssertTrue(store.agents.allSatisfy { $0.stage == nil })
    }

    // MARK: Codex

    private func codex(_ type: String, _ payload: String) -> String {
        #"{"timestamp":"2026-01-01T00:00:00.000Z","type":"\#(type)","payload":\#(payload)}"# + "\n"
    }

    func testCodexParser() {
        func parse(_ line: String) -> [AgentEvent.Kind] {
            CodexRolloutParser.events(fromLine: Data(line.utf8), agentID: "x").map(\.kind)
        }
        XCTAssertEqual(parse(codex("event_msg", #"{"type":"task_started","turn_id":"t"}"#)), [.turnStarted])
        XCTAssertEqual(parse(codex("event_msg", #"{"type":"task_complete"}"#)), [.turnEnded])
        XCTAssertEqual(parse(codex("event_msg", #"{"type":"user_message","message":"Remove the logo\nplease"}"#)),
                       [.titled("Remove the logo")])
        XCTAssertEqual(parse(codex("event_msg", ##"{"type":"user_message","message":"# Context from my IDE setup:\n\n## Open tabs:\n- a.ts\n\n## My request for Codex:\nRemove the logo\n"}"##)),
                       [.titled("Remove the logo")])
        XCTAssertEqual(parse(codex("response_item", #"{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"npm test\",\"workdir\":\"/r\"}"}"#)),
                       [.activity(stage: .verify, status: "Running tests…", ship: false)])
        XCTAssertEqual(parse(codex("response_item", #"{"type":"function_call","name":"shell","arguments":"{\"command\":[\"bash\",\"-lc\",\"git push\"]}"}"#)),
                       [.activity(stage: .ship, status: "Pushing…", ship: true)])
        XCTAssertEqual(parse(codex("response_item", #"{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch"}"#)),
                       [.activity(stage: .build, status: "Applying a patch…", ship: false)])
        XCTAssertEqual(parse(codex("turn_context", #"{"collaboration_mode":{"mode":"plan"}}"#)),
                       [.activity(stage: .plan, status: "Planning…", ship: false)])
        XCTAssertEqual(parse(codex("turn_context", #"{"collaboration_mode":{"mode":"default"}}"#)), [])
        XCTAssertEqual(parse(codex("event_msg", #"{"type":"token_count"}"#)), [])
        XCTAssertEqual(parse(codex("response_item", #"{"type":"function_call","name":"exec_command","arguments":"not json"}"#)),
                       [.activity(stage: nil, status: "Running a command…", ship: false)])
    }

    func testCodexSourceFollowsARollout() throws {
        let name = "sessions/2026/01/01/rollout-2026-01-01T10-00-00-019d4ebc-c4d8-7763-99a3-5a49a44ec9cb.jsonl"
        let rollout = try write(
            codex("session_meta", #"{"id":"019d4ebc-c4d8-7763-99a3-5a49a44ec9cb","cwd":"/repo/site"}"#)
                + codex("event_msg", #"{"type":"task_started"}"#)
                + codex("event_msg", #"{"type":"task_complete"}"#)
                + codex("event_msg", #"{"type":"task_started"}"#)
                + codex("event_msg", #"{"type":"user_message","message":"Remove the logo"}"#)
                + codex("response_item", #"{"type":"custom_tool_call","name":"apply_patch"}"#),
            to: name)
        _ = try write(#"{"id":"019d4ebc-c4d8-7763-99a3-5a49a44ec9cb","thread_name":"Logo cleanup"}"# + "\n", to: "session_index.jsonl")

        let source = CodexSource(root: root)
        let store = FloorStore()
        store.ingest(source.poll(now: t0), now: t0)

        let id = "codex:019d4ebc-c4d8-7763-99a3-5a49a44ec9cb"
        var agent = try XCTUnwrap(store.agent(id))
        XCTAssertEqual(agent.source, .codex)
        XCTAssertEqual(agent.title, "Logo cleanup", "stored thread name beats the prompt")
        XCTAssertEqual(agent.cwd, "/repo/site")
        XCTAssertTrue(agent.isWorking)
        XCTAssertEqual(agent.stage, .build)

        try append(codex("event_msg", #"{"type":"task_complete"}"#), to: rollout)
        store.ingest(source.poll(now: t0.addingTimeInterval(1)), now: t0.addingTimeInterval(1))
        agent = try XCTUnwrap(store.agent(id))
        XCTAssertFalse(agent.isWorking)

        // Quiet for longer than the idle window: the agent leaves.
        let later = t0.addingTimeInterval(11 * 60)
        store.ingest(source.poll(now: later), now: later)
        XCTAssertNil(store.agent(id))
    }

    func testCodexThreadIDFromFilename() {
        XCTAssertEqual(CodexSource.threadID(fromRolloutName: "rollout-2026-04-02T16-08-07-019d4ebc-c4d8-7763-99a3-5a49a44ec9cb"),
                       "019d4ebc-c4d8-7763-99a3-5a49a44ec9cb")
        XCTAssertEqual(CodexSource.threadID(fromRolloutName: "odd"), "odd")
    }

    // MARK: Copilot

    private func copilot(_ type: String, _ data: String) -> String {
        #"{"type":"\#(type)","data":\#(data),"id":"e","timestamp":"2026-01-01T00:00:00.000Z"}"# + "\n"
    }

    func testCopilotParser() {
        func parse(_ line: String) -> [AgentEvent.Kind] {
            CopilotEventParser.events(fromLine: Data(line.utf8), agentID: "x").map(\.kind)
        }
        XCTAssertEqual(parse(copilot("user.message", #"{"content":"Add a dark mode toggle\nthanks"}"#)),
                       [.titled("Add a dark mode toggle"), .turnStarted])
        XCTAssertEqual(parse(copilot("assistant.turn_start", "{}")), [.turnStarted])
        XCTAssertEqual(parse(copilot("tool.execution_start", #"{"toolName":"view","arguments":{"path":"/r/src/App.tsx"}}"#)),
                       [.activity(stage: .research, status: "Reading App.tsx…", ship: false)])
        XCTAssertEqual(parse(copilot("tool.execution_start", #"{"toolName":"edit","arguments":{"path":"/r/src/App.tsx"}}"#)),
                       [.activity(stage: .build, status: "Editing App.tsx…", ship: false)])
        XCTAssertEqual(parse(copilot("tool.execution_start", #"{"toolName":"bash","arguments":{"command":"npm test"}}"#)),
                       [.activity(stage: .verify, status: "Running tests…", ship: false)])
        XCTAssertEqual(parse(copilot("tool.execution_start", #"{"toolName":"report_intent","arguments":{"intent":"Exploring the codebase"}}"#)),
                       [.activity(stage: nil, status: "Exploring the codebase…", ship: false)])
        XCTAssertEqual(parse(copilot("assistant.message", #"{"content":"","toolRequests":[{"name":"view"}]}"#)), [])
        XCTAssertEqual(parse(copilot("assistant.message", #"{"content":"All done.","toolRequests":[]}"#)), [.turnEnded])
        XCTAssertEqual(parse(copilot("assistant.turn_end", "{}")), [], "a round-trip ending is not the reply ending")
        XCTAssertEqual(parse(copilot("tool.execution_start", "{}")), [])
        XCTAssertEqual(parse(#"{"type":"session.start"}"#), [])
    }

    func testCopilotSourceFollowsASession() throws {
        let log = try write(
            copilot("session.start", #"{"sessionId":"abc"}"#)
                + copilot("user.message", #"{"content":"Add a dark mode toggle"}"#)
                + copilot("tool.execution_start", #"{"toolName":"grep","arguments":{"pattern":"theme"}}"#),
            to: "session-state/abc/events.jsonl")
        _ = try write("id: abc\ncwd: /repo/web\nsummary: \"Dark mode toggle\"\nnested:\n  cwd: /wrong\n",
                      to: "session-state/abc/workspace.yaml")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("session-state/empty"),
                                                withIntermediateDirectories: true)

        let source = CopilotSource(root: root)
        let store = FloorStore()
        store.ingest(source.poll(now: t0), now: t0)

        XCTAssertEqual(store.agents.map(\.id), ["copilot:abc"], "a session directory with no log is ignored")
        var agent = try XCTUnwrap(store.agent("copilot:abc"))
        XCTAssertEqual(agent.source, .copilot)
        XCTAssertEqual(agent.title, "Dark mode toggle", "Copilot's own summary beats the prompt")
        XCTAssertEqual(agent.cwd, "/repo/web")
        XCTAssertTrue(agent.isWorking)
        XCTAssertEqual(agent.stage, .research)

        try append(copilot("assistant.message", #"{"content":"Done.","toolRequests":[]}"#), to: log)
        store.ingest(source.poll(now: t0.addingTimeInterval(1)), now: t0.addingTimeInterval(1))
        agent = try XCTUnwrap(store.agent("copilot:abc"))
        XCTAssertFalse(agent.isWorking)

        let later = t0.addingTimeInterval(11 * 60)
        store.ingest(source.poll(now: later), now: later)
        XCTAssertNil(store.agent("copilot:abc"))
    }

    // MARK: Demo and replay

    func testDemoSourceCyclesThroughEveryStation() {
        let source = DemoSource()
        let store = FloorStore()
        var seen: Set<Stage> = []
        var shipped = false
        for step in 0..<160 {
            let now = t0.addingTimeInterval(Double(step) * 0.5)
            store.ingest(source.poll(now: now), now: now)
            store.tick(now: now)
            store.agents.compactMap(\.stage).forEach { seen.insert($0) }
            shipped = shipped || store.agents.contains { $0.shipCount > 0 }
        }
        XCTAssertEqual(store.agents.filter { !$0.isSubagent }.count, 5)
        XCTAssertEqual(seen, Set(Stage.allCases))
        XCTAssertTrue(shipped)
    }

    func testReplayKeepsOriginalPacing() throws {
        func line(_ seconds: Int, _ payload: String) -> String {
            #"{"timestamp":"2026-01-01T00:00:\#(String(format: "%02d", seconds)).000Z","type":"response_item","payload":\#(payload)}"# + "\n"
        }
        let url = try write(
            line(0, #"{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"rg x\"}"}"#)
                + line(20, #"{"type":"custom_tool_call","name":"apply_patch"}"#),
            to: "rollout.jsonl")
        let source = ReplaySource(url: url, speed: 10)
        let store = FloorStore()

        store.ingest(source.poll(now: t0), now: t0)
        XCTAssertEqual(store.agents.first?.source, .codex)
        XCTAssertEqual(store.agents.first?.stage, .research)

        store.ingest(source.poll(now: t0.addingTimeInterval(1)), now: t0.addingTimeInterval(1))
        XCTAssertEqual(store.agents.first?.status, "Reading the code…", "20s at 10× is not due after 1s")

        store.ingest(source.poll(now: t0.addingTimeInterval(2.5)), now: t0.addingTimeInterval(2.5))
        XCTAssertEqual(store.agents.first?.isWorking, false, "replay ends by handing back")
        XCTAssertTrue(store.agents.first?.recent.contains("Applying a patch…") ?? false)
    }
}
