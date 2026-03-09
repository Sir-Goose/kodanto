import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class KodantoAppModel {
    struct DiagnosticsSnapshot {
        let serverURL: String
        let binaryPath: String
        let liveSyncState: String
        let reconnectCount: Int
        let lastEventDescription: String
        let lastError: String?
        let selectedProjectDirectory: String?
        let cachedProjects: Int
        let cachedSessions: Int
        let sidecarLog: String
    }

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected(version: String)
        case failed(String)
    }

    var profiles: [ServerProfile] = []
    var selectedProfileID: ServerProfile.ID?
    var connectionState: ConnectionState = .idle
    var projects: [OpenCodeProject] = []
    var selectedProjectID: OpenCodeProject.ID?
    var sessions: [OpenCodeSession] = []
    var selectedSessionID: OpenCodeSession.ID?
    var selectedSessionMessages: [OpenCodeMessageEnvelope] = []
    var sessionStatuses: [String: OpenCodeSessionStatus] = [:]
    var sessionTodos: [OpenCodeTodo] = []
    var permissions: [OpenCodePermissionRequest] = []
    var questions: [OpenCodeQuestionRequest] = []
    var availableModelGroups: [OpenCodeModelProviderGroup] = []
    var selectedModelID: String?
    var isLoadingModels = false
    var modelLoadError: String?
    var pathInfo: OpenCodePathInfo?
    var draftPrompt = ""
    var sidecarLog = ""
    var showingConnectionSheet = false
    var showingDiagnostics = false
    var lastSSEError: String?
    var loadingSessionDirectories: Set<String> = []

    private let sidecar = SidecarProcess()
    private let storage = ServerProfileStore()
    private let modelSelectionStore = ModelSelectionStore()
    private var globalEventTask: Task<Void, Never>?
    private var heartbeatWatchdogTask: Task<Void, Never>?
    private var liveSync = LiveSyncTracker()
    private var sessionMessagesByID: [String: OpenCodeMessage] = [:]
    private var messagePartsByMessageID: [String: [OpenCodePart]] = [:]
    private var sessionsByDirectory: [String: [OpenCodeSession]] = [:]
    private var sessionStatusesByDirectory: [String: [String: OpenCodeSessionStatus]] = [:]

    private let reconnectDelay: Duration = .milliseconds(250)

    init() {
        profiles = storage.load()
        if profiles.isEmpty {
            let local = Self.makeLocalProfile()
            profiles = [local]
            selectedProfileID = local.id
            storage.save(profiles)
        } else {
            selectedProfileID = profiles.first?.id
        }
        selectedModelID = selectedProfileID.flatMap { modelSelectionStore.load(for: $0) }

        sidecar.setOutputHandler { [weak self] line in
            guard let self else { return }
            self.sidecarLog.append(line)
            if self.sidecarLog.count > 12000 {
                self.sidecarLog = String(self.sidecarLog.suffix(12000))
            }
        }
    }

    var selectedProfile: ServerProfile? {
        profiles.first(where: { $0.id == selectedProfileID })
    }

    var selectedProject: OpenCodeProject? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    var selectedSession: OpenCodeSession? {
        sessions.first(where: { $0.id == selectedSessionID })
    }

    var selectedModel: OpenCodeModelOption? {
        availableModelGroups
            .flatMap(\.models)
            .first(where: { $0.id == selectedModelID })
    }

    var canCreateSession: Bool {
        selectedProject != nil && selectedProfile != nil
    }

    var canSendPrompt: Bool {
        selectedSession != nil && !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isLiveSyncActive: Bool {
        liveSync.state.isRunning
    }

    var liveSyncPhase: LiveSyncTracker.State {
        liveSync.state
    }

    var reconnectCount: Int {
        liveSync.reconnectCount
    }

    var diagnostics: DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            serverURL: selectedProfile?.normalizedBaseURL ?? "Not configured",
            binaryPath: (try? SidecarProcess.executablePath()) ?? "Not found",
            liveSyncState: liveSync.state.label,
            reconnectCount: reconnectCount,
            lastEventDescription: liveSync.lastEventAt == .distantPast ? "No events yet" : RelativeDateTimeFormatter().localizedString(for: liveSync.lastEventAt, relativeTo: .now),
            lastError: lastSSEError,
            selectedProjectDirectory: selectedProject?.worktree,
            cachedProjects: sessionsByDirectory.keys.count,
            cachedSessions: sessionsByDirectory.values.reduce(0) { $0 + $1.count },
            sidecarLog: sidecarLog
        )
    }

    func selectProfile(_ profileID: ServerProfile.ID) {
        stopLiveSync()
        selectedProfileID = profileID
        selectedModelID = modelSelectionStore.load(for: profileID)
        connectionState = .idle
        projects = []
        selectedProjectID = nil
        sessions = []
        selectedSessionID = nil
        selectedSessionMessages = []
        sessionTodos = []
        permissions = []
        questions = []
        availableModelGroups = []
        isLoadingModels = false
        modelLoadError = nil
        pathInfo = nil
        lastSSEError = nil
        liveSync = LiveSyncTracker()
        sessionsByDirectory = [:]
        sessionStatusesByDirectory = [:]
        loadingSessionDirectories = []
        resetMessageCaches()
    }

    func saveProfile(_ profile: ServerProfile) {
        var profile = profile
        if profile.kind == .localSidecar, profile.password?.isEmpty != false {
            profile.password = UUID().uuidString
        }

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        storage.save(profiles)
        selectedProfileID = profile.id
        selectedModelID = modelSelectionStore.load(for: profile.id)
    }

    func deleteProfile(_ profile: ServerProfile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        modelSelectionStore.remove(for: profile.id)
        if selectedProfileID == profile.id {
            selectedProfileID = profiles.first?.id
            selectedModelID = selectedProfileID.flatMap { modelSelectionStore.load(for: $0) }
        }
        storage.save(profiles)
    }

    func selectModel(_ modelID: String) {
        selectedModelID = modelID
        guard let profileID = selectedProfileID else { return }
        modelSelectionStore.save(modelID, for: profileID)
    }

    func connect() {
        Task {
            await connectSelectedProfile()
        }
    }

    func connectSelectedProfile() async {
        guard let profile = selectedProfile else { return }
        connectionState = .connecting
        stopLiveSync()

        do {
            let client = OpenCodeAPIClient(profile: profile)

            if profile.kind == .localSidecar {
                if (try? await client.health().healthy) != true {
                    try sidecar.start(profile: profile)
                    try await waitForServer(profile: profile)
                }
            }

            let health = try await client.health()
            connectionState = .connected(version: health.version)
            try await refreshAll(using: client)
            startLiveSync(for: profile)
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    func refresh() {
        Task {
            guard let profile = selectedProfile else { return }
            do {
                try await refreshAll(using: OpenCodeAPIClient(profile: profile))
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func sessions(for project: OpenCodeProject) -> [OpenCodeSession] {
        sessionsByDirectory[project.worktree] ?? []
    }

    func sessionStatus(for session: OpenCodeSession, in project: OpenCodeProject) -> OpenCodeSessionStatus? {
        sessionStatusesByDirectory[project.worktree]?[session.id]
    }

    func hasLoadedSessions(for project: OpenCodeProject) -> Bool {
        sessionsByDirectory[project.worktree] != nil
    }

    func isLoadingSessions(for project: OpenCodeProject) -> Bool {
        loadingSessionDirectories.contains(project.worktree)
    }

    func loadSessionsIfNeeded(for project: OpenCodeProject) {
        guard sessionsByDirectory[project.worktree] == nil,
              !loadingSessionDirectories.contains(project.worktree)
        else { return }

        Task {
            guard let profile = selectedProfile else { return }
            do {
                try await loadSessions(for: project, using: OpenCodeAPIClient(profile: profile))
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func createSession(in projectID: OpenCodeProject.ID) {
        Task {
            guard let profile = selectedProfile, let project = project(for: projectID) else { return }
            selectedProjectID = project.id
            applySelectedProjectCache()

            do {
                let client = OpenCodeAPIClient(profile: profile)
                let created = try await client.createSession(directory: project.worktree, title: nil)
                try await loadSessions(for: project, using: client)
                selectedSessionID = created.id
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func sendPrompt() {
        Task {
            guard let profile = selectedProfile, let project = selectedProject, let session = selectedSession else { return }
            let text = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            draftPrompt = ""

            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.sendPrompt(
                    sessionID: session.id,
                    directory: project.worktree,
                    text: text,
                    model: selectedModel.map {
                        PromptRequestBody.ModelSelection(providerID: $0.providerID, modelID: $0.modelID)
                    }
                )
                try await loadSessionDetail(using: client)
                try await loadSessions(for: project, using: client)
            } catch {
                draftPrompt = text
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func selectSession(_ sessionID: OpenCodeSession.ID, in projectID: OpenCodeProject.ID) {
        Task {
            guard let profile = selectedProfile, let project = project(for: projectID) else { return }
            selectedProjectID = project.id
            applySelectedProjectCache()
            selectedSessionID = sessionID

            do {
                let client = OpenCodeAPIClient(profile: profile)
                if sessionsByDirectory[project.worktree] == nil {
                    try await loadSessions(for: project, using: client)
                } else {
                    try await loadSessionDetail(using: client)
                }
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func respondToPermission(_ request: OpenCodePermissionRequest, reply: String) {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.replyToPermission(requestID: request.id, directory: project.worktree, reply: reply)
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func answerQuestion(_ request: OpenCodeQuestionRequest, answers: [[String]]) {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.replyToQuestion(requestID: request.id, directory: project.worktree, answers: answers)
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func rejectQuestion(_ request: OpenCodeQuestionRequest) {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.rejectQuestion(requestID: request.id, directory: project.worktree)
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func refreshAll(using client: OpenCodeAPIClient) async throws {
        async let pathInfoTask = client.pathInfo(directory: nil)
        async let projectsTask = client.projects()

        let resolvedPathInfo = try await pathInfoTask
        let loadedProjects = try await projectsTask.sorted { $0.time.updated > $1.time.updated }

        pathInfo = resolvedPathInfo
        projects = loadedProjects

        do {
            try await loadAvailableModels(using: client)
        } catch {
            availableModelGroups = []
            isLoadingModels = false
            modelLoadError = error.localizedDescription
        }

        if selectedProjectID == nil || !loadedProjects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = loadedProjects.first?.id
        }

        let projectsToRefresh = loadedProjects.filter { project in
            project.id == selectedProjectID || sessionsByDirectory[project.worktree] != nil
        }

        if projectsToRefresh.isEmpty {
            sessions = []
            sessionStatuses = [:]
            selectedSessionID = nil
            selectedSessionMessages = []
            sessionTodos = []
            permissions = []
            questions = []
            resetMessageCaches()
        } else {
            applySelectedProjectCache()
            for project in projectsToRefresh {
                try await loadSessions(for: project, using: client)
            }
        }
    }

    private func loadSessions(for project: OpenCodeProject, using client: OpenCodeAPIClient) async throws {
        loadingSessionDirectories.insert(project.worktree)
        defer { loadingSessionDirectories.remove(project.worktree) }

        async let sessionsTask = client.sessions(directory: project.worktree)
        async let statusesTask = client.sessionStatuses(directory: project.worktree)

        let loadedSessions = try await sessionsTask.sorted { $0.time.updated > $1.time.updated }
        let loadedStatuses = try await statusesTask

        sessionsByDirectory[project.worktree] = loadedSessions
        sessionStatusesByDirectory[project.worktree] = loadedStatuses

        guard selectedProjectID == project.id else { return }

        applySelectedProjectCache()

        if selectedSessionID == nil || !loadedSessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = loadedSessions.first?.id
        }

        try await loadSessionDetail(using: client)
    }

    private func loadSessionDetail(using client: OpenCodeAPIClient) async throws {
        guard let project = selectedProject else {
            selectedSessionMessages = []
            sessionTodos = []
            permissions = []
            questions = []
            return
        }

        async let permissionsTask = client.permissions(directory: project.worktree)
        async let questionsTask = client.questions(directory: project.worktree)

        permissions = try await permissionsTask
        questions = try await questionsTask

        guard let session = selectedSession else {
            resetMessageCaches()
            selectedSessionMessages = []
            sessionTodos = []
            return
        }

        async let messagesTask = client.messages(sessionID: session.id, directory: project.worktree)
        async let todosTask = client.sessionTodos(sessionID: session.id, directory: project.worktree)

        replaceMessages(try await messagesTask)
        sessionTodos = try await todosTask
    }

    private func startLiveSync(for profile: ServerProfile) {
        globalEventTask?.cancel()
        heartbeatWatchdogTask?.cancel()
        liveSync.start()
        lastSSEError = nil

        globalEventTask = Task { [weak self] in
            guard let self else { return }
            let client = OpenCodeAPIClient(profile: profile)

            while !Task.isCancelled {
                do {
                    let sse = OpenCodeSSEClient(profile: profile)
                    startHeartbeatWatchdog(for: profile)

                    for try await event in sse.streamGlobalEvents() {
                        if Task.isCancelled { return }
                        let shouldRefresh = liveSync.receiveEvent(event)
                        if shouldRefresh {
                            try await refreshAll(using: client)
                        }
                        applyGlobalEvent(event)
                    }

                    if !Task.isCancelled {
                        markLiveSyncReconnectNeeded("Live sync stream ended. Reconnecting...")
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    markLiveSyncReconnectNeeded(error.localizedDescription)
                }

                stopHeartbeatWatchdog()
                if Task.isCancelled { return }
                liveSync.start()
                try? await Task.sleep(for: reconnectDelay)
            }
        }
    }

    private func stopLiveSync() {
        globalEventTask?.cancel()
        globalEventTask = nil
        stopHeartbeatWatchdog()
        liveSync.stop()
    }

    private func startHeartbeatWatchdog(for profile: ServerProfile) {
        heartbeatWatchdogTask?.cancel()
        heartbeatWatchdogTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard liveSync.state.isRunning else { continue }
                guard liveSync.isHeartbeatTimedOut() else { continue }
                markLiveSyncReconnectNeeded("Heartbeat timed out")
                globalEventTask?.cancel()
                startLiveSync(for: profile)
                return
            }
        }
    }

    private func stopHeartbeatWatchdog() {
        heartbeatWatchdogTask?.cancel()
        heartbeatWatchdogTask = nil
    }

    private func markLiveSyncReconnectNeeded(_ reason: String) {
        lastSSEError = reason
        liveSync.markReconnectNeeded(reason: reason)
    }

    private func applyGlobalEvent(_ event: OpenCodeGlobalEvent) {
        let directory = event.directory ?? "global"

        switch event.payload {
        case .serverConnected:
            break
        case .serverHeartbeat:
            break
        case .globalDisposed:
            refresh()
        case .projectUpdated(let project):
            upsertProject(project)
        default:
            applyDirectoryEvent(event.payload, directory: directory)
        }
    }

    private func applyDirectoryEvent(_ event: OpenCodeEvent, directory: String) {
        switch event {
        case .sessionCreated(let payload):
            upsertSession(payload.info, directory: directory)
        case .sessionUpdated(let payload):
            upsertSession(payload.info, directory: directory)
        case .sessionDeleted(let payload):
            removeSession(payload.info, directory: directory)
        case .sessionStatus(let payload):
            upsertSessionStatus(payload.status, sessionID: payload.sessionID, directory: directory)
        case .todoUpdated(let payload):
            guard directoryMatchesSelection(directory), payload.sessionID == selectedSessionID else { return }
            sessionTodos = payload.todos
        case .messageUpdated(let payload):
            guard directoryMatchesSelection(directory) else { return }
            upsertMessage(payload.info)
        case .messageRemoved(let payload):
            guard directoryMatchesSelection(directory) else { return }
            removeMessage(sessionID: payload.sessionID, messageID: payload.messageID)
        case .messagePartUpdated(let payload):
            guard directoryMatchesSelection(directory) else { return }
            upsertPart(payload.part)
        case .messagePartDelta(let payload):
            guard directoryMatchesSelection(directory) else { return }
            applyPartDelta(payload)
        case .messagePartRemoved(let payload):
            guard directoryMatchesSelection(directory) else { return }
            removePart(messageID: payload.messageID, partID: payload.partID)
        case .permissionAsked(let payload):
            guard directoryMatchesSelection(directory) else { return }
            upsertPermission(payload)
        case .permissionReplied(let payload):
            guard directoryMatchesSelection(directory) else { return }
            removePermission(sessionID: payload.sessionID, requestID: payload.requestID)
        case .questionAsked(let payload):
            guard directoryMatchesSelection(directory) else { return }
            upsertQuestion(payload)
        case .questionReplied(let payload), .questionRejected(let payload):
            guard directoryMatchesSelection(directory) else { return }
            removeQuestion(sessionID: payload.sessionID, requestID: payload.requestID)
        default:
            break
        }
    }

    private func upsertProject(_ project: OpenCodeProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
            projects.sort { $0.time.updated > $1.time.updated }
        }
    }

    private func upsertSession(_ session: OpenCodeSession, directory: String) {
        var cached = sessionsByDirectory[directory] ?? []
        if let index = cached.firstIndex(where: { $0.id == session.id }) {
            cached[index] = session
        } else {
            cached.append(session)
        }

        cached.sort { $0.time.updated > $1.time.updated }
        sessionsByDirectory[directory] = cached

        if directoryMatchesSelection(directory) {
            applySelectedProjectCache()
            if selectedSessionID == nil {
                selectedSessionID = session.id
            }
        }
    }

    private func removeSession(_ session: OpenCodeSession, directory: String) {
        var cached = sessionsByDirectory[directory] ?? []
        cached.removeAll { $0.id == session.id }
        sessionsByDirectory[directory] = cached

        var cachedStatuses = sessionStatusesByDirectory[directory] ?? [:]
        cachedStatuses.removeValue(forKey: session.id)
        sessionStatusesByDirectory[directory] = cachedStatuses

        if directoryMatchesSelection(directory) {
            applySelectedProjectCache()
        }

        if selectedSessionID == session.id {
            selectedSessionID = sessions.first?.id
            if selectedSessionID == nil {
                resetMessageCaches()
                selectedSessionMessages = []
                sessionTodos = []
            } else {
                rebuildSelectedSessionMessages()
            }
        }
    }

    private func upsertSessionStatus(_ status: OpenCodeSessionStatus, sessionID: String, directory: String) {
        var cachedStatuses = sessionStatusesByDirectory[directory] ?? [:]
        cachedStatuses[sessionID] = status
        sessionStatusesByDirectory[directory] = cachedStatuses

        if directoryMatchesSelection(directory) {
            applySelectedProjectCache()
        }
    }

    private func replaceMessages(_ envelopes: [OpenCodeMessageEnvelope]) {
        resetMessageCaches()
        for envelope in envelopes {
            sessionMessagesByID[envelope.id] = envelope.info
            messagePartsByMessageID[envelope.id] = envelope.parts.sorted(by: sortParts)
        }
        rebuildSelectedSessionMessages()
    }

    private func upsertMessage(_ message: OpenCodeMessage) {
        guard message.sessionID == selectedSessionID else { return }
        sessionMessagesByID[message.id] = message
        if messagePartsByMessageID[message.id] == nil {
            messagePartsByMessageID[message.id] = []
        }
        rebuildSelectedSessionMessages()
    }

    private func removeMessage(sessionID: String, messageID: String) {
        guard sessionID == selectedSessionID else { return }
        sessionMessagesByID.removeValue(forKey: messageID)
        messagePartsByMessageID.removeValue(forKey: messageID)
        rebuildSelectedSessionMessages()
    }

    private func upsertPart(_ part: OpenCodePart) {
        guard part.sessionID == selectedSessionID else { return }
        var parts = messagePartsByMessageID[part.messageID] ?? []
        if let index = parts.firstIndex(where: { $0.id == part.id }) {
            parts[index] = part
        } else {
            parts.append(part)
        }
        messagePartsByMessageID[part.messageID] = parts.sorted(by: sortParts)
        rebuildSelectedSessionMessages()
    }

    private func applyPartDelta(_ payload: OpenCodeEvent.MessagePartDeltaPayload) {
        guard payload.sessionID == selectedSessionID else { return }
        guard var parts = messagePartsByMessageID[payload.messageID],
              let index = parts.firstIndex(where: { $0.id == payload.partID }),
              let updated = parts[index].applyingDelta(field: payload.field, delta: payload.delta)
        else { return }

        parts[index] = updated
        messagePartsByMessageID[payload.messageID] = parts
        rebuildSelectedSessionMessages()
    }

    private func removePart(messageID: String, partID: String) {
        guard var parts = messagePartsByMessageID[messageID] else { return }
        parts.removeAll { $0.id == partID }
        messagePartsByMessageID[messageID] = parts
        rebuildSelectedSessionMessages()
    }

    private func upsertPermission(_ request: OpenCodePermissionRequest) {
        guard request.sessionID == selectedSessionID else { return }
        if let index = permissions.firstIndex(where: { $0.id == request.id }) {
            permissions[index] = request
        } else {
            permissions.append(request)
        }
    }

    private func removePermission(sessionID: String, requestID: String) {
        guard sessionID == selectedSessionID else { return }
        permissions.removeAll { $0.id == requestID }
    }

    private func upsertQuestion(_ request: OpenCodeQuestionRequest) {
        guard request.sessionID == selectedSessionID else { return }
        if let index = questions.firstIndex(where: { $0.id == request.id }) {
            questions[index] = request
        } else {
            questions.append(request)
        }
    }

    private func removeQuestion(sessionID: String, requestID: String) {
        guard sessionID == selectedSessionID else { return }
        questions.removeAll { $0.id == requestID }
    }

    private func rebuildSelectedSessionMessages() {
        guard let selectedSessionID else {
            selectedSessionMessages = []
            return
        }

        selectedSessionMessages = sessionMessagesByID.values
            .filter { $0.sessionID == selectedSessionID }
            .sorted { $0.createdAt < $1.createdAt }
            .map { message in
                OpenCodeMessageEnvelope(
                    info: message,
                    parts: (messagePartsByMessageID[message.id] ?? []).sorted(by: sortParts)
                )
            }
    }

    private func resetMessageCaches() {
        sessionMessagesByID = [:]
        messagePartsByMessageID = [:]
    }

    private func project(for projectID: OpenCodeProject.ID) -> OpenCodeProject? {
        projects.first(where: { $0.id == projectID })
    }

    private func applySelectedProjectCache() {
        guard let selectedProject else {
            sessions = []
            sessionStatuses = [:]
            return
        }

        sessions = sessionsByDirectory[selectedProject.worktree] ?? []
        sessionStatuses = sessionStatusesByDirectory[selectedProject.worktree] ?? [:]
    }

    private func directoryMatchesSelection(_ directory: String) -> Bool {
        guard let selectedProject else { return false }
        return directory == selectedProject.worktree || directory == selectedProject.id
    }

    private func sortParts(_ lhs: OpenCodePart, _ rhs: OpenCodePart) -> Bool {
        lhs.id < rhs.id
    }

    private func waitForServer(profile: ServerProfile) async throws {
        let client = OpenCodeAPIClient(profile: profile)
        for _ in 0 ..< 50 {
            if let health = try? await client.health(), health.healthy {
                return
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw OpenCodeAPIError.serverError(statusCode: 0, message: "Timed out waiting for local opencode sidecar.")
    }

    static func makeLocalProfile() -> ServerProfile {
        var profile = ServerProfile.localDefault
        profile.password = UUID().uuidString
        return profile
    }

    private func loadAvailableModels(using client: OpenCodeAPIClient) async throws {
        isLoadingModels = true
        modelLoadError = nil
        defer { isLoadingModels = false }

        async let configTask = client.config(directory: nil)
        async let providersTask = client.configProviders(directory: nil)

        let config = try await configTask
        let providersResponse = try await providersTask
        applyAvailableModels(config: config, providersResponse: providersResponse)
    }

    private func applyAvailableModels(config: OpenCodeConfig, providersResponse: OpenCodeConfigProviders) {
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
                            modelName: (model.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? resolvedModelID
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

        availableModelGroups = groups.filter { !$0.models.isEmpty }

        let availableIDs = Set(availableModelGroups.flatMap(\.models).map(\.id))
        let storedModelID = selectedProfileID.flatMap { modelSelectionStore.load(for: $0) }
        let configuredModelID = normalizedModelIdentifier(config.model)
        let providerDefaultModelID = resolvedProviderDefaultModelID(from: providersResponse.default, groups: availableModelGroups)

        let resolvedSelection = [selectedModelID, storedModelID, configuredModelID, providerDefaultModelID, availableModelGroups.first?.models.first?.id]
            .compactMap { $0 }
            .first(where: { availableIDs.contains($0) })

        selectedModelID = resolvedSelection

        guard let profileID = selectedProfileID else { return }
        if let resolvedSelection {
            modelSelectionStore.save(resolvedSelection, for: profileID)
        } else {
            modelSelectionStore.remove(for: profileID)
        }
    }

    private func normalizedModelIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
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

private extension KodantoAppModel.ConnectionState {
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

private struct ServerProfileStore {
    private let key = "kodanto.serverProfiles"

    func load() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [ServerProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct ModelSelectionStore {
    private let key = "kodanto.selectedModelByProfile"

    func load(for profileID: UUID) -> String? {
        values()[profileID.uuidString]
    }

    func save(_ modelID: String, for profileID: UUID) {
        var updated = values()
        updated[profileID.uuidString] = modelID
        UserDefaults.standard.set(updated, forKey: key)
    }

    func remove(for profileID: UUID) {
        var updated = values()
        updated.removeValue(forKey: profileID.uuidString)
        UserDefaults.standard.set(updated, forKey: key)
    }

    private func values() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
