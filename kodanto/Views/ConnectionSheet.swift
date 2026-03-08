import SwiftUI

struct ConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingProfile: ServerProfile?
    let onSave: (ServerProfile) -> Void

    @State private var name = ""
    @State private var kind: ServerProfile.Kind = .remote
    @State private var baseURL = "http://127.0.0.1:4096"
    @State private var username = "opencode"
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Form {
                Picker("Connection Type", selection: $kind) {
                    Text("Local Sidecar").tag(ServerProfile.Kind.localSidecar)
                    Text("Remote HTTP Server").tag(ServerProfile.Kind.remote)
                }

                TextField("Name", text: $name)
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Text(kind == .localSidecar ? "Kodanto will try this URL first, then launch `opencode serve` from your PATH." : "Use this for an already-running opencode server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(existingProfile == nil ? "Add" : "Save") {
                    let finalPassword: String?
                    if password.isEmpty {
                        finalPassword = nil
                    } else {
                        finalPassword = password
                    }

                    onSave(
                        ServerProfile(
                            id: existingProfile?.id ?? UUID(),
                            name: name.isEmpty ? defaultName : name,
                            kind: kind,
                            baseURL: baseURL,
                            username: username.isEmpty ? "opencode" : username,
                            password: finalPassword
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(width: 420)
        .padding()
        .onAppear {
            if let existingProfile {
                name = existingProfile.name
                kind = existingProfile.kind
                baseURL = existingProfile.baseURL
                username = existingProfile.username
                password = existingProfile.password ?? ""
            }
        }
    }

    private var defaultName: String {
        kind == .localSidecar ? "Local Sidecar" : "Remote Server"
    }
}
