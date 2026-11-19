import XCTest

/// 隐私政策按包里有没有 iCloud 同步能力取标记的前半或后半（05 标，04 三审第 5 条）。
final class PolicyFilterTests: XCTestCase {
    func testNoMarkersUnchanged() {
        let text = "## 一\n\n第一段。\n\n1. 甲\n2. 乙"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), text)
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), text)
    }

    func testSwap() {
        let text = "数据保存在设备上[[iCloud:，开启同步时也保存在 iCloud 中||，不会离开设备]]。"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), "数据保存在设备上，开启同步时也保存在 iCloud 中。")
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), "数据保存在设备上，不会离开设备。")
    }

    func testDropWithoutAlternative() {
        let text = "前一段。[[iCloud:\n\n**iCloud 同步：** 第一段。\n\n第二段。]]\n\n后一段。"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), "前一段。\n\n后一段。")
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), "前一段。\n\n**iCloud 同步：** 第一段。\n\n第二段。\n\n后一段。")
    }

    func testSeveralMarkersStayApart() {
        let text = "[[iCloud:甲]]中[[iCloud:乙||丙]]尾"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), "中丙尾")
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: true), "甲中乙尾")
    }

    func testUnclosedMarkerKeepsRest() {
        let text = "前[[iCloud:没有结尾"
        XCTAssertEqual(PolicyFilter.apply(text, iCloudSync: false), text)
    }
}
