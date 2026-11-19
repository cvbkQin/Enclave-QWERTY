import XCTest

/// 隐私政策按包里有没有 iCloud 同步能力去掉或换掉几段（05 标，04 三审第 5 条）。
final class PolicyFilterTests: XCTestCase {
    func testNoMarkersUnchanged() {
        let text = "## 一\n\n第一段。\n\n1. 甲\n2. 乙"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), text)
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), text)
    }

    func testInlineSwap() {
        let text = "数据保存在设备上[[icloud]]，开启 iCloud 同步时也保存在 iCloud 中[[/icloud]][[no-icloud]]，不会离开设备[[/no-icloud]]。"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), "数据保存在设备上，开启 iCloud 同步时也保存在 iCloud 中。")
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), "数据保存在设备上，不会离开设备。")
    }

    func testWholeParagraphsRemovedWithoutExtraBlankLines() {
        let text = "前一段。\n\n[[icloud]]**iCloud 同步：** 第一段。\n\n第二段。[[/icloud]]\n\n后一段。"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), "前一段。\n\n后一段。")
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), "前一段。\n\n**iCloud 同步：** 第一段。\n\n第二段。\n\n后一段。")
    }

    func testListItemRemovedWithoutSplittingList() {
        let text = "1. 甲\n[[icloud]]2. 乙[[/icloud]]\n3. 丙"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), "1. 甲\n3. 丙")
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), "1. 甲\n2. 乙\n3. 丙")
    }

    func testBlocksDoNotSwallowTextBetweenThem() {
        let text = "[[icloud]]甲[[/icloud]]中间[[icloud]]乙[[/icloud]]\n下一行"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), "中间\n下一行")
    }
}
