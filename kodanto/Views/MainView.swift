import AppKit
import UniformTypeIdentifiers
import SwiftUI

struct MainView: View {
    @Bindable var model: KodantoAppModel
    @State private var editingProfile: ServerProfile?
    @State private var expandedProjectIDs: Set<OpenCodeProject.ID> = []
    @State private var projectHeaderFrames: [OpenCodeProject.ID: CGRect] = [:]
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var promptEditorHeight: CGFloat = 0
    @State private var showingConnectionPopover = false
    @State private var pendingInitialBottomSessionID: OpenCodeSession.ID?
    @State private var draggedProjectID: OpenCodeProject.ID?
    @State private var projectDropTarget: ProjectDropTarget?
    @State private var transcriptDisclosureStates: [String: Bool] = [:]
    @State private var patchDisclosureStates: [String: Bool] = [:]
    @State private var shellOutputDisclosureStates: [String: Bool] = [:]
    @State private var sidebarFocusedItem: SidebarFocusItem?
    @FocusState private var isSidebarFocused: Bool

    private let transcriptScrollTarget = "transcript-bottom"
    private let projectDropCoordinateSpace = "project-drop-coordinate-space"

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
    private static let composerContentGap: CGFloat = 12
    private static let collapsedHeaderLeadingInset: CGFloat = 124

    private var transcriptTurns: [TranscriptTurn] {
        TranscriptTurn.build(from: model.selectedSessionMessages)
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
                saveConnectionProfile(profile, selectAfterSave: true, connectAfterSave: true)
                editingProfile = nil
            }
        }
        .sheet(isPresented: $model.showingConnectionsManager) {
            ConnectionsManagerSheet(model: model) { profile in
                activateConnection(profile, dismissPopover: false)
            }
        }
        .background {
            WindowTitlebarAccessory(content: connectionStatusButton)
                .frame(width: 0, height: 0)
        }
        .task {
            if case .idle = model.connectionState {
                model.connect()
            }
        }
        .task(id: model.selectedProjectID) {
            guard let selectedProjectID = model.selectedProjectID else { return }
            expandedProjectIDs.insert(selectedProjectID)
        }
        .onAppear {
            model.sanitizeProjects()
            draggedProjectID = nil
            projectDropTarget = nil
            if sidebarFocusedItem == nil {
                sidebarFocusedItem = sidebarFocusableItems.first
            }
        }
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sidebarSectionHeader("Projects")
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.projects) { project in
                        projectSection(for: project)
                    }
                }
                .padding(.horizontal, 8)
                .coordinateSpace(name: projectDropCoordinateSpace)
                .onPreferenceChange(ProjectHeaderFramePreferenceKey.self) { frames in
                    projectHeaderFrames = frames
                }
                .contentShape(Rectangle())
                .onDrop(of: [UTType.plainText], delegate: ProjectSidebarContainerDropDelegate(
                    model: model,
                    projectOrder: model.projects.map(\.id),
                    projectHeaderFrames: projectHeaderFrames,
                    draggedProjectID: $draggedProjectID,
                    dropTarget: $projectDropTarget
                ))
            }
            .padding(.vertical, 10)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isSidebarFocused)
        .onMoveCommand(perform: handleSidebarMoveCommand)
        .onKeyPress(.return, phases: .down) { _ in
            guard isSidebarFocused else { return .ignored }
            activateFocusedSidebarItem()
            return .handled
        }
        .onKeyPress(.space, phases: .down) { _ in
            guard isSidebarFocused else { return .ignored }
            activateFocusedSidebarItem()
            return .handled
        }
        .onChange(of: sidebarFocusableItems) { oldItems, newItems in
            sidebarFocusedItem = SidebarFocusNavigator.reconcileFocus(
                current: sidebarFocusedItem,
                previousItems: oldItems,
                updatedItems: newItems
            )
            projectHeaderFrames = projectHeaderFrames.filter { newItems.contains(.project($0.key)) }
        }
        .navigationTitle("kodanto")
    }

    private func projectSection(for project: OpenCodeProject) -> some View {
        let isExpanded = expandedProjectIDs.contains(project.id)
        let sessions = model.sessions(for: project)
        let projectFocusItem = SidebarFocusItem.project(project.id)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProjectSidebarRow(
                    project: project,
                    isExpanded: isExpanded,
                    dropPlacement: dropPlacement(for: project.id)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    setSidebarFocus(projectFocusItem)
                    toggleProjectExpansion(for: project)
                }
                .onDrag {
                    draggedProjectID = project.id
                    return NSItemProvider(object: NSString(string: project.id))
                }

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
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ProjectHeaderFramePreferenceKey.self, value: [
                            project.id: proxy.frame(in: .named(projectDropCoordinateSpace))
                        ])
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
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
                            let focusItem = SidebarFocusItem.session(projectID: project.id, sessionID: session.id)
                            Button {
                                setSidebarFocus(focusItem)
                                model.selectSession(session.id, in: project.id)
                            } label: {
                                SessionSidebarRow(
                                    session: session,
                                    indicator: model.sessionSidebarIndicator(for: session, in: project),
                                    isSelected: model.selectedSessionID == session.id,
                                    isFocused: sidebarFocusedItem == focusItem
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var sidebarFocusableItems: [SidebarFocusItem] {
        var items: [SidebarFocusItem] = []
        for project in model.projects {
            items.append(.project(project.id))
            guard expandedProjectIDs.contains(project.id) else { continue }
            for session in model.sessions(for: project) {
                items.append(.session(projectID: project.id, sessionID: session.id))
            }
        }
        return items
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }

    private func setSidebarFocus(_ item: SidebarFocusItem) {
        sidebarFocusedItem = item
        isSidebarFocused = true
    }

    private func handleSidebarMoveCommand(_ direction: MoveCommandDirection) {
        let items = sidebarFocusableItems
        guard !items.isEmpty else { return }
        isSidebarFocused = true

        switch direction {
        case .up:
            sidebarFocusedItem = SidebarFocusNavigator.previous(from: sidebarFocusedItem, in: items)
        case .down:
            sidebarFocusedItem = SidebarFocusNavigator.next(from: sidebarFocusedItem, in: items)
        case .left:
            handleSidebarMoveLeft()
        case .right:
            handleSidebarMoveRight()
        default:
            break
        }
    }

    private func handleSidebarMoveLeft() {
        guard let sidebarFocusedItem else { return }

        switch sidebarFocusedItem {
        case let .project(projectID):
            guard expandedProjectIDs.contains(projectID) else { return }
            expandedProjectIDs.remove(projectID)
        case let .session(projectID, _):
            self.sidebarFocusedItem = .project(projectID)
        }
    }

    private func handleSidebarMoveRight() {
        guard let sidebarFocusedItem else { return }

        switch sidebarFocusedItem {
        case let .project(projectID):
            if expandedProjectIDs.contains(projectID) {
                if let firstSession = SidebarFocusNavigator.firstSession(in: projectID, from: sidebarFocusableItems) {
                    self.sidebarFocusedItem = firstSession
                }
            } else {
                expandedProjectIDs.insert(projectID)
                if let project = model.projects.first(where: { $0.id == projectID }) {
                    model.loadSessionsIfNeeded(for: project)
                }
            }
        case .session:
            break
        }
    }

    private func activateFocusedSidebarItem() {
        guard let sidebarFocusedItem else {
            if let firstItem = sidebarFocusableItems.first {
                setSidebarFocus(firstItem)
            }
            return
        }

        switch sidebarFocusedItem {
        case let .project(projectID):
            guard let project = model.projects.first(where: { $0.id == projectID }) else { return }
            toggleProjectExpansion(for: project)
        case let .session(projectID, sessionID):
            model.selectSession(sessionID, in: projectID)
        }
    }

    private func presentAddConnection() {
        showingConnectionPopover = false
        editingProfile = nil
        model.showingConnectionSheet = true
    }

    private func presentConnectionsManager() {
        showingConnectionPopover = false
        model.showingConnectionsManager = true
    }

    private func activateConnection(_ profile: ServerProfile, dismissPopover: Bool = true) {
        let isSwitchingProfiles = model.selectedProfileID != profile.id
        if isSwitchingProfiles {
            model.selectProfile(profile.id)
        }

        if isSwitchingProfiles || model.canConnect {
            model.connect()
        }

        if dismissPopover {
            showingConnectionPopover = false
        }
    }

    private func saveConnectionProfile(
        _ profile: ServerProfile,
        selectAfterSave: Bool,
        connectAfterSave: Bool
    ) {
        model.saveProfile(profile, selectAfterSave: selectAfterSave)
        if connectAfterSave {
            model.connect()
        }
    }

    private func toggleProjectExpansion(for project: OpenCodeProject) {
        let shouldExpand = !expandedProjectIDs.contains(project.id)
        if shouldExpand {
            expandedProjectIDs.insert(project.id)
        } else {
            expandedProjectIDs.remove(project.id)
        }

        if shouldExpand {
            model.loadSessionsIfNeeded(for: project)
        }
    }

    private func dropPlacement(for projectID: OpenCodeProject.ID) -> ProjectDropPlacement? {
        guard let projectDropTarget, projectDropTarget.projectID == projectID else { return nil }
        return projectDropTarget.placement
    }

    private var detailPanel: some View {
        GeometryReader { geometry in
            let composerMaxHeight = max(promptMinimumHeight, geometry.size.height * 0.3)

            VStack(spacing: 0) {
                if let session = model.selectedSession {
                    header(for: session)
                    Divider()
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    ForEach(transcriptTurns) { turn in
                                        TranscriptTurnView(
                                            turn: turn,
                                            worktreeRoot: model.selectedProject?.worktree,
                                            resolveTaskTarget: { sessionID in
                                                model.loadedSessionNavigationTarget(for: sessionID)
                                            },
                                            navigateToSession: { target in
                                                model.selectSession(target.sessionID, in: target.projectID)
                                            },
                                            disclosureStates: $transcriptDisclosureStates,
                                            patchDisclosureStates: $patchDisclosureStates,
                                            shellOutputDisclosureStates: $shellOutputDisclosureStates
                                        )
                                    }

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
                            .onAppear {
                                pendingInitialBottomSessionID = model.selectedSessionID
                                jumpTranscriptToBottom(using: proxy)
                            }
                            .onChange(of: model.selectedSessionID) { _, sessionID in
                                pendingInitialBottomSessionID = sessionID
                                transcriptDisclosureStates = [:]
                                patchDisclosureStates = [:]
                                shellOutputDisclosureStates = [:]
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

                        bottomPanel(maxHeight: composerMaxHeight)
                            .frame(maxWidth: Self.composerMaxWidth)
                            .padding(.horizontal, Self.composerOuterPadding)
                            .padding(.bottom, Self.composerOuterPadding)
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
            HStack(spacing: 10) {
                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.9), lineWidth: 1)
                    }
                    .shadow(color: connectionIndicatorColor.opacity(0.35), radius: 3)

                Text(activeConnectionName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.secondary.opacity(showingConnectionPopover ? 0.22 : 0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            .padding(.top, 8)
            .padding(.leading, 6)
            .padding(.bottom, 6)
            .padding(.trailing, 16)
        }
        .buttonStyle(.plain)
        .help(connectionToolbarHelp)
        .popover(isPresented: $showingConnectionPopover, arrowEdge: .top) {
            connectionPopover
        }
    }

    private var connectionPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: activeConnectionIconName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(activeConnectionName)
                            .font(.headline)
                        Text(activeConnectionDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                Label(connectionStatusTitle, systemImage: connectionStatusSymbol)
                    .font(.callout)
                Label(liveSyncStatusTitle, systemImage: liveSyncStatusSymbol)
                    .font(.callout)
            }

            if model.profiles.count > 1 {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Switch Connection")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.profiles) { profile in
                            let isSelected = model.selectedProfileID == profile.id
                            let isDisabled = isSelected && !model.canConnect

                            Button {
                                activateConnection(profile)
                            } label: {
                                ConnectionSwitchRow(
                                    profile: profile,
                                    isSelected: isSelected
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isDisabled)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
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

                Button("Add Connection...") {
                    presentAddConnection()
                }

                Button("Manage Connections...") {
                    presentConnectionsManager()
                }

                Button("Diagnostics") {
                    showingConnectionPopover = false
                    model.showingDiagnostics = true
                }
            }

            Text("Switching connections reloads projects and sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labelStyle(.titleAndIcon)
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private var activeConnectionName: String {
        model.selectedProfile?.name ?? "No Connection"
    }

    private var activeConnectionDetail: String {
        guard let profile = model.selectedProfile else {
            return "Add a connection to get started."
        }

        return "\(profile.connectionTypeLabel) - \(profile.normalizedBaseURL)"
    }

    private var activeConnectionIconName: String {
        model.selectedProfile?.connectionIconName ?? "network"
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
        "\(activeConnectionName). \(connectionStatusTitle). \(liveSyncStatusTitle)."
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

private struct ConnectionsManagerSheet: View {
    @Bindable var model: KodantoAppModel
    let onActivateProfile: (ServerProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile: ServerProfile?
    @State private var showingConnectionSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connections")
                        .font(.title2.weight(.semibold))
                    Text("Local is the default, but you can keep remote connections ready to switch into.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.profiles) { profile in
                        ConnectionManagerRow(
                            profile: profile,
                            isSelected: model.selectedProfileID == profile.id,
                            isConnectable: model.selectedProfileID != profile.id || model.canConnect,
                            canDelete: model.profiles.count > 1,
                            onActivate: {
                                onActivateProfile(profile)
                            },
                            onEdit: {
                                editingProfile = profile
                                showingConnectionSheet = true
                            },
                            onDelete: {
                                model.deleteProfile(profile)
                            }
                        )
                    }
                }
            }

            HStack {
                Button {
                    editingProfile = nil
                    showingConnectionSheet = true
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }

                Spacer()

                Text("Switching connections reloads projects and sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 620, height: 460)
        .sheet(isPresented: $showingConnectionSheet) {
            ConnectionSheet(existingProfile: editingProfile) { profile in
                model.saveProfile(profile, selectAfterSave: false)
                if model.selectedProfileID == profile.id {
                    model.connect()
                }
                editingProfile = nil
                showingConnectionSheet = false
            }
        }
    }
}

private struct ConnectionManagerRow: View {
    let profile: ServerProfile
    let isSelected: Bool
    let isConnectable: Bool
    let canDelete: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: profile.connectionIconName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.headline)
                        if isSelected {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }

                    Text(profile.connectionTypeLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(profile.normalizedBaseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(primaryActionTitle) {
                    onActivate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConnectable)

                Button("Edit") {
                    onEdit()
                }

                Button("Delete", role: .destructive) {
                    onDelete()
                }
                .disabled(!canDelete)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var primaryActionTitle: String {
        if isSelected {
            return isConnectable ? "Reconnect" : "Current Connection"
        }

        return "Switch and Connect"
    }
}

private struct ConnectionSwitchRow: View {
    let profile: ServerProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.connectionIconName)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.callout.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                Text(profile.connectionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }

        return Color.secondary.opacity(0.05)
    }
}

private struct ProjectSidebarRow: View {
    let project: OpenCodeProject
    let isExpanded: Bool
    let dropPlacement: ProjectDropPlacement?
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
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: overlayAlignment) {
            if dropPlacement != nil {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: dropPlacement)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }

    private var overlayAlignment: Alignment {
        switch dropPlacement {
        case .before:
            return .top
        case .after:
            return .bottom
        case nil:
            return .center
        }
    }
}

struct ProjectDropTarget: Equatable {
    let projectID: OpenCodeProject.ID
    let placement: ProjectDropPlacement
}

struct ProjectDropRowFrame: Equatable {
    let projectID: OpenCodeProject.ID
    let minY: CGFloat
    let maxY: CGFloat

    var midpointY: CGFloat {
        (minY + maxY) / 2
    }
}

enum ProjectDropFrameResolver {
    static func orderedFrames(
        projectOrder: [OpenCodeProject.ID],
        projectHeaderFrames: [OpenCodeProject.ID: CGRect]
    ) -> [ProjectDropRowFrame] {
        projectOrder.compactMap { projectID in
            guard let frame = projectHeaderFrames[projectID] else { return nil }
            return ProjectDropRowFrame(projectID: projectID, minY: frame.minY, maxY: frame.maxY)
        }
    }
}

enum ProjectDropTargetResolver {
    static func resolve(
        locationY: CGFloat,
        frames: [ProjectDropRowFrame]
    ) -> ProjectDropTarget? {
        guard let firstFrame = frames.first, let lastFrame = frames.last else { return nil }

        if locationY <= firstFrame.midpointY {
            return ProjectDropTarget(projectID: firstFrame.projectID, placement: .before)
        }

        if locationY >= lastFrame.midpointY {
            return ProjectDropTarget(projectID: lastFrame.projectID, placement: .after)
        }

        for (index, frame) in frames.enumerated() {
            if locationY <= frame.maxY {
                let placement: ProjectDropPlacement = locationY <= frame.midpointY ? .before : .after
                return ProjectDropTarget(projectID: frame.projectID, placement: placement)
            }

            guard index + 1 < frames.count else { continue }
            let nextFrame = frames[index + 1]
            guard locationY >= frame.maxY, locationY <= nextFrame.minY else { continue }

            let distanceToCurrentBottom = abs(locationY - frame.maxY)
            let distanceToNextTop = abs(nextFrame.minY - locationY)
            if distanceToCurrentBottom <= distanceToNextTop {
                return ProjectDropTarget(projectID: frame.projectID, placement: .after)
            }
            return ProjectDropTarget(projectID: nextFrame.projectID, placement: .before)
        }

        return ProjectDropTarget(projectID: lastFrame.projectID, placement: .after)
    }
}

enum ProjectDropValidationResolver {
    static func canDrop(
        draggedProjectID: OpenCodeProject.ID?,
        targetProjectID: OpenCodeProject.ID
    ) -> Bool {
        guard let draggedProjectID else { return false }
        return draggedProjectID != targetProjectID
    }
}

private struct ProjectSidebarContainerDropDelegate: DropDelegate {
    let model: KodantoAppModel
    let projectOrder: [OpenCodeProject.ID]
    let projectHeaderFrames: [OpenCodeProject.ID: CGRect]
    @Binding var draggedProjectID: OpenCodeProject.ID?
    @Binding var dropTarget: ProjectDropTarget?

    func dropEntered(info: DropInfo) {
        dropTarget = resolvedTarget(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedProjectID != nil else {
            return DropProposal(operation: .forbidden)
        }

        dropTarget = resolvedTarget(for: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedProjectID, let resolvedTarget = resolvedTarget(for: info) else {
            clearDropState()
            return false
        }

        model.moveProject(draggedProjectID, relativeTo: resolvedTarget.projectID, placement: resolvedTarget.placement)
        clearDropState()
        return true
    }

    func dropExited(info: DropInfo) {
        dropTarget = nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedProjectID != nil
    }

    private func clearDropState() {
        dropTarget = nil
        draggedProjectID = nil
    }

    private func resolvedTarget(for info: DropInfo) -> ProjectDropTarget? {
        let orderedFrames = ProjectDropFrameResolver.orderedFrames(
            projectOrder: projectOrder,
            projectHeaderFrames: projectHeaderFrames
        )

        guard let target = ProjectDropTargetResolver.resolve(locationY: info.location.y, frames: orderedFrames) else {
            return nil
        }

        guard ProjectDropValidationResolver.canDrop(
            draggedProjectID: draggedProjectID,
            targetProjectID: target.projectID
        ) else {
            return nil
        }

        return target
    }
}

private struct ProjectHeaderFramePreferenceKey: PreferenceKey {
    static var defaultValue: [OpenCodeProject.ID: CGRect] = [:]

    static func reduce(value: inout [OpenCodeProject.ID: CGRect], nextValue: () -> [OpenCodeProject.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

enum SidebarFocusItem: Hashable {
    case project(OpenCodeProject.ID)
    case session(projectID: OpenCodeProject.ID, sessionID: OpenCodeSession.ID)
}

enum SidebarFocusNavigator {
    static func next(from current: SidebarFocusItem?, in items: [SidebarFocusItem]) -> SidebarFocusItem? {
        guard !items.isEmpty else { return nil }
        guard let current, let currentIndex = items.firstIndex(of: current) else {
            return items.first
        }
        let nextIndex = min(currentIndex + 1, items.count - 1)
        return items[nextIndex]
    }

    static func previous(from current: SidebarFocusItem?, in items: [SidebarFocusItem]) -> SidebarFocusItem? {
        guard !items.isEmpty else { return nil }
        guard let current, let currentIndex = items.firstIndex(of: current) else {
            return items.first
        }
        let previousIndex = max(currentIndex - 1, 0)
        return items[previousIndex]
    }

    static func firstSession(
        in projectID: OpenCodeProject.ID,
        from items: [SidebarFocusItem]
    ) -> SidebarFocusItem? {
        items.first {
            if case let .session(sessionProjectID, _) = $0 {
                return sessionProjectID == projectID
            }
            return false
        }
    }

    static func reconcileFocus(
        current: SidebarFocusItem?,
        previousItems: [SidebarFocusItem],
        updatedItems: [SidebarFocusItem]
    ) -> SidebarFocusItem? {
        guard !updatedItems.isEmpty else { return nil }
        guard let current else { return updatedItems.first }

        if updatedItems.contains(current) {
            return current
        }

        if case let .session(projectID, _) = current {
            let projectItem = SidebarFocusItem.project(projectID)
            if updatedItems.contains(projectItem) {
                return projectItem
            }
        }

        guard let previousIndex = previousItems.firstIndex(of: current) else {
            return updatedItems.first
        }

        if previousIndex > 0 {
            let fallbackIndex = min(previousIndex - 1, updatedItems.count - 1)
            return updatedItems[fallbackIndex]
        }

        return updatedItems.first
    }
}

private struct SessionSidebarRow: View {
    let session: OpenCodeSession
    let indicator: SessionSidebarIndicatorState
    let isSelected: Bool
    let isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            SessionSidebarIndicator(indicator: indicator)

            Text(session.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 0)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(SessionRecencyFormatter.string(since: session.time.updated, now: context.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
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
        if isFocused {
            return Color.secondary.opacity(0.14)
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

private struct ComposerControlsRow: View {
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
                            .truncationMode(.tail)

                        Text(selectedModel.providerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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

                ThinkingEffortPicker(model: model)
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

            PermissionAutoAcceptToggle(model: model)
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

private struct PermissionAutoAcceptToggle: View {
    @Bindable var model: KodantoAppModel

    private var isOn: Binding<Bool> {
        Binding(
            get: { model.isPermissionAutoAcceptEnabled },
            set: { model.setPermissionAutoAccept($0) }
        )
    }

    var body: some View {
        Toggle("Full Access", isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption.weight(.medium))
            .fixedSize()
            .disabled(!model.canTogglePermissionAutoAccept)
            .help(model.isPermissionAutoAcceptEnabled ? "Stop auto-accepting permission requests" : "Auto-accept permission requests for this session")
            .opacity(model.canTogglePermissionAutoAccept ? 1 : 0.45)
            .accessibilityIdentifier("permission-auto-accept-toggle")
    }
}

private struct ThinkingEffortPicker: View {
    @Bindable var model: KodantoAppModel
    @State private var isHovered = false
    @State private var isShowingPicker = false

    private var selectionLabel: String {
        model.selectedPromptVariant ?? "Default"
    }

    private var hasVariants: Bool {
        !model.selectedModelVariants.isEmpty
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectionLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!hasVariants)
        .help("Thinking effort")
        .accessibilityIdentifier("thinking-effort-picker")
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            ThinkingEffortPickerPopover(
                variants: model.selectedModelVariants,
                selectedVariant: model.selectedPromptVariant
            ) { variant in
                model.selectModelVariant(variant)
                isShowingPicker = false
            }
        }
    }

    private struct ThinkingEffortPickerPopover: View {
        let variants: [String]
        let selectedVariant: String?
        let onSelect: (String?) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    onSelect(nil)
                } label: {
                    optionRow("Default", isSelected: selectedVariant == nil)
                }
                .buttonStyle(.plain)

                ForEach(variants, id: \.self) { variant in
                    Button {
                        onSelect(variant)
                    } label: {
                        optionRow(variant, isSelected: selectedVariant == variant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(width: 180, alignment: .leading)
        }

        @ViewBuilder
        private func optionRow(_ title: String, isSelected: Bool) -> some View {
            HStack(spacing: 10) {
                Text(title)
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
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    @ViewBuilder
    private func optionLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var backgroundColor: Color {
        isHovered ? Color.secondary.opacity(0.08) : .clear
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
