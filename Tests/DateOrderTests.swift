import XCTest

/// 比时间先后不走 Foundation 的 Date <= / >=（iPadOS 27.2 测试版上调用会跳到 0 地址闪退，见 DateOrder.swift）。
/// 这里只核对换了写法以后结果和原来一样。
final class DateOrderTests: XCTestCase {
    private let early = Date(timeIntervalSince1970: 100)
    private let late = Date(timeIntervalSince1970: 200)

    func testOrder() {
        XCTAssertTrue(late.isAfter(early))
        XCTAssertFalse(early.isAfter(late))
        XCTAssertFalse(early.isAfter(early))
        XCTAssertTrue(early.isBefore(late))
        XCTAssertFalse(late.isBefore(early))
        XCTAssertFalse(late.isBefore(late))
    }

    func testLater() {
        XCTAssertEqual(Date.later(early, late), late)
        XCTAssertEqual(Date.later(late, early), late)
        XCTAssertEqual(Date.later(early, early), early)
        XCTAssertEqual(Date.later(.distantPast, early), early)
    }

    /// 合并时取最新的一条；时间一样取先传进来的（SyncMerge.latest 原来的规则不变）。
    func testLatestKeepsFirstOnTie() {
        typealias E = SyncMerge.Entry<String>
        let entries = [E(value: "a", time: early), E(value: "b", time: late), E(value: "c", time: late), E(value: nil, time: .distantFuture)]
        XCTAssertEqual(SyncMerge.latest(entries)?.value, "b")
        XCTAssertNil(SyncMerge.latest([E(value: nil, time: late)]))
    }

    func testStampAfterOld() {
        XCTAssertEqual(SyncMerge.stamp(now: late, after: early), late)
        XCTAssertEqual(SyncMerge.stamp(now: early, after: late), late.addingTimeInterval(0.001))
        XCTAssertEqual(SyncMerge.stamp(now: early, after: nil), early)
    }
}
