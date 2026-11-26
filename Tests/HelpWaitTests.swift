import XCTest

/// 帮回加要求（对齐清单第 94 条，design/help-reply/again）：再点帮回用这一版的原话、开新的一句先等 1.5 秒、等待条的节奏。
final class HelpWaitTests: XCTestCase {
    private let source = EditSession.ReplySource(message: "这份方案明天能交吗？", request: nil, meaning: nil)

    /// HR1 第 2 条：卡展开、卡上是帮回写的一版、没有新的待回复制：回这一版的原话，不读剪贴板。
    func testReplyAgainUsesRecordedMessage() {
        XCTAssertEqual(HelpWait.againSource(expanded: true, pending: false, current: source)?.message, "这份方案明天能交吗？")
        // 中间又复制了别的话：读剪贴板，回新的那句。
        XCTAssertNil(HelpWait.againSource(expanded: true, pending: true, current: source))
        // 卡收着、卡上不是帮回写的一版：照常读剪贴板。
        XCTAssertNil(HelpWait.againSource(expanded: false, pending: false, current: source))
        XCTAssertNil(HelpWait.againSource(expanded: true, pending: false, current: nil))
    }

    /// HW1 第 1 条：开新的一句、识意框空着才等；再点帮回重写、已经写了要求都马上回。
    func testWaitsOnlyForNewMessageWithoutRequest() {
        XCTAssertTrue(HelpWait.waitsBeforeReply(again: false, request: ""))
        XCTAssertTrue(HelpWait.waitsBeforeReply(again: false, request: "  \n"))
        XCTAssertFalse(HelpWait.waitsBeforeReply(again: false, request: "说周五下午三点"))
        XCTAssertFalse(HelpWait.waitsBeforeReply(again: true, request: ""))
    }

    /// 二之三第 1 条：1.5 秒，0.75 秒走到 68%，1.125 秒 90%，1.5 秒刚好碰到右边，之后不再走。
    func testBrushSlowsNearTheEndAndLandsAtOneAndAHalfSeconds() {
        XCTAssertEqual(HelpWait.duration, 1.5)
        XCTAssertEqual(HelpWait.progress(elapsed: 0), 0)
        XCTAssertEqual(HelpWait.progress(elapsed: 0.75), 0.68, accuracy: 0.01)
        XCTAssertEqual(HelpWait.progress(elapsed: 1.125), 0.90, accuracy: 0.01)
        XCTAssertEqual(HelpWait.progress(elapsed: 1.5), 1)
        XCTAssertEqual(HelpWait.progress(elapsed: 3), 1)
        // 前快后慢：最后 1/4 时间只走 10% 左右。
        let early = HelpWait.progress(elapsed: 0.375), late = 1 - HelpWait.progress(elapsed: 1.125)
        XCTAssertGreaterThan(early, late * 3)
    }

    /// 打断时记下笔刷走到哪儿，往回收从这里算。
    func testInterruptKeepsWhereTheBrushStopped() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var wait = HelpWait(message: "Hey, when and where are we meeting on Friday?", changeCount: 5, fromPin: true, startedAt: start)
        XCTAssertFalse(wait.interrupted)
        XCTAssertNil(wait.interruptProgress)
        wait.interruptedAt = start.addingTimeInterval(0.75)
        XCTAssertTrue(wait.interrupted)
        XCTAssertEqual(wait.interruptProgress ?? 0, 0.68, accuracy: 0.01)
    }

    func testCubicBezierEndsAndMonotonic() {
        for curve in [CubicBezier.brush, CubicBezier.retract, CubicBezier.flashOut] {
            XCTAssertEqual(curve.value(at: 0), 0)
            XCTAssertEqual(curve.value(at: 1), 1)
            var last = 0.0
            for i in 1...20 {
                let v = curve.value(at: Double(i) / 20)
                XCTAssertGreaterThanOrEqual(v, last)
                last = v
            }
        }
    }
}
