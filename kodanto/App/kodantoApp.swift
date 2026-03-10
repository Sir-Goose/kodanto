import SwiftUI

@main
struct kodantoApp: App {
    @State private var model = KodantoAppModel()

    private var detectedBinaryPath: String {
        (try? SidecarProcess.executablePath()) ?? "Not found"
    }

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("View") {
                Button("Connections...") {
                    model.showingConnectionsManager = true
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])

                Button("Diagnostics") {
                    model.showingDiagnostics = true
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            Form {
                Section("About") {
                    Text("kodanto is a native macOS frontend for opencode.")
                    Text("It assumes a user-installed `opencode` binary and talks to the server protocol directly.")
                        .foregroundStyle(.secondary)
                }

                Section("Runtime") {
                    LabeledContent("Detected opencode") {
                        Text(detectedBinaryPath)
                            .textSelection(.enabled)
                    }
                    Text("App Sandbox is disabled so kodanto can launch your installed `opencode` binary directly.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(width: 420)
        }
    }
}
