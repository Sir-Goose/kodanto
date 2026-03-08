import SwiftUI

struct MainView: View {
    @Bindable var model: KodantoAppModel
    @State private var editingProfile: ServerProfile?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            sessionList
        } detail: {
            detailPanel
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
    }

    private var sidebar: some View {
        List(selection: $model.selectedProjectID) {
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName)
                        Text(project.worktree)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(project.id)
                    .onTapGesture {
                        model.selectProject(project.id)
                    }
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

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selectedProject?.displayName ?? "Select a project")
                        .font(.title2.weight(.semibold))
                    if let pathInfo = model.pathInfo {
                        Text(pathInfo.directory)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("New Session") {
                    model.createSession()
                }
                .disabled(!model.canCreateSession)
            }

            TextField("Optional session title", text: $model.newSessionTitle)

            List(selection: $model.selectedSessionID) {
                ForEach(model.sessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title)
                            Text(session.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(model.sessionStatuses[session.id]?.label ?? "-")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectSession(session.id)
                    }
                }
            }
        }
        .padding()
    }

    private var detailPanel: some View {
        VStack(spacing: 0) {
            if let session = model.selectedSession {
                header(for: session)
                Divider()
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
                    }
                    .padding()
                }

                Divider()
                composer
            } else {
                ContentUnavailableView("Select a session", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt")
                .font(.headline)
            TextEditor(text: $model.draftPrompt)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
            HStack {
                Spacer()
                Button("Send") {
                    model.sendPrompt()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canSendPrompt)
            }
        }
        .padding()
        .background(.regularMaterial)
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
