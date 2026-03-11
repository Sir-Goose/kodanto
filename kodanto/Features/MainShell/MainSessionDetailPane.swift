import AppKit
import SwiftUI

struct MainSessionDetailPane: View {
    @Bindable var model: KodantoAppModel
    let splitViewVisibility: NavigationSplitViewVisibility

    @State private var promptEditorHeight: CGFloat = 0
    @State private var pendingInitialBottomSessionID: OpenCodeSession.ID?
    @State private var transcriptDisclosureStore = TranscriptDisclosureStore()

    private let transcriptScrollTarget = "transcript-bottom"

    private static let composerHorizontalPadding: CGFloat = 8
    private static let composerVerticalPadding: CGFloat = 6
    private static let composerNSFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
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

    var body: some View {
        GeometryReader { geometry in
            detailContent(for: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func detailContent(for availableHeight: CGFloat) -> some View {
        let composerMaxHeight = max(promptMinimumHeight, availableHeight * 0.3)

        if let session = model.selectedSession {
            selectedSessionView(session: session, composerMaxHeight: composerMaxHeight)
        } else {
            ContentUnavailableView("Select a session", systemImage: "bubble.left.and.text.bubble.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectedSessionView(session: OpenCodeSession, composerMaxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(for: session)
            Divider()

            VStack(spacing: 0) {
                transcriptPanel

                bottomPanel(maxHeight: composerMaxHeight)
                    .frame(maxWidth: Self.composerMaxWidth)
                    .padding(.horizontal, Self.composerOuterPadding)
                    .padding(.bottom, Self.composerOuterPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transcriptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    transcriptTurns
                    transcriptBottomAnchor
                }
                .padding()
                .frame(maxWidth: Self.messageColumnMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                pendingInitialBottomSessionID = model.selectedSessionID
                jumpTranscriptToBottom(using: proxy)
            }
            .onChange(of: model.selectedSessionID) { _, sessionID in
                pendingInitialBottomSessionID = sessionID
                transcriptDisclosureStore.reset()
                jumpTranscriptToBottom(using: proxy)
            }
            .onChange(of: model.selectedSessionTranscriptRevision) { _, _ in
                handleTranscriptChange(using: proxy)
            }
            .onChange(of: model.sessionTodos.count) { _, _ in
                handleTranscriptChange(using: proxy)
            }
            .onChange(of: model.permissions.count) { _, _ in
                handleTranscriptChange(using: proxy)
            }
            .onChange(of: model.questions.count) { _, _ in
                handleTranscriptChange(using: proxy)
            }
            .onChange(of: model.isSelectedSessionRunning) { _, isRunning in
                if isRunning {
                    scrollTranscriptToBottom(using: proxy)
                }
            }
        }
    }

    private var transcriptTurns: some View {
        ForEach(model.selectedSessionTurns) { turn in
            TranscriptTurnView(
                turn: turn,
                worktreeRoot: model.selectedProject?.worktree,
                resolveTaskTarget: { sessionID in
                    model.loadedSessionNavigationTarget(for: sessionID)
                },
                navigateToSession: { target in
                    model.selectSession(target.sessionID, in: target.projectID)
                },
                disclosureStore: transcriptDisclosureStore
            )
        }
    }

    private var transcriptBottomAnchor: some View {
        Color.clear
            .frame(height: 1)
            .id(transcriptScrollTarget)
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

                ComposerControlsRow(model: model)
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

    private func bottomPanel(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.composerContentGap) {
            SessionTodoDockView(todos: model.sessionTodos)
                .id(model.selectedSessionID ?? "session-todo-dock")

            if let request = model.activePermissionRequest {
                SessionPermissionDockView(model: model, request: request)
                    .id(request.id)
            } else if let request = model.activeQuestionRequest {
                SessionQuestionDockView(model: model, request: request)
                    .id(request.id)
            } else {
                composer(maxHeight: maxHeight)
            }
        }
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

    private func scrollTranscriptToBottomIfNeeded(using proxy: ScrollViewProxy) {
        guard model.isSelectedSessionRunning else { return }
        scrollTranscriptToBottom(using: proxy)
    }

    private func handleTranscriptChange(using proxy: ScrollViewProxy) {
        guard let selectedSessionID = model.selectedSessionID else { return }

        if pendingInitialBottomSessionID == selectedSessionID {
            jumpTranscriptToBottom(using: proxy)

            if transcriptHasVisibleContent {
                pendingInitialBottomSessionID = nil
            }
            return
        }

        scrollTranscriptToBottomIfNeeded(using: proxy)
    }

    private var transcriptHasVisibleContent: Bool {
        !model.selectedSessionMessages.isEmpty || !model.sessionTodos.isEmpty || !model.permissions.isEmpty || !model.questions.isEmpty
    }

    private func jumpTranscriptToBottom(using proxy: ScrollViewProxy) {
        let transaction = Transaction(animation: nil)

        DispatchQueue.main.async {
            withTransaction(transaction) {
                proxy.scrollTo(transcriptScrollTarget, anchor: .bottom)
            }
        }
    }

    private func scrollTranscriptToBottom(using proxy: ScrollViewProxy) {
        jumpTranscriptToBottom(using: proxy)
    }
}
