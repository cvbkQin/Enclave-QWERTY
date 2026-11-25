import Foundation

/// 帮回开始前的等待（对齐清单第 94 条，design/help-reply/again 逻辑稿二之二）：开新的一句、识意框空着时先等 2 秒，
/// 上半格的绿色像干笔刷一样从左往右扫开，碰到右边的那一刻开始帮回；中途点识意框就停下，等用户写要求。
/// 这里只放时间和曲线（有单测），画法在键盘的 HelpWaitViews.swift。
struct HelpWait: Equatable {
    /// 要回的那句原话，和这次读剪贴板的 changeCount（从剪贴板记录发起的没有）。
    var message: String
    var changeCount: Int?
    /// 是从弹出的帮回键发起的（生成中、成功动效按它找键）。
    var fromPin: Bool
    var startedAt: Date
    /// 点了识意框（或在框里打字）：计时停下，不再自动回。
    var interruptedAt: Date?

    /// 2 秒走满（cvbk 11-25 14:22，原来 1.5 秒）。
    static let duration: TimeInterval = 2

    var interrupted: Bool { interruptedAt != nil }

    /// 停下那一刻笔刷走到哪儿（0…1）；没停下是 nil。
    var interruptProgress: Double? {
        interruptedAt.map { Self.progress(elapsed: $0.timeIntervalSince(startedAt)) }
    }

    /// 再点帮回回哪句（HR1 第 2 条）：回答卡展开、卡上是帮回写的一版、又没有新的待回复制时，用这一版记下的原话，不读剪贴板；
    /// 中间又复制了别的话（帮回键重新亮起），或者卡收着（看不到这一版），就是 nil，照常读剪贴板。
    static func againSource(expanded: Bool, pending: Bool, current: EditSession.ReplySource?) -> EditSession.ReplySource? {
        guard expanded, !pending else { return nil }
        return current
    }

    /// 要不要先等 2 秒（HW1 第 1 条）：开新的一句、识意框空着才等；再点帮回重写、识意框已经有要求都马上回。
    static func waitsBeforeReply(again: Bool, request: String) -> Bool {
        !again && request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 笔刷前沿走到哪儿（0…1）：一路稳稳往前扫，接近右边放慢，2 秒时刚好碰到右边。
    /// cubic-bezier(.3,.45,.6,.92)：一半时间 68%，3/4 时间 90%。
    static func progress(elapsed: TimeInterval) -> Double {
        let x = min(max(elapsed / duration, 0), 1)
        return CubicBezier.brush.value(at: x)
    }
}

/// CSS 那种 cubic-bezier(x1, y1, x2, y2)：给时间比例（0…1）求进度。按 x 二分求 t，再算 y。
struct CubicBezier {
    var x1: Double, y1: Double, x2: Double, y2: Double

    /// 等待条的笔刷：前面稳、接近右边放慢。
    static let brush = CubicBezier(x1: 0.3, y1: 0.45, x2: 0.6, y2: 0.92)
    /// 打断后往回收 70pt。
    static let retract = CubicBezier(x1: 0.3, y1: 0, x2: 0.2, y2: 1)
    /// 到位后白光扫过整张卡（参考润色成功的扫光）。
    static let sweep = CubicBezier(x1: 0.45, y1: 0, x2: 0.25, y2: 1)

    func value(at x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x == 0 || x == 1 { return x }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let t = (lo + hi) / 2
            if Self.point(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return Self.point((lo + hi) / 2, y1, y2)
    }

    private static func point(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }
}
