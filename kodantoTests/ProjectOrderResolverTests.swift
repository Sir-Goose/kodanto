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

final class SessionRecencyFormatterTests: XCTestCase {
    func testRecencyBoundaryTransitions() {
        XCTAssertEqual(formatted(elapsed: 59 * minute), "59m")
        XCTAssertEqual(formatted(elapsed: 60 * minute), "1h")
        XCTAssertEqual(formatted(elapsed: 24 * hour), "1d")
        XCTAssertEqual(formatted(elapsed: 7 * day), "1w")
        XCTAssertEqual(formatted(elapsed: 52 * week), "1y")
    }

    func testRecencyUsesYearsForMultiYearElapsedTime() {
        XCTAssertEqual(formatted(elapsed: 104 * week), "2y")
    }

    func testRecencyCapsAtNinetyNineYearsPlus() {
        XCTAssertEqual(formatted(elapsed: 100 * 52 * week), "99y+")
    }

    func testSidebarTemplateTokenStaysInSyncWithFormatterMaxToken() {
        XCTAssertEqual(SessionSidebarRow.trailingAccessoryTemplateToken, SessionRecencyFormatter.maxLayoutToken)
    }

    private func formatted(elapsed: TimeInterval) -> String {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let timestamp = now.addingTimeInterval(-elapsed).timeIntervalSince1970
        return SessionRecencyFormatter.string(since: timestamp, now: now)
    }

    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60
    private let week: TimeInterval = 7 * 24 * 60 * 60
}

final class OpenCodeModelOptionVariantDisplayTests: XCTestCase {
    func testDisplayVariantNameCapitalizesSingleWordVariants() {
        XCTAssertEqual(OpenCodeModelOption.displayVariantName("low"), "Low")
        XCTAssertEqual(OpenCodeModelOption.displayVariantName("medium"), "Medium")
        XCTAssertEqual(OpenCodeModelOption.displayVariantName("high"), "High")
    }

    func testDisplayVariantNameMapsXHighToExtraHigh() {
        XCTAssertEqual(OpenCodeModelOption.displayVariantName("xhigh"), "Extra High")
        XCTAssertEqual(OpenCodeModelOption.displayVariantName("XHIGH"), "Extra High")
    }

    func testDisplayVariantNameNormalizesDelimitedUnknownVariants() {
        XCTAssertEqual(OpenCodeModelOption.displayVariantName("super_high"), "Super High")
        XCTAssertEqual(OpenCodeModelOption.displayVariantName("ultra-high"), "Ultra High")
    }
}
