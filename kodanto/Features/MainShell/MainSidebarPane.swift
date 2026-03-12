import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainSidebarPane: View {
    @Bindable var model: KodantoAppModel

    @State private var expandedProjectIDs: Set<OpenCodeProject.ID> = []
    @State private var projectHeaderFrames: [OpenCodeProject.ID: CGRect] = [:]
    @State private var draggedProjectID: OpenCodeProject.ID?
    @State private var projectDropTarget: ProjectDropTarget?
    @State private var hoveredProjectID: OpenCodeProject.ID?
    @State private var sidebarFocusedItem: SidebarFocusItem?
    @State private var renamingSessionContext: SessionActionContext?
    @State private var renameDraftTitle = ""
    @FocusState private var isSidebarFocused: Bool

    private let projectDropCoordinateSpace = "project-drop-coordinate-space"

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                projectsSectionHeader
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

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
        .task(id: model.selectedProjectID) {
            guard let selectedProjectID = model.selectedProjectID else { return }
            expandedProjectIDs.insert(selectedProjectID)
        }
        .onAppear {
            draggedProjectID = nil
            projectDropTarget = nil
            if sidebarFocusedItem == nil {
                sidebarFocusedItem = sidebarFocusableItems.first
            }
        }
        .sheet(item: $renamingSessionContext) { context in
            RenameSessionSheet(
                title: $renameDraftTitle,
                onCancel: {
                    renamingSessionContext = nil
                },
                onSave: {
                    let nextTitle = renameDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nextTitle.isEmpty else { return }
                    model.renameSession(sessionID: context.sessionID, in: context.projectID, newTitle: nextTitle)
                    renamingSessionContext = nil
                }
            )
        }
        .navigationTitle("kodanto")
    }

    private var projectsSectionHeader: some View {
        HStack(spacing: 8) {
            sidebarSectionHeader("Projects")
            Spacer(minLength: 0)
            Button {
                showAddProjectPicker()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Add Project")
            .disabled(model.selectedProfile == nil)
        }
    }

    private func projectSection(for project: OpenCodeProject) -> some View {
        let isExpanded = expandedProjectIDs.contains(project.id)
        let sessions = model.sessions(for: project)
        let projectFocusItem = SidebarFocusItem.project(project.id)
        let showNewSessionButton = hoveredProjectID == project.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProjectSidebarRow(
                    project: project,
                    isExpanded: isExpanded,
                    dropPlacement: dropPlacement(for: project.id),
                    showsNewSessionButton: showNewSessionButton,
                    canCreateSession: model.selectedProfile != nil,
                    onCreateSession: {
                        expandedProjectIDs.insert(project.id)
                        model.createSession(in: project.id)
                    }
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
            }
            .onHover { hovering in
                if hovering {
                    hoveredProjectID = project.id
                } else if hoveredProjectID == project.id {
                    hoveredProjectID = nil
                }
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
                            .padding(.leading, 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contextMenu {
                                Button("Rename…") {
                                    beginRename(session: session, in: project)
                                }
                                Button("Archive", role: .destructive) {
                                    model.archiveSession(sessionID: session.id, in: project.id)
                                }
                            }
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
    }

    private func showAddProjectPicker() {
        let panel = NSOpenPanel()
        panel.title = "Add Project"
        panel.prompt = "Add Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferredProjectPickerDirectory()

        guard panel.runModal() == .OK, let selectedDirectory = panel.url?.path else { return }
        model.addProject(from: selectedDirectory)
    }

    private func preferredProjectPickerDirectory() -> URL {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let programmingDirectory = homeDirectory.appendingPathComponent("Programming", isDirectory: true)
        if fileManager.fileExists(atPath: programmingDirectory.path) {
            return programmingDirectory
        }

        return homeDirectory
    }

    private func setSidebarFocus(_ item: SidebarFocusItem) {
        sidebarFocusedItem = item
        isSidebarFocused = true
    }

    private func beginRename(session: OpenCodeSession, in project: OpenCodeProject) {
        renameDraftTitle = session.title
        renamingSessionContext = SessionActionContext(projectID: project.id, sessionID: session.id)
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
}

private struct SessionActionContext: Identifiable {
    let projectID: OpenCodeProject.ID
    let sessionID: OpenCodeSession.ID

    var id: String { "\(projectID)|\(sessionID)" }
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

struct ProjectSidebarContainerDropDelegate: DropDelegate {
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

struct ProjectHeaderFramePreferenceKey: PreferenceKey {
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

struct ProjectSidebarRow: View {
    let project: OpenCodeProject
    let isExpanded: Bool
    let dropPlacement: ProjectDropPlacement?
    let showsNewSessionButton: Bool
    let canCreateSession: Bool
    let onCreateSession: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: leadingIconSystemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)
                .padding(.top, 2)

            Text(project.displayName)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Button(action: onCreateSession) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help("New Session")
            .disabled(!canCreateSession)
            .opacity(showsNewSessionButton ? 1 : 0)
            .allowsHitTesting(showsNewSessionButton)
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
        isHovered ? Color.secondary.opacity(0.08) : .clear
    }

    private var leadingIconSystemName: String {
        guard isHovered else { return "folder" }
        return isExpanded ? "chevron.down" : "chevron.right"
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

struct SessionSidebarRow: View {
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

struct SessionSidebarIndicator: View {
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

private struct RenameSessionSheet: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Session")
                .font(.headline)

            TextField("Session title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit {
                    onSave()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isTitleFocused = true
        }
    }
}
