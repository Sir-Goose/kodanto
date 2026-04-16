import Foundation

struct ServerProfile: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable, Hashable {
        case localSidecar
        case remote
    }

    var id: UUID
    var name: String
    var kind: Kind
    var baseURL: String
    var username: String
    var password: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        baseURL: String,
        username: String = "opencode",
        password: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    var trimmedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBaseURL: String {
        let raw = trimmedBaseURL
        guard !raw.isEmpty else { return raw }
        let withScheme = raw.contains("://") ? raw : "http://\(raw)"
        return withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
    }

    var resolvedURL: URL? {
        URL(string: normalizedBaseURL)
    }

    var connectionTypeLabel: String {
        switch kind {
        case .localSidecar:
            return "Local Sidecar"
        case .remote:
            return "Remote Connection"
        }
    }

    var connectionKindLabel: String {
        switch kind {
        case .localSidecar:
            return "Local"
        case .remote:
            return "Remote"
        }
    }

    var connectionIconName: String {
        switch kind {
        case .localSidecar:
            return "desktopcomputer"
        case .remote:
            return "network"
        }
    }

    var connectionDetail: String {
        switch kind {
        case .localSidecar:
            return normalizedBaseURL
        case .remote:
            if let host = resolvedURL?.host, !host.isEmpty {
                return host
            }
            return normalizedBaseURL
        }
    }

    static func defaultName(for kind: Kind, baseURL: String) -> String {
        switch kind {
        case .localSidecar:
            return "Local Sidecar"
        case .remote:
            let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBaseURL.isEmpty else { return "Remote Connection" }
            let withScheme = trimmedBaseURL.contains("://") ? trimmedBaseURL : "http://\(trimmedBaseURL)"
            if let host = URL(string: withScheme)?.host, !host.isEmpty {
                return host
            }
            return "Remote Connection"
        }
    }

    static let localDefault = ServerProfile(
        name: "Local Sidecar",
        kind: .localSidecar,
        baseURL: "http://127.0.0.1:4096"
    )
}

struct OpenCodeHealth: Decodable {
    let healthy: Bool
    let version: String
}

struct OpenCodePathInfo: Decodable {
    let home: String
    let state: String
    let config: String
    let worktree: String
    let directory: String
}

struct OpenCodeConfig: Decodable {
    let model: String?
}

struct OpenCodeConfigProviders: Decodable {
    let providers: [Provider]
    let `default`: [String: String]

    struct Provider: Decodable {
        let id: String
        let name: String
        let models: [String: Model]
    }

    struct Model: Decodable {
        let id: String?
        let name: String?
        let status: String?
        let cost: ModelCost?
        let variants: [String: JSONValue]?
        let limit: ModelLimit?
    }

    struct ModelLimit: Decodable {
        let context: Int
        let input: Int?
        let output: Int
    }

    struct ModelCost: Decodable {
        let input: Double?
        let output: Double?
    }
}

struct OpenCodeAgent: Decodable, Identifiable, Hashable {
    let name: String
    let description: String?
    let mode: String
    let hidden: Bool?

    var id: String { name }

    var isPrimaryVisible: Bool {
        hidden != true && mode != "subagent"
    }
}

struct OpenCodeModelOption: Identifiable, Hashable {
    let providerID: String
    let providerName: String
    let modelID: String
    let modelName: String
    let status: String?
    let variants: [String]
    let contextLimit: Int?

    var id: String { "\(providerID)/\(modelID)" }

    var isDeprecated: Bool { status == "deprecated" }

    static func sortedVariantNames(_ names: [String]) -> [String] {
        let preferredOrder = [
            "thinking",
            "none",
            "minimal",
            "low",
            "medium",
            "high",
            "xhigh",
            "max"
        ]
        let preferredIndexes = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { ($1, $0) })

        return names.sorted { lhs, rhs in
            let lhsKey = lhs.lowercased()
            let rhsKey = rhs.lowercased()
            let lhsIndex = preferredIndexes[lhsKey]
            let rhsIndex = preferredIndexes[rhsKey]

            switch (lhsIndex, rhsIndex) {
            case let (lhsIndex?, rhsIndex?):
                return lhsIndex < rhsIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        }
    }

    nonisolated static func displayVariantName(_ variant: String) -> String {
        let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return variant }

        if trimmed.caseInsensitiveCompare("xhigh") == .orderedSame {
            return "Extra High"
        }

        let withSpaces = trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return withSpaces.capitalized
    }
}

struct OpenCodeModelProviderGroup: Identifiable, Hashable {
    let providerID: String
    let providerName: String
    let models: [OpenCodeModelOption]

    var id: String { providerID }
}

struct OpenCodeProject: Decodable, Identifiable, Hashable {
    struct ProjectIcon: Decodable, Hashable {
        let url: String?
        let override: String?
        let color: String?
    }

    struct ProjectCommands: Decodable, Hashable {
        let start: String?
    }

    struct ProjectTime: Decodable, Hashable {
        let created: Double
        let updated: Double
        let initialized: Double?
    }

    let id: String
    let worktree: String
    let vcs: String?
    let name: String?
    let icon: ProjectIcon?
    let commands: ProjectCommands?
    let time: ProjectTime
    let sandboxes: [String]

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return URL(fileURLWithPath: worktree).lastPathComponent
    }
}

struct OpenCodeSession: Decodable, Identifiable, Hashable {
    struct Summary: Decodable, Hashable {
        let additions: Int
        let deletions: Int
        let files: Int
    }

    struct Share: Decodable, Hashable {
        let url: String
    }

    struct Time: Decodable, Hashable {
        let created: Double
        let updated: Double
        let compacting: Double?
        let archived: Double?
    }

    struct Revert: Decodable, Hashable {
        let messageID: String
        let partID: String?
        let snapshot: String?
        let diff: String?
    }

    let id: String
    let slug: String
    let projectID: String
    let workspaceID: String?
    let directory: String
    let parentID: String?
    let summary: Summary?
    let share: Share?
    let title: String
    let version: String
    let time: Time
    let revert: Revert?

    var isArchived: Bool {
        time.archived != nil
    }
}

struct OpenCodeSessionShare: Decodable, Hashable {
    let url: String
}

struct OpenCodePTY: Decodable, Identifiable, Hashable {
    enum Status: String, Decodable, Hashable {
        case running
        case exited
    }

    let id: String
    let title: String
    let command: String
    let args: [String]
    let cwd: String
    let status: Status
    let pid: Int
}

struct OpenCodeTodo: Decodable, Hashable {
    let content: String
    let status: String
    let priority: String
}

struct OpenCodePermissionRequest: Decodable, Identifiable, Hashable {
    struct ToolInfo: Decodable, Hashable {
        let messageID: String
        let callID: String
    }

    let id: String
    let sessionID: String
    let permission: String
    let patterns: [String]
    let metadata: [String: JSONValue]
    let always: [String]
    let tool: ToolInfo?
}

struct OpenCodeQuestionRequest: Decodable, Identifiable, Hashable {
    struct Question: Decodable, Hashable, Identifiable {
        struct Option: Decodable, Hashable, Identifiable {
            var id: String { "\(label)|\(description)" }

            let label: String
            let description: String
        }

        var id: String { header }

        let question: String
        let header: String
        let options: [Option]
        let multiple: Bool?
        let custom: Bool?
    }

    struct ToolInfo: Decodable, Hashable {
        let messageID: String
        let callID: String
    }

    let id: String
    let sessionID: String
    let questions: [Question]
    let tool: ToolInfo?
}

struct OpenCodeSessionStatusMap: Decodable {
    let values: [String: OpenCodeSessionStatus]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: OpenCodeSessionStatus].self)
    }
}

enum SessionSidebarIndicatorState: Equatable {
    case none
    case running
    case completedUnread
}

struct SessionSidebarIndicatorStore {
    private var statesByDirectory: [String: [String: SessionSidebarIndicatorState]] = [:]

    func indicator(for sessionID: String, in directory: String) -> SessionSidebarIndicatorState {
        statesByDirectory[directory]?[sessionID] ?? .none
    }

    mutating func applyStatusMap(
        _ statuses: [String: OpenCodeSessionStatus],
        previousStatuses: [String: OpenCodeSessionStatus],
        sessionIDs: [String],
        in directory: String,
        selectedSessionID: String?,
        isSelectedDirectory: Bool
    ) {
        let validIDs = Set(sessionIDs)
        var states = statesByDirectory[directory] ?? [:]
        states = states.filter { validIDs.contains($0.key) }

        for sessionID in sessionIDs {
            let currentStatus = statuses[sessionID] ?? .idle
            let previousStatus = previousStatuses[sessionID]
            let isSelected = isSelectedDirectory && selectedSessionID == sessionID

            states[sessionID] = resolvedState(
                current: currentStatus,
                previous: previousStatus,
                existing: states[sessionID] ?? .none,
                isSelected: isSelected
            )
        }

        statesByDirectory[directory] = states.filter { $0.value != .none }
    }

    mutating func applyStatus(
        _ status: OpenCodeSessionStatus,
        previousStatus: OpenCodeSessionStatus?,
        sessionID: String,
        in directory: String,
        isSelected: Bool
    ) {
        var states = statesByDirectory[directory] ?? [:]
        let nextState = resolvedState(
            current: status,
            previous: previousStatus,
            existing: states[sessionID] ?? .none,
            isSelected: isSelected
        )

        if nextState == .none {
            states.removeValue(forKey: sessionID)
        } else {
            states[sessionID] = nextState
        }

        statesByDirectory[directory] = states
    }

    mutating func clearIndicator(for sessionID: String, in directory: String) {
        var states = statesByDirectory[directory] ?? [:]
        states.removeValue(forKey: sessionID)
        statesByDirectory[directory] = states
    }

    mutating func markUnread(for sessionID: String, in directory: String) {
        var states = statesByDirectory[directory] ?? [:]
        states[sessionID] = .completedUnread
        statesByDirectory[directory] = states
    }

    mutating func removeSession(_ sessionID: String, in directory: String) {
        clearIndicator(for: sessionID, in: directory)
    }

    mutating func reset() {
        statesByDirectory = [:]
    }

    private func resolvedState(
        current: OpenCodeSessionStatus,
        previous: OpenCodeSessionStatus?,
        existing: SessionSidebarIndicatorState,
        isSelected: Bool
    ) -> SessionSidebarIndicatorState {
        if current.isRunning {
            return .running
        }

        if isSelected {
            return .none
        }

        if previous?.isRunning == true {
            return .completedUnread
        }

        if existing == .completedUnread {
            return .completedUnread
        }

        return .none
    }
}

enum OpenCodeSessionStatus: Decodable, Hashable {
    case idle
    case busy
    case retry(attempt: Int, message: String, next: Double)

    enum CodingKeys: String, CodingKey {
        case type
        case attempt
        case message
        case next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "idle":
            self = .idle
        case "busy":
            self = .busy
        case "retry":
            self = .retry(
                attempt: try container.decode(Int.self, forKey: .attempt),
                message: try container.decode(String.self, forKey: .message),
                next: try container.decode(Double.self, forKey: .next)
            )
        default:
            self = .idle
        }
    }

}

extension OpenCodeSessionStatus {
    var isRunning: Bool {
        switch self {
        case .busy, .retry:
            return true
        case .idle:
            return false
        }
    }
}

struct OpenCodeMessageEnvelope: Decodable, Identifiable, Hashable {
    let info: OpenCodeMessage
    let parts: [OpenCodePart]

    var id: String { info.id }
}

enum OpenCodeMessage: Decodable, Identifiable, Hashable {
    case user(User)
    case assistant(Assistant)

    struct User: Decodable, Hashable {
        struct ModelRef: Decodable, Hashable {
            let providerID: String
            let modelID: String
        }

        struct Time: Decodable, Hashable {
            let created: Double
        }

        let id: String
        let sessionID: String
        let role: String
        let time: Time
        let agent: String
        let model: ModelRef
        let variant: String?
    }

    struct Assistant: Decodable, Hashable {
        struct Time: Decodable, Hashable {
            let created: Double
            let completed: Double?
        }

        struct PathInfo: Decodable, Hashable {
            let cwd: String
            let root: String
        }

        struct Tokens: Decodable, Hashable {
            struct Cache: Decodable, Hashable {
                let read: Int
                let write: Int
            }

            let total: Int?
            let input: Int
            let output: Int
            let reasoning: Int
            let cache: Cache
        }

        let id: String
        let sessionID: String
        let role: String
        let time: Time
        let parentID: String
        let modelID: String
        let providerID: String
        let mode: String
        let agent: String
        let path: PathInfo
        let summary: Bool?
        let cost: Double
        let tokens: Tokens
        let variant: String?
        let finish: String?
    }

    enum CodingKeys: String, CodingKey {
        case role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .role) {
        case "user":
            self = .user(try User(from: decoder))
        case "assistant":
            self = .assistant(try Assistant(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .role, in: container, debugDescription: "Unknown role")
        }
    }

    var id: String {
        switch self {
        case .user(let user):
            return user.id
        case .assistant(let assistant):
            return assistant.id
        }
    }

    var roleLabel: String {
        switch self {
        case .user:
            return "You"
        case .assistant:
            return "OpenCode"
        }
    }

    var sessionID: String {
        switch self {
        case .user(let user):
            return user.sessionID
        case .assistant(let assistant):
            return assistant.sessionID
        }
    }

    var createdAt: Double {
        switch self {
        case .user(let user):
            return user.time.created
        case .assistant(let assistant):
            return assistant.time.created
        }
    }
}

enum OpenCodePart: Decodable, Identifiable, Hashable {
    case text(Text)
    case reasoning(Reasoning)
    case tool(Tool)
    case file(File)
    case patch(Patch)
    case agent(Agent)
    case snapshot(Snapshot)
    case retry(Retry)
    case compaction(Compaction)
    case stepStart(StepStart)
    case stepFinish(StepFinish)
    case subtask(Subtask)
    case unknown(Unknown)

    struct Text: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let text: String
    }

    struct Reasoning: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let text: String
    }

    struct Tool: Decodable, Hashable {
        struct State: Decodable, Hashable {
            struct Time: Decodable, Hashable {
                let start: Double
                let end: Double?
                let compacted: Double?
            }

            let status: String
            let input: [String: JSONValue]?
            let raw: String?
            let title: String?
            let output: String?
            let error: String?
            let metadata: [String: JSONValue]?
            let time: Time?
        }

        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let callID: String
        let tool: String
        let state: State
    }

    struct File: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let mime: String
        let filename: String?
        let url: String
    }

    struct Patch: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let hash: String
        let files: [String]
    }

    struct Agent: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let name: String
    }

    struct Snapshot: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let snapshot: String
    }

    struct Retry: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let attempt: Int
    }

    struct Compaction: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let auto: Bool
        let overflow: Bool?
    }

    struct StepStart: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
    }

    struct StepFinish: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let reason: String
        let cost: Double
    }

    struct Subtask: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
        let prompt: String
        let description: String
        let agent: String
    }

    struct Unknown: Decodable, Hashable {
        let id: String
        let sessionID: String
        let messageID: String
        let type: String
    }

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try Text(from: decoder))
        case "reasoning":
            self = .reasoning(try Reasoning(from: decoder))
        case "tool":
            self = .tool(try Tool(from: decoder))
        case "file":
            self = .file(try File(from: decoder))
        case "patch":
            self = .patch(try Patch(from: decoder))
        case "agent":
            self = .agent(try Agent(from: decoder))
        case "snapshot":
            self = .snapshot(try Snapshot(from: decoder))
        case "retry":
            self = .retry(try Retry(from: decoder))
        case "compaction":
            self = .compaction(try Compaction(from: decoder))
        case "step-start":
            self = .stepStart(try StepStart(from: decoder))
        case "step-finish":
            self = .stepFinish(try StepFinish(from: decoder))
        case "subtask":
            self = .subtask(try Subtask(from: decoder))
        default:
            self = .unknown(try Unknown(from: decoder))
        }
    }

    var id: String {
        switch self {
        case .text(let value):
            return value.id
        case .reasoning(let value):
            return value.id
        case .tool(let value):
            return value.id
        case .file(let value):
            return value.id
        case .patch(let value):
            return value.id
        case .agent(let value):
            return value.id
        case .snapshot(let value):
            return value.id
        case .retry(let value):
            return value.id
        case .compaction(let value):
            return value.id
        case .stepStart(let value):
            return value.id
        case .stepFinish(let value):
            return value.id
        case .subtask(let value):
            return value.id
        case .unknown(let value):
            return value.id
        }
    }

    var summary: String {
        switch self {
        case .text(let value):
            return value.text
        case .reasoning(let value):
            return value.text
        case .tool(let value):
            return value.displayTitle
        case .file(let value):
            return value.filename ?? value.url
        case .patch(let value):
            return "Patch for \(value.files.count) files"
        case .agent(let value):
            return "Agent: \(value.name)"
        case .snapshot:
            return "Snapshot"
        case .retry(let value):
            return "Retry attempt \(value.attempt)"
        case .compaction:
            return "Compaction"
        case .stepStart:
            return "Step started"
        case .stepFinish(let value):
            return "Step finished: \(value.reason)"
        case .subtask(let value):
            return value.description
        case .unknown(let value):
            return value.type
        }
    }

    var reasoningHeading: String? {
        guard case .reasoning(let value) = self else { return nil }
        let text = value.text
        if let start = text.range(of: "**"),
           let end = text[start.upperBound...].range(of: "**") {
            let heading = text[start.upperBound..<end.lowerBound]
            return String(heading).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    var sessionID: String {
        switch self {
        case .text(let value):
            return value.sessionID
        case .reasoning(let value):
            return value.sessionID
        case .tool(let value):
            return value.sessionID
        case .file(let value):
            return value.sessionID
        case .patch(let value):
            return value.sessionID
        case .agent(let value):
            return value.sessionID
        case .snapshot(let value):
            return value.sessionID
        case .retry(let value):
            return value.sessionID
        case .compaction(let value):
            return value.sessionID
        case .stepStart(let value):
            return value.sessionID
        case .stepFinish(let value):
            return value.sessionID
        case .subtask(let value):
            return value.sessionID
        case .unknown(let value):
            return value.sessionID
        }
    }

    var messageID: String {
        switch self {
        case .text(let value):
            return value.messageID
        case .reasoning(let value):
            return value.messageID
        case .tool(let value):
            return value.messageID
        case .file(let value):
            return value.messageID
        case .patch(let value):
            return value.messageID
        case .agent(let value):
            return value.messageID
        case .snapshot(let value):
            return value.messageID
        case .retry(let value):
            return value.messageID
        case .compaction(let value):
            return value.messageID
        case .stepStart(let value):
            return value.messageID
        case .stepFinish(let value):
            return value.messageID
        case .subtask(let value):
            return value.messageID
        case .unknown(let value):
            return value.messageID
        }
    }

    var isVisibleInTranscript: Bool {
        switch self {
        case .stepStart, .stepFinish:
            return false
        default:
            return true
        }
    }

    func applyingDelta(field: String, delta: String) -> OpenCodePart? {
        switch self {
        case .text(let value) where field == "text":
            return .text(.init(
                id: value.id,
                sessionID: value.sessionID,
                messageID: value.messageID,
                type: value.type,
                text: value.text + delta
            ))
        case .reasoning(let value) where field == "text":
            return .reasoning(.init(
                id: value.id,
                sessionID: value.sessionID,
                messageID: value.messageID,
                type: value.type,
                text: value.text + delta
            ))
        default:
            return nil
        }
    }
}

extension OpenCodePart.Tool {
    var displayTitle: String {
        state.title ?? "Tool: \(tool)"
    }

    var command: String? {
        state.input?["command"]?.stringValue
    }
}

struct OpenCodeGlobalEvent: Decodable {
    let directory: String?
    let payload: OpenCodeEvent
}

enum OpenCodeEvent: Decodable {
    struct SessionInfoPayload: Decodable {
        let info: OpenCodeSession
    }

    struct SessionStatusPayload: Decodable {
        let sessionID: String
        let status: OpenCodeSessionStatus
    }

    struct TodoUpdatedPayload: Decodable {
        let sessionID: String
        let todos: [OpenCodeTodo]
    }

    struct MessageUpdatedPayload: Decodable {
        let info: OpenCodeMessage
    }

    struct MessageRemovedPayload: Decodable {
        let sessionID: String
        let messageID: String
    }

    struct MessagePartUpdatedPayload: Decodable {
        let part: OpenCodePart
    }

    struct MessagePartDeltaPayload: Decodable {
        let sessionID: String
        let messageID: String
        let partID: String
        let field: String
        let delta: String
    }

    struct MessagePartRemovedPayload: Decodable {
        let sessionID: String
        let messageID: String
        let partID: String
    }

    struct PTYInfoPayload: Decodable {
        let info: OpenCodePTY
    }

    struct PTYExitedPayload: Decodable {
        let id: String
        let exitCode: Int
    }

    struct PTYDeletedPayload: Decodable {
        let id: String
    }

    struct PermissionRepliedPayload: Decodable {
        let sessionID: String
        let requestID: String
        let reply: String
    }

    struct QuestionResolvedPayload: Decodable {
        let sessionID: String
        let requestID: String
    }

    case serverConnected
    case serverHeartbeat
    case globalDisposed
    case projectUpdated(OpenCodeProject)
    case sessionCreated(SessionInfoPayload)
    case sessionUpdated(SessionInfoPayload)
    case sessionDeleted(SessionInfoPayload)
    case sessionStatus(SessionStatusPayload)
    case todoUpdated(TodoUpdatedPayload)
    case messageUpdated(MessageUpdatedPayload)
    case messageRemoved(MessageRemovedPayload)
    case messagePartUpdated(MessagePartUpdatedPayload)
    case messagePartDelta(MessagePartDeltaPayload)
    case messagePartRemoved(MessagePartRemovedPayload)
    case ptyCreated(PTYInfoPayload)
    case ptyUpdated(PTYInfoPayload)
    case ptyExited(PTYExitedPayload)
    case ptyDeleted(PTYDeletedPayload)
    case permissionAsked(OpenCodePermissionRequest)
    case permissionReplied(PermissionRepliedPayload)
    case questionAsked(OpenCodeQuestionRequest)
    case questionReplied(QuestionResolvedPayload)
    case questionRejected(QuestionResolvedPayload)
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case type
        case properties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "server.connected":
            self = .serverConnected
        case "server.heartbeat":
            self = .serverHeartbeat
        case "global.disposed":
            self = .globalDisposed
        case "project.updated":
            self = .projectUpdated(try container.decode(OpenCodeProject.self, forKey: .properties))
        case "session.created":
            self = .sessionCreated(try container.decode(SessionInfoPayload.self, forKey: .properties))
        case "session.updated":
            self = .sessionUpdated(try container.decode(SessionInfoPayload.self, forKey: .properties))
        case "session.deleted":
            self = .sessionDeleted(try container.decode(SessionInfoPayload.self, forKey: .properties))
        case "session.status":
            self = .sessionStatus(try container.decode(SessionStatusPayload.self, forKey: .properties))
        case "todo.updated":
            self = .todoUpdated(try container.decode(TodoUpdatedPayload.self, forKey: .properties))
        case "message.updated":
            self = .messageUpdated(try container.decode(MessageUpdatedPayload.self, forKey: .properties))
        case "message.removed":
            self = .messageRemoved(try container.decode(MessageRemovedPayload.self, forKey: .properties))
        case "message.part.updated":
            self = .messagePartUpdated(try container.decode(MessagePartUpdatedPayload.self, forKey: .properties))
        case "message.part.delta":
            self = .messagePartDelta(try container.decode(MessagePartDeltaPayload.self, forKey: .properties))
        case "message.part.removed":
            self = .messagePartRemoved(try container.decode(MessagePartRemovedPayload.self, forKey: .properties))
        case "pty.created":
            self = .ptyCreated(try container.decode(PTYInfoPayload.self, forKey: .properties))
        case "pty.updated":
            self = .ptyUpdated(try container.decode(PTYInfoPayload.self, forKey: .properties))
        case "pty.exited":
            self = .ptyExited(try container.decode(PTYExitedPayload.self, forKey: .properties))
        case "pty.deleted":
            self = .ptyDeleted(try container.decode(PTYDeletedPayload.self, forKey: .properties))
        case "permission.asked":
            self = .permissionAsked(try container.decode(OpenCodePermissionRequest.self, forKey: .properties))
        case "permission.replied":
            self = .permissionReplied(try container.decode(PermissionRepliedPayload.self, forKey: .properties))
        case "question.asked":
            self = .questionAsked(try container.decode(OpenCodeQuestionRequest.self, forKey: .properties))
        case "question.replied":
            self = .questionReplied(try container.decode(QuestionResolvedPayload.self, forKey: .properties))
        case "question.rejected":
            self = .questionRejected(try container.decode(QuestionResolvedPayload.self, forKey: .properties))
        default:
            self = .unknown(type)
        }
    }
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard let numberValue else { return nil }
        return Int(numberValue)
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    func decoded<T: Decodable>(as type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct PromptRequestBody: Encodable {
    struct ModelSelection: Encodable {
        let providerID: String
        let modelID: String
    }

    struct Part: Encodable {
        let type: String
        let text: String
    }

    let model: ModelSelection?
    let agent: String?
    let variant: String?
    let parts: [Part]
}

struct PermissionReplyBody: Encodable {
    let reply: String
    let message: String?
}

struct QuestionReplyBody: Encodable {
    let answers: [[String]]
}
