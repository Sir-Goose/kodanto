import Foundation
import XCTest
@testable import kodanto

@MainActor
final class TerminalStoreTests: XCTestCase {
    func testEnsureConnectedCreatesPTYWhenNoneExists() async {
        let service = MockTerminalAPIService()
        service.listedPTYs = []
        service.createdPTY = makePTY(id: "pty-created")

        let harness = ConnectionHarness()
        let store = makeStore(harness: harness)
        store.setActiveDirectory("/tmp/project-a")

        await store.ensureConnected(
            directory: "/tmp/project-a",
            launchConfiguration: localLaunchConfiguration(directory: "/tmp/project-a"),
            client: service,
            requestBuilder: requestBuilder
        )

        XCTAssertEqual(service.createCalls, ["/tmp/project-a"])
        XCTAssertEqual(store.activePTY?.id, "pty-created")
        XCTAssertEqual(store.activePhase, .connected)
        XCTAssertEqual(harness.connections.count, 1)
    }

    func testEnsureConnectedMaintainsSeparateWorkspaceSessions() async {
        let service = MockTerminalAPIService()
        service.listedPTYs = []

        let harness = ConnectionHarness()
        let store = makeStore(harness: harness)

        store.setActiveDirectory("/tmp/project-a")
        await store.ensureConnected(
            directory: "/tmp/project-a",
            launchConfiguration: localLaunchConfiguration(directory: "/tmp/project-a"),
            client: service,
            requestBuilder: requestBuilder
        )

        store.setActiveDirectory("/tmp/project-b")
        await store.ensureConnected(
            directory: "/tmp/project-b",
            launchConfiguration: localLaunchConfiguration(directory: "/tmp/project-b"),
            client: service,
            requestBuilder: requestBuilder
        )

        XCTAssertEqual(service.createCalls, ["/tmp/project-a", "/tmp/project-b"])
        XCTAssertEqual(store.activeDirectory, "/tmp/project-b")
        XCTAssertEqual(store.activePTY?.id, "pty-2")
        XCTAssertEqual(harness.connections.count, 2)
    }

    func testPTYExitedEventClearsActiveSession() async {
        let service = MockTerminalAPIService()
        service.listedPTYs = []

        let harness = ConnectionHarness()
        let store = makeStore(harness: harness)
        store.setActiveDirectory("/tmp/project-a")
        await store.ensureConnected(
            directory: "/tmp/project-a",
            launchConfiguration: localLaunchConfiguration(directory: "/tmp/project-a"),
            client: service,
            requestBuilder: requestBuilder
        )

        let ptyID = try XCTUnwrap(store.activePTY?.id)
        store.handleGlobalEvent(
            OpenCodeGlobalEvent(
                directory: "/tmp/project-a",
                payload: .ptyExited(.init(id: ptyID, exitCode: 0))
            )
        )

        await Task.yield()

        XCTAssertNil(store.activePTY)
        XCTAssertEqual(store.activePhase, .closed)
        XCTAssertEqual(harness.connections.first?.disconnectCalls, 1)
    }

    func testConsumeActiveOutputChunksDrainsBufferedOutput() async {
        let service = MockTerminalAPIService()
        service.listedPTYs = []

        let harness = ConnectionHarness()
        let store = makeStore(harness: harness)
        store.setActiveDirectory("/tmp/project-a")
        await store.ensureConnected(
            directory: "/tmp/project-a",
            launchConfiguration: localLaunchConfiguration(directory: "/tmp/project-a"),
            client: service,
            requestBuilder: requestBuilder
        )

        harness.connections.first?.emitOutput("hello")
        harness.connections.first?.emitOutput(" world")

        await Task.yield()

        XCTAssertEqual(store.consumeActiveOutputChunks(), ["hello", " world"])
        XCTAssertTrue(store.consumeActiveOutputChunks().isEmpty)
    }

    func testEnsureConnectedRecreatesCachedPTYWhenShellPolicyChanges() async {
        let service = MockTerminalAPIService()
        service.listedPTYs = []

        let harness = ConnectionHarness()
        let store = makeStore(harness: harness)
        let directory = "/tmp/project-a"
        store.setActiveDirectory(directory)

        await store.ensureConnected(
            directory: directory,
            launchConfiguration: remoteLaunchConfiguration(directory: directory),
            client: service,
            requestBuilder: requestBuilder
        )

        await store.ensureConnected(
            directory: directory,
            launchConfiguration: localLaunchConfiguration(directory: directory),
            client: service,
            requestBuilder: requestBuilder
        )

        XCTAssertEqual(service.removeCalls, [directory + "/pty-1"])
        XCTAssertEqual(service.createCalls, [directory, directory])
        XCTAssertEqual(store.activePTY?.command, "/bin/zsh")
        XCTAssertTrue(store.activePTY?.args.contains("-l") == true)
    }

    private func makeStore(harness: ConnectionHarness) -> TerminalStore {
        TerminalStore(
            connectionFactory: { request, onConnected, onOutput, onCursor, onDisconnect in
                harness.makeConnection(
                    request: request,
                    onConnected: onConnected,
                    onOutput: onOutput,
                    onCursor: onCursor,
                    onDisconnect: onDisconnect
                )
            }
        )
    }

    private func requestBuilder(ptyID: String, directory: String, cursor: Int) throws -> URLRequest {
        var components = URLComponents(string: "wss://localhost/pty/\(ptyID)/connect")!
        components.queryItems = [
            URLQueryItem(name: "directory", value: directory),
            URLQueryItem(name: "cursor", value: String(cursor))
        ]
        return URLRequest(url: components.url!)
    }

    private func makePTY(id: String) -> OpenCodePTY {
        OpenCodePTY(
            id: id,
            title: "Terminal",
            command: "zsh",
            args: ["-l"],
            cwd: "/tmp/project",
            status: .running,
            pid: 123
        )
    }

    private func localLaunchConfiguration(directory: String) -> TerminalStore.LaunchConfiguration {
        TerminalStore.LaunchConfiguration(
            title: "Terminal",
            cwd: directory,
            command: "/bin/zsh",
            args: ["-l"],
            enforceShell: true
        )
    }

    private func remoteLaunchConfiguration(directory: String) -> TerminalStore.LaunchConfiguration {
        TerminalStore.LaunchConfiguration(
            title: "Terminal",
            cwd: directory,
            command: nil,
            args: nil,
            enforceShell: false
        )
    }
}

private final class ConnectionHarness {
    private(set) var connections: [FakePTYConnection] = []

    func makeConnection(
        request: URLRequest,
        onConnected: @escaping @Sendable () -> Void,
        onOutput: @escaping @Sendable (String) -> Void,
        onCursor: @escaping @Sendable (Int) -> Void,
        onDisconnect: @escaping @Sendable (Error?) -> Void
    ) -> PTYWebSocketConnecting {
        let connection = FakePTYConnection(
            request: request,
            onConnected: onConnected,
            onOutput: onOutput,
            onCursor: onCursor,
            onDisconnect: onDisconnect
        )
        connections.append(connection)
        return connection
    }
}

private final class FakePTYConnection: PTYWebSocketConnecting {
    let request: URLRequest
    private let onConnected: @Sendable () -> Void
    private let onOutput: @Sendable (String) -> Void
    private let onCursor: @Sendable (Int) -> Void
    private let onDisconnect: @Sendable (Error?) -> Void

    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0
    private(set) var sentInputs: [String] = []

    init(
        request: URLRequest,
        onConnected: @escaping @Sendable () -> Void,
        onOutput: @escaping @Sendable (String) -> Void,
        onCursor: @escaping @Sendable (Int) -> Void,
        onDisconnect: @escaping @Sendable (Error?) -> Void
    ) {
        self.request = request
        self.onConnected = onConnected
        self.onOutput = onOutput
        self.onCursor = onCursor
        self.onDisconnect = onDisconnect
    }

    func connect() async {
        connectCalls += 1
        onConnected()
    }

    func sendInput(_ text: String) async throws {
        sentInputs.append(text)
    }

    func disconnect() async {
        disconnectCalls += 1
        onDisconnect(nil)
    }

    func emitOutput(_ text: String) {
        onOutput(text)
    }

    func emitCursor(_ cursor: Int) {
        onCursor(cursor)
    }
}

private final class MockTerminalAPIService: OpenCodeAPIService {
    var listedPTYs: [OpenCodePTY] = []
    var createdPTY = OpenCodePTY(
        id: "pty-1",
        title: "Terminal",
        command: "zsh",
        args: [],
        cwd: "/tmp/project",
        status: .running,
        pid: 1
    )

    private(set) var createCalls: [String] = []
    private(set) var removeCalls: [String] = []

    func ptySessions(directory: String) async throws -> [OpenCodePTY] {
        listedPTYs
    }

    func ptySession(ptyID: String, directory: String) async throws -> OpenCodePTY {
        listedPTYs.first(where: { $0.id == ptyID }) ?? createdPTY
    }

    func createPTY(
        directory: String,
        title: String?,
        cwd: String?,
        command: String?,
        args: [String]?
    ) async throws -> OpenCodePTY {
        createCalls.append(directory)
        let index = createCalls.count
        return OpenCodePTY(
            id: "pty-\(index)",
            title: title ?? "Terminal",
            command: command ?? "bash",
            args: args ?? [],
            cwd: cwd ?? directory,
            status: .running,
            pid: index
        )
    }

    func updatePTY(
        ptyID: String,
        directory: String,
        title: String?,
        rows: Int?,
        cols: Int?
    ) async throws -> OpenCodePTY {
        ptySession(ptyID: ptyID, directory: directory)
    }

    func removePTY(ptyID: String, directory: String) async throws {
        removeCalls.append("\(directory)/\(ptyID)")
    }

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
    ) async throws { fatalError("unused") }
    func replyToPermission(requestID: String, directory: String, reply: String) async throws { fatalError("unused") }
    func replyToQuestion(requestID: String, directory: String, answers: [[String]]) async throws { fatalError("unused") }
    func rejectQuestion(requestID: String, directory: String) async throws { fatalError("unused") }
}
