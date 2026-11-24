import XCTest

/// 26 键空格旁的「，。」键（对齐清单第 80 条）：打出的标点和「放哪边」这个设置。
final class QuickPunctTests: XCTestCase {
    private func decode(_ json: String) throws -> EnclaveSettings {
        try JSONDecoder().decode(EnclaveSettings.self, from: Data(json.utf8))
    }

    func testMarks() {
        XCTAssertEqual(QuickPunct.tap(chinese: true), "，")
        XCTAssertEqual(QuickPunct.up(chinese: true), "。")
        XCTAssertEqual(QuickPunct.tap(chinese: false), ",")
        XCTAssertEqual(QuickPunct.up(chinese: false), ".")
        // 长按那一排（T92）：点一下打的那个是默认那格，往右第一个是往上划的那个。
        for chinese in [true, false] {
            let row = QuickPunct.row(chinese: chinese)
            XCTAssertEqual(row.main, QuickPunct.tap(chinese: chinese))
            XCTAssertEqual(row.right.first, QuickPunct.up(chinese: chinese))
            let all = [row.main] + row.left + row.right
            XCTAssertEqual(all.count, 6)
            XCTAssertEqual(Set(all).count, all.count)
        }
        XCTAssertEqual(QuickPunct.row(chinese: true), AlternatesRow(main: "，", left: ["？", "！", "、"], right: ["。", "；"]))
        XCTAssertEqual(QuickPunct.row(chinese: false), AlternatesRow(main: ",", left: ["?", "!", "'"], right: [".", ";"]))
    }

    /// 默认右边；旧版本的设置里没有这一项，读出来也是右边；认不得的值不让整份设置读坏。
    func testSideSetting() throws {
        XCTAssertEqual(EnclaveSettings().quickPunctSide, .right)
        XCTAssertEqual(try decode("{}").quickPunctSide, .right)
        XCTAssertEqual(try decode("{\"quickPunctSide\": \"left\"}").quickPunctSide, .left)
        let odd = try decode("{\"quickPunctSide\": \"middle\", \"keyboardLayout\": \"nineKey\"}")
        XCTAssertEqual(odd.quickPunctSide, .right)
        XCTAssertEqual(odd.keyboardLayout, .nineKey)

        var settings = EnclaveSettings()
        settings.quickPunctSide = .left
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(EnclaveSettings.self, from: data).quickPunctSide, .left)
    }

    /// 键盘手感类设置，iCloud 不同步：风格、接口两份同步记录写回时都不动它。
    func testSideIsNotSynced() {
        var source = EnclaveSettings()
        source.quickPunctSide = .right
        var other = EnclaveSettings()
        other.quickPunctSide = .left
        SyncMerge.StyleProfile(settings: source).apply(to: &other)
        XCTAssertEqual(other.quickPunctSide, .left)
        SyncMerge.EndpointProfile(settings: source, keys: [:]).apply(to: &other)
        XCTAssertEqual(other.quickPunctSide, .left)
    }
}
