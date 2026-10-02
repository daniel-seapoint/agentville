import Foundation
import Observation

/// Folds the event stream from every source into the list of agents the UI draws.
@Observable
public final class FloorStore {
    public private(set) var agents: [AgentSnapshot] = []

    /// How long a new stage must hold before the robot walks to it. Stops robots
    /// ping-ponging between stations on Read → Edit → Read sequences.
    public var dwell: TimeInterval = 1.5

    private var nextColor = 0
    private let recentLimit = 8

    public init() {}

    public var workingCount: Int { agents.filter { $0.isWorking && !$0.isSubagent }.count }

    public func agent(_ id: String) -> AgentSnapshot? { agents.first { $0.id == id } }

    /// Forgets every agent, as if the app had just launched.
    public func reset() {
        agents.removeAll()
        nextColor = 0
    }

    public func ingest(_ events: [AgentEvent], now: Date) {
        for event in events { apply(event, now: now) }
    }

    /// Promotes stage changes that have held for `dwell`.
    public func tick(now: Date) {
        for index in agents.indices {
            guard let pending = agents[index].pendingStage,
                  let since = agents[index].pendingSince,
                  now.timeIntervalSince(since) >= dwell else { continue }
            agents[index].stage = pending
            agents[index].pendingStage = nil
            agents[index].pendingSince = nil
        }
    }

    private func apply(_ event: AgentEvent, now: Date) {
        if case let .appeared(source, title, cwd, parent) = event.kind {
            if let index = agents.firstIndex(where: { $0.id == event.agentID }) {
                if !title.isEmpty { agents[index].title = title }
                if !cwd.isEmpty { agents[index].cwd = cwd }
                return
            }
            let color: Int
            if let parent, let parentAgent = agent(parent) {
                color = parentAgent.colorIndex
            } else {
                color = nextColor
                nextColor += 1
            }
            agents.append(AgentSnapshot(
                id: event.agentID, source: source, title: title, cwd: cwd, parentID: parent,
                stage: nil, status: "Waiting for you", isWorking: false, recent: [],
                shipCount: 0, colorIndex: color, lastActivity: now))
            return
        }

        guard let index = agents.firstIndex(where: { $0.id == event.agentID }) else { return }

        switch event.kind {
        case .appeared:
            break

        case .titled(let title):
            if !title.isEmpty { agents[index].title = title }

        case .turnStarted:
            if !agents[index].isWorking {
                agents[index].isWorking = true
                agents[index].status = "Thinking…"
            }
            agents[index].lastActivity = now

        case let .activity(stage, status, ship):
            if event.isBacklog {
                // History only fills in where a busy agent currently is.
                guard agents[index].isWorking else { return }
            } else {
                agents[index].isWorking = true
                if ship { agents[index].shipCount += 1 }
            }
            agents[index].status = status
            agents[index].lastActivity = now
            if agents[index].recent.last != status {
                agents[index].recent.append(status)
                if agents[index].recent.count > recentLimit { agents[index].recent.removeFirst() }
            }
            guard let stage else { return }
            if agents[index].stage == nil {
                agents[index].stage = stage
                agents[index].pendingStage = nil
                agents[index].pendingSince = nil
            } else if agents[index].stage == stage {
                agents[index].pendingStage = nil
                agents[index].pendingSince = nil
            } else if agents[index].pendingStage != stage {
                agents[index].pendingStage = stage
                agents[index].pendingSince = now
            }

        case .turnEnded:
            agents[index].isWorking = false
            agents[index].stage = nil
            agents[index].pendingStage = nil
            agents[index].pendingSince = nil
            agents[index].status = agents[index].isSubagent ? "Done" : "Waiting for you"
            agents[index].lastActivity = now

        case .gone:
            let id = event.agentID
            agents.removeAll { $0.id == id || $0.parentID == id }
        }
    }
}
