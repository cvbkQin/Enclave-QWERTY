import XCTest

/// 「常用 / 剪贴板」合并面板和常用语的标题、简码（对齐清单第 62 条，CW1–CW4）。
final class QuickPanelTests: XCTestCase {
    // MARK: - 两栏比例

    func testStoredSplitFallsBackToHalf() {
        XCTAssertEqual(QuickSplit.stored(nil), 0.5)
        XCTAssertEqual(QuickSplit.stored(.nan), 0.5)
        XCTAssertEqual(QuickSplit.stored(1.4), 0.5)
        XCTAssertEqual(QuickSplit.stored(0), 0)
        XCTAssertEqual(QuickSplit.stored(0.62), 0.62, accuracy: 0.0001)
    }

    func testSettleSnapsNearThirdsAndHalf() {
        XCTAssertEqual(QuickSplit.settle(0.52).split, 0.5)
        XCTAssertTrue(QuickSplit.settle(0.52).snapped)
        XCTAssertEqual(QuickSplit.settle(0.36).split, 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(QuickSplit.settle(0.64).split, 2.0 / 3, accuracy: 0.0001)
        let free = QuickSplit.settle(0.42)
        XCTAssertEqual(free.split, 0.42, accuracy: 0.0001)
        XCTAssertFalse(free.snapped)
    }

    func testSettleCollapsesBelowOneSixth() {
        XCTAssertEqual(QuickSplit.settle(0.1).split, 0)
        XCTAssertEqual(QuickSplit.settle(0.9).split, 1)
        XCTAssertEqual(QuickSplit.settle(-0.3).split, 0)
        XCTAssertEqual(QuickSplit.collapsedSide(0), .phrases)
        XCTAssertEqual(QuickSplit.collapsedSide(1), .clipboard)
        XCTAssertNil(QuickSplit.collapsedSide(0.5))
    }

    func testWidthsKeepAStripForEachColumn() {
        let half = QuickSplit.widths(split: 0.5, available: 300)
        XCTAssertEqual(half.left, 150)
        XCTAssertEqual(half.right, 150)
        let left = QuickSplit.widths(split: 0, available: 300)
        XCTAssertEqual(left.left, QuickSplit.stripWidth)
        XCTAssertEqual(left.right, 300 - QuickSplit.stripWidth)
        let right = QuickSplit.widths(split: 1, available: 300)
        XCTAssertEqual(right.right, QuickSplit.stripWidth)
        // 拖到很边上但还没松手：展开的栏也不比竖条窄。
        XCTAssertEqual(QuickSplit.widths(split: 0.02, available: 300).left, QuickSplit.stripWidth)
    }

    func testFractionLabel() {
        XCTAssertEqual(QuickSplit.fraction(0.5), "1/2")
        XCTAssertEqual(QuickSplit.fraction(0.34), "1/3")
        XCTAssertEqual(QuickSplit.fraction(0.42), "42%")
    }

    // MARK: - 常用语

    func testDisplayCyclesThroughThreeModes() {
        XCTAssertEqual(PhraseDisplay.both.next, .title)
        XCTAssertEqual(PhraseDisplay.title.next, .content)
        XCTAssertEqual(PhraseDisplay.content.next, .both)
    }

    func testPhraseDecodesOldShapeAndTitles() throws {
        let data = Data(#"[{"text":"好的"},{"title":"  ","text":"a\nb","shortcut":"ab"}]"#.utf8)
        let phrases = try JSONDecoder().decode([KeyboardPhrase].self, from: data)
        XCTAssertEqual(phrases[0], KeyboardPhrase(text: "好的"))
        XCTAssertNil(phrases[1].displayTitle)
        XCTAssertEqual(phrases[1].flattened, "a b")
        XCTAssertEqual(phrases[1].shortcut, "ab")
    }

    func testMergedKeepsFirstPositionAndFillsMissingFields() {
        let merged = KeyboardPhrase.merged([
            KeyboardPhrase(text: "地址"),
            KeyboardPhrase(text: "邮箱", shortcut: "yx"),
            KeyboardPhrase(title: "公司", text: "地址", shortcut: "gsdz"),
            KeyboardPhrase(title: "另一个", text: "邮箱", shortcut: "mail"),
            KeyboardPhrase(text: ""),
        ])
        XCTAssertEqual(merged, [
            KeyboardPhrase(title: "公司", text: "地址", shortcut: "gsdz"),
            KeyboardPhrase(title: "另一个", text: "邮箱", shortcut: "yx"),
        ])
    }

    func testBackupMergeOfPhrases() {
        let current = [KeyboardPhrase(text: "好的"), KeyboardPhrase(text: "在吗")]
        let backup = [KeyboardPhrase(title: "问候", text: "在吗", shortcut: "zm"), KeyboardPhrase(text: "收到")]
        XCTAssertEqual(BackupMerge.keyboardPhrases(current: current, backup: backup, mode: .merge), [
            KeyboardPhrase(text: "好的"),
            KeyboardPhrase(title: "问候", text: "在吗", shortcut: "zm"),
            KeyboardPhrase(text: "收到"),
        ])
        XCTAssertEqual(BackupMerge.keyboardPhrases(current: current, backup: backup, mode: .replace), backup)
    }

    func testShortcutEntriesOnlyForPhrasesWithShortcut() {
        let entries = CommonWordStore.phraseShortcutEntries([
            KeyboardPhrase(text: "不进候选"),
            KeyboardPhrase(title: "地址", text: "北京市\n海淀区", shortcut: "GS-dz"),
        ])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].text, "北京市 海淀区")
        XCTAssertEqual(entries[0].code, "gsdz")
    }

    func testPhraseTablePutsShortcutsAboveCommonWords() {
        let table = CommonWordStore.phraseTable([(text: "公司", code: "gs")], nineKey: false,
                                                priority: [(text: "北京市海淀区", code: "gsdz")])
        let lines = table.split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(lines.suffix(2)), ["北京市海淀区\tgsdz\t101", "公司\tgs\t100"])
        let nine = CommonWordStore.phraseTable([], nineKey: true, priority: [(text: "北京市海淀区", code: "gsdz")])
        XCTAssertTrue(nine.contains("北京市海淀区\t4739\t101"))
    }
}
