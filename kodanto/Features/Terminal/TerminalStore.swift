import Foundation
import Observation

@MainActor
@Observable
final class TerminalStore {
    struct LaunchConfiguration: Equatable {
        let title: String
        let cwd: String
        let command: String?
        let args: [String]?
        let enforceShell: Bool
    }

    enum ConnectionPhase: Equatable {
        case closed
        case loading
        case connecting
        case connected
        case failed(String)

        var isConnected: Bool {
            if case .connected = self {
                return true
            }
            return false
        }
    }

    typealias ConnectionFactory = (
        _ request: URLRequest,
        _ onConnected: @escaping @Sendable () -> Void,
        _ onOutput: @escaping @Sendable (String) -> Void,
        _ onCursor: @escaping @Sendable (Int) -> Void,
        _ onDisconnect: @escaping @Sendable (Error?) -> Void
    ) -> PTYWebSocketConnecting

    private struct WorkspaceSession {
        var pty: OpenCodePTY?
        var cursor: Int = 0
        var phase: ConnectionPhase = .closed
        var rows: Int?
        var cols: Int?
        var queuedOutput: [String] = []
        var outputRevision: Int = 0
        var connection: PTYWebSocketConnecting?
        var connectionToken = UUID()
    }

    private let connectionFactory: ConnectionFactory

    private var sessionsByDirectory: [String: WorkspaceSession] = [:]

    var activeDirectory: String?
    var activePTY: OpenCodePTY?
    var activePhase: ConnectionPhase = .closed
    var activeOutputRevision: Int = 0

    init(connectionFactory: @escaping ConnectionFactory) {
        self.connectionFactory = connectionFactory
    }

    convenience init() {
        self.init(connectionFactory: Self.makeLiveConnection)
    }

    private static func makeLiveConnection(
        request: URLRequest,
        onConnected: @escaping @Sendable () -> Void,
        onOutput: @escaping @Sendable (String) -> Void,
        onCursor: @escaping @Sendable (Int) -> Void,
        onDisconnect: @escaping @Sendable (Error?) -> Void
    ) -> PTYWebSocketConnecting {
        LivePTYWebSocketConnection(
            request: request,
            onConnected: onConnected,
            onOutput: onOutput,
            onCursor: onCursor,
            onDisconnect: onDisconnect
        )
    }

    var activeErrorMessage: String? {
        if case .failed(let message) = activePhase {
            return message
        }
        return nil
    }

    func setActiveDirectory(_ directory: String?) {
        activeDirectory = directory
        syncActiveSnapshot()
    }

    func ensureConnected(
        directory: String,
        launchConfiguration: LaunchConfiguration,
        client: OpenCodeAPIService,
        requestBuilder: (_ ptyID: String, _ directory: String, _ cursor: Int) throws -> URLRequest
    ) async {
        var session = sessionsByDirectory[directory] ?? WorkspaceSession()

        if let cachedPTY = session.pty,
           cachedPTY.status == .running,
           !isReusable(cachedPTY, configuration: launchConfiguration) {
            if let connection = session.connection {
                session.connection = nil
                session.connectionToken = UUID()
                sessionsByDirectory[directory] = session
                syncActiveSnapshot()
                await connection.disconnect()
                session = sessionsByDirectory[directory] ?? session
            }

            do {
                try await client.removePTY(ptyID: cachedPTY.id, directory: directory)
            } catch {
                // Proceed with recreation even if stale session cleanup fails.
            }

            session.pty = nil
            session.cursor = 0
            session.phase = .closed
            sessionsByDirectory[directory] = session
            syncActiveSnapshot()
        }

        if session.connection != nil,
           let pty = session.pty,
           pty.status == .running,
           isReusable(pty, configuration: launchConfiguration) {
            sessionsByDirectory[directory] = session
            syncActiveSnapshot()
            return
        }

        if session.pty == nil || session.pty?.status == .exited {
            session.phase = .loading
            sessionsByDirectory[directory] = session
            syncActiveSnapshot()

            do {
                let existing = try await client.ptySessions(directory: directory)
                let resolved = existing.first(where: { pty in
                    pty.status == .running && isReusable(pty, configuration: launchConfiguration)
                })
                if let resolved {
                    session.pty = resolved
                } else {
                    session.pty = try await client.createPTY(
                        directory: directory,
                        title: launchConfiguration.title,
                        cwd: launchConfiguration.cwd,
                        command: launchConfiguration.command,
                        args: launchConfiguration.args
                    )
                }
            } catch {
                session.phase = .failed(error.localizedDescription)
                sessionsByDirectory[directory] = session
                syncActiveSnapshot()
                return
            }
        }

        guard let pty = session.pty else {
            session.phase = .failed("Unable to create terminal session.")
            sessionsByDirectory[directory] = session
            syncActiveSnapshot()
            return
        }

        let token = UUID()
        session.connectionToken = token
        session.phase = .connecting

        let request: URLRequest
        do {
            request = try requestBuilder(pty.id, directory, max(session.cursor, 0))
        } catch {
            session.phase = .failed(error.localizedDescription)
            sessionsByDirectory[directory] = session
            syncActiveSnapshot()
            return
        }

        let connection = connectionFactory(
            request,
            { [self] in
                Task { @MainActor in
                    self.handleConnectionOpened(directory: directory, token: token)
                }
            },
            { [self] output in
                Task { @MainActor in
                    self.handleConnectionOutput(directory: directory, token: token, output: output)
                }
            },
            { [self] cursor in
                Task { @MainActor in
                    self.handleCursor(directory: directory, token: token, cursor: cursor)
                }
            },
            { [self] error in
                Task { @MainActor in
                    self.handleConnectionClosed(directory: directory, token: token, error: error)
                }
            }
        )

        session.connection = connection
        sessionsByDirectory[directory] = session
        syncActiveSnapshot()

        await connection.connect()
    }

    func retryActiveConnection(
        launchConfiguration: LaunchConfiguration,
        client: OpenCodeAPIService,
        requestBuilder: (_ ptyID: String, _ directory: String, _ cursor: Int) throws -> URLRequest
    ) async {
        guard let directory = activeDirectory else { return }
        await disconnectSession(directory: directory)
        await ensureConnected(
            directory: directory,
            launchConfiguration: launchConfiguration,
            client: client,
            requestBuilder: requestBuilder
        )
    }

    func disconnectAll() async {
        let connections = sessionsByDirectory.values.compactMap(\.connection)
        for connection in connections {
            await connection.disconnect()
        }

        sessionsByDirectory.removeAll()
        syncActiveSnapshot()
    }

    func consumeActiveOutputChunks() -> [String] {
        guard let directory = activeDirectory,
              var session = sessionsByDirectory[directory],
              !session.queuedOutput.isEmpty
        else {
            return []
        }

        let chunks = session.queuedOutput
        session.queuedOutput.removeAll(keepingCapacity: true)
        sessionsByDirectory[directory] = session
        return chunks
    }

    func sendInputToActive(_ input: String) async {
        guard !input.isEmpty,
              let directory = activeDirectory,
              let connection = sessionsByDirectory[directory]?.connection
        else {
            return
        }

        do {
            try await connection.sendInput(input)
        } catch {
            markFailed(directory: directory, message: error.localizedDescription)
        }
    }

    func updateActiveSize(rows: Int, cols: Int, client: OpenCodeAPIService) async {
        guard rows > 0, cols > 0,
              let directory = activeDirectory,
              var session = sessionsByDirectory[directory],
              let pty = session.pty
        else {
            return
        }

        if session.rows == rows, session.cols == cols {
            return
        }

        session.rows = rows
        session.cols = cols
        sessionsByDirectory[directory] = session

        do {
            let updated = try await client.updatePTY(
                ptyID: pty.id,
                directory: directory,
                title: nil,
                rows: rows,
                cols: cols
            )
            guard var current = sessionsByDirectory[directory] else { return }
            current.pty = updated
            sessionsByDirectory[directory] = current
            syncActiveSnapshot()
        } catch {
            markFailed(directory: directory, message: error.localizedDescription)
        }
    }

    func handleGlobalEvent(_ event: OpenCodeGlobalEvent) {
        guard let directory = event.directory else { return }

        switch event.payload {
        case .ptyCreated(let payload), .ptyUpdated(let payload):
            var session = sessionsByDirectory[directory] ?? WorkspaceSession()
            if session.pty?.id == payload.info.id || session.pty == nil {
                session.pty = payload.info
                if payload.info.status == .running, session.connection != nil {
                    session.phase = .connected
                }
            }
            sessionsByDirectory[directory] = session
            syncActiveSnapshot()

        case .ptyExited(let payload):
            closeSessionIfMatchingPTY(directory: directory, ptyID: payload.id)

        case .ptyDeleted(let payload):
            closeSessionIfMatchingPTY(directory: directory, ptyID: payload.id)

        default:
            return
        }
    }

    private func closeSessionIfMatchingPTY(directory: String, ptyID: String) {
        guard var session = sessionsByDirectory[directory], session.pty?.id == ptyID else {
            return
        }

        session.phase = .closed
        session.pty = nil
        session.cursor = 0
        let connection = session.connection
        session.connection = nil
        session.connectionToken = UUID()
        sessionsByDirectory[directory] = session
        syncActiveSnapshot()

        if let connection {
            Task {
                await connection.disconnect()
            }
        }
    }

    private func disconnectSession(directory: String) async {
        guard var session = sessionsByDirectory[directory] else { return }
        let connection = session.connection
        session.connection = nil
        session.connectionToken = UUID()
        sessionsByDirectory[directory] = session
        syncActiveSnapshot()
        if let connection {
            await connection.disconnect()
        }
    }

    private func handleConnectionOpened(directory: String, token: UUID) {
        guard var session = sessionsByDirectory[directory], session.connectionToken == token else { return }
        session.phase = .connected
        sessionsByDirectory[directory] = session
        syncActiveSnapshot()
    }

    private func handleConnectionOutput(directory: String, token: UUID, output: String) {
        guard !output.isEmpty,
              var session = sessionsByDirectory[directory],
              session.connectionToken == token
        else {
            return
        }

        session.queuedOutput.append(output)
        if session.queuedOutput.count > 1_000 {
            session.queuedOutput.removeFirst(session.queuedOutput.count - 1_000)
        }
        session.outputRevision &+= 1
        sessionsByDirectory[directory] = session
        syncActiveSnapshot()
    }

    private func handleCursor(directory: String, token: UUID, cursor: Int) {
        guard var session = sessionsByDirectory[directory], session.connectionToken == token else { return }
        session.cursor = max(cursor, 0)
        sessionsByDirectory[directory] = session
    }

    private func handleConnectionClosed(directory: String, token: UUID, error: Error?) {
        guard var session = sessionsByDirectory[directory], session.connectionToken == token else { return }
        session.connection = nil

        if session.pty == nil {
            session.phase = .closed
        } else if let error {
            session.phase = .failed(error.localizedDescription)
        } else {
            session.phase = .closed
        }

        sessionsByDirectory[directory] = session
        syncActiveSnapshot()
    }

    private func markFailed(directory: String, message: String) {
        guard var session = sessionsByDirectory[directory] else { return }
        session.phase = .failed(message)
        sessionsByDirectory[directory] = session
        syncActiveSnapshot()
    }

    private func isReusable(_ pty: OpenCodePTY, configuration: LaunchConfiguration) -> Bool {
        guard pty.cwd == configuration.cwd else { return false }
        guard configuration.enforceShell else { return true }
        guard let expectedCommand = configuration.command else { return true }
        guard shellBaseName(from: pty.command) == shellBaseName(from: expectedCommand) else { return false }

        if let requiredArgs = configuration.args {
            for arg in requiredArgs where !pty.args.contains(arg) {
                return false
            }
        }

        // OpenCode should add login args for sh-family shells; guard this for local zsh policy.
        return pty.args.contains("-l")
    }

    private func shellBaseName(from command: String) -> String {
        URL(fileURLWithPath: command).lastPathComponent.lowercased()
    }

    private func syncActiveSnapshot() {
        guard let directory = activeDirectory,
              let session = sessionsByDirectory[directory]
        else {
            activePTY = nil
            activePhase = .closed
            activeOutputRevision = 0
            return
        }

        activePTY = session.pty
        activePhase = session.phase
        activeOutputRevision = session.outputRevision
    }
}
