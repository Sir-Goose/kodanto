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

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .busy:
            return "Busy"
        case .retry(let attempt, _, _):
            return "Retry \(attempt)"
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
            let status: String
            let title: String?
            let output: String?
            let error: String?
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
            return value.state.title ?? "Tool: \(value.tool)"
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

struct PromptRequestBody: Encodable {
    struct Part: Encodable {
        let type: String
        let text: String
    }

    let parts: [Part]
}

struct PermissionReplyBody: Encodable {
    let reply: String
    let message: String?
}

struct QuestionReplyBody: Encodable {
    let answers: [[String]]
}
