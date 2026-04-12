import XCTest
@testable import kodanto

@MainActor
final class KodantoAppModelSessionActionsTests: XCTestCase {
    func testAddProjectMovesNewProjectToTopOfSidebar() async throws {
        let firstProject = TestFixtures.project(
            id: "project-1",
            worktree: "/tmp/project-1",
            updatedAt: 300
        )
        let secondProject = TestFixtures.project(
            id: "project-2",
            worktree: "/tmp/project-2",
            updatedAt: 200
        )
        let createdProject = TestFixtures.project(
            id: "project-test1",
            worktree: "/Users/matthew/Programming/test1",
            updatedAt: 10
        )

        let service = MockOpenCodeAPIService(
            sessions: [],
            projects: [firstProject, secondProject],
            initializedProjectsByDirectory: [createdProject.worktree: createdProject]
        )
        let model = makeModel(apiService: service)
        model.workspaceStore.applyLoadedProjects([firstProject, secondProject], profileID: model.selectedProfileID)
        model.workspaceStore.selectProject(firstProject.id)

        model.addProject(from: createdProject.worktree)

        let reachedTop = await waitUntil {
            model.projects.first?.id == createdProject.id && model.selectedProjectID == createdProject.id
        }
        XCTAssertTrue(reachedTop)
        XCTAssertEqual(service.initializeGitRepositoryCalls, [createdProject.worktree])
        XCTAssertEqual(model.projects.first?.id, createdProject.id)
        XCTAssertEqual(model.selectedProjectID, createdProject.id)
    }

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

    func testSendPromptFromNewSessionRendersMessagesWithoutSessionReselect() async throws {
        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        let service = MockOpenCodeAPIService(sessions: [])
        let model = makeModel(apiService: service)
        model.workspaceStore.applyLoadedProjects([project], profileID: model.selectedProfileID)
        model.workspaceStore.selectProject(project.id)

        model.createSession(in: project.id)
        model.draftPrompt = "Hello from first prompt"
        model.sendPrompt()

        let createCalled = await waitUntil { service.createCalls.count == 1 }
        XCTAssertTrue(createCalled)
        let promptCalled = await waitUntil { service.promptCalls.count == 1 }
        XCTAssertTrue(promptCalled)
        let renderedMessages = await waitUntil { !model.selectedSessionMessages.isEmpty }
        XCTAssertTrue(renderedMessages)

        guard let firstMessage = model.selectedSessionMessages.first else {
            XCTFail("Expected first message to render for new-session first send")
            return
        }

        switch firstMessage.info {
        case .user:
            break
        case .assistant:
            XCTFail("Expected first rendered message to be the user prompt")
        }

        let renderedTextParts = firstMessage.parts.compactMap { part -> String? in
            guard case .text(let value) = part else { return nil }
            return value.text
        }
        XCTAssertTrue(renderedTextParts.contains("Hello from first prompt"))
    }

    private func waitUntil(
        attempts: Int = 120,
        interval: Duration = .milliseconds(10),
        condition: () -> Bool
    ) async -> Bool {
        for _ in 0 ..< attempts {
            if condition() {
                return true
            }
            try? await Task.sleep(for: interval)
        }
        return false
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
            terminalLayoutStore: TerminalLayoutStore(userDefaults: defaults),
            terminalResumeStore: TerminalResumeStateStore(userDefaults: defaults),
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

    struct CreateCall: Equatable {
        let directory: String
        let title: String?
    }

    struct PromptCall {
        let sessionID: String
        let directory: String
        let text: String
        let model: PromptRequestBody.ModelSelection?
        let agent: String?
        let variant: String?
    }

    private(set) var updateCalls: [UpdateCall] = []
    private(set) var createCalls: [CreateCall] = []
    private(set) var promptCalls: [PromptCall] = []
    private(set) var initializeGitRepositoryCalls: [String] = []
    private(set) var permissionsRequests: [String] = []
    private(set) var questionsRequests: [String] = []
    private(set) var messagesRequests: [(sessionID: String, directory: String)] = []
    private(set) var todosRequests: [(sessionID: String, directory: String)] = []
    private var sessionsByID: [String: OpenCodeSession]
    private var messageEnvelopesBySessionID: [String: [OpenCodeMessageEnvelope]] = [:]
    private var availableProjects: [OpenCodeProject]
    private let availablePathInfo: OpenCodePathInfo
    private var initializedProjectsByDirectory: [String: OpenCodeProject]
    private var sessionSerial = 0

    init(
        sessions: [OpenCodeSession],
        projects: [OpenCodeProject] = [],
        pathInfo: OpenCodePathInfo = .init(
            home: "/tmp",
            state: "/tmp/state",
            config: "/tmp/config",
            worktree: "/tmp",
            directory: "/tmp"
        ),
        initializedProjectsByDirectory: [String: OpenCodeProject] = [:]
    ) {
        sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        availableProjects = projects
        availablePathInfo = pathInfo
        self.initializedProjectsByDirectory = initializedProjectsByDirectory
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
        return messageEnvelopesBySessionID[sessionID] ?? []
    }

    func sessionTodos(sessionID: String, directory: String) async throws -> [OpenCodeTodo] {
        todosRequests.append((sessionID, directory))
        return []
    }

    func health() async throws -> OpenCodeHealth { fatalError("unused") }
    func pathInfo(directory: String?) async throws -> OpenCodePathInfo {
        if let directory {
            return .init(
                home: availablePathInfo.home,
                state: availablePathInfo.state,
                config: availablePathInfo.config,
                worktree: directory,
                directory: directory
            )
        }
        return availablePathInfo
    }
    func config(directory: String?) async throws -> OpenCodeConfig { fatalError("unused") }
    func configProviders(directory: String?) async throws -> OpenCodeConfigProviders { fatalError("unused") }
    func agents() async throws -> [OpenCodeAgent] { [] }
    func projects() async throws -> [OpenCodeProject] { availableProjects }
    func sessions(directory: String) async throws -> [OpenCodeSession] {
        sessionsByID.values.filter { $0.directory == directory }
    }
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] { [:] }
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession {
        createCalls.append(.init(directory: directory, title: title))
        sessionSerial += 1

        let sessionID = "session-created-\(sessionSerial)"
        let now = Date().timeIntervalSince1970
        let created = OpenCodeSession(
            id: sessionID,
            slug: sessionID,
            projectID: "project-1",
            workspaceID: nil,
            directory: directory,
            parentID: nil,
            summary: nil,
            share: nil,
            title: title ?? "Session",
            version: "1",
            time: .init(created: now - 1, updated: now, compacting: nil, archived: nil),
            revert: nil
        )
        sessionsByID[sessionID] = created
        return created
    }
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
    func initializeGitRepository(directory: String) async throws -> OpenCodeProject {
        initializeGitRepositoryCalls.append(directory)

        let created = initializedProjectsByDirectory[directory] ?? TestFixtures.project(
            id: "project-\(UUID().uuidString)",
            worktree: directory,
            updatedAt: Date().timeIntervalSince1970
        )

        if let existingIndex = availableProjects.firstIndex(where: { $0.id == created.id }) {
            availableProjects[existingIndex] = created
        } else {
            availableProjects.append(created)
        }
        return created
    }
    func sendPrompt(
        sessionID: String,
        directory: String,
        text: String,
        model: PromptRequestBody.ModelSelection?,
        agent: String?,
        variant: String?
    ) async throws {
        promptCalls.append(.init(sessionID: sessionID, directory: directory, text: text, model: model, agent: agent, variant: variant))

        let createdAt = Date().timeIntervalSince1970
        let messageID = "message-\(UUID().uuidString)"
        let partID = "part-\(UUID().uuidString)"
        let envelope = OpenCodeMessageEnvelope(
            info: .user(
                .init(
                    id: messageID,
                    sessionID: sessionID,
                    role: "user",
                    time: .init(created: createdAt),
                    agent: "assistant",
                    model: .init(providerID: "provider-1", modelID: "model-1"),
                    variant: variant
                )
            ),
            parts: [
                .text(
                    .init(
                        id: partID,
                        sessionID: sessionID,
                        messageID: messageID,
                        type: "text",
                        text: text
                    )
                )
            ]
        )
        messageEnvelopesBySessionID[sessionID, default: []].append(envelope)
    }
    func disposeInstance(directory: String?) async throws { fatalError("unused") }
    func abortSession(sessionID: String, directory: String) async throws { fatalError("unused") }
    func shareSession(sessionID: String, directory: String) async throws -> OpenCodeSessionShare { fatalError("unused") }
    func unshareSession(sessionID: String, directory: String) async throws -> OpenCodeSessionShare { fatalError("unused") }
    func undo(sessionID: String, directory: String) async throws { fatalError("unused") }
    func redo(sessionID: String, directory: String) async throws { fatalError("unused") }
    func compactSession(sessionID: String, directory: String) async throws { fatalError("unused") }
    func forkSession(sessionID: String, directory: String) async throws -> OpenCodeSession { fatalError("unused") }
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
