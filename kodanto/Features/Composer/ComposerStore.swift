import Foundation
import Observation

struct ResolvedModelCatalog {
    let groups: [OpenCodeModelProviderGroup]
    let selectedModelID: String?
}

@MainActor
@Observable
final class ComposerStore {
    var availableModelGroups: [OpenCodeModelProviderGroup] = []
    var selectedModelID: String?
    var selectedModelVariant: String?
    var availablePrimaryAgents: [OpenCodeAgent] = []
    var selectedAgentName: String?
    var isLoadingModels = false
    var modelLoadError: String?
    var draftPrompt = ""

    private let modelSelectionStore: ModelSelectionStoring
    private let modelVariantSelectionStore: ModelVariantSelectionStoring
    private var selectedProfileID: UUID?
    private var lastSyncedAgentSessionID: String?
    private var lastSyncedAgentMessageID: String?

    init(
        modelSelectionStore: ModelSelectionStoring,
        modelVariantSelectionStore: ModelVariantSelectionStoring
    ) {
        self.modelSelectionStore = modelSelectionStore
        self.modelVariantSelectionStore = modelVariantSelectionStore
    }

    var selectedModel: OpenCodeModelOption? {
        availableModelGroups
            .flatMap(\.models)
            .first(where: { $0.id == selectedModelID })
    }

    var selectedModelSelection: PromptRequestBody.ModelSelection? {
        selectedModel.map {
            PromptRequestBody.ModelSelection(providerID: $0.providerID, modelID: $0.modelID)
        }
    }

    var selectedModelVariants: [String] {
        selectedModel?.variants ?? []
    }

    var selectedPromptVariant: String? {
        guard let selectedModel else { return nil }
        guard let selectedModelVariant else { return nil }
        guard selectedModel.variants.contains(selectedModelVariant) else { return nil }
        return selectedModelVariant
    }

    var selectedPromptAgent: String? {
        resolvedAgentSelection(selectedAgentName, availableAgents: availablePrimaryAgents)
    }

    func updateSelectedProfile(_ profileID: UUID?) {
        selectedProfileID = profileID
        selectedModelID = profileID.flatMap { modelSelectionStore.load(for: $0) }
        if let profileID, let selectedModelID {
            selectedModelVariant = modelVariantSelectionStore.load(for: profileID, modelID: selectedModelID)
        } else {
            selectedModelVariant = nil
        }
        availableModelGroups = []
        availablePrimaryAgents = []
        selectedAgentName = nil
        lastSyncedAgentSessionID = nil
        lastSyncedAgentMessageID = nil
        isLoadingModels = false
        modelLoadError = nil
    }

    func clearModelCatalog() {
        availableModelGroups = []
        availablePrimaryAgents = []
        selectedAgentName = nil
        lastSyncedAgentSessionID = nil
        lastSyncedAgentMessageID = nil
        isLoadingModels = false
        modelLoadError = nil
    }

    func selectModel(_ modelID: String) {
        selectedModelID = modelID
        guard let profileID = selectedProfileID else { return }
        modelSelectionStore.save(modelID, for: profileID)
        if let option = availableModelGroups.flatMap(\.models).first(where: { $0.id == modelID }) {
            let storedVariant = modelVariantSelectionStore.load(for: profileID, modelID: modelID)
            selectedModelVariant = resolvedModelVariantSelection(storedVariant, availableVariants: option.variants)
        } else {
            selectedModelVariant = nil
        }
    }

    func selectModelVariant(_ variant: String?) {
        let normalizedVariant = resolvedModelVariantSelection(variant, availableVariants: selectedModelVariants)
        selectedModelVariant = normalizedVariant

        guard let profileID = selectedProfileID, let selectedModelID else { return }
        if let normalizedVariant {
            modelVariantSelectionStore.save(normalizedVariant, for: profileID, modelID: selectedModelID)
        } else {
            modelVariantSelectionStore.remove(for: profileID, modelID: selectedModelID)
        }
    }

    func selectAgent(_ agentName: String?) {
        selectedAgentName = resolvedAgentSelection(agentName, availableAgents: availablePrimaryAgents)
            ?? availablePrimaryAgents.first?.name
    }

    func syncSelectedAgent(from messages: [OpenCodeMessageEnvelope], sessionID: String?) {
        guard let sessionID else {
            lastSyncedAgentSessionID = nil
            lastSyncedAgentMessageID = nil
            return
        }

        guard let latestUser = latestUserMessage(in: messages) else {
            lastSyncedAgentSessionID = sessionID
            lastSyncedAgentMessageID = nil
            return
        }

        let didSessionChange = lastSyncedAgentSessionID != sessionID
        let didLatestUserMessageChange = lastSyncedAgentMessageID != latestUser.id
        guard didSessionChange || didLatestUserMessageChange else { return }

        selectedAgentName = resolvedAgentSelection(latestUser.agent, availableAgents: availablePrimaryAgents)
            ?? resolvedAgentSelection(selectedAgentName, availableAgents: availablePrimaryAgents)
            ?? availablePrimaryAgents.first?.name
        lastSyncedAgentSessionID = sessionID
        lastSyncedAgentMessageID = latestUser.id
    }

    func refreshModelCatalog(using client: OpenCodeAPIService) async throws {
        isLoadingModels = true
        modelLoadError = nil
        defer { isLoadingModels = false }

        async let configTask = client.config(directory: nil)
        async let providersTask = client.configProviders(directory: nil)

        let config = try await configTask
        let providersResponse = try await providersTask
        applyModelCatalog(resolvedModelCatalog(config: config, providersResponse: providersResponse))
        let agents = (try? await client.agents()) ?? []
        applyAgentCatalog(agents.filter(\.isPrimaryVisible))
    }

    func submitPrompt(
        using client: OpenCodeAPIService,
        project: OpenCodeProject,
        session: OpenCodeSession,
        reload: @escaping () async throws -> Void
    ) async throws {
        let text = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftPrompt = ""

        do {
            try await client.sendPrompt(
                sessionID: session.id,
                directory: project.worktree,
                text: text,
                model: selectedModelSelection,
                agent: selectedPromptAgent,
                variant: selectedPromptVariant
            )
            try await reload()
        } catch {
            draftPrompt = text
            throw error
        }
    }

    private func resolvedModelCatalog(
        config: OpenCodeConfig,
        providersResponse: OpenCodeConfigProviders
    ) -> ResolvedModelCatalog {
        let groups = providersResponse.providers
            .map { provider in
                OpenCodeModelProviderGroup(
                    providerID: provider.id,
                    providerName: provider.name,
                    models: provider.models.map { key, model in
                        let resolvedModelID = (model.id ?? key).trimmingCharacters(in: .whitespacesAndNewlines)
                        return OpenCodeModelOption(
                            providerID: provider.id,
                            providerName: provider.name,
                            modelID: resolvedModelID,
                            modelName: (model.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? resolvedModelID,
                            variants: OpenCodeModelOption.sortedVariantNames(model.variants.map { Array($0.keys) } ?? [])
                        )
                    }
                    .sorted {
                        if $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedSame {
                            return $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending
                        }
                        return $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending
            }
            .filter { !$0.models.isEmpty }

        let availableIDs = Set(groups.flatMap { $0.models }.map { $0.id })
        let storedModelID = selectedProfileID.flatMap { modelSelectionStore.load(for: $0) }
        let configuredModelID = normalizedModelIdentifier(config.model)
        let providerDefaultModelID = resolvedProviderDefaultModelID(from: providersResponse.default, groups: groups)

        let resolvedSelection = [selectedModelID, storedModelID, configuredModelID, providerDefaultModelID, groups.first?.models.first?.id]
            .compactMap { $0 }
            .first(where: { availableIDs.contains($0) })

        return ResolvedModelCatalog(groups: groups, selectedModelID: resolvedSelection)
    }

    private func applyModelCatalog(_ catalog: ResolvedModelCatalog) {
        let previousSelectedModelID = selectedModelID

        if availableModelGroups != catalog.groups {
            availableModelGroups = catalog.groups
        }

        if selectedModelID != catalog.selectedModelID {
            selectedModelID = catalog.selectedModelID
        }

        guard let profileID = selectedProfileID else { return }
        if let selectedModelID = catalog.selectedModelID {
            modelSelectionStore.save(selectedModelID, for: profileID)

            let availableVariants = catalog.groups
                .flatMap { $0.models }
                .first(where: { $0.id == selectedModelID })?
                .variants ?? []
            let storedVariant = modelVariantSelectionStore.load(for: profileID, modelID: selectedModelID)

            if previousSelectedModelID == selectedModelID {
                selectedModelVariant = resolvedModelVariantSelection(selectedModelVariant, availableVariants: availableVariants)
                    ?? resolvedModelVariantSelection(storedVariant, availableVariants: availableVariants)
            } else {
                selectedModelVariant = resolvedModelVariantSelection(storedVariant, availableVariants: availableVariants)
            }
        } else {
            modelSelectionStore.remove(for: profileID)
            selectedModelVariant = nil
        }
    }

    private func applyAgentCatalog(_ agents: [OpenCodeAgent]) {
        if availablePrimaryAgents != agents {
            availablePrimaryAgents = agents
        }

        selectedAgentName = resolvedAgentSelection(selectedAgentName, availableAgents: agents)
            ?? agents.first?.name
    }

    private func normalizedModelIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func resolvedModelVariantSelection(_ value: String?, availableVariants: [String]) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        guard availableVariants.contains(value) else { return nil }
        return value
    }

    private func resolvedAgentSelection(_ value: String?, availableAgents: [OpenCodeAgent]) -> String? {
        guard let value = normalizedAgentName(value) else { return nil }
        guard availableAgents.contains(where: { $0.name == value }) else { return nil }
        return value
    }

    private func normalizedAgentName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func latestUserMessage(in messages: [OpenCodeMessageEnvelope]) -> OpenCodeMessage.User? {
        for envelope in messages.reversed() {
            guard case .user(let user) = envelope.info else { continue }
            return user
        }
        return nil
    }

    private func resolvedProviderDefaultModelID(
        from defaults: [String: String],
        groups: [OpenCodeModelProviderGroup]
    ) -> String? {
        for group in groups {
            guard let candidate = defaults[group.providerID]?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
                continue
            }

            if candidate.contains("/"), group.models.contains(where: { $0.id == candidate }) {
                return candidate
            }

            if let match = group.models.first(where: { $0.modelID == candidate }) {
                return match.id
            }
        }

        return nil
    }
}
