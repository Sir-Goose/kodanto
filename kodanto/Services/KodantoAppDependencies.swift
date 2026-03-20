import Foundation

protocol OpenCodeAPIService {
    func health() async throws -> OpenCodeHealth
    func pathInfo(directory: String?) async throws -> OpenCodePathInfo
    func config(directory: String?) async throws -> OpenCodeConfig
    func configProviders(directory: String?) async throws -> OpenCodeConfigProviders
    func agents() async throws -> [OpenCodeAgent]
    func projects() async throws -> [OpenCodeProject]
    func sessions(directory: String) async throws -> [OpenCodeSession]
    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus]
    func sessionTodos(sessionID: String, directory: String) async throws -> [OpenCodeTodo]
    func permissions(directory: String) async throws -> [OpenCodePermissionRequest]
    func questions(directory: String) async throws -> [OpenCodeQuestionRequest]
    func messages(sessionID: String, directory: String) async throws -> [OpenCodeMessageEnvelope]
    func createSession(directory: String, title: String?) async throws -> OpenCodeSession
    func updateSession(
        sessionID: String,
        directory: String,
        title: String?,
        archivedAt: Double?
    ) async throws -> OpenCodeSession
    func initializeGitRepository(directory: String) async throws -> OpenCodeProject
    func ptySessions(directory: String) async throws -> [OpenCodePTY]
    func ptySession(ptyID: String, directory: String) async throws -> OpenCodePTY
    func createPTY(
        directory: String,
        title: String?,
        cwd: String?,
        command: String?,
        args: [String]?
    ) async throws -> OpenCodePTY
    func updatePTY(
        ptyID: String,
        directory: String,
        title: String?,
        rows: Int?,
        cols: Int?
    ) async throws -> OpenCodePTY
    func removePTY(ptyID: String, directory: String) async throws
    func sendPrompt(
        sessionID: String,
        directory: String,
        text: String,
        model: PromptRequestBody.ModelSelection?,
        agent: String?,
        variant: String?
    ) async throws
    func disposeInstance(directory: String?) async throws
    func abortSession(sessionID: String, directory: String) async throws
    func replyToPermission(requestID: String, directory: String, reply: String) async throws
    func replyToQuestion(requestID: String, directory: String, answers: [[String]]) async throws
    func rejectQuestion(requestID: String, directory: String) async throws
}

protocol OpenCodeAPIServiceFactory {
    func makeService(profile: ServerProfile) -> OpenCodeAPIService
}

protocol OpenCodeSSEStreamProviding {
    func streamGlobalEvents(for profile: ServerProfile) -> AsyncThrowingStream<OpenCodeGlobalEvent, Error>
}

protocol SidecarControlling: AnyObject {
    func restart(profile: ServerProfile) async throws
    func stop()
    func setOutputHandler(_ handler: @escaping (String) -> Void)
    func executablePath() throws -> String
    func executableVersion() throws -> String
    func versionsMatch(_ lhs: String, _ rhs: String) -> Bool
}

protocol AppClock {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct KodantoAppDependencies {
    let sidecar: SidecarControlling
    let apiFactory: OpenCodeAPIServiceFactory
    let sseStreamProvider: OpenCodeSSEStreamProviding
    let profileStore: ServerProfileStoring
    let modelSelectionStore: ModelSelectionStoring
    let modelVariantSelectionStore: ModelVariantSelectionStoring
    let permissionAutoAcceptStore: PermissionAutoAcceptStoring
    let terminalLayoutStore: TerminalLayoutStoring
    let terminalResumeStore: TerminalResumeStateStoring
    let projectOrderStore: ProjectOrderStoring
    let clock: AppClock

    static func live(userDefaults: UserDefaults = .standard) -> KodantoAppDependencies {
        KodantoAppDependencies(
            sidecar: LiveSidecarController(),
            apiFactory: LiveOpenCodeAPIServiceFactory(),
            sseStreamProvider: LiveOpenCodeSSEStreamProvider(),
            profileStore: ServerProfileStore(userDefaults: userDefaults),
            modelSelectionStore: ModelSelectionStore(userDefaults: userDefaults),
            modelVariantSelectionStore: ModelVariantSelectionStore(userDefaults: userDefaults),
            permissionAutoAcceptStore: PermissionAutoAcceptStore(userDefaults: userDefaults),
            terminalLayoutStore: TerminalLayoutStore(userDefaults: userDefaults),
            terminalResumeStore: TerminalResumeStateStore(userDefaults: userDefaults),
            projectOrderStore: ProjectOrderStore(userDefaults: userDefaults),
            clock: SystemAppClock()
        )
    }
}

extension OpenCodeAPIClient: OpenCodeAPIService {}

private struct LiveOpenCodeAPIServiceFactory: OpenCodeAPIServiceFactory {
    func makeService(profile: ServerProfile) -> OpenCodeAPIService {
        OpenCodeAPIClient(profile: profile)
    }
}

private struct LiveOpenCodeSSEStreamProvider: OpenCodeSSEStreamProviding {
    func streamGlobalEvents(for profile: ServerProfile) -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
        OpenCodeSSEClient(profile: profile).streamGlobalEvents()
    }
}

private final class LiveSidecarController: SidecarControlling {
    private let process = SidecarProcess()

    func restart(profile: ServerProfile) async throws {
        try await process.restart(profile: profile)
    }

    func stop() {
        process.stop()
    }

    func setOutputHandler(_ handler: @escaping (String) -> Void) {
        process.setOutputHandler(handler)
    }

    func executablePath() throws -> String {
        try SidecarProcess.executablePath()
    }

    func executableVersion() throws -> String {
        try SidecarProcess.executableVersion()
    }

    func versionsMatch(_ lhs: String, _ rhs: String) -> Bool {
        SidecarProcess.versionsMatch(lhs, rhs)
    }
}

private struct SystemAppClock: AppClock {
    var now: Date { .now }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
