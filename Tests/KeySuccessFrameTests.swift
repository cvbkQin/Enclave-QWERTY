import XCTest
import SwiftUI

/// AI 栏键的成功动效时间轴（对齐清单第 61 条，对照 design/polish-success/ps3.html 的 bs()）。
final class KeySuccessFrameTests: XCTestCase {
    private func frame(_ ms: Double, reduced: Bool = false) -> KeySuccessFrame? {
        KeySuccessFrame.at(ms / 1000, reduceMotion: reduced)
    }

    func testFlashPeaksAt150AndFadesBy600() throws {
        XCTAssertEqual(try XCTUnwrap(frame(150)).flash, 0.12, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(600)).flash, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(75)).flash, 0.06, accuracy: 0.001)
    }

    func testTextHidesThenComesBack() throws {
        let gone = try XCTUnwrap(frame(300))
        XCTAssertEqual(gone.textOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(gone.textBlur, 3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(10_000)).textOpacity, 0, accuracy: 0.001)
        let back = try XCTUnwrap(frame(18_699))
        XCTAssertEqual(back.textOpacity, 1, accuracy: 0.01)
        XCTAssertEqual(back.textDrop, 0, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(frame(18_300)).textDrop, 3, accuracy: 0.001)
        XCTAssertNil(frame(18_700))
    }

    func testCheckDrawsFrom80To680AndShrinksAway() throws {
        XCTAssertEqual(try XCTUnwrap(frame(79)).checkOpacity, 0)
        XCTAssertEqual(try XCTUnwrap(frame(380)).check, 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(680)).check, 1, accuracy: 0.001)
        let fading = try XCTUnwrap(frame(18_500))
        XCTAssertEqual(fading.checkOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(fading.checkScale, 0.92, accuracy: 0.001)
    }

    func testSweepRunsFiveTimesWithGaps() throws {
        var sweeps = 0
        var inside = false
        for ms in stride(from: 0.0, to: 18_700, by: 50) {
            let on = try XCTUnwrap(frame(ms)).sweep != nil
            if on && !inside { sweeps += 1 }
            inside = on
        }
        XCTAssertEqual(sweeps, 5)
        XCTAssertNil(try XCTUnwrap(frame(3_400)).sweep)
        XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(frame(3_800 + 1_500)).sweep), 0.5, accuracy: 0.001)
        XCTAssertNil(try XCTUnwrap(frame(18_300)).sweep)
    }

    func testLogoBouncesAndKeepsAnimating() throws {
        XCTAssertEqual(try XCTUnwrap(frame(175)).logoScale, 1.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(420)).logoScale, 1.05, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(700)).logoScale, 1, accuracy: 0.001)
        XCTAssertTrue(try XCTUnwrap(frame(18_000)).logoAnimating)
    }

    func testReduceMotionOnlyFadesTheCheck() throws {
        let mid = try XCTUnwrap(frame(800, reduced: true))
        XCTAssertNil(mid.sweep)
        XCTAssertEqual(mid.check, 1)
        XCTAssertEqual(mid.checkOpacity, 1, accuracy: 0.001)
        XCTAssertFalse(mid.logoAnimating)
        XCTAssertEqual(mid.logoScale, 1)
        XCTAssertEqual(mid.flash, 0)
        XCTAssertNil(frame(1_600, reduced: true))
    }
}
