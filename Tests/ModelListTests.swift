import XCTest

/// 接口页「选择」模型：列表地址、解析、排序。
final class ModelListTests: XCTestCase {
    func testURL() {
        XCTAssertEqual(ModelList.url(baseURL: "https://api.deepseek.com/v1")?.absoluteString, "https://api.deepseek.com/v1/models")
        XCTAssertEqual(ModelList.url(baseURL: " https://api.deepseek.com/v1/ ")?.absoluteString, "https://api.deepseek.com/v1/models")
        XCTAssertEqual(ModelList.url(baseURL: "https://x.com/v1/chat/completions")?.absoluteString, "https://x.com/v1/models")
        XCTAssertEqual(ModelList.url(baseURL: "http://192.168.1.100:11434/v1")?.absoluteString, "http://192.168.1.100:11434/api/tags")
        XCTAssertNil(ModelList.url(baseURL: "not a url"))
    }

    func testParseOpenAI() {
        let json = #"{"object":"list","data":[{"id":"deepseek-chat"},{"id":"deepseek-reasoner"},{"id":"deepseek-chat"}]}"#
        XCTAssertEqual(ModelList.parse(Data(json.utf8)), ["deepseek-chat", "deepseek-reasoner"])
    }

    func testParseOllama() {
        let json = #"{"models":[{"name":"qwen2.5:7b","model":"qwen2.5:7b"},{"name":"llama3:8b"}]}"#
        XCTAssertEqual(ModelList.parse(Data(json.utf8)), ["qwen2.5:7b", "llama3:8b"])
    }

    func testParseGarbage() {
        XCTAssertEqual(ModelList.parse(Data("<html>".utf8)), [])
    }

    func testOrderedPutsCurrentFirst() {
        XCTAssertEqual(ModelList.ordered(["a", "b", "c"], current: "c"), ["c", "a", "b"])
        XCTAssertEqual(ModelList.ordered(["a", "b"], current: "x"), ["a", "b"])
    }

    func testThinking() {
        XCTAssertTrue(ModelList.isThinking("deepseek-reasoner"))
        XCTAssertTrue(ModelList.isThinking("kimi-k2-Thinking"))
        XCTAssertFalse(ModelList.isThinking("qwen-plus"))
    }
}
