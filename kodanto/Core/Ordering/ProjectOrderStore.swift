import Foundation

protocol ProjectOrderStoring {
    func load(for profileID: UUID) -> [String]
    func save(_ projectIDs: [String], for profileID: UUID)
    func remove(for profileID: UUID)
}

struct ProjectOrderStore: ProjectOrderStoring {
    private let key = "kodanto.projectOrderByProfile"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(for profileID: UUID) -> [String] {
        values()[profileID.uuidString] ?? []
    }

    func save(_ projectIDs: [String], for profileID: UUID) {
        let deduplicatedIDs = ProjectOrderResolver.deduplicatedProjectIDs(projectIDs)
        guard !deduplicatedIDs.isEmpty else { return }
        var updated = values()
        updated[profileID.uuidString] = deduplicatedIDs
        userDefaults.set(updated, forKey: key)
    }

    func remove(for profileID: UUID) {
        var updated = values()
        updated.removeValue(forKey: profileID.uuidString)
        userDefaults.set(updated, forKey: key)
    }

    private func values() -> [String: [String]] {
        userDefaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }
}
