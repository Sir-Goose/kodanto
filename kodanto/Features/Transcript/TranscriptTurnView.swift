import Observation
import SwiftUI

struct TranscriptTurnView: View {
    let turn: TranscriptTurn
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Bindable var disclosureStore: TranscriptDisclosureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if turn.user != nil {
                UserPromptCard(parts: turn.userVisibleParts, worktreeRoot: worktreeRoot)
            }

            let groups = turn.assistantPartGroups
            if !groups.isEmpty {
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
            }
        }
    }
}

private struct UserPromptCard: View {
    let parts: [OpenCodePart]
    let worktreeRoot: String?

    var body: some View {
        if !parts.isEmpty {
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
