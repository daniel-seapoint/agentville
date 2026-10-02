import XCTest
@testable import AgentvilleCore

final class FloorStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func makeStore() -> FloorStore {
        let store = FloorStore()
        store.ingest([AgentEvent("a", .appeared(source: .claude, title: "Task", cwd: "/repo", parent: nil))], now: t0)
        return store
    }

    private func activity(_ stage: Stage?, _ status: String = "s", ship: Bool = false, backlog: Bool = false) -> AgentEvent {
        AgentEvent("a", .activity(stage: stage, status: status, ship: ship), isBacklog: backlog)
    }

    func testNewAgentStartsIdleInTheLounge() {
        let agent = makeStore().agent("a")!
        XCTAssertFalse(agent.isWorking)
        XCTAssertNil(agent.stage)
        XCTAssertEqual(agent.status, "Waiting for you")
    }

    func testFirstStageAppliesImmediately() {
        let store = makeStore()
        store.ingest([activity(.research, "Reading…")], now: t0)
        XCTAssertEqual(store.agent("a")?.stage, .research)
        XCTAssertEqual(store.agent("a")?.isWorking, true)
        XCTAssertEqual(store.workingCount, 1)
    }

    func testStageChangeWaitsForDwell() {
        let store = makeStore()
        store.ingest([activity(.research)], now: t0)
        store.ingest([activity(.build, "Editing…")], now: t0.addingTimeInterval(1))
        XCTAssertEqual(store.agent("a")?.stage, .research, "agent stays put during the dwell")
        XCTAssertEqual(store.agent("a")?.status, "Editing…", "status updates straight away")

        store.tick(now: t0.addingTimeInterval(2))
        XCTAssertEqual(store.agent("a")?.stage, .research)
        store.tick(now: t0.addingTimeInterval(2.6))
        XCTAssertEqual(store.agent("a")?.stage, .build)
    }

    func testBouncingBackCancelsThePendingMove() {
        let store = makeStore()
        store.ingest([activity(.research)], now: t0)
        store.ingest([activity(.build)], now: t0.addingTimeInterval(1))
        store.ingest([activity(.research)], now: t0.addingTimeInterval(1.5))
        store.tick(now: t0.addingTimeInterval(10))
        XCTAssertEqual(store.agent("a")?.stage, .research)
    }

    func testUnclassifiedActivityKeepsTheStage() {
        let store = makeStore()
        store.ingest([activity(.build), activity(nil, "Using a tool…")], now: t0)
        store.tick(now: t0.addingTimeInterval(5))
        XCTAssertEqual(store.agent("a")?.stage, .build)
        XCTAssertEqual(store.agent("a")?.status, "Using a tool…")
    }

    func testTurnEndSendsAgentToTheLounge() {
        let store = makeStore()
        store.ingest([activity(.build), AgentEvent("a", .turnEnded)], now: t0)
        XCTAssertEqual(store.agent("a")?.isWorking, false)
        XCTAssertNil(store.agent("a")?.stage)
        XCTAssertEqual(store.workingCount, 0)
    }

    func testShipCountsLiveEventsOnly() {
        let store = makeStore()
        store.ingest([AgentEvent("a", .turnStarted), activity(.ship, ship: true, backlog: true)], now: t0)
        XCTAssertEqual(store.agent("a")?.shipCount, 0)
        store.ingest([activity(.ship, ship: true)], now: t0)
        XCTAssertEqual(store.agent("a")?.shipCount, 1)
    }

    func testBacklogDoesNotWakeAnIdleAgent() {
        let store = makeStore()
        store.ingest([activity(.build, backlog: true)], now: t0)
        XCTAssertEqual(store.agent("a")?.isWorking, false)
        XCTAssertNil(store.agent("a")?.stage)
    }

    func testSubagentsShareColourAndLeaveWithTheirParent() {
        let store = makeStore()
        store.ingest([
            AgentEvent("b", .appeared(source: .codex, title: "Other", cwd: "", parent: nil)),
            AgentEvent("a/sub", .appeared(source: .claude, title: "Scout", cwd: "", parent: "a")),
            AgentEvent("a/sub", .turnStarted),
        ], now: t0)
        XCTAssertEqual(store.agent("a/sub")?.colorIndex, store.agent("a")?.colorIndex)
        XCTAssertNotEqual(store.agent("b")?.colorIndex, store.agent("a")?.colorIndex)
        XCTAssertEqual(store.workingCount, 0, "subagents are not counted")

        store.ingest([AgentEvent("a", .gone)], now: t0)
        XCTAssertEqual(store.agents.map(\.id), ["b"])
    }

    func testResetClearsAgentsAndRestartsColours() {
        let store = makeStore()
        store.ingest([AgentEvent("b", .appeared(source: .codex, title: "Other", cwd: "", parent: nil))], now: t0)
        store.reset()
        XCTAssertTrue(store.agents.isEmpty)
        store.ingest([AgentEvent("c", .appeared(source: .claude, title: "New", cwd: "", parent: nil))], now: t0)
        XCTAssertEqual(store.agent("c")?.colorIndex, 0)
    }

    func testEventsForUnknownAgentsAreIgnored() {
        let store = FloorStore()
        store.ingest([AgentEvent("ghost", .turnStarted), AgentEvent("ghost", .gone)], now: t0)
        XCTAssertTrue(store.agents.isEmpty)
    }

    func testRecentIsCappedAndDeduplicated() {
        let store = makeStore()
        store.ingest((0..<20).flatMap { [activity(nil, "step \($0)"), activity(nil, "step \($0)")] }, now: t0)
        XCTAssertEqual(store.agent("a")?.recent.count, 8)
        XCTAssertEqual(store.agent("a")?.recent.last, "step 19")
    }
}
