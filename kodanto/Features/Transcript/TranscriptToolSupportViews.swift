import AppKit
import SwiftUI

enum ToolSubtitle {
    case text(String)
    case link(String)
    case action(String, () -> Void)
}

struct ExpandableToolCard<Header: View, Content: View>: View {
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

struct ToolHeaderSummary: View {
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

struct ToolStatusPill: View {
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

struct ToolBadges: View {
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

struct MarkdownOutputBlock: View {
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

struct MonospaceBlock: View {
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

struct ShellTranscriptBlock: View {
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

struct ToolErrorCard: View {
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

struct FileToolCard<Content: View>: View {
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

struct FileDiffBlock: View {
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

struct DiagnosticsBlock: View {
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

struct PatchFileRow: View {
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

struct PatchFileDetails: View {
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
