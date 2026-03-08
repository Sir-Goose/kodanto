import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class KodantoAppModel {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected(version: String)
        case failed(String)
    }

    var profiles: [ServerProfile] = []
    var selectedProfileID: ServerProfile.ID?
    var connectionState: ConnectionState = .idle
    var projects: [OpenCodeProject] = []
    var selectedProjectID: OpenCodeProject.ID?
    var sessions: [OpenCodeSession] = []
    var selectedSessionID: OpenCodeSession.ID?
    var selectedSessionMessages: [OpenCodeMessageEnvelope] = []
    var sessionStatuses: [String: OpenCodeSessionStatus] = [:]
    var sessionTodos: [OpenCodeTodo] = []
    var permissions: [OpenCodePermissionRequest] = []
    var questions: [OpenCodeQuestionRequest] = []
    var pathInfo: OpenCodePathInfo?
    var draftPrompt = ""
    var newSessionTitle = ""
    var sidecarLog = ""
    var showingConnectionSheet = false

    private let sidecar = SidecarProcess()
    private let storage = ServerProfileStore()

    init() {
        profiles = storage.load()
        if profiles.isEmpty {
            let local = Self.makeLocalProfile()
            profiles = [local]
            selectedProfileID = local.id
            storage.save(profiles)
        } else {
            selectedProfileID = profiles.first?.id
        }

        sidecar.setOutputHandler { [weak self] line in
            guard let self else { return }
            self.sidecarLog.append(line)
            if self.sidecarLog.count > 12000 {
                self.sidecarLog = String(self.sidecarLog.suffix(12000))
            }
        }
    }

    var selectedProfile: ServerProfile? {
        profiles.first(where: { $0.id == selectedProfileID })
    }

    var selectedProject: OpenCodeProject? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    var selectedSession: OpenCodeSession? {
        sessions.first(where: { $0.id == selectedSessionID })
    }

    var canCreateSession: Bool {
        selectedProject != nil && selectedProfile != nil
    }

    var canSendPrompt: Bool {
        selectedSession != nil && !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func selectProfile(_ profileID: ServerProfile.ID) {
        selectedProfileID = profileID
        connectionState = .idle
        projects = []
        selectedProjectID = nil
        sessions = []
        selectedSessionID = nil
        selectedSessionMessages = []
        sessionTodos = []
        permissions = []
        questions = []
        pathInfo = nil
    }

    func saveProfile(_ profile: ServerProfile) {
        var profile = profile
        if profile.kind == .localSidecar, profile.password?.isEmpty != false {
            profile.password = UUID().uuidString
        }

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        storage.save(profiles)
        selectedProfileID = profile.id
    }

    func deleteProfile(_ profile: ServerProfile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        if selectedProfileID == profile.id {
            selectedProfileID = profiles.first?.id
        }
        storage.save(profiles)
    }

    func connect() {
        Task {
            await connectSelectedProfile()
        }
    }

    func connectSelectedProfile() async {
        guard let profile = selectedProfile else { return }
        connectionState = .connecting

        do {
            let client = OpenCodeAPIClient(profile: profile)

            if profile.kind == .localSidecar {
                if (try? await client.health().healthy) != true {
                    try sidecar.start(profile: profile)
                    try await waitForServer(profile: profile)
                }
            }

            let health = try await client.health()
            connectionState = .connected(version: health.version)
            try await refreshAll(using: client)
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    func refresh() {
        Task {
            guard let profile = selectedProfile else { return }
            do {
                try await refreshAll(using: OpenCodeAPIClient(profile: profile))
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func createSession() {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                let client = OpenCodeAPIClient(profile: profile)
                let created = try await client.createSession(
                    directory: project.worktree,
                    title: emptyToNil(newSessionTitle)
                )
                newSessionTitle = ""
                try await loadSessions(for: project, using: client)
                selectedSessionID = created.id
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func sendPrompt() {
        Task {
            guard let profile = selectedProfile, let project = selectedProject, let session = selectedSession else { return }
            let text = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            draftPrompt = ""

            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.sendPrompt(sessionID: session.id, directory: project.worktree, text: text)
                try await loadSessionDetail(using: client)
                try await loadSessions(for: project, using: client)
            } catch {
                draftPrompt = text
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func selectProject(_ projectID: OpenCodeProject.ID) {
        selectedProjectID = projectID
        selectedSessionID = nil
        selectedSessionMessages = []
        sessionTodos = []

        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                try await loadSessions(for: project, using: OpenCodeAPIClient(profile: profile))
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func selectSession(_ sessionID: OpenCodeSession.ID) {
        selectedSessionID = sessionID
        Task {
            guard let profile = selectedProfile else { return }
            do {
                try await loadSessionDetail(using: OpenCodeAPIClient(profile: profile))
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func respondToPermission(_ request: OpenCodePermissionRequest, reply: String) {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.replyToPermission(requestID: request.id, directory: project.worktree, reply: reply)
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func answerQuestion(_ request: OpenCodeQuestionRequest, answers: [[String]]) {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.replyToQuestion(requestID: request.id, directory: project.worktree, answers: answers)
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    func rejectQuestion(_ request: OpenCodeQuestionRequest) {
        Task {
            guard let profile = selectedProfile, let project = selectedProject else { return }
            do {
                let client = OpenCodeAPIClient(profile: profile)
                try await client.rejectQuestion(requestID: request.id, directory: project.worktree)
                try await loadSessionDetail(using: client)
            } catch {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    private func refreshAll(using client: OpenCodeAPIClient) async throws {
        async let pathInfoTask = client.pathInfo(directory: nil)
        async let projectsTask = client.projects()

        let resolvedPathInfo = try await pathInfoTask
        let loadedProjects = try await projectsTask.sorted { $0.time.updated > $1.time.updated }

        pathInfo = resolvedPathInfo
        projects = loadedProjects

        if selectedProjectID == nil || !loadedProjects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = loadedProjects.first?.id
        }

        if let project = selectedProject {
            try await loadSessions(for: project, using: client)
        }
    }

    private func loadSessions(for project: OpenCodeProject, using client: OpenCodeAPIClient) async throws {
        async let sessionsTask = client.sessions(directory: project.worktree)
        async let statusesTask = client.sessionStatuses(directory: project.worktree)

        let loadedSessions = try await sessionsTask.sorted { $0.time.updated > $1.time.updated }
        sessions = loadedSessions
        sessionStatuses = try await statusesTask

        if selectedSessionID == nil || !loadedSessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = loadedSessions.first?.id
        }

        try await loadSessionDetail(using: client)
    }

    private func loadSessionDetail(using client: OpenCodeAPIClient) async throws {
        guard let project = selectedProject else {
            selectedSessionMessages = []
            sessionTodos = []
            permissions = []
            questions = []
            return
        }

        async let permissionsTask = client.permissions(directory: project.worktree)
        async let questionsTask = client.questions(directory: project.worktree)

        permissions = try await permissionsTask
        questions = try await questionsTask

        guard let session = selectedSession else {
            selectedSessionMessages = []
            sessionTodos = []
            return
        }

        async let messagesTask = client.messages(sessionID: session.id, directory: project.worktree)
        async let todosTask = client.sessionTodos(sessionID: session.id, directory: project.worktree)

        selectedSessionMessages = try await messagesTask
        sessionTodos = try await todosTask
    }

    private func waitForServer(profile: ServerProfile) async throws {
        let client = OpenCodeAPIClient(profile: profile)
        for _ in 0 ..< 50 {
            if let health = try? await client.health(), health.healthy {
                return
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw OpenCodeAPIError.serverError(statusCode: 0, message: "Timed out waiting for local opencode sidecar.")
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func makeLocalProfile() -> ServerProfile {
        var profile = ServerProfile.localDefault
        profile.password = UUID().uuidString
        return profile
    }
}

private struct ServerProfileStore {
    private let key = "kodanto.serverProfiles"

    func load() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [ServerProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
