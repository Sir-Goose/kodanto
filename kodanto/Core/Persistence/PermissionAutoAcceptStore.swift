import Foundation

protocol PermissionAutoAcceptStoring {
    func load() -> [String: Bool]
    func save(_ values: [String: Bool])
}

struct PermissionAutoAcceptStore: PermissionAutoAcceptStoring {
    private let key = "kodanto.permissionAutoAccept"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [String: Bool] {
        userDefaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
    }

    func save(_ values: [String: Bool]) {
        userDefaults.set(values, forKey: key)
    }

    static func makeKey(sessionID: String, directory: String) -> String {
        "\(directory)|\(sessionID)"
    }

    static func makeDirectoryKey(directory: String) -> String {
        "\(directory)|*"
    }
}
