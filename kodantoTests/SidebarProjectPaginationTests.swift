import XCTest
@testable import kodanto

final class SidebarProjectPaginationTests: XCTestCase {
    func testDefaultShowsTwentyFiveAndRendersShowMoreWithHiddenCount() {
        let projection = SidebarProjectPagination.projection(
            totalProjectCount: 100,
            selectedProjectIndex: nil,
            isShowingAll: false,
            defaultVisibleCount: 25
        )

        XCTAssertEqual(projection.visibleCount, 25)
        XCTAssertEqual(projection.hiddenCount, 75)
        XCTAssertTrue(projection.showsShowMore)
        XCTAssertFalse(projection.showsShowLess)
    }

    func testShowMoreRevealsAllAndShowsShowLess() {
        let projection = SidebarProjectPagination.projection(
            totalProjectCount: 100,
            selectedProjectIndex: nil,
            isShowingAll: true,
            defaultVisibleCount: 25
        )

        XCTAssertEqual(projection.visibleCount, 100)
        XCTAssertEqual(projection.hiddenCount, 0)
        XCTAssertFalse(projection.showsShowMore)
        XCTAssertTrue(projection.showsShowLess)
    }

    func testSelectedProjectOutsideDefaultWindowStaysVisible() {
        let projection = SidebarProjectPagination.projection(
            totalProjectCount: 100,
            selectedProjectIndex: 40,
            isShowingAll: false,
            defaultVisibleCount: 25
        )

        XCTAssertEqual(projection.visibleCount, 41)
        XCTAssertEqual(projection.hiddenCount, 59)
        XCTAssertTrue(projection.showsShowMore)
        XCTAssertFalse(projection.showsShowLess)
    }

    func testTwentyFiveOrFewerProjectsShowNoPaginationControl() {
        let projection = SidebarProjectPagination.projection(
            totalProjectCount: 25,
            selectedProjectIndex: nil,
            isShowingAll: false,
            defaultVisibleCount: 25
        )

        XCTAssertEqual(projection.visibleCount, 25)
        XCTAssertEqual(projection.hiddenCount, 0)
        XCTAssertFalse(projection.showsShowMore)
        XCTAssertFalse(projection.showsShowLess)
    }

    func testProjectListChangeResetsShowAllState() {
        XCTAssertFalse(SidebarProjectPaginationStateResolver.resetShowAllStateAfterProjectListChange())
    }
}
