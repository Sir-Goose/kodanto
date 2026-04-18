import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class KodantoAppModel {
    typealias SessionNavigationTarget = KodantoSessionNavigationTarget
    typealias DiagnosticsSnapshot = KodantoDiagnosticsSnapshot
    typealias ConnectionState = KodantoConnectionState

    private enum RefreshScope {
        case full
        case liveData

        var includesModelCatalog: Bool {
            self == .full
        }
    }

    private enum RequestActionError: LocalizedError {
        case missingSelection
        case missingProject

        var errorDescription: String? {
            switch self {
            case .missingSelection:
                return "Select a connected session before responding."
            case .missingProject:
                return "Select a connected project before performing this action."
            }
        }
    }

    var profiles: [ServerProfile] = []
    var selectedProfileID: ServerProfile.ID?
    var connectionState: ConnectionState = .idle
    var pathInfo: OpenCodePathInfo?
    var sidecarLog = ""
    var showingConnectionSheet = false
    var showingConnectionsManager = false
    var showingDiagnostics = false
    var notification: String?
    var isTerminalPanelOpen = false
    var terminalPanelHeight: Double = TerminalLayoutState.default.height

    let workspaceStore: WorkspaceStore
    let sessionDetailStore: SessionDetailStore
    let sessionRequestStore: SessionRequestStore
    let composerStore: ComposerStore
    let liveSyncCoordinator: LiveSyncCoordinator
    let terminalStore: TerminalStore

    private let dependencies: KodantoAppDependencies
    private var connectTask: Task<Void, Never>?

    convenience init(userDefaults: UserDefaults = .standard) {
        self.init(dependencies: .live(userDefaults: userDefaults))
    }

    init(dependencies: KodantoAppDependencies) {
        self.dependencies = dependencies
        workspaceStore = WorkspaceStore(projectOrderStore: dependencies.projectOrderStore)
        sessionDetailStore = SessionDetailStore()
        sessionRequestStore = SessionRequestStore(permissionAutoAcceptStore: dependencies.permissionAutoAcceptStore)
        composerStore = ComposerStore(
            modelSelectionStore: dependencies.modelSelectionStore,
            modelVariantSelectionStore: dependencies.modelVariantSelectionStore
        )
        liveSyncCoordinator = LiveSyncCoordinator(
            apiFactory: dependencies.apiFactory,
            sseStreamProvider: dependencies.sseStreamProvider,
            clock: dependencies.clock
        )
        terminalStore = TerminalStore(resumeStore: dependencies.terminalResumeStore)

        profiles = dependencies.profileStore.load()
        if profiles.isEmpty {
            let local = Self.makeLocalProfile()
            profiles = [local]
            selectedProfileID = local.id
            dependencies.profileStore.save(profiles)
        } else {
            selectedProfileID = profiles.first?.id
        }

        composerStore.updateSelectedProfile(selectedProfileID)
        syncSelectionContext(resetSessionState: true)

        let terminalLayout = dependencies.terminalLayoutStore.load()
        isTerminalPanelOpen = terminalLayout.isOpen
        terminalPanelHeight = terminalLayout.height

        dependencies.sidecar.setOutputHandler { [weak self] line in
            Task { @MainActor in
                self?.appendSidecarLog(line)
            }
        }
    }

    var selectedProfile: ServerProfile? {
        profiles.first(where: { $0.id == selectedProfileID })
    }

    var projects: [OpenCodeProject] {
        workspaceStore.projects
    }

    var selectedProjectID: OpenCodeProject.ID? {
        workspaceStore.selectedProjectID
    }

    var selectedProject: OpenCodeProject? {
        workspaceStore.selectedProject
    }

    var sessions: [OpenCodeSession] {
        workspaceStore.sessions
    }

    var selectedSessionID: OpenCodeSession.ID? {
        workspaceStore.selectedSessionID
    }

    var selectedSession: OpenCodeSession? {
        workspaceStore.selectedSession
    }

    var selectedSessionMessages: [OpenCodeMessageEnvelope] {
        sessionDetailStore.selectedSessionMessages
    }

    var selectedSessionTurns: [TranscriptTurn] {
        sessionDetailStore.selectedSessionTurns
    }

    var selectedSessionTranscriptRevision: Int {
        sessionDetailStore.selectedSessionTranscriptRevision
    }

    var sessionTodos: [OpenCodeTodo] {
        sessionDetailStore.sessionTodos
    }

    var permissions: [OpenCodePermissionRequest] {
        sessionRequestStore.permissions
    }

    var questions: [OpenCodeQuestionRequest] {
        sessionRequestStore.questions
    }

    var availableModelGroups: [OpenCodeModelProviderGroup] {
        composerStore.availableModelGroups
    }

    var selectedModelID: String? {
        composerStore.selectedModelID
    }

    var selectedModelVariant: String? {
        composerStore.selectedModelVariant
    }

    var isLoadingModels: Bool {
        composerStore.isLoadingModels
    }

    var modelLoadError: String? {
        composerStore.modelLoadError
    }

    var draftPrompt: String {
        get { composerStore.draftPrompt }
        set { composerStore.draftPrompt = newValue }
    }

    var activePermissionRequest: OpenCodePermissionRequest? {
        sessionRequestStore.activePermissionRequest
    }

    var activeQuestionRequest: OpenCodeQuestionRequest? {
        sessionRequestStore.activeQuestionRequest
    }

    var isPermissionAutoAcceptEnabled: Bool {
        sessionRequestStore.isPermissionAutoAcceptEnabled
    }

    var canTogglePermissionAutoAccept: Bool {
        sessionRequestStore.canTogglePermissionAutoAccept
    }

    func loadedSessionNavigationTarget(for sessionID: OpenCodeSession.ID) -> SessionNavigationTarget? {
        workspaceStore.loadedSessionNavigationTarget(for: sessionID)
    }

    var selectedModel: OpenCodeModelOption? {
        composerStore.selectedModel
    }

    var selectedModelSelection: PromptRequestBody.ModelSelection? {
        composerStore.selectedModelSelection
    }

    var selectedModelVariants: [String] {
        composerStore.selectedModelVariants
    }

    var selectedPromptVariant: String? {
        composerStore.selectedPromptVariant
    }

    var availablePromptAgents: [OpenCodeAgent] {
        composerStore.availablePrimaryAgents
    }

    var selectedPromptAgentName: String? {
        composerStore.selectedPromptAgent
    }

    var sessionContextUsage: SessionContextUsage? {
        SessionContextUsage.compute(
            messages: sessionDetailStore.selectedSessionMessages,
            modelContextLimit: composerStore.selectedModel?.contextLimit
        )
    }

    var canCreateSession: Bool {
        selectedProject != nil && selectedProfile != nil
    }

    var canSendPrompt: Bool {
        selectedProject != nil && selectedProfile != nil && !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canShowTerminal: Bool {
        selectedProject != nil && selectedProfile != nil
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

    func toggleTerminalPanel() {
        setTerminalPanelOpen(!isTerminalPanelOpen)
    }

    func setTerminalPanelOpen(_ isOpen: Bool) {
        guard isTerminalPanelOpen != isOpen else { return }
        isTerminalPanelOpen = isOpen
        persistTerminalLayout()
        if isOpen {
            ensureTerminalConnectedIfNeeded()
        }
    }

    func setTerminalPanelHeight(_ value: Double, persist: Bool = true) {
        guard value.isFinite else { return }
        let clamped = max(140, value)
        guard terminalPanelHeight != clamped else { return }
        terminalPanelHeight = clamped
        if persist {
            persistTerminalLayout()
        }
    }

    func consumeTerminalOutputChunks() -> [String] {
        terminalStore.consumeActiveOutputChunks()
    }

    func sendTerminalInput(_ input: String) {
        Task {
            await terminalStore.sendInputToActive(input)
        }
    }

    func retryTerminalConnection() {
        guard isTerminalPanelOpen,
              let profile = selectedProfile,
              let directory = selectedProject?.worktree
        else {
            return
        }

        let launchConfiguration = terminalLaunchConfiguration(profile: profile, directory: directory)
        let client = dependencies.apiFactory.makeService(profile: profile)
        Task {
            await terminalStore.retryActiveConnection(
                launchConfiguration: launchConfiguration,
                client: client
            ) { ptyID, directory, cursor in
                try OpenCodeAPIClient(profile: profile).ptyConnectRequest(
                    ptyID: ptyID,
                    directory: directory,
                    cursor: cursor
                )
            }
        }
    }

    func ensureTerminalConnectedIfNeeded() {
        guard isTerminalPanelOpen,
              let profile = selectedProfile,
              let directory = selectedProject?.worktree
        else {
            return
        }

        let launchConfiguration = terminalLaunchConfiguration(profile: profile, directory: directory)
        let client = dependencies.apiFactory.makeService(profile: profile)
        Task {
            await terminalStore.ensureConnected(
                directory: directory,
                launchConfiguration: launchConfiguration,
                client: client
            ) { ptyID, directory, cursor in
                try OpenCodeAPIClient(profile: profile).ptyConnectRequest(
                    ptyID: ptyID,
                    directory: directory,
                    cursor: cursor
                )
            }
        }
    }

    func updateTerminalSize(rows: Int, cols: Int) {
        guard let profile = selectedProfile else { return }
        let client = dependencies.apiFactory.makeService(profile: profile)
        Task {
            await terminalStore.updateActiveSize(rows: rows, cols: cols, client: client)
        }
    }

    private func terminalLaunchConfiguration(profile: ServerProfile, directory: String) -> TerminalStore.LaunchConfiguration {
        switch profile.kind {
        case .localSidecar:
            let shell = resolvedLocalZshPath()
            return TerminalStore.LaunchConfiguration(
                title: "Terminal",
                cwd: directory,
                command: shell,
                args: ["-l"],
                enforceShell: true
            )
        case .remote:
            return TerminalStore.LaunchConfiguration(
                title: "Terminal",
                cwd: directory,
                command: nil,
                args: nil,
                enforceShell: false
            )
        }
    }

    private func resolvedLocalZshPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shell, !shell.isEmpty, URL(fileURLWithPath: shell).lastPathComponent.lowercased() == "zsh" {
            return shell
        }
        return "/bin/zsh"
    }

    var isLiveSyncActive: Bool {
        liveSyncCoordinator.isActive
    }

    var liveSyncPhase: LiveSyncTracker.State {
        liveSyncCoordinator.state
    }

    var reconnectCount: Int {
        liveSyncCoordinator.reconnectCount
    }

    var isSelectedSessionRunning: Bool {
        workspaceStore.isSelectedSessionRunning
    }

    var diagnostics: DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            serverURL: selectedProfile?.normalizedBaseURL ?? "Not configured",
            binaryPath: (try? dependencies.sidecar.executablePath()) ?? "Not found",
            liveSyncState: liveSyncCoordinator.state.label,
            reconnectCount: reconnectCount,
            lastEventDescription: liveSyncCoordinator.lastEventAt == .distantPast
                ? "No events yet"
                : RelativeDateTimeFormatter().localizedString(for: liveSyncCoordinator.lastEventAt, relativeTo: .now),
            lastError: liveSyncCoordinator.lastSSEError,
            selectedProjectDirectory: workspaceStore.selectedProjectDirectory,
            cachedProjects: workspaceStore.cachedProjectCount,
            cachedSessions: workspaceStore.cachedSessionCount,
            sidecarLog: sidecarLog
        )
    }

    func selectProfile(_ profileID: ServerProfile.ID, forceReset: Bool = false) {
        guard forceReset || selectedProfileID != profileID else { return }
        connectTask?.cancel()
        stopLiveSync()
        Task {
            await terminalStore.disconnectAll()
        }

        selectedProfileID = profileID
        composerStore.updateSelectedProfile(profileID)
        connectionState = .idle
        pathInfo = nil
        workspaceStore.reset()
        syncSelectionContext(resetSessionState: true)
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
        dependencies.profileStore.save(profiles)

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
        dependencies.modelSelectionStore.remove(for: profile.id)
        dependencies.modelVariantSelectionStore.remove(for: profile.id)
        dependencies.projectOrderStore.remove(for: profile.id)
        dependencies.profileStore.save(profiles)

        if let fallbackProfileID {
            selectProfile(fallbackProfileID, forceReset: true)
        }
    }

    func selectModel(_ modelID: String) {
        composerStore.selectModel(modelID)
    }

    func selectModelVariant(_ variant: String?) {
        composerStore.selectModelVariant(variant)
    }

    func selectPromptAgent(_ agentName: String?) {
        composerStore.selectAgent(agentName)
    }

    func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int) {
        workspaceStore.moveProjects(fromOffsets: source, toOffset: destination, profileID: selectedProfileID)
    }

    func moveProject(
        _ projectID: OpenCodeProject.ID,
        relativeTo targetProjectID: OpenCodeProject.ID,
        placement: ProjectDropPlacement
    ) {
        workspaceStore.moveProject(
            projectID,
            relativeTo: targetProjectID,
            placement: placement,
            profileID: selectedProfileID
        )
    }

    func sanitizeProjects() {
        workspaceStore.sanitizeProjects(profileID: selectedProfileID)
        syncSelectionContext(resetSessionState: false)
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
            let client = dependencies.apiFactory.makeService(profile: profile)

            if profile.kind == .localSidecar {
                let installedVersion = try? dependencies.sidecar.executableVersion()

                if let health = try? await client.health(), health.healthy {
                    if let installedVersion,
                       !dependencies.sidecar.versionsMatch(health.version, installedVersion) {
                        appendSidecarLog("Restarting local sidecar to use installed opencode \(installedVersion) instead of running \(health.version).\n")
                        try await dependencies.sidecar.restart(profile: profile)
                        try await waitForServer(profile: profile)
                    }
                } else {
                    try await dependencies.sidecar.restart(profile: profile)
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
                try await refreshAll(using: dependencies.apiFactory.makeService(profile: profile), scope: .full)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func restartServer() {
        Task {
            guard let profile = selectedProfile else { return }
            guard profile.kind == .localSidecar else { return }
            appendSidecarLog("Restarting server...\n")
            do {
                try await dependencies.sidecar.restart(profile: profile)
                try await waitForServer(profile: profile)
                let client = dependencies.apiFactory.makeService(profile: profile)
                let health = try await client.health()
                connectionState = .connected(version: health.version)
                try await refreshAll(using: client, scope: .full)
                startLiveSync(for: profile)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func refreshModelCatalogForSelectedProject() {
        guard connectionState.isConnected,
              let profile = selectedProfile
        else { return }

        let client = dependencies.apiFactory.makeService(profile: profile)
        let directory = modelCatalogDirectoryForCurrentSelection()

        Task {
            do {
                try await composerStore.refreshModelCatalog(using: client, directory: directory)
            } catch {
                composerStore.modelLoadError = error.localizedDescription
            }
        }
    }

    func sessions(for project: OpenCodeProject) -> [OpenCodeSession] {
        workspaceStore.sessions(for: project)
    }

    func sessionSidebarIndicator(for session: OpenCodeSession, in project: OpenCodeProject) -> SessionSidebarIndicatorState {
        workspaceStore.sessionSidebarIndicator(for: session, in: project)
    }

    func parentSessionTarget(for session: OpenCodeSession) -> KodantoSessionNavigationTarget? {
        workspaceStore.parentSessionTarget(for: session)
    }

    func canMarkSessionUnread(sessionID: OpenCodeSession.ID, in projectID: OpenCodeProject.ID) -> Bool {
        workspaceStore.canMarkSessionUnread(sessionID, in: projectID)
    }

    func markSessionUnread(sessionID: OpenCodeSession.ID, in projectID: OpenCodeProject.ID) {
        workspaceStore.markSessionUnread(sessionID, in: projectID)
    }

    func hasLoadedSessions(for project: OpenCodeProject) -> Bool {
        workspaceStore.hasLoadedSessions(for: project)
    }

    func isLoadingSessions(for project: OpenCodeProject) -> Bool {
        workspaceStore.isLoadingSessions(for: project)
    }

    func loadSessionsIfNeeded(for project: OpenCodeProject) {
        guard !workspaceStore.hasLoadedSessions(for: project), !workspaceStore.isLoadingSessions(for: project) else { return }

        Task {
            guard let profile = selectedProfile else { return }
            do {
                try await loadSessions(for: project, using: dependencies.apiFactory.makeService(profile: profile))
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func createSession(in projectID: OpenCodeProject.ID) {
        guard selectedProfile != nil, let project = projects.first(where: { $0.id == projectID }) else { return }
        workspaceStore.selectProject(project.id)
        workspaceStore.clearSelectedSession()
        syncSelectionContext(resetSessionState: true)
    }

    func renameSession(
        sessionID: OpenCodeSession.ID,
        in projectID: OpenCodeProject.ID,
        newTitle: String
    ) {
        Task {
            do {
                try await submitSessionRename(sessionID: sessionID, in: projectID, newTitle: newTitle)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func archiveSession(
        sessionID: OpenCodeSession.ID,
        in projectID: OpenCodeProject.ID
    ) {
        Task {
            do {
                try await submitSessionArchive(sessionID: sessionID, in: projectID)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func submitSessionRename(
        sessionID: OpenCodeSession.ID,
        in projectID: OpenCodeProject.ID,
        newTitle: String
    ) async throws {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let (client, project) = try actionContext(for: projectID)
        let updated = try await client.updateSession(
            sessionID: sessionID,
            directory: project.worktree,
            title: trimmed,
            archivedAt: nil
        )
        _ = workspaceStore.upsertSession(updated, directory: project.worktree)
    }

    func submitSessionArchive(
        sessionID: OpenCodeSession.ID,
        in projectID: OpenCodeProject.ID
    ) async throws {
        let (client, project) = try actionContext(for: projectID)
        let archivedAt = Date().timeIntervalSince1970 * 1000
        let updated = try await client.updateSession(
            sessionID: sessionID,
            directory: project.worktree,
            title: nil,
            archivedAt: archivedAt
        )

        let selectionChanged = workspaceStore.upsertSession(updated, directory: project.worktree)
        guard selectionChanged else { return }

        syncSelectionContext(resetSessionState: true)
        try await loadSessionDetail(using: client)
    }

    func addProject(from directory: String) {
        Task {
            guard let profile = selectedProfile else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                let createdProject = try await client.initializeGitRepository(directory: directory)

                try await refreshAll(using: client, scope: .liveData)

                guard let refreshedProject = projects.first(where: { $0.id == createdProject.id }) else { return }
                if let firstProjectID = projects.first?.id, firstProjectID != refreshedProject.id {
                    workspaceStore.moveProject(
                        refreshedProject.id,
                        relativeTo: firstProjectID,
                        placement: .before,
                        profileID: selectedProfileID
                    )
                }
                workspaceStore.selectProject(refreshedProject.id)
                syncSelectionContext(resetSessionState: true)

                if !workspaceStore.hasLoadedSessions(for: refreshedProject) {
                    try await loadSessions(for: refreshedProject, using: client)
                }
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func sendPrompt() {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                let session: OpenCodeSession
                if let selectedSession {
                    session = selectedSession
                } else {
                    let createdSession = try await client.createSession(directory: project.worktree, title: nil)
                    _ = workspaceStore.upsertSession(createdSession, directory: project.worktree)
                    _ = workspaceStore.selectSession(createdSession.id, in: project.id)
                    syncSelectionContext(resetSessionState: true)
                    try await loadSessionDetail(using: client)
                    session = selectedSession ?? createdSession
                }

                try await composerStore.submitPrompt(
                    using: client,
                    project: project,
                    session: session
                ) {
                    try await self.loadSessionDetail(using: client)
                    try await self.loadSessions(for: project, using: client)
                }
            } catch {
                if let profile = selectedProfile {
                    try? await loadSessionDetail(using: dependencies.apiFactory.makeService(profile: profile))
                }
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func abortSession() {
        Task {
            guard let profile = selectedProfile,
                  let project = selectedProject,
                  let session = selectedSession
            else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                try await client.abortSession(sessionID: session.id, directory: project.worktree)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    var selectedSlashCommand: SlashCommand? {
        composerStore.selectedSlashCommand
    }

    func selectNextSlashCommand() {
        composerStore.selectNextSlashCommand()
    }

    func selectPreviousSlashCommand() {
        composerStore.selectPreviousSlashCommand()
    }

    func executeSlashCommand(_ command: SlashCommand) {
        switch command.id {
        case "session.new":
            handleNewSession()
        case "session.share":
            handleShareSession()
        case "session.unshare":
            handleUnshareSession()
        case "session.undo":
            handleUndo()
        case "session.redo":
            handleRedo()
        case "session.compact":
            handleCompact()
        case "session.fork":
            handleFork()
        case "terminal.toggle":
            isTerminalPanelOpen.toggle()
        case "file.open":
            break
        case "model.choose":
            composerStore.showModelPicker()
        case "agent.cycle":
            handleAgentCycle()
        case "mcp.toggle":
            break
        default:
            break
        }
    }

    private func handleNewSession() {
        guard workspaceStore.selectedProjectID != nil else { return }
        workspaceStore.clearSelectedSession()
        syncSelectionContext(resetSessionState: true)
    }

    private func handleShareSession() {
        Task {
            guard let profile = selectedProfile,
                  let project = selectedProject,
                  let session = selectedSession
            else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                let share = try await client.shareSession(sessionID: session.id, directory: project.worktree)
                try await loadSessionDetail(using: client)
                
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(share.url, forType: .string)
                notification = "Share link copied to clipboard"
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func handleUnshareSession() {
        Task {
            guard let profile = selectedProfile,
                  let project = selectedProject,
                  let session = selectedSession
            else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                _ = try await client.unshareSession(sessionID: session.id, directory: project.worktree)
                try await loadSessionDetail(using: client)
                notification = "Session unshared"
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func handleUndo() {
        Task {
            guard let profile = selectedProfile,
                  let project = selectedProject,
                  let session = selectedSession
            else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                let messages = try await client.messages(sessionID: session.id, directory: project.worktree)

                var lastUserMessageID: String?
                for msg in messages {
                    if case .user = msg.info,
                       session.revert?.messageID == nil || msg.id < session.revert!.messageID {
                        lastUserMessageID = msg.id
                    }
                }

                guard let messageID = lastUserMessageID else { return }

                let updatedSession = try await client.revert(sessionID: session.id, messageID: messageID, directory: project.worktree)
                _ = workspaceStore.upsertSession(updatedSession, directory: project.worktree)
                try await loadSessionDetail(using: client)
                notification = "Message removed"
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func handleRedo() {
        Task {
            guard let profile = selectedProfile,
                  let project = selectedProject,
                  let session = selectedSession
            else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                let messages = try await client.messages(sessionID: session.id, directory: project.worktree)

                if let revertMessageID = session.revert?.messageID,
                   let nextUserMessageID = messages.first(where: {
                       if case .user = $0.info {
                           return $0.id > revertMessageID
                       }
                       return false
                   })?.id {
                    let updatedSession = try await client.revert(
                        sessionID: session.id,
                        messageID: nextUserMessageID,
                        directory: project.worktree
                    )
                    _ = workspaceStore.upsertSession(updatedSession, directory: project.worktree)
                } else {
                    let updatedSession = try await client.unrevert(sessionID: session.id, directory: project.worktree)
                    _ = workspaceStore.upsertSession(updatedSession, directory: project.worktree)
                }

                try await loadSessionDetail(using: client)
                notification = "Message restored"
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func handleCompact() {
        Task {
            guard let profile = selectedProfile else {
                notification = "No profile selected"
                return
            }
            guard let project = selectedProject else {
                notification = "No project selected"
                return
            }
            guard let session = selectedSession else {
                notification = "No session selected"
                return
            }
            guard let model = composerStore.selectedModel else {
                notification = "No model selected"
                return
            }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                try await client.compactSession(
                    sessionID: session.id,
                    directory: project.worktree,
                    providerID: model.providerID,
                    modelID: model.modelID
                )
                try await loadSessionDetail(using: client)
                notification = "Session compacted"
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func handleFork() {
        Task {
            guard let profile = selectedProfile,
                  let project = selectedProject,
                  let session = selectedSession
            else { return }

            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                let forkedSession = try await client.forkSession(sessionID: session.id, directory: project.worktree)
                _ = workspaceStore.upsertSession(forkedSession, directory: project.worktree)
                _ = workspaceStore.selectSession(forkedSession.id, in: project.id)
                syncSelectionContext(resetSessionState: true)
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func handleAgentCycle() {
        guard !composerStore.availablePrimaryAgents.isEmpty else { return }
        let currentIndex = composerStore.availablePrimaryAgents.firstIndex(where: { $0.name == composerStore.selectedAgentName }) ?? -1
        let nextIndex = (currentIndex + 1) % composerStore.availablePrimaryAgents.count
        composerStore.selectAgent(composerStore.availablePrimaryAgents[nextIndex].name)
    }

    func selectSession(_ sessionID: OpenCodeSession.ID, in projectID: OpenCodeProject.ID) {
        guard selectedProfile != nil else { return }
        let didSwitch = workspaceStore.selectSession(sessionID, in: projectID)
        syncSelectionContext(resetSessionState: didSwitch)

        guard let profile = selectedProfile, let project = selectedProject else { return }

        Task {
            do {
                let client = dependencies.apiFactory.makeService(profile: profile)
                if !workspaceStore.hasLoadedSessions(for: project) {
                    try await loadSessions(for: project, using: client)
                } else {
                    try await loadSessionDetail(using: client)
                }
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func respondToPermission(_ request: OpenCodePermissionRequest, reply: PermissionReply) {
        Task {
            do {
                try await submitPermissionResponse(request, reply: reply)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func togglePermissionAutoAccept() {
        sessionRequestStore.togglePermissionAutoAccept()
        autoRespondToPendingPermissionsIfNeeded()
    }

    func setPermissionAutoAccept(_ enabled: Bool) {
        sessionRequestStore.setPermissionAutoAccept(enabled)
        if enabled {
            autoRespondToPendingPermissionsIfNeeded()
        }
    }

    func submitPermissionResponse(_ request: OpenCodePermissionRequest, reply: PermissionReply) async throws {
        let (client, directory) = try selectedActionContext()
        try await sessionRequestStore.submitPermissionResponse(
            request,
            reply: reply,
            using: client,
            directory: directory
        ) {
            try await self.loadSessionDetail(using: client)
        }
    }

    func answerQuestion(_ request: OpenCodeQuestionRequest, answers: [[String]]) {
        Task {
            do {
                try await submitQuestionAnswers(request, answers: answers)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func rejectQuestion(_ request: OpenCodeQuestionRequest) {
        Task {
            do {
                try await submitQuestionRejection(request)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func submitQuestionAnswers(_ request: OpenCodeQuestionRequest, answers: [[String]]) async throws {
        let (client, directory) = try selectedActionContext()
        try await sessionRequestStore.submitQuestionAnswers(
            request,
            answers: answers,
            using: client,
            directory: directory
        ) {
            try await self.loadSessionDetail(using: client)
        }
    }

    func submitQuestionRejection(_ request: OpenCodeQuestionRequest) async throws {
        let (client, directory) = try selectedActionContext()
        try await sessionRequestStore.submitQuestionRejection(
            request,
            using: client,
            directory: directory
        ) {
            try await self.loadSessionDetail(using: client)
        }
    }

    private func selectedActionContext() throws -> (client: OpenCodeAPIService, directory: String) {
        guard let profile = selectedProfile, let project = selectedProject, selectedSession != nil else {
            throw RequestActionError.missingSelection
        }

        return (dependencies.apiFactory.makeService(profile: profile), project.worktree)
    }

    private func actionContext(for projectID: OpenCodeProject.ID) throws -> (client: OpenCodeAPIService, project: OpenCodeProject) {
        guard let profile = selectedProfile else {
            throw RequestActionError.missingSelection
        }

        guard let project = projects.first(where: { $0.id == projectID }) else {
            throw RequestActionError.missingProject
        }

        return (dependencies.apiFactory.makeService(profile: profile), project)
    }

    private func refreshAll(using client: OpenCodeAPIService, scope: RefreshScope) async throws {
        async let pathInfoTask = client.pathInfo(directory: nil)
        async let projectsTask = client.projects()

        pathInfo = try await pathInfoTask
        workspaceStore.applyLoadedProjects(try await projectsTask, profileID: selectedProfileID)
        syncSelectionContext(resetSessionState: false)

        if scope.includesModelCatalog {
            do {
                try await composerStore.refreshModelCatalog(
                    using: client,
                    directory: modelCatalogDirectoryForCurrentSelection()
                )
            } catch {
                composerStore.modelLoadError = error.localizedDescription
            }
        }

        let projectsToRefresh = projects.filter { project in
            workspaceStore.hasLoadedSessions(for: project)
        }

        if projectsToRefresh.isEmpty {
            workspaceStore.clearSelectedSession()
            syncSelectionContext(resetSessionState: true)
        } else {
            for project in projectsToRefresh {
                try await loadSessions(for: project, using: client)
            }
        }
    }

    private func loadSessions(for project: OpenCodeProject, using client: OpenCodeAPIService) async throws {
        workspaceStore.beginLoadingSessions(for: project)
        defer { workspaceStore.finishLoadingSessions(for: project) }

        async let sessionsTask = client.sessions(directory: project.worktree)
        async let statusesTask = client.sessionStatuses(directory: project.worktree)

        let loadedSessions = try await sessionsTask
        let loadedStatuses = try await statusesTask
        let previousSelectedSessionID = selectedSessionID

        workspaceStore.applyLoadedSessions(loadedSessions, statuses: loadedStatuses, for: project)
        let didSwitch = previousSelectedSessionID != selectedSessionID
        if didSwitch {
            syncSelectionContext(resetSessionState: true)
        } else {
            syncSelectionContext(resetSessionState: false)
        }

        guard selectedProjectID == project.id else { return }
        try await loadSessionDetail(using: client)
    }

    private func loadSessionDetail(using client: OpenCodeAPIService) async throws {
        guard let project = selectedProject else {
            syncSelectionContext(resetSessionState: true)
            return
        }

        let selectedSessionID = self.selectedSessionID
        let directory = project.worktree
        sessionRequestStore.updateSelection(sessionID: selectedSessionID, directory: directory)

        async let permissionsTask = client.permissions(directory: directory)
        async let questionsTask = client.questions(directory: directory)

        let loadedPermissions = try await permissionsTask
        let loadedQuestions = try await questionsTask

        guard selectedProject?.worktree == directory, self.selectedSessionID == selectedSessionID else { return }

        sessionRequestStore.replaceRequests(permissions: loadedPermissions, questions: loadedQuestions)
        autoRespondToPendingPermissionsIfNeeded()

        guard let session = selectedSession else {
            sessionDetailStore.clearSessionDetail()
            return
        }

        async let messagesTask = client.messages(sessionID: session.id, directory: directory)
        async let todosTask = client.sessionTodos(sessionID: session.id, directory: directory)

        let loadedMessages = try await messagesTask
        let loadedTodos = try await todosTask

        guard selectedProject?.worktree == directory, self.selectedSessionID == selectedSessionID else { return }

        sessionDetailStore.replaceMessages(loadedMessages)
        sessionDetailStore.replaceSessionTodos(loadedTodos)
        composerStore.syncSelectedAgent(from: loadedMessages, sessionID: selectedSessionID)
    }

    private func startLiveSync(for profile: ServerProfile) {
        liveSyncCoordinator.start(
            for: profile,
            refresh: { [weak self] client in
                guard let self else { return }
                try await self.refreshAll(using: client, scope: .liveData)
            },
            handleEvent: { [weak self] event in
                self?.applyGlobalEvent(event)
            }
        )
    }

    private func stopLiveSync() {
        liveSyncCoordinator.stop()
    }

    private func applyGlobalEvent(_ event: OpenCodeGlobalEvent) {
        terminalStore.handleGlobalEvent(event)

        let effects = GlobalEventRouter.apply(
            event,
            selectedProfileID: selectedProfileID,
            workspaceStore: workspaceStore,
            sessionDetailStore: sessionDetailStore,
            sessionRequestStore: sessionRequestStore
        )

        composerStore.syncSelectedAgent(from: sessionDetailStore.selectedSessionMessages, sessionID: selectedSessionID)

        if effects.contains(.refresh) {
            refresh()
        }

        if effects.contains(.loadSessionDetail) {
            syncSelectionContext(resetSessionState: true)
            Task {
                guard let profile = selectedProfile else { return }
                do {
                    try await loadSessionDetail(using: dependencies.apiFactory.makeService(profile: profile))
                } catch {
                    connectionState = .failed(error.localizedDescription)
                }
            }
        }

        if effects.contains(.autoRespondPermissions) {
            autoRespondToPendingPermissionsIfNeeded()
        }
    }

    private func autoRespondToPendingPermissionsIfNeeded() {
        sessionRequestStore.autoRespondToPendingPermissionsIfNeeded(
            submit: { [weak self] request, reply in
                guard let self else { return }
                try await self.submitPermissionResponse(request, reply: reply)
            },
            onError: { [weak self] error in
                self?.connectionState = .failed(error.localizedDescription)
            }
        )
    }

    private func syncSelectionContext(resetSessionState: Bool) {
        if resetSessionState {
            sessionDetailStore.selectSession(selectedSessionID)
            sessionRequestStore.clearRequests()
        }
        terminalStore.setPersistenceScope(profileID: selectedProfileID)
        sessionRequestStore.updateSelection(sessionID: selectedSessionID, directory: selectedProject?.worktree)
        terminalStore.setActiveDirectory(selectedProject?.worktree)
        ensureTerminalConnectedIfNeeded()
    }

    private func modelCatalogDirectoryForCurrentSelection() -> String? {
        guard let project = selectedProject else { return nil }
        guard workspaceStore.hasLoadedSessions(for: project) else { return nil }
        return project.worktree
    }

    private func waitForServer(profile: ServerProfile) async throws {
        let client = dependencies.apiFactory.makeService(profile: profile)
        for _ in 0 ..< 50 {
            if let health = try? await client.health(), health.healthy {
                return
            }
            try await dependencies.clock.sleep(for: .milliseconds(150))
        }
        throw OpenCodeAPIError.serverError(statusCode: 0, message: "Timed out waiting for local opencode sidecar.")
    }

    private func appendSidecarLog(_ line: String) {
        sidecarLog.append(line)
        if sidecarLog.count > 12000 {
            sidecarLog = String(sidecarLog.suffix(12000))
        }
    }

    private func persistTerminalLayout() {
        dependencies.terminalLayoutStore.save(
            .init(isOpen: isTerminalPanelOpen, height: terminalPanelHeight)
        )
    }

    static func makeLocalProfile() -> ServerProfile {
        var profile = ServerProfile.localDefault
        profile.password = UUID().uuidString
        return profile
    }
}
