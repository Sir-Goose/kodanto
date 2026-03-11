import XCTest
@testable import kodanto

final class OpenCodeSSEClientEventParserTests: XCTestCase {
    func testPushIgnoresCommentsAndUnknownLines() throws {
        var parser = OpenCodeSSEClient.EventParser()

        XCTAssertTrue(try parser.push(line: ": keepalive").isEmpty)
        XCTAssertTrue(try parser.push(line: "event: server.connected").isEmpty)
        XCTAssertTrue(try parser.finish().isEmpty)
    }

    func testPushParsesCompleteEventWithoutBlankLine() throws {
        var parser = OpenCodeSSEClient.EventParser()

        let events = try parser.push(line: #"data: {"directory":"/tmp/project","payload":{"type":"server.connected"}}"#)

        XCTAssertEqual(events.count, 1)
        assertServerConnected(events[0], directory: "/tmp/project")
        XCTAssertTrue(try parser.push(line: "").isEmpty)
    }

    func testPushParsesMultilineEventWhenSecondLineCompletesJSON() throws {
        var parser = OpenCodeSSEClient.EventParser()

        XCTAssertTrue(try parser.push(line: #"data: {"directory":"/tmp/project","payload":"#).isEmpty)
        let events = try parser.push(line: #"data: {"type":"server.connected"}}"#)

        XCTAssertEqual(events.count, 1)
        assertServerConnected(events[0], directory: "/tmp/project")
    }

    func testFinishThrowsWhenIncompletePayloadRemainsBuffered() throws {
        var parser = OpenCodeSSEClient.EventParser()
        XCTAssertTrue(try parser.push(line: #"data: {"directory":"/tmp/project","payload":"#).isEmpty)

        XCTAssertThrowsError(try parser.finish())
    }

    private func assertServerConnected(_ event: OpenCodeGlobalEvent, directory: String?) {
        XCTAssertEqual(event.directory, directory)
        guard case .serverConnected = event.payload else {
            XCTFail("Expected server.connected payload")
            return
        }
    }
}
