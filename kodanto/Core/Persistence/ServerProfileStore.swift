import Foundation

protocol ServerProfileStoring {
    func load() -> [ServerProfile]
    func save(_ profiles: [ServerProfile])
}

struct ServerProfileStore: ServerProfileStoring {
    private let key = "kodanto.serverProfiles"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [ServerProfile] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [ServerProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        userDefaults.set(data, forKey: key)
    }
}
