import XCTest

/// AI 页的最近 20 次（第 51 条）：旧数据照常解码，失败原因按错误分类。
final class RecentRequestsTests: XCTestCase {
    func testOldRequestDecodes() throws {
        let json = #"[{"ms":820,"ok":true,"at":700000000},{"ms":15000,"ok":false,"at":700000100}]"#
        let requests = try JSONDecoder().decode([UsageStats.Request].self, from: Data(json.utf8))
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].model)
        XCTAssertNil(requests[1].error)
        XCTAssertFalse(requests[0].slow)
    }

    func testFailureKinds() {
        XCTAssertEqual(UsageStats.Request.Failure.of(LLMError.http(401, "")), UsageStats.Request.Failure.unauthorized)
        XCTAssertEqual(UsageStats.Request.Failure.of(LLMError.http(402, "")), UsageStats.Request.Failure.noBalance)
        XCTAssertEqual(UsageStats.Request.Failure.of(LLMError.http(503, "")), UsageStats.Request.Failure.server)
        XCTAssertEqual(UsageStats.Request.Failure.of(LLMError.timeout(firstData: true)), UsageStats.Request.Failure.timeout)
        XCTAssertEqual(UsageStats.Request.Failure.of(URLError(.notConnectedToInternet)), UsageStats.Request.Failure.network)
        let slow = UsageStats.Request(ms: 3600, ok: true, at: Date())
        XCTAssertTrue(slow.slow)
        XCTAssertEqual(UsageStats.recentLimit, 20)
    }
}
