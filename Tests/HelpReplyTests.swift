import XCTest

/// AI 帮回（T16）：拆模型输出、剪贴板哪条能帮回、帮回风格打勾。
final class HelpReplyTests: XCTestCase {
    func testParseNumberedReplies() {
        let raw = "【1】\n好啊，周六晚上可以！几点在火锅店见？\n【2】\n谢谢你想着我～到时候楼下火锅店见。\n\n【3】\n可以，几点？"
        XCTAssertEqual(HelpReply.parse(raw, count: 3), [
            "好啊，周六晚上可以！几点在火锅店见？", "谢谢你想着我～到时候楼下火锅店见。", "可以，几点？",
        ])
    }

    func testParseFallsBackToNumberedLinesAndStripsQuotes() {
        let raw = "1. “好的，没问题”\n2. 风格「客气」：谢谢邀请！\n3. 行"
        XCTAssertEqual(HelpReply.parse(raw, count: 3), ["好的，没问题", "谢谢邀请！", "行"])
    }

    func testParseSingleReplyWithoutNumber() {
        XCTAssertEqual(HelpReply.parse("你们组局我肯定到！", count: 1), ["你们组局我肯定到！"])
    }

    func testParseTakesAtMostCount() {
        XCTAssertEqual(HelpReply.parse("【1】a\n【2】b\n【3】c\n【4】d", count: 3), ["a", "b", "c"])
    }

    func testMessagesCarryOnlyMessageStylesAndDirection() {
        let styles = Array(StylePreset.replyDefaults.prefix(2))
        let messages = HelpReply.messages(message: "这周六晚上有空吗？", styles: styles, direction: "委婉拒绝")
        XCTAssertEqual(messages.count, 2)
        let user = messages[1].content
        XCTAssertTrue(user.contains("这周六晚上有空吗？"))
        XCTAssertTrue(user.contains("【2】风格「客气」"))
        XCTAssertTrue(user.contains("回复方向（每条都按这个方向写）：委婉拒绝"))
        XCTAssertFalse(HelpReply.messages(message: "x", styles: styles, direction: " ")[1].content.contains("回复方向"))
    }

    func testSingleStyleMessages() {
        let style = StylePreset.replyDefaults[1]
        let messages = HelpReply.messages(message: "周六有空吗？", style: style, direction: "委婉拒绝")
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[1].content.contains("风格「客气」：礼貌"))
        XCTAssertTrue(messages[1].content.contains("回复方向：委婉拒绝"))
        XCTAssertFalse(HelpReply.messages(message: "x", style: style, direction: "").last!.content.contains("回复方向"))
    }

    func testSingleStripsMarkersAndQuotes() {
        XCTAssertEqual(HelpReply.single("【1】\n好啊，几点？"), "好啊，几点？")
        XCTAssertEqual(HelpReply.single("“可以呀”"), "可以呀")
        XCTAssertEqual(HelpReply.single("【"), "")
        XCTAssertEqual(HelpReply.single("好的\n\n我晚点到"), "好的\n\n我晚点到")
    }

    func testSuitsSkipsTrackingNumbersLinksAndNumbers() {
        XCTAssertTrue(HelpReply.suits("一起吃个饭，叫上小王，就在公司楼下那家火锅"))
        XCTAssertTrue(HelpReply.suits("Are you free on Saturday?"))
        XCTAssertFalse(HelpReply.suits("SF2048-KX9Q"))
        XCTAssertFalse(HelpReply.suits("https://example.com/a"))
        XCTAssertFalse(HelpReply.suits("13800138000"))
        XCTAssertFalse(HelpReply.suits("wang.lei@enclavekb.cn"))
        XCTAssertFalse(HelpReply.suits("¥ 2,000.00"))
    }

    func testCheckedReplyStylesDefaultAndLimits() {
        var settings = EnclaveSettings()
        XCTAssertEqual(settings.checkedReplyStyles.map(\.name), ["正常", "客气", "简短"])
        let highEQ = StylePreset.replyDefaults[3].id
        XCTAssertFalse(settings.toggleReplyChecked(highEQ), "勾满 3 种不能再勾")
        XCTAssertTrue(settings.toggleReplyChecked(StylePreset.replyDefaults[1].id))
        XCTAssertTrue(settings.toggleReplyChecked(highEQ))
        XCTAssertEqual(settings.checkedReplyStyles.map(\.name), ["正常", "简短", "高情商"])
        XCTAssertTrue(settings.toggleReplyChecked(StylePreset.replyDefaults[0].id))
        XCTAssertTrue(settings.toggleReplyChecked(StylePreset.replyDefaults[2].id))
        XCTAssertFalse(settings.toggleReplyChecked(highEQ), "至少留 1 种")
    }

    func testOldSettingsGetReplyDefaults() throws {
        let data = Data(#"{"baseURL":"https://api.deepseek.com/v1","model":"deepseek-flash"}"#.utf8)
        let settings = try JSONDecoder().decode(EnclaveSettings.self, from: data)
        XCTAssertEqual(settings.replyStyles.count, 7)
        XCTAssertEqual(settings.replyCheckedIDs.count, 3)
    }
}
