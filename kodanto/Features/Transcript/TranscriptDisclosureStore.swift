import Observation
import SwiftUI

enum TranscriptDisclosureKey: Hashable {
    case contextGroup(String)
    case tool(String)
    case patchFile(toolID: String, filePath: String)
    case shellOutput(String)
}

@MainActor
@Observable
final class TranscriptDisclosureStore {
    private var states: [TranscriptDisclosureKey: Bool] = [:]

    func binding(for key: TranscriptDisclosureKey, defaultOpen: Bool = false) -> Binding<Bool> {
        Binding(
            get: { self.states[key] ?? defaultOpen },
            set: { self.states[key] = $0 }
        )
    }

    func reset() {
        states.removeAll()
    }
}
