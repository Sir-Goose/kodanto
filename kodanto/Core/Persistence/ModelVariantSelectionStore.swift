import Foundation

protocol ModelVariantSelectionStoring {
    func load(for profileID: UUID, modelID: String) -> String?
    func save(_ variant: String, for profileID: UUID, modelID: String)
    func remove(for profileID: UUID, modelID: String)
    func remove(for profileID: UUID)
}

struct ModelVariantSelectionStore: ModelVariantSelectionStoring {
    private let key = "kodanto.selectedModelVariantByProfile"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(for profileID: UUID, modelID: String) -> String? {
        values()[profileID.uuidString]?[modelID]
    }

    func save(_ variant: String, for profileID: UUID, modelID: String) {
        var updated = values()
        var profileValues = updated[profileID.uuidString] ?? [:]
        profileValues[modelID] = variant
        updated[profileID.uuidString] = profileValues
        userDefaults.set(updated, forKey: key)
    }

    func remove(for profileID: UUID, modelID: String) {
        var updated = values()
        var profileValues = updated[profileID.uuidString] ?? [:]
        profileValues.removeValue(forKey: modelID)
        updated[profileID.uuidString] = profileValues.isEmpty ? nil : profileValues
        userDefaults.set(updated, forKey: key)
    }

    func remove(for profileID: UUID) {
        var updated = values()
        updated.removeValue(forKey: profileID.uuidString)
        userDefaults.set(updated, forKey: key)
    }

    private func values() -> [String: [String: String]] {
        userDefaults.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
    }
}
