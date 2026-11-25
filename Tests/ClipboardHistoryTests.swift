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
}
