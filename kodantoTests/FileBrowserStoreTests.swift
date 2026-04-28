import XCTest
@testable import kodanto

@MainActor
final class FileBrowserStoreTests: XCTestCase {
    private var apiService: MockFileAPIService!
    private var store: FileBrowserStore!

    override func setUp() {
        apiService = MockFileAPIService()
        store = FileBrowserStore(apiService: apiService)
        store.worktreeDirectory = "/project"
    }

    override func tearDown() {
        apiService = nil
        store = nil
    }

    // MARK: - Tab Management

    func testDefaultTabIsChanges() {
        XCTAssertEqual(store.tab, .changes)
    }

    func testSetTabChangesTab() {
        store.setTab(.files)
        XCTAssertEqual(store.tab, .files)
        store.setTab(.changes)
        XCTAssertEqual(store.tab, .changes)
    }

    // MARK: - Loading Directories

    func testLoadDirectoryStoresNodes() async {
        apiService.stubNodes[""] = [
            FileNode(name: "src", path: "src", absolute: "/project/src", type: "directory", ignored: false),
            FileNode(name: "README.md", path: "README.md", absolute: "/project/README.md", type: "file", ignored: false),
        ]

        try? await store.loadDirectory("")

        let nodes = store.children(of: "")
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].name, "src")
        XCTAssertEqual(nodes[1].name, "README.md")
        XCTAssertNil(store.loadError)
    }

    func testLoadDirectoryDoesNotRefetchCachedDirectory() async {
        apiService.stubNodes[""] = [
            FileNode(name: "README.md", path: "README.md", absolute: "/project/README.md", type: "file", ignored: false),
        ]

        try? await store.loadDirectory("")
        apiService.listCallCount = 0

        try? await store.loadDirectory("")

        XCTAssertEqual(apiService.listCallCount, 0, "Should not re-fetch an already loaded directory")
    }

    func testLoadDirectoryForceRefreshFetchesAgain() async {
        apiService.stubNodes[""] = [
            FileNode(name: "README.md", path: "README.md", absolute: "/project/README.md", type: "file", ignored: false),
        ]

        try? await store.loadDirectory("")
        apiService.listCallCount = 0

        try? await store.loadDirectory("", force: true)

        XCTAssertEqual(apiService.listCallCount, 1, "Should re-fetch when force is true")
    }

    func testLoadDirectoryStoresNestedNodes() async {
        apiService.stubNodes["src"] = [
            FileNode(name: "main.swift", path: "src/main.swift", absolute: "/project/src/main.swift", type: "file", ignored: false),
            FileNode(name: "util.swift", path: "src/util.swift", absolute: "/project/src/util.swift", type: "file", ignored: false),
        ]

        try? await store.loadDirectory("src")

        let nodes = store.children(of: "src")
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].name, "main.swift")
    }

    func testLoadDirectorySetsErrorOnFailure() async {
        struct TestError: Error, Equatable {
            let message: String
        }
        apiService.stubError = TestError(message: "network error")

        do {
            try await store.loadDirectory("")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertNotNil(store.loadError)
        }
    }

    func testLoadDirectoryTracksLoadingState() async {
        apiService.stubNodes[""] = [
            FileNode(name: "README.md", path: "README.md", absolute: "/project/README.md", type: "file", ignored: false),
        ]
        apiService.listDelay = 0.05

        XCTAssertTrue(store.loadingPaths.isEmpty)

        let task = Task { try? await store.loadDirectory("") }
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(store.isLoading(path: ""))
        await task.value

        XCTAssertFalse(store.isLoading(path: ""))
    }

    // MARK: - Directory Expand/Collapse

    func testToggleDirectoryExpands() async {
        XCTAssertFalse(store.isExpanded(path: "src"))

        await store.toggleDirectory("src")

        XCTAssertTrue(store.isExpanded(path: "src"))
    }

    func testToggleDirectoryCollapses() async {
        await store.toggleDirectory("src")
        XCTAssertTrue(store.isExpanded(path: "src"))

        await store.toggleDirectory("src")
        XCTAssertFalse(store.isExpanded(path: "src"))
    }

    func testToggleDirectoryLoadsChildrenIfNotCached() async {
        apiService.stubNodes["src"] = [
            FileNode(name: "main.swift", path: "src/main.swift", absolute: "/project/src/main.swift", type: "file", ignored: false),
        ]

        await store.toggleDirectory("src")

        XCTAssertTrue(store.isExpanded(path: "src"))
        let nodes = store.children(of: "src")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].name, "main.swift")
    }

    func testToggleDirectoryDoesNotRefetchCachedChildren() async {
        apiService.stubNodes["src"] = [
            FileNode(name: "main.swift", path: "src/main.swift", absolute: "/project/src/main.swift", type: "file", ignored: false),
        ]

        await store.toggleDirectory("src")
        apiService.listCallCount = 0

        await store.toggleDirectory("src")
        XCTAssertFalse(store.isExpanded(path: "src"))

        await store.toggleDirectory("src")
        XCTAssertTrue(store.isExpanded(path: "src"))
        XCTAssertEqual(apiService.listCallCount, 0)
    }

    // MARK: - Expand to Path

    func testExpandToPathExpandsAllAncestors() async {
        apiService.stubNodes[""] = [
            FileNode(name: "src", path: "src", absolute: "/project/src", type: "directory", ignored: false),
        ]
        apiService.stubNodes["src"] = [
            FileNode(name: "components", path: "src/components", absolute: "/project/src/components", type: "directory", ignored: false),
        ]
        apiService.stubNodes["src/components"] = [
            FileNode(name: "Button.swift", path: "src/components/Button.swift", absolute: "/project/src/components/Button.swift", type: "file", ignored: false),
        ]

        try? await store.expandToParent(of: "src/components/Button.swift")

        XCTAssertTrue(store.isExpanded(path: ""))
        XCTAssertTrue(store.isExpanded(path: "src"))
        XCTAssertTrue(store.isCached(path: "src/components"))
    }

    // MARK: - Reset

    func testResetClearsAllState() async {
        apiService.stubNodes[""] = [
            FileNode(name: "README.md", path: "README.md", absolute: "/project/README.md", type: "file", ignored: false),
        ]
        store.setTab(.files)
        try? await store.loadDirectory("")
        await store.toggleDirectory("src")

        store.reset()

        XCTAssertEqual(store.tab, .changes)
        XCTAssertTrue(store.children(of: "").isEmpty)
        XCTAssertTrue(store.expandedPaths.isEmpty)
        XCTAssertTrue(store.loadingPaths.isEmpty)
        XCTAssertNil(store.loadError)
    }

    // MARK: - hasNodes

    func testHasNodesReturnsTrueWhenNodesLoaded() async {
        apiService.stubNodes[""] = [
            FileNode(name: "README.md", path: "README.md", absolute: "/project/README.md", type: "file", ignored: false),
        ]

        XCTAssertFalse(store.hasNodes)

        try? await store.loadDirectory("")

        XCTAssertTrue(store.hasNodes)
    }

    func testHasNodesIsDirectoryAgnostic() async {
        apiService.stubNodes["src"] = [
            FileNode(name: "main.swift", path: "src/main.swift", absolute: "/project/src/main.swift", type: "file", ignored: false),
        ]

        XCTAssertFalse(store.hasNodes)

        try? await store.loadDirectory("src")

        XCTAssertTrue(store.hasNodes)
    }
}

// MARK: - Mock API Service

private final class MockFileAPIService: OpenCodeAPIService {
    var stubNodes: [String: [FileNode]] = [:]
    var stubError: Error?
    var listCallCount = 0
    var listDelay: TimeInterval = 0

    func health() async throws -> OpenCodeHealth { fatalError("unexpected") }
    func pathInfo(directory: String?) async throws -> OpenCodePathInfo { fatalError("unexpected") }
    func config(directory: String?) async throws -> OpenCodeConfig { fatalError("unexpected") }
    func configProviders(directory: String?) async throws -> OpenCodeConfigProviders { fatalError("unexpected") }
    func agents() async throws -> [OpenCodeAgent] { fatalError("unexpected") }
    func projects() async throws -> [OpenCodeProject] { fatalError("unexpected") }
    func sessions(directory: String) async throws -> [OpenCodeSession] { fatalError("unexpected") }
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] { fatalError("unexpected") }
    func sessionTodos(sessionID: String, directory: String) async throws -> [OpenCodeTodo] { fatalError("unexpected") }
    func permissions(directory: String) async throws -> [OpenCodePermissionRequest] { fatalError("unexpected") }
    func questions(directory: String) async throws -> [OpenCodeQuestionRequest] { fatalError("unexpected") }
    func messages(sessionID: String, directory: String) async throws -> [OpenCodeMessageEnvelope] { fatalError("unexpected") }
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession { fatalError("unexpected") }
    func updateSession(sessionID: String, directory: String, title: String?, archivedAt: Double?) async throws -> OpenCodeSession { fatalError("unexpected") }
    func initializeGitRepository(directory: String) async throws -> OpenCodeProject { fatalError("unexpected") }
    func ptySessions(directory: String) async throws -> [OpenCodePTY] { fatalError("unexpected") }
    func ptySession(ptyID: String, directory: String) async throws -> OpenCodePTY { fatalError("unexpected") }
    func createPTY(directory: String, title: String?, cwd: String?, command: String?, args: [String]?) async throws -> OpenCodePTY { fatalError("unexpected") }
    func updatePTY(ptyID: String, directory: String, title: String?, rows: Int?, cols: Int?) async throws -> OpenCodePTY { fatalError("unexpected") }
    func removePTY(ptyID: String, directory: String) async throws { fatalError("unexpected") }
    func sendPrompt(sessionID: String, directory: String, text: String, model: PromptRequestBody.ModelSelection?, agent: String?, variant: String?) async throws { fatalError("unexpected") }
    func disposeInstance(directory: String?) async throws { fatalError("unexpected") }
    func abortSession(sessionID: String, directory: String) async throws { fatalError("unexpected") }
    func shareSession(sessionID: String, directory: String) async throws -> OpenCodeSessionShare { fatalError("unexpected") }
    func unshareSession(sessionID: String, directory: String) async throws -> OpenCodeSessionShare { fatalError("unexpected") }
    func revert(sessionID: String, messageID: String, directory: String) async throws -> OpenCodeSession { fatalError("unexpected") }
    func unrevert(sessionID: String, directory: String) async throws -> OpenCodeSession { fatalError("unexpected") }
    func compactSession(sessionID: String, directory: String, providerID: String, modelID: String) async throws { fatalError("unexpected") }
    func forkSession(sessionID: String, directory: String) async throws -> OpenCodeSession { fatalError("unexpected") }
    func replyToPermission(requestID: String, directory: String, reply: String) async throws { fatalError("unexpected") }
    func replyToQuestion(requestID: String, directory: String, answers: [[String]]) async throws { fatalError("unexpected") }
    func rejectQuestion(requestID: String, directory: String) async throws { fatalError("unexpected") }

    func fileList(path: String, directory: String) async throws -> [FileNode] {
        listCallCount += 1
        if listDelay > 0 {
            try? await Task.sleep(for: .seconds(listDelay))
        }
        if let error = stubError {
            throw error
        }
        return stubNodes[path] ?? []
    }
}
