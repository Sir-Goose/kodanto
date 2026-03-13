import Foundation

struct OpenCodeAPIClient {
    let profile: ServerProfile

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    func health() async throws -> OpenCodeHealth {
        try await request(path: "/global/health")
    }

    func pathInfo(directory: String?) async throws -> OpenCodePathInfo {
        try await request(path: "/path", directory: directory)
    }

    func config(directory: String?) async throws -> OpenCodeConfig {
        try await request(path: "/config", directory: directory)
    }

    func configProviders(directory: String?) async throws -> OpenCodeConfigProviders {
        try await request(path: "/config/providers", directory: directory)
    }

    func agents() async throws -> [OpenCodeAgent] {
        try await request(path: "/agent")
    }

    func projects() async throws -> [OpenCodeProject] {
        try await request(path: "/project")
    }

    func sessions(directory: String) async throws -> [OpenCodeSession] {
        let request = try sessionListRequest(directory: directory)
        let data = try await requestData(for: request)
        return try decoder.decode([OpenCodeSession].self, from: data)
    }

    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] {
        let request = try sessionStatusRequest(directory: directory)
        let data = try await requestData(for: request)
        let map = try decoder.decode(OpenCodeSessionStatusMap.self, from: data)
        return map.values
    }

    func sessionTodos(sessionID: String, directory: String) async throws -> [OpenCodeTodo] {
        try await request(path: "/session/\(sessionID)/todo", directory: directory)
    }

    func permissions(directory: String) async throws -> [OpenCodePermissionRequest] {
        try await request(path: "/permission", directory: directory)
    }

    func questions(directory: String) async throws -> [OpenCodeQuestionRequest] {
        try await request(path: "/question", directory: directory)
    }

    func globalSSEClient() -> OpenCodeSSEClient {
        OpenCodeSSEClient(profile: profile)
    }

    func messages(sessionID: String, directory: String) async throws -> [OpenCodeMessageEnvelope] {
        try await request(path: "/session/\(sessionID)/message", directory: directory, queryItems: [
            URLQueryItem(name: "limit", value: "200")
        ])
    }

    func createSession(directory: String, title: String?) async throws -> OpenCodeSession {
        struct Body: Encodable {
            let title: String?
        }

        return try await request(
            path: "/session",
            method: "POST",
            directory: directory,
            body: AnyEncodable(Body(title: title))
        )
    }

    func updateSession(
        sessionID: String,
        directory: String,
        title: String?,
        archivedAt: Double?
    ) async throws -> OpenCodeSession {
        struct Body: Encodable {
            struct Time: Encodable {
                let archived: Double?
            }

            let title: String?
            let time: Time?
        }

        return try await patchSession(
            sessionID: sessionID,
            directory: directory,
            body: Body(
                title: title,
                time: archivedAt.map { Body.Time(archived: $0) }
            )
        )
    }

    func initializeGitRepository(directory: String) async throws -> OpenCodeProject {
        try await request(
            path: "/project/git/init",
            method: "POST",
            directory: directory
        )
    }

    func ptySessions(directory: String) async throws -> [OpenCodePTY] {
        let request = try ptyListRequest(directory: directory)
        let data = try await requestData(for: request)
        return try decoder.decode([OpenCodePTY].self, from: data)
    }

    func ptySession(ptyID: String, directory: String) async throws -> OpenCodePTY {
        let request = try ptyGetRequest(ptyID: ptyID, directory: directory)
        let data = try await requestData(for: request)
        return try decoder.decode(OpenCodePTY.self, from: data)
    }

    func createPTY(
        directory: String,
        title: String?,
        cwd: String?,
        command: String?,
        args: [String]?
    ) async throws -> OpenCodePTY {
        let request = try ptyCreateRequest(
            directory: directory,
            title: title,
            cwd: cwd,
            command: command,
            args: args
        )
        let data = try await requestData(for: request)
        return try decoder.decode(OpenCodePTY.self, from: data)
    }

    func updatePTY(
        ptyID: String,
        directory: String,
        title: String?,
        rows: Int?,
        cols: Int?
    ) async throws -> OpenCodePTY {
        let request = try ptyUpdateRequest(
            ptyID: ptyID,
            directory: directory,
            title: title,
            rows: rows,
            cols: cols
        )
        let data = try await requestData(for: request)
        return try decoder.decode(OpenCodePTY.self, from: data)
    }

    func removePTY(ptyID: String, directory: String) async throws {
        let request = try ptyDeleteRequest(ptyID: ptyID, directory: directory)
        _ = try await requestData(for: request)
    }

    func sendPrompt(
        sessionID: String,
        directory: String,
        text: String,
        model: PromptRequestBody.ModelSelection?,
        agent: String?,
        variant: String?
    ) async throws {
        try await requestNoContent(
            path: "/session/\(sessionID)/prompt_async",
            method: "POST",
            directory: directory,
            body: AnyEncodable(PromptRequestBody(model: model, agent: agent, variant: variant, parts: [.init(type: "text", text: text)]))
        )
    }

    func replyToPermission(requestID: String, directory: String, reply: String) async throws {
        try await requestNoContent(
            path: "/permission/\(requestID)/reply",
            method: "POST",
            directory: directory,
            body: AnyEncodable(PermissionReplyBody(reply: reply, message: nil))
        )
    }

    func replyToQuestion(requestID: String, directory: String, answers: [[String]]) async throws {
        try await requestNoContent(
            path: "/question/\(requestID)/reply",
            method: "POST",
            directory: directory,
            body: AnyEncodable(QuestionReplyBody(answers: answers))
        )
    }

    func rejectQuestion(requestID: String, directory: String) async throws {
        _ = try await requestNoContent(path: "/question/\(requestID)/reject", method: "POST", directory: directory)
    }

    func ptyListRequest(directory: String) throws -> URLRequest {
        try makeRequest(path: "/pty", method: "GET", queryItems: [URLQueryItem(name: "directory", value: directory)])
    }

    func sessionListRequest(directory: String) throws -> URLRequest {
        try makeRequest(path: "/session", method: "GET", directory: directory, queryItems: [
            URLQueryItem(name: "roots", value: "true"),
            URLQueryItem(name: "limit", value: "100")
        ])
    }

    func sessionStatusRequest(directory: String) throws -> URLRequest {
        try makeRequest(path: "/session/status", method: "GET", directory: directory)
    }

    func ptyCreateRequest(
        directory: String,
        title: String?,
        cwd: String?,
        command: String?,
        args: [String]?
    ) throws -> URLRequest {
        struct Body: Encodable {
            let command: String?
            let args: [String]?
            let cwd: String?
            let title: String?
        }

        return try makeRequest(
            path: "/pty",
            method: "POST",
            queryItems: [URLQueryItem(name: "directory", value: directory)],
            body: AnyEncodable(Body(command: command, args: args, cwd: cwd, title: title))
        )
    }

    func ptyGetRequest(ptyID: String, directory: String) throws -> URLRequest {
        try makeRequest(
            path: "/pty/\(ptyID)",
            method: "GET",
            queryItems: [URLQueryItem(name: "directory", value: directory)]
        )
    }

    func ptyUpdateRequest(
        ptyID: String,
        directory: String,
        title: String?,
        rows: Int?,
        cols: Int?
    ) throws -> URLRequest {
        struct Body: Encodable {
            struct Size: Encodable {
                let rows: Int
                let cols: Int
            }

            let title: String?
            let size: Size?
        }

        let resolvedSize: Body.Size?
        if let rows, let cols {
            resolvedSize = Body.Size(rows: rows, cols: cols)
        } else {
            resolvedSize = nil
        }

        return try makeRequest(
            path: "/pty/\(ptyID)",
            method: "PUT",
            queryItems: [URLQueryItem(name: "directory", value: directory)],
            body: AnyEncodable(Body(title: title, size: resolvedSize))
        )
    }

    func ptyDeleteRequest(ptyID: String, directory: String) throws -> URLRequest {
        try makeRequest(
            path: "/pty/\(ptyID)",
            method: "DELETE",
            queryItems: [URLQueryItem(name: "directory", value: directory)]
        )
    }

    func ptyConnectRequest(ptyID: String, directory: String, cursor: Int?) throws -> URLRequest {
        var queryItems = [URLQueryItem(name: "directory", value: directory)]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: String(cursor)))
        }

        var request = try makeRequest(
            path: "/pty/\(ptyID)/connect",
            method: "GET",
            queryItems: queryItems
        )

        guard let originalURL = request.url,
              var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        else {
            return request
        }

        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        default:
            components.scheme = "ws"
        }

        // Keep URL credentials for websocket servers that ignore Authorization header.
        components.user = profile.username
        components.password = profile.password

        if let wsURL = components.url {
            request.url = wsURL
        }

        return request
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        directory: String? = nil,
        queryItems: [URLQueryItem] = [],
        body: AnyEncodable? = nil
    ) async throws -> T {
        let data = try await requestData(path: path, method: method, directory: directory, queryItems: queryItems, body: body)
        return try decoder.decode(T.self, from: data)
    }

    private func requestNoContent(
        path: String,
        method: String = "GET",
        directory: String? = nil,
        queryItems: [URLQueryItem] = [],
        body: AnyEncodable? = nil
    ) async throws {
        _ = try await requestData(path: path, method: method, directory: directory, queryItems: queryItems, body: body)
    }

    private func requestData(
        path: String,
        method: String,
        directory: String?,
        queryItems: [URLQueryItem],
        body: AnyEncodable?
    ) async throws -> Data {
        let request = try makeRequest(path: path, method: method, directory: directory, queryItems: queryItems, body: body)
        return try await requestData(for: request)
    }

    private func requestData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeAPIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenCodeAPIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    private func patchSession<T: Encodable>(
        sessionID: String,
        directory: String,
        body: T
    ) async throws -> OpenCodeSession {
        try await request(
            path: "/session/\(sessionID)",
            method: "PATCH",
            directory: directory,
            body: AnyEncodable(body)
        )
    }

    private func makeRequest(
        path: String,
        method: String,
        directory: String? = nil,
        queryItems: [URLQueryItem] = [],
        body: AnyEncodable? = nil
    ) throws -> URLRequest {
        guard let baseURL = profile.resolvedURL else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        var resolvedQueryItems = queryItems
        if let directory, !directory.isEmpty,
           !resolvedQueryItems.contains(where: { $0.name == "directory" }) {
            resolvedQueryItems.append(URLQueryItem(name: "directory", value: directory))
        }
        components.queryItems = resolvedQueryItems.isEmpty ? nil : resolvedQueryItems

        guard let url = components.url else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let directory, !directory.isEmpty {
            request.setValue(directory, forHTTPHeaderField: "x-opencode-directory")
        }

        if let password = profile.password, !password.isEmpty {
            let credentials = "\(profile.username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        return request
    }
}

enum OpenCodeAPIError: LocalizedError {
    case invalidBaseURL(String)
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid server URL: \(value)"
        case .invalidResponse:
            return "The server returned an invalid response."
        case .serverError(_, let message):
            return message
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        encodeImpl = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}
