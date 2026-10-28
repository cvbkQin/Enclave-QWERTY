import XCTest

/// AI 读输入框里的哪一段（FieldSpan）：100 / 200 字上限、按整句截、替换前核对。
final class FieldSpanTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testLimits() {
        XCTAssertEqual(FieldSpan.limits(longText: false).limit, 100)
        XCTAssertEqual(FieldSpan.limits(longText: false).lookahead, 150)
        XCTAssertEqual(FieldSpan.limits(longText: true).limit, 200)
        XCTAssertEqual(FieldSpan.limits(longText: true).lookahead, 250)
    }

    func testShortTextIsReadWhole() {
        let span = FieldSpan(before: "abc。def", after: "ghi", longText: false)
        XCTAssertEqual(span.text, "abc。defghi")
        XCTAssertEqual(span.beforeCount, 7)
        XCTAssertEqual(span.afterCount, 3)
    }

    /// 2000 字的长文本：只读光标前最后几句整句，开头是「第 N 句」，不超过上限。
    func testLongFixtureCutsAtSentence() throws {
        let text = try fixture("长文本测试-2000字")
        let normal = FieldSpan(before: text, after: "", longText: false)
        XCTAssertEqual(normal.beforeCount, 76)
        XCTAssertEqual(normal.afterCount, 0)
        XCTAssertTrue(normal.text.hasPrefix("第55句："))
        XCTAssertTrue(text.hasSuffix(normal.text))

        let long = FieldSpan(before: text, after: "", longText: true)
        XCTAssertEqual(long.beforeCount, 190)
        XCTAssertTrue(long.text.hasPrefix("第52句："))
    }

    func testUniqueFixture() throws {
        let text = try fixture("长文本测试-不重复")
        let normal = FieldSpan(before: text, after: "", longText: false)
        XCTAssertEqual(normal.beforeCount, 85)
        XCTAssertTrue(normal.text.hasPrefix("第53句："))
        let long = FieldSpan(before: text, after: "", longText: true)
        XCTAssertEqual(long.beforeCount, 176)
        XCTAssertTrue(long.text.hasPrefix("第49句："))
    }

    /// 不到上限的长度都不硬截；全文没有任何断点、又超过 lookahead 时才硬截 100 字。
    func testHardCutWithoutBoundary() {
        let text = String(repeating: "一二三四五六七八九十", count: 20)
        let span = FieldSpan(before: text, after: "", longText: false)
        XCTAssertEqual(span.beforeCount, 100)
    }

    /// 没有句末时退到逗号。
    func testFallsBackToClause() {
        let text = String(repeating: "这是一句话，", count: 30)
        let span = FieldSpan(before: text, after: "", longText: false)
        XCTAssertEqual(span.beforeCount, 96)
        XCTAssertTrue(span.text.hasPrefix("这是一句话，"))
    }

    /// 系统给的光标前文字从半句话开始（以标点开头）：跳到第一个句末之后。
    func testSkipsTruncatedHead() {
        let span = FieldSpan(before: "，后半句。完整的一句。", after: "", longText: false)
        XCTAssertEqual(span.text, "完整的一句。")
        XCTAssertEqual(span.beforeCount, 6)
    }

    func testMatches() {
        let span = FieldSpan(before: "前面的字。要改的一句", after: "光标后", longText: false)
        XCTAssertTrue(span.matches(before: "前面的字。要改的一句", after: "光标后"))
        // 系统这次只给了一截光标前文字。
        XCTAssertTrue(span.matches(before: "要改的一句", after: "光标后"))
        XCTAssertFalse(span.matches(before: "别的内容", after: "光标后"))
        XCTAssertFalse(span.matches(before: "前面的字。要改的一句", after: "不一样"))
    }

    func testWrittenSpan() {
        let span = FieldSpan(written: "新写的")
        XCTAssertEqual(span.beforeCount, 3)
        XCTAssertEqual(span.afterCount, 0)
        XCTAssertTrue(span.matches(before: "前面新写的", after: ""))
    }
}
