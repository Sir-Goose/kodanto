import XCTest
@testable import kodanto
import CoreGraphics

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

    func testResolverDeduplicatesProjectsByID() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 10),
            makeProject(id: "alpha", updatedAt: 5),
            makeProject(id: "beta", updatedAt: 30)
        ]

        let ordered = ProjectOrderResolver.orderedProjects(projects, storedIDs: [])

        XCTAssertEqual(ordered.map(\.id), ["beta", "alpha"])
    }

    func testResolverDeduplicatesStoredProjectIDs() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 10),
            makeProject(id: "beta", updatedAt: 30),
            makeProject(id: "gamma", updatedAt: 20)
        ]

        let ordered = ProjectOrderResolver.orderedProjects(projects, storedIDs: ["gamma", "gamma", "alpha"])

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

    func testReorderedProjectsRemovesDuplicateDraggedProject() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 40),
            makeProject(id: "beta", updatedAt: 30),
            makeProject(id: "alpha", updatedAt: 20),
            makeProject(id: "gamma", updatedAt: 10)
        ]

        let ordered = ProjectOrderResolver.reorderedProjects(
            projects,
            movingProjectID: "alpha",
            relativeTo: "gamma",
            placement: .after
        )

        XCTAssertEqual(ordered.map(\.id), ["beta", "gamma", "alpha"])
    }

    func testProjectOrderStoreDeduplicatesSavedIDs() {
        let suiteName = "ProjectOrderTests-Dedupe-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated user defaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ProjectOrderStore(userDefaults: defaults)
        let profileID = UUID()

        store.save(["project-a", "project-a", "project-b"], for: profileID)

        XCTAssertEqual(store.load(for: profileID), ["project-a", "project-b"])
    }

    func testResolverSanitizesExistingDuplicateProjectsUsingStoredOrder() {
        let projects = [
            makeProject(id: "alpha", updatedAt: 40),
            makeProject(id: "beta", updatedAt: 30),
            makeProject(id: "alpha", updatedAt: 20),
            makeProject(id: "gamma", updatedAt: 10)
        ]

        let ordered = ProjectOrderResolver.orderedProjects(projects, storedIDs: ["gamma", "alpha", "beta", "alpha"])

        XCTAssertEqual(ordered.map(\.id), ["gamma", "alpha", "beta"])
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

    func testDropFrameResolverRespectsProjectOrder() {
        let framesByID: [String: CGRect] = [
            "beta": CGRect(x: 0, y: 40, width: 100, height: 20),
            "alpha": CGRect(x: 0, y: 0, width: 100, height: 20)
        ]

        let orderedFrames = ProjectDropFrameResolver.orderedFrames(
            projectOrder: ["alpha", "beta", "gamma"],
            projectHeaderFrames: framesByID
        )

        XCTAssertEqual(orderedFrames.map(\.projectID), ["alpha", "beta"])
    }

    func testDropTargetResolverClampsAboveFirstAndBelowLast() {
        let frames = [
            ProjectDropRowFrame(projectID: "alpha", minY: 0, maxY: 20),
            ProjectDropRowFrame(projectID: "beta", minY: 40, maxY: 60)
        ]

        XCTAssertEqual(
            ProjectDropTargetResolver.resolve(locationY: -10, frames: frames),
            ProjectDropTarget(projectID: "alpha", placement: .before)
        )

        XCTAssertEqual(
            ProjectDropTargetResolver.resolve(locationY: 100, frames: frames),
            ProjectDropTarget(projectID: "beta", placement: .after)
        )
    }

    func testDropTargetResolverUsesRowMidpointBoundary() {
        let frames = [
            ProjectDropRowFrame(projectID: "alpha", minY: 0, maxY: 20),
            ProjectDropRowFrame(projectID: "beta", minY: 40, maxY: 60)
        ]

        XCTAssertEqual(
            ProjectDropTargetResolver.resolve(locationY: 9, frames: frames),
            ProjectDropTarget(projectID: "alpha", placement: .before)
        )

        XCTAssertEqual(
            ProjectDropTargetResolver.resolve(locationY: 10, frames: frames),
            ProjectDropTarget(projectID: "alpha", placement: .before)
        )

        XCTAssertEqual(
            ProjectDropTargetResolver.resolve(locationY: 11, frames: frames),
            ProjectDropTarget(projectID: "alpha", placement: .after)
        )
    }

    func testDropTargetResolverMapsGapToNearestEdge() {
        let frames = [
            ProjectDropRowFrame(projectID: "alpha", minY: 0, maxY: 20),
            ProjectDropRowFrame(projectID: "beta", minY: 40, maxY: 60)
        ]

        XCTAssertEqual(
            ProjectDropTargetResolver.resolve(locationY: 27, frames: frames),
            ProjectDropTarget(projectID: "alpha", placement: .after)
        )

        XCTAssertEqual(
            ProjectDropTargetResolver.resolve(locationY: 36, frames: frames),
            ProjectDropTarget(projectID: "beta", placement: .before)
        )
    }

    func testSidebarFocusNavigatorMovesUpAndDownAcrossMixedRows() {
        let serverID = UUID()
        let items: [SidebarFocusItem] = [
            .server(serverID),
            .addConnection,
            .project("alpha"),
            .session(projectID: "alpha", sessionID: "session-1"),
            .project("beta")
        ]

        XCTAssertEqual(
            SidebarFocusNavigator.next(from: .project("alpha"), in: items),
            .session(projectID: "alpha", sessionID: "session-1")
        )
        XCTAssertEqual(
            SidebarFocusNavigator.previous(from: .project("alpha"), in: items),
            .addConnection
        )
    }

    func testSidebarFocusNavigatorFindsFirstSessionForProject() {
        let items: [SidebarFocusItem] = [
            .project("alpha"),
            .session(projectID: "alpha", sessionID: "session-1"),
            .session(projectID: "alpha", sessionID: "session-2"),
            .project("beta")
        ]

        XCTAssertEqual(
            SidebarFocusNavigator.firstSession(in: "alpha", from: items),
            .session(projectID: "alpha", sessionID: "session-1")
        )
    }

    func testSidebarFocusNavigatorReconcilesRemovedSessionToParentProject() {
        let oldItems: [SidebarFocusItem] = [
            .project("alpha"),
            .session(projectID: "alpha", sessionID: "session-1"),
            .project("beta")
        ]
        let newItems: [SidebarFocusItem] = [
            .project("alpha"),
            .project("beta")
        ]

        XCTAssertEqual(
            SidebarFocusNavigator.reconcileFocus(
                current: .session(projectID: "alpha", sessionID: "session-1"),
                previousItems: oldItems,
                updatedItems: newItems
            ),
            .project("alpha")
        )
    }

    func testSidebarFocusNavigatorReconcilesRemovedProjectToPreviousItem() {
        let oldItems: [SidebarFocusItem] = [
            .server(UUID()),
            .addConnection,
            .project("alpha"),
            .project("beta")
        ]
        let newItems: [SidebarFocusItem] = [
            oldItems[0],
            .addConnection,
            .project("beta")
        ]

        XCTAssertEqual(
            SidebarFocusNavigator.reconcileFocus(
                current: .project("alpha"),
                previousItems: oldItems,
                updatedItems: newItems
            ),
            .addConnection
        )
    }

    func testDropValidationResolverForbidsSelfDropAndAllowsOtherProject() {
        XCTAssertFalse(
            ProjectDropValidationResolver.canDrop(
                draggedProjectID: nil,
                targetProjectID: "alpha"
            )
        )

        XCTAssertFalse(
            ProjectDropValidationResolver.canDrop(
                draggedProjectID: "alpha",
                targetProjectID: "alpha"
            )
        )

        XCTAssertTrue(
            ProjectDropValidationResolver.canDrop(
                draggedProjectID: "beta",
                targetProjectID: "alpha"
            )
        )
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
