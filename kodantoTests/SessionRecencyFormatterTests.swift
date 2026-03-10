import XCTest
@testable import kodanto

final class SessionRecencyFormatterTests: XCTestCase {
    func testFormatterUsesMinutesBelowOneHour() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(SessionRecencyFormatter.string(since: 10_000, now: now), "0m")
        XCTAssertEqual(SessionRecencyFormatter.string(since: 10_000 - 59 * 60, now: now), "59m")
    }

    func testFormatterRollsUpToHoursDaysAndWeeks() {
        let now = Date(timeIntervalSince1970: 50_000)

        XCTAssertEqual(SessionRecencyFormatter.string(since: 50_000 - 60 * 60, now: now), "1h")
        XCTAssertEqual(SessionRecencyFormatter.string(since: 50_000 - 23 * 60 * 60, now: now), "23h")
        XCTAssertEqual(SessionRecencyFormatter.string(since: 50_000 - 24 * 60 * 60, now: now), "1d")
        XCTAssertEqual(SessionRecencyFormatter.string(since: 50_000 - 6 * 24 * 60 * 60, now: now), "6d")
        XCTAssertEqual(SessionRecencyFormatter.string(since: 50_000 - 7 * 24 * 60 * 60, now: now), "1w")
        XCTAssertEqual(SessionRecencyFormatter.string(since: 50_000 - 15 * 24 * 60 * 60, now: now), "2w")
    }

    func testFormatterAcceptsMillisecondTimestamps() {
        let now = Date(timeIntervalSince1970: 20_000)
        let ninetyMinutesAgoMilliseconds = Double((20_000 - 90 * 60) * 1000)

        XCTAssertEqual(SessionRecencyFormatter.string(since: ninetyMinutesAgoMilliseconds, now: now), "1h")
    }

    func testFormatterClampsFutureTimestampsToZeroMinutes() {
        let now = Date(timeIntervalSince1970: 30_000)

        XCTAssertEqual(SessionRecencyFormatter.string(since: 30_000 + 5 * 60, now: now), "0m")
    }
}
