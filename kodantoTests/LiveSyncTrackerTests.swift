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

@MainActor
final class ComposerAgentSelectionTests: XCTestCase {
    private static var retainedStores: [ComposerStore] = []

    func testRefreshModelCatalogFiltersPrimaryVisibleAgents() async throws {
        let store = makeStore()
        let service = ComposerAgentMockAPIService()
        service.agentsResponse = [
            makeAgent(name: "build", mode: "primary"),
            makeAgent(name: "plan", mode: "primary"),
            makeAgent(name: "general", mode: "subagent"),
            makeAgent(name: "hidden", mode: "primary", hidden: true),
            makeAgent(name: "custom", mode: "all")
        ]

        try await store.refreshModelCatalog(using: service)

        XCTAssertEqual(store.availablePrimaryAgents.map(\.name), ["build", "plan", "custom"])
        XCTAssertEqual(store.selectedPromptAgent, "build")
    }

    func testSyncSelectedAgentUsesLatestUserMessageAgentWhenAvailable() {
        let store = makeStore()
        store.availablePrimaryAgents = [
            makeAgent(name: "build", mode: "primary"),
            makeAgent(name: "plan", mode: "primary")
        ]
        store.selectedAgentName = "build"

        let messages: [OpenCodeMessageEnvelope] = [
            makeUserEnvelope(messageID: "m1", sessionID: "session-1", createdAt: 1, agent: "build"),
            makeUserEnvelope(messageID: "m2", sessionID: "session-1", createdAt: 2, agent: "plan")
        ]

        store.syncSelectedAgent(from: messages)

        XCTAssertEqual(store.selectedPromptAgent, "plan")
    }

    func testSyncSelectedAgentFallsBackWhenHistoricalAgentUnavailable() {
        let store = makeStore()
        store.availablePrimaryAgents = [
            makeAgent(name: "build", mode: "primary"),
            makeAgent(name: "plan", mode: "primary")
        ]
        store.selectedAgentName = "build"

        let messages: [OpenCodeMessageEnvelope] = [
            makeUserEnvelope(messageID: "m1", sessionID: "session-1", createdAt: 1, agent: "my-custom-agent")
        ]

        store.syncSelectedAgent(from: messages)

        XCTAssertEqual(store.selectedPromptAgent, "build")
    }

    func testSubmitPromptPassesSelectedAgent() async throws {
        let store = makeStore()
        let service = ComposerAgentMockAPIService()
        store.availablePrimaryAgents = [
            makeAgent(name: "build", mode: "primary"),
            makeAgent(name: "plan", mode: "primary")
        ]
        store.selectAgent("plan")
        store.draftPrompt = "Use plan mode"

        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        let session = TestFixtures.session(id: "session-1", directory: project.worktree, updatedAt: 100)

        try await store.submitPrompt(using: service, project: project, session: session) {}

        XCTAssertEqual(service.promptCalls.count, 1)
        XCTAssertEqual(service.promptCalls.first?.agent, "plan")
    }

    func testSubmitPromptWithoutAvailableAgentsSendsNilAgent() async throws {
        let store = makeStore()
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

    private func makeStore() -> ComposerStore {
        let defaults = UserDefaults(suiteName: "kodanto-tests-\(UUID().uuidString)")!
        let store = ComposerStore(
            modelSelectionStore: ModelSelectionStore(userDefaults: defaults),
            modelVariantSelectionStore: ModelVariantSelectionStore(userDefaults: defaults)
        )
        store.updateSelectedProfile(UUID())
        Self.retainedStores.append(store)
        return store
    }

    private func makeAgent(name: String, mode: String, hidden: Bool = false) -> OpenCodeAgent {
        OpenCodeAgent(name: name, description: "\(name) agent", mode: mode, hidden: hidden)
    }

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
