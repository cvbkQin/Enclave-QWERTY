import XCTest

/// AI 帮回（T16）并进润色（方案 D v6）：提示词、去掉模型加的编号引号、剪贴板哪条能帮回、待回的复制、
/// 会话里帮回的版本和历史记录、固定帮回键的设置。
final class HelpReplyTests: XCTestCase {
    private let formal = StylePreset(name: "正式", prompt: "风格：正式。用书面、得体、礼貌的表达。")

    func testMessagesUsePolishStyleMeaningAndRequest() {
        let messages = HelpReply.messages(message: "这份方案明天能交吗？", style: formal, meaning: "明天可能来不及", request: "说要后天")
        XCTAssertEqual(messages.count, 2)
        let user = messages[1].content
        XCTAssertTrue(user.contains("<对方的话>\n这份方案明天能交吗？\n</对方的话>"))
        XCTAssertTrue(user.contains("下面是用户选的润色风格，只取它对语气、用词、长度的要求，用在你写的回复上：\n风格：正式。"))
        XCTAssertTrue(user.contains("<用户想表达的意思>\n明天可能来不及\n</用户想表达的意思>"))
        XCTAssertTrue(user.contains("要求：说要后天"))
        XCTAssertFalse(user.contains("回复方向"))
        XCTAssertTrue(messages[0].content.contains("写一条"))
    }

    func testMessagesWithoutStyleOrExtras() {
        let blank = StylePreset(name: "润色", prompt: "")
        for style in [nil, blank] {
            let user = HelpReply.messages(message: "周六有空吗？", style: style, meaning: " ", request: "").last!.content
            XCTAssertTrue(user.contains("风格：自然、像本人。"))
            XCTAssertFalse(user.contains("用户想表达的意思"))
            XCTAssertFalse(user.contains("要求："))
        }
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

    /// 待回的复制：第一次用时原来的内容不算；换了新内容，复制时间按键盘上次看剪贴板的时间算，
    /// 查完不是链接、纯数字才算，1 分钟后、用过就不算。
    func testHelpCopyPending() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = HelpCopy.observe(nil, count: 5, hasStrings: true, now: start, lookedAt: nil)
        XCTAssertTrue(first.used, "装好后剪贴板里原来的内容不算新复制")
        // 键盘开着（1 秒前还看过）时换了：就是刚复制的。
        var copy = HelpCopy.observe(first, count: 6, hasStrings: true, now: start, lookedAt: start.addingTimeInterval(-1))
        XCTAssertFalse(copy.used)
        XCTAssertFalse(copy.pending(now: start), "detectPatterns 还没查完")
        copy.suits = true
        XCTAssertTrue(copy.pending(now: start.addingTimeInterval(58)))
        XCTAssertFalse(copy.pending(now: start.addingTimeInterval(59)))
        // 同一份再看一眼：复制时间不变。
        XCTAssertEqual(HelpCopy.observe(copy, count: 6, hasStrings: true, now: start.addingTimeInterval(100), lookedAt: start).seen,
                       start.addingTimeInterval(-1))
        var link = copy
        link.suits = false
        XCTAssertFalse(link.pending(now: start))
        var used = copy
        used.used = true
        XCTAssertFalse(used.pending(now: start))
        XCTAssertTrue(HelpCopy.observe(copy, count: 7, hasStrings: false, now: start, lookedAt: start).used, "图片之类没有文字")
    }

    /// 键盘收起很久以后再弹出，剪贴板换过：分不清是刚复制还是很久以前复制的，按键盘上次看剪贴板的时间算，不再算待回。
    func testHelpCopyChangedWhileKeyboardHidden() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = HelpCopy(count: 5, seen: now.addingTimeInterval(-7200), used: true, suits: nil)
        var stale = HelpCopy.observe(old, count: 6, hasStrings: true, now: now, lookedAt: now.addingTimeInterval(-3600))
        stale.suits = true
        XCTAssertFalse(stale.pending(now: now), "一小时前收起的键盘，现在才看到的复制不算")
        var fresh = HelpCopy.observe(old, count: 6, hasStrings: true, now: now, lookedAt: now.addingTimeInterval(-40))
        fresh.suits = true
        XCTAssertTrue(fresh.pending(now: now), "刚收起去复制、回来再弹出：算")
        XCTAssertFalse(fresh.pending(now: now.addingTimeInterval(25)), "从收起时算 1 分钟")
        var unknown = HelpCopy.observe(old, count: 6, hasStrings: true, now: now, lookedAt: nil)
        unknown.suits = true
        XCTAssertFalse(unknown.pending(now: now), "不知道键盘上次什么时候看过")
        // 旧版存的记录没有 typed，照常读。
        let legacy = #"{"count":6,"seen":0,"used":false,"suits":true}"#
        XCTAssertNil(try JSONDecoder().decode(HelpCopy.self, from: Data(legacy.utf8)).typed)
    }

    /// 帮回的一版接在同一条时间线后面，带对方的话；历史记录第一版是帮回时记成帮回，每版标得出润 / 问 / 回。
    func testReplyVersionInSessionAndHistory() {
        var session = EditSession(mode: .polish, original: "")
        session.append("方案细节我再完善一下，后天上午发给您可以吗？")
        session.noteCurrent(style: "正式", provider: "DeepSeek", source: EditSession.VersionSource.reply)
        session.markReply(EditSession.ReplySource(message: "这份方案明天能交吗？", request: "说要后天", meaning: "明天来不及"))
        XCTAssertTrue(session.currentIsReply)
        XCTAssertEqual(session.currentReplySource?.message, "这份方案明天能交吗？")
        session.append("您好，方案预计后天上午发给您。")
        session.noteCurrent(style: "正式", provider: "DeepSeek", source: EditSession.VersionSource.polish)
        XCTAssertFalse(session.currentIsReply)
        session.appendAsk("「冗余」读 rǒng yú。", answer: true, replacingLast: false, source: .init(question: "冗余怎么读", context: ""))

        let entry = AIHistoryEntry(session: session)!
        XCTAssertEqual(entry.kind, .reply)
        XCTAssertEqual(entry.original, "这份方案明天能交吗？")
        XCTAssertTrue(entry.hasReply)
        XCTAssertFalse(entry.isLegacyReply)
        XCTAssertEqual(entry.versions[0].message, "这份方案明天能交吗？")
        XCTAssertEqual(entry.versions[0].direction, "说要后天")
        XCTAssertEqual(entry.versions[0].meaning, "明天来不及")
        XCTAssertEqual((0..<3).map(entry.versionKind), [.reply, .polish, .answer])

        // 先润色、后帮回：记成润色，「帮回」筛选里也有。
        var polish = EditSession(mode: .polish, original: "明天可能来不及")
        polish.append("明天恐怕来不及。")
        polish.append("方案明天可能来不及，后天上午给您可以吗？")
        polish.markReply(EditSession.ReplySource(message: "这份方案明天能交吗？"))
        let mixed = AIHistoryEntry(session: polish)!
        XCTAssertEqual(mixed.kind, .polish)
        XCTAssertTrue(mixed.hasReply)

        // 编码再读回来不丢。
        let data = try! JSONEncoder().encode(session)
        XCTAssertEqual(try! JSONDecoder().decode(EditSession.self, from: data).replySources, session.replySources)
    }

    /// 旧版单独帮回的记录（有轮次）照常读，还是按轮显示。
    func testLegacyReplyRecordsStillRead() throws {
        let old = #"[{"id":"b","kind":"reply","date":1700000000,"original":"能交吗？","context":"","versions":[{"text":"好的","edited":false,"style":"客气","round":1,"source":"reply"}]}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let legacy = try decoder.decode([AIHistoryEntry].self, from: Data(old.utf8))
        XCTAssertEqual(legacy.first?.versions.first?.style, "客气")
        XCTAssertTrue(legacy.first?.isLegacyReply ?? false)
        XCTAssertTrue(legacy.first?.hasReply ?? false)
    }

    /// AI 栏上的帮回键：默认不钉，全键盘和九宫格同一个设置；以前的两个设置不再读。
    func testHelpPinDefaultsAndToggle() throws {
        var settings = EnclaveSettings()
        XCTAssertFalse(settings.helpPinned)
        settings.helpPinned.toggle()
        let back = try JSONDecoder().decode(EnclaveSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(back.helpPinned)
        XCTAssertEqual(back.pinnedStyles.count, settings.pinnedStyles.count)
        let old = Data(#"{"baseURL":"https://api.deepseek.com/v1","model":"deepseek-flash","helpPinnedQwerty":true,"replyStyles":[]}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(EnclaveSettings.self, from: old).helpPinned)
    }

    // MARK: 自动判断（帮回开关方案第 2 版）

    /// 新装开；0.97 以前的设置没有这一项，读出来也是开；关掉能存下来。
    func testHelpAutoDefaultsAndUpgrade() throws {
        var settings = EnclaveSettings()
        XCTAssertTrue(settings.helpAuto, "新装默认开")
        let old = Data(#"{"baseURL":"https://api.deepseek.com/v1","model":"deepseek-flash","helpPinned":true}"#.utf8)
        let upgraded = try JSONDecoder().decode(EnclaveSettings.self, from: old)
        XCTAssertTrue(upgraded.helpAuto, "升级读不到就当开（0.97 相当于开着）")
        XCTAssertTrue(upgraded.helpPinned)
        settings.helpAuto = false
        XCTAssertFalse(try JSONDecoder().decode(EnclaveSettings.self, from: JSONEncoder().encode(settings)).helpAuto)
    }

    /// 润色关了，帮回整个没有（bug #34），也不做自动判断；自动判断关着只停判断，帮回照样能用。
    func testHelpUsableFollowsPolishSwitchAndAuto() {
        var settings = EnclaveSettings()
        settings.baseURL = "https://help-auto-test.example/v1"
        settings.model = "help-auto-model"
        XCTAssertTrue(settings.helpReplyUsable)
        XCTAssertTrue(settings.helpAutoDetects)

        settings.helpAuto = false
        XCTAssertTrue(settings.helpReplyUsable, "关着自动判断：⌄ 那一行、钉住的键、「帮回这条」照样在")
        XCTAssertFalse(settings.helpAutoDetects)

        settings.helpAuto = true
        settings.polishEnabled = false
        XCTAssertTrue(settings.polishUsable, "接口本身还能用")
        XCTAssertFalse(settings.helpReplyUsable, "润色关了帮回也没有")
        XCTAssertFalse(settings.helpAutoDetects, "润色关了也不看剪贴板")

        settings.polishEnabled = true
        settings.model = ""
        XCTAssertFalse(settings.helpReplyUsable, "润色接口没配好")
    }

    /// 方案第 9 节依赖的前提：关着自动判断时键盘不写「上次看剪贴板」的时间（noteClipboardLook，KeyboardModel 不在测试目标里，
    /// 那一处只能在模拟器上看），lookedAt 就停在关掉以前；这时关着那段时间里复制的，再打开后按很久以前算，不会突然变绿。
    func testReenablingAutoDoesNotFlagOldCopy() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 关掉以前最后一次看剪贴板是 10 分钟前；关着时复制了，现在打开、键盘弹出。
        let before = HelpCopy(count: 5, seen: now.addingTimeInterval(-900), used: true, suits: nil)
        var copy = HelpCopy.observe(before, count: 6, hasStrings: true, now: now, lookedAt: now.addingTimeInterval(-600))
        copy.suits = true
        XCTAssertFalse(copy.pending(now: now))
        // 打开以后再复制（键盘开着、1 秒前看过）：照常算刚复制。
        var next = HelpCopy.observe(copy, count: 7, hasStrings: true, now: now.addingTimeInterval(30), lookedAt: now.addingTimeInterval(29))
        next.suits = true
        XCTAssertTrue(next.pending(now: now.addingTimeInterval(30)))
    }
}
