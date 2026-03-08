import Foundation

struct OpenCodeSSEClient {
    let profile: ServerProfile

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

                    let decoder = JSONDecoder()
                    var buffer = ""

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        let normalized = line.replacingOccurrences(of: "\r", with: "")
                        if normalized.isEmpty {
                            try decodeEvent(from: buffer, decoder: decoder, continuation: continuation)
                            buffer.removeAll(keepingCapacity: true)
                            continue
                        }

                        buffer.append(normalized)
                        buffer.append("\n")
                    }

                    if !buffer.isEmpty {
                        try decodeEvent(from: buffer, decoder: decoder, continuation: continuation)
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

    private func decodeEvent(
        from rawEvent: String,
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<OpenCodeGlobalEvent, Error>.Continuation
    ) throws {
        let lines = rawEvent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        var dataLines: [String] = []

        for line in lines {
            if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }

        guard !dataLines.isEmpty else { return }
        let payload = dataLines.joined(separator: "\n")
        let data = Data(payload.utf8)
        let event = try decoder.decode(OpenCodeGlobalEvent.self, from: data)
        continuation.yield(event)
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
