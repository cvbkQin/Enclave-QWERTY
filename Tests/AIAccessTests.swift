import XCTest

/// 14 天试用改成 0 元内购（05 上架风险报告高 2）：点了「开始试用」才算，没开始时和到期后一样每天 10 次。
final class AIAccessTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour))!
    }

    override func setUp() {
        super.setUp()
        AIAccess.setDebug(nil)
        AIAccess.recordPurchase(unlocked: false, date: nil)
        AIAccess.recordTrial(start: nil)
    }

    override func tearDown() {
        AIAccess.recordTrial(start: nil)
        AIAccess.recordPurchase(unlocked: false, date: nil)
        super.tearDown()
    }

    /// 开始那天算第 1 天，第 14 天还在试用，第 15 天 0 点到期。
    func testTrialDays() {
        let start = date(1, 22)
        XCTAssertEqual(AIAccess.trialState(start: start, now: date(1, 23), calendar: calendar),
                       .trial(daysLeft: 14, ends: date(15, 0)))
        XCTAssertEqual(AIAccess.trialState(start: start, now: date(14, 23), calendar: calendar),
                       .trial(daysLeft: 1, ends: date(15, 0)))
        XCTAssertEqual(AIAccess.trialState(start: start, now: date(15, 0), calendar: calendar), .expired(ended: date(15, 0)))
    }

    /// 到期日统一写「用到 X 月 Y 日」：ends（第 15 天 0 点）减一天，就是第 14 天。
    func testLastTrialDay() {
        XCTAssertEqual(AIAccess.lastTrialDay(ends: date(15, 0), calendar: calendar), date(14, 0))
    }

    /// 没领试用商品：不是自动开始的试用，按每天次数走。
    func testNotStartedUsesDailyQuota() {
        XCTAssertEqual(AIAccess.current, .notStarted)
        XCTAssertTrue(AIAccess.notStarted.usesDailyQuota)
        XCTAssertTrue(AIAccess.expired(ended: Date()).usesDailyQuota)
        XCTAssertFalse(AIAccess.trial(daysLeft: 3, ends: Date()).usesDailyQuota)
        XCTAssertFalse(AIAccess.unlocked(purchased: nil).usesDailyQuota)
    }

    /// 领了试用商品从购买日算；退款（记录清掉）回到没开始；买断优先于试用。
    func testTrialRecord() {
        let now = Date()
        AIAccess.recordTrial(start: now)
        guard case .trial(let days, _) = AIAccess.current else { return XCTFail("\(AIAccess.current)") }
        XCTAssertEqual(days, AIAccess.trialDays)

        AIAccess.recordTrial(start: now.addingTimeInterval(-30 * 86_400))
        guard case .expired = AIAccess.current else { return XCTFail("\(AIAccess.current)") }

        AIAccess.recordPurchase(unlocked: true, date: now)
        guard case .unlocked = AIAccess.current else { return XCTFail("\(AIAccess.current)") }

        AIAccess.recordPurchase(unlocked: false, date: nil)
        AIAccess.recordTrial(start: nil)
        XCTAssertEqual(AIAccess.current, .notStarted)
    }

    func testDebugNotStarted() {
        AIAccess.setDebug("notStarted")
        defer { AIAccess.setDebug(nil) }
        XCTAssertEqual(AIAccess.current(now: Date()), .notStarted)
    }

    func testProductIDs() {
        XCTAssertNotEqual(AIAccess.trialProductID, AIAccess.productID)
        XCTAssertTrue(AIAccess.trialProductID.hasPrefix("com.gengyunqin.enclave."))
    }
}
