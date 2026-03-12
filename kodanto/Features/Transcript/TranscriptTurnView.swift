import AppKit
import Observation
import SwiftUI

struct TranscriptTurnView: View {
    let turn: TranscriptTurn
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Bindable var disclosureStore: TranscriptDisclosureStore
    @State private var isAssistantHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if turn.user != nil {
                UserPromptCard(
                    parts: turn.userVisibleParts,
                    worktreeRoot: worktreeRoot,
                    copyText: turn.userCopyText
                )
            }

            let groups = turn.assistantPartGroups
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 10) {
                        if turn.user == nil {
                            Text("OpenCode")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(groups) { group in
                            AssistantPartGroupView(
                                group: group,
                                worktreeRoot: worktreeRoot,
                                resolveTaskTarget: resolveTaskTarget,
                                navigateToSession: navigateToSession,
                                disclosureStore: disclosureStore
                            )
                        }
                    }
                    .padding(.leading, turn.user == nil ? 0 : 12)

                    CopyActionRow(
                        text: turn.assistantCopyText,
                        isVisible: isAssistantHovered,
                        helpText: "Copy response"
                    )
                    .padding(.leading, turn.user == nil ? 0 : 12)
                }
                .contentShape(Rectangle())
                .onHover { isAssistantHovered = $0 }
            }
        }
    }
}

private struct UserPromptCard: View {
    let parts: [OpenCodePart]
    let worktreeRoot: String?
    let copyText: String?
    @State private var isHovered = false

    var body: some View {
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You")
                        .font(.headline)

                    ForEach(parts) { part in
                        TranscriptPartView(
                            part: part,
                            worktreeRoot: worktreeRoot,
                            resolveTaskTarget: { _ in nil },
                            navigateToSession: { _ in },
                            disclosureStore: TranscriptDisclosureStore()
                        )
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                )

                CopyActionRow(
                    text: copyText,
                    isVisible: isHovered,
                    helpText: "Copy prompt"
                )
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }
    }
}

private struct CopyActionRow: View {
    let text: String?
    let isVisible: Bool
    let helpText: String

    var body: some View {
        if text != nil {
            HStack(spacing: 0) {
                HoverCopyButton(
                    text: text,
                    isVisible: isVisible,
                    helpText: helpText
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 24, alignment: .leading)
        }
    }
}

private struct HoverCopyButton: View {
    let text: String?
    let isVisible: Bool
    let helpText: String

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Group {
            if text != nil {
                Button(action: copyToClipboard) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(didCopy ? "Copied" : helpText)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .animation(.easeInOut(duration: 0.15), value: isVisible)
                .onDisappear {
                    resetTask?.cancel()
                    resetTask = nil
                }
            }
        }
    }

    private func copyToClipboard() {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        didCopy = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                didCopy = false
            }
        }
    }
}

private struct AssistantPartGroupView: View {
    let group: AssistantPartGroup
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Bindable var disclosureStore: TranscriptDisclosureStore

    var body: some View {
        switch group {
        case .part(let part):
            TranscriptPartView(
                part: part,
                worktreeRoot: worktreeRoot,
                resolveTaskTarget: resolveTaskTarget,
                navigateToSession: navigateToSession,
                disclosureStore: disclosureStore
            )
        case .context(let id, let tools):
            ContextToolGroupView(
                tools: tools,
                worktreeRoot: worktreeRoot,
                isExpanded: disclosureStore.binding(for: .contextGroup(id), defaultOpen: false)
            )
        }
    }
}
