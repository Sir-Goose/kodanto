import Foundation

struct EventRoutingEffects: OptionSet {
    let rawValue: Int

    static let refresh = EventRoutingEffects(rawValue: 1 << 0)
    static let loadSessionDetail = EventRoutingEffects(rawValue: 1 << 1)
    static let autoRespondPermissions = EventRoutingEffects(rawValue: 1 << 2)
}

@MainActor
enum GlobalEventRouter {
    static func apply(
        _ event: OpenCodeGlobalEvent,
        selectedProfileID: UUID?,
        workspaceStore: WorkspaceStore,
        sessionDetailStore: SessionDetailStore,
        sessionRequestStore: SessionRequestStore
    ) -> EventRoutingEffects {
        let directory = event.directory ?? "global"

        switch event.payload {
        case .serverConnected:
            return []
        case .serverHeartbeat:
            return []
        case .globalDisposed:
            return .refresh
        case .projectUpdated(let project):
            workspaceStore.upsertProject(project, profileID: selectedProfileID)
            return []
        default:
            return DirectoryEventRouter.apply(
                event.payload,
                directory: directory,
                workspaceStore: workspaceStore,
                sessionDetailStore: sessionDetailStore,
                sessionRequestStore: sessionRequestStore
            )
        }
    }
}

@MainActor
enum DirectoryEventRouter {
    static func apply(
        _ event: OpenCodeEvent,
        directory: String,
        workspaceStore: WorkspaceStore,
        sessionDetailStore: SessionDetailStore,
        sessionRequestStore: SessionRequestStore
    ) -> EventRoutingEffects {
        switch event {
        case .sessionCreated(let payload):
            workspaceStore.upsertSession(payload.info, directory: directory)
            return []
        case .sessionUpdated(let payload):
            workspaceStore.upsertSession(payload.info, directory: directory)
            return []
        case .sessionDeleted(let payload):
            let selectionChanged = workspaceStore.removeSession(payload.info, directory: directory)
            return selectionChanged ? .loadSessionDetail : []
        case .sessionStatus(let payload):
            workspaceStore.upsertSessionStatus(payload.status, sessionID: payload.sessionID, directory: directory)
            return []
        case .todoUpdated(let payload):
            guard workspaceStore.directoryMatchesSelection(directory), payload.sessionID == workspaceStore.selectedSessionID else { return [] }
            sessionDetailStore.replaceSessionTodos(payload.todos)
            return []
        case .messageUpdated(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionDetailStore.upsertMessage(payload.info)
            return []
        case .messageRemoved(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionDetailStore.removeMessage(sessionID: payload.sessionID, messageID: payload.messageID)
            return []
        case .messagePartUpdated(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionDetailStore.upsertPart(payload.part)
            return []
        case .messagePartDelta(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionDetailStore.applyPartDelta(payload)
            return []
        case .messagePartRemoved(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionDetailStore.removePart(messageID: payload.messageID, partID: payload.partID)
            return []
        case .permissionAsked(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionRequestStore.upsertPermission(payload)
            return .autoRespondPermissions
        case .permissionReplied(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionRequestStore.removePermission(sessionID: payload.sessionID, requestID: payload.requestID)
            return []
        case .questionAsked(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionRequestStore.upsertQuestion(payload)
            return []
        case .questionReplied(let payload), .questionRejected(let payload):
            guard workspaceStore.directoryMatchesSelection(directory) else { return [] }
            sessionRequestStore.removeQuestion(sessionID: payload.sessionID, requestID: payload.requestID)
            return []
        default:
            return []
        }
    }
}
