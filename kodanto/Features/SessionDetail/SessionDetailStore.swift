import Foundation
import Observation

private func sessionDetailSortParts(_ lhs: OpenCodePart, _ rhs: OpenCodePart) -> Bool {
    lhs.id < rhs.id
}

struct SessionDetailMessageState {
    var sessionMessagesByID: [String: OpenCodeMessage] = [:]
    var messagePartsByMessageID: [String: [OpenCodePart]] = [:]
}

enum SessionDetailReducer {
    static func replacingMessages(_ envelopes: [OpenCodeMessageEnvelope]) -> SessionDetailMessageState {
        var state = SessionDetailMessageState()
        for envelope in envelopes {
            state.sessionMessagesByID[envelope.id] = envelope.info
            state.messagePartsByMessageID[envelope.id] = envelope.parts.sorted(by: sessionDetailSortParts)
        }
        return state
    }

    static func upsertingMessage(_ message: OpenCodeMessage, in state: inout SessionDetailMessageState) {
        state.sessionMessagesByID[message.id] = message
        if state.messagePartsByMessageID[message.id] == nil {
            state.messagePartsByMessageID[message.id] = []
        }
    }

    static func removingMessage(messageID: String, in state: inout SessionDetailMessageState) {
        state.sessionMessagesByID.removeValue(forKey: messageID)
        state.messagePartsByMessageID.removeValue(forKey: messageID)
    }

    static func upsertingPart(_ part: OpenCodePart, in state: inout SessionDetailMessageState) {
        var parts = state.messagePartsByMessageID[part.messageID] ?? []
        if let index = parts.firstIndex(where: { $0.id == part.id }) {
            parts[index] = part
        } else {
            parts.append(part)
        }
        state.messagePartsByMessageID[part.messageID] = parts.sorted(by: sessionDetailSortParts)
    }

    static func applyingPartDelta(_ payload: OpenCodeEvent.MessagePartDeltaPayload, in state: inout SessionDetailMessageState) {
        guard var parts = state.messagePartsByMessageID[payload.messageID],
              let index = parts.firstIndex(where: { $0.id == payload.partID }),
              let updated = parts[index].applyingDelta(field: payload.field, delta: payload.delta)
        else { return }

        parts[index] = updated
        state.messagePartsByMessageID[payload.messageID] = parts
    }

    static func removingPart(messageID: String, partID: String, in state: inout SessionDetailMessageState) {
        guard var parts = state.messagePartsByMessageID[messageID] else { return }
        parts.removeAll { $0.id == partID }
        state.messagePartsByMessageID[messageID] = parts
    }

    static func rebuildTranscript(
        for selectedSessionID: String?,
        state: SessionDetailMessageState
    ) -> (messages: [OpenCodeMessageEnvelope], turns: [TranscriptTurn]) {
        guard let selectedSessionID else {
            return ([], [])
        }

        let messages = state.sessionMessagesByID.values
            .filter { $0.sessionID == selectedSessionID }
            .sorted { $0.createdAt < $1.createdAt }
            .map { message in
                OpenCodeMessageEnvelope(
                    info: message,
                    parts: (state.messagePartsByMessageID[message.id] ?? []).sorted(by: sessionDetailSortParts)
                )
            }

        return (messages, TranscriptTurn.build(from: messages))
    }
}

@MainActor
@Observable
final class SessionDetailStore {
    var selectedSessionMessages: [OpenCodeMessageEnvelope] = []
    var selectedSessionTurns: [TranscriptTurn] = []
    var selectedSessionTranscriptRevision = 0
    var sessionTodos: [OpenCodeTodo] = []

    private var selectedSessionID: String?
    private var state = SessionDetailMessageState()

    func selectSession(_ sessionID: String?) {
        guard selectedSessionID != sessionID else { return }
        selectedSessionID = sessionID
        resetSelectionState(incrementRevision: true)
    }

    func clearSessionDetail() {
        resetSelectionState(incrementRevision: false)
    }

    func replaceMessages(_ envelopes: [OpenCodeMessageEnvelope]) {
        state = SessionDetailReducer.replacingMessages(envelopes)
        rebuildSelectedSessionMessages()
    }

    func replaceSessionTodos(_ todos: [OpenCodeTodo]) {
        sessionTodos = todos
    }

    func upsertMessage(_ message: OpenCodeMessage) {
        guard message.sessionID == selectedSessionID else { return }
        SessionDetailReducer.upsertingMessage(message, in: &state)
        rebuildSelectedSessionMessages()
    }

    func removeMessage(sessionID: String, messageID: String) {
        guard sessionID == selectedSessionID else { return }
        SessionDetailReducer.removingMessage(messageID: messageID, in: &state)
        rebuildSelectedSessionMessages()
    }

    func upsertPart(_ part: OpenCodePart) {
        guard part.sessionID == selectedSessionID else { return }
        SessionDetailReducer.upsertingPart(part, in: &state)
        rebuildSelectedSessionMessages()
    }

    func applyPartDelta(_ payload: OpenCodeEvent.MessagePartDeltaPayload) {
        guard payload.sessionID == selectedSessionID else { return }
        SessionDetailReducer.applyingPartDelta(payload, in: &state)
        rebuildSelectedSessionMessages()
    }

    func removePart(messageID: String, partID: String) {
        SessionDetailReducer.removingPart(messageID: messageID, partID: partID, in: &state)
        rebuildSelectedSessionMessages()
    }

    private func resetSelectionState(incrementRevision: Bool) {
        state = SessionDetailMessageState()
        selectedSessionMessages = []
        selectedSessionTurns = []
        sessionTodos = []
        if incrementRevision {
            selectedSessionTranscriptRevision &+= 1
        }
    }

    private func rebuildSelectedSessionMessages() {
        let rebuilt = SessionDetailReducer.rebuildTranscript(for: selectedSessionID, state: state)
        selectedSessionMessages = rebuilt.messages
        selectedSessionTurns = rebuilt.turns
        selectedSessionTranscriptRevision &+= 1
    }
}
