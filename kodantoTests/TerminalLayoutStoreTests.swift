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

    func testResumeStoreReturnsNilWhenMissing() {
        let defaults = UserDefaults(suiteName: "terminal-resume-tests-\(UUID().uuidString)")!
        let store = TerminalResumeStateStore(userDefaults: defaults)

        XCTAssertNil(store.load(profileID: UUID(), directory: "/tmp/project"))
    }

    func testResumeStoreRoundTripsByProfileAndDirectory() {
        let defaults = UserDefaults(suiteName: "terminal-resume-tests-\(UUID().uuidString)")!
        let store = TerminalResumeStateStore(userDefaults: defaults)
        let profileID = UUID()
        let directory = "/tmp/project"
        let saved = TerminalResumeState(ptyID: "pty-1", cursor: 42, buffer: "hello")

        store.save(saved, profileID: profileID, directory: directory)

        XCTAssertEqual(store.load(profileID: profileID, directory: directory), saved)
    }

    func testResumeStoreFallsBackToNilWhenCorrupted() {
        let defaults = UserDefaults(suiteName: "terminal-resume-tests-\(UUID().uuidString)")!
        defaults.set(Data("not-json".utf8), forKey: "kodanto.terminalResumeByProfileAndDirectory.v1")
        let store = TerminalResumeStateStore(userDefaults: defaults)

        XCTAssertNil(store.load(profileID: UUID(), directory: "/tmp/project"))
    }

    func testResumeStoreIsScopedByProfileAndDirectory() {
        let defaults = UserDefaults(suiteName: "terminal-resume-tests-\(UUID().uuidString)")!
        let store = TerminalResumeStateStore(userDefaults: defaults)
        let profileA = UUID()
        let profileB = UUID()
        let directoryA = "/tmp/project-a"
        let directoryB = "/tmp/project-b"

        let stateA = TerminalResumeState(ptyID: "pty-a", cursor: 1, buffer: "a")
        let stateB = TerminalResumeState(ptyID: "pty-b", cursor: 2, buffer: "b")
        store.save(stateA, profileID: profileA, directory: directoryA)
        store.save(stateB, profileID: profileB, directory: directoryB)

        XCTAssertEqual(store.load(profileID: profileA, directory: directoryA), stateA)
        XCTAssertNil(store.load(profileID: profileA, directory: directoryB))
        XCTAssertNil(store.load(profileID: profileB, directory: directoryA))
        XCTAssertEqual(store.load(profileID: profileB, directory: directoryB), stateB)
    }
}
