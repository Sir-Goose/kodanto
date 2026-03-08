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

    func projects() async throws -> [OpenCodeProject] {
        try await request(path: "/project")
    }

    func sessions(directory: String) async throws -> [OpenCodeSession] {
        try await request(path: "/session", directory: directory, queryItems: [
            URLQueryItem(name: "roots", value: "true"),
            URLQueryItem(name: "limit", value: "100")
        ])
    }

    func sessionStatuses(directory: String) async throws -> [String: OpenCodeSessionStatus] {
        let map: OpenCodeSessionStatusMap = try await request(path: "/session/status", directory: directory)
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

    func sendPrompt(sessionID: String, directory: String, text: String) async throws {
        try await requestNoContent(
            path: "/session/\(sessionID)/prompt_async",
            method: "POST",
            directory: directory,
            body: AnyEncodable(PromptRequestBody(parts: [.init(type: "text", text: text)]))
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

    private func makeRequest(
        path: String,
        method: String,
        directory: String?,
        queryItems: [URLQueryItem],
        body: AnyEncodable?
    ) throws -> URLRequest {
        guard let baseURL = profile.resolvedURL else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

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
