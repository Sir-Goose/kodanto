import AppKit
import SwiftUI

struct MainSessionDetailPane: View {
    @Bindable var model: KodantoAppModel
    let splitViewVisibility: NavigationSplitViewVisibility

    @State private var promptEditorHeight: CGFloat = 0
    @State private var transcriptDisclosureStore = TranscriptDisclosureStore()
    @State private var userScrolledUp = false
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var isSlashPopoverVisible = false
    @State private var slashQuery = ""

    private static let composerHorizontalPadding: CGFloat = 8
    private static let composerVerticalPadding: CGFloat = 6
    private static let composerNSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let messageColumnMaxWidth: CGFloat = 760
    private static let composerMaxWidth: CGFloat = 770
    private static let composerOuterPadding: CGFloat = 16
    private static let composerInnerPadding: CGFloat = 14
    private static let composerContentGap: CGFloat = 12
    private static let collapsedHeaderLeadingInset: CGFloat = 124

    private var promptLineHeight: CGFloat {
        Self.composerNSFont.ascender - Self.composerNSFont.descender + Self.composerNSFont.leading
    }

    private var promptMinimumHeight: CGFloat {
        ceil(promptLineHeight + (Self.composerVerticalPadding * 2))
    }

    private var selectedProject: OpenCodeProject? {
        model.workspaceStore.selectedProject
    }

    private var selectedSession: OpenCodeSession? {
        model.workspaceStore.selectedSession
    }

    private var selectedSessionID: OpenCodeSession.ID? {
        model.workspaceStore.selectedSessionID
    }

    private var selectedSessionMessages: [OpenCodeMessageEnvelope] {
        model.sessionDetailStore.selectedSessionMessages
    }

    private var selectedSessionTurns: [TranscriptTurn] {
        model.sessionDetailStore.selectedSessionTurns
    }

    private var sessionTodos: [OpenCodeTodo] {
        model.sessionDetailStore.sessionTodos
    }

    private var permissions: [OpenCodePermissionRequest] {
        model.sessionRequestStore.permissions
    }

    private var questions: [OpenCodeQuestionRequest] {
        model.sessionRequestStore.questions
    }

    private var activePermissionRequest: OpenCodePermissionRequest? {
        model.sessionRequestStore.activePermissionRequest
    }

    private var activeQuestionRequest: OpenCodeQuestionRequest? {
        model.sessionRequestStore.activeQuestionRequest
    }

    private var isSelectedSessionRunning: Bool {
        model.workspaceStore.isSelectedSessionRunning
    }

    var body: some View {
        GeometryReader { geometry in
            detailContent(for: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            model.ensureTerminalConnectedIfNeeded()
        }
        .onChange(of: selectedProject?.worktree) { _, _ in
            model.ensureTerminalConnectedIfNeeded()
            model.refreshModelCatalogForSelectedProject()
        }
        .onChange(of: model.isTerminalPanelOpen) { _, isOpen in
            if isOpen { model.ensureTerminalConnectedIfNeeded() }
        }
        .onChange(of: model.workspaceStore.selectedProjectID) { _, _ in
            model.composerStore.refreshPlaceholder()
        }
        .onChange(of: selectedSessionID) { _, _ in
            model.composerStore.refreshPlaceholder()
        }
    }

    @ViewBuilder
    private func detailContent(for availableHeight: CGFloat) -> some View {
        let composerMaxHeight = max(promptMinimumHeight, availableHeight * 0.3)

        if let session = selectedSession {
            selectedSessionView(
                session: session,
                composerMaxHeight: composerMaxHeight,
                availableHeight: availableHeight
            )
        } else if let project = selectedProject {
            newSessionView(
                project: project,
                composerMaxHeight: composerMaxHeight,
                availableHeight: availableHeight
            )
        } else {
            ContentUnavailableView("Select a session", systemImage: "bubble.left.and.text.bubble.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectedSessionView(
        session: OpenCodeSession,
        composerMaxHeight: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            header(for: session)
            Divider()

            VStack(spacing: 0) {
                transcriptPanel

                bottomPanel(maxHeight: composerMaxHeight)
                    .frame(maxWidth: Self.composerMaxWidth)
                    .padding(.horizontal, Self.composerOuterPadding)
                    .padding(.bottom, Self.composerOuterPadding)

                TerminalPanelView(model: model, availableHeight: availableHeight)
            }
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func newSessionView(
        project: OpenCodeProject,
        composerMaxHeight: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            newSessionHeader(for: project)
            Divider()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                composer(maxHeight: composerMaxHeight)
                    .frame(maxWidth: Self.composerMaxWidth)
                    .padding(.horizontal, Self.composerOuterPadding)
                    .padding(.bottom, Self.composerOuterPadding)

                TerminalPanelView(model: model, availableHeight: availableHeight)
            }
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transcriptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    transcriptTurns
                }
                .scrollTargetLayout()
                .id("transcript-\(selectedSessionID ?? "none")")
                .padding()
                .frame(maxWidth: Self.messageColumnMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height - geometry.visibleRect.maxY
                return distanceFromBottom < 50
            } action: { wasNearBottom, isNearBottom in
                if wasNearBottom && !isNearBottom {
                    userScrolledUp = true
                } else if isNearBottom {
                    userScrolledUp = false
                }
            }
            .onChange(of: selectedSessionID) { _, _ in
                userScrolledUp = false
                transcriptDisclosureStore.reset()
                scrollPosition.scrollTo(edge: .bottom)
            }
            .onChange(of: isSelectedSessionRunning) { _, isRunning in
                if isRunning && !userScrolledUp {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
        }
    }

    private var transcriptTurns: some View {
        let turns = selectedSessionTurns
        return ForEach(turns) { turn in
            TranscriptTurnView(
                turn: turn,
                worktreeRoot: selectedProject?.worktree,
                resolveTaskTarget: { sessionID in
                    model.loadedSessionNavigationTarget(for: sessionID)
                },
                navigateToSession: { target in
                    model.selectSession(target.sessionID, in: target.projectID)
                },
                disclosureStore: transcriptDisclosureStore,
                isThinking: isSelectedSessionRunning && turn.id == turns.last?.id
            )
        }
    }

    private var isNewChat: Bool {
        selectedSession == nil && selectedProject != nil
    }

    private var placeholderText: String {
        if isNewChat {
            return model.composerStore.currentPlaceholder
        } else {
            return "Ask anything..."
        }
    }

    private func composer(maxHeight: CGFloat) -> some View {
        let resolvedPromptHeight = min(max(promptEditorHeight, promptMinimumHeight), maxHeight)
        
        let filteredCommands: [SlashCommand] = {
            if slashQuery.isEmpty {
                return SlashCommand.builtinCommands
            }
            let lowercasedQuery = slashQuery.lowercased()
            return SlashCommand.builtinCommands.filter { command in
                command.trigger.lowercased().contains(lowercasedQuery) ||
                command.title.lowercased().contains(lowercasedQuery) ||
                (command.description?.lowercased().contains(lowercasedQuery) ?? false)
            }
        }()

        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    AutoSizingPromptEditor(
                        text: $model.draftPrompt,
                        measuredHeight: $promptEditorHeight,
                        font: Self.composerNSFont,
                        textInset: NSSize(width: Self.composerHorizontalPadding, height: Self.composerVerticalPadding),
                        maxHeight: maxHeight,
                        onSubmit: {
                            if isSlashPopoverVisible {
                                if let command = filteredCommands.first {
                                    model.executeSlashCommand(command)
                                    isSlashPopoverVisible = false
                                    slashQuery = ""
                                    model.draftPrompt = ""
                                }
                            } else {
                                guard model.canSendPrompt else { return }
                                model.sendPrompt()
                            }
                        },
                        onSlashCommand: { query in
                            slashQuery = query
                            isSlashPopoverVisible = true
                        },
                        onSlashCommandDismiss: {
                            isSlashPopoverVisible = false
                            slashQuery = ""
                        }
                    )
                    .frame(height: resolvedPromptHeight)
                    .onKeyPress(.escape) {
                        if isSlashPopoverVisible {
                            isSlashPopoverVisible = false
                            slashQuery = ""
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if isSlashPopoverVisible {
                            model.selectPreviousSlashCommand()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if isSlashPopoverVisible {
                            model.selectNextSlashCommand()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.tab) {
                        if isSlashPopoverVisible {
                            if let command = model.selectedSlashCommand {
                                model.executeSlashCommand(command)
                                isSlashPopoverVisible = false
                                slashQuery = ""
                                model.draftPrompt = ""
                            }
                            return .handled
                        }
                        return .ignored
                    }

                    if model.draftPrompt.isEmpty {
                        Text(placeholderText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Self.composerHorizontalPadding)
                            .padding(.vertical, Self.composerVerticalPadding)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: resolvedPromptHeight, alignment: .topLeading)

                HStack(alignment: .center, spacing: 12) {
                    ComposerControlsRow(model: model)

                    Button {
                        if isSelectedSessionRunning {
                            model.abortSession()
                        } else if isSlashPopoverVisible {
                            if let command = model.selectedSlashCommand {
                                model.executeSlashCommand(command)
                                isSlashPopoverVisible = false
                                slashQuery = ""
                                model.draftPrompt = ""
                            }
                        } else {
                            model.sendPrompt()
                        }
                    } label: {
                        Image(systemName: isSelectedSessionRunning ? "stop.fill" : "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .disabled(!isSelectedSessionRunning && !model.canSendPrompt && !isSlashPopoverVisible)
                    .help(isSelectedSessionRunning ? "Stop" : (isSlashPopoverVisible ? "Select Command" : "Send"))
                }
            }
            .padding(Self.composerInnerPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18))
            )
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
            
            if isSlashPopoverVisible {
                SlashCommandPopover(
                    commands: filteredCommands,
                    selectedIndex: model.composerStore.selectedSlashCommandIndex,
                    onSelect: { command in
                        model.executeSlashCommand(command)
                        isSlashPopoverVisible = false
                        slashQuery = ""
                        model.draftPrompt = ""
                    },
                    onHover: { index in
                        model.composerStore.selectedSlashCommandIndex = index
                    }
                )
                .frame(width: 350)
                .offset(y: -8)
                .onAppear {
                    model.composerStore.selectedSlashCommandIndex = 0
                }
            }
        }
    }

    private func bottomPanel(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.composerContentGap) {
            SessionTodoDockView(todos: sessionTodos)
                .id(selectedSessionID ?? "session-todo-dock")

            if let request = activePermissionRequest {
                SessionPermissionDockView(model: model, request: request)
                    .id(request.id)
            } else if let request = activeQuestionRequest {
                SessionQuestionDockView(model: model, request: request)
                    .id(request.id)
            } else {
                composer(maxHeight: maxHeight)
            }
        }
    }

    private func header(for session: OpenCodeSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let target = model.parentSessionTarget(for: session) {
                Button {
                    model.selectSession(target.sessionID, in: target.projectID)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Go to parent session")
                .padding(.top, 2)
            }

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .padding(.leading, splitViewVisibility == .detailOnly ? Self.collapsedHeaderLeadingInset : 0)
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.16), value: splitViewVisibility)
    }

    private func newSessionHeader(for project: OpenCodeProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New Session")
                .font(.title2.weight(.semibold))
            Text(project.worktree)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .padding(.leading, splitViewVisibility == .detailOnly ? Self.collapsedHeaderLeadingInset : 0)
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.16), value: splitViewVisibility)
    }
}
