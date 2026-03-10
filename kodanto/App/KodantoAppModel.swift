import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class KodantoAppModel {
    struct SessionNavigationTarget: Hashable {
        let projectID: OpenCodeProject.ID
        let sessionID: OpenCodeSession.ID
    }

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

    private enum RefreshScope {
        case full
        case liveData

        var includesModelCatalog: Bool {
            self == .full
        }
    }

    var profiles: [ServerProfile] = []
    var selectedProfileID: ServerProfile.ID?
    var connectionState: ConnectionState = .idle
    var projects: [OpenCodeProject] = []
    var selectedProjectID: OpenCodeProject.ID?
    var sessions: [OpenCodeSession] = []
    var selectedSessionID: OpenCodeSession.ID?
    var selectedSessionMessages: [OpenCodeMessageEnvelope] = []
    var selectedSessionTranscriptRevision = 0
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
    var showingConnectionsManager = false
    var showingDiagnostics = false
    var lastSSEError: String?
    var loadingSessionDirectories: Set<String> = []

    private let sidecar = SidecarProcess()
    private let storage = ServerProfileStore()
    private let modelSelectionStore = ModelSelectionStore()
    private let projectOrderStore = ProjectOrderStore()
    private var globalEventTask: Task<Void, Never>?
    private var heartbeatWatchdogTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var liveSync = LiveSyncTracker()
    private var sessionMessagesByID: [String: OpenCodeMessage] = [:]
    private var messagePartsByMessageID: [String: [OpenCodePart]] = [:]
    private var sessionsByDirectory: [String: [OpenCodeSession]] = [:]
    private var sessionStatusesByDirectory: [String: [String: OpenCodeSessionStatus]] = [:]
    private var sessionSidebarIndicators = SessionSidebarIndicatorStore()

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

    func loadedSessionNavigationTarget(for sessionID: OpenCodeSession.ID) -> SessionNavigationTarget? {
        guard let location = SessionNavigationTargetResolver.resolve(
            sessionID: sessionID,
            projects: projects,
            sessionsByDirectory: sessionsByDirectory
        ) else { return nil }

        return SessionNavigationTarget(projectID: location.projectID, sessionID: location.sessionID)
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

    var canCreateSession: Bool {
        selectedProject != nil && selectedProfile != nil
    }

    var canSendPrompt: Bool {
        selectedSession != nil && !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canRefresh: Bool {
        connectionState.isConnected
    }

    var canConnect: Bool {
        switch connectionState {
        case .idle, .failed:
            return true
        case .connecting, .connected:
            return false
        }
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

    var isSelectedSessionRunning: Bool {
        guard let selectedProject, let selectedSessionID else { return false }
        guard let status = sessionStatusesByDirectory[selectedProject.worktree]?[selectedSessionID] else {
            return false
        }

        switch status {
        case .busy, .retry:
            return true
        case .idle:
            return false
        }
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

    func selectProfile(_ profileID: ServerProfile.ID, forceReset: Bool = false) {
        guard forceReset || selectedProfileID != profileID else { return }
        connectTask?.cancel()
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
        sessionSidebarIndicators.reset()
        loadingSessionDirectories = []
        resetMessageCaches()
    }

    func saveProfile(_ profile: ServerProfile, selectAfterSave: Bool = true) {
        var profile = profile
        if profile.kind == .localSidecar, profile.password?.isEmpty != false {
            profile.password = UUID().uuidString
        }

        let existingProfile = profiles.first(where: { $0.id == profile.id })
        let shouldResetSelectedProfile = selectedProfileID == profile.id && existingProfile != profile
        let shouldResetSelection = selectAfterSave || shouldResetSelectedProfile

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        storage.save(profiles)

        if shouldResetSelection {
            selectProfile(profile.id, forceReset: true)
        }
    }

    func deleteProfile(_ profile: ServerProfile) {
        guard profiles.count > 1 else { return }

        let isDeletingSelectedProfile = selectedProfileID == profile.id
        let fallbackProfileID = isDeletingSelectedProfile
            ? profiles.first(where: { $0.id != profile.id })?.id
            : nil

        profiles.removeAll { $0.id == profile.id }
        modelSelectionStore.remove(for: profile.id)
        projectOrderStore.remove(for: profile.id)
        storage.save(profiles)

        if let fallbackProfileID {
            selectProfile(fallbackProfileID, forceReset: true)
        }
    }

    func selectModel(_ modelID: String) {
        selectedModelID = modelID
        guard let profileID = selectedProfileID else { return }
        modelSelectionStore.save(modelID, for: profileID)
    }

    func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard projects.count > 1 else { return }

        var reorderedProjects = projects
        reorderedProjects.moveItems(fromOffsets: source, toOffset: destination)
        reorderedProjects = ProjectOrderResolver.deduplicatedProjects(reorderedProjects)

        guard reorderedProjects != projects else { return }

        projects = reorderedProjects
        persistProjectOrder()
    }

    func moveProject(
        _ projectID: OpenCodeProject.ID,
        relativeTo targetProjectID: OpenCodeProject.ID,
        placement: ProjectDropPlacement
    ) {
        let reorderedProjects = ProjectOrderResolver.reorderedProjects(
            projects,
            movingProjectID: projectID,
            relativeTo: targetProjectID,
            placement: placement
        )

        guard reorderedProjects != projects else { return }

        projects = reorderedProjects
        persistProjectOrder()
    }

    func sanitizeProjects() {
        let sanitizedProjects = resolvedProjectOrder(for: projects)
        let previousProjects = projects

        if sanitizedProjects != projects {
            projects = sanitizedProjects
            reconcileSelectedProject(previousProjects: previousProjects, updatedProjects: sanitizedProjects, selectingFirstProjectIfNeeded: true)
        }

        persistProjectOrder()
    }

    func connect() {
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.connectSelectedProfile()
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
            try await refreshAll(using: client, scope: .full)
            startLiveSync(for: profile)
        } catch is CancellationError {
            return
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    func refresh() {
        Task {
            guard let profile = selectedProfile else { return }
            guard canRefresh else { return }
            do {
                try await refreshAll(using: OpenCodeAPIClient(profile: profile), scope: .full)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func sessions(for project: OpenCodeProject) -> [OpenCodeSession] {
        sessionsByDirectory[project.worktree] ?? []
    }

    func sessionSidebarIndicator(for session: OpenCodeSession, in project: OpenCodeProject) -> SessionSidebarIndicatorState {
        sessionSidebarIndicators.indicator(for: session.id, in: project.worktree)
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
                    model: selectedModelSelection
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
        guard let profile = selectedProfile, let project = project(for: projectID) else { return }

        let isSwitchingSessions = selectedSessionID != sessionID || selectedProjectID != project.id
        selectedProjectID = project.id
        applySelectedProjectCache()
        selectedSessionID = sessionID
        sessionSidebarIndicators.clearIndicator(for: sessionID, in: project.worktree)

        if isSwitchingSessions {
            resetMessageCaches()
            selectedSessionMessages = []
            selectedSessionTranscriptRevision &+= 1
            sessionTodos = []
            permissions = []
            questions = []
        }

        Task {
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

    private func refreshAll(using client: OpenCodeAPIClient, scope: RefreshScope) async throws {
        async let pathInfoTask = client.pathInfo(directory: nil)
        async let projectsTask = client.projects()

        let resolvedPathInfo = try await pathInfoTask
        let loadedProjects = resolvedProjectOrder(for: try await projectsTask)
        let previousProjects = projects

        pathInfo = resolvedPathInfo
        projects = loadedProjects
        reconcileSelectedProject(previousProjects: previousProjects, updatedProjects: loadedProjects, selectingFirstProjectIfNeeded: true)
        persistProjectOrder()

        if scope.includesModelCatalog {
            do {
                try await refreshModelCatalog(using: client)
            } catch {
                modelLoadError = error.localizedDescription
                isLoadingModels = false
            }
        }

        let projectsToRefresh = loadedProjects.filter { project in
            project.id == selectedProjectID || sessionsByDirectory[project.worktree] != nil
        }

        if projectsToRefresh.isEmpty {
            sessions = []
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

        let previousStatuses = sessionStatusesByDirectory[project.worktree] ?? [:]

        sessionsByDirectory[project.worktree] = loadedSessions
        sessionStatusesByDirectory[project.worktree] = loadedStatuses
        sessionSidebarIndicators.applyStatusMap(
            loadedStatuses,
            previousStatuses: previousStatuses,
            sessionIDs: loadedSessions.map(\.id),
            in: project.worktree,
            selectedSessionID: selectedSessionID,
            isSelectedDirectory: selectedProjectID == project.id
        )

        guard selectedProjectID == project.id else { return }

        applySelectedProjectCache()

        if selectedSessionID == nil || !loadedSessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = loadedSessions.first?.id
            if let selectedSessionID {
                sessionSidebarIndicators.clearIndicator(for: selectedSessionID, in: project.worktree)
            }
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
                            try await refreshAll(using: client, scope: .liveData)
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
        var updatedProjects = projects
        let previousProjects = projects

        if let index = updatedProjects.firstIndex(where: { $0.id == project.id }) {
            updatedProjects[index] = project
        } else {
            updatedProjects.append(project)
        }

        projects = resolvedProjectOrder(for: updatedProjects)
        reconcileSelectedProject(previousProjects: previousProjects, updatedProjects: projects, selectingFirstProjectIfNeeded: true)
        persistProjectOrder()
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
        sessionSidebarIndicators.removeSession(session.id, in: directory)

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
        let previousStatus = cachedStatuses[sessionID]
        cachedStatuses[sessionID] = status
        sessionStatusesByDirectory[directory] = cachedStatuses
        sessionSidebarIndicators.applyStatus(
            status,
            previousStatus: previousStatus,
            sessionID: sessionID,
            in: directory,
            isSelected: directoryMatchesSelection(directory) && selectedSessionID == sessionID
        )

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
            selectedSessionTranscriptRevision &+= 1
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
        selectedSessionTranscriptRevision &+= 1
    }

    private func resetMessageCaches() {
        sessionMessagesByID = [:]
        messagePartsByMessageID = [:]
    }

    private func project(for projectID: OpenCodeProject.ID) -> OpenCodeProject? {
        projects.first(where: { $0.id == projectID })
    }

    private func resolvedProjectOrder(for projects: [OpenCodeProject]) -> [OpenCodeProject] {
        let storedProjectReferences = selectedProfileID.map { projectOrderStore.load(for: $0) } ?? []
        return ProjectOrderResolver.orderedProjects(projects, storedIDs: storedProjectReferences)
    }

    private func persistProjectOrder() {
        guard let selectedProfileID else { return }
        let storedProjectReferences = ProjectOrderResolver.storedProjectReferences(for: projects)
        guard !storedProjectReferences.isEmpty else { return }
        projectOrderStore.save(storedProjectReferences, for: selectedProfileID)
    }

    private func applySelectedProjectCache() {
        guard let selectedProject else {
            sessions = []
            return
        }

        sessions = sessionsByDirectory[selectedProject.worktree] ?? []
    }

    private func directoryMatchesSelection(_ directory: String) -> Bool {
        guard let selectedProject else { return false }
        return directory == selectedProject.worktree || directory == selectedProject.id
    }

    private func sortParts(_ lhs: OpenCodePart, _ rhs: OpenCodePart) -> Bool {
        lhs.id < rhs.id
    }

    private func reconcileSelectedProject(
        previousProjects: [OpenCodeProject],
        updatedProjects: [OpenCodeProject],
        selectingFirstProjectIfNeeded: Bool
    ) {
        let previousSelection = selectedProjectID

        if let selectedProjectID,
           !updatedProjects.contains(where: { $0.id == selectedProjectID }),
           let previousSelectedProject = previousProjects.first(where: { $0.id == selectedProjectID }),
           let replacement = updatedProjects.first(where: {
               ProjectOrderResolver.matchesProjectLocation($0.worktree, previousSelectedProject.worktree)
           }) {
            self.selectedProjectID = replacement.id
        }

        if selectingFirstProjectIfNeeded,
           (selectedProjectID == nil || !updatedProjects.contains(where: { $0.id == selectedProjectID })) {
            selectedProjectID = updatedProjects.first?.id
        }

        if previousSelection != selectedProjectID {
            applySelectedProjectCache()
        }
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

    private func refreshModelCatalog(using client: OpenCodeAPIClient) async throws {
        isLoadingModels = true
        modelLoadError = nil
        defer { isLoadingModels = false }

        async let configTask = client.config(directory: nil)
        async let providersTask = client.configProviders(directory: nil)

        let config = try await configTask
        let providersResponse = try await providersTask
        applyModelCatalog(resolvedModelCatalog(config: config, providersResponse: providersResponse))
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
            .filter { !$0.models.isEmpty }

        let availableIDs = Set(groups.flatMap(\.models).map(\.id))
        let storedModelID = selectedProfileID.flatMap { modelSelectionStore.load(for: $0) }
        let configuredModelID = normalizedModelIdentifier(config.model)
        let providerDefaultModelID = resolvedProviderDefaultModelID(from: providersResponse.default, groups: groups)

        let resolvedSelection = [selectedModelID, storedModelID, configuredModelID, providerDefaultModelID, groups.first?.models.first?.id]
            .compactMap { $0 }
            .first(where: { availableIDs.contains($0) })

        return ResolvedModelCatalog(groups: groups, selectedModelID: resolvedSelection)
    }

    private func applyModelCatalog(_ catalog: ResolvedModelCatalog) {
        if availableModelGroups != catalog.groups {
            availableModelGroups = catalog.groups
        }

        if selectedModelID != catalog.selectedModelID {
            selectedModelID = catalog.selectedModelID
        }

        guard let profileID = selectedProfileID else { return }
        if let selectedModelID = catalog.selectedModelID {
            modelSelectionStore.save(selectedModelID, for: profileID)
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

    private struct ResolvedModelCatalog {
        let groups: [OpenCodeModelProviderGroup]
        let selectedModelID: String?
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

struct ProjectOrderStore {
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

enum ProjectDropPlacement: Equatable {
    case before
    case after
}

enum ProjectOrderResolver {
    static func deduplicatedProjectIDs(_ projectIDs: [String]) -> [String] {
        var seenIDs: Set<String> = []
        return projectIDs.filter { seenIDs.insert($0).inserted }
    }

    static func storedProjectReferences(for projects: [OpenCodeProject]) -> [String] {
        var seenReferences: Set<String> = []
        return projects.compactMap { project in
            let reference = projectIdentity(for: project)
            guard seenReferences.insert(reference).inserted else { return nil }
            return reference
        }
    }

    static func matchesProjectLocation(_ lhs: String, _ rhs: String) -> Bool {
        normalizedProjectLocation(lhs) == normalizedProjectLocation(rhs)
    }

    static func deduplicatedProjects(_ projects: [OpenCodeProject], preferredIDs: [String] = []) -> [OpenCodeProject] {
        let storedIndexes = Dictionary(uniqueKeysWithValues: deduplicatedProjectIDs(preferredIDs).enumerated().map { ($1, $0) })
        var bestProjectsByIdentity: [String: OpenCodeProject] = [:]
        var orderedIdentities: [String] = []

        for project in projects {
            let identity = projectIdentity(for: project)

            guard let existing = bestProjectsByIdentity[identity] else {
                orderedIdentities.append(identity)
                bestProjectsByIdentity[identity] = project
                continue
            }

            if prefers(project, over: existing, storedIndexes: storedIndexes) {
                bestProjectsByIdentity[identity] = project
            }
        }

        return orderedIdentities.compactMap { bestProjectsByIdentity[$0] }
    }

    static func orderedProjects(_ projects: [OpenCodeProject], storedIDs: [String]) -> [OpenCodeProject] {
        let orderedByRecency = deduplicatedProjects(projects, preferredIDs: storedIDs).sorted { lhs, rhs in
            if lhs.time.updated != rhs.time.updated {
                return lhs.time.updated > rhs.time.updated
            }

            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        guard !storedIDs.isEmpty else { return orderedByRecency }

        let storedIndexes = Dictionary(uniqueKeysWithValues: deduplicatedProjectIDs(storedIDs).enumerated().map { ($1, $0) })

        return orderedByRecency.sorted { lhs, rhs in
            let lhsStoredIndex = storedIndex(for: lhs, in: storedIndexes)
            let rhsStoredIndex = storedIndex(for: rhs, in: storedIndexes)

            switch (lhsStoredIndex, rhsStoredIndex) {
            case let (lhsIndex?, rhsIndex?) where lhsIndex != rhsIndex:
                return lhsIndex < rhsIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.time.updated != rhs.time.updated {
                    return lhs.time.updated > rhs.time.updated
                }

                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        }
    }

    static func reorderedProjects(
        _ projects: [OpenCodeProject],
        movingProjectID: OpenCodeProject.ID,
        relativeTo targetProjectID: OpenCodeProject.ID,
        placement: ProjectDropPlacement
    ) -> [OpenCodeProject] {
        var reorderedProjects = deduplicatedProjects(projects)

        guard reorderedProjects.count > 1 else { return reorderedProjects }
        guard movingProjectID != targetProjectID else { return reorderedProjects }
        guard let sourceIndex = reorderedProjects.firstIndex(where: { $0.id == movingProjectID }) else { return reorderedProjects }
        guard let targetIndex = reorderedProjects.firstIndex(where: { $0.id == targetProjectID }) else { return reorderedProjects }

        let movedProject = reorderedProjects.remove(at: sourceIndex)

        var insertionIndex = targetIndex
        if placement == .after {
            insertionIndex += 1
        }
        if sourceIndex < insertionIndex {
            insertionIndex -= 1
        }

        reorderedProjects.insert(movedProject, at: max(0, min(insertionIndex, reorderedProjects.count)))
        return reorderedProjects
    }

    private static func projectIdentity(for project: OpenCodeProject) -> String {
        let normalizedWorktree = normalizedProjectLocation(project.worktree)
        if normalizedWorktree.isEmpty {
            return "id:\(project.id)"
        }

        return "worktree:\(normalizedWorktree)"
    }

    private static func normalizedProjectLocation(_ location: String) -> String {
        NSString(string: location).standardizingPath
    }

    private static func prefers(
        _ candidate: OpenCodeProject,
        over existing: OpenCodeProject,
        storedIndexes: [String: Int]
    ) -> Bool {
        let candidateStoredIndex = storedIndex(for: candidate, in: storedIndexes)
        let existingStoredIndex = storedIndex(for: existing, in: storedIndexes)

        switch (candidateStoredIndex, existingStoredIndex) {
        case let (candidateIndex?, existingIndex?) where candidateIndex != existingIndex:
            return candidateIndex < existingIndex
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if candidate.time.updated != existing.time.updated {
                return candidate.time.updated > existing.time.updated
            }

            return candidate.id.localizedCaseInsensitiveCompare(existing.id) == .orderedAscending
        }
    }

    private static func storedIndex(for project: OpenCodeProject, in storedIndexes: [String: Int]) -> Int? {
        let references = [projectIdentity(for: project), project.id]
        return references.compactMap { storedIndexes[$0] }.min()
    }
}

private extension Array {
    mutating func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        let movingItems = source.map { self[$0] }
        var insertionIndex = destination

        for index in source.sorted(by: >) {
            remove(at: index)
            if index < insertionIndex {
                insertionIndex -= 1
            }
        }

        insert(contentsOf: movingItems, at: insertionIndex)
    }
}
