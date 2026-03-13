import Foundation

struct TerminalLayoutState: Codable, Equatable {
    var isOpen: Bool
    var height: Double

    static let `default` = TerminalLayoutState(isOpen: false, height: 280)
}

protocol TerminalLayoutStoring {
    func load() -> TerminalLayoutState
    func save(_ state: TerminalLayoutState)
}

struct TerminalLayoutStore: TerminalLayoutStoring {
    private let key = "kodanto.terminalLayout.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> TerminalLayoutState {
        guard let data = userDefaults.data(forKey: key) else {
            return .default
        }

        return (try? JSONDecoder().decode(TerminalLayoutState.self, from: data)) ?? .default
    }

    func save(_ state: TerminalLayoutState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: key)
    }
}
