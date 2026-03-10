import XCTest
@testable import kodanto

@MainActor
final class ProjectOrderTests: XCTestCase {
    func testResolverFallsBackToUpdatedTimeWithoutStoredOrder() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 10),
            makeProject(id: "beta", updatedAt: 30),
            makeProject(id: "gamma", updatedAt: 20)
        ]

        let ordered = ProjectOrderResolver.orderedProjects(projects, storedIDs: [])

        XCTAssertEqual(ordered.map(\.id), ["beta", "gamma", "alpha"])
    }

    func testResolverRespectsStoredOrderAndAppendsNewProjects() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 10),
            makeProject(id: "beta", updatedAt: 30),
            makeProject(id: "gamma", updatedAt: 20)
        ]

        let ordered = ProjectOrderResolver.orderedProjects(projects, storedIDs: ["gamma", "alpha"])

        XCTAssertEqual(ordered.map(\.id), ["gamma", "alpha", "beta"])
    }

    func testReorderedProjectsMovesBeforeTarget() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 40),
            makeProject(id: "beta", updatedAt: 30),
            makeProject(id: "gamma", updatedAt: 20)
        ]

        let ordered = ProjectOrderResolver.reorderedProjects(
            projects,
            movingProjectID: "gamma",
            relativeTo: "alpha",
            placement: .before
        )

        XCTAssertEqual(ordered.map(\.id), ["gamma", "alpha", "beta"])
    }

    func testReorderedProjectsMovesAfterTarget() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 40),
            makeProject(id: "beta", updatedAt: 30),
            makeProject(id: "gamma", updatedAt: 20)
        ]

        let ordered = ProjectOrderResolver.reorderedProjects(
            projects,
            movingProjectID: "alpha",
            relativeTo: "beta",
            placement: .after
        )

        XCTAssertEqual(ordered.map(\.id), ["beta", "alpha", "gamma"])
    }

    func testProjectOrderStorePersistsValuesPerProfile() {
        let suiteName = "ProjectOrderTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ProjectOrderStore(userDefaults: defaults)
        let firstProfileID = UUID()
        let secondProfileID = UUID()

        store.save(["project-a", "project-b"], for: firstProfileID)
        store.save(["project-c"], for: secondProfileID)

        XCTAssertEqual(store.load(for: firstProfileID), ["project-a", "project-b"])
        XCTAssertEqual(store.load(for: secondProfileID), ["project-c"])

        store.remove(for: firstProfileID)

        XCTAssertEqual(store.load(for: firstProfileID), [])
        XCTAssertEqual(store.load(for: secondProfileID), ["project-c"])
    }

    private func makeProject(id: String, updatedAt: Double) -> OpenCodeProject {
        OpenCodeProject(
            id: id,
            worktree: "/tmp/\(id)",
            vcs: nil,
            name: id.capitalized,
            icon: nil,
            commands: nil,
            time: .init(created: 0, updated: updatedAt, initialized: nil),
            sandboxes: []
        )
    }
}
