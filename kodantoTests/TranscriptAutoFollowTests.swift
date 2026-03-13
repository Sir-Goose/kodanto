import XCTest
@testable import kodanto

final class TranscriptAutoFollowTests: XCTestCase {
    func testNearBottomIsTrueWithinThreshold() {
        XCTAssertTrue(
            TranscriptAutoFollow.isNearBottom(
                viewportBottom: 880,
                contentBottom: 950
            )
        )
    }

    func testNearBottomIsFalseBeyondThreshold() {
        XCTAssertFalse(
            TranscriptAutoFollow.isNearBottom(
                viewportBottom: 700,
                contentBottom: 900
            )
        )
    }

    func testUserScrollAwayFromBottomDetachesAutoFollow() {
        XCTAssertTrue(
            TranscriptAutoFollow.updatedDetachmentState(
                wasDetachedByUser: false,
                previousDistanceFromBottom: 0,
                newDistanceFromBottom: 24,
                isUserDriven: true
            )
        )
    }

    func testProgrammaticBottomLockDoesNotDetachAutoFollow() {
        XCTAssertFalse(
            TranscriptAutoFollow.updatedDetachmentState(
                wasDetachedByUser: false,
                previousDistanceFromBottom: 0,
                newDistanceFromBottom: 0,
                isUserDriven: false
            )
        )
    }

    func testNonUserUpdatesDoNotClearDetachedAutoFollow() {
        XCTAssertTrue(
            TranscriptAutoFollow.updatedDetachmentState(
                wasDetachedByUser: true,
                previousDistanceFromBottom: 24,
                newDistanceFromBottom: 6,
                isUserDriven: false
            )
        )
    }

    func testUserScrollingTowardBottomDoesNotReattachBeforeExactBottom() {
        XCTAssertTrue(
            TranscriptAutoFollow.updatedDetachmentState(
                wasDetachedByUser: true,
                previousDistanceFromBottom: 24,
                newDistanceFromBottom: 2,
                isUserDriven: true
            )
        )
    }

    func testExactBottomReattachesAutoFollow() {
        XCTAssertFalse(
            TranscriptAutoFollow.updatedDetachmentState(
                wasDetachedByUser: true,
                previousDistanceFromBottom: 2,
                newDistanceFromBottom: 0.5,
                isUserDriven: true
            )
        )
    }

    func testProgrammaticBottomScrollMarkerMatchesWithinTimeout() {
        let marker = TranscriptAutoFollow.ProgrammaticBottomScrollMarker(
            offset: 420,
            timestamp: Date(timeIntervalSinceReferenceDate: 100)
        )

        XCTAssertTrue(
            TranscriptAutoFollow.matchesProgrammaticBottomScroll(
                currentOffset: 421,
                marker: marker,
                now: Date(timeIntervalSinceReferenceDate: 101)
            )
        )
    }

    func testProgrammaticBottomScrollMarkerExpires() {
        let marker = TranscriptAutoFollow.ProgrammaticBottomScrollMarker(
            offset: 420,
            timestamp: Date(timeIntervalSinceReferenceDate: 100)
        )

        XCTAssertFalse(
            TranscriptAutoFollow.matchesProgrammaticBottomScroll(
                currentOffset: 420,
                marker: marker,
                now: Date(timeIntervalSinceReferenceDate: 102)
            )
        )
    }

    func testSettlingWindowKeepsBottomPinnedAfterRunEnds() {
        XCTAssertTrue(
            TranscriptAutoFollow.shouldKeepPinnedToBottom(
                isRunning: false,
                isSettlingAfterRun: true,
                isDetachedByUser: false
            )
        )
    }

    func testDetachedStateDisablesPinnedBottomEvenWhileSettling() {
        XCTAssertFalse(
            TranscriptAutoFollow.shouldKeepPinnedToBottom(
                isRunning: false,
                isSettlingAfterRun: true,
                isDetachedByUser: true
            )
        )
    }

    func testBottomScrollOffsetClampsWhenContentShorterThanViewport() {
        XCTAssertEqual(
            TranscriptAutoFollow.bottomScrollOffset(
                contentHeight: 320,
                viewportHeight: 500
            ),
            0,
            accuracy: 0.001
        )
    }

    func testDistanceFromBottomUsesBottomOffsetMath() {
        XCTAssertEqual(
            TranscriptAutoFollow.distanceFromBottom(
                contentHeight: 1200,
                viewportHeight: 400,
                scrollOffset: 760
            ),
            40,
            accuracy: 0.001
        )
    }

    func testSettlingWindowExpiresAfterDeadline() {
        let settlingUntil = Date(timeIntervalSinceReferenceDate: 10.3)

        XCTAssertTrue(
            TranscriptAutoFollow.isSettlingAfterRun(
                settlingUntil: settlingUntil,
                now: Date(timeIntervalSinceReferenceDate: 10.2)
            )
        )
        XCTAssertFalse(
            TranscriptAutoFollow.isSettlingAfterRun(
                settlingUntil: settlingUntil,
                now: Date(timeIntervalSinceReferenceDate: 10.4)
            )
        )
    }
}
