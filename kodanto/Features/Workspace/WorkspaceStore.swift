import Foundation
import Observation

import struct Swift.String

@MainActor
@Observable
final class WorkspaceStore {
    var projects: [OpenCodeProject] = []
    var selectedProjectID: OpenCodeProject.ID?
    var sessions: [OpenCodeSession] = []
    var selectedSessionID: OpenCodeSession.ID?
    var loadingSessionDirectories: Set<String> = []

    private let projectOrderStore: ProjectOrderStoring
    private var sessionsByDirectory: [String: [OpenCodeSession]] = [:]
    private var sessionStatusesByDirectory: [String: [String: OpenCodeSessionStatus]] = [:]
    private var sessionSidebarIndicators = SessionSidebarIndicatorStore()

    init(projectOrderStore: ProjectOrderStoring) {
        self.projectOrderStore = projectOrderStore
    }

    var selectedProject: OpenCodeProject? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    var selectedSession: OpenCodeSession? {
        sessions.first(where: { $0.id == selectedSessionID })
    }

    var selectedProjectDirectory: String? {
        selectedProject?.worktree
    }

    var cachedProjectCount: Int {
        sessionsByDirectory.keys.count
    }

    var cachedSessionCount: Int {
        sessionsByDirectory.values.reduce(0) { $0 + $1.count }
    }

    var isSelectedSessionRunning: Bool {
        guard let selectedProject, let selectedSessionID else { return false }
        guard let status = sessionStatusesByDirectory[selectedProject.worktree]?[selectedSessionID] else {
            return false
        }
        return status.isRunning
    }

    func reset() {
        projects = []
        selectedProjectID = nil
        sessions = []
        selectedSessionID = nil
        loadingSessionDirectories = []
        sessionsByDirectory = [:]
        sessionStatusesByDirectory = [:]
        sessionSidebarIndicators.reset()
    }

    func sessions(for project: OpenCodeProject) -> [OpenCodeSession] {
        (sessionsByDirectory[project.worktree] ?? [])
            .filter { $0.parentID == nil }
    }

    func sessionSidebarIndicator(for session: OpenCodeSession, in project: OpenCodeProject) -> SessionSidebarIndicatorState {
        sessionSidebarIndicators.indicator(for: session.id, in: project.worktree)
    }

    func canMarkSessionUnread(_ sessionID: OpenCodeSession.ID, in projectID: OpenCodeProject.ID) -> Bool {
        guard let project = project(for: projectID) else { return false }
        guard let session = sessionsByDirectory[project.worktree]?.first(where: { $0.id == sessionID }) else { return false }
        guard !session.isArchived else { return false }
        guard sessionSidebarIndicators.indicator(for: sessionID, in: project.worktree) != .completedUnread else { return false }
        let status = sessionStatusesByDirectory[project.worktree]?[sessionID] ?? .idle
        return !status.isRunning
    }

    func markSessionUnread(_ sessionID: OpenCodeSession.ID, in projectID: OpenCodeProject.ID) {
        guard canMarkSessionUnread(sessionID, in: projectID), let project = project(for: projectID) else { return }
        sessionSidebarIndicators.markUnread(for: sessionID, in: project.worktree)
    }

    func hasLoadedSessions(for project: OpenCodeProject) -> Bool {
        sessionsByDirectory[project.worktree] != nil
    }

    func isLoadingSessions(for project: OpenCodeProject) -> Bool {
        loadingSessionDirectories.contains(project.worktree)
    }

    func beginLoadingSessions(for project: OpenCodeProject) {
        loadingSessionDirectories.insert(project.worktree)
    }

    func finishLoadingSessions(for project: OpenCodeProject) {
        loadingSessionDirectories.remove(project.worktree)
    }

    func selectProject(_ projectID: OpenCodeProject.ID?) {
        selectedProjectID = projectID
        applySelectedProjectCache()
    }

    func clearSelectedSession() {
        selectedSessionID = nil
        applySelectedProjectCache()
    }

    func selectSession(_ sessionID: OpenCodeSession.ID, in projectID: OpenCodeProject.ID) -> Bool {
        guard let project = project(for: projectID) else { return false }

        let isSwitchingSessions = selectedSessionID != sessionID || selectedProjectID != project.id
        selectedProjectID = project.id
        applySelectedProjectCache()
        selectedSessionID = sessionID
        sessionSidebarIndicators.clearIndicator(for: sessionID, in: project.worktree)
        return isSwitchingSessions
    }

    func loadedSessionNavigationTarget(for sessionID: OpenCodeSession.ID) -> KodantoSessionNavigationTarget? {
        guard let location = SessionNavigationTargetResolver.resolve(
            sessionID: sessionID,
            projects: projects,
            sessionsByDirectory: sessionsByDirectory
        ) else { return nil }

        return KodantoSessionNavigationTarget(projectID: location.projectID, sessionID: location.sessionID)
    }

    func parentSessionTarget(for session: OpenCodeSession) -> KodantoSessionNavigationTarget? {
        guard let parentID = session.parentID else { return nil }
        return loadedSessionNavigationTarget(for: parentID)
    }

    func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int, profileID: UUID?) {
        guard projects.count > 1 else { return }

        var reorderedProjects = projects
        reorderedProjects.moveItems(fromOffsets: source, toOffset: destination)
        reorderedProjects = ProjectOrderResolver.deduplicatedProjects(reorderedProjects)

        guard reorderedProjects != projects else { return }

        projects = reorderedProjects
        persistProjectOrder(profileID: profileID)
    }

    func moveProject(
        _ projectID: OpenCodeProject.ID,
        relativeTo targetProjectID: OpenCodeProject.ID,
        placement: ProjectDropPlacement,
        profileID: UUID?
    ) {
        let reorderedProjects = ProjectOrderResolver.reorderedProjects(
            projects,
            movingProjectID: projectID,
            relativeTo: targetProjectID,
            placement: placement
        )

        guard reorderedProjects != projects else { return }

        projects = reorderedProjects
        persistProjectOrder(profileID: profileID)
    }

    func sanitizeProjects(profileID: UUID?) {
        let sanitizedProjects = resolvedProjectOrder(for: projects, profileID: profileID)
        let previousProjects = projects

        if sanitizedProjects != projects {
            projects = sanitizedProjects
            reconcileSelectedProject(previousProjects: previousProjects, updatedProjects: sanitizedProjects, selectingFirstProjectIfNeeded: true)
        }

        persistProjectOrder(profileID: profileID)
    }

    func applyLoadedProjects(_ loadedProjects: [OpenCodeProject], profileID: UUID?) {
        let orderedProjects = resolvedProjectOrder(for: loadedProjects, profileID: profileID)
        let previousProjects = projects
        projects = orderedProjects
        reconcileSelectedProject(previousProjects: previousProjects, updatedProjects: orderedProjects, selectingFirstProjectIfNeeded: true)
        persistProjectOrder(profileID: profileID)
    }

    func applyLoadedSessions(
        _ loadedSessions: [OpenCodeSession],
        statuses: [String: OpenCodeSessionStatus],
        for project: OpenCodeProject
    ) {
        let previousSessions = sessionsByDirectory[project.worktree] ?? []
        var sortedSessions = loadedSessions
            .filter { !$0.isArchived }
            .sorted { $0.time.updated > $1.time.updated }

        if selectedProjectID == project.id,
           let selectedSessionID,
           !sortedSessions.contains(where: { $0.id == selectedSessionID }),
           let selectedCachedSession = previousSessions.first(where: { $0.id == selectedSessionID }),
           !selectedCachedSession.isArchived {
            sortedSessions.append(selectedCachedSession)
            sortedSessions.sort { $0.time.updated > $1.time.updated }
        }

        let previousStatuses = sessionStatusesByDirectory[project.worktree] ?? [:]

        sessionsByDirectory[project.worktree] = sortedSessions
        sessionStatusesByDirectory[project.worktree] = statuses
        sessionSidebarIndicators.applyStatusMap(
            statuses,
            previousStatuses: previousStatuses,
            sessionIDs: sortedSessions.map(\.id),
            in: project.worktree,
            selectedSessionID: selectedSessionID,
            isSelectedDirectory: selectedProjectID == project.id
        )

        guard selectedProjectID == project.id else { return }

        applySelectedProjectCache()

        if selectedSessionID == nil || !sortedSessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sortedSessions.first?.id
            if let selectedSessionID {
                sessionSidebarIndicators.clearIndicator(for: selectedSessionID, in: project.worktree)
            }
        }
    }

    func upsertProject(_ project: OpenCodeProject, profileID: UUID?) {
        var updatedProjects = projects
        let previousProjects = projects

        if let index = updatedProjects.firstIndex(where: { $0.id == project.id }) {
            updatedProjects[index] = project
        } else {
            updatedProjects.append(project)
        }

        projects = resolvedProjectOrder(for: updatedProjects, profileID: profileID)
        reconcileSelectedProject(previousProjects: previousProjects, updatedProjects: projects, selectingFirstProjectIfNeeded: true)
        persistProjectOrder(profileID: profileID)
    }

    @discardableResult
    func upsertSession(_ session: OpenCodeSession, directory: String) -> Bool {
        if session.isArchived {
            return removeSessionID(session.id, directory: directory)
        }

        var cached = sessionsByDirectory[directory] ?? []
        if let index = cached.firstIndex(where: { $0.id == session.id }) {
            cached[index] = session
        } else {
            cached.append(session)
        }

        cached.sort { $0.time.updated > $1.time.updated }
        sessionsByDirectory[directory] = cached

        if directoryMatchesSelection(directory) {
            applySelectedProjectCache()
            if selectedSessionID == nil {
                selectedSessionID = session.id
            }
        }

        return false
    }

    func removeSession(_ session: OpenCodeSession, directory: String) -> Bool {
        removeSessionID(session.id, directory: directory)
    }

    func upsertSessionStatus(_ status: OpenCodeSessionStatus, sessionID: String, directory: String) {
        var cachedStatuses = sessionStatusesByDirectory[directory] ?? [:]
        let previousStatus = cachedStatuses[sessionID]
        cachedStatuses[sessionID] = status
        sessionStatusesByDirectory[directory] = cachedStatuses
        sessionSidebarIndicators.applyStatus(
            status,
            previousStatus: previousStatus,
            sessionID: sessionID,
            in: directory,
            isSelected: directoryMatchesSelection(directory) && selectedSessionID == sessionID
        )

        if directoryMatchesSelection(directory) {
            applySelectedProjectCache()
        }
    }

    func directoryMatchesSelection(_ directory: String) -> Bool {
        guard let selectedProject else { return false }
        return directory == selectedProject.worktree || directory == selectedProject.id
    }

    private func project(for projectID: OpenCodeProject.ID) -> OpenCodeProject? {
        projects.first(where: { $0.id == projectID })
    }

    private func resolvedProjectOrder(for projects: [OpenCodeProject], profileID: UUID?) -> [OpenCodeProject] {
        let storedProjectReferences = profileID.map { projectOrderStore.load(for: $0) } ?? []
        return ProjectOrderResolver.orderedProjects(projects, storedIDs: storedProjectReferences)
    }

    private func persistProjectOrder(profileID: UUID?) {
        guard let profileID else { return }
        let storedProjectReferences = ProjectOrderResolver.storedProjectReferences(for: projects)
        guard !storedProjectReferences.isEmpty else { return }
        projectOrderStore.save(storedProjectReferences, for: profileID)
    }

    @discardableResult
    private func removeSessionID(_ sessionID: String, directory: String) -> Bool {
        var cached = sessionsByDirectory[directory] ?? []
        cached.removeAll { $0.id == sessionID }
        sessionsByDirectory[directory] = cached

        var cachedStatuses = sessionStatusesByDirectory[directory] ?? [:]
        cachedStatuses.removeValue(forKey: sessionID)
        sessionStatusesByDirectory[directory] = cachedStatuses
        sessionSidebarIndicators.removeSession(sessionID, in: directory)

        if directoryMatchesSelection(directory) {
            applySelectedProjectCache()
        }

        guard selectedSessionID == sessionID else { return false }
        selectedSessionID = sessions.first?.id
        return true
    }

    private func applySelectedProjectCache() {
        guard let selectedProject else {
            sessions = []
            return
        }

        sessions = sessionsByDirectory[selectedProject.worktree] ?? []
    }

    private func reconcileSelectedProject(
        previousProjects: [OpenCodeProject],
        updatedProjects: [OpenCodeProject],
        selectingFirstProjectIfNeeded: Bool
    ) {
        let previousSelection = selectedProjectID

        if let selectedProjectID,
           !updatedProjects.contains(where: { $0.id == selectedProjectID }),
           let previousSelectedProject = previousProjects.first(where: { $0.id == selectedProjectID }),
           let replacement = updatedProjects.first(where: {
               ProjectOrderResolver.matchesProjectLocation($0.worktree, previousSelectedProject.worktree)
           }) {
            self.selectedProjectID = replacement.id
        }

        if selectingFirstProjectIfNeeded,
           (selectedProjectID == nil || !updatedProjects.contains(where: { $0.id == selectedProjectID })) {
            selectedProjectID = updatedProjects.first?.id
        }

        if previousSelection != selectedProjectID {
            applySelectedProjectCache()
        }
    }
}
