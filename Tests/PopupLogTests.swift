import XCTest

/// 弹出记录：途中被打断、系统预热过的不算慢、不进「一般多久」；旧记录照常解码；高度变化、截图判断后又变了的写法。
final class PopupLogTests: XCTestCase {
    private func record(nth: Int = 2, processToLoad: Double? = nil, paused: Double? = nil, loadToAppear: Double = 60) -> PopupRecord {
        PopupRecord(at: Date(), nth: nth, processToLoad: processToLoad, initToLoad: 5, paused: paused,
                    load: 2, willAppear: 20, willHost: 1, willReload: 1, willLayout: 15, loadToAppear: loadToAppear,
                    didClipboard: 0, didCommonWords: 0, nineKey: true)
    }

    func testInterruptedIsNotSlow() {
        let interrupted = record(loadToAppear: 4200)
        XCTAssertTrue(interrupted.interrupted)
        XCTAssertFalse(interrupted.isSlow)
        XCTAssertTrue(interrupted.title.contains("途中被打断"))
        // 被挂起的照旧只标挂起，不再标打断。
        let paused = record(paused: 3000, loadToAppear: 4200)
        XCTAssertFalse(paused.interrupted)
        XCTAssertTrue(paused.title.contains("中途被挂起"))
        // 正常慢的照旧标慢。
        XCTAssertTrue(record(loadToAppear: 400).isSlow)
    }

    func testSummaryLeavesOutInterrupted() {
        let records = [record(loadToAppear: 60), record(loadToAppear: 70), record(loadToAppear: 5000)]
        let summary = PopupLog.summary(records)
        XCTAssertTrue(summary.contains("热启动 3 次（1 次中途被挂起或打断，不算），一般 75 毫秒"), summary)
        XCTAssertTrue(summary.contains("没有明显慢的"), summary)
    }

    func testPauseBeforeLoadIsOnPrepareLine() {
        var before = record(paused: 2000)
        before.pausedBeforeLoad = true
        XCTAssertTrue(before.details[0].contains("其中键盘进程被系统挂起 2.0 秒"), before.details[0])
        XCTAssertFalse(before.details.contains { $0.hasPrefix("建键盘到显示出来") && $0.contains("挂起") })
        let during = record(paused: 2000)
        XCTAssertTrue(during.details.contains { $0.hasPrefix("建键盘到显示出来") && $0.contains("挂起 2.0 秒") })
    }

    func testPrewarmedColdStartCountsFromController() {
        let prewarmed = record(nth: 1, processToLoad: 42_000, loadToAppear: 300)
        XCTAssertTrue(prewarmed.prewarmed)
        XCTAssertEqual(prewarmed.total, 305, accuracy: 0.01)
        XCTAssertFalse(prewarmed.isSlow)
        XCTAssertTrue(prewarmed.title.contains("系统提前启动过键盘进程"))
        let cold = record(nth: 1, processToLoad: 350, loadToAppear: 300)
        XCTAssertFalse(cold.prewarmed)
        XCTAssertEqual(cold.total, 650, accuracy: 0.01)
    }

    func testOldRecordDecodes() throws {
        var old = record()
        old.heights = nil
        let data = try JSONEncoder().encode([old])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        json[0].removeValue(forKey: "heights")
        json[0].removeValue(forKey: "wantedHeight")
        let decoded = try JSONDecoder().decode([PopupRecord].self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded[0].heights)
        XCTAssertFalse(decoded[0].details.contains { $0.hasPrefix("键盘高度") })
    }

    func testHeightsText() {
        let marks = PopupMarks()
        XCTAssertNil(marks.heightsText(from: 10))
        marks.noteHeight(667, at: 10.013)
        marks.noteHeight(667, at: 10.020)
        marks.noteHeight(296, at: 10.062)
        XCTAssertEqual(marks.heightsText(from: 10), "第 13 毫秒 667 → 第 62 毫秒 296")
        var shown = record()
        shown.heights = marks.heightsText(from: 10)
        shown.wantedHeight = 296
        XCTAssertTrue(shown.details.contains("键盘高度：第 13 毫秒 667 → 第 62 毫秒 296（我们要的 296）"))
    }

    func testSnapshotDriftLine() {
        var shot = record()
        shot.snapshotMiss = "和上次不一样：回车键"
        shot.snapshotDrift = "回车键、深浅色"
        XCTAssertTrue(shot.details.contains("截图开关开着，这次没用截图：和上次不一样：回车键；判断用不用截图以后，0.4 秒内又变了：回车键、深浅色"),
                      shot.details.joined(separator: "\n"))
        XCTAssertFalse(record().details.contains { $0.contains("0.4 秒内又变了") })
    }
}
