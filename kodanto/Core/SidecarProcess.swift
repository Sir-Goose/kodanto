import Foundation

final class SidecarProcess {
    private(set) var process: Process?
    private(set) var outputHandler: ((String) -> Void)?

    static func executablePath() throws -> String {
        try resolveExecutable().path
    }

    func start(profile: ServerProfile) throws {
        guard profile.kind == .localSidecar else { return }
        guard process == nil || process?.isRunning == false else { return }
        guard let baseURL = profile.resolvedURL, let host = baseURL.host, let port = baseURL.port else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        let executable = try Self.resolveExecutable()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve", "--hostname", host, "--port", String(port)]

        var environment = ProcessInfo.processInfo.environment
        environment["OPENCODE_SERVER_USERNAME"] = profile.username
        if let password = profile.password, !password.isEmpty {
            environment["OPENCODE_SERVER_PASSWORD"] = password
        }
        environment["OPENCODE_CLIENT"] = "kodanto"
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.outputHandler?(string)
            }
        }

        try process.run()
        self.process = process
    }

    func stop() {
        outputHandler = nil
        process?.terminate()
        process = nil
    }

    func setOutputHandler(_ handler: @escaping (String) -> Void) {
        outputHandler = handler
    }

    private static func resolveExecutable() throws -> URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path

        let candidates = [
            ProcessInfo.processInfo.environment["OPENCODE_BINARY"],
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            "\(home)/.opencode/bin/opencode",
            "\(home)/.local/bin/opencode",
            "\(home)/bin/opencode"
        ].compactMap { $0 }

        for path in candidates {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for component in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(component)).appendingPathComponent("opencode")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw SidecarError.opencodeNotFound
    }
}

enum SidecarError: LocalizedError {
    case opencodeNotFound

    var errorDescription: String? {
        switch self {
        case .opencodeNotFound:
            return "Could not find `opencode` in PATH. Install it first or add it to your shell path."
        }
    }
}
