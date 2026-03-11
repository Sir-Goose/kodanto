import SwiftUI

struct SessionPermissionDockView: View {
    @Bindable var model: KodantoAppModel
    let request: OpenCodePermissionRequest

    @State private var actionModel: SessionPermissionActionModel

    init(model: KodantoAppModel, request: OpenCodePermissionRequest) {
        self.model = model
        self.request = request
        _actionModel = State(initialValue: SessionPermissionActionModel(requestID: request.id) { reply in
            try await model.submitPermissionResponse(request, reply: reply)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let toolDescription, !toolDescription.isEmpty {
                Text(toolDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !request.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Requested access")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(request.patterns, id: \.self) { pattern in
                            Text(pattern)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { model.isPermissionAutoAcceptEnabled },
                set: { model.setPermissionAutoAccept($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-accept permissions")
                        .font(.callout.weight(.medium))
                    Text("Automatically allow future permission requests for this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!model.canTogglePermissionAutoAccept || actionModel.isResponding)

            if let responseError = actionModel.responseError, !responseError.isEmpty {
                Text(responseError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.2))
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        .onChange(of: request.id) { _, _ in
            actionModel.reset(for: request.id)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Permission required")
                    .font(.headline)
                Text(permissionTitle)
                    .font(.callout.weight(.medium))
                Text("Review this request before the agent can continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Deny", role: .destructive) {
                actionModel.respond(with: .reject)
            }
            .disabled(actionModel.isResponding)

            Spacer(minLength: 0)

            Button("Allow Always") {
                actionModel.respond(with: .always)
            }
            .disabled(actionModel.isResponding)

            Button("Allow Once") {
                actionModel.respond(with: .once)
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionModel.isResponding)
        }
    }

    private var permissionTitle: String {
        request.permission
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var toolDescription: String? {
        switch request.permission {
        case "read":
            return "The agent wants to read files that match these paths."
        case "edit":
            return "The agent wants to modify files in your workspace."
        case "bash":
            return "The agent wants to run a shell command."
        case "task":
            return "The agent wants to launch a sub-agent to continue the task."
        case "webfetch":
            return "The agent wants to fetch data from a website."
        case "grep":
            return "The agent wants to search file contents."
        case "glob", "list":
            return "The agent wants to inspect files in your project."
        default:
            return nil
        }
    }
}
