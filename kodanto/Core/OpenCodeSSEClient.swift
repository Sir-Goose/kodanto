import Foundation

struct OpenCodeSSEClient {
    let profile: ServerProfile

    struct EventParser {
        private let decoder = JSONDecoder()
        private var buffer = ""

        mutating func push(line: String) throws -> [OpenCodeGlobalEvent] {
            let normalized = line.replacingOccurrences(of: "\r", with: "")

            if normalized.isEmpty {
                return try flush(strict: true)
            }

            guard normalized.hasPrefix(":") == false else {
                return []
            }

            guard normalized.hasPrefix("data:") else {
                return []
            }

            let payload = String(normalized.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if !buffer.isEmpty {
                buffer.append("\n")
            }
            buffer.append(payload)

            return try flush(strict: false)
        }

        mutating func finish() throws -> [OpenCodeGlobalEvent] {
            try flush(strict: true)
        }

        private mutating func flush(strict: Bool) throws -> [OpenCodeGlobalEvent] {
            guard !buffer.isEmpty else { return [] }

            do {
                let data = Data(buffer.utf8)
                let event = try decoder.decode(OpenCodeGlobalEvent.self, from: data)
                buffer.removeAll(keepingCapacity: true)
                return [event]
            } catch {
                if strict {
                    throw error
                }
                return []
            }
        }
    }

    func streamGlobalEvents() -> AsyncThrowingStream<OpenCodeGlobalEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(path: "/global/event")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenCodeAPIError.invalidResponse
                    }

                    guard (200 ... 299).contains(httpResponse.statusCode) else {
                        throw OpenCodeAPIError.serverError(
                            statusCode: httpResponse.statusCode,
                            message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                        )
                    }

                    var parser = EventParser()

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        for event in try parser.push(line: line) {
                            continuation.yield(event)
                        }
                    }

                    for event in try parser.finish() {
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let baseURL = profile.resolvedURL else {
            throw OpenCodeAPIError.invalidBaseURL(profile.baseURL)
        }

        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60 * 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        if let password = profile.password, !password.isEmpty {
            let credentials = "\(profile.username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        return request
    }
}
