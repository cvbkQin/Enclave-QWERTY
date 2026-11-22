import UIKit

/// 弹出时先显示「上次键盘的样子」（开发版试验，测试工具 › 弹出记录里的开关，默认关）。
///
/// 系统一来要键盘就开始往上推底板，不等我们；我们建整棵 SwiftUI 键盘要几十毫秒，这段时间底板是空的，
/// 键画好了才一下子跳出来（11-19 录屏：微信、小红书空底板滑了 50–70 毫秒，正好是建键盘到显示出来的时间）。
/// 开了开关：进了窗口、第一帧交出去之前，样子和上次一样（宽高、深浅色、回车键、九宫格 / 全键盘、哪一页、中英、横竖屏、设置都对得上），
/// 就先放一张上次截下的图，第一帧马上交出去；第一帧交出去以后的下一轮再建真键盘，真键盘盖在图上面，也交出一帧以后再把图拿掉。
/// 对不上就照旧直接建真键盘。图只存在内存里（热启动才有，冷启动照旧），最多两张（回车键不同的框来回切）。
enum PopupSnapshot {
    static var enabled: Bool { PopupLog.snapshotEnabled }

    /// 键盘长什么样由哪些东西决定：这些都一样，上次截的图才拿来用。
    struct Key: Equatable {
        var size: CGSize
        var style: UIUserInterfaceStyle
        var appearance: UIKeyboardAppearance
        var returnKey: UIReturnKeyType
        var hasText: Bool
        var nineKey: Bool
        /// 字母、数字、符号哪一页：数字框直接出数字页。原来没比这一样，在数字框里截的图，下次弹到普通框也会先露出数字页。
        var layer: KeyboardModel.KeyLayer
        var chinese: Bool
        var landscape: Bool
        var settings: EnclaveSettings

        /// 和另一张图的样子哪里不一样（写进弹出记录，看截图为什么没用上）。
        func differences(from other: Key) -> [String] {
            var names: [String] = []
            if size != other.size {
                names.append(String(format: "尺寸（%.0f×%.0f / 上次 %.0f×%.0f）", size.width, size.height, other.size.width, other.size.height))
            }
            if style != other.style { names.append("深浅色") }
            if appearance != other.appearance { names.append("输入框要的键盘外观") }
            if returnKey != other.returnKey { names.append("回车键") }
            if hasText != other.hasText { names.append("输入框有没有字") }
            if nineKey != other.nineKey { names.append("九宫格 / 全键盘") }
            if layer != other.layer { names.append("字母 / 数字 / 符号页") }
            if chinese != other.chinese { names.append("中英") }
            if landscape != other.landscape { names.append("横竖屏") }
            if settings != other.settings { names.append("设置") }
            return names
        }
    }

    private static var cache: [(key: Key, image: UIImage)] = []
    private static let limit = 2

    static func image(for key: Key) -> UIImage? { cache.first { $0.key == key }?.image }

    /// 没有对得上的图时，说一句为什么（还没截过，或者和最近一张哪里不一样）。
    static func missReason(for key: Key) -> String {
        guard let latest = cache.first else { return "还没有截图（这个键盘进程里第一次弹出，或者上次没截成）" }
        let names = key.differences(from: latest.key)
        return names.isEmpty ? "和上次一样却没对上" : "和上次不一样：" + names.joined(separator: "、")
    }

    static func store(_ image: UIImage, for key: Key) {
        cache.removeAll { $0.key == key }
        cache.insert((key, image), at: 0)
        if cache.count > limit { cache.removeLast(cache.count - limit) }
    }

    /// 把键盘现在的样子画成一张图。用 2 倍：图只在弹出那几十毫秒里露面，又是在滑动中，看不出比屏幕的 3 倍糊；
    /// 一张约 2.4 MB，比 3 倍省一半多。上面拼音行那截是透明渐变，图也留着透明，系统的玻璃底照样透出来。
    static func capture(_ view: UIView) -> UIImage? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            drawn = view.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        return drawn ? image : nil
    }
}
