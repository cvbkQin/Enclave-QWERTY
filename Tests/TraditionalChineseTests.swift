import XCTest

/// 繁体输出（B5）：结果和 OpenCC 默认的 s2t 一致（期望值用 scripts/build-s2t.py 生成的同一份词表、同样的最长匹配算出）。
final class TraditionalChineseTests: XCTestCase {
    func testPhrasesWin() {
        XCTAssertEqual(TraditionalChinese.convert("输入法"), "輸入法")
        XCTAssertEqual(TraditionalChinese.convert("头发"), "頭髮")
        XCTAssertEqual(TraditionalChinese.convert("发展"), "發展")
        XCTAssertEqual(TraditionalChinese.convert("干净"), "乾淨")
        XCTAssertEqual(TraditionalChinese.convert("干部"), "幹部")
        XCTAssertEqual(TraditionalChinese.convert("头发很干"), "頭髮很乾")
        XCTAssertEqual(TraditionalChinese.convert("联系"), "聯繫")
        XCTAssertEqual(TraditionalChinese.convert("系统"), "系統")
        XCTAssertEqual(TraditionalChinese.convert("一只"), "一隻")
        XCTAssertEqual(TraditionalChinese.convert("汉语拼音"), "漢語拼音")
    }

    func testCharactersAndUntouched() {
        XCTAssertEqual(TraditionalChinese.convert("我们"), "我們")
        XCTAssertEqual(TraditionalChinese.convert("中国"), "中國")
        XCTAssertEqual(TraditionalChinese.convert("皇后"), "皇后")
        XCTAssertEqual(TraditionalChinese.convert("abc123"), "abc123")
        XCTAssertEqual(TraditionalChinese.convert(""), "")
        XCTAssertEqual(TraditionalChinese.convert("好的，OK"), "好的，OK")
    }
}
