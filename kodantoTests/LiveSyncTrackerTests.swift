import XCTest
@testable import kodanto

@MainActor
final class LiveSyncTrackerTests: XCTestCase {
    func testStartTransitionsToConnectingAndTracksTimestamp() {
        var tracker = LiveSyncTracker()
        let now = Date(timeIntervalSince1970: 100)

        tracker.start(now: now)

        XCTAssertEqual(tracker.state, .connecting)
        XCTAssertEqual(tracker.lastEventAt, now)
        XCTAssertEqual(tracker.reconnectCount, 0)
    }

    func testStartKeepsReconnectingStateDuringRetryLoop() {
        var tracker = LiveSyncTracker()
        tracker.markReconnectNeeded(reason: "network error")

        tracker.start(now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(tracker.state, .reconnecting("network error"))
        XCTAssertEqual(tracker.reconnectCount, 1)
    }

    func testReceiveServerConnectedAfterReconnectRequestsRefresh() {
        var tracker = LiveSyncTracker()
        tracker.markReconnectNeeded(reason: "stream ended")

        let shouldRefresh = tracker.receiveEvent(
            TestFixtures.globalEvent(payload: .serverConnected),
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertTrue(shouldRefresh)
        XCTAssertEqual(tracker.state, .active)
    }

    func testReceiveNonServerConnectedEventAfterReconnectDoesNotRequestRefresh() {
        var tracker = LiveSyncTracker()
        tracker.markReconnectNeeded(reason: "stream ended")

        let shouldRefresh = tracker.receiveEvent(
            TestFixtures.globalEvent(payload: .serverHeartbeat),
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertFalse(shouldRefresh)
        XCTAssertEqual(tracker.state, .active)
    }

    func testHeartbeatTimeoutUsesMostRecentEventTimestamp() {
        var tracker = LiveSyncTracker()
        let now = Date(timeIntervalSince1970: 1_000)
        tracker.start(now: now)

        XCTAssertFalse(tracker.isHeartbeatTimedOut(now: now.addingTimeInterval(LiveSyncTracker.heartbeatTimeout - 0.1)))
        XCTAssertTrue(tracker.isHeartbeatTimedOut(now: now.addingTimeInterval(LiveSyncTracker.heartbeatTimeout + 0.1)))
    }

    func testStopResetsRuntimeState() {
        var tracker = LiveSyncTracker()
        tracker.start(now: Date(timeIntervalSince1970: 100))
        _ = tracker.receiveEvent(TestFixtures.globalEvent(payload: .serverConnected), now: Date(timeIntervalSince1970: 101))

        tracker.stop()

        XCTAssertEqual(tracker.state, .inactive)
        XCTAssertEqual(tracker.lastEventAt, .distantPast)
        XCTAssertFalse(tracker.isHeartbeatTimedOut(now: Date(timeIntervalSince1970: 200)))
    }
}

final class ComposerAgentSelectionTests: XCTestCase {
    private var defaultsSuites: [String] = []

    override func tearDown() {
        for suiteName in defaultsSuites {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaultsSuites.removeAll()
        super.tearDown()
    }

    func testRefreshModelCatalogFiltersPrimaryVisibleAgents() async throws {
        try await runOnMainActor {
            let store = self.makeStore()
            let service = ComposerAgentMockAPIService()
            service.agentsResponse = [
                self.makeAgent(name: "build", mode: "primary"),
                self.makeAgent(name: "plan", mode: "primary"),
                self.makeAgent(name: "general", mode: "subagent"),
                self.makeAgent(name: "hidden", mode: "primary", hidden: true),
                self.makeAgent(name: "custom", mode: "all")
            ]

            try await store.refreshModelCatalog(using: service)

            XCTAssertEqual(store.availablePrimaryAgents.map(\.name), ["build", "plan", "custom"])
            XCTAssertEqual(store.selectedPromptAgent, "build")
        }
    }

    func testSyncSelectedAgentUsesLatestUserMessageAgentWhenAvailable() async {
        await runOnMainActor {
            let store = self.makeStore()
            store.availablePrimaryAgents = [
                self.makeAgent(name: "build", mode: "primary"),
                self.makeAgent(name: "plan", mode: "primary")
            ]
            store.selectedAgentName = "build"

            let messages: [OpenCodeMessageEnvelope] = [
                self.makeUserEnvelope(messageID: "m1", sessionID: "session-1", createdAt: 1, agent: "build"),
                self.makeUserEnvelope(messageID: "m2", sessionID: "session-1", createdAt: 2, agent: "plan")
            ]

            store.syncSelectedAgent(from: messages, sessionID: "session-1")

            XCTAssertEqual(store.selectedPromptAgent, "plan")
        }
    }

    func testSyncSelectedAgentFallsBackWhenHistoricalAgentUnavailable() async {
        await runOnMainActor {
            let store = self.makeStore()
            store.availablePrimaryAgents = [
                self.makeAgent(name: "build", mode: "primary"),
                self.makeAgent(name: "plan", mode: "primary")
            ]
            store.selectedAgentName = "build"

            let messages: [OpenCodeMessageEnvelope] = [
                self.makeUserEnvelope(messageID: "m1", sessionID: "session-1", createdAt: 1, agent: "my-custom-agent")
            ]

            store.syncSelectedAgent(from: messages, sessionID: "session-1")

            XCTAssertEqual(store.selectedPromptAgent, "build")
        }
    }

    func testSyncSelectedAgentDoesNotOverrideManualSelectionWhenLatestUserMessageUnchanged() async {
        await runOnMainActor {
            let store = self.makeStore()
            store.availablePrimaryAgents = [
                self.makeAgent(name: "build", mode: "primary"),
                self.makeAgent(name: "plan", mode: "primary")
            ]

            let messages: [OpenCodeMessageEnvelope] = [
                self.makeUserEnvelope(messageID: "m1", sessionID: "session-1", createdAt: 1, agent: "build")
            ]

            store.syncSelectedAgent(from: messages, sessionID: "session-1")
            XCTAssertEqual(store.selectedPromptAgent, "build")

            store.selectAgent("plan")
            XCTAssertEqual(store.selectedPromptAgent, "plan")

            store.syncSelectedAgent(from: messages, sessionID: "session-1")
            XCTAssertEqual(store.selectedPromptAgent, "plan")
        }
    }

    func testSyncSelectedAgentReappliesSessionHistoryWhenSwitchingSessions() async {
        await runOnMainActor {
            let store = self.makeStore()
            store.availablePrimaryAgents = [
                self.makeAgent(name: "build", mode: "primary"),
                self.makeAgent(name: "plan", mode: "primary")
            ]

            let sessionOneMessages: [OpenCodeMessageEnvelope] = [
                self.makeUserEnvelope(messageID: "m1", sessionID: "session-1", createdAt: 1, agent: "build")
            ]
            let sessionTwoMessages: [OpenCodeMessageEnvelope] = [
                self.makeUserEnvelope(messageID: "m2", sessionID: "session-2", createdAt: 2, agent: "plan")
            ]

            store.syncSelectedAgent(from: sessionOneMessages, sessionID: "session-1")
            XCTAssertEqual(store.selectedPromptAgent, "build")

            store.selectAgent("plan")
            XCTAssertEqual(store.selectedPromptAgent, "plan")

            store.syncSelectedAgent(from: sessionTwoMessages, sessionID: "session-2")
            XCTAssertEqual(store.selectedPromptAgent, "plan")

            store.syncSelectedAgent(from: sessionOneMessages, sessionID: "session-1")
            XCTAssertEqual(store.selectedPromptAgent, "build")
        }
    }

    func testSubmitPromptPassesSelectedAgent() async throws {
        try await runOnMainActor {
            let store = self.makeStore()
            let service = ComposerAgentMockAPIService()
            store.availablePrimaryAgents = [
                self.makeAgent(name: "build", mode: "primary"),
                self.makeAgent(name: "plan", mode: "primary")
            ]
            store.selectAgent("plan")
            store.draftPrompt = "Use plan mode"

            let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
            let session = TestFixtures.session(id: "session-1", directory: project.worktree, updatedAt: 100)

            try await store.submitPrompt(using: service, project: project, session: session) {}

            XCTAssertEqual(service.promptCalls.count, 1)
            XCTAssertEqual(service.promptCalls.first?.agent, "plan")
        }
    }

    func testSubmitPromptWithoutAvailableAgentsSendsNilAgent() async throws {
        try await runOnMainActor {
            let store = self.makeStore()
            let service = ComposerAgentMockAPIService()
            store.availablePrimaryAgents = []
            store.selectedAgentName = nil
            store.draftPrompt = "Use default agent"

            let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
            let session = TestFixtures.session(id: "session-1", directory: project.worktree, updatedAt: 100)

            try await store.submitPrompt(using: service, project: project, session: session) {}

            XCTAssertEqual(service.promptCalls.count, 1)
            XCTAssertNil(service.promptCalls.first?.agent)
        }
    }

    func testAgentIconResolverReturnsHammerForBuildAgent() {
        let icon = AgentModeIconResolver.systemImageName(
            selectedAgentName: "build",
            availableAgents: [
                OpenCodeAgent(name: "build", description: nil, mode: "primary", hidden: nil)
            ]
        )

        XCTAssertEqual(icon, "hammer")
    }

    func testAgentIconResolverReturnsChecklistForPlanAgent() {
        let icon = AgentModeIconResolver.systemImageName(
            selectedAgentName: "plan",
            availableAgents: [
                OpenCodeAgent(name: "plan", description: nil, mode: "primary", hidden: nil)
            ]
        )

        XCTAssertEqual(icon, "checklist")
    }

    func testAgentIconResolverReturnsGenericForCustomAgent() {
        let icon = AgentModeIconResolver.systemImageName(
            selectedAgentName: "custom",
            availableAgents: [
                OpenCodeAgent(name: "custom", description: nil, mode: "all", hidden: nil)
            ]
        )

        XCTAssertEqual(icon, "person.crop.circle")
    }

    func testAgentIconResolverNormalizesCaseAndWhitespace() {
        let buildIcon = AgentModeIconResolver.systemImageName(
            selectedAgentName: " Build ",
            availableAgents: [
                OpenCodeAgent(name: "build", description: nil, mode: "primary", hidden: nil)
            ]
        )
        let planIcon = AgentModeIconResolver.systemImageName(
            selectedAgentName: " PLAN ",
            availableAgents: [
                OpenCodeAgent(name: "plan", description: nil, mode: "primary", hidden: nil)
            ]
        )

        XCTAssertEqual(buildIcon, "hammer")
        XCTAssertEqual(planIcon, "checklist")
    }

    func testAgentIconResolverUsesSelectedAgentModeForCustomAgentNames() {
        let buildModeIcon = AgentModeIconResolver.systemImageName(
            selectedAgentName: "my-custom-build-agent",
            availableAgents: [
                OpenCodeAgent(name: "my-custom-build-agent", description: nil, mode: "build", hidden: nil)
            ]
        )
        let planModeIcon = AgentModeIconResolver.systemImageName(
            selectedAgentName: "my-custom-plan-agent",
            availableAgents: [
                OpenCodeAgent(name: "my-custom-plan-agent", description: nil, mode: "plan", hidden: nil)
            ]
        )

        XCTAssertEqual(buildModeIcon, "hammer")
        XCTAssertEqual(planModeIcon, "checklist")
    }

    @MainActor
    private func makeStore() -> ComposerStore {
        let suiteName = "kodanto-tests-\(UUID().uuidString)"
        defaultsSuites.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ComposerStore(
            modelSelectionStore: ModelSelectionStore(userDefaults: defaults),
            modelVariantSelectionStore: ModelVariantSelectionStore(userDefaults: defaults)
        )
        store.updateSelectedProfile(UUID())
        return store
    }

    @MainActor
    private func makeAgent(name: String, mode: String, hidden: Bool = false) -> OpenCodeAgent {
        OpenCodeAgent(name: name, description: "\(name) agent", mode: mode, hidden: hidden)
    }

    @MainActor
    private func makeUserEnvelope(
        messageID: String,
        sessionID: String,
        createdAt: Double,
        agent: String
    ) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: .user(
                .init(
                    id: messageID,
                    sessionID: sessionID,
                    role: "user",
                    time: .init(created: createdAt),
                    agent: agent,
                    model: .init(providerID: "provider-1", modelID: "model-1"),
                    variant: nil
                )
            ),
            parts: [
                .text(
                    .init(
                        id: "part-\(messageID)",
                        sessionID: sessionID,
                        messageID: messageID,
                        type: "text",
                        text: "Prompt"
                    )
                )
            ]
        )
    }
}

final class SessionUnreadModelTests: XCTestCase {
    private var defaultsSuites: [String] = []

    override func tearDown() {
        for suiteName in defaultsSuites {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaultsSuites.removeAll()
        super.tearDown()
    }

    func testMarkSessionUnreadUpdatesIndicatorWithoutCallingUpdateSession() async {
        await runOnMainActor {
            let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
            let session = TestFixtures.session(
                id: "session-1",
                projectID: project.id,
                directory: project.worktree,
                title: "Session",
                updatedAt: 200
            )

            let service = SessionUnreadMockAPIService()
            let model = self.makeModel(apiService: service)
            model.workspaceStore.applyLoadedProjects([project], profileID: model.selectedProfileID)
            model.workspaceStore.selectProject(project.id)
            model.workspaceStore.applyLoadedSessions([session], statuses: [session.id: .idle], for: project)

            XCTAssertEqual(model.sessionSidebarIndicator(for: session, in: project), .none)
            model.markSessionUnread(sessionID: session.id, in: project.id)

            XCTAssertEqual(model.sessionSidebarIndicator(for: session, in: project), .completedUnread)
            XCTAssertEqual(service.updateCallCount, 0)
        }
    }

    @MainActor
    private func makeModel(apiService: SessionUnreadMockAPIService) -> KodantoAppModel {
        let profile = ServerProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000321") ?? UUID(),
            name: "Test",
            kind: .remote,
            baseURL: "http://localhost:4096",
            username: "opencode",
            password: "pw"
        )
        let suiteName = "kodanto-tests-\(UUID().uuidString)"
        defaultsSuites.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!

        let dependencies = KodantoAppDependencies(
            sidecar: SessionUnreadTestSidecarController(),
            apiFactory: SessionUnreadAPIServiceFactory(service: apiService),
            sseStreamProvider: SessionUnreadSSEStreamProvider(),
            profileStore: SessionUnreadProfileStore(profiles: [profile]),
            modelSelectionStore: ModelSelectionStore(userDefaults: defaults),
            modelVariantSelectionStore: ModelVariantSelectionStore(userDefaults: defaults),
            permissionAutoAcceptStore: PermissionAutoAcceptStore(userDefaults: defaults),
            terminalLayoutStore: TerminalLayoutStore(userDefaults: defaults),
            terminalResumeStore: TerminalResumeStateStore(userDefaults: defaults),
            projectOrderStore: ProjectOrderStore(userDefaults: defaults),
            clock: SessionUnreadTestClock()
        )

        return KodantoAppModel(dependencies: dependencies)
    }
}

final class SessionUnreadWorkspaceStoreTests: XCTestCase {
    func testMarkUnreadIdleSessionSetsCompletedUnreadIndicator() async {
        await runOnMainActor {
            let store = self.makeStore()
            let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
            let session = TestFixtures.session(id: "session-1", directory: project.worktree, updatedAt: 200)

            store.applyLoadedProjects([project], profileID: nil)
            store.selectProject(project.id)
            store.applyLoadedSessions([session], statuses: [session.id: .idle], for: project)

            store.markSessionUnread(session.id, in: project.id)
            XCTAssertEqual(store.sessionSidebarIndicator(for: session, in: project), .completedUnread)
        }
    }

    func testSelectingMarkedUnreadSessionClearsIndicator() async {
        await runOnMainActor {
            let store = self.makeStore()
            let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
            let session = TestFixtures.session(id: "session-1", directory: project.worktree, updatedAt: 200)

            store.applyLoadedProjects([project], profileID: nil)
            store.selectProject(project.id)
            store.applyLoadedSessions([session], statuses: [session.id: .idle], for: project)
            store.markSessionUnread(session.id, in: project.id)

            _ = store.selectSession(session.id, in: project.id)
            XCTAssertEqual(store.sessionSidebarIndicator(for: session, in: project), .none)
        }
    }

    func testMarkUnreadDoesNotOverrideRunningIndicator() async {
        await runOnMainActor {
            let store = self.makeStore()
            let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
            let selectedSession = TestFixtures.session(id: "selected", directory: project.worktree, updatedAt: 300)
            let runningSession = TestFixtures.session(id: "running", directory: project.worktree, updatedAt: 200)

            store.applyLoadedProjects([project], profileID: nil)
            store.selectProject(project.id)
            store.applyLoadedSessions(
                [selectedSession, runningSession],
                statuses: [selectedSession.id: .idle, runningSession.id: .busy],
                for: project
            )
            _ = store.selectSession(selectedSession.id, in: project.id)
            XCTAssertNotEqual(store.selectedSessionID, runningSession.id)

            XCTAssertEqual(store.sessionSidebarIndicator(for: runningSession, in: project), .running)
            store.markSessionUnread(runningSession.id, in: project.id)
            XCTAssertEqual(store.sessionSidebarIndicator(for: runningSession, in: project), .running)
        }
    }

    func testMarkUnreadMissingSessionIsNoOp() async {
        await runOnMainActor {
            let store = self.makeStore()
            let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
            let session = TestFixtures.session(id: "session-1", directory: project.worktree, updatedAt: 200)

            store.applyLoadedProjects([project], profileID: nil)
            store.selectProject(project.id)
            store.applyLoadedSessions([session], statuses: [session.id: .idle], for: project)

            store.markSessionUnread("missing-session", in: project.id)
            XCTAssertEqual(store.sessionSidebarIndicator(for: session, in: project), .none)
        }
    }

    @MainActor
    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(projectOrderStore: SessionUnreadProjectOrderStore())
    }
}

private extension XCTestCase {
    @MainActor
    func runOnMainActor(_ operation: @escaping @MainActor () async throws -> Void) async rethrows {
        try await operation()
    }
}

private final class ComposerAgentMockAPIService: OpenCodeAPIService {
    struct PromptCall {
        let sessionID: String
        let directory: String
        let text: String
        let model: PromptRequestBody.ModelSelection?
        let agent: String?
        let variant: String?
    }

    var configResponse = OpenCodeConfig(model: nil)
    var configProvidersResponse = OpenCodeConfigProviders(
        providers: [
            .init(
                id: "provider-1",
                name: "Provider 1",
                models: [
                    "model-1": .init(id: "model-1", name: "Model 1", variants: nil)
                ]
            )
        ],
        default: ["provider-1": "model-1"]
    )
    var agentsResponse: [OpenCodeAgent] = []
    private(set) var promptCalls: [PromptCall] = []

    func health() async throws -> OpenCodeHealth { fatalError("unused") }
    func pathInfo(directory: String?) async throws -> OpenCodePathInfo { fatalError("unused") }
    func config(directory: String?) async throws -> OpenCodeConfig { configResponse }
    func configProviders(directory: String?) async throws -> OpenCodeConfigProviders { configProvidersResponse }
    func agents() async throws -> [OpenCodeAgent] { agentsResponse }
    func projects() async throws -> [OpenCodeProject] { fatalError("unused") }
    func sessions(directory: String) async throws -> [OpenCodeSession] { fatalError("unused") }
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] { fatalError("unused") }
    func sessionTodos(sessionID: String, directory: String) async throws -> [OpenCodeTodo] { fatalError("unused") }
    func permissions(directory: String) async throws -> [OpenCodePermissionRequest] { fatalError("unused") }
    func questions(directory: String) async throws -> [OpenCodeQuestionRequest] { fatalError("unused") }
    func messages(sessionID: String, directory: String) async throws -> [OpenCodeMessageEnvelope] { fatalError("unused") }
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession { fatalError("unused") }
    func ptySessions(directory: String) async throws -> [OpenCodePTY] { [] }
    func ptySession(ptyID: String, directory: String) async throws -> OpenCodePTY { fatalError("unused") }
    func createPTY(
        directory: String,
        title: String?,
        cwd: String?,
        command: String?,
        args: [String]?
    ) async throws -> OpenCodePTY { fatalError("unused") }
    func updatePTY(
        ptyID: String,
        directory: String,
        title: String?,
        rows: Int?,
        cols: Int?
    ) async throws -> OpenCodePTY { fatalError("unused") }
    func removePTY(ptyID: String, directory: String) async throws {}
    func updateSession(
        sessionID: String,
        directory: String,
        title: String?,
        archivedAt: Double?
    ) async throws -> OpenCodeSession { fatalError("unused") }
    func initializeGitRepository(directory: String) async throws -> OpenCodeProject { fatalError("unused") }
    func sendPrompt(
        sessionID: String,
        directory: String,
        text: String,
        model: PromptRequestBody.ModelSelection?,
        agent: String?,
        variant: String?
    ) async throws {
        promptCalls.append(.init(sessionID: sessionID, directory: directory, text: text, model: model, agent: agent, variant: variant))
    }
    func replyToPermission(requestID: String, directory: String, reply: String) async throws { fatalError("unused") }
    func replyToQuestion(requestID: String, directory: String, answers: [[String]]) async throws { fatalError("unused") }
    func rejectQuestion(requestID: String, directory: String) async throws { fatalError("unused") }
}

private final class SessionUnreadMockAPIService: OpenCodeAPIService {
    private(set) var updateCallCount = 0

    func health() async throws -> OpenCodeHealth { fatalError("unused") }
    func pathInfo(directory: String?) async throws -> OpenCodePathInfo { fatalError("unused") }
    func config(directory: String?) async throws -> OpenCodeConfig { fatalError("unused") }
    func configProviders(directory: String?) async throws -> OpenCodeConfigProviders { fatalError("unused") }
    func agents() async throws -> [OpenCodeAgent] { fatalError("unused") }
    func projects() async throws -> [OpenCodeProject] { fatalError("unused") }
    func sessions(directory: String) async throws -> [OpenCodeSession] { fatalError("unused") }
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] { fatalError("unused") }
    func sessionTodos(sessionID: String, directory: String) async throws -> [OpenCodeTodo] { fatalError("unused") }
    func permissions(directory: String) async throws -> [OpenCodePermissionRequest] { fatalError("unused") }
    func questions(directory: String) async throws -> [OpenCodeQuestionRequest] { fatalError("unused") }
    func messages(sessionID: String, directory: String) async throws -> [OpenCodeMessageEnvelope] { fatalError("unused") }
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession { fatalError("unused") }
    func ptySessions(directory: String) async throws -> [OpenCodePTY] { [] }
    func ptySession(ptyID: String, directory: String) async throws -> OpenCodePTY { fatalError("unused") }
    func createPTY(
        directory: String,
        title: String?,
        cwd: String?,
        command: String?,
        args: [String]?
    ) async throws -> OpenCodePTY { fatalError("unused") }
    func updatePTY(
        ptyID: String,
        directory: String,
        title: String?,
        rows: Int?,
        cols: Int?
    ) async throws -> OpenCodePTY { fatalError("unused") }
    func removePTY(ptyID: String, directory: String) async throws {}
    func updateSession(
        sessionID: String,
        directory: String,
        title: String?,
        archivedAt: Double?
    ) async throws -> OpenCodeSession {
        updateCallCount += 1
        return TestFixtures.session(id: sessionID, directory: directory, updatedAt: Date().timeIntervalSince1970)
    }
    func initializeGitRepository(directory: String) async throws -> OpenCodeProject { fatalError("unused") }
    func sendPrompt(
        sessionID: String,
        directory: String,
        text: String,
        model: PromptRequestBody.ModelSelection?,
        agent: String?,
        variant: String?
    ) async throws { fatalError("unused") }
    func replyToPermission(requestID: String, directory: String, reply: String) async throws { fatalError("unused") }
    func replyToQuestion(requestID: String, directory: String, answers: [[String]]) async throws { fatalError("unused") }
    func rejectQuestion(requestID: String, directory: String) async throws { fatalError("unused") }
}

private struct SessionUnreadAPIServiceFactory: OpenCodeAPIServiceFactory {
    let service: OpenCodeAPIService
    func makeService(profile: ServerProfile) -> OpenCodeAPIService { service }
}

private struct SessionUnreadSSEStreamProvider: OpenCodeSSEStreamProviding {
    func streamGlobalEvents(for profile: ServerProfile) -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct SessionUnreadProfileStore: ServerProfileStoring {
    var profiles: [ServerProfile]
    func load() -> [ServerProfile] { profiles }
    func save(_ profiles: [ServerProfile]) {}
}

private final class SessionUnreadTestSidecarController: SidecarControlling {
    func restart(profile: ServerProfile) async throws {}
    func stop() {}
    func setOutputHandler(_ handler: @escaping (String) -> Void) {}
    func executablePath() throws -> String { "opencode" }
    func executableVersion() throws -> String { "test" }
    func versionsMatch(_ lhs: String, _ rhs: String) -> Bool { lhs == rhs }
}

private struct SessionUnreadTestClock: AppClock {
    var now: Date { .now }
    func sleep(for duration: Duration) async throws {}
}

private struct SessionUnreadProjectOrderStore: ProjectOrderStoring {
    func load(for profileID: UUID) -> [String] { [] }
    func save(_ projectIDs: [String], for profileID: UUID) {}
    func remove(for profileID: UUID) {}
}
