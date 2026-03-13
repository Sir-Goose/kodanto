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

    func testPushParsesPTYEvents() throws {
        var parser = OpenCodeSSEClient.EventParser()

        let createdEvents = try parser.push(line: #"data: {"directory":"/tmp/project","payload":{"type":"pty.created","properties":{"info":{"id":"pty-1","title":"Terminal","command":"zsh","args":[],"cwd":"/tmp/project","status":"running","pid":123}}}}"#)
        XCTAssertEqual(createdEvents.count, 1)
        guard case .ptyCreated(let payload) = createdEvents[0].payload else {
            XCTFail("Expected pty.created payload")
            return
        }
        XCTAssertEqual(payload.info.id, "pty-1")
        XCTAssertEqual(payload.info.status, .running)

        let exitedEvents = try parser.push(line: #"data: {"directory":"/tmp/project","payload":{"type":"pty.exited","properties":{"id":"pty-1","exitCode":0}}}"#)
        XCTAssertEqual(exitedEvents.count, 1)
        guard case .ptyExited(let exitedPayload) = exitedEvents[0].payload else {
            XCTFail("Expected pty.exited payload")
            return
        }
        XCTAssertEqual(exitedPayload.id, "pty-1")
        XCTAssertEqual(exitedPayload.exitCode, 0)
    }

    private func assertServerConnected(_ event: OpenCodeGlobalEvent, directory: String?) {
        XCTAssertEqual(event.directory, directory)
        guard case .serverConnected = event.payload else {
            XCTFail("Expected server.connected payload")
            return
        }
    }
}

final class WindowDoubleClickBehaviorTests: XCTestCase {
    func testPreferenceResolverMapsMinimizeSetting() {
        let action = WindowDoubleClickPreferenceResolver.resolve(
            actionOnDoubleClickValue: "Minimize",
            legacyMiniaturize: nil
        )

        XCTAssertEqual(action, .minimize)
    }

    func testPreferenceResolverMapsNoneSetting() {
        let action = WindowDoubleClickPreferenceResolver.resolve(
            actionOnDoubleClickValue: "None",
            legacyMiniaturize: nil
        )

        XCTAssertEqual(action, .none)
    }

    func testPreferenceResolverTreatsMaximizeAsZoom() {
        let action = WindowDoubleClickPreferenceResolver.resolve(
            actionOnDoubleClickValue: "Maximize",
            legacyMiniaturize: nil
        )

        XCTAssertEqual(action, .zoom)
    }

    func testPreferenceResolverFallsBackToLegacyMiniaturizeTrue() {
        let action = WindowDoubleClickPreferenceResolver.resolve(
            actionOnDoubleClickValue: nil,
            legacyMiniaturize: true
        )

        XCTAssertEqual(action, .minimize)
    }

    func testPreferenceResolverFallsBackToLegacyMiniaturizeFalse() {
        let action = WindowDoubleClickPreferenceResolver.resolve(
            actionOnDoubleClickValue: nil,
            legacyMiniaturize: false
        )

        XCTAssertEqual(action, .zoom)
    }

    func testPreferenceResolverDefaultsToZoomWhenMissing() {
        let action = WindowDoubleClickPreferenceResolver.resolve(
            actionOnDoubleClickValue: nil,
            legacyMiniaturize: nil
        )

        XCTAssertEqual(action, .zoom)
    }

    func testTopChromeHitIsTrueAtBoundaryAndAbove() {
        XCTAssertTrue(WindowDoubleClickBehavior.isTopChromeHit(locationInWindowY: 100, contentLayoutMaxY: 100))
        XCTAssertTrue(WindowDoubleClickBehavior.isTopChromeHit(locationInWindowY: 101, contentLayoutMaxY: 100))
    }

    func testTopChromeHitIsFalseBelowBoundary() {
        XCTAssertFalse(WindowDoubleClickBehavior.isTopChromeHit(locationInWindowY: 99, contentLayoutMaxY: 100))
    }
}
