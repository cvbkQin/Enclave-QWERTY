import CoreGraphics
import XCTest

/// 长按弹出的一排以按键为中心（T92，对齐清单第 87 条，design/popup-center/说明.md）。
final class AlternatesRowTests: XCTestCase {
    /// iPhone 竖屏 375 宽：每格 34，字母键一个 unit = 37.5。
    private let width: CGFloat = 375
    private let cell: CGFloat = 34
    private func letterCenter(row0 index: Int) -> CGFloat { (CGFloat(index) + 0.5) * width / 10 }

    private func arrange(_ row: AlternatesRow, centerX: CGFloat, containerWidth: CGFloat? = nil) -> AlternatesRow.Arranged {
        row.arranged(centerX: centerX, cellWidth: cell, containerWidth: containerWidth ?? width)
    }

    /// 默认那格正对按键中心并且已经选中；手指不挪就是它。
    private func assertCentered(_ arranged: AlternatesRow.Arranged, centerX: CGFloat, main: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(arranged.options[arranged.selected], main, file: file, line: line)
        let mainMinX = arranged.minX + cell * CGFloat(arranged.selected)
        XCTAssertEqual(mainMinX + cell / 2, centerX, accuracy: 0.01, file: file, line: line)
        XCTAssertGreaterThanOrEqual(arranged.minX, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(arranged.minX + cell * CGFloat(arranged.options.count), width, file: file, line: line)
    }

    /// 「，。」放在空格右边（录屏里的情况）和左边：顺序一样，「，」在手指正上方。
    /// 竖屏 375：右边时键中心 = 375 − 回车 2.5 格 − 半格 = 262.5；左边时在 123、表情、中/英后面，约 140–165。
    func testQuickPunctCenteredBothSides() {
        for centerX: CGFloat in [262.5, 140, 165] {
            let zh = arrange(QuickPunct.row(chinese: true), centerX: centerX)
            XCTAssertEqual(zh.options, ["、", "！", "？", "，", "。", "；"])
            assertCentered(zh, centerX: centerX, main: "，")
            let en = arrange(QuickPunct.row(chinese: false), centerX: centerX)
            XCTAssertEqual(en.options, ["'", "!", "?", ",", ".", ";"])
            assertCentered(en, centerX: centerX, main: ",")
        }
    }

    /// 横屏（按键区约 800 宽，回车 2 格）：放在空格右边也一样。
    func testQuickPunctLandscape() {
        let landscape: CGFloat = 800, centerX = landscape - landscape / 10 * 2.5
        let arranged = arrange(QuickPunct.row(chinese: true), centerX: centerX, containerWidth: landscape)
        XCTAssertEqual(arranged.options, ["、", "！", "？", "，", "。", "；"])
        XCTAssertEqual(arranged.options[arranged.selected], "，")
        XCTAssertEqual(arranged.minX + cell * CGFloat(arranged.selected) + cell / 2, centerX, accuracy: 0.01)
    }

    func testEnglishCommaKey() {
        // 只用英文时逗号键在 123、表情后面，中心约 120。
        let centerX: CGFloat = 120
        let arranged = arrange(.englishComma, centerX: centerX)
        XCTAssertEqual(arranged.options, ["!", "?", ",", "'"])
        assertCentered(arranged, centerX: centerX, main: ",")
    }

    /// 字母：声调朝键盘中间，数字朝外边；贴边放不下的接到另一边。
    func testLettersFirstRow() {
        let accents: [String: [String]] = ["e": ["ē", "é", "ě", "è", "ê"], "u": ["ū", "ú", "ǔ", "ù", "ü"],
                                           "i": ["ī", "í", "ǐ", "ì"], "o": ["ō", "ó", "ǒ", "ò"]]
        let expected: [String: [String]] = [
            "q": ["q", "1"], "e": ["3", "e", "ē", "é", "ě", "è", "ê"],
            "u": ["ü", "ù", "ǔ", "ú", "ū", "u", "7"], "i": ["ì", "ǐ", "í", "ī", "i", "8"],
            "o": ["ò", "ǒ", "ó", "ō", "o", "9"], "p": ["0", "p"],
        ]
        let letters = "qwertyuiop".map(String.init), digits = "1234567890".map(String.init)
        for (index, letter) in letters.enumerated() {
            let centerX = letterCenter(row0: index)
            let row = AlternatesRow.letter(letter, digit: digits[index], accents: accents[letter] ?? [],
                                           onLeftHalf: centerX < width / 2)!
            let arranged = arrange(row, centerX: centerX)
            assertCentered(arranged, centerX: centerX, main: letter)
            if let options = expected[letter] { XCTAssertEqual(arranged.options, options, letter) }
        }
    }

    func testLettersWithoutDigit() {
        XCTAssertNil(AlternatesRow.letter("b", digit: nil, accents: [], onLeftHalf: true))
        let a = AlternatesRow.letter("a", digit: nil, accents: ["ā", "á", "ǎ", "à"], onLeftHalf: true)!
        XCTAssertEqual(arrange(a, centerX: 37.5).options, ["a", "ā", "á", "ǎ", "à"])
        let n = AlternatesRow.letter("n", digit: nil, accents: ["ñ"], onLeftHalf: false)!
        XCTAssertEqual(arrange(n, centerX: 262.5).options, ["ñ", "n"])
    }

    /// 按了 ⇧：字母换成大写，位置不变。
    func testUppercased() {
        let row = AlternatesRow.letter("u", digit: "7", accents: ["ū", "ú"], onLeftHalf: false)!.uppercased()
        XCTAssertEqual(row, AlternatesRow(main: "U", left: ["Ū", "Ú"], right: ["7"]))
    }

    /// 一边放不下：多出来的接到另一边后面，默认那格不动。
    func testOverflowGoesToOtherSide() {
        let row = AlternatesRow(main: "x", left: ["1", "2", "3"], right: ["a"])
        // 左边只放得下 1 格。
        let arranged = arrange(row, centerX: 34 + 17 + 5)
        XCTAssertEqual(arranged.options, ["1", "x", "a", "2", "3"])
        assertCentered(arranged, centerX: 56, main: "x")
    }

    /// iPad 每格 56：u 在竖屏 11 寸上也正对按键。
    func testPadCell() {
        let padWidth: CGFloat = 820, padCell: CGFloat = 56
        let row = QuickPunct.row(chinese: true)
        let centerX = padWidth - 70
        let arranged = row.arranged(centerX: centerX, cellWidth: padCell, containerWidth: padWidth)
        XCTAssertEqual(arranged.options[arranged.selected], "，")
        XCTAssertEqual(arranged.minX + padCell * CGFloat(arranged.selected) + padCell / 2, centerX, accuracy: 0.01)
    }
}
