import XCTest
@testable import AgentvilleCore

final class StageClassifierTests: XCTestCase {
    func testClaudeTools() {
        XCTAssertEqual(StageClassifier.claude(tool: "Read", input: ["file_path": "/a/b/App.swift"]),
                       Classification(stage: .research, status: "Reading App.swift…"))
        XCTAssertEqual(StageClassifier.claude(tool: "Grep", input: [:]).stage, .research)
        XCTAssertEqual(StageClassifier.claude(tool: "WebSearch", input: [:]).stage, .research)
        XCTAssertEqual(StageClassifier.claude(tool: "Edit", input: ["file_path": "/a/Model.swift"]),
                       Classification(stage: .build, status: "Editing Model.swift…"))
        XCTAssertEqual(StageClassifier.claude(tool: "Write", input: ["file_path": "/Users/x/.claude/plans/p.md"]).stage, .plan)
        XCTAssertEqual(StageClassifier.claude(tool: "ExitPlanMode", input: [:]).stage, .plan)
        XCTAssertEqual(StageClassifier.claude(tool: "Agent", input: ["subagent_type": "Explore"]).stage, .research)
        XCTAssertEqual(StageClassifier.claude(tool: "Skill", input: ["skill": "code-review"]).stage, .review)
        XCTAssertEqual(StageClassifier.claude(tool: "mcp__notion__search", input: [:]),
                       Classification(stage: nil, status: "Using notion…"))
    }

    func testClaudeBashUsesDescriptionOnlyWhenUnclassified() {
        let unknown = StageClassifier.claude(tool: "Bash", input: ["command": "open .", "description": "Open the folder"])
        XCTAssertEqual(unknown, Classification(stage: nil, status: "Open the folder…"))
        let tests = StageClassifier.claude(tool: "Bash", input: ["command": "swift test", "description": "Run it"])
        XCTAssertEqual(tests, Classification(stage: .verify, status: "Running tests…"))
    }

    func testCodexTools() {
        XCTAssertEqual(StageClassifier.codex(tool: "exec_command", command: "rg -n TODO src").stage, .research)
        XCTAssertEqual(StageClassifier.codex(tool: "apply_patch", command: nil).stage, .build)
        XCTAssertEqual(StageClassifier.codex(tool: "update_plan", command: nil).stage, .plan)
        XCTAssertNil(StageClassifier.codex(tool: "view_image", command: nil).stage)
    }

    func testCopilotTools() {
        XCTAssertEqual(StageClassifier.copilot(tool: "glob", arguments: [:]).stage, .research)
        XCTAssertEqual(StageClassifier.copilot(tool: "create", arguments: ["path": "/r/New.swift"]),
                       Classification(stage: .build, status: "Editing New.swift…"))
        XCTAssertEqual(StageClassifier.copilot(tool: "bash", arguments: ["command": "git push"]).stage, .ship)
        XCTAssertEqual(StageClassifier.copilot(tool: "bash", arguments: ["command": "open .", "description": "Open the folder"]),
                       Classification(stage: nil, status: "Open the folder…"))
        XCTAssertEqual(StageClassifier.copilot(tool: "update_todo", arguments: [:]).stage, .plan)
        XCTAssertEqual(StageClassifier.copilot(tool: "report_intent", arguments: [:]).status, "Thinking…")
    }

    func testShellVerify() {
        XCTAssertEqual(StageClassifier.shell("swift test"), Classification(stage: .verify, status: "Running tests…"))
        XCTAssertEqual(StageClassifier.shell("npm run lint").status, "Linting…")
        XCTAssertEqual(StageClassifier.shell("npx tsc --noEmit").status, "Typechecking…")
        XCTAssertEqual(StageClassifier.shell("xcodebuild -scheme App build").status, "Building…")
        XCTAssertEqual(StageClassifier.shell("xcodebuild test -scheme App").status, "Running tests…")
        XCTAssertEqual(StageClassifier.shell("CI=1 pnpm test").stage, .verify)
        XCTAssertEqual(StageClassifier.shell("python3 -m pytest -q").stage, .verify)
        XCTAssertNil(StageClassifier.shell("npm install").stage)
    }

    func testShellReviewAndShip() {
        XCTAssertEqual(StageClassifier.shell("git status --short").stage, .review)
        XCTAssertEqual(StageClassifier.shell("git -C /repo diff HEAD~1").stage, .review)
        XCTAssertEqual(StageClassifier.shell("gh pr view 12").stage, .review)
        XCTAssertEqual(StageClassifier.shell("git commit -m 'x'"), Classification(stage: .ship, status: "Committing…", ship: true))
        XCTAssertEqual(StageClassifier.shell("git push origin main").stage, .ship)
        XCTAssertEqual(StageClassifier.shell("gh pr create --fill").status, "Opening a pull request…")
        XCTAssertNil(StageClassifier.shell("git checkout -b feature").stage)
    }

    func testShellResearch() {
        XCTAssertEqual(StageClassifier.shell("cat README.md").stage, .research)
        XCTAssertEqual(StageClassifier.shell("sed -n '1,40p' file.swift").stage, .research)
        XCTAssertEqual(StageClassifier.shell("sed -i '' 's/a/b/' file.swift").stage, .build)
        XCTAssertEqual(StageClassifier.shell("echo 'git push'"), Classification(stage: nil, status: "Running echo…"))
    }

    func testCompoundCommandsTakeTheMostSignificantPart() {
        XCTAssertEqual(StageClassifier.shell("cd app && git diff | head -50").stage, .review)
        XCTAssertEqual(StageClassifier.shell("swift build 2>&1 | tail -20").stage, .verify)
        XCTAssertEqual(StageClassifier.shell("git add -A && git commit -m wip && git status").stage, .ship)
        XCTAssertEqual(StageClassifier.shell("ls; npm test").stage, .verify)
    }

    func testEmptyCommand() {
        XCTAssertEqual(StageClassifier.shell(""), Classification(stage: nil, status: "Running a command…"))
    }
}
