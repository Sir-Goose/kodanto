import XCTest
@testable import kodanto

final class OpenCodeAPIClientPTYRequestTests: XCTestCase {
    func testPTYListRequestIncludesDirectoryQueryAndAuthHeader() throws {
        let client = makeClient()

        let request = try client.ptyListRequest(directory: "/tmp/project")

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/pty")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "directory")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "/tmp/project")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expectedAuthorization)
    }

    func testPTYUpdateRequestEncodesSizePayload() throws {
        let client = makeClient()

        let request = try client.ptyUpdateRequest(
            ptyID: "pty-123",
            directory: "/tmp/project",
            title: nil,
            rows: 24,
            cols: 80
        )

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/pty/pty-123")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let size = try XCTUnwrap(json["size"] as? [String: Any])
        XCTAssertEqual(size["rows"] as? Int, 24)
        XCTAssertEqual(size["cols"] as? Int, 80)
    }

    func testPTYCreateRequestEncodesShellAndCWD() throws {
        let client = makeClient()

        let request = try client.ptyCreateRequest(
            directory: "/tmp/project",
            title: "Terminal",
            cwd: "/tmp/project",
            command: "/bin/zsh",
            args: ["-l"]
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/pty")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Terminal")
        XCTAssertEqual(json["cwd"] as? String, "/tmp/project")
        XCTAssertEqual(json["command"] as? String, "/bin/zsh")
        XCTAssertEqual(json["args"] as? [String], ["-l"])
    }

    func testPTYConnectRequestUsesWebSocketSchemeWithAuthAndCursor() throws {
        let client = makeClient()

        let request = try client.ptyConnectRequest(ptyID: "pty-123", directory: "/tmp/project", cursor: 91)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(components.scheme, "ws")
        XCTAssertEqual(components.path, "/pty/pty-123/connect")
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "directory" })?.value, "/tmp/project")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "cursor" })?.value, "91")
        XCTAssertEqual(components.user, "opencode")
        XCTAssertEqual(components.password, "pw")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expectedAuthorization)
    }

    func testPTYCreateRequestOmitsShellFieldsWhenUnset() throws {
        let client = makeClient()
        let request = try client.ptyCreateRequest(
            directory: "/tmp/project",
            title: "Terminal",
            cwd: "/tmp/project",
            command: nil,
            args: nil
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Terminal")
        XCTAssertEqual(json["cwd"] as? String, "/tmp/project")
        XCTAssertNil(json["command"])
        XCTAssertNil(json["args"])
    }

    func testPTYConnectRequestUsesWSSForHTTPSBaseURL() throws {
        let client = OpenCodeAPIClient(
            profile: ServerProfile(
                name: "Secure",
                kind: .remote,
                baseURL: "https://example.com",
                username: "opencode",
                password: "pw"
            )
        )

        let request = try client.ptyConnectRequest(ptyID: "pty-123", directory: "/tmp/project", cursor: nil)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "wss")
    }

    private var expectedAuthorization: String {
        let value = Data("opencode:pw".utf8).base64EncodedString()
        return "Basic \(value)"
    }

    private func makeClient() -> OpenCodeAPIClient {
        OpenCodeAPIClient(
            profile: ServerProfile(
                name: "Test",
                kind: .remote,
                baseURL: "http://localhost:4096",
                username: "opencode",
                password: "pw"
            )
        )
    }
}
