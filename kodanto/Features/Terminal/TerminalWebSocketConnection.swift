import Foundation

protocol PTYWebSocketConnecting: AnyObject {
    func connect() async
    func sendInput(_ text: String) async throws
    func disconnect() async
}

final actor LivePTYWebSocketConnection: PTYWebSocketConnecting {
    private struct CursorControlFrame: Decodable {
        let cursor: Int
    }

    private let request: URLRequest
    private let onConnected: @Sendable () -> Void
    private let onOutput: @Sendable (String) -> Void
    private let onCursor: @Sendable (Int) -> Void
    private let onDisconnect: @Sendable (Error?) -> Void

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var disconnecting = false

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
        await disconnectInternal(notify: false)

        disconnecting = false
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        onConnected()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendInput(_ text: String) async throws {
        guard let task else {
            throw NSError(domain: "kodanto.terminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Terminal is disconnected."])
        }

        try await task.send(.string(text))
    }

    func disconnect() async {
        await disconnectInternal(notify: false)
    }

    private func receiveLoop() async {
        guard let task else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                try await handleMessage(message)
            } catch {
                await disconnectInternal(notify: true, error: disconnecting ? nil : error)
                return
            }
        }

        await disconnectInternal(notify: true, error: nil)
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async throws {
        switch message {
        case .string(let value):
            if !value.isEmpty {
                onOutput(value)
            }
        case .data(let data):
            if data.isEmpty {
                return
            }

            if data.first == 0 {
                let payload = data.dropFirst()
                let frame = try JSONDecoder().decode(CursorControlFrame.self, from: Data(payload))
                onCursor(frame.cursor)
                return
            }

            if let value = String(data: data, encoding: .utf8), !value.isEmpty {
                onOutput(value)
            }
        @unknown default:
            return
        }
    }

    private func disconnectInternal(notify: Bool, error: Error? = nil) async {
        disconnecting = true
        receiveTask?.cancel()
        receiveTask = nil

        if let task {
            task.cancel(with: .normalClosure, reason: nil)
            self.task = nil
        }

        if notify {
            onDisconnect(error)
        }

        disconnecting = false
    }
}
