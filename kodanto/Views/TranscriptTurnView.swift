import AppKit
import SwiftUI

struct TranscriptTurnView: View {
    let turn: TranscriptTurn
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Binding var disclosureStates: [String: Bool]
    @Binding var patchDisclosureStates: [String: Bool]
    @Binding var shellOutputDisclosureStates: [String: Bool]

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
                            disclosureStates: $disclosureStates,
                            patchDisclosureStates: $patchDisclosureStates,
                            shellOutputDisclosureStates: $shellOutputDisclosureStates
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
                        disclosureStates: .constant([:]),
                        patchDisclosureStates: .constant([:]),
                        shellOutputDisclosureStates: .constant([:])
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
    @Binding var disclosureStates: [String: Bool]
    @Binding var patchDisclosureStates: [String: Bool]
    @Binding var shellOutputDisclosureStates: [String: Bool]

    var body: some View {
        switch group {
        case .part(let part):
            TranscriptPartView(
                part: part,
                worktreeRoot: worktreeRoot,
                resolveTaskTarget: resolveTaskTarget,
                navigateToSession: navigateToSession,
                disclosureStates: $disclosureStates,
                patchDisclosureStates: $patchDisclosureStates,
                shellOutputDisclosureStates: $shellOutputDisclosureStates
            )
        case .context(let id, let tools):
            ContextToolGroupView(
                id: id,
                tools: tools,
                worktreeRoot: worktreeRoot,
                isExpanded: binding(for: id, defaultOpen: false)
            )
        }
    }

    private func binding(for key: String, defaultOpen: Bool) -> Binding<Bool> {
        Binding(
            get: { disclosureStates[key] ?? defaultOpen },
            set: { disclosureStates[key] = $0 }
        )
    }
}

private struct TranscriptPartView: View {
    let part: OpenCodePart
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Binding var disclosureStates: [String: Bool]
    @Binding var patchDisclosureStates: [String: Bool]
    @Binding var shellOutputDisclosureStates: [String: Bool]

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
                isExpanded: binding(for: tool.id, defaultOpen: tool.defaultOpen),
                patchDisclosureStates: $patchDisclosureStates,
                shellOutputDisclosureStates: $shellOutputDisclosureStates
            )
        default:
            Text(part.summary)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func binding(for key: String, defaultOpen: Bool) -> Binding<Bool> {
        Binding(
            get: { disclosureStates[key] ?? defaultOpen },
            set: { disclosureStates[key] = $0 }
        )
    }
}

private struct ContextToolGroupView: View {
    let id: String
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

private struct ToolPartView: View {
    let tool: OpenCodePart.Tool
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Binding var isExpanded: Bool
    @Binding var patchDisclosureStates: [String: Bool]
    @Binding var shellOutputDisclosureStates: [String: Bool]

    var body: some View {
        if tool.isError, let error = tool.state.error, !error.isEmpty {
            ToolErrorCard(title: tool.titleLabel, message: error)
        } else {
            switch tool.tool {
            case "bash":
                shellTool
            case "read":
                readTool
            case "list", "glob", "grep":
                searchableTool
            case "webfetch":
                webfetchTool
            case "websearch", "codesearch":
                webSearchTool
            case "edit":
                editTool
            case "write":
                writeTool
            case "apply_patch":
                patchTool
            case "task":
                taskTool
            case "question":
                questionTool
            case "skill":
                compactTool(icon: "brain")
            default:
                genericTool
            }
        }
    }

    private var shellTool: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: tool.shellTranscript?.isEmpty == false,
            header: {
                ToolHeaderSummary(
                    title: "Shell",
                    subtitle: tool.shellDescription.map(ToolSubtitle.text),
                    badges: [],
                    status: tool.displayStatus,
                    isRunning: tool.isPendingOrRunning,
                    icon: "terminal"
                )
            },
            content: {
                if let transcript = tool.shellTranscript, !transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Spacer(minLength: 0)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(transcript, forType: .string)
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                        }

                        ShellTranscriptBlock(
                            tool: tool,
                            isExpanded: shellOutputBinding(for: tool.id)
                        )
                    }
                }
            }
        )
    }

    private var readTool: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactTool(
                icon: "eyeglasses",
                titleOverride: "Read",
                subtitleOverride: .text(TranscriptPathFormatter.displayPath(tool.filePath, worktreeRoot: worktreeRoot)),
                badgesOverride: tool.argBadges
            )

            if !tool.readLoadedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tool.readLoadedFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Loaded \(TranscriptPathFormatter.displayPath(file, worktreeRoot: worktreeRoot))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.leading, 12)
            }
        }
    }

    private var searchableTool: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: tool.state.output?.isEmpty == false,
            header: {
                ToolHeaderSummary(
                    title: tool.titleLabel,
                    subtitle: searchableSubtitle,
                    badges: searchableBadges,
                    status: tool.displayStatus,
                    isRunning: tool.isPendingOrRunning,
                    icon: searchableIcon
                )
            },
            content: {
                if let output = tool.state.output, !output.isEmpty {
                    MarkdownOutputBlock(text: output)
                }
            }
        )
    }

    private var webfetchTool: some View {
        compactTool(
            icon: "safari",
            titleOverride: "Webfetch",
            subtitleOverride: tool.subtitleText.map(ToolSubtitle.link),
            badgesOverride: []
        )
    }

    private var webSearchTool: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: tool.state.output?.isEmpty == false,
            header: {
                ToolHeaderSummary(
                    title: tool.titleLabel,
                    subtitle: tool.subtitleText.map(ToolSubtitle.text),
                    badges: titleCountBadges,
                    status: tool.displayStatus,
                    isRunning: tool.isPendingOrRunning,
                    icon: "magnifyingglass"
                )
            },
            content: {
                if let output = tool.state.output, !output.isEmpty {
                    MarkdownOutputBlock(text: output)
                }
            }
        )
    }

    private var editTool: some View {
        FileToolCard(
            title: "Edit",
            filePath: tool.fileDiff?.file ?? tool.filePath,
            worktreeRoot: worktreeRoot,
            status: tool.displayStatus,
            isRunning: tool.isPendingOrRunning,
            isExpanded: $isExpanded
        ) {
            if let fileDiff = tool.fileDiff {
                FileDiffBlock(fileDiff: fileDiff)
                DiagnosticsBlock(diagnostics: tool.diagnostics(for: fileDiff.file))
            } else if let transcript = tool.shellTranscript {
                MonospaceBlock(text: transcript)
            }
        }
    }

    private var writeTool: some View {
        FileToolCard(
            title: "Write",
            filePath: tool.filePath,
            worktreeRoot: worktreeRoot,
            status: tool.displayStatus,
            isRunning: tool.isPendingOrRunning,
            isExpanded: $isExpanded
        ) {
            if let content = tool.inputValues["content"]?.stringValue, !content.isEmpty {
                MonospaceBlock(text: content)
            }
            DiagnosticsBlock(diagnostics: tool.diagnostics(for: tool.filePath))
        }
    }

    private var patchTool: some View {
        let patchFiles = tool.patchFiles
        let titlePath = patchFiles.count == 1 ? patchFiles.first?.relativePath : nil

        return FileToolCard(
            title: "Patch",
            filePath: titlePath,
            worktreeRoot: worktreeRoot,
            status: tool.displayStatus,
            isRunning: tool.isPendingOrRunning,
            isExpanded: $isExpanded,
            trailingSummary: patchFiles.count > 1 ? "\(patchFiles.count) files" : nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if patchFiles.count == 1, let file = patchFiles.first {
                    PatchFileDetails(file: file, diagnostics: tool.diagnostics(for: file.movePath ?? file.filePath))
                } else {
                    ForEach(patchFiles, id: \.filePath) { file in
                        PatchFileRow(
                            toolID: tool.id,
                            file: file,
                            worktreeRoot: worktreeRoot,
                            diagnostics: tool.diagnostics(for: file.movePath ?? file.filePath),
                            isExpanded: patchBinding(for: file.filePath, defaultOpen: file.type != "delete")
                        )
                    }
                }
            }
        }
    }

    private var taskTool: some View {
        let target = tool.childSessionID.flatMap(resolveTaskTarget)
        let subtitle: ToolSubtitle?
        if let description = tool.subtitleText, !description.isEmpty {
            if let target {
                subtitle = .action(description) { navigateToSession(target) }
            } else {
                subtitle = .text(description)
            }
        } else {
            subtitle = nil
        }

        return compactTool(
            icon: "point.3.connected.trianglepath.dotted",
            titleOverride: tool.titleLabel,
            subtitleOverride: subtitle,
            badgesOverride: []
        )
    }

    private var questionTool: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: !tool.questionAnswers.isEmpty,
            header: {
                ToolHeaderSummary(
                    title: "Questions",
                    subtitle: .text(questionSubtitle),
                    badges: [],
                    status: tool.displayStatus,
                    isRunning: tool.isPendingOrRunning,
                    icon: "bubble.left.and.text.bubble.right"
                )
            },
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    let questions = tool.inputValues["questions"]?.decoded(as: [OpenCodeQuestionRequest.Question].self) ?? []
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.question)
                                .font(.callout.weight(.medium))
                            Text(answerText(for: index))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        )
    }

    private var genericTool: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: tool.state.output?.isEmpty == false,
            header: {
                ToolHeaderSummary(
                    title: tool.titleLabel,
                    subtitle: tool.subtitleText.map(ToolSubtitle.text),
                    badges: tool.argBadges,
                    status: tool.displayStatus,
                    isRunning: tool.isPendingOrRunning,
                    icon: "wrench.adjustable"
                )
            },
            content: {
                if let output = tool.state.output, !output.isEmpty {
                    MarkdownOutputBlock(text: output)
                }
            }
        )
    }

    private func compactTool(
        icon: String,
        titleOverride: String? = nil,
        subtitleOverride: ToolSubtitle? = nil,
        badgesOverride: [String] = []
    ) -> some View {
        ExpandableToolCard(
            isExpanded: .constant(false),
            expandable: false,
            header: {
                ToolHeaderSummary(
                    title: titleOverride ?? tool.titleLabel,
                    subtitle: subtitleOverride ?? tool.subtitleText.map(ToolSubtitle.text),
                    badges: badgesOverride,
                    status: tool.displayStatus,
                    isRunning: tool.isPendingOrRunning,
                    icon: icon
                )
            },
            content: {
                EmptyView()
            }
        )
    }

    private var searchableSubtitle: ToolSubtitle? {
        switch tool.tool {
        case "list":
            let directory = TranscriptPathFormatter.directory(tool.inputValues["path"]?.stringValue, worktreeRoot: worktreeRoot)
            return directory.isEmpty ? nil : .text(directory)
        case "glob", "grep":
            let directory = TranscriptPathFormatter.directory(tool.inputValues["path"]?.stringValue, worktreeRoot: worktreeRoot)
            return directory.isEmpty ? nil : .text(directory)
        default:
            return tool.subtitleText.map(ToolSubtitle.text)
        }
    }

    private var searchableBadges: [String] {
        tool.argBadges + titleCountBadges
    }

    private var titleCountBadges: [String] {
        guard let count = tool.titleBadgeCount else { return [] }
        switch tool.tool {
        case "grep":
            return ["\(count) matches"]
        case "list", "glob":
            return ["\(count) items"]
        default:
            return ["\(count)"]
        }
    }

    private var searchableIcon: String {
        switch tool.tool {
        case "list":
            return "list.bullet"
        default:
            return "magnifyingglass"
        }
    }

    private var questionSubtitle: String {
        let count = tool.questionAnswers.count
        if count > 0 {
            return count == 1 ? "1 answered" : "\(count) answered"
        }

        let questions = tool.inputValues["questions"]?.arrayValue?.count ?? 0
        if questions == 0 {
            return "Questions"
        }
        return questions == 1 ? "1 question" : "\(questions) questions"
    }

    private func answerText(for index: Int) -> String {
        let answers = tool.questionAnswers
        guard answers.indices.contains(index) else { return "No answer" }
        let value = answers[index].joined(separator: ", ")
        return value.isEmpty ? "No answer" : value
    }

    private func patchBinding(for filePath: String, defaultOpen: Bool) -> Binding<Bool> {
        let key = "\(tool.id)::\(filePath)"
        return Binding(
            get: { patchDisclosureStates[key] ?? defaultOpen },
            set: { patchDisclosureStates[key] = $0 }
        )
    }

    private func shellOutputBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { shellOutputDisclosureStates[key] ?? false },
            set: { shellOutputDisclosureStates[key] = $0 }
        )
    }
}

private enum ToolSubtitle {
    case text(String)
    case link(String)
    case action(String, () -> Void)
}

private struct ExpandableToolCard<Header: View, Content: View>: View {
    @Binding var isExpanded: Bool
    let expandable: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if expandable {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        header
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    content
                }
            } else {
                header
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ToolHeaderSummary: View {
    let title: String
    let subtitle: ToolSubtitle?
    let badges: [String]
    let status: String
    let isRunning: Bool
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isRunning ? Color.accentColor : Color.secondary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))

                    ToolStatusPill(text: status, isRunning: isRunning)
                }

                if let subtitle {
                    subtitleView(subtitle)
                }

                if !badges.isEmpty {
                    ToolBadges(badges: badges)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func subtitleView(_ subtitle: ToolSubtitle) -> some View {
        switch subtitle {
        case .text(let value):
            if !value.isEmpty {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .link(let value):
            if let url = URL(string: value), !value.isEmpty {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(value)
                            .font(.caption)
                            .underline()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        case .action(let value, let action):
            if !value.isEmpty {
                Button(action: action) {
                    Text(value)
                        .font(.caption)
                        .underline()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ToolStatusPill: View {
    let text: String
    let isRunning: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isRunning ? Color.accentColor : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((isRunning ? Color.accentColor : Color.secondary).opacity(0.12), in: Capsule())
    }
}

private struct ToolBadges: View {
    let badges: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownOutputBlock: View {
    let text: String

    var body: some View {
        MarkdownText(text: text)
            .equatable()
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MonospaceBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(verbatim: text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: true, vertical: true)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ShellTranscriptBlock: View {
    let tool: OpenCodePart.Tool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let transcript = displayedTranscript {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(verbatim: transcript)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: maxHeight)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if tool.shellHasHiddenOutput, !tool.isPendingOrRunning {
                Button(isExpanded ? "Show less" : expandLabel) {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayedTranscript: String? {
        if isExpanded || tool.isPendingOrRunning {
            return tool.shellTranscript
        }
        return tool.shellPreviewTranscript
    }

    private var expandLabel: String {
        let lineCount = tool.shellOutputLineCount
        let noun = lineCount == 1 ? "line" : "lines"
        return "Show all \(lineCount) \(noun)"
    }

    private var maxHeight: CGFloat? {
        if isExpanded || tool.isPendingOrRunning {
            return 360
        }
        return 220
    }
}

private struct ToolErrorCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message.replacingOccurrences(of: "Error: ", with: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct FileToolCard<Content: View>: View {
    let title: String
    let filePath: String?
    let worktreeRoot: String?
    let status: String
    let isRunning: Bool
    @Binding var isExpanded: Bool
    var trailingSummary: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: true,
            header: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isRunning ? Color.accentColor : Color.secondary)
                        .frame(width: 16)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(title)
                                .font(.callout.weight(.semibold))

                            if let filePath, !TranscriptPathFormatter.filename(filePath).isEmpty {
                                Text(TranscriptPathFormatter.filename(filePath))
                                    .font(.callout)
                            }

                            ToolStatusPill(text: status, isRunning: isRunning)
                        }

                        if let directory = filePath.map({ TranscriptPathFormatter.directory($0, worktreeRoot: worktreeRoot) }),
                           !directory.isEmpty {
                            Text(directory)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let trailingSummary, !trailingSummary.isEmpty {
                            ToolBadges(badges: [trailingSummary])
                        }
                    }
                }
            },
            content: {
                content
            }
        )
    }
}

private struct FileDiffBlock: View {
    let fileDiff: ToolFileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !fileDiff.before.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MonospaceBlock(text: fileDiff.before)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("After")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                MonospaceBlock(text: fileDiff.after)
            }

            ToolBadges(badges: ["+\(fileDiff.additions)", "-\(fileDiff.deletions)"])
        }
    }
}

private struct DiagnosticsBlock: View {
    let diagnostics: [ToolDiagnostic]

    var body: some View {
        if !diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(diagnostics.prefix(3).enumerated()), id: \.offset) { _, diagnostic in
                    HStack(alignment: .top, spacing: 8) {
                        Text("Error")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.1), in: Capsule())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(diagnostic.range.start.line + 1):\(diagnostic.range.start.character + 1)]")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(diagnostic.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

private struct PatchFileRow: View {
    let toolID: String
    let file: ToolPatchFile
    let worktreeRoot: String?
    let diagnostics: [ToolDiagnostic]
    @Binding var isExpanded: Bool

    var body: some View {
        ExpandableToolCard(
            isExpanded: $isExpanded,
            expandable: true,
            header: {
                ToolHeaderSummary(
                    title: patchActionTitle,
                    subtitle: .text(TranscriptPathFormatter.displayPath(file.movePath ?? file.relativePath, worktreeRoot: worktreeRoot)),
                    badges: ["+\(file.additions)", "-\(file.deletions)"],
                    status: "Done",
                    isRunning: false,
                    icon: "doc.text"
                )
            },
            content: {
                PatchFileDetails(file: file, diagnostics: diagnostics)
            }
        )
    }

    private var patchActionTitle: String {
        switch file.type {
        case "add":
            return "Created"
        case "delete":
            return "Deleted"
        case "move":
            return "Moved"
        default:
            return "Patched"
        }
    }
}

private struct PatchFileDetails: View {
    let file: ToolPatchFile
    let diagnostics: [ToolDiagnostic]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !file.before.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MonospaceBlock(text: file.before)
                }
            }

            if !file.after.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("After")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MonospaceBlock(text: file.after)
                }
            }

            DiagnosticsBlock(diagnostics: diagnostics)
        }
    }
}
