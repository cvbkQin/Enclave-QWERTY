import CoreGraphics
import XCTest

/// 长按十字的托盘外形（对齐清单第 88 条，design/popup-style 第 3 节）。
final class CrossTrayTests: XCTestCase {
    /// iPhone 竖屏九宫格：格子 56×40，缝 4，托盘外围 4。
    private let center = CGRect(x: 100, y: 100, width: 56, height: 40)
    private let across: CGFloat = 56 + 4, along: CGFloat = 40 + 4

    private func corners(_ points: [CGPoint]) -> (outer: Int, inner: Int) {
        var outer = 0, inner = 0
        for i in points.indices {
            let turn = CrossTray.turn(points[(i + points.count - 1) % points.count], points[i], points[(i + 1) % points.count])
            if turn > 0 { outer += 1 } else if turn < 0 { inner += 1 }
        }
        return (outer, inner)
    }

    private func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// 四个方向都有（「，。?!」）：完整十字，8 个外角、4 个里角。
    func testFullCross() {
        let points = CrossTray.outline(center: center, up: along, right: across, down: along, left: across, padding: 4)
        XCTAssertEqual(points.count, 12)
        XCTAssertEqual(corners(points).outer, 8)
        XCTAssertEqual(corners(points).inner, 4)
        XCTAssertEqual(bounds(points), CGRect(x: 100 - 60 - 4, y: 100 - 44 - 4, width: 56 * 3 + 8 + 8, height: 40 * 3 + 8 + 8))
    }

    /// ABC 只有左、下、右：上面是一条直边，少一条胳膊。
    func testThreeArms() {
        let points = CrossTray.outline(center: center, up: 0, right: across, down: along, left: across, padding: 4)
        XCTAssertEqual(points.count, 8)
        XCTAssertEqual(corners(points).outer, 6)
        XCTAssertEqual(corners(points).inner, 2)
        XCTAssertEqual(bounds(points).minY, 96)
    }

    /// 全键盘「，。」只有往上：一竖条，就是圆角矩形。
    func testUpOnly() {
        let square = CGRect(x: 300, y: 200, width: 40, height: 40)
        let points = CrossTray.outline(center: square, up: 44, right: 0, down: 0, left: 0, padding: 4)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(corners(points).outer, 4)
        XCTAssertEqual(bounds(points), CGRect(x: 296, y: 152, width: 48, height: 92))
    }

    /// 圆角路径不出托盘外沿。
    func testPathStaysInside() {
        let points = CrossTray.outline(center: center, up: along, right: across, down: along, left: across, padding: 4)
        let box = CrossTray.path(points, outer: 12, inner: 6).boundingBox
        XCTAssertEqual(box.minX, bounds(points).minX, accuracy: 0.01)
        XCTAssertEqual(box.maxY, bounds(points).maxY, accuracy: 0.01)
        XCTAssertTrue(bounds(points).insetBy(dx: -0.01, dy: -0.01).contains(box))
    }
}
