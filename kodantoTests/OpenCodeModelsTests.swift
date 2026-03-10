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

    func testConfigProvidersDecodeModelVariants() throws {
        let data = Data(
            #"""
            {
              "providers": [
                {
                  "id": "openai",
                  "name": "OpenAI",
                  "models": {
                    "gpt-5": {
                      "id": "gpt-5",
                      "name": "GPT-5",
                      "variants": {
                        "minimal": {},
                        "high": {},
                        "xhigh": {}
                      }
                    }
                  }
                }
              ],
              "default": {
                "openai": "gpt-5"
              }
            }
            """#.utf8
        )

        let response = try JSONDecoder().decode(OpenCodeConfigProviders.self, from: data)
        let model = try XCTUnwrap(response.providers.first?.models["gpt-5"])

        XCTAssertEqual(Set(model.variants.map { Array($0.keys) } ?? []), ["minimal", "high", "xhigh"])
    }

    func testPromptRequestBodyEncodesVariant() throws {
        let body = PromptRequestBody(
            model: .init(providerID: "openai", modelID: "gpt-5"),
            variant: "high",
            parts: [.init(type: "text", text: "Hello")]
        )

        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let model = try XCTUnwrap(json["model"] as? [String: String])

        XCTAssertEqual(model["providerID"], "openai")
        XCTAssertEqual(model["modelID"], "gpt-5")
        XCTAssertEqual(json["variant"] as? String, "high")
    }
}
