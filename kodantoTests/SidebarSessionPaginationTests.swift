import XCTest
@testable import kodanto

final class SidebarSessionPaginationTests: XCTestCase {
    func testDefaultShowsTenAndRendersShowMoreWithHiddenCount() {
        let projection = SidebarSessionPagination.projection(
            totalSessionCount: 25,
            selectedSessionIndex: nil,
            isShowingAll: false,
            defaultVisibleCount: 10
        )

        XCTAssertEqual(projection.visibleCount, 10)
        XCTAssertEqual(projection.hiddenCount, 15)
        XCTAssertTrue(projection.showsShowMore)
        XCTAssertFalse(projection.showsShowLess)
    }

    func testShowMoreRevealsAllAndShowsShowLess() {
        let projection = SidebarSessionPagination.projection(
            totalSessionCount: 25,
            selectedSessionIndex: nil,
            isShowingAll: true,
            defaultVisibleCount: 10
        )

        XCTAssertEqual(projection.visibleCount, 25)
        XCTAssertEqual(projection.hiddenCount, 0)
        XCTAssertFalse(projection.showsShowMore)
        XCTAssertTrue(projection.showsShowLess)
    }

    func testShowLessReturnsToDefaultWindow() {
        let projection = SidebarSessionPagination.projection(
            totalSessionCount: 25,
            selectedSessionIndex: nil,
            isShowingAll: false,
            defaultVisibleCount: 10
        )

        XCTAssertEqual(projection.visibleCount, 10)
        XCTAssertTrue(projection.showsShowMore)
        XCTAssertFalse(projection.showsShowLess)
    }

    func testSelectedSessionOutsideDefaultWindowStaysVisible() {
        let projection = SidebarSessionPagination.projection(
            totalSessionCount: 25,
            selectedSessionIndex: 18,
            isShowingAll: false,
            defaultVisibleCount: 10
        )

        XCTAssertEqual(projection.visibleCount, 19)
        XCTAssertEqual(projection.hiddenCount, 6)
        XCTAssertTrue(projection.showsShowMore)
        XCTAssertFalse(projection.showsShowLess)
    }

    func testTenOrFewerSessionsShowNoPaginationControl() {
        let projection = SidebarSessionPagination.projection(
            totalSessionCount: 10,
            selectedSessionIndex: nil,
            isShowingAll: false,
            defaultVisibleCount: 10
        )

        XCTAssertEqual(projection.visibleCount, 10)
        XCTAssertEqual(projection.hiddenCount, 0)
        XCTAssertFalse(projection.showsShowMore)
        XCTAssertFalse(projection.showsShowLess)
    }

    func testCollapsingProjectResetsShowMoreState() {
        let projectsShowingAll: Set<OpenCodeProject.ID> = ["project-a", "project-b"]

        let resolved = SidebarSessionPaginationStateResolver.collapsed(
            projectsShowingAll,
            projectID: "project-a"
        )

        XCTAssertEqual(resolved, ["project-b"])
    }

    func testSanitizingShowMoreStateDropsMissingProjects() {
        let projectsShowingAll: Set<OpenCodeProject.ID> = ["project-a", "project-b", "project-c"]
        let validProjectIDs: Set<OpenCodeProject.ID> = ["project-b", "project-c", "project-d"]

        let resolved = SidebarSessionPaginationStateResolver.sanitized(
            projectsShowingAll,
            validProjectIDs: validProjectIDs
        )

        XCTAssertEqual(resolved, ["project-b", "project-c"])
    }
}
