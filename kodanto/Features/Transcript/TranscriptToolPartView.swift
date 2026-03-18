import Observation
import SwiftUI

struct ToolPartView: View {
    let tool: OpenCodePart.Tool
    let worktreeRoot: String?
    let resolveTaskTarget: (String) -> KodantoAppModel.SessionNavigationTarget?
    let navigateToSession: (KodantoAppModel.SessionNavigationTarget) -> Void
    @Bindable var disclosureStore: TranscriptDisclosureStore

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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen),
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
                            isExpanded: disclosureStore.binding(for: .shellOutput(tool.id), defaultOpen: false)
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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen),
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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen),
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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen)
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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen)
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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen),
            trailingSummary: patchFiles.count > 1 ? "\(patchFiles.count) files" : nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if patchFiles.count == 1, let file = patchFiles.first {
                    PatchFileDetails(file: file, diagnostics: tool.diagnostics(for: file.movePath ?? file.filePath))
                } else {
                    ForEach(patchFiles, id: \.filePath) { file in
                        PatchFileRow(
                            file: file,
                            worktreeRoot: worktreeRoot,
                            diagnostics: tool.diagnostics(for: file.movePath ?? file.filePath),
                            isExpanded: disclosureStore.binding(
                                for: .patchFile(toolID: tool.id, filePath: file.filePath),
                                defaultOpen: file.type != "delete"
                            )
                        )
                    }
                }
            }
        }
    }

    private var taskTool: some View {
        let subtitle: ToolSubtitle?
        if let description = tool.subtitleText, !description.isEmpty, let childSessionID = tool.childSessionID {
            subtitle = .action(description) { [resolveTaskTarget, navigateToSession] in
                if let target = resolveTaskTarget(childSessionID) {
                    navigateToSession(target)
                }
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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen),
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
            isExpanded: disclosureStore.binding(for: .tool(tool.id), defaultOpen: tool.defaultOpen),
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
}
