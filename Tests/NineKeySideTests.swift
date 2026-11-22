import XCTest

/// iPad 全宽 9 键「九键位置」（PK3、PK4）：默认右边，旧设置里没有这一项也是右边，认不得的值不让整份设置读坏。
final class NineKeySideTests: XCTestCase {
    private func decode(_ json: String) throws -> EnclaveSettings {
        try JSONDecoder().decode(EnclaveSettings.self, from: Data(json.utf8))
    }

    func testDefaultAndDecode() throws {
        XCTAssertEqual(EnclaveSettings().nineKeySide, .right)
        XCTAssertEqual(try decode("{}").nineKeySide, .right)
        XCTAssertEqual(try decode("{\"nineKeySide\": \"left\"}").nineKeySide, .left)
        let odd = try decode("{\"nineKeySide\": \"middle\", \"keyboardLayout\": \"nineKey\"}")
        XCTAssertEqual(odd.nineKeySide, .right)
        XCTAssertEqual(odd.keyboardLayout, .nineKey)

        var settings = EnclaveSettings()
        settings.nineKeySide = .left
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(EnclaveSettings.self, from: data).nineKeySide, .left)
    }

    /// 键盘排法类设置，iCloud 不同步。
    func testNotSynced() {
        var source = EnclaveSettings()
        source.nineKeySide = .right
        var other = EnclaveSettings()
        other.nineKeySide = .left
        SyncMerge.StyleProfile(settings: source).apply(to: &other)
        XCTAssertEqual(other.nineKeySide, .left)
        SyncMerge.EndpointProfile(settings: source, keys: [:]).apply(to: &other)
        XCTAssertEqual(other.nineKeySide, .left)
    }

    /// iPad 11 寸「字母上的数字和符号」（PA3、PK1）：默认开，旧设置里没有也是开，关了能存住，不同步。
    func testPadLetterHints() throws {
        XCTAssertTrue(EnclaveSettings().padLetterHints)
        XCTAssertTrue(try decode("{}").padLetterHints)
        XCTAssertFalse(try decode("{\"padLetterHints\": false}").padLetterHints)
        XCTAssertTrue(try decode("{\"padLetterHints\": \"no\"}").padLetterHints)

        var settings = EnclaveSettings()
        settings.padLetterHints = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertFalse(try JSONDecoder().decode(EnclaveSettings.self, from: data).padLetterHints)

        var other = EnclaveSettings()
        other.padLetterHints = false
        SyncMerge.StyleProfile(settings: EnclaveSettings()).apply(to: &other)
        SyncMerge.EndpointProfile(settings: EnclaveSettings(), keys: [:]).apply(to: &other)
        XCTAssertFalse(other.padLetterHints)
    }
}
