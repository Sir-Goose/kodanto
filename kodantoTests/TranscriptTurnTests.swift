import XCTest
@testable import kodanto

final class TranscriptTurnTests: XCTestCase {
    func testBuildGroupsAssistantsWithMatchingParentIntoSingleTurn() {
        let user = TestFixtures.userMessage(id: "user-1", createdAt: 1)
        let assistantA = TestFixtures.assistantMessage(id: "assistant-1", parentID: user.id, createdAt: 2)
        let assistantB = TestFixtures.assistantMessage(id: "assistant-2", parentID: user.id, createdAt: 3)

        let turns = TranscriptTurn.build(from: [user, assistantA, assistantB])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].user?.id, user.id)
        XCTAssertEqual(turns[0].assistantMessages.map(\.id), [assistantA.id, assistantB.id])
        XCTAssertEqual(turns[0].userVisibleParts.count, 1)
    }

    func testBuildCreatesStandaloneTurnForOrphanAssistantMessage() {
        let assistant = TestFixtures.assistantMessage(id: "assistant-1", parentID: "missing-user", createdAt: 1)

        let turns = TranscriptTurn.build(from: [assistant])

        XCTAssertEqual(turns.count, 1)
        XCTAssertNil(turns[0].user)
        XCTAssertEqual(turns[0].assistantMessages.map(\.id), [assistant.id])
    }

    func testBuildFlushesCurrentUserWhenAssistantParentDoesNotMatch() {
        let user = TestFixtures.userMessage(id: "user-1", createdAt: 1)
        let mismatchedAssistant = TestFixtures.assistantMessage(id: "assistant-1", parentID: "other-user", createdAt: 2)

        let turns = TranscriptTurn.build(from: [user, mismatchedAssistant])

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].user?.id, user.id)
        XCTAssertTrue(turns[0].assistantMessages.isEmpty)
        XCTAssertNil(turns[1].user)
        XCTAssertEqual(turns[1].assistantMessages.map(\.id), [mismatchedAssistant.id])
    }
}
