import XCTest

/// 剪贴板记录（B1）：同样的不重复存、挪到最前；最多 20 条；24 小时后删掉。
final class ClipboardHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testInsertMovesDuplicateToFront() {
        var items: [ClipItem] = []
        items = ClipboardHistory.inserting("A", into: items, now: now.addingTimeInterval(-300))
        items = ClipboardHistory.inserting("B", into: items, now: now.addingTimeInterval(-200))
        items = ClipboardHistory.inserting("A", into: items, now: now)
        XCTAssertEqual(items.map(\.text), ["A", "B"])
        XCTAssertEqual(items[0].date, now)
    }

    func testKeepsAtMostTwenty() {
        var items: [ClipItem] = []
        for i in 0..<25 { items = ClipboardHistory.inserting("第 \(i) 条", into: items, now: now.addingTimeInterval(Double(i))) }
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(items.first?.text, "第 24 条")
        XCTAssertEqual(items.last?.text, "第 5 条")
    }

    func testDropsAfter24Hours() {
        let items = [ClipItem(text: "新", date: now.addingTimeInterval(-3600)),
                     ClipItem(text: "旧", date: now.addingTimeInterval(-25 * 3600))]
        XCTAssertEqual(ClipboardHistory.pruned(items, now: now).map(\.text), ["新"])
        // 插入时也顺手删掉过期的。
        XCTAssertEqual(ClipboardHistory.inserting("再来", into: items, now: now).map(\.text), ["再来", "新"])
    }

    // MARK: T97 点开就存、最多保存条数（design/clipboard-autosave）

    func testLimitKeepsNewestAndDropsOldest() {
        var items: [ClipItem] = []
        for i in 0..<12 { items = ClipboardHistory.inserting("第 \(i) 条", into: items, now: now.addingTimeInterval(Double(i)), limit: 10) }
        XCTAssertEqual(items.count, 10)
        XCTAssertEqual(items.first?.text, "第 11 条")
        XCTAssertEqual(items.last?.text, "第 2 条")
    }

    func testShrinkingLimitDeletesOldestAndGrowingKeepsAll() {
        let items = (0..<12).map { ClipItem(text: "第 \($0) 条", date: now.addingTimeInterval(Double($0))) }
        let shrunk = ClipboardHistory.trimmed(items, limit: 10)
        XCTAssertEqual(shrunk.count, 10)
        XCTAssertFalse(shrunk.contains { $0.text == "第 0 条" || $0.text == "第 1 条" })
        XCTAssertEqual(ClipboardHistory.trimmed(items, limit: 50).count, 12)
        XCTAssertEqual(ClipboardHistory.removedCount(current: 12, limit: 10), 2)
        XCTAssertEqual(ClipboardHistory.removedCount(current: 12, limit: 20), 0)
    }

    func testNewMarkOnlyAfterLeavingPanel() {
        let left = now.addingTimeInterval(-60)
        XCTAssertTrue(ClipboardHistory.isNew(ClipItem(text: "刚存", date: now), since: left))
        XCTAssertFalse(ClipboardHistory.isNew(ClipItem(text: "以前", date: left.addingTimeInterval(-1)), since: left))
    }

    func testConcealedPasswordsAreNotRead() {
        XCTAssertTrue(ClipboardHistory.isConcealed(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipboardHistory.isConcealed(types: ["public.utf8-plain-text"]))
    }

    func testDoesNotCaptureWhenCollapsedOffOrUnchanged() {
        XCTAssertTrue(ClipboardHistory.shouldCapture(enabled: true, columnVisible: true, changeCount: 5, hasStrings: true, last: 4))
        // 剪贴板一栏收起：不读。
        XCTAssertFalse(ClipboardHistory.shouldCapture(enabled: true, columnVisible: false, changeCount: 5, hasStrings: true, last: 4))
        // 记录关着、没换过、不是文字：都不读。
        XCTAssertFalse(ClipboardHistory.shouldCapture(enabled: false, columnVisible: true, changeCount: 5, hasStrings: true, last: 4))
        XCTAssertFalse(ClipboardHistory.shouldCapture(enabled: true, columnVisible: true, changeCount: 5, hasStrings: true, last: 5))
        XCTAssertFalse(ClipboardHistory.shouldCapture(enabled: true, columnVisible: true, changeCount: 5, hasStrings: false, last: 4))
    }

    func testConfigExportWithApiKeyIsNotKept() {
        XCTAssertTrue(SettingsStore.isExportString("  enclave-config:eyJ9"))
        XCTAssertFalse(SettingsStore.isExportString("普通的一段话 enclave-config:"))
    }
}
