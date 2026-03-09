import AppKit
import SwiftUI

struct MainView: View {
    @Bindable var model: KodantoAppModel
    @State private var editingProfile: ServerProfile?
    @State private var expandedProjectIDs: Set<OpenCodeProject.ID> = []
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var promptEditorHeight: CGFloat = 0
    @State private var showingConnectionPopover = false

    private let transcriptScrollTarget = "transcript-bottom"

    private static let composerHorizontalPadding: CGFloat = 8
    private static let composerVerticalPadding: CGFloat = 6
    private static let composerNSFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let messageColumnMaxWidth: CGFloat = 760
    private static let composerMaxWidth: CGFloat = 770
    static let composerModelRowHeight: CGFloat = 34

    private var promptLineHeight: CGFloat {
        Self.composerNSFont.ascender - Self.composerNSFont.descender + Self.composerNSFont.leading
    }

    private var promptMinimumHeight: CGFloat {
        ceil(promptLineHeight + (Self.composerVerticalPadding * 2))
    }

    private static let composerOuterPadding: CGFloat = 16
    private static let composerInnerPadding: CGFloat = 14
    private static let composerButtonSize: CGFloat = 34
    private static let composerContentGap: CGFloat = 12
    private static let collapsedHeaderLeadingInset: CGFloat = 124

    private var composerReservedHeight: CGFloat {
        max(max(promptEditorHeight, promptMinimumHeight), Self.composerButtonSize)
        + Self.composerModelRowHeight
        + (Self.composerInnerPadding * 2)
        + Self.composerOuterPadding
        + Self.composerContentGap
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
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
        .background {
            WindowTitlebarAccessory(content: connectionStatusButton)
                .frame(width: 0, height: 0)
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
                                indicator: model.sessionSidebarIndicator(for: session, in: project),
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
                        ScrollViewReader { proxy in
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
                                        .frame(height: composerReservedHeight)

                                    Color.clear
                                        .frame(height: 1)
                                        .id(transcriptScrollTarget)
                                }
                                .padding()
                                .frame(maxWidth: Self.messageColumnMaxWidth, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .defaultScrollAnchor(.bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .onChange(of: model.selectedSessionTranscriptRevision) { _, _ in
                                scrollTranscriptToBottomIfNeeded(using: proxy)
                            }
                            .onChange(of: model.sessionTodos.count) { _, _ in
                                scrollTranscriptToBottomIfNeeded(using: proxy)
                            }
                            .onChange(of: model.permissions.count) { _, _ in
                                scrollTranscriptToBottomIfNeeded(using: proxy)
                            }
                            .onChange(of: model.questions.count) { _, _ in
                                scrollTranscriptToBottomIfNeeded(using: proxy)
                            }
                            .onChange(of: model.isSelectedSessionRunning) { _, isRunning in
                                if isRunning {
                                    scrollTranscriptToBottom(using: proxy)
                                }
                            }
                        }

                        composer(maxHeight: composerMaxHeight)
                            .frame(maxWidth: Self.composerMaxWidth)
                            .padding(.horizontal, Self.composerOuterPadding)
                            .padding(.bottom, Self.composerOuterPadding)
                            .zIndex(1)
                    }
                } else {
                    ContentUnavailableView("Select a session", systemImage: "bubble.left.and.text.bubble.right")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var connectionStatusButton: some View {
        Button {
            showingConnectionPopover.toggle()
        } label: {
            Circle()
                .fill(connectionIndicatorColor)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                }
                .shadow(color: connectionIndicatorColor.opacity(0.35), radius: 3)
                .padding(.top, 10)
                .padding(.leading, 6)
                .padding(.bottom, 6)
                .padding(.trailing, 20)
        }
        .buttonStyle(.plain)
        .help(connectionToolbarHelp)
        .popover(isPresented: $showingConnectionPopover, arrowEdge: .top) {
            connectionPopover
        }
    }

    private var connectionPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(connectionStatusTitle, systemImage: connectionStatusSymbol)
            Label(liveSyncStatusTitle, systemImage: liveSyncStatusSymbol)

            Divider()

            if model.canConnect {
                Button(connectionActionTitle) {
                    showingConnectionPopover = false
                    model.connect()
                }
            }

            if model.canRefresh {
                Button("Refresh") {
                    showingConnectionPopover = false
                    model.refresh()
                }
            }

            Button("Diagnostics") {
                showingConnectionPopover = false
                model.showingDiagnostics = true
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
    }

    private func composer(maxHeight: CGFloat) -> some View {
        let resolvedPromptHeight = min(max(promptEditorHeight, promptMinimumHeight), maxHeight)

        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    AutoSizingPromptEditor(
                        text: $model.draftPrompt,
                        measuredHeight: $promptEditorHeight,
                        font: Self.composerNSFont,
                        textInset: NSSize(width: Self.composerHorizontalPadding, height: Self.composerVerticalPadding),
                        maxHeight: maxHeight
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

                ModelPickerRow(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

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
        .padding(Self.composerInnerPadding)
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
            if let shareURL = session.share?.url {
                Label(shareURL, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .padding(.leading, splitViewVisibility == .detailOnly ? Self.collapsedHeaderLeadingInset : 0)
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.16), value: splitViewVisibility)
    }

    private var connectionIndicatorColor: Color {
        switch model.connectionState {
        case .connected:
            switch _model.wrappedValue.liveSyncPhase {
            case .active:
                return .green
            case .connecting, .reconnecting:
                return .yellow
            case .inactive:
                return .yellow
            }
        case .connecting:
            return .yellow
        case .idle, .failed:
            return .red
        }
    }

    private var connectionStatusTitle: String {
        switch model.connectionState {
        case .idle:
            return "Not connected"
        case .connecting:
            return "Connecting..."
        case .connected(let version):
            return "Connected to opencode \(version)"
        case .failed(let message):
            return message
        }
    }

    private var connectionStatusSymbol: String {
        switch model.connectionState {
        case .idle:
            return "xmark.circle"
        case .connecting:
            return "bolt.horizontal.circle"
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var liveSyncStatusTitle: String {
        switch _model.wrappedValue.liveSyncPhase {
        case .inactive:
            return "Live sync inactive"
        case .connecting:
            return "Live sync connecting"
        case .active:
            return "Live sync active"
        case .reconnecting:
            return "Live sync reconnecting"
        }
    }

    private var liveSyncStatusSymbol: String {
        switch _model.wrappedValue.liveSyncPhase {
        case .inactive:
            return "pause.circle"
        case .connecting, .reconnecting:
            return "arrow.trianglehead.clockwise"
        case .active:
            return "dot.radiowaves.left.and.right"
        }
    }

    private var connectionToolbarHelp: String {
        "\(connectionStatusTitle). \(liveSyncStatusTitle)."
    }

    private var connectionActionTitle: String {
        switch model.connectionState {
        case .failed:
            return "Reconnect"
        default:
            return "Connect"
        }
    }

    private func scrollTranscriptToBottomIfNeeded(using proxy: ScrollViewProxy) {
        guard model.isSelectedSessionRunning else { return }
        scrollTranscriptToBottom(using: proxy)
    }

    private func scrollTranscriptToBottom(using proxy: ScrollViewProxy) {
        let action = {
            proxy.scrollTo(transcriptScrollTarget, anchor: .bottom)
        }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18), action)
        }
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
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)
                .padding(.top, 3)

            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text(project.displayName)
                .font(.body.weight(isActive ? .semibold : .regular))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.12)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

private struct SessionSidebarRow: View {
    let session: OpenCodeSession
    let indicator: SessionSidebarIndicatorState
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            SessionSidebarIndicator(indicator: indicator)

            Text(session.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

private struct SessionSidebarIndicator: View {
    let indicator: SessionSidebarIndicatorState
    @State private var isPulsing = false

    private static let slotWidth: CGFloat = 10
    private static let dotSize: CGFloat = 7
    private static let pulseSize: CGFloat = 12

    var body: some View {
        ZStack {
            switch indicator {
            case .none:
                Color.clear
                    .frame(width: Self.dotSize, height: Self.dotSize)
            case .running:
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(width: Self.pulseSize, height: Self.pulseSize)
                        .scaleEffect(isPulsing ? 1.15 : 0.7)
                        .opacity(isPulsing ? 0.1 : 0.5)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                }
            case .completedUnread:
                Circle()
                    .fill(.green)
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .frame(width: Self.slotWidth, height: Self.pulseSize)
        .onAppear {
            updatePulseState()
        }
        .onChange(of: indicator) { _, _ in
            updatePulseState()
        }
        .animation(
            .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
            value: isPulsing
        )
    }

    private func updatePulseState() {
        if indicator == .running {
            isPulsing = true
        } else {
            isPulsing = false
        }
    }
}

private struct MessageCard: View {
    let envelope: OpenCodeMessageEnvelope

    private var visibleParts: [OpenCodePart] {
        envelope.parts.filter(\.isVisibleInTranscript)
    }

    var body: some View {
        if !visibleParts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(envelope.info.roleLabel)
                    .font(.headline)

                ForEach(visibleParts) { part in
                    switch part {
                    case .text(let value):
                        MarkdownText(text: value.text)
                            .textSelection(.enabled)
                    case .reasoning(let value):
                        MarkdownText(text: value.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .tool(let value):
                        ToolCallCard(tool: value)
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
}

private struct ToolCallCard: View {
    let tool: OpenCodePart.Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tool.displayTitle)
                    .font(.callout.weight(.semibold))

                Text(tool.state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let command = tool.command, !command.isEmpty {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if let error = tool.state.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ModelPickerRow: View {
    @Bindable var model: KodantoAppModel
    @State private var isHovered = false
    @State private var isShowingPicker = false

    var body: some View {
        HStack(spacing: 10) {
            if model.isLoadingModels {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let selectedModel = model.selectedModel {
                Button {
                    isShowingPicker.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Text(selectedModel.modelName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(selectedModel.providerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background(modelPickerBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
                }
                .buttonStyle(.plain)
                .help(selectedModel.id)
                .accessibilityIdentifier("model-picker-button")
                .onHover { hovering in
                    isHovered = hovering
                }
                .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
                    ModelPickerPopover(
                        groups: model.availableModelGroups,
                        selectedModelID: selectedModel.id
                    ) { option in
                        model.selectModel(option.id)
                        isShowingPicker = false
                    }
                }
            } else if let modelLoadError = model.modelLoadError {
                Text(modelLoadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No models available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: MainView.composerModelRowHeight, alignment: .center)
    }

    private var modelPickerBackground: Color {
        if isShowingPicker {
            return Color.accentColor.opacity(0.12)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

private struct ModelPickerPopover: View {
    let groups: [OpenCodeModelProviderGroup]
    let selectedModelID: String
    let onSelect: (OpenCodeModelOption) -> Void

    @State private var expandedProviderID: String?

    init(
        groups: [OpenCodeModelProviderGroup],
        selectedModelID: String,
        onSelect: @escaping (OpenCodeModelOption) -> Void
    ) {
        self.groups = groups
        self.selectedModelID = selectedModelID
        self.onSelect = onSelect
        _expandedProviderID = State(initialValue: groups.first(where: { group in
            group.models.contains(where: { $0.id == selectedModelID })
        })?.id ?? groups.first?.id)
    }

    private var selectedProviderID: String? {
        groups.first(where: { group in
            group.models.contains(where: { $0.id == selectedModelID })
        })?.id
    }

    private var idealHeight: CGFloat {
        let visibleModelCount = groups.first(where: { $0.id == expandedProviderID })?.models.count ?? 0
        let estimatedHeight = CGFloat(groups.count * 36) + CGFloat(visibleModelCount * 34) + 32
        return min(max(estimatedHeight, 120), 320)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                if expandedProviderID == group.id {
                                    expandedProviderID = nil
                                } else {
                                    expandedProviderID = group.id
                                }
                            }
                        } label: {
                            ModelPickerProviderRow(
                                group: group,
                                isExpanded: expandedProviderID == group.id,
                                isSelected: selectedProviderID == group.id
                            )
                        }
                        .buttonStyle(.plain)

                        if expandedProviderID == group.id {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.models) { option in
                                    Button {
                                        onSelect(option)
                                    } label: {
                                        ModelPickerOptionRow(
                                            option: option,
                                            isSelected: option.id == selectedModelID
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 18)
                            .transition(.opacity)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300, height: idealHeight)
        .accessibilityIdentifier("model-picker-popover")
    }
}

private struct ModelPickerProviderRow: View {
    let group: OpenCodeModelProviderGroup
    let isExpanded: Bool
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)

            Text(group.providerName)
                .font(.callout.weight(isSelected ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

private struct ModelPickerOptionRow: View {
    let option: OpenCodeModelOption
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(option.modelName)
                .font(.callout.weight(isSelected ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
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
