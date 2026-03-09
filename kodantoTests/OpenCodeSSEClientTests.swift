import XCTest
@testable import kodanto

final class OpenCodeSSEClientTests: XCTestCase {
    func testParserYieldsSingleLineEventsWithoutBlankSeparators() throws {
        var parser = OpenCodeSSEClient.EventParser()

        let connected = try parser.push(line: "data: {\"payload\":{\"type\":\"server.connected\",\"properties\":{}}}")
        let heartbeat = try parser.push(line: "data: {\"payload\":{\"type\":\"server.heartbeat\",\"properties\":{}}}")

        XCTAssertEqual(connected.count, 1)
        XCTAssertEqual(heartbeat.count, 1)
        XCTAssertTrue(connected.first?.payload.isServerConnected == true)
        XCTAssertTrue(heartbeat.first?.payload.isServerHeartbeat == true)
    }

    func testParserFlushesEventOnBlankLine() throws {
        var parser = OpenCodeSSEClient.EventParser()

        let pending = try parser.push(line: "data: {\"payload\":{\"type\":\"server.connected\",\"properties\":{}}}")
        let flushed = try parser.push(line: "")

        XCTAssertEqual(pending.count, 1)
        XCTAssertTrue(flushed.isEmpty)
    }
}

private extension OpenCodeEvent {
    var isServerConnected: Bool {
        if case .serverConnected = self {
            return true
        }
        return false
    }

    var isServerHeartbeat: Bool {
        if case .serverHeartbeat = self {
            return true
        }
        return false
    }
}
