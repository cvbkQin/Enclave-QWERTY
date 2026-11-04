import XCTest

/// 扩展词库（B6）的文件格式：细胞词库、Rime 词库的读取，接进 import_tables。
final class ExtDictFormatTests: XCTestCase {
    /// 按格式说明拼一个最小的细胞词库：词库名、两个音节、一组词（同音的两个词）。
    private func scel(title: String, syllables: [String], groups: [(indexes: [Int], words: [(String, Int)])]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x2628)
        bytes[0] = 0x40; bytes[1] = 0x15
        func utf16(_ text: String) -> [UInt8] { text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }
        func u16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
        let name = utf16(title)
        bytes.replaceSubrange(0x130..<0x130 + name.count, with: name)
        var table = u16(syllables.count) + [0, 0]
        for (index, syllable) in syllables.enumerated() {
            let text = utf16(syllable)
            table += u16(index) + u16(text.count) + text
        }
        bytes.replaceSubrange(0x1540..<0x1540 + table.count, with: table)
        for group in groups {
            bytes += u16(group.words.count) + u16(group.indexes.count * 2) + group.indexes.flatMap(u16)
            for (word, freq) in group.words {
                let text = utf16(word)
                bytes += u16(text.count) + text + u16(10) + u16(freq) + [UInt8](repeating: 0, count: 8)
            }
        }
        return Data(bytes)
    }

    func testScel() throws {
        let data = scel(title: "测试词库", syllables: ["ya", "suo", "hu", "tao"],
                        groups: [([0, 1], [("亚索", 300), ("压缩", 10)]), ([2, 3], [("胡桃", 200)])])
        let parsed = try ExtDictFormat.parse(data, fileName: "游戏.scel")
        XCTAssertEqual(parsed.title, "测试词库")
        XCTAssertEqual(parsed.entries.map(\.word), ["亚索", "压缩", "胡桃"])
        XCTAssertEqual(parsed.entries.map(\.code), ["ya suo", "ya suo", "hu tao"])
        XCTAssertEqual(parsed.entries[0].weight, 9)
        XCTAssertTrue(parsed.entries.allSatisfy { (1...9).contains($0.weight) })
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try ExtDictFormat.parse(Data("<html></html>".utf8), fileName: "下载.html")) {
            XCTAssertEqual($0 as? ExtDictFormat.ParseError, .unsupported)
        }
        XCTAssertThrowsError(try ExtDictFormat.parse(Data(repeating: 0, count: 20000), fileName: "坏.scel")) {
            XCTAssertEqual($0 as? ExtDictFormat.ParseError, .unsupported)
        }
        XCTAssertThrowsError(try ExtDictFormat.parse(Data("---\nname: x\n...\nhello\tworld\n".utf8), fileName: "x.dict.yaml")) {
            XCTAssertEqual($0 as? ExtDictFormat.ParseError, .empty)
        }
    }

    func testRime() throws {
        let text = """
        # 注释
        ---
        name: demo
        ...
        银行\tyín háng\t500
        绿色\tlǜ sè\t5
        没拼音
        abc\tabc\t3
        银行\tyin hang\t1
        肉鸽\trou'ge
        """
        let entries = try ExtDictFormat.parse(Data(text.utf8), fileName: "demo.dict.yaml").entries
        XCTAssertEqual(entries.map(\.word), ["银行", "绿色", "肉鸽"])
        XCTAssertEqual(entries.map(\.code), ["yin hang", "lv se", "rou ge"])
        XCTAssertEqual(entries[0].weight, 9)
    }

    func testWriteAndCount() {
        let entries = [ExtDictFormat.Entry(word: "亚索", code: "ya suo", weight: 9), .init(word: "胡桃", code: "hu tao", weight: 5)]
        let text = ExtDictFormat.rimeText(entries, id: "imp1", source: "游戏.scel", version: "2026-10-30")
        XCTAssertTrue(text.contains("name: ext_imp1\n"))
        XCTAssertEqual(ExtDictFormat.entryCount(text), 2)
        XCTAssertEqual(ExtDictFormat.parseRime(text), entries)
    }

    func testPatchImportTables() {
        let dict = """
        ---
        name: enclave
        import_tables:
          - cn_dicts/zi
          - cn_dicts/yiren
        ...

        """
        let patched = ExtDictFormat.patchImportTables(dict, tables: ["ext_dicts/ext_lol", "ext_dicts/ext_meme"])
        XCTAssertTrue(patched.contains("  - cn_dicts/yiren\n  - ext_dicts/ext_lol\n  - ext_dicts/ext_meme\n...\n"))
        XCTAssertEqual(ExtDictFormat.patchImportTables(dict, tables: []), dict)
    }
}
