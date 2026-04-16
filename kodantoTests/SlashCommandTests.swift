import Foundation
@testable import kodanto
import XCTest

final class SlashCommandTests: XCTestCase {
    func testBuiltinCommandsAreNotEmpty() {
        XCTAssertFalse(SlashCommand.builtinCommands.isEmpty)
    }

    func testBuiltinCommandsHaveUniqueIDs() {
        let ids = SlashCommand.builtinCommands.map { $0.id }
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Command IDs should be unique")
    }

    func testBuiltinCommandsHaveUniqueTriggers() {
        let triggers = SlashCommand.builtinCommands.map { $0.trigger }
        let uniqueTriggers = Set(triggers)
        XCTAssertEqual(triggers.count, uniqueTriggers.count, "Command triggers should be unique")
    }

    func testAllBuiltinCommandsHaveTitles() {
        for command in SlashCommand.builtinCommands {
            XCTAssertFalse(command.title.isEmpty, "Command \(command.id) should have a title")
        }
    }

    func testAllBuiltinCommandsHaveTypeBuiltin() {
        for command in SlashCommand.builtinCommands {
            XCTAssertEqual(command.type, .builtin, "Command \(command.id) should be builtin")
        }
    }

    func testSlashCommandEquality() {
        let command1 = SlashCommand(
            id: "test.command",
            trigger: "test",
            title: "Test Command",
            description: "A test command",
            keybind: "⌘T",
            type: .builtin,
            source: nil,
            availability: .always
        )
        let command2 = SlashCommand(
            id: "test.command",
            trigger: "test",
            title: "Test Command",
            description: "A test command",
            keybind: "⌘T",
            type: .builtin,
            source: nil,
            availability: .always
        )
        XCTAssertEqual(command1, command2)
    }

    func testSlashCommandInequality() {
        let command1 = SlashCommand(
            id: "test.command1",
            trigger: "test1",
            title: "Test Command 1",
            description: nil,
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .always
        )
        let command2 = SlashCommand(
            id: "test.command2",
            trigger: "test2",
            title: "Test Command 2",
            description: nil,
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .always
        )
        XCTAssertNotEqual(command1, command2)
    }

    func testSlashCommandHash() {
        let command = SlashCommand(
            id: "test.command",
            trigger: "test",
            title: "Test Command",
            description: nil,
            keybind: nil,
            type: .builtin,
            source: nil,
            availability: .always
        )
        var hashSet = Set<SlashCommand>()
        hashSet.insert(command)
        XCTAssertTrue(hashSet.contains(command))
    }

    func testAvailabilityFiltersWithoutSession() {
        let alwaysCommands = SlashCommand.builtinCommands.filter { $0.availability == .always }
        let sessionCommands = SlashCommand.builtinCommands.filter { $0.availability == .requiresSession }
        let messageCommands = SlashCommand.builtinCommands.filter { $0.availability == .requiresSessionWithMessages }
        XCTAssertFalse(alwaysCommands.isEmpty, "Should have always-available commands")
        XCTAssertFalse(sessionCommands.isEmpty || messageCommands.isEmpty, "Should have session-dependent commands")
    }
}

final class ComposerStoreSlashCommandTests: XCTestCase {
    var store: ComposerStore!

    override func setUp() {
        super.setUp()
        store = ComposerStore(
            modelSelectionStore: ModelSelectionStore(),
            modelVariantSelectionStore: ModelVariantSelectionStore()
        )
    }

    func testSlashCommandsAreInitialized() {
        XCTAssertFalse(store.slashCommands.isEmpty)
        XCTAssertEqual(store.slashCommands.count, SlashCommand.builtinCommands.count)
    }

    func testFilteredCommandsStartWithContextAware() {
        store.hasActiveSession = false
        store.hasMessages = false
        let alwaysCount = SlashCommand.builtinCommands.filter { $0.availability == .always }.count
        XCTAssertEqual(store.filteredSlashCommands.count, alwaysCount)
    }

    func testFilteredCommandsIncludeSessionDependentWithSession() {
        store.hasActiveSession = true
        store.hasMessages = true
        store.updateSlashQuery("")
        XCTAssertEqual(store.filteredSlashCommands.count, SlashCommand.builtinCommands.count)
    }

    func testFilterByTrigger() {
        store.hasActiveSession = true
        store.hasMessages = true
        store.updateSlashQuery("new")
        XCTAssertTrue(store.filteredSlashCommands.allSatisfy { $0.trigger.contains("new") })
    }

    func testFilterByTitle() {
        store.hasActiveSession = true
        store.hasMessages = true
        store.updateSlashQuery("session")
        XCTAssertTrue(store.filteredSlashCommands.allSatisfy {
            $0.title.lowercased().contains("session")
        })
    }

    func testFilterByDescription() {
        store.hasActiveSession = true
        store.hasMessages = true
        store.updateSlashQuery("share")
        let matchingShare = store.filteredSlashCommands.contains { $0.id == "session.share" }
        XCTAssertTrue(matchingShare)
    }

    func testFilterIsCaseInsensitive() {
        store.hasActiveSession = true
        store.hasMessages = true
        store.updateSlashQuery("NEW")
        XCTAssertTrue(store.filteredSlashCommands.allSatisfy { $0.trigger.contains("new") })
    }

    func testEmptyQueryReturnsContextAwareCommands() {
        store.hasActiveSession = true
        store.hasMessages = true
        store.updateSlashQuery("")
        XCTAssertEqual(store.filteredSlashCommands.count, SlashCommand.builtinCommands.count)
    }

    func testSelectNextSlashCommand() {
        store.showSlashPopover()
        let initialIndex = store.selectedSlashCommandIndex
        store.selectNextSlashCommand()
        XCTAssertEqual(store.selectedSlashCommandIndex, initialIndex + 1)
    }

    func testSelectPreviousSlashCommand() {
        store.showSlashPopover()
        store.selectNextSlashCommand()
        let indexAfterNext = store.selectedSlashCommandIndex
        store.selectPreviousSlashCommand()
        XCTAssertEqual(store.selectedSlashCommandIndex, indexAfterNext - 1)
    }

    func testSelectNextDoesNotExceedBounds() {
        store.showSlashPopover()
        let maxIndex = store.filteredSlashCommands.count - 1
        for _ in 0..<10 {
            store.selectNextSlashCommand()
        }
        XCTAssertLessThanOrEqual(store.selectedSlashCommandIndex, maxIndex)
    }

    func testSelectPreviousDoesNotGoBelowZero() {
        store.showSlashPopover()
        for _ in 0..<10 {
            store.selectPreviousSlashCommand()
        }
        XCTAssertGreaterThanOrEqual(store.selectedSlashCommandIndex, 0)
    }

    func testShowSlashPopoverResetsIndex() {
        store.showSlashPopover()
        store.selectNextSlashCommand()
        store.selectNextSlashCommand()
        store.hideSlashPopover()
        store.showSlashPopover()
        XCTAssertEqual(store.selectedSlashCommandIndex, 0)
    }

    func testHideSlashPopoverClearsQuery() {
        store.updateSlashQuery("test")
        store.hideSlashPopover()
        XCTAssertTrue(store.slashQuery.isEmpty)
    }

    func testSelectedSlashCommandReturnsCorrectCommand() {
        store.showSlashPopover()
        store.selectNextSlashCommand()
        let selected = store.selectedSlashCommand
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.id, store.filteredSlashCommands[store.selectedSlashCommandIndex].id)
    }

    func testContextFiltersOutSessionCommandsWhenNoSession() {
        store.hasActiveSession = false
        store.hasMessages = false
        store.updateSlashQuery("")
        let alwaysIDs = SlashCommand.builtinCommands.filter { $0.availability == .always }.map(\.id)
        let filteredIDs = store.filteredSlashCommands.map(\.id)
        XCTAssertEqual(filteredIDs.sorted(), alwaysIDs.sorted())
    }

    func testContextFiltersOutMessageCommandsWhenNoMessages() {
        store.hasActiveSession = true
        store.hasMessages = false
        store.updateSlashQuery("")
        let alwaysAndSessionOnlyIDs = SlashCommand.builtinCommands.filter { $0.availability != .requiresSessionWithMessages }.map(\.id)
        let filteredIDs = store.filteredSlashCommands.map(\.id)
        XCTAssertEqual(filteredIDs.sorted(), alwaysAndSessionOnlyIDs.sorted())
    }
        store.updateSlashQuery("nonexistentcommand12345")
        XCTAssertNil(store.selectedSlashCommand)
    }
}