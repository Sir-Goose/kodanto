import Observation
import SwiftUI

struct TranscriptPartView: View {
    let part: OpenCodePart
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Bindable var disclosureStore: TranscriptDisclosureStore

    var body: some View {
        switch part {
        case .text(let value):
            MarkdownText(text: value.text)
                .equatable()
                .textSelection(.enabled)
        case .reasoning(let value):
            MarkdownText(text: value.text)
                .equatable()
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .tool(let tool):
            ToolPartView(
                tool: tool,
                worktreeRoot: worktreeRoot,
                resolveTaskTarget: resolveTaskTarget,
                navigateToSession: navigateToSession,
                disclosureStore: disclosureStore
            )
        default:
            Text(part.summary)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct ContextToolGroupView: View {
    let tools: [OpenCodePart.Tool]
    let worktreeRoot: String?
    @Binding var isExpanded: Bool

    private var isRunning: Bool {
        tools.contains(where: \.isPendingOrRunning)
    }

    private var summaryText: String {
        let readCount = tools.filter { $0.tool == "read" }.count
        let searchCount = tools.filter { $0.tool == "glob" || $0.tool == "grep" }.count
        let listCount = tools.filter { $0.tool == "list" }.count

        let pieces = [
            readCount > 0 ? countLabel(readCount, singular: "read", plural: "reads") : nil,
            searchCount > 0 ? countLabel(searchCount, singular: "search", plural: "searches") : nil,
            listCount > 0 ? countLabel(listCount, singular: "list", plural: "lists") : nil
        ].compactMap { $0 }

        return pieces.joined(separator: " · ")
    }

    var body: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: true,
            header: {
                ToolHeaderSummary(
                    title: isRunning ? "Exploring" : "Explored",
                    subtitle: summaryText.isEmpty ? nil : .text(summaryText),
                    badges: [],
                    status: isRunning ? "Running" : "Done",
                    isRunning: isRunning,
                    icon: "magnifyingglass"
                )
            },
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tools, id: \.id) { tool in
                        ContextToolItem(tool: tool, worktreeRoot: worktreeRoot)
                    }
                }
                .padding(.top, 2)
            }
        )
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

private struct ContextToolItem: View {
    let tool: OpenCodePart.Tool
    let worktreeRoot: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toolIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(tool.titleLabel)
                    .font(.callout.weight(.medium))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !tool.argBadges.isEmpty {
                    ToolBadges(badges: tool.argBadges)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var toolIcon: String {
        switch tool.tool {
        case "read":
            return "eyeglasses"
        case "glob", "grep":
            return "magnifyingglass"
        case "list":
            return "list.bullet"
        default:
            return "wrench.adjustable"
        }
    }

    private var subtitle: String? {
        switch tool.tool {
        case "read":
            return TranscriptPathFormatter.displayPath(tool.filePath, worktreeRoot: worktreeRoot)
        case "list":
            return TranscriptPathFormatter.directory(tool.inputValues["path"]?.stringValue, worktreeRoot: worktreeRoot)
        case "glob", "grep":
            return TranscriptPathFormatter.directory(tool.inputValues["path"]?.stringValue, worktreeRoot: worktreeRoot)
        default:
            return tool.subtitleText
        }
    }
}
