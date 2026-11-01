import XCTest

/// AI 栏固定风格（AK5）：最多 5 个、按固定先后、删掉的风格不占名额、旧设置能解。
final class PinnedStylesTests: XCTestCase {
    func testPinOrderAndLimit() {
        var settings = EnclaveSettings()
        let all = settings.styles + settings.answerStyles
        XCTAssertGreaterThanOrEqual(all.count, 6)
        for style in all.prefix(5) { XCTAssertTrue(settings.togglePin(style.id)) }
        XCTAssertEqual(settings.pinnedStyles.map(\.style.id), all.prefix(5).map(\.id))
        // 第 6 个加不进去。
        XCTAssertFalse(settings.togglePin(all[5].id))
        XCTAssertFalse(settings.isPinned(all[5].id))
        // 取消一个后能加，接在最后。
        XCTAssertTrue(settings.togglePin(all[1].id))
        XCTAssertTrue(settings.togglePin(all[5].id))
        XCTAssertEqual(settings.pinnedStyles.last?.style.id, all[5].id)
    }

    func testAnswerFlagAndDeletedStyles() {
        var settings = EnclaveSettings()
        let rewrite = settings.styles[0], answer = settings.answerStyles[0]
        settings.togglePin(rewrite.id)
        settings.togglePin(answer.id)
        XCTAssertEqual(settings.pinnedStyles.map(\.answer), [false, true])
        // 删掉的风格不显示，也不占名额。
        settings.styles.removeAll { $0.id == rewrite.id }
        XCTAssertEqual(settings.pinnedStyles.map(\.style.id), [answer.id])
        for _ in 0..<4 { settings.togglePin(UUID()) }
        let extra = settings.answerStyles[1]
        XCTAssertTrue(settings.togglePin(extra.id))
    }

    func testDecodeRoundTripAndOldData() throws {
        var settings = EnclaveSettings()
        settings.togglePin(settings.styles[1].id)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(EnclaveSettings.self, from: data)
        XCTAssertEqual(decoded.pinnedStyleIDs, settings.pinnedStyleIDs)
        // 旧版本存的设置里没有这一项。
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["pinnedStyleIDs"] = nil
        let old = try JSONDecoder().decode(EnclaveSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.pinnedStyleIDs, [])
    }
}
