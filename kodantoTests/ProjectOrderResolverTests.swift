import XCTest
@testable import kodanto

final class ProjectOrderResolverTests: XCTestCase {
    func testStoredProjectReferencesDeduplicateNormalizedWorktrees() {
        let projects = [
            TestFixtures.project(id: "project-a", worktree: "/tmp/project", updatedAt: 10),
            TestFixtures.project(id: "project-b", worktree: "/tmp/./project", updatedAt: 20),
            TestFixtures.project(id: "project-c", worktree: "/tmp/other", updatedAt: 30)
        ]

        let references = ProjectOrderResolver.storedProjectReferences(for: projects)

        XCTAssertEqual(references, ["worktree:/tmp/project", "worktree:/tmp/other"])
    }

    func testOrderedProjectsRespectStoredOrderBeforeRecencyFallback() {
        let first = TestFixtures.project(id: "first", worktree: "/tmp/first", updatedAt: 10)
        let second = TestFixtures.project(id: "second", worktree: "/tmp/second", updatedAt: 30)
        let third = TestFixtures.project(id: "third", worktree: "/tmp/third", updatedAt: 20)

        let ordered = ProjectOrderResolver.orderedProjects([first, second, third], storedIDs: [third.id, first.id])

        XCTAssertEqual(ordered.map(\.id), [third.id, first.id, second.id])
    }

    func testDeduplicatedProjectsPreferStoredMatchOverRecency() {
        let moreRecent = TestFixtures.project(id: "recent", worktree: "/tmp/project", updatedAt: 50)
        let storedPreferred = TestFixtures.project(id: "preferred", worktree: "/tmp/./project", updatedAt: 10)

        let projects = ProjectOrderResolver.deduplicatedProjects([moreRecent, storedPreferred], preferredIDs: [storedPreferred.id])

        XCTAssertEqual(projects.map(\.id), [storedPreferred.id])
    }

    func testReorderedProjectsInsertMovedProjectAfterTarget() {
        let first = TestFixtures.project(id: "first", worktree: "/tmp/first", updatedAt: 10)
        let second = TestFixtures.project(id: "second", worktree: "/tmp/second", updatedAt: 20)
        let third = TestFixtures.project(id: "third", worktree: "/tmp/third", updatedAt: 30)

        let reordered = ProjectOrderResolver.reorderedProjects(
            [first, second, third],
            movingProjectID: first.id,
            relativeTo: second.id,
            placement: .after
        )

        XCTAssertEqual(reordered.map(\.id), [second.id, first.id, third.id])
    }

    func testMatchesProjectLocationNormalizesPaths() {
        XCTAssertTrue(ProjectOrderResolver.matchesProjectLocation("/tmp/project", "/tmp/./project"))
    }
}
