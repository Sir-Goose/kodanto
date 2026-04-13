import Darwin
import Foundation

private struct ProviderAuth: Codable {
    let type: String?
    let key: String?
}

final class SidecarProcess {
    private(set) var process: Process?
    private(set) var outputHandler: ((String) -> Void)?
    private var outputPipe: Pipe?

    static func executablePath() throws -> String {
        try resolveExecutable().path
    }

    static func executableVersion() throws -> String {
        let output = try commandOutput(
            executableURL: resolveExecutable(),
            arguments: ["--version"]
        )
        return normalizedVersion(output)
    }

    static func versionsMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedVersion(lhs) == normalizedVersion(rhs)
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

        if let authKeys = try? Self.loadProviderAPIKeys() {
            for (key, value) in authKeys {
                environment[key] = value
            }
        }

        environment["OPENCODE_SERVER_USERNAME"] = profile.username
        if let password = profile.password, !password.isEmpty {
            environment["OPENCODE_SERVER_PASSWORD"] = password
        }
        environment["OPENCODE_CLIENT"] = "kodanto"
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        outputPipe = output
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

    func restart(profile: ServerProfile) async throws {
        guard profile.kind == .localSidecar else { return }
        stop()
        try await terminateExistingServer(profile: profile)
        try start(profile: profile)
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        outputPipe = nil
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

    private func terminateExistingServer(profile: ServerProfile) async throws {
        guard let port = profile.resolvedURL?.port else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        let targetPIDs = try Self.opencodeProcessIDsListening(on: port)
        guard !targetPIDs.isEmpty else { return }

        for pid in targetPIDs {
            _ = kill(pid, SIGTERM)
        }

        for _ in 0 ..< 20 {
            if try Self.opencodeProcessIDsListening(on: port).isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        for pid in try Self.opencodeProcessIDsListening(on: port) {
            _ = kill(pid, SIGKILL)
        }
    }

    private static func opencodeProcessIDsListening(on port: Int) throws -> [Int32] {
        let output = try commandOutput(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"],
            allowedTerminationStatuses: [0, 1]
        )

        var results: [Int32] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let pid = Int32(line) else { continue }
            if try isOpenCodeProcess(pid) {
                results.append(pid)
            }
        }
        return results
    }

    private static func isOpenCodeProcess(_ pid: Int32) throws -> Bool {
        let output = try commandOutput(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-p", String(pid), "-o", "command="],
            allowedTerminationStatuses: [0, 1]
        )
        return output.localizedCaseInsensitiveContains("opencode")
    }

    private static func normalizedVersion(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "version", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        let versionTokens = normalized
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .filter { !$0.isEmpty && $0.contains(".") }

        return versionTokens.first ?? normalized
    }

    private static func loadProviderAPIKeys() throws -> [String: String] {
        var keys: [String: String] = [:]
        let currentEnv = ProcessInfo.processInfo.environment

        if let authKeys = try? loadAuthJSONKeys() {
            keys.merge(authKeys) { _, new in new }
        }

        if let shellKeys = try? loadShellConfigKeys() {
            keys.merge(shellKeys) { _, new in new }
        }

        let knownProviderEnvVars = [
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
            "OPENAI_API_KEY_2",
            "OPENAI_API_KEY_3",
            "GOOGLE_GENERATIVE_AI_API_KEY",
            "GOOGLE_API_KEY",
            "AZURE_OPENAI_API_KEY",
            "MISTRAL_API_KEY",
            "GROQ_API_KEY",
            "OPENROUTER_API_KEY",
            "TOGETHER_API_KEY",
            "PERPLEXITY_API_KEY",
            "DEEPSEEK_API_KEY",
            "QWEN_API_KEY",
            "DASHSCOPE_API_KEY",
            "ALIBABA_API_KEY",
            "CLOUDEAI_API_KEY",
            "CROFAI_API_KEY",
            "MOONSHOT_API_KEY",
            "KIMI_API_KEY",
            "VERTEX_API_KEY",
            "GEMINI_API_KEY"
        ]

        for varName in knownProviderEnvVars {
            if let value = currentEnv[varName], !value.isEmpty {
                keys[varName] = value
            }
        }

        return keys
    }

    private static func loadShellConfigKeys() throws -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configFiles = [
            "\(home)/.zshrc",
            "\(home)/.bashrc",
            "\(home)/.zprofile",
            "\(home)/.bash_profile",
            "\(home)/.profile"
        ]

        var keys: [String: String] = [:]
        let knownVars = [
            "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "OPENAI_API_KEY_2", "OPENAI_API_KEY_3",
            "GOOGLE_GENERATIVE_AI_API_KEY", "GOOGLE_API_KEY", "AZURE_OPENAI_API_KEY",
            "MISTRAL_API_KEY", "GROQ_API_KEY", "OPENROUTER_API_KEY", "TOGETHER_API_KEY",
            "PERPLEXITY_API_KEY", "DEEPSEEK_API_KEY", "QWEN_API_KEY", "DASHSCOPE_API_KEY",
            "ALIBABA_API_KEY", "CLOUDEAI_API_KEY", "CROFAI_API_KEY", "MOONSHOT_API_KEY",
            "KIMI_API_KEY", "VERTEX_API_KEY", "GEMINI_API_KEY"
        ]

        for configPath in configFiles {
            guard FileManager.default.fileExists(atPath: configPath) else { continue }
            guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("export ") else { continue }
                let afterExport = String(trimmed.dropFirst(6))
                guard let range = afterExport.range(of: "=") else { continue }
                let varName = String(afterExport[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                guard knownVars.contains(varName) else { continue }
                var value = String(afterExport[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                } else if value.hasPrefix("'") && value.hasSuffix("'") {
                    value = String(value.dropFirst().dropLast())
                }
                if !value.isEmpty && keys[varName] == nil {
                    keys[varName] = value
                }
            }
        }

        return keys
    }

    private static func loadAuthJSONKeys() throws -> [String: String] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let authPath = "\(home)/.local/share/opencode/auth.json"

        guard fileManager.fileExists(atPath: authPath) else { return [:] }

        let data = try Data(contentsOf: URL(fileURLWithPath: authPath))
        guard let auth = try? JSONDecoder().decode([String: ProviderAuth].self, from: data) else {
            return [:]
        }

        var keys: [String: String] = [:]
        for (name, authInfo) in auth {
            if let key = authInfo.key {
                let envName = "\(name.uppercased().replacingOccurrences(of: "-", with: "_"))_API_KEY"
                keys[envName] = key
            }
        }

        return keys
    }

    private static func commandOutput(
        executableURL: URL,
        arguments: [String],
        allowedTerminationStatuses: Set<Int32> = [0]
    ) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard allowedTerminationStatuses.contains(process.terminationStatus) else {
            throw SidecarError.commandFailed(output.isEmpty ? executableURL.path : output)
        }

        return output
    }
}

enum SidecarError: LocalizedError {
    case opencodeNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .opencodeNotFound:
            return "Could not find `opencode` in PATH. Install it first or add it to your shell path."
        case let .commandFailed(output):
            return output
        }
    }
}