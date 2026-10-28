import XCTest

/// 失败分类（LLMFailure）和自动重试：超时、429、5xx 还没出字时重发一次；Key 无效、余额不足不重发。
final class LLMFailureTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(LLMFailure.of(LLMError.timeout(firstData: true)), .timeout)
        XCTAssertEqual(LLMFailure.of(LLMError.http(401, "")), .unauthorized)
        XCTAssertEqual(LLMFailure.of(LLMError.http(403, "")), .unauthorized)
        XCTAssertEqual(LLMFailure.of(LLMError.http(402, "")), .noBalance)
        XCTAssertEqual(LLMFailure.of(LLMError.http(429, "rate limit")), .rateLimited)
        // Kimi 余额不足回 429，按正文认。
        XCTAssertEqual(LLMFailure.of(LLMError.http(429, #"{"error":{"type":"exceeded_current_quota_error"}}"#)), .noBalance)
        XCTAssertEqual(LLMFailure.of(LLMError.http(503, "")), .server(503))
        XCTAssertEqual(LLMFailure.of(LLMError.http(400, "")), .other)
        XCTAssertEqual(LLMFailure.of(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(LLMFailure.of(URLError(.timedOut)), .timeout)
        XCTAssertEqual(LLMFailure.of(LLMError.notConfigured), .other)
    }

    func testAutoRetry() {
        XCTAssertTrue(LLMFailure.timeout.autoRetry)
        XCTAssertTrue(LLMFailure.rateLimited.autoRetry)
        XCTAssertTrue(LLMFailure.server(500).autoRetry)
        XCTAssertFalse(LLMFailure.network.autoRetry)
        XCTAssertFalse(LLMFailure.unauthorized.autoRetry)
        XCTAssertFalse(LLMFailure.noBalance.autoRetry)
        XCTAssertTrue(LLMFailure.unauthorized.needsSettings)
        XCTAssertFalse(LLMFailure.server(500).needsSettings)
    }

    func testDetail() {
        XCTAssertEqual(LLMFailure.detail(LLMError.http(401, "bad key"), provider: "DeepSeek"), "DeepSeek · HTTP 401\nbad key")
    }
}

final class LLMClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubProtocol.self)
        StubProtocol.reset()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubProtocol.self)
        super.tearDown()
    }

    private func client(_ base: String = "https://stub.test/v1") -> LLMClient {
        var settings = EnclaveSettings()
        settings.baseURL = base
        settings.model = "test-model"
        return LLMClient(settings: settings, apiKey: "sk-fake-test")
    }

    private func collect(_ client: LLMClient, retries: Int) async throws -> String {
        var text = ""
        for try await piece in client.stream([.user("hi")], retries: retries) { text += piece }
        return text
    }

    func testEndpoint() throws {
        XCTAssertEqual(try client("https://api.deepseek.com/v1/").endpoint().absoluteString, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(try client("https://x.com/v1/chat/completions").endpoint().absoluteString, "https://x.com/v1/chat/completions")
        XCTAssertThrowsError(try client("nope").endpoint())
    }

    func testFirstDataLimit() {
        XCTAssertEqual(client("http://192.168.1.2:11434/v1").firstDataLimit, 45)
        XCTAssertEqual(client("https://api.deepseek.com/v1").firstDataLimit, 20)
    }

    func testStreamsText() async throws {
        StubProtocol.responses = [.sse(["你", "好"])]
        let text = try await collect(client(), retries: 1)
        XCTAssertEqual(text, "你好")
        XCTAssertEqual(StubProtocol.requestCount, 1)
        XCTAssertEqual(StubProtocol.lastAuthorization, "Bearer sk-fake-test")
    }

    /// 5xx 还没出字：重发一次后成功。
    func testRetriesServerErrorOnce() async throws {
        StubProtocol.responses = [.status(503, "busy"), .sse(["好"])]
        let text = try await collect(client(), retries: 1)
        XCTAssertEqual(text, "好")
        XCTAssertEqual(StubProtocol.requestCount, 2)
    }

    /// Key 无效不重发，直接报错。
    func testDoesNotRetryUnauthorized() async {
        StubProtocol.responses = [.status(401, "invalid key"), .sse(["好"])]
        do {
            _ = try await collect(client(), retries: 1)
            XCTFail("应该报错")
        } catch {
            XCTAssertEqual(LLMFailure.of(error), .unauthorized)
        }
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }

    /// retries: 0（接口页「测试」）时 5xx 也不重发。
    func testNoRetryWhenDisabled() async {
        StubProtocol.responses = [.status(500, ""), .sse(["好"])]
        do {
            _ = try await collect(client(), retries: 0)
            XCTFail("应该报错")
        } catch {
            XCTAssertEqual(LLMFailure.of(error), .server(500))
        }
        XCTAssertEqual(StubProtocol.requestCount, 1)
    }
}

/// 假的服务端：按顺序回 responses 里的每一个。
final class StubProtocol: URLProtocol {
    enum Response {
        case status(Int, String)
        case sse([String])
    }

    private static let lock = NSLock()
    private static var _responses: [Response] = []
    private static var _count = 0
    private static var _authorization: String?

    static var responses: [Response] {
        get { lock.lock(); defer { lock.unlock() }; return _responses }
        set { lock.lock(); _responses = newValue; lock.unlock() }
    }
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return _count }
    static var lastAuthorization: String? { lock.lock(); defer { lock.unlock() }; return _authorization }

    static func reset() {
        lock.lock(); _responses = []; _count = 0; _authorization = nil; lock.unlock()
    }

    private static func next(_ request: URLRequest) -> Response {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        _authorization = request.value(forHTTPHeaderField: "Authorization")
        return _responses.isEmpty ? .status(500, "no stub") : _responses.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (code, type, body): (Int, String, String)
        switch Self.next(request) {
        case .status(let status, let text): (code, type, body) = (status, "application/json", text)
        case .sse(let pieces):
            let lines = pieces.map { piece -> String in
                let escaped = piece.replacingOccurrences(of: "\"", with: "\\\"")
                return #"data: {"choices":[{"delta":{"content":""# + escaped + #""}}]}"#
            }
            (code, type, body) = (200, "text/event-stream", (lines + ["data: [DONE]"]).joined(separator: "\n\n") + "\n\n")
        }
        let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
