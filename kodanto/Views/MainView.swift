import AppKit
import SwiftUI

struct MainView: View {
    @Bindable var model: KodantoAppModel
    @State private var editingProfile: ServerProfile?
    @State private var expandedProjectIDs: Set<OpenCodeProject.ID> = []
    @State private var promptEditorHeight: CGFloat = 0
    @State private var composerOverlayHeight: CGFloat = 0

    private static let composerHorizontalPadding: CGFloat = 8
    private static let composerVerticalPadding: CGFloat = 6
    private static let composerNSFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let messageColumnMaxWidth: CGFloat = 760
    private static let composerMaxWidth: CGFloat = 900

    private var promptLineHeight: CGFloat {
        Self.composerNSFont.ascender - Self.composerNSFont.descender + Self.composerNSFont.leading
    }

    private var promptMinimumHeight: CGFloat {
        ceil(promptLineHeight + (Self.composerVerticalPadding * 2))
    }

    private var composerScrollClearance: CGFloat {
        composerOverlayHeight + 88
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPanel
        }
        .sheet(isPresented: $model.showingDiagnostics) {
            DiagnosticsSheet(model: model)
        }
        .sheet(isPresented: $model.showingConnectionSheet) {
            ConnectionSheet(existingProfile: editingProfile) { profile in
                model.saveProfile(profile)
                editingProfile = nil
            }
        }
        .task {
            if case .idle = model.connectionState {
                await model.connectSelectedProfile()
            }
        }
        .task(id: model.selectedProjectID) {
            guard let selectedProjectID = model.selectedProjectID else { return }
            expandedProjectIDs.insert(selectedProjectID)
        }
    }

    private var sidebar: some View {
        List {
            Section("Servers") {
                ForEach(model.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name)
                            Text(profile.normalizedBaseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.selectedProfileID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectProfile(profile.id)
                    }
                    .contextMenu {
                        Button("Edit") {
                            editingProfile = profile
                            model.showingConnectionSheet = true
                        }
                        Button("Delete", role: .destructive) {
                            model.deleteProfile(profile)
                        }
                        .disabled(model.profiles.count == 1)
                    }
                }

                Button {
                    editingProfile = nil
                    model.showingConnectionSheet = true
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }
            }

            Section("Projects") {
                ForEach(model.projects) { project in
                    projectSection(for: project)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                connectionStatus
                HStack {
                    Button("Connect") {
                        model.connect()
                    }
                    Button("Refresh") {
                        model.refresh()
                    }
                    if model.isLiveSyncActive {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("kodanto")
    }

    private func projectSection(for project: OpenCodeProject) -> some View {
        let isExpanded = expandedProjectIDs.contains(project.id)
        let sessions = model.sessions(for: project)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    toggleProjectExpansion(for: project)
                } label: {
                    ProjectSidebarRow(
                        project: project,
                        isExpanded: isExpanded,
                        isActive: model.selectedProjectID == project.id
                    )
                }
                .buttonStyle(.plain)

                if model.isLoadingSessions(for: project) {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    expandedProjectIDs.insert(project.id)
                    model.createSession(in: project.id)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("New Session")
                .disabled(model.selectedProfile == nil)
            }

            if isExpanded {
                if model.isLoadingSessions(for: project), sessions.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                    Text("Loading sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 28)
                    .padding(.vertical, 4)
                } else if model.hasLoadedSessions(for: project), sessions.isEmpty {
                    Text("No sessions yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                        .padding(.vertical, 4)
                } else {
                    ForEach(sessions) { session in
                        Button {
                            model.selectSession(session.id, in: project.id)
                        } label: {
                            SessionSidebarRow(
                                session: session,
                                status: model.sessionStatus(for: session, in: project),
                                isSelected: model.selectedSessionID == session.id
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 24)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func toggleProjectExpansion(for project: OpenCodeProject) {
        let shouldExpand = !expandedProjectIDs.contains(project.id)
        withAnimation(.easeInOut(duration: 0.16)) {
            if shouldExpand {
                expandedProjectIDs.insert(project.id)
            } else {
                expandedProjectIDs.remove(project.id)
            }
        }

        if shouldExpand {
            model.loadSessionsIfNeeded(for: project)
        }
    }

    private var detailPanel: some View {
        GeometryReader { geometry in
            let composerMaxHeight = max(promptMinimumHeight, geometry.size.height * 0.3)

            VStack(spacing: 0) {
                if let session = model.selectedSession {
                    header(for: session)
                    Divider()
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(model.selectedSessionMessages) { envelope in
                                    MessageCard(envelope: envelope)
                                }

                                if !model.sessionTodos.isEmpty {
                                    InspectorSection(title: "Todos") {
                                        ForEach(Array(model.sessionTodos.enumerated()), id: \.offset) { _, todo in
                                            HStack {
                                                Text(todo.content)
                                                Spacer()
                                                Text(todo.status)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }

                                if !model.permissions.isEmpty {
                                    InspectorSection(title: "Permissions") {
                                        ForEach(model.permissions) { request in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(request.permission)
                                                    .font(.headline)
                                                Text(request.patterns.joined(separator: ", "))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                HStack {
                                                    Button("Allow Once") {
                                                        model.respondToPermission(request, reply: "once")
                                                    }
                                                    Button("Always") {
                                                        model.respondToPermission(request, reply: "always")
                                                    }
                                                    Button("Reject", role: .destructive) {
                                                        model.respondToPermission(request, reply: "reject")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                if !model.questions.isEmpty {
                                    InspectorSection(title: "Questions") {
                                        ForEach(model.questions) { request in
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(request.questions.first?.question ?? "Question")
                                                    .font(.headline)
                                                if let options = request.questions.first?.options, !options.isEmpty {
                                                    ForEach(options) { option in
                                                        Button(option.label) {
                                                            model.answerQuestion(request, answers: [[option.label]])
                                                        }
                                                    }
                                                }
                                                Button("Reject", role: .destructive) {
                                                    model.rejectQuestion(request)
                                                }
                                            }
                                        }
                                    }
                                }

                                Color.clear
                                    .frame(height: composerScrollClearance)
                            }
                            .padding()
                            .frame(maxWidth: Self.messageColumnMaxWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        composer(maxHeight: composerMaxHeight)
                            .frame(maxWidth: Self.composerMaxWidth)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(key: ComposerOverlayHeightPreferenceKey.self, value: proxy.size.height)
                                }
                            }
                            .zIndex(1)
                    }
                    .onPreferenceChange(ComposerOverlayHeightPreferenceKey.self) { height in
                        composerOverlayHeight = height
                    }
                } else {
                    ContentUnavailableView("Select a session", systemImage: "bubble.left.and.text.bubble.right")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func composer(maxHeight: CGFloat) -> some View {
        let resolvedPromptHeight = min(max(promptEditorHeight, promptMinimumHeight), maxHeight)

        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                AutoSizingPromptEditor(
                    text: $model.draftPrompt,
                    measuredHeight: $promptEditorHeight,
                    font: Self.composerNSFont,
                    textInset: NSSize(width: Self.composerHorizontalPadding, height: Self.composerVerticalPadding)
                ) {
                    guard model.canSendPrompt else { return }
                    model.sendPrompt()
                }
                .frame(height: resolvedPromptHeight)

                if model.draftPrompt.isEmpty {
                    Text("Write a prompt...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Self.composerHorizontalPadding)
                        .padding(.vertical, Self.composerVerticalPadding)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: resolvedPromptHeight, alignment: .topLeading)

            Button {
                model.sendPrompt()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.canSendPrompt)
            .help("Send")
        }
        .padding(14)
        .animation(.easeInOut(duration: 0.16), value: resolvedPromptHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }

    private func header(for session: OpenCodeSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title)
                .font(.title2.weight(.semibold))
            Text(session.directory)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(model.sessionStatuses[session.id]?.label ?? "Unknown", systemImage: "bolt.horizontal.circle")
                if let shareURL = session.share?.url {
                    Label(shareURL, systemImage: "link")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
    }

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch model.connectionState {
            case .idle:
                Text("Not connected")
            case .connecting:
                Label("Connecting...", systemImage: "bolt.horizontal.circle")
            case .connected(let version):
                Label("Connected to opencode \(version)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }
}

private struct ComposerOverlayHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DiagnosticsSheet: View {
    @Bindable var model: KodantoAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let diagnostics = model.diagnostics

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Diagnostics")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            Form {
                LabeledContent("Server URL", value: diagnostics.serverURL)
                LabeledContent("Binary", value: diagnostics.binaryPath)
                LabeledContent("Live Sync", value: diagnostics.liveSyncState)
                LabeledContent("Reconnects", value: "\(diagnostics.reconnectCount)")
                LabeledContent("Last Event", value: diagnostics.lastEventDescription)
                LabeledContent("Cached Projects", value: "\(diagnostics.cachedProjects)")
                LabeledContent("Cached Sessions", value: "\(diagnostics.cachedSessions)")
                LabeledContent("Selected Directory", value: diagnostics.selectedProjectDirectory ?? "None")
                LabeledContent("Last Error", value: diagnostics.lastError ?? "None")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sidecar Log")
                        .font(.headline)
                    ScrollView {
                        Text(diagnostics.sidecarLog.isEmpty ? "No sidecar output yet." : diagnostics.sidecarLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 220)
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(width: 680, height: 620)
    }
}

private struct ProjectSidebarRow: View {
    let project: OpenCodeProject
    let isExpanded: Bool
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Text(project.worktree)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }

    private var backgroundColor: Color {
        isActive ? Color.accentColor.opacity(0.12) : Color.clear
    }
}

private struct SessionSidebarRow: View {
    let session: OpenCodeSession
    let status: OpenCodeSessionStatus?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(status?.label ?? "Idle")
                    Text(session.id)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9))
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .orange
        case .retry:
            return .yellow
        default:
            return .green
        }
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.05)
    }
}

private struct MessageCard: View {
    let envelope: OpenCodeMessageEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(envelope.info.roleLabel)
                .font(.headline)

            ForEach(envelope.parts) { part in
                switch part {
                case .text(let value):
                    Text(value.text)
                        .textSelection(.enabled)
                case .reasoning(let value):
                    Text(value.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                default:
                    Text(part.summary)
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
