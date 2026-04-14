import Foundation

enum SlashCommandType: String, Codable, Equatable {
    case builtin
    case custom
}

enum SlashCommandSource: String, Codable, Equatable {
    case command
    case mcp
    case skill
}

enum SlashCommandAvailability: String, Codable, Equatable {
    case always
    case requiresSession
    case requiresSessionWithMessages
}

struct SlashCommand: Identifiable, Equatable, Hashable {
    let id: String
    let trigger: String
    let title: String
    let description: String?
    let keybind: String?
    let type: SlashCommandType
    let source: SlashCommandSource?
    let availability: SlashCommandAvailability

    static func == (lhs: SlashCommand, rhs: SlashCommand) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension SlashCommand {
    static let builtinCommands: [SlashCommand] = [
        SlashCommand(
            id: "session.new",
            trigger: "new",
            title: "New Session",
            description: "Start a new session",
            keybind: "⌘⇧S",
            type: .builtin,
            source: nil,
            availability: .always
        ),
        SlashCommand(
            id: "session.share",
            trigger: "share",
            title: "Share Session",
            description: "Share this session via link",
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .requiresSessionWithMessages
        ),
        SlashCommand(
            id: "session.unshare",
            trigger: "unshare",
            title: "Unshare Session",
            description: "Remove sharing link",
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .requiresSessionWithMessages
        ),
        SlashCommand(
            id: "session.undo",
            trigger: "undo",
            title: "Undo",
            description: "Remove the last message",
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .requiresSessionWithMessages
        ),
        SlashCommand(
            id: "session.redo",
            trigger: "redo",
            title: "Redo",
            description: "Restore the last undone message",
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .requiresSessionWithMessages
        ),
        SlashCommand(
            id: "session.compact",
            trigger: "compact",
            title: "Compact Session",
            description: "Reduce session size",
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .requiresSessionWithMessages
        ),
        SlashCommand(
            id: "session.fork",
            trigger: "fork",
            title: "Fork Session",
            description: "Create a copy of this session",
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .requiresSessionWithMessages
        ),
        SlashCommand(
            id: "terminal.toggle",
            trigger: "terminal",
            title: "Toggle Terminal",
            description: "Show or hide the terminal panel",
            keybind: "⌃`",
            type: .builtin,
            source: nil,
            availability: .always
        ),
        SlashCommand(
            id: "file.open",
            trigger: "open",
            title: "Open File",
            description: "Open a file from the project",
            keybind: "⌘K⌘P",
            type: .builtin,
            source: nil,
            availability: .always
        ),
        SlashCommand(
            id: "model.choose",
            trigger: "model",
            title: "Choose Model",
            description: "Select a different model",
            keybind: "⌘'",
            type: .builtin,
            source: nil,
            availability: .always
        ),
        SlashCommand(
            id: "agent.cycle",
            trigger: "agent",
            title: "Cycle Agent",
            description: "Switch to the next agent",
            keybind: "⌘.",
            type: .builtin,
            source: nil,
            availability: .always
        ),
        SlashCommand(
            id: "mcp.toggle",
            trigger: "mcp",
            title: "MCP Servers",
            description: "Configure MCP servers",
            keybind: "⌘;",
            type: .builtin,
            source: nil,
            availability: .always
        ),
    ]
}