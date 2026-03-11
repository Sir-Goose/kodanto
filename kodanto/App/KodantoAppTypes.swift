import Foundation

struct KodantoSessionNavigationTarget: Hashable {
    let projectID: OpenCodeProject.ID
    let sessionID: OpenCodeSession.ID
}

struct KodantoDiagnosticsSnapshot {
    let serverURL: String
    let binaryPath: String
    let liveSyncState: String
    let reconnectCount: Int
    let lastEventDescription: String
    let lastError: String?
    let selectedProjectDirectory: String?
    let cachedProjects: Int
    let cachedSessions: Int
    let sidecarLog: String
}

enum KodantoConnectionState: Equatable {
    case idle
    case connecting
    case connected(version: String)
    case failed(String)
}

extension KodantoConnectionState {
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}
