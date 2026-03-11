import XCTest
@testable import kodanto

@MainActor
final class KodantoAppModelSessionActionsTests: XCTestCase {
    func testSubmitSessionRenamePatchesTitleAndUpdatesSidebarCache() async throws {
        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        let session = TestFixtures.session(
            id: "session-1",
            projectID: project.id,
            directory: project.worktree,
            title: "Original",
            updatedAt: 200
        )

        let service = MockOpenCodeAPIService(sessions: [session])
        let model = makeModel(apiService: service)
        model.workspaceStore.applyLoadedProjects([project], profileID: model.selectedProfileID)
        model.workspaceStore.selectProject(project.id)
        model.workspaceStore.applyLoadedSessions([session], statuses: [:], for: project)

        try await model.submitSessionRename(sessionID: session.id, in: project.id, newTitle: "Renamed")

        XCTAssertEqual(service.updateCalls.count, 1)
        XCTAssertEqual(service.updateCalls.first?.sessionID, session.id)
        XCTAssertEqual(service.updateCalls.first?.directory, project.worktree)
        XCTAssertEqual(service.updateCalls.first?.title, "Renamed")
        XCTAssertNil(service.updateCalls.first?.archivedAt)
        XCTAssertEqual(model.sessions(for: project).first?.title, "Renamed")
    }

    func testSubmitSessionArchivePatchesArchivedTimeAndFallsBackSelection() async throws {
        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        let olderSession = TestFixtures.session(
            id: "session-1",
            projectID: project.id,
            directory: project.worktree,
            title: "Older",
            updatedAt: 190
        )
        let selectedSession = TestFixtures.session(
            id: "session-2",
            projectID: project.id,
            directory: project.worktree,
            title: "Selected",
            updatedAt: 200
        )

        let service = MockOpenCodeAPIService(sessions: [olderSession, selectedSession])
        let model = makeModel(apiService: service)
        model.workspaceStore.applyLoadedProjects([project], profileID: model.selectedProfileID)
        model.workspaceStore.selectProject(project.id)
        model.workspaceStore.applyLoadedSessions([olderSession, selectedSession], statuses: [:], for: project)
        _ = model.workspaceStore.selectSession(selectedSession.id, in: project.id)

        try await model.submitSessionArchive(sessionID: selectedSession.id, in: project.id)

        XCTAssertEqual(service.updateCalls.count, 1)
        XCTAssertEqual(service.updateCalls.first?.sessionID, selectedSession.id)
        XCTAssertNil(service.updateCalls.first?.title)
        XCTAssertNotNil(service.updateCalls.first?.archivedAt)
        XCTAssertEqual(model.selectedSessionID, olderSession.id)
        XCTAssertEqual(model.sessions(for: project).map(\.id), [olderSession.id])
        XCTAssertGreaterThanOrEqual(service.permissionsRequests.count, 1)
        XCTAssertGreaterThanOrEqual(service.questionsRequests.count, 1)
        XCTAssertGreaterThanOrEqual(service.messagesRequests.count, 1)
        XCTAssertGreaterThanOrEqual(service.todosRequests.count, 1)
    }

    private func makeModel(apiService: MockOpenCodeAPIService) -> KodantoAppModel {
        let profile = ServerProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123") ?? UUID(),
            name: "Test",
            kind: .remote,
            baseURL: "http://localhost:4096",
            username: "opencode",
            password: "pw"
        )
        let defaults = UserDefaults(suiteName: "kodanto-tests-\(UUID().uuidString)")!

        let dependencies = KodantoAppDependencies(
            sidecar: TestSidecarController(),
            apiFactory: TestAPIServiceFactory(service: apiService),
            sseStreamProvider: TestSSEStreamProvider(),
            profileStore: TestProfileStore(profiles: [profile]),
            modelSelectionStore: ModelSelectionStore(userDefaults: defaults),
            modelVariantSelectionStore: ModelVariantSelectionStore(userDefaults: defaults),
            permissionAutoAcceptStore: PermissionAutoAcceptStore(userDefaults: defaults),
            projectOrderStore: ProjectOrderStore(userDefaults: defaults),
            clock: TestClock()
        )

        return KodantoAppModel(dependencies: dependencies)
    }
}

private final class MockOpenCodeAPIService: OpenCodeAPIService {
    struct UpdateCall: Equatable {
        let sessionID: String
        let directory: String
        let title: String?
        let archivedAt: Double?
    }

    private(set) var updateCalls: [UpdateCall] = []
    private(set) var permissionsRequests: [String] = []
    private(set) var questionsRequests: [String] = []
    private(set) var messagesRequests: [(sessionID: String, directory: String)] = []
    private(set) var todosRequests: [(sessionID: String, directory: String)] = []
    private var sessionsByID: [String: OpenCodeSession]

    init(sessions: [OpenCodeSession]) {
        sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    func updateSession(
        sessionID: String,
        directory: String,
        title: String?,
        archivedAt: Double?
    ) async throws -> OpenCodeSession {
        updateCalls.append(.init(sessionID: sessionID, directory: directory, title: title, archivedAt: archivedAt))

        guard let current = sessionsByID[sessionID] else {
            throw OpenCodeAPIError.serverError(statusCode: 404, message: "Missing session")
        }

        let next = OpenCodeSession(
            id: current.id,
            slug: current.slug,
            projectID: current.projectID,
            workspaceID: current.workspaceID,
            directory: current.directory,
            parentID: current.parentID,
            summary: current.summary,
            share: current.share,
            title: title ?? current.title,
            version: current.version,
            time: .init(
                created: current.time.created,
                updated: max(current.time.updated + 1, Date().timeIntervalSince1970),
                compacting: current.time.compacting,
                archived: archivedAt ?? current.time.archived
            ),
            revert: current.revert
        )
        sessionsByID[sessionID] = next
        return next
    }

    func permissions(directory: String) async throws -> [OpenCodePermissionRequest] {
        permissionsRequests.append(directory)
        return []
    }

    func questions(directory: String) async throws -> [OpenCodeQuestionRequest] {
        questionsRequests.append(directory)
        return []
    }

    func messages(sessionID: String, directory: String) async throws -> [OpenCodeMessageEnvelope] {
        messagesRequests.append((sessionID, directory))
        return []
    }

    func sessionTodos(sessionID: String, directory: String) async throws -> [OpenCodeTodo] {
        todosRequests.append((sessionID, directory))
        return []
    }

    func health() async throws -> OpenCodeHealth { fatalError("unused") }
    func pathInfo(directory: String?) async throws -> OpenCodePathInfo { fatalError("unused") }
    func config(directory: String?) async throws -> OpenCodeConfig { fatalError("unused") }
    func configProviders(directory: String?) async throws -> OpenCodeConfigProviders { fatalError("unused") }
    func projects() async throws -> [OpenCodeProject] { fatalError("unused") }
    func sessions(directory: String) async throws -> [OpenCodeSession] { fatalError("unused") }
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] { fatalError("unused") }
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession { fatalError("unused") }
    func initializeGitRepository(directory: String) async throws -> OpenCodeProject { fatalError("unused") }
    func sendPrompt(
        sessionID: String,
        directory: String,
        text: String,
        model: PromptRequestBody.ModelSelection?,
        variant: String?
    ) async throws { fatalError("unused") }
    func replyToPermission(requestID: String, directory: String, reply: String) async throws { fatalError("unused") }
    func replyToQuestion(requestID: String, directory: String, answers: [[String]]) async throws { fatalError("unused") }
    func rejectQuestion(requestID: String, directory: String) async throws { fatalError("unused") }
}

private struct TestAPIServiceFactory: OpenCodeAPIServiceFactory {
    let service: OpenCodeAPIService
    func makeService(profile: ServerProfile) -> OpenCodeAPIService { service }
}

private struct TestSSEStreamProvider: OpenCodeSSEStreamProviding {
    func streamGlobalEvents(for profile: ServerProfile) -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct TestProfileStore: ServerProfileStoring {
    var profiles: [ServerProfile]
    func load() -> [ServerProfile] { profiles }
    func save(_ profiles: [ServerProfile]) {}
}

private final class TestSidecarController: SidecarControlling {
    func restart(profile: ServerProfile) async throws {}
    func stop() {}
    func setOutputHandler(_ handler: @escaping (String) -> Void) {}
    func executablePath() throws -> String { "opencode" }
    func executableVersion() throws -> String { "test" }
    func versionsMatch(_ lhs: String, _ rhs: String) -> Bool { lhs == rhs }
}

private struct TestClock: AppClock {
    var now: Date { .now }
    func sleep(for duration: Duration) async throws {}
}
