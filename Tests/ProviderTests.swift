import XCTest

/// 服务商预设：中国大陆店面和其他地区填不同的地址，认得出现有设置。
final class ProviderTests: XCTestCase {
    private let key = "storefront.country"
    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: key)
        super.tearDown()
    }

    private func storefront(_ code: String?) { UserDefaults.standard.set(code, forKey: key) }

    func testMainlandPresets() {
        storefront("CHN")
        XCTAssertTrue(Storefront.isMainlandChina)
        XCTAssertEqual(Provider.kimi.preset?.baseURL, "https://api.moonshot.cn/v1")
        XCTAssertEqual(Provider.qwen.preset?.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(Provider.glm.preset?.baseURL, "https://open.bigmodel.cn/api/paas/v4")
        XCTAssertEqual(Provider.deepseek.preset?.baseURL, "https://api.deepseek.com/v1")
    }

    func testGlobalPresets() {
        storefront("USA")
        XCTAssertFalse(Storefront.isMainlandChina)
        XCTAssertEqual(Provider.kimi.preset?.baseURL, "https://api.moonshot.ai/v1")
        XCTAssertEqual(Provider.qwen.preset?.baseURL, "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(Provider.glm.preset?.baseURL, "https://api.z.ai/api/paas/v4")
        // 没读到过店面按非大陆。
        storefront(nil)
        XCTAssertEqual(Provider.kimi.preset?.baseURL, "https://api.moonshot.ai/v1")
    }

    /// 问答页 Kimi 用 K3，润色用高速版。
    func testAnswerPreset() {
        XCTAssertEqual(Provider.kimi.answerPreset?.model, Provider.kimiAnswerModel)
        XCTAssertNotEqual(Provider.kimi.preset?.model, Provider.kimiAnswerModel)
        XCTAssertEqual(Provider.qwen.answerPreset?.model, Provider.qwen.preset?.model)
        XCTAssertNil(Provider.custom.preset)
    }

    func testDetect() {
        XCTAssertEqual(Provider.detect("https://api.deepseek.com/v1"), .deepseek)
        XCTAssertEqual(Provider.detect("https://api.moonshot.ai/v1"), .kimi)
        XCTAssertEqual(Provider.detect("https://dashscope-intl.aliyuncs.com/compatible-mode/v1"), .qwen)
        XCTAssertEqual(Provider.detect("https://api.z.ai/api/paas/v4"), .glm)
        XCTAssertEqual(Provider.detect("http://192.168.1.5:11434/v1"), .ollama)
        XCTAssertEqual(Provider.detect("https://example.com/v1"), .custom)
        XCTAssertEqual(ProviderName.of("https://example.com/v1"), "example.com")
    }

    /// 国内站、国际站的地址都认；模型改了就算自定义；地址末尾的 / 不影响。
    func testMatching() {
        storefront("CHN")
        let model = Provider.kimi.preset!.model
        XCTAssertEqual(Provider.matching(baseURL: Provider.kimiGlobal, model: model), .kimi)
        XCTAssertEqual(Provider.matching(baseURL: Provider.kimiChina + "/", model: model), .kimi)
        XCTAssertNil(Provider.matching(baseURL: Provider.kimiChina, model: "my-model"))
        XCTAssertEqual(Provider.matching(baseURL: "http://10.0.0.2:11434/v1", model: "anything"), .ollama)
        XCTAssertEqual(Provider.matching(baseURL: Provider.kimiChina, model: Provider.kimiAnswerModel, answer: true), .kimi)
    }
}
