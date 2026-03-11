import SwiftUI

struct DiagnosticsSheet: View {
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

struct ConnectionsManagerSheet: View {
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

struct ConnectionManagerRow: View {
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

struct ConnectionSwitchRow: View {
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
