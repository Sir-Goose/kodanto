import Foundation

struct LiveSyncTracker {
    enum State: Equatable {
        case inactive
        case connecting
        case active
        case reconnecting(String)

        var isRunning: Bool {
            switch self {
            case .inactive:
                return false
            case .connecting, .active, .reconnecting:
                return true
            }
        }

        var label: String {
            switch self {
            case .inactive:
                return "Inactive"
            case .connecting:
                return "Connecting"
            case .active:
                return "Active"
            case .reconnecting:
                return "Reconnecting"
            }
        }
    }

    static let heartbeatTimeout: TimeInterval = 15

    private(set) var state: State = .inactive
    private(set) var lastEventAt: Date = .distantPast
    private(set) var reconnectCount = 0
    private var needsRefreshAfterReconnect = false

    mutating func start(now: Date = .now) {
        lastEventAt = now
        if case .reconnecting = state {
            return
        }
        state = .connecting
    }

    mutating func stop() {
        state = .inactive
        lastEventAt = .distantPast
        needsRefreshAfterReconnect = false
    }

    mutating func receiveEvent(_ event: OpenCodeGlobalEvent, now: Date = .now) -> Bool {
        lastEventAt = now

        let shouldRefresh = needsRefreshAfterReconnect && event.isServerConnected
        if shouldRefresh {
            needsRefreshAfterReconnect = false
        }

        state = .active
        return shouldRefresh
    }

    mutating func markReconnectNeeded(reason: String) {
        reconnectCount += 1
        needsRefreshAfterReconnect = true
        state = .reconnecting(reason)
    }

    func isHeartbeatTimedOut(now: Date = .now, timeout: TimeInterval = Self.heartbeatTimeout) -> Bool {
        guard lastEventAt != .distantPast else { return false }
        return now.timeIntervalSince(lastEventAt) > timeout
    }
}

private extension OpenCodeGlobalEvent {
    var isServerConnected: Bool {
        if case .serverConnected = payload {
            return true
        }
        return false
    }
}
