import CoreGraphics
import Foundation
import Observation

enum PermissionReply: String, CaseIterable, Hashable {
    case reject
    case always
    case once
}

struct QuestionDraftAnswer: Hashable {
    var selectedAnswers: [String] = []
    var customValue = ""
    var isCustomEnabled = false
}

@MainActor
@Observable
final class SessionRequestStore {
    var permissions: [OpenCodePermissionRequest] = []
    var questions: [OpenCodeQuestionRequest] = []

    private let permissionAutoAcceptStore: PermissionAutoAcceptStoring
    private var permissionAutoAcceptValues: [String: Bool]
    private var autoRespondingPermissionIDs: Set<String> = []
    private var failedAutoRespondPermissionIDs: Set<String> = []
    private var selectedSessionID: String?
    private var selectedDirectory: String?

    init(permissionAutoAcceptStore: PermissionAutoAcceptStoring) {
        self.permissionAutoAcceptStore = permissionAutoAcceptStore
        permissionAutoAcceptValues = permissionAutoAcceptStore.load()
    }

    var activePermissionRequest: OpenCodePermissionRequest? {
        guard !isPermissionAutoAcceptEnabled else { return nil }
        guard let selectedSessionID else { return nil }
        return permissions.first(where: { $0.sessionID == selectedSessionID })
    }

    var activeQuestionRequest: OpenCodeQuestionRequest? {
        guard let selectedSessionID else { return nil }
        return questions.first(where: { $0.sessionID == selectedSessionID })
    }

    var isPermissionAutoAcceptEnabled: Bool {
        if let sessionID = selectedSessionID,
           let directory = selectedDirectory {
            let sessionKey = PermissionAutoAcceptStore.makeKey(sessionID: sessionID, directory: directory)
            if let value = permissionAutoAcceptValues[sessionKey] {
                return value
            }
        }
        guard let directory = selectedDirectory else { return false }
        let directoryKey = PermissionAutoAcceptStore.makeDirectoryKey(directory: directory)
        return permissionAutoAcceptValues[directoryKey] ?? false
    }

    var canTogglePermissionAutoAccept: Bool {
        selectedDirectory != nil
    }

    func updateSelection(sessionID: String?, directory: String?) {
        selectedSessionID = sessionID
        selectedDirectory = directory
    }

    func clearRequests() {
        permissions = []
        questions = []
        autoRespondingPermissionIDs = []
        failedAutoRespondPermissionIDs = []
    }

    func replaceRequests(
        permissions loadedPermissions: [OpenCodePermissionRequest],
        questions loadedQuestions: [OpenCodeQuestionRequest]
    ) {
        permissions = loadedPermissions.filter { $0.sessionID == selectedSessionID }
        questions = loadedQuestions.filter { $0.sessionID == selectedSessionID }

        let permissionIDs = Set(permissions.map(\.id))
        autoRespondingPermissionIDs = autoRespondingPermissionIDs.intersection(permissionIDs)
        failedAutoRespondPermissionIDs = failedAutoRespondPermissionIDs.intersection(permissionIDs)
    }

    func togglePermissionAutoAccept() {
        setPermissionAutoAccept(!isPermissionAutoAcceptEnabled)
    }

    func setPermissionAutoAccept(_ enabled: Bool) {
        guard let directory = selectedDirectory else { return }
        let key: String
        if let sessionID = selectedSessionID {
            key = PermissionAutoAcceptStore.makeKey(sessionID: sessionID, directory: directory)
        } else {
            key = PermissionAutoAcceptStore.makeDirectoryKey(directory: directory)
        }
        permissionAutoAcceptValues[key] = enabled
        permissionAutoAcceptStore.save(permissionAutoAcceptValues)
        if enabled {
            failedAutoRespondPermissionIDs = []
        }
    }

    func submitPermissionResponse(
        _ request: OpenCodePermissionRequest,
        reply: PermissionReply,
        using client: OpenCodeAPIService,
        directory: String,
        reload: @escaping () async throws -> Void
    ) async throws {
        try await client.replyToPermission(requestID: request.id, directory: directory, reply: reply.rawValue)
        try await reload()
    }

    func submitQuestionAnswers(
        _ request: OpenCodeQuestionRequest,
        answers: [[String]],
        using client: OpenCodeAPIService,
        directory: String,
        reload: @escaping () async throws -> Void
    ) async throws {
        try await client.replyToQuestion(requestID: request.id, directory: directory, answers: answers)
        try await reload()
    }

    func submitQuestionRejection(
        _ request: OpenCodeQuestionRequest,
        using client: OpenCodeAPIService,
        directory: String,
        reload: @escaping () async throws -> Void
    ) async throws {
        try await client.rejectQuestion(requestID: request.id, directory: directory)
        try await reload()
    }

    func upsertPermission(_ request: OpenCodePermissionRequest) {
        guard request.sessionID == selectedSessionID else { return }
        if let index = permissions.firstIndex(where: { $0.id == request.id }) {
            permissions[index] = request
        } else {
            permissions.append(request)
        }
    }

    func removePermission(sessionID: String, requestID: String) {
        guard sessionID == selectedSessionID else { return }
        permissions.removeAll { $0.id == requestID }
        autoRespondingPermissionIDs.remove(requestID)
        failedAutoRespondPermissionIDs.remove(requestID)
    }

    func upsertQuestion(_ request: OpenCodeQuestionRequest) {
        guard request.sessionID == selectedSessionID else { return }
        if let index = questions.firstIndex(where: { $0.id == request.id }) {
            questions[index] = request
        } else {
            questions.append(request)
        }
    }

    func removeQuestion(sessionID: String, requestID: String) {
        guard sessionID == selectedSessionID else { return }
        questions.removeAll { $0.id == requestID }
    }

    func autoRespondToPendingPermissionsIfNeeded(
        submit: @escaping @MainActor (OpenCodePermissionRequest, PermissionReply) async throws -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        guard isPermissionAutoAcceptEnabled else { return }

        let pendingRequests = permissions.filter { request in
            request.sessionID == selectedSessionID &&
                !autoRespondingPermissionIDs.contains(request.id) &&
                !failedAutoRespondPermissionIDs.contains(request.id)
        }
        guard !pendingRequests.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }

            for request in pendingRequests {
                guard self.isPermissionAutoAcceptEnabled, self.selectedSessionID == request.sessionID else { break }
                guard self.autoRespondingPermissionIDs.insert(request.id).inserted else { continue }

                defer {
                    self.autoRespondingPermissionIDs.remove(request.id)
                }

                do {
                    try await submit(request, .once)
                } catch {
                    self.failedAutoRespondPermissionIDs.insert(request.id)
                    onError(error)
                }
            }
        }
    }

    private var selectedPermissionAutoAcceptKey: String? {
        guard let selectedSessionID, let selectedDirectory else { return nil }
        return PermissionAutoAcceptStore.makeKey(sessionID: selectedSessionID, directory: selectedDirectory)
    }
}

@MainActor
@Observable
final class SessionPermissionActionModel {
    var isResponding = false
    var responseError: String?

    private let requestID: String
    private let submit: @MainActor (PermissionReply) async throws -> Void

    init(requestID: String, submit: @escaping @MainActor (PermissionReply) async throws -> Void) {
        self.requestID = requestID
        self.submit = submit
    }

    func reset(for requestID: String) {
        guard self.requestID != requestID else { return }
        isResponding = false
        responseError = nil
    }

    func respond(with reply: PermissionReply) {
        guard !isResponding else { return }
        isResponding = true
        responseError = nil

        Task {
            do {
                try await submit(reply)
                isResponding = false
            } catch {
                isResponding = false
                responseError = error.localizedDescription
            }
        }
    }
}

@MainActor
@Observable
final class SessionQuestionDraftModel {
    let request: OpenCodeQuestionRequest

    var currentIndex = 0
    var answers: [QuestionDraftAnswer]
    var isEditingCustomAnswer = false
    var isSending = false
    var submissionError: String?
    var customEditorHeight: CGFloat = 0

    init(request: OpenCodeQuestionRequest) {
        self.request = request
        answers = Array(repeating: QuestionDraftAnswer(), count: request.questions.count)
    }

    var questions: [OpenCodeQuestionRequest.Question] {
        request.questions
    }

    var totalQuestions: Int {
        questions.count
    }

    var hasQuestions: Bool {
        !questions.isEmpty
    }

    var currentQuestion: OpenCodeQuestionRequest.Question? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    var currentAnswers: [String] {
        answers[safe: currentIndex]?.selectedAnswers ?? []
    }

    var currentCustomValue: String {
        answers[safe: currentIndex]?.customValue ?? ""
    }

    var isCurrentCustomEnabled: Bool {
        answers[safe: currentIndex]?.isCustomEnabled ?? false
    }

    var currentQuestionAllowsMultiple: Bool {
        currentQuestion?.multiple == true
    }

    var currentQuestionAllowsCustom: Bool {
        currentQuestion?.custom != false
    }

    var summaryTitle: String {
        "\(min(currentIndex + 1, totalQuestions)) of \(totalQuestions) questions"
    }

    var isLastQuestion: Bool {
        currentIndex >= totalQuestions - 1
    }

    var canGoBack: Bool {
        currentIndex > 0 && !isSending
    }

    func jump(to index: Int) {
        guard !isSending, questions.indices.contains(index) else { return }
        commitCustomAnswerEditing()
        currentIndex = index
        isEditingCustomAnswer = false
        submissionError = nil
    }

    func goBack() {
        guard canGoBack else { return }
        commitCustomAnswerEditing()
        currentIndex -= 1
        isEditingCustomAnswer = false
        submissionError = nil
    }

    func advance(
        onSubmit: @escaping @MainActor ([[String]]) async throws -> Void
    ) {
        guard !isSending else { return }
        commitCustomAnswerEditing()
        submissionError = nil

        if isLastQuestion {
            submitAnswers(onSubmit: onSubmit)
        } else {
            currentIndex += 1
            isEditingCustomAnswer = false
        }
    }

    func selectSuggestedAnswer(_ label: String) {
        guard !isSending else { return }

        if currentQuestionAllowsMultiple {
            if currentAnswers.contains(label) {
                setAnswersForCurrentQuestion(currentAnswers.filter { $0 != label })
            } else {
                setAnswersForCurrentQuestion(currentAnswers + [label])
            }
        } else {
            setAnswersForCurrentQuestion([label])
            setCustomEnabledForCurrentQuestion(false)
            isEditingCustomAnswer = false
        }

        submissionError = nil
    }

    func toggleCustomAnswer() {
        guard !isSending else { return }

        if currentQuestionAllowsMultiple {
            let shouldEnable = !isCurrentCustomEnabled
            setCustomEnabledForCurrentQuestion(shouldEnable)
            if shouldEnable {
                isEditingCustomAnswer = true
                syncCurrentCustomAnswerIntoSelection()
            } else {
                removeCurrentCustomAnswerFromSelection()
                isEditingCustomAnswer = false
            }
        } else {
            setCustomEnabledForCurrentQuestion(true)
            isEditingCustomAnswer = true
            syncCurrentCustomAnswerIntoSelection()
        }

        submissionError = nil
    }

    func openCustomAnswerEditor() {
        guard !isSending else { return }
        if !isCurrentCustomEnabled {
            setCustomEnabledForCurrentQuestion(true)
            syncCurrentCustomAnswerIntoSelection()
        }
        isEditingCustomAnswer = true
        submissionError = nil
    }

    func updateCustomAnswer(_ value: String) {
        setCustomValueForCurrentQuestion(value)
        syncCurrentCustomAnswerIntoSelection()
    }

    func commitCustomAnswerEditing() {
        guard isEditingCustomAnswer else { return }
        isEditingCustomAnswer = false
        syncCurrentCustomAnswerIntoSelection()
    }

    func reject(using action: @escaping @MainActor () async throws -> Void) {
        guard !isSending else { return }
        isSending = true
        submissionError = nil

        Task {
            do {
                try await action()
                isSending = false
            } catch {
                isSending = false
                submissionError = error.localizedDescription
            }
        }
    }

    func progressFill(for index: Int) -> Bool {
        if index == currentIndex {
            return true
        }
        return !(answers[safe: index]?.selectedAnswers.isEmpty ?? true)
    }

    private func syncCurrentCustomAnswerIntoSelection() {
        guard isCurrentCustomEnabled else { return }

        let trimmedValue = currentCustomValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousValue = previousCustomAnswerValue()
        var updatedAnswers = currentAnswers.filter { $0 != previousValue }

        if !trimmedValue.isEmpty {
            if currentQuestionAllowsMultiple {
                if !updatedAnswers.contains(trimmedValue) {
                    updatedAnswers.append(trimmedValue)
                }
            } else {
                updatedAnswers = [trimmedValue]
            }
        }

        setAnswersForCurrentQuestion(updatedAnswers)
    }

    private func removeCurrentCustomAnswerFromSelection() {
        let previousValue = previousCustomAnswerValue()
        setAnswersForCurrentQuestion(currentAnswers.filter { $0 != previousValue })
    }

    private func previousCustomAnswerValue() -> String {
        currentCustomValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitAnswers(
        onSubmit: @escaping @MainActor ([[String]]) async throws -> Void
    ) {
        let payload = answers.map { draft in
            draft.selectedAnswers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        isSending = true
        submissionError = nil

        Task {
            do {
                try await onSubmit(payload)
                isSending = false
            } catch {
                isSending = false
                submissionError = error.localizedDescription
            }
        }
    }

    private func setAnswersForCurrentQuestion(_ value: [String]) {
        guard answers.indices.contains(currentIndex) else { return }
        answers[currentIndex].selectedAnswers = value
    }

    private func setCustomValueForCurrentQuestion(_ value: String) {
        guard answers.indices.contains(currentIndex) else { return }
        answers[currentIndex].customValue = value
    }

    private func setCustomEnabledForCurrentQuestion(_ value: Bool) {
        guard answers.indices.contains(currentIndex) else { return }
        answers[currentIndex].isCustomEnabled = value
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
