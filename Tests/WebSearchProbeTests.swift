import XCTest

/// 「测试联网」看返回判断能不能联网。
final class WebSearchProbeTests: XCTestCase {
    /// 2026-11-03 10:00 北京时间。
    private let now = Date(timeIntervalSince1970: 1_793_671_200)

    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testZhipuWebSearchField() {
        let body = #"{"choices":[{"message":{"content":"上海今天多云。"}}],"web_search":[{"title":"上海天气","link":"https://x"}]}"#
        XCTAssertEqual(WebSearchProbe.verdict(provider: .glm, response: json(body), now: now), .online)
    }

    func testQwenSearchInfo() {
        let body = #"{"choices":[{"message":{"content":"多云。"}}],"search_info":{"search_results":[{"title":"t"}]}}"#
        XCTAssertEqual(WebSearchProbe.verdict(provider: .qwen, response: json(body), now: now), .online)
    }

    func testEmptySearchFieldDoesNotCount() {
        let body = #"{"choices":[{"message":{"content":"我无法获取实时信息。"}}],"web_search":[]}"#
        XCTAssertEqual(WebSearchProbe.verdict(provider: .glm, response: json(body), now: now), .offline)
    }

    func testFallsBackToTodaysDate() {
        let online = #"{"choices":[{"message":{"content":"今天是 11 月 3 日，上海多云，18 度。"}}]}"#
        XCTAssertEqual(WebSearchProbe.verdict(provider: .hunyuan, response: json(online), now: now), .online)
        let offline = #"{"choices":[{"message":{"content":"抱歉，我无法获取今天的日期和实时天气。"}}]}"#
        XCTAssertEqual(WebSearchProbe.verdict(provider: .hunyuan, response: json(offline), now: now), .offline)
    }

    func testThinkingIsIgnored() {
        let body = #"{"choices":[{"message":{"content":"<think>大概是11月3日</think>我不知道今天几号。"}}]}"#
        XCTAssertEqual(WebSearchProbe.verdict(provider: .qwen, response: json(body), now: now), .offline)
    }

    func testDateFormats() {
        XCTAssertTrue(WebSearchProbe.mentionsDate("2026-11-03 上海晴", now))
        XCTAssertTrue(WebSearchProbe.mentionsDate("Today is Nov 3, sunny", now))
        XCTAssertTrue(WebSearchProbe.mentionsDate("11月3号", now))
        XCTAssertFalse(WebSearchProbe.mentionsDate("11月4日", now))
    }

    func testStoreByURLAndModel() {
        let url = "https://example-probe.test/v1/"
        WebSearchProbe.store(.online, baseURL: url, model: "m1")
        XCTAssertEqual(WebSearchProbe.stored(baseURL: "https://example-probe.test/v1", model: "m1"), .online)
        XCTAssertNil(WebSearchProbe.stored(baseURL: url, model: "m2"))
    }
}
