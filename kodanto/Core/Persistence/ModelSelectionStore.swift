import Foundation

protocol ModelSelectionStoring {
    func load(for profileID: UUID) -> String?
    func save(_ modelID: String, for profileID: UUID)
    func remove(for profileID: UUID)
}

struct ModelSelectionStore: ModelSelectionStoring {
    private let key = "kodanto.selectedModelByProfile"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(for profileID: UUID) -> String? {
        values()[profileID.uuidString]
    }

    func save(_ modelID: String, for profileID: UUID) {
        var updated = values()
        updated[profileID.uuidString] = modelID
        userDefaults.set(updated, forKey: key)
    }

    func remove(for profileID: UUID) {
        var updated = values()
        updated.removeValue(forKey: profileID.uuidString)
        userDefaults.set(updated, forKey: key)
    }

    private func values() -> [String: String] {
        userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
