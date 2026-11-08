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

    func testRelatedAllowsHandEditsButNotOtherText() {
        let reply = "好的，明天上午能交，我今晚再过一遍细节。"
        XCTAssertTrue(HelpReply.related(reply, reply))
        XCTAssertTrue(HelpReply.related("好的，明天上午能交，我今晚再看一遍。", reply))
        XCTAssertFalse(HelpReply.related("周末去爬山吗", reply))
        XCTAssertFalse(HelpReply.related("", reply))
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

    /// 11-08：帮回的版本多记 styleID、polish；旧记录没有这两个字段也要读得出来。
    func testReplyVersionKeepsStyleAndReadsOldRecords() throws {
        var version = AIHistoryEntry.Version(text: "好的", style: "客气 · ✨正式", round: 2, direction: "委婉点")
        version.styleID = "6F1C1A64-0F0A-4C77-9E5E-0B3C2D1E4F50"
        version.polish = "正式"
        let entry = AIHistoryEntry(id: "a", kind: .reply, date: Date(timeIntervalSince1970: 1_700_000_000), original: "能交吗？",
                                   context: "", versions: [version])
        let data = try JSONEncoder().encode([entry])
        let back = try JSONDecoder().decode([AIHistoryEntry].self, from: data)
        XCTAssertEqual(back.first?.versions.first?.styleID, version.styleID)
        XCTAssertEqual(back.first?.versions.first?.polish, "正式")

        let old = #"[{"id":"b","kind":"reply","date":1700000000,"original":"能交吗？","context":"","versions":[{"text":"好的","edited":false,"style":"客气","round":1}]}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let legacy = try decoder.decode([AIHistoryEntry].self, from: Data(old.utf8))
        XCTAssertNil(legacy.first?.versions.first?.styleID)
        XCTAssertNil(legacy.first?.versions.first?.polish)
        XCTAssertEqual(legacy.first?.versions.first?.style, "客气")
    }
}
