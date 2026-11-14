// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

/// Pretends to be the Mac bridge. Routes by path and can walk a job through several states.
private final class FakeBridge: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [URLRequest] = []
    private var statusReplies: [HTTPResponse] = []
    var routes: [String: HTTPResponse] = [:]
    var failWith: Error?

    var sent: [URLRequest] { lock.withLock { _sent } }

    func queueStatus(_ json: String) {
        lock.withLock { statusReplies.append(HTTPResponse(status: 200, body: Data(json.utf8))) }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.withLock { _sent.append(request) }
        if let failWith { throw failWith }
        let path = request.url?.path ?? ""
        if path == "/jobs/job1", request.httpMethod == "GET" {
            let next: HTTPResponse? = lock.withLock {
                statusReplies.count > 1 ? statusReplies.removeFirst() : statusReplies.first
            }
            if let next { return next }
        }
        return routes[path] ?? HTTPResponse(status: 404, body: Data())
    }
}

private func body(_ text: String) -> HTTPResponse { HTTPResponse(status: 200, body: Data(text.utf8)) }

final class NihonSubClientTests: XCTestCase {
    private let srt = """
    1
    00:00:01,000 --> 00:00:02,500
    Hello there.

    2
    00:00:03,000 --> 00:00:04,000
    Second line.

    """

    func testAddressAndTokenAreCleanedUp() {
        let bridge = FakeBridge()
        XCTAssertEqual(NihonSubClient(address: " 192.168.1.20:3100/ ", token: " abc \n", transport: bridge)?.baseURL.absoluteString,
                       "http://192.168.1.20:3100")
        XCTAssertEqual(NihonSubClient(address: "https://mac.local:3100", token: "t", transport: bridge)?.baseURL.absoluteString,
                       "https://mac.local:3100")
        XCTAssertEqual(NihonSubClient(address: "my-mac.local:3100", token: "abc", transport: bridge)?.token, "abc")
        XCTAssertNil(NihonSubClient(address: "", token: "abc", transport: bridge))
        XCTAssertNil(NihonSubClient(address: "192.168.1.20:3100", token: "  ", transport: bridge))
        XCTAssertNil(NihonSubClient(address: "ftp://192.168.1.20", token: "abc", transport: bridge))
    }

    func testVerifyAcceptsAReadyBridgeAndSendsTheToken() async throws {
        let bridge = FakeBridge()
        bridge.routes["/health"] = body(#"{"ok":true,"ffmpeg":true,"nihonsub":true,"configured":true}"#)
        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))
        try await client.verify()
        XCTAssertEqual(bridge.sent.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(bridge.sent.first?.url?.absoluteString, "http://mac.local:3100/health")
    }

    func testVerifyExplainsWhatIsMissing() async throws {
        let bridge = FakeBridge()
        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))

        bridge.routes["/health"] = body(#"{"ok":true,"ffmpeg":false,"nihonsub":true,"configured":true}"#)
        await assertThrows(client, .ffmpegMissing) { try await $0.verify() }

        bridge.routes["/health"] = body(#"{"ok":true,"ffmpeg":true,"nihonsub":false,"configured":false}"#)
        await assertThrows(client, .nihonSubNotRunning) { try await $0.verify() }

        bridge.routes["/health"] = body(#"{"ok":true,"ffmpeg":true,"nihonsub":true,"configured":false}"#)
        await assertThrows(client, .needsGroqKey) { try await $0.verify() }

        bridge.routes["/health"] = HTTPResponse(status: 401, body: Data(#"{"error":"nope"}"#.utf8))
        await assertThrows(client, .wrongToken) { try await $0.verify() }

        bridge.routes["/health"] = body("not json")
        await assertThrows(client, .invalidResponse) { try await $0.verify() }
    }

    func testUnreachableBridgeNamesTheAddress() async throws {
        let bridge = FakeBridge()
        bridge.failWith = URLError(.cannotConnectToHost)
        let client = try XCTUnwrap(NihonSubClient(address: "192.168.1.20:3100", token: "secret", transport: bridge))
        await assertThrows(client, .unreachable("192.168.1.20:3100")) { try await $0.verify() }
    }

    func testStartSendsTheStreamLinkLanguageAndHeaders() async throws {
        let bridge = FakeBridge()
        bridge.routes["/jobs"] = HTTPResponse(status: 202, body: Data(#"{"id":"job1"}"#.utf8))
        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))
        let id = try await client.start(url: URL(string: "https://cdn.example/video.mkv")!,
                                        headers: ["Cookie": "a=b"], language: .hinglish)
        XCTAssertEqual(id, "job1")

        let request = try XCTUnwrap(bridge.sent.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(sent["url"] as? String, "https://cdn.example/video.mkv")
        XCTAssertEqual(sent["language"] as? String, "hinglish")
        XCTAssertEqual((sent["headers"] as? [String: String])?["Cookie"], "a=b")
    }

    func testStartLeavesOutEmptyHeaders() async throws {
        let bridge = FakeBridge()
        bridge.routes["/jobs"] = HTTPResponse(status: 202, body: Data(#"{"id":"job1"}"#.utf8))
        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))
        _ = try await client.start(url: URL(string: "https://cdn.example/v.mp4")!, headers: [:], language: .english)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(bridge.sent.first?.httpBody)) as? [String: Any])
        XCTAssertNil(sent["headers"])
        XCTAssertEqual(sent["language"] as? String, "en")
    }

    func testGenerateFollowsProgressAndReturnsCues() async throws {
        let bridge = FakeBridge()
        bridge.routes["/jobs"] = HTTPResponse(status: 202, body: Data(#"{"id":"job1"}"#.utf8))
        bridge.routes["/jobs/job1/srt"] = body(srt)
        bridge.queueStatus(#"{"id":"job1","state":"extracting","percent":5,"message":"Reading the audio"}"#)
        bridge.queueStatus(#"{"id":"job1","state":"transcribing","percent":40,"message":"Listening"}"#)
        bridge.queueStatus(#"{"id":"job1","state":"done","percent":100,"message":"Done"}"#)

        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))
        let seen = Seen()
        let cues = try await client.generate(url: URL(string: "https://cdn.example/v.mkv")!, headers: nil,
                                             language: .english, pollEvery: 0.01) { status in
            seen.add(status.percent)
        }
        XCTAssertEqual(seen.values, [5, 40, 100])
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues.first?.text, "Hello there.")
    }

    func testGenerateReportsAFailedJob() async throws {
        let bridge = FakeBridge()
        bridge.routes["/jobs"] = HTTPResponse(status: 202, body: Data(#"{"id":"job1"}"#.utf8))
        bridge.queueStatus(#"{"id":"job1","state":"failed","percent":10,"message":"","error":"Groq said no"}"#)
        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))
        do {
            _ = try await client.generate(url: URL(string: "https://cdn.example/v.mkv")!, headers: nil,
                                          language: .english, pollEvery: 0.01)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NihonSubError, .failed("Groq said no"))
        }
    }

    func testGenerateGivesUpWhenTheBridgeForgetsTheJob() async throws {
        let bridge = FakeBridge()
        bridge.routes["/jobs"] = HTTPResponse(status: 202, body: Data(#"{"id":"job1"}"#.utf8))
        // No status route, so /jobs/job1 answers 404.
        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))
        do {
            _ = try await client.generate(url: URL(string: "https://cdn.example/v.mkv")!, headers: nil,
                                          language: .english, pollEvery: 0.01)
            XCTFail("expected lostJob")
        } catch {
            XCTAssertEqual(error as? NihonSubError, .lostJob)
        }
    }

    func testBridgeErrorMessageIsPassedOn() async throws {
        let bridge = FakeBridge()
        bridge.routes["/jobs"] = HTTPResponse(status: 400, body: Data(#"{"error":"Only http and https links."}"#.utf8))
        let client = try XCTUnwrap(NihonSubClient(address: "mac.local:3100", token: "secret", transport: bridge))
        do {
            _ = try await client.start(url: URL(string: "https://cdn.example/v.mkv")!, headers: nil, language: .english)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NihonSubError, .failed("Only http and https links."))
        }
    }

    func testLanguageCodes() {
        XCTAssertEqual(NihonSubClient.Language.english.trackLanguageCode, "en")
        XCTAssertEqual(NihonSubClient.Language.hindi.trackLanguageCode, "hi")
        XCTAssertEqual(NihonSubClient.Language.hinglish.trackLanguageCode, "hi")
        XCTAssertEqual(NihonSubClient.Language.allCases.map(\.displayName), ["English", "Hindi", "Hinglish"])
    }

    // MARK: Helpers

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Int] = []
        func add(_ value: Int) { lock.withLock { items.append(value) } }
        var values: [Int] { lock.withLock { items } }
    }

    private func assertThrows(
        _ client: NihonSubClient,
        _ expected: NihonSubError,
        _ work: (NihonSubClient) async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await work(client)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? NihonSubError, expected, file: file, line: line)
        }
    }
}
