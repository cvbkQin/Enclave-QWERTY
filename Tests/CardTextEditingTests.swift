import XCTest

final class CardTextEditingTests: XCTestCase {
    func testOffsetsWithEmoji() {
        let text = "好😀a"
        XCTAssertEqual(CardTextEditing.utf16Offset(0, in: text), 0)
        XCTAssertEqual(CardTextEditing.utf16Offset(2, in: text), 3)
        XCTAssertEqual(CardTextEditing.utf16Offset(9, in: text), 4)
        XCTAssertEqual(CardTextEditing.characterIndex(utf16: 3, in: text), 2)
        // 落在表情两个单位中间：算到表情后面。
        XCTAssertEqual(CardTextEditing.characterIndex(utf16: 2, in: text), 2)
    }

    func testWordRangeEnglish() {
        let text = "hello world"
        XCTAssertEqual(CardTextEditing.wordRange(at: 7, in: text), 6..<11)
        XCTAssertEqual(CardTextEditing.wordRange(at: 0, in: text), 0..<5)
        // 空格不属于任何词：只选这一个字。
        XCTAssertEqual(CardTextEditing.wordRange(at: 5, in: text), 5..<6)
        // 超出末尾按最后一个字算。
        XCTAssertEqual(CardTextEditing.wordRange(at: 99, in: text), 6..<11)
        XCTAssertNil(CardTextEditing.wordRange(at: 0, in: ""))
    }

    func testWordRangeChineseStaysInBounds() {
        let text = "明天新加坡先多云，午后有雨。"
        for index in 0..<text.count {
            guard let range = CardTextEditing.wordRange(at: index, in: text) else { return XCTFail("no range at \(index)") }
            XCTAssertTrue(range.contains(index), "\(range) should contain \(index)")
            XCTAssertGreaterThanOrEqual(range.lowerBound, 0)
            XCTAssertLessThanOrEqual(range.upperBound, text.count)
        }
        // 标点只选它自己。
        XCTAssertEqual(CardTextEditing.wordRange(at: 8, in: text), 8..<9)
    }

    func testReplacing() {
        let text = "明天多云"
        let cut = CardTextEditing.replacing(2..<4, in: text, with: "")
        XCTAssertEqual(cut.text, "明天")
        XCTAssertEqual(cut.caret, 2)
        let pasted = CardTextEditing.replacing(0..<2, in: text, with: "后天😀")
        XCTAssertEqual(pasted.text, "后天😀多云")
        XCTAssertEqual(pasted.caret, 3)
        XCTAssertEqual(CardTextEditing.substring(1..<3, of: text), "天多")
        XCTAssertEqual(CardTextEditing.substring(2..<99, of: text), "多云")
        XCTAssertEqual(CardTextEditing.range(5, 2), 2..<5)
    }
}
