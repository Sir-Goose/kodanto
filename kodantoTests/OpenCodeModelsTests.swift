import XCTest
@testable import kodanto

@MainActor
final class OpenCodeModelsTests: XCTestCase {
    func testToolPartDecodesCommandFromStateInput() throws {
        let data = Data(
            #"""
            {
              "id": "part-1",
              "sessionID": "session-1",
              "messageID": "message-1",
              "type": "tool",
              "callID": "call-1",
              "tool": "bash",
              "state": {
                "status": "completed",
                "input": {
                  "command": "git status",
                  "description": "Show repository status"
                },
                "title": "Shows working tree status",
                "output": "On branch main",
                "metadata": {},
                "time": {
                  "start": 1,
                  "end": 2
                }
              }
            }
            """#.utf8
        )

        let part = try JSONDecoder().decode(OpenCodePart.self, from: data)

        guard case .tool(let tool) = part else {
            return XCTFail("Expected tool part")
        }

        XCTAssertEqual(tool.command, "git status")
        XCTAssertEqual(tool.displayTitle, "Shows working tree status")
        XCTAssertEqual(part.summary, "Shows working tree status")
    }
}
