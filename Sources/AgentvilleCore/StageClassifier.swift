import Foundation

public struct Classification: Equatable {
    public var stage: Stage?
    public var status: String
    public var ship: Bool

    public init(stage: Stage?, status: String, ship: Bool = false) {
        self.stage = stage
        self.status = status
        self.ship = ship
    }
}

/// Infers which station a tool call belongs to. Sessions never announce a stage,
/// so this is a heuristic over tool names and shell commands.
public enum StageClassifier {

    // MARK: Claude Code

    public static func claude(tool: String, input: [String: Any]) -> Classification {
        let file = (input["file_path"] as? String ?? input["notebook_path"] as? String)
            .map { ($0 as NSString).lastPathComponent }

        switch tool {
        case "Read":
            return .init(stage: .research, status: file.map { "Reading \($0)…" } ?? "Reading the code…")
        case "Grep", "Glob":
            return .init(stage: .research, status: "Searching the code…")
        case "WebSearch", "WebFetch":
            return .init(stage: .research, status: "Researching the web…")
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            if let path = input["file_path"] as? String, path.contains("/.claude/plans/") {
                return .init(stage: .plan, status: "Writing the plan…")
            }
            return .init(stage: .build, status: file.map { "Editing \($0)…" } ?? "Editing code…")
        case "Bash":
            var result = shell(input["command"] as? String ?? "")
            if result.stage == nil, let description = input["description"] as? String, !description.isEmpty {
                result.status = description.titleLine(limit: 60) + "…"
            }
            return result
        case "EnterPlanMode", "ExitPlanMode", "TodoWrite", "TaskCreate", "TaskUpdate":
            return .init(stage: .plan, status: "Planning…")
        case "Agent", "Task":
            switch input["subagent_type"] as? String {
            case "Explore": return .init(stage: .research, status: "Sending out a scout…")
            case "Plan": return .init(stage: .plan, status: "Planning with an architect…")
            default: return .init(stage: nil, status: "Delegating to a subagent…")
            }
        case "Skill":
            let skill = input["skill"] as? String ?? "a"
            if skill.contains("review") { return .init(stage: .review, status: "Reviewing changes…") }
            return .init(stage: nil, status: "Using the \(skill) skill…")
        case "AskUserQuestion":
            return .init(stage: nil, status: "Asking you a question…")
        default:
            if tool.hasPrefix("mcp__") {
                let server = tool.dropFirst(5).components(separatedBy: "__").first ?? "a tool"
                return .init(stage: nil, status: "Using \(server)…")
            }
            return .init(stage: nil, status: "Using \(tool)…")
        }
    }

    // MARK: Codex

    /// - Parameter command: the shell command for exec-style tools, if any.
    public static func codex(tool: String, command: String?) -> Classification {
        switch tool {
        case "exec_command", "shell", "local_shell", "shell_command":
            return shell(command ?? "")
        case "apply_patch":
            return .init(stage: .build, status: "Applying a patch…")
        case "update_plan":
            return .init(stage: .plan, status: "Updating the plan…")
        case "web_search":
            return .init(stage: .research, status: "Researching the web…")
        default:
            return .init(stage: nil, status: "Using \(tool)…")
        }
    }

    // MARK: Copilot

    public static func copilot(tool: String, arguments: [String: Any]) -> Classification {
        let file = (arguments["path"] as? String).map { ($0 as NSString).lastPathComponent }

        switch tool {
        case "bash", "powershell", "shell":
            var result = shell(arguments["command"] as? String ?? "")
            if result.stage == nil, let description = arguments["description"] as? String, !description.isEmpty {
                result.status = description.titleLine(limit: 60) + "…"
            }
            return result
        case "view", "read":
            return .init(stage: .research, status: file.map { "Reading \($0)…" } ?? "Reading the code…")
        case "grep", "glob", "rg", "search":
            return .init(stage: .research, status: "Searching the code…")
        case "web_fetch", "web_search":
            return .init(stage: .research, status: "Researching the web…")
        case "edit", "create", "write", "str_replace_editor", "apply_patch":
            return .init(stage: .build, status: file.map { "Editing \($0)…" } ?? "Editing code…")
        case "update_todo":
            return .init(stage: .plan, status: "Updating the plan…")
        case "report_intent":
            // Copilot narrates what it is about to do; that reads better than a tool name.
            let intent = (arguments["intent"] as? String)?.titleLine(limit: 60) ?? ""
            return .init(stage: nil, status: intent.isEmpty ? "Thinking…" : intent + "…")
        case "task":
            return .init(stage: nil, status: "Delegating to a subagent…")
        default:
            return .init(stage: nil, status: "Using \(tool)…")
        }
    }

    // MARK: Shell

    private static let researchCommands: Set<String> = [
        "rg", "grep", "cat", "ls", "find", "fd", "head", "tail", "wc", "tree", "sed", "awk",
        "jq", "less", "bat", "stat", "file", "which", "nl",
    ]
    private static let verifyCommands: Set<String> = [
        "xcodebuild", "tsc", "eslint", "jest", "vitest", "pytest", "mypy", "ruff", "flake8",
        "rspec", "phpunit", "swiftlint", "prettier", "biome", "tox", "ctest", "gradle",
        "./gradlew", "mvn", "make", "playwright",
    ]
    private static let packageRunners: Set<String> = ["npm", "pnpm", "yarn", "bun", "npx", "bunx", "pnpx"]
    private static let verifyKeywords = ["test", "lint", "typecheck", "type-check", "tsc", "build", "check", "clippy", "vet"]

    /// Classifies a shell command line. Compound commands (`&&`, `;`, `|`) are split and the
    /// most significant part wins: ship > verify > review > research.
    public static func shell(_ command: String) -> Classification {
        var best: Classification?
        var bestRank = -1
        for segment in segments(of: command) {
            guard let found = classify(words: segment) else { continue }
            let rank: Int
            switch found.stage {
            case .ship: rank = 4
            case .verify: rank = 3
            case .review: rank = 2
            case .research: rank = 1
            default: rank = 0
            }
            if rank > bestRank {
                best = found
                bestRank = rank
            }
        }
        if let best { return best }
        let first = segments(of: command).first?.first.map { ($0 as NSString).lastPathComponent }
        return .init(stage: nil, status: first.map { "Running \($0)…" } ?? "Running a command…")
    }

    /// Splits a command line into word lists, one per pipeline/sequence segment, with leading
    /// `VAR=value` assignments and `sudo`/`time`/`env` wrappers removed.
    static func segments(of command: String) -> [[String]] {
        var normalised = command
        for separator in ["&&", "||", ";", "|", "\n"] {
            normalised = normalised.replacingOccurrences(of: separator, with: "\u{1F}")
        }
        return normalised.split(separator: "\u{1F}").compactMap { raw in
            var words = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            while let first = words.first,
                  first == "sudo" || first == "time" || first == "env" || first == "command"
                    || (first.contains("=") && !first.hasPrefix("-") && !first.hasPrefix("=")) {
                words.removeFirst()
            }
            return words.isEmpty ? nil : words
        }
    }

    private static func classify(words: [String]) -> Classification? {
        let head = words[0]
        let rest = Array(words.dropFirst())
        let joined = rest.joined(separator: " ")

        switch head {
        case "git":
            switch gitSubcommand(rest) {
            case "commit": return .init(stage: .ship, status: "Committing…", ship: true)
            case "push": return .init(stage: .ship, status: "Pushing…", ship: true)
            case "diff", "status", "log", "show", "blame":
                return .init(stage: .review, status: "Reviewing changes…")
            default: return nil
            }
        case "gh":
            guard rest.first == "pr", rest.count > 1 else { return nil }
            switch rest[1] {
            case "create": return .init(stage: .ship, status: "Opening a pull request…", ship: true)
            case "merge": return .init(stage: .ship, status: "Merging the pull request…", ship: true)
            case "view", "diff", "checks", "list", "status":
                return .init(stage: .review, status: "Reviewing the pull request…")
            default: return nil
            }
        case "swift":
            guard let sub = rest.first, sub == "test" || sub == "build" else { return nil }
            return verify(sub)
        case "cargo", "go":
            guard let sub = rest.first,
                  ["test", "build", "check", "clippy", "vet", "fmt"].contains(sub) else { return nil }
            return verify(sub)
        case "python", "python3":
            return joined.contains("pytest") || joined.contains("unittest") ? verify("test") : nil
        default:
            break
        }

        if packageRunners.contains(head) {
            guard let keyword = verifyKeywords.first(where: { joined.contains($0) })
                    ?? rest.first(where: { verifyCommands.contains($0) }) else { return nil }
            return verify(keyword)
        }
        if verifyCommands.contains(head) {
            return verify(head == "make" || head == "xcodebuild" ? joined + " build" : head)
        }
        if researchCommands.contains(head) {
            // `sed -i` rewrites files; only the read-only form counts as research.
            if head == "sed" && rest.contains(where: { $0.hasPrefix("-i") }) {
                return .init(stage: .build, status: "Editing code…")
            }
            return .init(stage: .research, status: "Reading the code…")
        }
        return nil
    }

    /// First non-option word after `git`, skipping `-C <path>` / `-c <key=value>`.
    private static func gitSubcommand(_ words: [String]) -> String? {
        var index = 0
        while index < words.count {
            let word = words[index]
            if word == "-C" || word == "-c" {
                index += 2
            } else if word.hasPrefix("-") {
                index += 1
            } else {
                return word
            }
        }
        return nil
    }

    private static func verify(_ hint: String) -> Classification {
        let status: String
        if hint.contains("test") || ["jest", "vitest", "pytest", "rspec", "phpunit", "tox", "ctest", "playwright"].contains(hint) {
            status = "Running tests…"
        } else if hint.contains("lint") || ["ruff", "flake8", "clippy", "vet", "prettier", "biome", "fmt"].contains(hint) {
            status = "Linting…"
        } else if hint.contains("type") || hint == "tsc" || hint == "mypy" || hint == "check" {
            status = "Typechecking…"
        } else {
            status = "Building…"
        }
        return .init(stage: .verify, status: status)
    }
}
