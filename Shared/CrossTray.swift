import CoreGraphics
import Foundation

/// 长按十字的托盘（对齐清单第 88 条，design/popup-style 第 3 节）：中间那格和有选项的几条胳膊连成一整块十字形，
/// 外角圆角大、里角圆角小。只算形状，画在 KeysPanels 的 CrossView 里。
enum CrossTray {
    /// 外沿多边形，顺时针（y 朝下）。center：中间那格；reach：每条胳膊从中间那格边上往外伸多长（没有胳膊就是 0）；
    /// padding：托盘比格子多出来的一圈。
    static func outline(center: CGRect, up: CGFloat, right: CGFloat, down: CGFloat, left: CGFloat,
                        padding: CGFloat) -> [CGPoint] {
        let box = center.insetBy(dx: -padding, dy: -padding)
        // 横条和竖条，十字 = 两条的并集。
        let h = CGRect(x: box.minX - left, y: box.minY, width: box.width + left + right, height: box.height)
        let v = CGRect(x: box.minX, y: box.minY - up, width: box.width, height: box.height + up + down)
        let raw = [
            CGPoint(x: v.minX, y: v.minY), CGPoint(x: v.maxX, y: v.minY),
            CGPoint(x: v.maxX, y: h.minY), CGPoint(x: h.maxX, y: h.minY),
            CGPoint(x: h.maxX, y: h.maxY), CGPoint(x: v.maxX, y: h.maxY),
            CGPoint(x: v.maxX, y: v.maxY), CGPoint(x: v.minX, y: v.maxY),
            CGPoint(x: v.minX, y: h.maxY), CGPoint(x: h.minX, y: h.maxY),
            CGPoint(x: h.minX, y: h.minY), CGPoint(x: v.minX, y: h.minY),
        ]
        return simplified(raw)
    }

    /// 去掉重合的点和一条直线上的中间点（没有某条胳膊时会出现）。
    static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points where result.last.map({ !close($0, point) }) ?? true { result.append(point) }
        while result.count > 1, close(result[0], result[result.count - 1]) { result.removeLast() }
        var changed = true
        while changed && result.count > 3 {
            changed = false
            for i in result.indices {
                let prev = result[(i + result.count - 1) % result.count], next = result[(i + 1) % result.count]
                if abs(turn(prev, result[i], next)) < 0.0001 {
                    result.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    /// 顺时针（y 朝下）时外角为正，里角为负。
    static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
    }

    /// 圆角路径：外角 outer，里角 inner；圆角不超过相邻两条边的一半。
    static func path(_ points: [CGPoint], outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n >= 3 else { return path }
        let start = CGPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2)
        path.move(to: start)
        for i in 0..<n {
            let prev = points[(i + n - 1) % n], point = points[i], next = points[(i + 1) % n]
            let limit = min(distance(prev, point), distance(point, next)) / 2
            let radius = min(turn(prev, point, next) > 0 ? outer : inner, limit)
            path.addArc(tangent1End: point, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }

    private static func close(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001 }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
