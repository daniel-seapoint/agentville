import Foundation

/// Scripted fake agents that loop through every station. Used by `--demo` to check the
/// floor's look and motion without needing live sessions.
public final class DemoSource: AgentEventSource {
    private struct Step {
        var duration: TimeInterval
        var events: [AgentEvent]
    }

    private struct Actor {
        var steps: [Step]
        var offset: TimeInterval
        var emitted = -1
    }

    private var actors: [Actor] = []
    private var intro: [AgentEvent] = []
    private var start: Date?

    /// - Parameter idle: the cast turns up but nobody does any work.
    public init(idle: Bool = false) {
        let cast: [(String, AgentSource, String)] = [
            ("demo:1", .claude, "Fix mobile nav overflow"),
            ("demo:2", .codex, "Fix flaky e2e: invoice export"),
            ("demo:3", .copilot, "Read mobile breakpoints"),
            ("demo:4", .codex, "Add CSV export"),
            ("demo:5", .copilot, "Review PR #11834"),
        ]
        for (index, (id, source, title)) in cast.enumerated() {
            intro.append(AgentEvent(id, .appeared(source: source, title: title, cwd: "/tmp/demo", parent: nil)))
            let scout = "\(id)/scout"
            func act(_ stage: Stage?, _ status: String, ship: Bool = false) -> AgentEvent {
                AgentEvent(id, .activity(stage: stage, status: status, ship: ship))
            }
            var research = [act(.research, "Reading the code…")]
            var build = [act(.build, "Implementing the plan…")]
            if index == 0 {
                // One agent brings a subagent along while it researches.
                research += [
                    AgentEvent(scout, .appeared(source: .claude, title: "Find breakpoints", cwd: "", parent: id)),
                    AgentEvent(scout, .activity(stage: .research, status: "Searching the code…", ship: false)),
                ]
                build.append(AgentEvent(scout, .gone))
            }
            let steps = [
                Step(duration: 5, events: [act(.plan, "Planning with architect…")]),
                Step(duration: 5, events: research),
                Step(duration: 6, events: build),
                Step(duration: 5, events: [act(.verify, "Typecheck, lint & tests…")]),
                Step(duration: 4, events: [act(.review, "Reviewing changes…")]),
                Step(duration: 4, events: [act(.ship, "Submitting the stack…", ship: true)]),
                Step(duration: 5, events: [AgentEvent(id, .turnEnded)]),
            ]
            if !idle { actors.append(Actor(steps: steps, offset: Double(index) * 6.3)) }
        }
    }

    public func poll(now: Date) -> [AgentEvent] {
        var out: [AgentEvent] = []
        if start == nil {
            start = now
            out = intro
        }
        let elapsed = now.timeIntervalSince(start!)

        for index in actors.indices {
            let steps = actors[index].steps
            let cycle = steps.reduce(0) { $0 + $1.duration }
            let time = elapsed + actors[index].offset
            var position = time.truncatingRemainder(dividingBy: cycle)
            var stepIndex = 0
            while position >= steps[stepIndex].duration {
                position -= steps[stepIndex].duration
                stepIndex += 1
            }
            let counter = Int(time / cycle) * steps.count + stepIndex
            // Jump straight to the current step rather than replaying everything in between.
            if counter > actors[index].emitted {
                actors[index].emitted = counter
                out.append(contentsOf: steps[stepIndex].events)
            }
        }
        return out
    }
}
