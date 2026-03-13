import Foundation

struct TerminalResumeState: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let ptyID: String
    let cursor: Int
    let buffer: String

    init(ptyID: String, cursor: Int, buffer: String, version: Int = TerminalResumeState.currentVersion) {
        self.version = version
        self.ptyID = ptyID
        self.cursor = cursor
        self.buffer = buffer
    }
}

protocol TerminalResumeStateStoring {
    func load(profileID: UUID, directory: String) -> TerminalResumeState?
    func save(_ state: TerminalResumeState, profileID: UUID, directory: String)
    func remove(profileID: UUID, directory: String)
}

struct TerminalResumeStateStore: TerminalResumeStateStoring {
    private let key = "kodanto.terminalResumeByProfileAndDirectory.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(profileID: UUID, directory: String) -> TerminalResumeState? {
        let map = values()
        guard let state = map[scopeKey(profileID: profileID, directory: directory)] else {
            return nil
        }
        guard state.version == TerminalResumeState.currentVersion else {
            return nil
        }
        return state
    }

    func save(_ state: TerminalResumeState, profileID: UUID, directory: String) {
        guard state.version == TerminalResumeState.currentVersion else { return }
        var updated = values()
        updated[scopeKey(profileID: profileID, directory: directory)] = state
        persist(updated)
    }

    func remove(profileID: UUID, directory: String) {
        var updated = values()
        updated.removeValue(forKey: scopeKey(profileID: profileID, directory: directory))
        persist(updated)
    }

    private func values() -> [String: TerminalResumeState] {
        guard let data = userDefaults.data(forKey: key) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: TerminalResumeState].self, from: data)) ?? [:]
    }

    private func persist(_ values: [String: TerminalResumeState]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        userDefaults.set(data, forKey: key)
    }

    private func scopeKey(profileID: UUID, directory: String) -> String {
        "\(profileID.uuidString)::\(NSString(string: directory).standardizingPath)"
    }
}
