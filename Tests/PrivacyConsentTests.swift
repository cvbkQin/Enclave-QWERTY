import XCTest

/// 隐私政策同意：同意、仅基础功能、撤回、政策更新后再弹。
final class PrivacyConsentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PrivacyConsent.resetForTesting()
    }

    override func tearDown() {
        PrivacyConsent.resetForTesting()
        super.tearDown()
    }

    func testFreshInstall() {
        XCTAssertFalse(PrivacyConsent.isAgreed)
        XCTAssertTrue(PrivacyConsent.needsPrompt)
        XCTAssertFalse(PrivacyConsent.isUpdate)
    }

    func testAgree() {
        PrivacyConsent.agree()
        XCTAssertTrue(PrivacyConsent.isAgreed)
        XCTAssertFalse(PrivacyConsent.needsPrompt)
        XCTAssertEqual(PrivacyConsent.agreedVersion, PrivacyConsent.currentVersion)
        XCTAssertNotNil(PrivacyConsent.agreedDate)
    }

    func testBasicOnly() {
        PrivacyConsent.useBasicOnly()
        XCTAssertFalse(PrivacyConsent.isAgreed)
        XCTAssertFalse(PrivacyConsent.needsPrompt)
    }

    func testRevoke() {
        PrivacyConsent.agree()
        PrivacyConsent.revoke()
        XCTAssertFalse(PrivacyConsent.isAgreed)
        XCTAssertNil(PrivacyConsent.agreedDate)
        // 撤回不会再弹说明页。
        XCTAssertFalse(PrivacyConsent.needsPrompt)
    }

    /// 同意的是旧版政策：算没同意，要再弹，并且标成「更新」。
    func testOlderVersionNeedsPromptAgain() {
        SharedStorage.defaults.set(PrivacyConsent.currentVersion - 1, forKey: "privacy.agreedVersion")
        SharedStorage.defaults.set(PrivacyConsent.currentVersion - 1, forKey: "privacy.seenVersion")
        XCTAssertFalse(PrivacyConsent.isAgreed)
        XCTAssertTrue(PrivacyConsent.needsPrompt)
        XCTAssertTrue(PrivacyConsent.isUpdate)
    }
}
