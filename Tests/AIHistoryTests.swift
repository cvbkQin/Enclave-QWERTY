import XCTest

/// 历史记录（第 48 条）：一轮会话记成一条的样子，保留时间和 1,000 条上限。
final class AIHistoryTests: XCTestCase {
    func testPolishEntry() throws {
        var session = EditSession(mode: .polish, original: "明天开会的事情我再跟你确认下时间哈")
        session.append("明天开会的时间，我再跟你确认一下。")
        session.noteCurrent(style: "正式", provider: "DeepSeek")
        session.append("明天会议的具体时间，我稍后再和您确认一下。")
        session.noteCurrent(style: "正式", provider: "DeepSeek")
        session.markCurrentUsed("replaced")
        session.append("明天会议的具体时间，我下午再和您确认。", edited: true)

        let entry = try XCTUnwrap(AIHistoryEntry(session: session))
        XCTAssertEqual(entry.kind, .polish)
        XCTAssertEqual(entry.id, session.historyID)
        XCTAssertEqual(entry.versions.count, 3)
        XCTAssertEqual(entry.usedIndex, 1)
        XCTAssertEqual(entry.shown, "明天会议的具体时间，我稍后再和您确认一下。")
        XCTAssertEqual(entry.versions[1].use, .replaced)
        XCTAssertTrue(entry.versions[2].edited)
        XCTAssertNil(entry.versions[2].style)
        XCTAssertEqual(entry.versions[0].provider, "DeepSeek")
        XCTAssertTrue(entry.matches("稍后"))
        XCTAssertFalse(entry.matches("天气"))
    }

    func testAnswerEntry() throws {
        var session = EditSession(mode: .polish, original: "下午去外滩拍照")
        session.appendAsk("多云转小雨，建议带伞。", answer: true, replacingLast: false,
                          source: .init(question: "今天上海天气怎么样", context: "下午去外滩拍照"))
        session.markSearched(by: "Kimi")
        let entry = try XCTUnwrap(AIHistoryEntry(session: session))
        XCTAssertEqual(entry.kind, .answer)
        XCTAssertEqual(entry.original, "今天上海天气怎么样")
        XCTAssertEqual(entry.context, "下午去外滩拍照")
        XCTAssertTrue(entry.searched)
        XCTAssertNil(entry.usedIndex)
        XCTAssertTrue(entry.matches("SHANGHAI") == false && entry.matches("外滩"))
    }

    func testSkipsEmptyAndLegacySessions() {
        XCTAssertNil(AIHistoryEntry(session: EditSession(mode: .polish, original: "没出结果")))
        var legacy = EditSession(mode: .polish, original: "旧数据")
        legacy.append("结果")
        legacy.historyID = nil
        XCTAssertNil(AIHistoryEntry(session: legacy))
    }

    func testOldSessionDataStillDecodes() throws {
        let old = #"{"mode":"polish","original":"原话","versions":["一版"],"currentIndex":0,"conversation":[]}"#
        let session = try JSONDecoder().decode(EditSession.self, from: Data(old.utf8))
        XCTAssertNil(session.historyID)
        XCTAssertEqual(session.current, "一版")
    }

    func testPruned() throws {
        let now = Date()
        func entry(daysAgo: Double) throws -> AIHistoryEntry {
            var session = EditSession(mode: .polish, original: "原文")
            session.append("结果")
            session.startedAt = now.addingTimeInterval(-daysAgo * 86_400)
            return try XCTUnwrap(AIHistoryEntry(session: session))
        }
        let entries = [try entry(daysAgo: 1), try entry(daysAgo: 10), try entry(daysAgo: 40), try entry(daysAgo: 400)]
        XCTAssertEqual(AIHistory.pruned(entries, now: now, retention: .week).count, 1)
        XCTAssertEqual(AIHistory.pruned(entries, now: now, retention: .month).count, 2)
        XCTAssertEqual(AIHistory.pruned(entries, now: now, retention: .year).count, 3)
        XCTAssertEqual(AIHistory.pruned(entries, now: now, retention: .forever).count, 4)

        let many = try (0..<1_005).map { try entry(daysAgo: Double($0) / 100) }
        let kept = AIHistory.pruned(many, now: now, retention: .forever)
        XCTAssertEqual(kept.count, AIHistory.maxEntries)
        XCTAssertEqual(kept.first?.id, many.first?.id)
    }
}
