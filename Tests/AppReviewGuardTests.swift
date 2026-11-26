import XCTest

/// 上架审核的硬性规矩，改代码时别又弄回来（05 上架风险报告，11-22）。
final class AppReviewGuardTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// 高 1：键盘扩展不能打开别的 App（4.4.1），也不能用 KVC、selector 绕开扩展的限制去调 openURL（2.5.1）。
    /// 键盘里要去 App 设置的地方只提示路径（AppPlace）。
    func testKeyboardDoesNotOpenApps() throws {
        let folder = Self.root.appendingPathComponent("Keyboard")
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let banned = ["sharedApplication", "openURL", "UIApplication.shared", "unsafeBitCast(application"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(file.lastPathComponent) 里有 \(word)")
            }
        }
    }
}
