import AppKit
import SwiftUI

struct MainSessionDetailPane: View {
    @Bindable var model: KodantoAppModel
    let splitViewVisibility: NavigationSplitViewVisibility

    @State private var promptEditorHeight: CGFloat = 0
    @State private var transcriptDisclosureStore = TranscriptDisclosureStore()

    private static let composerHorizontalPadding: CGFloat = 8
    private static let composerVerticalPadding: CGFloat = 6
    private static let composerNSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    private static let messageColumnMaxWidth: CGFloat = 760
    private static let composerMaxWidth: CGFloat = 770
    private static let composerOuterPadding: CGFloat = 16
    private static let composerInnerPadding: CGFloat = 14
    private static let composerContentGap: CGFloat = 12
    private static let transcriptBottomClearance: CGFloat = composerOuterPadding + 12
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

    private var transcriptHasVisibleContent: Bool {
        !selectedSessionTurns.isEmpty || !sessionTodos.isEmpty || !permissions.isEmpty || !questions.isEmpty
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
        }
        .onChange(of: model.isTerminalPanelOpen) { _, isOpen in
            if isOpen {
                model.ensureTerminalConnectedIfNeeded()
            }
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
        TranscriptScrollContainer(
            sessionID: selectedSessionID,
            isRunning: isSelectedSessionRunning,
            hasVisibleContent: transcriptHasVisibleContent
        ) {
            transcriptDocumentContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: selectedSessionID) { _, _ in
            transcriptDisclosureStore.reset()
        }
    }

    private var transcriptDocumentContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            transcriptTurns
            Color.clear
                .frame(height: Self.transcriptBottomClearance)
        }
        .padding()
        .frame(maxWidth: Self.messageColumnMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var transcriptTurns: some View {
        ForEach(selectedSessionTurns) { turn in
            TranscriptTurnView(
                turn: turn,
                worktreeRoot: selectedProject?.worktree,
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

    private func composer(maxHeight: CGFloat) -> some View {
        let resolvedPromptHeight = min(max(promptEditorHeight, promptMinimumHeight), maxHeight)

        return VStack(alignment: .leading, spacing: 10) {
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
                    model.sendPrompt()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .disabled(!model.canSendPrompt)
                .help("Send")
            }
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

private struct TranscriptScrollContainer<Content: View>: NSViewRepresentable {
    let sessionID: OpenCodeSession.ID?
    let isRunning: Bool
    let hasVisibleContent: Bool
    let content: Content

    init(
        sessionID: OpenCodeSession.ID?,
        isRunning: Bool,
        hasVisibleContent: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.sessionID = sessionID
        self.isRunning = isRunning
        self.hasVisibleContent = hasVisibleContent
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TranscriptScrollContainerView {
        let view = TranscriptScrollContainerView()
        context.coordinator.install(in: view)
        return view
    }

    func updateNSView(_ nsView: TranscriptScrollContainerView, context: Context) {
        context.coordinator.update(
            in: nsView,
            sessionID: sessionID,
            isRunning: isRunning,
            hasVisibleContent: hasVisibleContent,
            content: AnyView(content)
        )
    }

    static func dismantleNSView(_ nsView: TranscriptScrollContainerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private let documentView = TranscriptDocumentView()
        private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

        private weak var containerView: TranscriptScrollContainerView?
        private var boundsObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var sessionID: OpenCodeSession.ID?
        private var isRunning = false
        private var hasVisibleContent = false
        private var pendingInitialBottomAlignment = true
        private var userScrolled = false
        private var previousDistanceFromBottom: CGFloat = 0
        private var contentHeight: CGFloat = 0
        private var viewportHeight: CGFloat = 0
        private var settlingUntil: Date?
        private var programmaticBottomScrollMarker: TranscriptAutoFollow.ProgrammaticBottomScrollMarker?
        private var isSynchronizingLayout = false

        init() {
            hostingView.translatesAutoresizingMaskIntoConstraints = true
        }

        func install(in view: TranscriptScrollContainerView) {
            if containerView !== view {
                detachObservers()
                containerView = view
                configureScrollView(view.scrollView)
                observeClipView(of: view.scrollView)
            }

            if hostingView.superview !== documentView {
                hostingView.removeFromSuperview()
                documentView.addSubview(hostingView)
            }

            if view.scrollView.documentView !== documentView {
                view.scrollView.documentView = documentView
            }
        }

        func detach() {
            detachObservers()
            containerView = nil
        }

        func update(
            in view: TranscriptScrollContainerView,
            sessionID: OpenCodeSession.ID?,
            isRunning: Bool,
            hasVisibleContent: Bool,
            content: AnyView
        ) {
            install(in: view)

            let now = Date()
            if self.sessionID != sessionID {
                self.sessionID = sessionID
                pendingInitialBottomAlignment = true
                userScrolled = false
                previousDistanceFromBottom = 0
                contentHeight = 0
                viewportHeight = 0
                settlingUntil = nil
                programmaticBottomScrollMarker = nil
            }

            if isRunning {
                settlingUntil = nil
            } else if self.isRunning {
                settlingUntil = now.addingTimeInterval(TranscriptAutoFollow.settlingDuration)
            }

            self.isRunning = isRunning
            self.hasVisibleContent = hasVisibleContent
            hostingView.rootView = content
            hostingView.invalidateIntrinsicContentSize()

            let shouldForceInitialBottomAlignment = pendingInitialBottomAlignment && hasVisibleContent
            synchronizeLayoutAndScroll(in: view.scrollView, now: now, forceScrollToBottom: shouldForceInitialBottomAlignment)

            if shouldForceInitialBottomAlignment {
                pendingInitialBottomAlignment = false
            }
        }

        private func configureScrollView(_ scrollView: NSScrollView) {
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets()
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.contentView.postsFrameChangedNotifications = true
        }

        private func observeClipView(of scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.handleBoundsDidChange(for: scrollView)
            }

            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.handleViewportFrameDidChange(for: scrollView)
            }
        }

        private func detachObservers() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
            }
            boundsObserver = nil
            frameObserver = nil
        }

        private func handleBoundsDidChange(for scrollView: NSScrollView) {
            guard !isSynchronizingLayout else { return }

            let now = Date()
            pruneExpiredProgrammaticMarker(now: now)

            let currentOffset = scrollView.contentView.bounds.minY
            let isProgrammatic = TranscriptAutoFollow.matchesProgrammaticBottomScroll(
                currentOffset: currentOffset,
                marker: programmaticBottomScrollMarker,
                now: now
            )
            let isUserDriven = TranscriptAutoFollow.isUserDrivenScrollEvent(
                NSApp.currentEvent,
                in: scrollView
            ) && !isProgrammatic

            updateScrollState(in: scrollView, isUserDriven: isUserDriven)
        }

        private func handleViewportFrameDidChange(for scrollView: NSScrollView) {
            synchronizeLayoutAndScroll(in: scrollView, now: Date())
        }

        private func synchronizeLayoutAndScroll(
            in scrollView: NSScrollView,
            now: Date,
            forceScrollToBottom: Bool = false
        ) {
            guard !isSynchronizingLayout else { return }
            isSynchronizingLayout = true
            defer { isSynchronizingLayout = false }

            layoutDocumentView(in: scrollView)
            clampVisibleOffsetIfNeeded(in: scrollView)
            pruneExpiredProgrammaticMarker(now: now)

            if forceScrollToBottom || shouldKeepPinnedToBottom(now: now) {
                scrollToBottom(in: scrollView, now: now)
            }

            updateScrollState(in: scrollView, isUserDriven: false)
        }

        private func layoutDocumentView(in scrollView: NSScrollView) {
            let resolvedWidth = max(1, floor(scrollView.contentSize.width))
            let previousHeight = max(1, ceil(contentHeight))

            hostingView.frame = CGRect(x: 0, y: 0, width: resolvedWidth, height: previousHeight)
            hostingView.layoutSubtreeIfNeeded()

            var resolvedHeight = max(1, ceil(hostingView.fittingSize.height))
            documentView.frame = CGRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
            hostingView.frame = documentView.bounds
            hostingView.layoutSubtreeIfNeeded()

            let adjustedHeight = max(1, ceil(hostingView.fittingSize.height))
            if abs(adjustedHeight - resolvedHeight) > 0.5 {
                resolvedHeight = adjustedHeight
                documentView.frame = CGRect(x: 0, y: 0, width: resolvedWidth, height: resolvedHeight)
                hostingView.frame = documentView.bounds
            }

            contentHeight = resolvedHeight
            viewportHeight = max(0, scrollView.contentView.bounds.height)
            scrollView.hasVerticalScroller = contentHeight - viewportHeight > 1
        }

        private func clampVisibleOffsetIfNeeded(in scrollView: NSScrollView) {
            let currentOffset = scrollView.contentView.bounds.minY
            let clampedOffset = max(
                0,
                min(
                    currentOffset,
                    TranscriptAutoFollow.bottomScrollOffset(
                        contentHeight: contentHeight,
                        viewportHeight: viewportHeight
                    )
                )
            )

            if abs(clampedOffset - currentOffset) > 0.5 {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedOffset))
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scrollToBottom(in scrollView: NSScrollView, now: Date) {
            let targetOffset = TranscriptAutoFollow.bottomScrollOffset(
                contentHeight: contentHeight,
                viewportHeight: viewportHeight
            )
            programmaticBottomScrollMarker = .init(offset: targetOffset, timestamp: now)

            let currentOffset = scrollView.contentView.bounds.minY
            guard abs(currentOffset - targetOffset) > TranscriptAutoFollow.programmaticScrollOffsetEpsilon else {
                return
            }

            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func updateScrollState(in scrollView: NSScrollView, isUserDriven: Bool) {
            let currentOffset = scrollView.contentView.bounds.minY
            let distanceFromBottom = TranscriptAutoFollow.distanceFromBottom(
                contentHeight: contentHeight,
                viewportHeight: viewportHeight,
                scrollOffset: currentOffset
            )

            userScrolled = TranscriptAutoFollow.updatedDetachmentState(
                wasDetachedByUser: userScrolled,
                previousDistanceFromBottom: previousDistanceFromBottom,
                newDistanceFromBottom: distanceFromBottom,
                isUserDriven: isUserDriven
            )
            previousDistanceFromBottom = distanceFromBottom
        }

        private func shouldKeepPinnedToBottom(now: Date) -> Bool {
            TranscriptAutoFollow.shouldKeepPinnedToBottom(
                isRunning: isRunning,
                isSettlingAfterRun: TranscriptAutoFollow.isSettlingAfterRun(
                    settlingUntil: settlingUntil,
                    now: now
                ),
                isDetachedByUser: userScrolled
            )
        }

        private func pruneExpiredProgrammaticMarker(now: Date) {
            guard let programmaticBottomScrollMarker else { return }
            if now.timeIntervalSince(programmaticBottomScrollMarker.timestamp) > TranscriptAutoFollow.programmaticScrollTimeout {
                self.programmaticBottomScrollMarker = nil
            }
        }
    }
}

private final class TranscriptScrollContainerView: NSView {
    let scrollView = TranscriptRootScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TranscriptRootScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
}

private final class TranscriptDocumentView: NSView {
    override var isFlipped: Bool { true }
}

enum TranscriptAutoFollow {
    static let nearBottomThreshold: CGFloat = 120
    static let bottomReattachEpsilon: CGFloat = 1
    static let programmaticScrollOffsetEpsilon: CGFloat = 2
    static let programmaticScrollTimeout: TimeInterval = 1.5
    static let settlingDuration: TimeInterval = 0.3

    struct ProgrammaticBottomScrollMarker: Equatable {
        let offset: CGFloat
        let timestamp: Date
    }

    static func distanceFromBottom(viewportBottom: CGFloat, contentBottom: CGFloat) -> CGFloat {
        clampDistance(contentBottom - viewportBottom)
    }

    static func distanceFromBottom(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        scrollOffset: CGFloat
    ) -> CGFloat {
        clampDistance(bottomScrollOffset(contentHeight: contentHeight, viewportHeight: viewportHeight) - scrollOffset)
    }

    static func bottomScrollOffset(contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    static func clampDistance(_ distance: CGFloat) -> CGFloat {
        max(0, distance)
    }

    static func isNearBottom(
        distanceFromBottom: CGFloat,
        threshold: CGFloat = nearBottomThreshold
    ) -> Bool {
        clampDistance(distanceFromBottom) <= threshold
    }

    static func isNearBottom(
        viewportBottom: CGFloat,
        contentBottom: CGFloat,
        threshold: CGFloat = nearBottomThreshold
    ) -> Bool {
        isNearBottom(
            distanceFromBottom: distanceFromBottom(
                viewportBottom: viewportBottom,
                contentBottom: contentBottom
            ),
            threshold: threshold
        )
    }

    static func isAtBottom(
        distanceFromBottom: CGFloat,
        epsilon: CGFloat = bottomReattachEpsilon
    ) -> Bool {
        clampDistance(distanceFromBottom) <= epsilon
    }

    static func updatedDetachmentState(
        wasDetachedByUser: Bool,
        previousDistanceFromBottom: CGFloat,
        newDistanceFromBottom: CGFloat,
        isUserDriven: Bool,
        reattachEpsilon: CGFloat = bottomReattachEpsilon
    ) -> Bool {
        if isAtBottom(distanceFromBottom: newDistanceFromBottom, epsilon: reattachEpsilon) {
            return false
        }

        guard isUserDriven else {
            return wasDetachedByUser
        }

        if wasDetachedByUser {
            return true
        }

        let previousDistance = clampDistance(previousDistanceFromBottom)
        let nextDistance = clampDistance(newDistanceFromBottom)
        return nextDistance > max(previousDistance, reattachEpsilon)
    }

    static func shouldKeepPinnedToBottom(
        isRunning: Bool,
        isSettlingAfterRun: Bool,
        isDetachedByUser: Bool
    ) -> Bool {
        (isRunning || isSettlingAfterRun) && !isDetachedByUser
    }

    static func isSettlingAfterRun(
        settlingUntil: Date?,
        now: Date
    ) -> Bool {
        guard let settlingUntil else { return false }
        return now < settlingUntil
    }

    static func matchesProgrammaticBottomScroll(
        currentOffset: CGFloat,
        marker: ProgrammaticBottomScrollMarker?,
        now: Date,
        epsilon: CGFloat = programmaticScrollOffsetEpsilon,
        timeout: TimeInterval = programmaticScrollTimeout
    ) -> Bool {
        guard let marker else { return false }
        guard now.timeIntervalSince(marker.timestamp) <= timeout else { return false }
        return abs(currentOffset - marker.offset) <= epsilon
    }

    static func isUserDrivenScrollEvent(_ event: NSEvent?, in scrollView: NSScrollView) -> Bool {
        guard let event else { return false }

        switch event.type {
        case .scrollWheel:
            return !targetsNestedScrollView(event, rootScrollView: scrollView)
        case .leftMouseDown,
             .leftMouseDragged,
             .rightMouseDragged,
             .otherMouseDragged,
             .swipe,
             .magnify,
             .gesture,
             .keyDown:
            return true
        default:
            return false
        }
    }

    static func targetsNestedScrollView(_ event: NSEvent, rootScrollView: NSScrollView) -> Bool {
        guard let window = rootScrollView.window ?? event.window else { return false }
        let hitView = window.contentView?.hitTest(event.locationInWindow)
        guard let targetScrollView = hitView?.enclosingScrollView else { return false }
        return targetScrollView !== rootScrollView
    }
}
