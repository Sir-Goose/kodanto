import SwiftUI

struct MainView: View {
    @Bindable var model: KodantoAppModel
    @State private var editingProfile: ServerProfile?
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var showingConnectionPopover = false

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            MainSidebarPane(model: model)
        } detail: {
            MainSessionDetailPane(
                model: model,
                splitViewVisibility: splitViewVisibility
            )
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
        .onAppear {
            model.sanitizeProjects()
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
}
