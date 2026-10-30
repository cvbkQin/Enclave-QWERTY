import XCTest

/// 纠错层和 Python 参考实现对拍：Tests/Correction/golden.json 由 scripts/correction/corrector_ref.py golden 生成，
/// 用的是同一份 Vendor/KeyLM 表。表没生成（没跑 scripts/fetch-rime.sh）时跳过。
final class CorrectorTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func corrector(nineKey: Bool) throws -> Corrector {
        let url = Self.root.appendingPathComponent("Vendor/KeyLM/\(nineKey ? "t9" : "qw").eklm")
        guard let lm = KeyLM(url: url) else { throw XCTSkip("没有 \(url.path)，先运行 scripts/fetch-rime.sh") }
        return Corrector(lm: lm, nineKey: nineKey)
    }

    func testExamples() throws {
        let qwerty = try corrector(nineKey: false)
        XCTAssertEqual(qwerty.guess("nihoa"), Corrector.Guess(corrected: "nihao", place: 1))
        XCTAssertEqual(qwerty.guess("wozaimmenkou"), Corrector.Guess(corrected: "wozaimenkou", place: 1))
        XCTAssertEqual(qwerty.guess("tushuguna"), Corrector.Guess(corrected: "tushuguan", place: 2))
        XCTAssertNil(qwerty.guess("xianzai"))
        XCTAssertNil(qwerty.guess("zhon"))
        XCTAssertNil(qwerty.guess("bj"))
        XCTAssertNil(qwerty.guess("xi'an"))
    }

    func testMatchesReference() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("Tests/Correction/golden.json"))
        let golden = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        for (layout, nineKey) in [("qw", false), ("t9", true)] {
            let corrector = try corrector(nineKey: nineKey)
            var mismatches: [String] = []
            for (input, expected) in try XCTUnwrap(golden[layout]) {
                let want = (expected as? [Any]).map { Corrector.Guess(corrected: $0[0] as! String, place: $0[1] as! Int) }
                let got = corrector.guess(input)
                if got != want { mismatches.append("\(input): \(String(describing: got)) ≠ \(String(describing: want))") }
            }
            XCTAssertTrue(mismatches.isEmpty, "\(layout) 有 \(mismatches.count) 个对不上：\(mismatches.prefix(10))")
        }
    }

    /// 触点解码：按在正中间改成邻键罚得重，在两键中线上不变，偏向邻键罚得轻；九宫格同理。
    func testTouchAdjustment() throws {
        let qwerty = try corrector(nineKey: false)
        let o = UInt8(ascii: "o"), i = UInt8(ascii: "i")
        XCTAssertEqual(qwerty.touchAdjustment(o, to: i, at: .init(dx: 0, dy: 0)), Corrector.touchMaxExtra, accuracy: 1e-9)
        XCTAssertEqual(qwerty.touchAdjustment(o, to: i, at: .init(dx: -0.5, dy: 0)), 0, accuracy: 1e-9)
        XCTAssertLessThan(qwerty.touchAdjustment(o, to: i, at: .init(dx: -0.7, dy: 0)), -0.5)
        // 偏向另一边（p）时改成 i 更难。
        XCTAssertGreaterThan(qwerty.touchAdjustment(o, to: i, at: .init(dx: 0.4, dy: 0)), 1.5)
        let nine = try corrector(nineKey: true)
        XCTAssertEqual(nine.touchAdjustment(UInt8(ascii: "5"), to: UInt8(ascii: "6"), at: .init(dx: 0.5, dy: 0)), 0, accuracy: 1e-9)
    }

    /// 落点只影响「按到邻键」那种改法；没有落点时和参考实现一样。
    func testTouchesKeepOtherEdits() throws {
        let qwerty = try corrector(nineKey: false)
        let centered = Array(repeating: TouchTrail.Offset(dx: 0, dy: 0), count: 5)
        XCTAssertEqual(qwerty.guess("nihoa", touches: centered), qwerty.guess("nihoa"))
        // 长度对不上的落点不用。
        XCTAssertEqual(qwerty.guess("nihoa", touches: [.init(dx: 0, dy: 0)]), qwerty.guess("nihoa"))
    }

    func testTrailAlignment() {
        TouchTrail.clear()
        for char in "nihao" { TouchTrail.record(char, .init(dx: 0.1, dy: 0)) }
        XCTAssertEqual(TouchTrail.offsets(for: "nihao")?.count, 5)
        XCTAssertEqual(TouchTrail.offsets(for: "hao")?.count, 3)
        XCTAssertNil(TouchTrail.offsets(for: "nihai"))
        TouchTrail.dropLast()
        XCTAssertEqual(TouchTrail.offsets(for: "niha")?.count, 4)
        TouchTrail.clear()
        XCTAssertNil(TouchTrail.offsets(for: "niha"))
    }

    func testMergePlacesCorrection() {
        let first = CorrectionMerge.merge(["你好啊", "你", "泥"], input: "nihoa", guess: .init(corrected: "nihao", place: 1), correctedTop: "你好")
        XCTAssertEqual(first, .init(candidates: ["你好", "你好啊", "你", "泥"], index: 0, removed: nil))
        let second = CorrectionMerge.merge(["图书滚啊", "图书馆", "图书"], input: "tushuguna", guess: .init(corrected: "tushuguan", place: 2), correctedTop: "图书馆")
        XCTAssertEqual(second, .init(candidates: ["图书滚啊", "图书馆", "图书"], index: 1, removed: 1))
        // 引擎首选是整串英文：不纠。
        XCTAssertNil(CorrectionMerge.merge(["WiFi", "我"], input: "wifi", guess: .init(corrected: "woxi", place: 1), correctedTop: "我希"))
        // 改了也是同一个首选：不动。
        XCTAssertNil(CorrectionMerge.merge(["你好"], input: "nihoa", guess: .init(corrected: "nihao", place: 1), correctedTop: "你好"))
    }
}
