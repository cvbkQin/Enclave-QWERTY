import XCTest

/// 备份与恢复（B3）：zip 打包、Key 加密、恢复时的合并规则。
final class BackupTests: XCTestCase {
    // MARK: - 打包

    func testArchiveRoundTrip() throws {
        let files: [(name: String, data: Data)] = [
            ("manifest.json", Data(#"{"format":1}"#.utf8)),
            ("常用词.json", Data("你好，飞地".utf8)),
            ("empty.txt", Data()),
        ]
        let read = try BackupArchive.read(BackupArchive.write(files))
        XCTAssertEqual(read.count, 3)
        for file in files { XCTAssertEqual(read[file.name], file.data, file.name) }
    }

    func testArchiveReadsDeflate() throws {
        // Python zipfile 用 deflate 打的包（别的工具重新压缩过的备份也要能读）。
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "backup-deflate", withExtension: "enclave"))
        let read = try BackupArchive.read(Data(contentsOf: url))
        XCTAssertEqual(read["manifest.json"], Data(#"{"format":1}"#.utf8))
        let words = try XCTUnwrap(read["common-words.json"].map { String(decoding: $0, as: UTF8.self) })
        XCTAssertTrue(words.hasPrefix(#"{"words":[],"keyboardTexts":["你好，飞地"]}"#))
        XCTAssertEqual(read["common-words.json"]?.count, 960)
    }

    func testArchiveRejectsDamage() throws {
        XCTAssertThrowsError(try BackupArchive.read(Data("not a zip at all, just some text".utf8)))
        var data = BackupArchive.write([("a.txt", Data("hello world".utf8))])
        // 改掉内容里的一个字节：CRC 对不上。
        let index = try XCTUnwrap(data.range(of: Data("hello".utf8))).lowerBound
        data[index] = UInt8(ascii: "j")
        XCTAssertThrowsError(try BackupArchive.read(data))
    }

    func testCRC32() {
        XCTAssertEqual(BackupArchive.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    // MARK: - 加密

    func testCryptoRoundTrip() throws {
        let plain = Data(#"{"apiKey":"sk-test"}"#.utf8)
        let sealed = try XCTUnwrap(BackupCrypto.seal(plain, password: "飞地 2026", iterations: 1000))
        XCTAssertEqual(sealed.salt.count, 16)
        XCTAssertNotEqual(sealed.data, plain)
        XCTAssertEqual(BackupCrypto.open(sealed, password: "飞地 2026"), plain)
        XCTAssertNil(BackupCrypto.open(sealed, password: "飞地 2027"))
        // 同一个密码两次加密，盐不一样，结果也不一样。
        let again = try XCTUnwrap(BackupCrypto.seal(plain, password: "飞地 2026", iterations: 1000))
        XCTAssertNotEqual(again.salt, sealed.salt)
    }

    func testPBKDF2KnownAnswer() throws {
        // RFC 7914 第 11 节的 PBKDF2-HMAC-SHA256 测试向量（P="passwd"，S="salt"，c=1）。
        let key = try XCTUnwrap(BackupCrypto.deriveKey(password: "passwd", salt: Data("salt".utf8), iterations: 1))
        let hex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
    }

    // MARK: - 合并

    private func style(_ name: String, _ prompt: String) -> StylePreset { StylePreset(name: name, prompt: prompt) }

    func testStylesMerge() {
        let a = style("正式", "旧的正式"), b = style("口语", "口语")
        let c = style("正式", "新的正式"), d = style("撒娇", "撒娇")
        let result = BackupMerge.styles(current: .init(list: [a, b], selectedID: b.id),
                                        backup: .init(list: [c, d], selectedID: c.id), mode: .merge)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.styles.list.map(\.name), ["正式", "口语", "撒娇"])
        // 同名的用备份里的提示词，id 留现有的；备份里的默认是同名那条，默认跟着换到现有的 id。
        XCTAssertEqual(result.styles.list[0].id, a.id)
        XCTAssertEqual(result.styles.list[0].prompt, "新的正式")
        XCTAssertEqual(result.styles.selectedID, a.id)
    }

    func testStylesReplace() {
        let a = style("正式", "正式"), c = style("撒娇", "撒娇")
        let result = BackupMerge.styles(current: .init(list: [a], selectedID: a.id),
                                        backup: .init(list: [c], selectedID: UUID()), mode: .replace)
        XCTAssertEqual(result.styles.list, [c])
        XCTAssertNil(result.styles.selectedID)
        XCTAssertEqual(result.added, 1)
    }

    func testCommonWordsMerge() {
        let mine = CommonWord(text: "飞地", pinyin: "fei di")
        let same = CommonWord(text: "飞地", pinyin: "fei di", shortcut: "fd")
        let new = CommonWord(text: "输入法", pinyin: "shu ru fa")
        let contact = CommonWord(text: "张三", pinyin: "zhang san", source: .contact)
        let merged = BackupMerge.commonWords(current: [mine], backup: [same, new, contact], mode: .merge)
        XCTAssertEqual(merged.words.map(\.text), ["飞地", "输入法"])
        XCTAssertEqual(merged.words[0].shortcut, "")
        XCTAssertEqual(merged.added, 1)
        XCTAssertEqual(merged.existing, 1)

        let replaced = BackupMerge.commonWords(current: [mine], backup: [new, contact], mode: .replace)
        XCTAssertEqual(replaced.words.map(\.text), ["输入法"])
    }

    func testKeyboardTexts() {
        XCTAssertEqual(BackupMerge.keyboardTexts(current: ["好的", "在吗"], backup: ["在吗", "收到"], mode: .merge), ["好的", "在吗", "收到"])
        XCTAssertEqual(BackupMerge.keyboardTexts(current: ["好的"], backup: ["收到"], mode: .replace), ["收到"])
    }

    private func entry(_ id: String, _ seconds: Double) throws -> AIHistoryEntry {
        let json = #"{"id":"\#(id)","kind":"polish","date":\#(seconds),"original":"原文","context":"","versions":[{"text":"结果","edited":false}]}"#
        return try JSONDecoder().decode(AIHistoryEntry.self, from: Data(json.utf8))
    }

    func testHistoryMerge() throws {
        let old = try entry("a", 100), mid = try entry("b", 200), new = try entry("c", 300)
        let merged = BackupMerge.history(current: [old], backup: [new, old, mid], mode: .merge)
        XCTAssertEqual(merged.entries.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(merged.added, 2)
        let replaced = BackupMerge.history(current: [old], backup: [mid], mode: .replace)
        XCTAssertEqual(replaced.entries.map(\.id), ["b"])
    }

    func testSettingsKeepStyles() throws {
        var current = EnclaveSettings()
        current.styles = [style("我的", "我的")]
        current.traditionalOutput = false
        var backup = EnclaveSettings()
        backup.traditionalOutput = true
        backup.model = "kimi-k3"
        backup.styles = [style("别人的", "别人的")]
        let object = try BackupMerge.settingsObject(backup)
        XCTAssertNil(object["styles"])
        let restored = try BackupMerge.restoreSettings(object, keepingStylesOf: current)
        XCTAssertTrue(restored.traditionalOutput)
        XCTAssertEqual(restored.model, "kimi-k3")
        XCTAssertEqual(restored.styles.map(\.name), ["我的"])
    }

    func testLearnedCount() {
        let snapshot = """
        # Rime user dictionary
        #@/db_name\tenclave.userdb
        #@/tick\t42
        fei di \t飞地\tc=3 d=0.9 t=40
        shu ru fa \t输入法\tc=1 d=0.5 t=41
        ni hao \t你好\tc=-1 d=0.1 t=42
        """
        XCTAssertEqual(BackupMerge.learnedCount(snapshot), 2)
        XCTAssertEqual(BackupMerge.learnedCount(""), 0)
    }
}
