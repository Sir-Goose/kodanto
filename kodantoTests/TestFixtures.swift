import Foundation
@testable import kodanto

enum TestFixtures {
    static func project(
        id: String,
        worktree: String,
        name: String? = nil,
        updatedAt: Double
    ) -> OpenCodeProject {
        OpenCodeProject(
            id: id,
            worktree: worktree,
            vcs: nil,
            name: name,
            icon: nil,
            commands: nil,
            time: .init(created: updatedAt - 60, updated: updatedAt, initialized: nil),
            sandboxes: []
        )
    }

    static func session(
        id: String,
        projectID: String = "project-1",
        directory: String = "/tmp/project",
        title: String = "Session",
        updatedAt: Double,
        parentID: String? = nil
    ) -> OpenCodeSession {
        OpenCodeSession(
            id: id,
            slug: id,
            projectID: projectID,
            workspaceID: nil,
            directory: directory,
            parentID: parentID,
            summary: nil,
            share: nil,
            title: title,
            version: "1",
            time: .init(created: updatedAt - 60, updated: updatedAt, compacting: nil, archived: nil),
            revert: nil
        )
    }

    static func userMessage(
        id: String,
        sessionID: String = "session-1",
        createdAt: Double,
        parts: [OpenCodePart]? = nil
    ) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: .user(
                .init(
                    id: id,
                    sessionID: sessionID,
                    role: "user",
                    time: .init(created: createdAt),
                    agent: "assistant",
                    model: .init(providerID: "provider-1", modelID: "model-1"),
                    variant: nil
                )
            ),
            parts: parts ?? [textPart(id: "\(id)-text", sessionID: sessionID, messageID: id, text: "Prompt")]
        )
    }

    static func assistantMessage(
        id: String,
        sessionID: String = "session-1",
        parentID: String,
        createdAt: Double,
        parts: [OpenCodePart]? = nil
    ) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: .assistant(
                .init(
                    id: id,
                    sessionID: sessionID,
                    role: "assistant",
                    time: .init(created: createdAt, completed: createdAt + 1),
                    parentID: parentID,
                    modelID: "model-1",
                    providerID: "provider-1",
                    mode: "default",
                    agent: "assistant",
                    path: .init(cwd: "/tmp/project", root: "/tmp/project"),
                    summary: nil,
                    cost: 0,
                    tokens: .init(total: nil, input: 0, output: 0, reasoning: 0, cache: .init(read: 0, write: 0)),
                    variant: nil,
                    finish: nil
                )
            ),
            parts: parts ?? [textPart(id: "\(id)-text", sessionID: sessionID, messageID: id, text: "Reply")]
        )
    }

    static func textPart(
        id: String,
        sessionID: String = "session-1",
        messageID: String,
        text: String
    ) -> OpenCodePart {
        .text(.init(id: id, sessionID: sessionID, messageID: messageID, type: "text", text: text))
    }

    static func reasoningPart(
        id: String,
        sessionID: String = "session-1",
        messageID: String,
        text: String
    ) -> OpenCodePart {
        .reasoning(.init(id: id, sessionID: sessionID, messageID: messageID, type: "reasoning", text: text))
    }

    static func toolPart(
        id: String,
        sessionID: String = "session-1",
        messageID: String,
        tool: String,
        status: String = "completed",
        input: [String: JSONValue]? = nil,
        output: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) -> OpenCodePart {
        .tool(
            .init(
                id: id,
                sessionID: sessionID,
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
                    error: nil,
                    metadata: metadata,
                    time: .init(start: 0, end: 1, compacted: nil)
                )
            )
        )
    }

    static func permissionRequest(
        id: String,
        sessionID: String = "session-1",
        permission: String = "read",
        patterns: [String] = ["src/**/*.swift"]
    ) -> OpenCodePermissionRequest {
        OpenCodePermissionRequest(
            id: id,
            sessionID: sessionID,
            permission: permission,
            patterns: patterns,
            metadata: [:],
            always: [],
            tool: nil
        )
    }

    static func questionRequest(
        id: String,
        sessionID: String = "session-1",
        questions: [OpenCodeQuestionRequest.Question]
    ) -> OpenCodeQuestionRequest {
        OpenCodeQuestionRequest(id: id, sessionID: sessionID, questions: questions, tool: nil)
    }

    static func todo(
        _ content: String,
        status: String = "pending",
        priority: String = "medium"
    ) -> OpenCodeTodo {
        OpenCodeTodo(content: content, status: status, priority: priority)
    }

    static func globalEvent(
        directory: String? = nil,
        payload: OpenCodeEvent
    ) -> OpenCodeGlobalEvent {
        OpenCodeGlobalEvent(directory: directory, payload: payload)
    }
}
