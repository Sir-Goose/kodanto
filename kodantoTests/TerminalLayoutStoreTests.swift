import XCTest
@testable import kodanto

final class TerminalLayoutStoreTests: XCTestCase {
    func testLoadReturnsDefaultWhenMissing() {
        let defaults = UserDefaults(suiteName: "terminal-layout-tests-\(UUID().uuidString)")!
        let store = TerminalLayoutStore(userDefaults: defaults)

        XCTAssertEqual(store.load(), .default)
    }

    func testSavePersistsOpenAndHeight() {
        let defaults = UserDefaults(suiteName: "terminal-layout-tests-\(UUID().uuidString)")!
        let store = TerminalLayoutStore(userDefaults: defaults)

        let saved = TerminalLayoutState(isOpen: true, height: 333)
        store.save(saved)

        XCTAssertEqual(store.load(), saved)
    }
}
