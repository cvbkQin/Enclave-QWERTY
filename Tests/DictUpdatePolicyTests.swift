import XCTest

/// 对齐清单第 99 条：热门词库自动更新的时间判断、按 sha256 判断更新、版本比大小、内置词库用哪一份、整句模型线路。
final class DictUpdatePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86400

    func testDueEverySevenDays() {
        XCTAssertTrue(DictUpdatePolicy.isDue(now: now, lastCheck: nil, lastFailure: nil, enabled: true))
        XCTAssertFalse(DictUpdatePolicy.isDue(now: now, lastCheck: now - 6 * day, lastFailure: nil, enabled: true))
        XCTAssertTrue(DictUpdatePolicy.isDue(now: now, lastCheck: now - 7 * day, lastFailure: nil, enabled: true))
        // 关掉自动更新：不查。
        XCTAssertFalse(DictUpdatePolicy.isDue(now: now, lastCheck: nil, lastFailure: nil, enabled: false))
    }

    func testFailureRetriesAfterOneDay() {
        // 到期了但刚失败过：1 天内不再试，过了 1 天再试（不等 7 天）。
        XCTAssertFalse(DictUpdatePolicy.isDue(now: now, lastCheck: now - 8 * day, lastFailure: now - 3600, enabled: true))
        XCTAssertTrue(DictUpdatePolicy.isDue(now: now, lastCheck: now - 8 * day, lastFailure: now - day, enabled: true))
        XCTAssertFalse(DictUpdatePolicy.isDue(now: now, lastCheck: nil, lastFailure: now - 3600, enabled: true))
        // 失败以后又成功过：失败那次不算了，照 7 天。
        XCTAssertFalse(DictUpdatePolicy.isDue(now: now, lastCheck: now - 3600, lastFailure: now - 2 * 3600, enabled: true))
    }

    func testNewerBySHAThenVersion() {
        // 两边都有 sha256：只看变没变，日期一样也算更新；日期新了但内容没变不算。
        XCTAssertTrue(DictUpdatePolicy.isNewer(remoteSHA: "abc", remoteVersion: "2026-10-31", localSHA: "def", localVersion: "2026-10-31"))
        XCTAssertFalse(DictUpdatePolicy.isNewer(remoteSHA: "ABC", remoteVersion: "2026-11-26", localSHA: "abc", localVersion: "2026-10-31"))
        // 老记录没有 sha256：按版本比。
        XCTAssertTrue(DictUpdatePolicy.isNewer(remoteSHA: "abc", remoteVersion: "2026-11-26", localSHA: nil, localVersion: "2026-10-31"))
        XCTAssertFalse(DictUpdatePolicy.isNewer(remoteSHA: "abc", remoteVersion: "2026-10-31", localSHA: nil, localVersion: "2026-10-31"))
    }

    func testSameDaySecondVersionIsNewer() {
        XCTAssertEqual(DictUpdatePolicy.compare("2026-11-26.2", "2026-11-26"), .orderedDescending)
        XCTAssertEqual(DictUpdatePolicy.compare("2026-11-26.10", "2026-11-26.2"), .orderedDescending)
        XCTAssertEqual(DictUpdatePolicy.compare("2026-11-27", "2026-11-26.3"), .orderedDescending)
        XCTAssertEqual(DictUpdatePolicy.compare("2026-11-26", "2026-11-26.1"), .orderedSame)
    }

    func testBuiltinUsesServerCopyOnlyWhenNewer() {
        XCTAssertTrue(DictUpdatePolicy.usesServerCopy(serverVersion: "2026-11-26", bundledVersion: "2026-10-31"))
        // App 升级后自带的更新了：回到自带的。
        XCTAssertFalse(DictUpdatePolicy.usesServerCopy(serverVersion: "2026-11-26", bundledVersion: "2026-12-05"))
        XCTAssertFalse(DictUpdatePolicy.usesServerCopy(serverVersion: "2026-11-26", bundledVersion: "2026-11-26"))
        XCTAssertFalse(DictUpdatePolicy.usesServerCopy(serverVersion: nil, bundledVersion: "2026-10-31"))
    }

    func testNewDictsAreMarkedOnlyAfterFirstVisit() {
        XCTAssertEqual(DictUpdatePolicy.newIDs(catalog: ["baike", "medical"], seen: nil), [])
        XCTAssertEqual(DictUpdatePolicy.newIDs(catalog: ["baike", "medical", "anime"], seen: ["baike", "medical"]), ["anime"])
    }

    func testGrammarLines() {
        XCTAssertEqual(GrammarLine.defaultLine(mainland: true), .cn)
        XCTAssertEqual(GrammarLine.defaultLine(mainland: false), .global)
        XCTAssertEqual(GrammarLine.allCases.first, .global)
        XCTAssertEqual(GrammarLine.cn.other, .global)
        XCTAssertTrue(GrammarLine.cn.verifiesSHA)
        XCTAssertFalse(GrammarLine.global.verifiesSHA)
        XCTAssertEqual(GrammarLine.cn.defaultURL.host, "enclavekb.cn")
        XCTAssertEqual(GrammarLine.global.defaultURL.host, "github.com")
    }
}
