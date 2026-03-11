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

    func testUserCopyTextIncludesOnlyTextPartsAndIgnoresWhitespace() {
        let user = TestFixtures.userMessage(
            id: "user-1",
            createdAt: 1,
            parts: [
                TestFixtures.textPart(id: "user-1-text-a", messageID: "user-1", text: "  First prompt  "),
                TestFixtures.reasoningPart(id: "user-1-reasoning", messageID: "user-1", text: "thinking"),
                TestFixtures.textPart(id: "user-1-text-empty", messageID: "user-1", text: "   "),
                TestFixtures.textPart(id: "user-1-text-b", messageID: "user-1", text: "\nSecond prompt\n")
            ]
        )

        let turns = TranscriptTurn.build(from: [user])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].userCopyText, "First prompt\n\nSecond prompt")
    }

    func testAssistantCopyTextUsesLastTextPartAcrossAssistantMessages() {
        let user = TestFixtures.userMessage(id: "user-1", createdAt: 1)
        let assistantA = TestFixtures.assistantMessage(
            id: "assistant-1",
            parentID: user.id,
            createdAt: 2,
            parts: [
                TestFixtures.textPart(id: "assistant-1-text", messageID: "assistant-1", text: "First response")
            ]
        )
        let assistantB = TestFixtures.assistantMessage(
            id: "assistant-2",
            parentID: user.id,
            createdAt: 3,
            parts: [
                TestFixtures.toolPart(id: "assistant-2-tool", messageID: "assistant-2", tool: "read"),
                TestFixtures.textPart(id: "assistant-2-text", messageID: "assistant-2", text: "Final response")
            ]
        )

        let turns = TranscriptTurn.build(from: [user, assistantA, assistantB])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].assistantCopyText, "Final response")
    }

    func testAssistantCopyTextIsNilWithoutAssistantTextParts() {
        let user = TestFixtures.userMessage(id: "user-1", createdAt: 1)
        let assistant = TestFixtures.assistantMessage(
            id: "assistant-1",
            parentID: user.id,
            createdAt: 2,
            parts: [
                TestFixtures.reasoningPart(id: "assistant-1-reasoning", messageID: "assistant-1", text: "thinking"),
                TestFixtures.toolPart(id: "assistant-1-tool", messageID: "assistant-1", tool: "read")
            ]
        )

        let turns = TranscriptTurn.build(from: [user, assistant])

        XCTAssertEqual(turns.count, 1)
        XCTAssertNil(turns[0].assistantCopyText)
    }
}
