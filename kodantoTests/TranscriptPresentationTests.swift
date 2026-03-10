import XCTest
@testable import kodanto

final class TranscriptPresentationTests: XCTestCase {
    func testTranscriptTurnBuilderGroupsMultipleAssistantMessagesUnderUser() {
        let user = userEnvelope(id: "user-1", createdAt: 1, text: "First prompt")
        let firstAssistant = assistantEnvelope(
            id: "assistant-1",
            parentID: user.id,
            createdAt: 2,
            parts: [textPart(id: "part-1", messageID: "assistant-1", text: "First reply")]
        )
        let secondAssistant = assistantEnvelope(
            id: "assistant-2",
            parentID: user.id,
            createdAt: 3,
            parts: [textPart(id: "part-2", messageID: "assistant-2", text: "Second reply")]
        )
        let nextUser = userEnvelope(id: "user-2", createdAt: 4, text: "Second prompt")

        let turns = TranscriptTurn.build(from: [user, firstAssistant, secondAssistant, nextUser])

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].user?.id, user.id)
        XCTAssertEqual(turns[0].assistantMessages.map(\.id), [firstAssistant.id, secondAssistant.id])
        XCTAssertEqual(turns[1].user?.id, nextUser.id)
        XCTAssertTrue(turns[1].assistantMessages.isEmpty)
    }

    func testTranscriptTurnBuilderStopsGroupingAtNextUserBoundary() {
        let firstUser = userEnvelope(id: "user-1", createdAt: 1, text: "Prompt one")
        let firstAssistant = assistantEnvelope(
            id: "assistant-1",
            parentID: firstUser.id,
            createdAt: 2,
            parts: [textPart(id: "part-1", messageID: "assistant-1", text: "Reply one")]
        )
        let secondUser = userEnvelope(id: "user-2", createdAt: 3, text: "Prompt two")
        let lateAssistant = assistantEnvelope(
            id: "assistant-2",
            parentID: firstUser.id,
            createdAt: 4,
            parts: [textPart(id: "part-2", messageID: "assistant-2", text: "Late reply")]
        )

        let turns = TranscriptTurn.build(from: [firstUser, firstAssistant, secondUser, lateAssistant])

        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(turns[0].user?.id, firstUser.id)
        XCTAssertEqual(turns[0].assistantMessages.map(\.id), [firstAssistant.id])
        XCTAssertEqual(turns[1].user?.id, secondUser.id)
        XCTAssertTrue(turns[1].assistantMessages.isEmpty)
        XCTAssertNil(turns[2].user)
        XCTAssertEqual(turns[2].assistantMessages.map(\.id), [lateAssistant.id])
    }

    func testTranscriptTurnBuilderKeepsUnmatchedAssistantAsStandaloneTurn() {
        let assistant = assistantEnvelope(
            id: "assistant-1",
            parentID: "missing-user",
            createdAt: 1,
            parts: [textPart(id: "part-1", messageID: "assistant-1", text: "Standalone")]
        )

        let turns = TranscriptTurn.build(from: [assistant])

        XCTAssertEqual(turns.count, 1)
        XCTAssertNil(turns[0].user)
        XCTAssertEqual(turns[0].assistantMessages.map(\.id), [assistant.id])
    }

    func testAssistantPartGroupingCollapsesContiguousContextTools() {
        let assistant = assistantEnvelope(
            id: "assistant-1",
            parentID: "user-1",
            createdAt: 1,
            parts: [
                toolPart(id: "tool-1", messageID: "assistant-1", tool: "read", status: "completed"),
                toolPart(id: "tool-2", messageID: "assistant-1", tool: "grep", status: "completed"),
                textPart(id: "part-1", messageID: "assistant-1", text: "Done")
            ]
        )

        let groups = AssistantPartGroup.build(from: [assistant])

        XCTAssertEqual(groups.count, 2)
        guard case .context(_, let tools) = groups[0] else {
            return XCTFail("Expected context group")
        }
        XCTAssertEqual(tools.map(\.tool), ["read", "grep"])

        guard case let .part(.text(value)) = groups[1] else {
            return XCTFail("Expected trailing text part")
        }
        XCTAssertEqual(value.text, "Done")
    }

    func testAssistantPartGroupingBreaksContextGroupOnNonContextTool() {
        let assistant = assistantEnvelope(
            id: "assistant-1",
            parentID: "user-1",
            createdAt: 1,
            parts: [
                toolPart(id: "tool-1", messageID: "assistant-1", tool: "read", status: "completed"),
                toolPart(id: "tool-2", messageID: "assistant-1", tool: "bash", status: "completed"),
                toolPart(id: "tool-3", messageID: "assistant-1", tool: "grep", status: "completed")
            ]
        )

        let groups = AssistantPartGroup.build(from: [assistant])

        XCTAssertEqual(groups.count, 3)
        guard case .context(_, let firstTools) = groups[0] else {
            return XCTFail("Expected first context group")
        }
        XCTAssertEqual(firstTools.map(\.tool), ["read"])

        guard case let .part(.tool(tool)) = groups[1] else {
            return XCTFail("Expected middle bash tool")
        }
        XCTAssertEqual(tool.tool, "bash")

        guard case .context(_, let lastTools) = groups[2] else {
            return XCTFail("Expected trailing context group")
        }
        XCTAssertEqual(lastTools.map(\.tool), ["grep"])
    }

    func testAssistantPartGroupingHidesTodoTools() {
        let assistant = assistantEnvelope(
            id: "assistant-1",
            parentID: "user-1",
            createdAt: 1,
            parts: [
                toolPart(id: "tool-1", messageID: "assistant-1", tool: "todoread", status: "completed"),
                toolPart(id: "tool-2", messageID: "assistant-1", tool: "todowrite", status: "completed"),
                textPart(id: "part-1", messageID: "assistant-1", text: "Visible")
            ]
        )

        let groups = AssistantPartGroup.build(from: [assistant])

        XCTAssertEqual(groups.count, 1)
        guard case let .part(.text(text)) = groups[0] else {
            return XCTFail("Expected only text part to remain visible")
        }
        XCTAssertEqual(text.text, "Visible")
    }

    func testAssistantPartGroupingHidesPendingAndRunningQuestionTools() {
        let assistant = assistantEnvelope(
            id: "assistant-1",
            parentID: "user-1",
            createdAt: 1,
            parts: [
                toolPart(id: "tool-1", messageID: "assistant-1", tool: "question", status: "pending"),
                toolPart(id: "tool-2", messageID: "assistant-1", tool: "question", status: "running"),
                toolPart(
                    id: "tool-3",
                    messageID: "assistant-1",
                    tool: "question",
                    status: "completed",
                    metadata: [
                        "answers": .array([.array([.string("Yes")])])
                    ]
                )
            ]
        )

        let groups = AssistantPartGroup.build(from: [assistant])

        XCTAssertEqual(groups.count, 1)
        guard case let .part(.tool(tool)) = groups[0] else {
            return XCTFail("Expected completed question tool to remain")
        }
        XCTAssertEqual(tool.tool, "question")
        XCTAssertEqual(tool.questionAnswers, [["Yes"]])
    }

    func testBashToolHelpersExposeCommandDescriptionAndTranscript() {
        let tool = toolValue(
            id: "tool-1",
            messageID: "assistant-1",
            tool: "bash",
            status: "completed",
            input: [
                "command": .string("git status"),
                "description": .string("Show repo status")
            ],
            output: "On branch main",
            metadata: [
                "output": .string("On branch main"),
                "description": .string("Show repo status")
            ]
        )

        XCTAssertEqual(tool.command, "git status")
        XCTAssertEqual(tool.shellDescription, "Show repo status")
        XCTAssertEqual(tool.shellTranscript, "$ git status\n\nOn branch main")
        XCTAssertEqual(tool.shellPreviewTranscript, "$ git status\n\nOn branch main")
        XCTAssertEqual(tool.shellOutputLineCount, 1)
        XCTAssertEqual(tool.shellHiddenOutputLineCount, 0)
        XCTAssertFalse(tool.shellHasHiddenOutput)
        XCTAssertEqual(tool.shellLineCountBadge, "1 line")
        XCTAssertTrue(tool.defaultOpen)
    }

    func testBashToolPreviewTruncatesLongOutputToPreviewLimit() {
        let outputLines = (1...14).map { "line \($0)" }
        let output = outputLines.joined(separator: "\n")
        let preview = Array(outputLines.prefix(12)).joined(separator: "\n")
        let tool = toolValue(
            id: "tool-1",
            messageID: "assistant-1",
            tool: "bash",
            status: "completed",
            input: [
                "command": .string("python script.py")
            ],
            output: output
        )

        XCTAssertEqual(tool.shellTranscript, "$ python script.py\n\n\(output)")
        XCTAssertEqual(tool.shellPreviewTranscript, "$ python script.py\n\n\(preview)")
        XCTAssertEqual(tool.shellOutputLineCount, 14)
        XCTAssertEqual(tool.shellHiddenOutputLineCount, 2)
        XCTAssertTrue(tool.shellHasHiddenOutput)
        XCTAssertEqual(tool.shellLineCountBadge, "14 lines")
    }

    func testBashToolPreviewDoesNotTruncateAtPreviewThreshold() {
        let outputLines = (1...12).map { "line \($0)" }
        let output = outputLines.joined(separator: "\n")
        let tool = toolValue(
            id: "tool-1",
            messageID: "assistant-1",
            tool: "bash",
            status: "completed",
            input: [
                "command": .string("npm test")
            ],
            output: output
        )

        XCTAssertEqual(tool.shellTranscript, "$ npm test\n\n\(output)")
        XCTAssertEqual(tool.shellPreviewTranscript, "$ npm test\n\n\(output)")
        XCTAssertEqual(tool.shellOutputLineCount, 12)
        XCTAssertEqual(tool.shellHiddenOutputLineCount, 0)
        XCTAssertFalse(tool.shellHasHiddenOutput)
        XCTAssertEqual(tool.shellLineCountBadge, "12 lines")
    }

    func testReadToolHelpersDecodeLoadedFiles() {
        let tool = toolValue(
            id: "tool-1",
            messageID: "assistant-1",
            tool: "read",
            status: "completed",
            input: [
                "filePath": .string("/repo/Sources/App.swift"),
                "offset": .number(10),
                "limit": .number(30)
            ],
            metadata: [
                "loaded": .array([
                    .string("/repo/Sources/App.swift"),
                    .string("/repo/Tests/AppTests.swift")
                ])
            ]
        )

        XCTAssertEqual(tool.readLoadedFiles, ["/repo/Sources/App.swift", "/repo/Tests/AppTests.swift"])
        XCTAssertEqual(tool.argBadges, ["offset=10", "limit=30"])
    }

    func testEditToolHelpersDecodeFileDiffAndDiagnostics() {
        let tool = toolValue(
            id: "tool-1",
            messageID: "assistant-1",
            tool: "edit",
            status: "completed",
            input: [
                "filePath": .string("/repo/Sources/App.swift")
            ],
            metadata: [
                "filediff": .object([
                    "file": .string("/repo/Sources/App.swift"),
                    "before": .string("old"),
                    "after": .string("new"),
                    "additions": .number(1),
                    "deletions": .number(1)
                ]),
                "diagnostics": .object([
                    "/repo/Sources/App.swift": .array([
                        .object([
                            "range": .object([
                                "start": .object([
                                    "line": .number(3),
                                    "character": .number(5)
                                ]),
                                "end": .object([
                                    "line": .number(3),
                                    "character": .number(9)
                                ])
                            ]),
                            "message": .string("Missing return"),
                            "severity": .number(1)
                        ])
                    ])
                ])
            ]
        )

        XCTAssertEqual(tool.fileDiff?.file, "/repo/Sources/App.swift")
        XCTAssertEqual(tool.fileDiff?.additions, 1)
        XCTAssertEqual(tool.diagnostics(for: "/repo/Sources/App.swift").map(\.message), ["Missing return"])
    }

    func testApplyPatchHelpersDecodePatchFiles() {
        let tool = toolValue(
            id: "tool-1",
            messageID: "assistant-1",
            tool: "apply_patch",
            status: "completed",
            metadata: [
                "files": .array([
                    .object([
                        "filePath": .string("/repo/Sources/App.swift"),
                        "relativePath": .string("Sources/App.swift"),
                        "type": .string("update"),
                        "diff": .string("@@"),
                        "before": .string("old"),
                        "after": .string("new"),
                        "additions": .number(2),
                        "deletions": .number(1),
                        "movePath": .null
                    ])
                ])
            ]
        )

        XCTAssertEqual(tool.patchFiles.count, 1)
        XCTAssertEqual(tool.patchFiles.first?.relativePath, "Sources/App.swift")
        XCTAssertEqual(tool.patchFiles.first?.additions, 2)
        XCTAssertFalse(tool.defaultOpen)
    }

    func testToolDefaultOpenRulesMatchExpectedTools() {
        let bash = toolValue(id: "tool-1", messageID: "assistant-1", tool: "bash", status: "completed")
        let edit = toolValue(id: "tool-2", messageID: "assistant-1", tool: "edit", status: "completed")
        let question = toolValue(
            id: "tool-3",
            messageID: "assistant-1",
            tool: "question",
            status: "completed",
            metadata: [
                "answers": .array([.array([.string("Yes")])])
            ]
        )

        XCTAssertTrue(bash.defaultOpen)
        XCTAssertFalse(edit.defaultOpen)
        XCTAssertTrue(question.defaultOpen)
    }

    func testTaskChildSessionHelpersResolveKnownSessionAndFallbackToNil() {
        let tool = toolValue(
            id: "tool-1",
            messageID: "assistant-1",
            tool: "task",
            status: "completed",
            input: [
                "description": .string("Inspect child session")
            ],
            metadata: [
                "sessionId": .string("child-1")
            ]
        )

        let project = OpenCodeProject(
            id: "project-1",
            worktree: "/repo",
            vcs: nil,
            name: "Repo",
            icon: nil,
            commands: nil,
            time: .init(created: 0, updated: 0, initialized: nil),
            sandboxes: []
        )
        let session = OpenCodeSession(
            id: "child-1",
            slug: "child-1",
            projectID: project.id,
            workspaceID: nil,
            directory: "/repo",
            parentID: nil,
            summary: nil,
            share: nil,
            title: "Child",
            version: "1",
            time: .init(created: 0, updated: 0, compacting: nil, archived: nil),
            revert: nil
        )

        let resolved = SessionNavigationTargetResolver.resolve(
            sessionID: tool.childSessionID ?? "",
            projects: [project],
            sessionsByDirectory: [project.worktree: [session]]
        )
        let missing = SessionNavigationTargetResolver.resolve(
            sessionID: "missing-session",
            projects: [project],
            sessionsByDirectory: [project.worktree: [session]]
        )

        XCTAssertEqual(tool.childSessionID, "child-1")
        XCTAssertEqual(resolved?.projectID, project.id)
        XCTAssertEqual(resolved?.sessionID, session.id)
        XCTAssertNil(missing)
    }
}

private func userEnvelope(id: String, createdAt: Double, text: String) -> OpenCodeMessageEnvelope {
    let info = OpenCodeMessage.User(
        id: id,
        sessionID: "session-1",
        role: "user",
        time: .init(created: createdAt),
        agent: "build",
        model: .init(providerID: "provider-1", modelID: "model-1"),
        variant: nil
    )

    return OpenCodeMessageEnvelope(
        info: .user(info),
        parts: [textPart(id: "text-\(id)", messageID: id, text: text)]
    )
}

private func assistantEnvelope(
    id: String,
    parentID: String,
    createdAt: Double,
    parts: [OpenCodePart]
) -> OpenCodeMessageEnvelope {
    let info = OpenCodeMessage.Assistant(
        id: id,
        sessionID: "session-1",
        role: "assistant",
        time: .init(created: createdAt, completed: createdAt + 0.1),
        parentID: parentID,
        modelID: "model-1",
        providerID: "provider-1",
        mode: "build",
        agent: "build",
        path: .init(cwd: "/repo", root: "/repo"),
        summary: nil,
        cost: 0,
        tokens: .init(total: nil, input: 0, output: 0, reasoning: 0, cache: .init(read: 0, write: 0)),
        variant: nil,
        finish: nil
    )

    return OpenCodeMessageEnvelope(info: .assistant(info), parts: parts)
}

private func textPart(id: String, messageID: String, text: String) -> OpenCodePart {
    .text(.init(
        id: id,
        sessionID: "session-1",
        messageID: messageID,
        type: "text",
        text: text
    ))
}

private func toolPart(
    id: String,
    messageID: String,
    tool: String,
    status: String,
    input: [String: JSONValue] = [:],
    output: String? = nil,
    error: String? = nil,
    metadata: [String: JSONValue]? = nil
) -> OpenCodePart {
    .tool(toolValue(
        id: id,
        messageID: messageID,
        tool: tool,
        status: status,
        input: input,
        output: output,
        error: error,
        metadata: metadata
    ))
}

private func toolValue(
    id: String,
    messageID: String,
    tool: String,
    status: String,
    input: [String: JSONValue] = [:],
    output: String? = nil,
    error: String? = nil,
    metadata: [String: JSONValue]? = nil
) -> OpenCodePart.Tool {
    OpenCodePart.Tool(
        id: id,
        sessionID: "session-1",
        messageID: messageID,
        type: "tool",
        callID: "call-\(id)",
        tool: tool,
        state: .init(
            status: status,
            input: input,
            raw: nil,
            title: nil,
            output: output,
            error: error,
            metadata: metadata,
            time: nil
        )
    )
}
