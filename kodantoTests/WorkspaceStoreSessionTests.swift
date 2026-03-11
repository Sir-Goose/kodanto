import XCTest
@testable import kodanto

@MainActor
final class WorkspaceStoreSessionTests: XCTestCase {
    func testApplyLoadedSessionsFiltersArchivedSessions() {
        let store = WorkspaceStore(projectOrderStore: TestProjectOrderStore())
        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        store.applyLoadedProjects([project], profileID: nil)
        store.selectProject(project.id)

        let active = makeSession(id: "active", title: "Active", updatedAt: 200, archivedAt: nil)
        let archived = makeSession(id: "archived", title: "Archived", updatedAt: 300, archivedAt: 10)

        store.applyLoadedSessions([active, archived], statuses: [:], for: project)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id, active.id)
        XCTAssertEqual(store.selectedSessionID, active.id)
    }

    func testUpsertSessionUpdatesActiveSessionTitle() {
        let store = WorkspaceStore(projectOrderStore: TestProjectOrderStore())
        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        let original = makeSession(id: "session-1", title: "Old Title", updatedAt: 200, archivedAt: nil)
        let renamed = makeSession(id: "session-1", title: "New Title", updatedAt: 210, archivedAt: nil)

        store.applyLoadedProjects([project], profileID: nil)
        store.selectProject(project.id)
        store.applyLoadedSessions([original], statuses: [:], for: project)
        _ = store.upsertSession(renamed, directory: project.worktree)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.title, "New Title")
    }

    func testUpsertSessionRemovesArchivedSessionAndClearsSelection() {
        let store = WorkspaceStore(projectOrderStore: TestProjectOrderStore())
        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        let active = makeSession(id: "session-1", title: "Session", updatedAt: 200, archivedAt: nil)
        let archivedVersion = makeSession(id: "session-1", title: "Session", updatedAt: 210, archivedAt: 20)

        store.applyLoadedProjects([project], profileID: nil)
        store.selectProject(project.id)
        store.applyLoadedSessions([active], statuses: [:], for: project)

        let selectionChanged = store.upsertSession(archivedVersion, directory: project.worktree)

        XCTAssertTrue(selectionChanged)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.selectedSessionID)
    }

    func testUpsertSessionRemovesArchivedSelectedSessionAndFallsBackToNext() {
        let store = WorkspaceStore(projectOrderStore: TestProjectOrderStore())
        let project = TestFixtures.project(id: "project-1", worktree: "/tmp/project-1", updatedAt: 100)
        let first = makeSession(id: "session-1", title: "First", updatedAt: 300, archivedAt: nil)
        let second = makeSession(id: "session-2", title: "Second", updatedAt: 200, archivedAt: nil)
        let secondArchived = makeSession(id: "session-2", title: "Second", updatedAt: 210, archivedAt: 22)

        store.applyLoadedProjects([project], profileID: nil)
        store.selectProject(project.id)
        store.applyLoadedSessions([first, second], statuses: [:], for: project)
        _ = store.selectSession(second.id, in: project.id)

        let selectionChanged = store.upsertSession(secondArchived, directory: project.worktree)

        XCTAssertTrue(selectionChanged)
        XCTAssertEqual(store.selectedSessionID, first.id)
        XCTAssertEqual(store.sessions.map(\.id), [first.id])
    }

    private func makeSession(
        id: String,
        title: String,
        updatedAt: Double,
        archivedAt: Double?
    ) -> OpenCodeSession {
        OpenCodeSession(
            id: id,
            slug: id,
            projectID: "project-1",
            workspaceID: nil,
            directory: "/tmp/project-1",
            parentID: nil,
            summary: nil,
            share: nil,
            title: title,
            version: "1",
            time: .init(created: updatedAt - 60, updated: updatedAt, compacting: nil, archived: archivedAt),
            revert: nil
        )
    }
}

private struct TestProjectOrderStore: ProjectOrderStoring {
    func load(for profileID: UUID) -> [String] { [] }
    func save(_ projectIDs: [String], for profileID: UUID) {}
    func remove(for profileID: UUID) {}
}
