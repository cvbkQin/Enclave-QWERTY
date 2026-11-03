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

    func testNonChatModelsAreRecognised() {
        XCTAssertEqual(ModelList.nonChatKind("text-embedding-v4"), "向量")
        XCTAssertEqual(ModelList.nonChatKind("gte-rerank-v2"), "重排")
        XCTAssertEqual(ModelList.nonChatKind("cosyvoice-v3"), "语音合成")
        XCTAssertEqual(ModelList.nonChatKind("paraformer-v2"), "语音识别")
        XCTAssertEqual(ModelList.nonChatKind("wanx2.1-t2i"), "画图")
        for chat in ["qwen-flash", "qwen3.5-plus", "deepseek-flash", "kimi-k3.1-pro", "glm-5-flash", "hy3", "qwq-plus"] {
            XCTAssertNil(ModelList.nonChatKind(chat), chat)
        }
    }

    func testWebSearchModels() {
        for ok in ["qwen-max", "qwen-plus", "qwen-flash", "qwen-plus-latest", "qwen3.5-plus", "qwen3.6-plus", "qwen3.5-max", "qwen4-flash"] {
            XCTAssertTrue(ModelList.supportsWebSearch(ok, provider: .qwen), ok)
        }
        for no in ["qwen-turbo", "qwen-long", "qwen3-max", "qwen2.5-72b-instruct", "qwq-plus", "deepseek-v3"] {
            XCTAssertFalse(ModelList.supportsWebSearch(no, provider: .qwen), no)
        }
        XCTAssertTrue(ModelList.supportsWebSearch("hy3-thinking", provider: .hunyuan))
        XCTAssertTrue(ModelList.supportsWebSearch("deepseek-v4-pro", provider: .hunyuan))
        XCTAssertFalse(ModelList.supportsWebSearch("hunyuan-lite", provider: .hunyuan))
        XCTAssertTrue(ModelList.supportsWebSearch("anything", provider: .glm))
        XCTAssertTrue(ModelList.filtersForWebSearch(EnclaveSettings.searchProvider(baseURL: "https://maas.qianwenaiapi.com/compatible-mode/v1")))
        XCTAssertFalse(ModelList.filtersForWebSearch(EnclaveSettings.searchProvider(baseURL: "https://api.moonshot.cn/v1")))
    }
}
