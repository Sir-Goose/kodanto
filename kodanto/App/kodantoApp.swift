import SwiftUI
import AppIntents

@main
struct kodantoApp: App {
    private let isRunningTests: Bool
    @State private var model: KodantoAppModel?

    init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isRunningTests = isRunningTests
        _model = State(initialValue: isRunningTests ? nil : KodantoAppModel())
    }

    private var detectedBinaryPath: String {
        (try? SidecarProcess.executablePath()) ?? "Not found"
    }

    private var appModel: KodantoAppModel {
        guard let model else {
            fatalError("App model is unavailable while running tests.")
        }
        return model
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                EmptyView()
            } else {
                MainView(model: appModel)
                    .frame(minWidth: 1180, minHeight: 760)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            if !isRunningTests {
                CommandMenu("View") {
                    Button(appModel.isTerminalPanelOpen ? "Hide Terminal" : "Show Terminal") {
                        appModel.toggleTerminalPanel()
                    }
                    .keyboardShortcut("`", modifiers: [.control])
                    .disabled(!appModel.canShowTerminal)

                    Button("Connections...") {
                        appModel.showingConnectionsManager = true
                    }
                    .keyboardShortcut(",", modifiers: [.command, .shift])

                    Button("Diagnostics") {
                        appModel.showingDiagnostics = true
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }
            }
        }
        Settings {
            if isRunningTests {
                EmptyView()
            } else {
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
}
