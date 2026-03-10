import Foundation

struct TranscriptTurn: Identifiable, Hashable {
    let user: OpenCodeMessageEnvelope?
    let assistantMessages: [OpenCodeMessageEnvelope]
    let userVisibleParts: [OpenCodePart]
    let assistantPartGroups: [AssistantPartGroup]

    var id: String {
        user?.id ?? assistantMessages.first?.id ?? "transcript-turn"
    }

    init(user: OpenCodeMessageEnvelope?, assistantMessages: [OpenCodeMessageEnvelope]) {
        self.user = user
        self.assistantMessages = assistantMessages
        userVisibleParts = user?.parts.filter(\.isVisibleInUserTurn) ?? []
        assistantPartGroups = AssistantPartGroup.build(from: assistantMessages)
    }

    static func build(from messages: [OpenCodeMessageEnvelope]) -> [TranscriptTurn] {
        var turns: [TranscriptTurn] = []
        var currentUser: OpenCodeMessageEnvelope?
        var currentAssistants: [OpenCodeMessageEnvelope] = []

        func flushCurrentUser() {
            guard currentUser != nil else { return }
            turns.append(TranscriptTurn(user: currentUser, assistantMessages: currentAssistants))
            currentUser = nil
            currentAssistants = []
        }

        for message in messages {
            switch message.info {
            case .user:
                flushCurrentUser()
                currentUser = message
            case .assistant(let assistant):
                guard let currentUser else {
                    turns.append(TranscriptTurn(user: nil, assistantMessages: [message]))
                    continue
                }

                if assistant.parentID == currentUser.id {
                    currentAssistants.append(message)
                } else {
                    flushCurrentUser()
                    turns.append(TranscriptTurn(user: nil, assistantMessages: [message]))
                }
            }
        }

        flushCurrentUser()
        return turns
    }
}

enum AssistantPartGroup: Identifiable, Hashable {
    case part(OpenCodePart)
    case context(id: String, tools: [OpenCodePart.Tool])

    var id: String {
        switch self {
        case .part(let part):
            return part.id
        case .context(let id, _):
            return id
        }
    }

    var tools: [OpenCodePart.Tool] {
        guard case .context(_, let tools) = self else { return [] }
        return tools
    }

    static func build(from messages: [OpenCodeMessageEnvelope]) -> [AssistantPartGroup] {
        let visibleParts = messages
            .flatMap(\.parts)
            .filter(\.isVisibleInAssistantTurn)

        var groups: [AssistantPartGroup] = []
        var currentContextTools: [OpenCodePart.Tool] = []
        var currentContextID: String?

        func flushContextTools() {
            guard let contextID = currentContextID, !currentContextTools.isEmpty else { return }
            groups.append(.context(id: contextID, tools: currentContextTools))
            currentContextTools = []
            currentContextID = nil
        }

        for part in visibleParts {
            if let tool = part.contextTool {
                if currentContextID == nil {
                    currentContextID = "context:\(tool.id)"
                }
                currentContextTools.append(tool)
                continue
            }

            flushContextTools()
            groups.append(.part(part))
        }

        flushContextTools()

        return groups
    }
}

private let transcriptContextToolNames: Set<String> = ["read", "glob", "grep", "list"]
private let transcriptHiddenToolNames: Set<String> = ["todowrite", "todoread"]

extension OpenCodePart {
    var isVisibleInUserTurn: Bool {
        switch self {
        case .stepStart, .stepFinish:
            return false
        case .text(let value):
            return !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .reasoning(let value):
            return !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    var isVisibleInAssistantTurn: Bool {
        switch self {
        case .stepStart, .stepFinish:
            return false
        case .text(let value):
            return !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .reasoning(let value):
            return !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .tool(let tool):
            if transcriptHiddenToolNames.contains(tool.tool) {
                return false
            }
            if tool.tool == "question", tool.isPendingOrRunning {
                return false
            }
            return true
        default:
            return true
        }
    }

    var contextTool: OpenCodePart.Tool? {
        guard case .tool(let tool) = self, transcriptContextToolNames.contains(tool.tool) else { return nil }
        return tool
    }
}

struct ToolDiagnostic: Decodable, Hashable {
    struct Position: Decodable, Hashable {
        let line: Int
        let character: Int
    }

    struct Range: Decodable, Hashable {
        let start: Position
        let end: Position
    }

    let range: Range
    let message: String
    let severity: Int?

    var isError: Bool {
        severity == nil || severity == 1
    }
}

struct ToolFileDiff: Decodable, Hashable {
    let file: String
    let before: String
    let after: String
    let additions: Int
    let deletions: Int
}

struct ToolPatchFile: Decodable, Hashable {
    let filePath: String
    let relativePath: String
    let type: String
    let diff: String
    let before: String
    let after: String
    let additions: Int
    let deletions: Int
    let movePath: String?
}

struct LoadedSessionLocation: Hashable {
    let projectID: OpenCodeProject.ID
    let sessionID: OpenCodeSession.ID
}

enum SessionNavigationTargetResolver {
    static func resolve(
        sessionID: OpenCodeSession.ID,
        projects: [OpenCodeProject],
        sessionsByDirectory: [String: [OpenCodeSession]]
    ) -> LoadedSessionLocation? {
        for (directory, cachedSessions) in sessionsByDirectory {
            guard cachedSessions.contains(where: { $0.id == sessionID }) else { continue }
            guard let project = projects.first(where: { $0.worktree == directory || $0.id == directory }) else { continue }
            return LoadedSessionLocation(projectID: project.id, sessionID: sessionID)
        }

        return nil
    }
}

enum TranscriptPathFormatter {
    static func relativePath(_ path: String?, worktreeRoot: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        guard let worktreeRoot, !worktreeRoot.isEmpty else { return path }

        let standardizedPath = (path as NSString).standardizingPath
        let standardizedRoot = (worktreeRoot as NSString).standardizingPath
        if standardizedPath == standardizedRoot {
            return ""
        }

        let separator = standardizedRoot.contains("\\") ? "\\" : "/"
        let prefix = standardizedRoot.hasSuffix(separator) ? standardizedRoot : standardizedRoot + separator
        guard standardizedPath.hasPrefix(prefix) else { return path }
        return String(standardizedPath.dropFirst(prefix.count))
    }

    static func filename(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    static func directory(_ path: String?, worktreeRoot: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        let relative = relativePath(path, worktreeRoot: worktreeRoot)
        let directory = (relative as NSString).deletingLastPathComponent
        if directory == "." {
            return ""
        }
        return directory
    }

    static func displayPath(_ path: String?, worktreeRoot: String?) -> String {
        let relative = relativePath(path, worktreeRoot: worktreeRoot)
        return relative.isEmpty ? filename(path) : relative
    }
}

private let shellPreviewOutputLineLimit = 12

private struct ShellTranscriptPresentation {
    let commandLine: String?
    let output: String?

    init(command: String?, output: String?) {
        if let command, !command.isEmpty {
            commandLine = "$ \(command)"
        } else {
            commandLine = nil
        }

        if let output {
            let trimmed = output.trimmingCharacters(in: .newlines)
            self.output = trimmed.isEmpty ? nil : trimmed
        } else {
            self.output = nil
        }
    }

    var outputLines: [String] {
        guard let output else { return [] }
        return output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var outputLineCount: Int {
        outputLines.count
    }

    var hiddenOutputLineCount: Int {
        max(outputLineCount - shellPreviewOutputLineLimit, 0)
    }

    var hasHiddenOutput: Bool {
        hiddenOutputLineCount > 0
    }

    var previewOutput: String? {
        guard let output else { return nil }
        guard hasHiddenOutput else { return output }
        return Array(outputLines.prefix(shellPreviewOutputLineLimit)).joined(separator: "\n")
    }

    var fullTranscript: String? {
        formattedTranscript(output: output)
    }

    var previewTranscript: String? {
        formattedTranscript(output: previewOutput)
    }

    var lineCountBadge: String? {
        guard outputLineCount > 0 else { return nil }
        let noun = outputLineCount == 1 ? "line" : "lines"
        return "\(outputLineCount) \(noun)"
    }

    private func formattedTranscript(output: String?) -> String? {
        switch (commandLine, output) {
        case let (commandLine?, output?) where !output.isEmpty:
            return "\(commandLine)\n\n\(output)"
        case let (commandLine?, _):
            return commandLine
        case let (_, output?) where !output.isEmpty:
            return output
        default:
            return nil
        }
    }
}

extension OpenCodePart.Tool {
    var isPendingOrRunning: Bool {
        state.status == "pending" || state.status == "running"
    }

    var isCompleted: Bool {
        state.status == "completed"
    }

    var isError: Bool {
        state.status == "error"
    }

    var titleLabel: String {
        switch tool {
        case "bash":
            return "Shell"
        case "read":
            return "Read"
        case "list":
            return "List"
        case "glob":
            return "Glob"
        case "grep":
            return "Grep"
        case "webfetch":
            return "Webfetch"
        case "websearch":
            return "Web Search"
        case "codesearch":
            return "Code Search"
        case "edit":
            return "Edit"
        case "write":
            return "Write"
        case "apply_patch":
            return "Patch"
        case "question":
            return "Questions"
        case "task":
            return agentName ?? "Agent"
        case "skill":
            return skillName ?? "Skill"
        default:
            return displayTitle
        }
    }

    var displayStatus: String {
        switch state.status {
        case "pending", "running":
            return "Running"
        case "completed":
            return "Done"
        case "error":
            return "Error"
        default:
            return state.status.capitalized
        }
    }

    var defaultOpen: Bool {
        switch tool {
        case "bash":
            return true
        case "question":
            return !questionAnswers.isEmpty
        default:
            return false
        }
    }

    var inputValues: [String: JSONValue] {
        state.input ?? [:]
    }

    var metadataValues: [String: JSONValue] {
        state.metadata ?? [:]
    }

    var shellDescription: String? {
        inputValues["description"]?.stringValue ?? metadataValues["description"]?.stringValue
    }

    var shellOutput: String? {
        metadataValues["output"]?.stringValue ?? state.output
    }

    private var shellPresentation: ShellTranscriptPresentation {
        ShellTranscriptPresentation(command: command, output: shellOutput)
    }

    var shellTranscript: String? {
        shellPresentation.fullTranscript
    }

    var shellPreviewTranscript: String? {
        shellPresentation.previewTranscript
    }

    var shellOutputLineCount: Int {
        shellPresentation.outputLineCount
    }

    var shellHiddenOutputLineCount: Int {
        shellPresentation.hiddenOutputLineCount
    }

    var shellHasHiddenOutput: Bool {
        shellPresentation.hasHiddenOutput
    }

    var shellLineCountBadge: String? {
        shellPresentation.lineCountBadge
    }

    var agentName: String? {
        let type = inputValues["subagent_type"]?.stringValue
        guard let type, !type.isEmpty else { return nil }
        return type.prefix(1).uppercased() + type.dropFirst() + " Agent"
    }

    var skillName: String? {
        inputValues["name"]?.stringValue
    }

    var filePath: String? {
        inputValues["filePath"]?.stringValue ?? metadataValues["filepath"]?.stringValue
    }

    var relativeTitle: String? {
        state.title
    }

    var readLoadedFiles: [String] {
        metadataValues["loaded"]?.decoded(as: [String].self) ?? []
    }

    var fileDiff: ToolFileDiff? {
        metadataValues["filediff"]?.decoded(as: ToolFileDiff.self)
    }

    var patchFiles: [ToolPatchFile] {
        metadataValues["files"]?.decoded(as: [ToolPatchFile].self) ?? []
    }

    var questionAnswers: [[String]] {
        metadataValues["answers"]?.decoded(as: [[String]].self) ?? []
    }

    var childSessionID: String? {
        metadataValues["sessionId"]?.stringValue
    }

    var diagnosticsByFile: [String: [ToolDiagnostic]] {
        metadataValues["diagnostics"]?.decoded(as: [String: [ToolDiagnostic]].self) ?? [:]
    }

    func diagnostics(for filePath: String?) -> [ToolDiagnostic] {
        guard let filePath, !filePath.isEmpty else { return [] }
        let candidates = [
            filePath,
            (filePath as NSString).standardizingPath,
            URL(fileURLWithPath: filePath).path
        ]

        for candidate in candidates {
            if let diagnostics = diagnosticsByFile[candidate] {
                return diagnostics.filter(\.isError)
            }
        }

        return []
    }

    var titleBadgeCount: Int? {
        switch tool {
        case "list", "glob":
            return metadataValues["count"]?.intValue
        case "grep":
            return metadataValues["matches"]?.intValue
        default:
            return nil
        }
    }

    var subtitleText: String? {
        switch tool {
        case "bash":
            return shellDescription
        case "read":
            return filePath.map { TranscriptPathFormatter.filename($0) }
        case "webfetch":
            return inputValues["url"]?.stringValue
        case "websearch", "codesearch":
            return inputValues["query"]?.stringValue
        case "task":
            return inputValues["description"]?.stringValue
        case "skill":
            return skillName
        default:
            return nil
        }
    }

    var argBadges: [String] {
        switch tool {
        case "read":
            return [
                inputValues["offset"]?.intValue.map { "offset=\($0)" },
                inputValues["limit"]?.intValue.map { "limit=\($0)" }
            ].compactMap { $0 }
        case "glob":
            return [
                inputValues["pattern"]?.stringValue.map { "pattern=\($0)" }
            ].compactMap { $0 }
        case "grep":
            return [
                inputValues["pattern"]?.stringValue.map { "pattern=\($0)" },
                inputValues["include"]?.stringValue.map { "include=\($0)" }
            ].compactMap { $0 }
        default:
            return []
        }
    }
}
