import SwiftUI
import UIKit

// iPad 适配（PA1–PA4，11-22）：横向 regular（全屏、半屏）时六个标签，提示词、历史、设置左右两栏，
// 首页、接口、键盘标签宽屏排法；窗口窄到 iPhone 那么宽（分屏 1/3、台前调度小窗口）时一切照 iPhone。

/// 这台设备叫什么：「只存在这台 iPad 上」（PA2 ④）。
enum DeviceName {
    static var current: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
}

/// 右栏（两栏的右边、一列的宽屏页）内容最宽 640，居中（PA1–PA4）；解锁页 560。
enum PadWidth {
    static let content: CGFloat = 640
    static let unlock: CGFloat = 560
    extension View {
    /// 量自己的宽度（两栏的左栏跟着窗口宽）。
    func readWidth(_ width: Binding<CGFloat>) -> some View {
        background(GeometryReader { geo in
            Color.clear
                .onAppear { width.wrappedValue = geo.size.width }
                .onChange(of: geo.size.width) { width.wrappedValue = $0 }
        })
    }
}

/// 一长串设置排成两列要的最小宽度：11 寸横屏的内容区约 1180，竖屏 820 时一列。
    static let twoColumns: CGFloat = 960
    /// 两栏左边那一栏（PA4 ⑧：11 寸竖屏 330；PA2 横屏约 400）：跟着窗口宽，330～420。
    static func sidebar(_ windowWidth: CGFloat) -> CGFloat {
        min(max((windowWidth * 0.34).rounded(), 330), 420)
    }
}

private struct PadSplitKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SelectedPromptKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// 这一页在 iPad 两栏里（左边列表、右边内容）：列表点一行换右边，不往里推一页。
    var padSplit: Bool {
        get { self[PadSplitKey.self] }
        set { self[PadSplitKey.self] = newValue }
    }

    /// 提示词两栏（PA2 ③）：右边正在编辑的那条，左边这一行紫底白字。
    var selectedPromptID: UUID? {
        get { self[SelectedPromptKey.self] }
        set { self[SelectedPromptKey.self] = newValue }
    }
}

extension View {
    /// 宽屏时内容最宽 maxWidth、居中，两边露出分组页的底色。窄屏（iPhone）不变。
    @ViewBuilder
    func padReadable(_ enabled: Bool = true, maxWidth: CGFloat = PadWidth.content) -> some View {
        if enabled {
            self.frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
        } else {
            self
        }
    }

    /// iPadOS 18 起标签栏照系统 iPad 的样子（sidebarAdaptable）：标签在顶上居中，左上角按钮可以换成侧边栏（PA1 ③）。
    @ViewBuilder
    func padTabStyle() -> some View {
        if #available(iOS 18.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}

/// 一长串设置排成两列（PA1 ② 接口、PA3 ⑥ 键盘）：宽屏且够宽时左右两个分组列表，各自滚动；
/// 宽屏但不够宽（竖屏）时一列、最宽 640 居中；iPhone 照旧一列。
struct PadColumns<Left: View, Right: View>: View {
    @EnvironmentObject private var router: AppRouter
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        if router.wideLayout {
            GeometryReader { geo in
                if geo.size.width >= PadWidth.twoColumns {
                    HStack(alignment: .top, spacing: 0) {
                        Form { left }
                        Form { right }
                    }
                } else {
                    Form {
                        left
                        right
                    }
                    .padReadable()
                }
            }
        } else {
            Form {
                left
                right
            }
        }
    }
}

/// 两栏右边还没选东西时的空白页。
struct SplitPlaceholder: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

/// 一行几张卡按比例分宽（PA1 ①：AI 卡 2、接口卡 1），高度取最高的那张。
struct RatioRow: Layout {
    var ratios: [CGFloat]
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let widths = columnWidths(width, count: subviews.count)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(bounds.width, count: subviews.count)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func columnWidths(_ width: CGFloat, count: Int) -> [CGFloat] {
        let used = Array(ratios.prefix(count)) + Array(repeating: 1, count: max(count - ratios.count, 0))
        let total = used.reduce(0, +)
        let room = max(width - spacing * CGFloat(max(count - 1, 0)), 0)
        return used.map { total > 0 ? room * $0 / total : 0 }
    }
}

extension View {
    /// iPad 宽屏时首次打开的隐私说明、引导、功能演示改成居中的表单窗口（PA4 ⑦），iPhone 照旧整屏盖住。
    /// 不能下滑关掉（和整屏时一样，要点里面的按钮）。
    func padCover<Item: Identifiable, Content: View>(item: Binding<Item?>, wide: Bool, onDismiss: (() -> Void)? = nil,
                                                     @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(PadCoverItem(item: item, wide: wide, onDismiss: onDismiss, cover: content))
    }

    func padCover<Content: View>(isPresented: Binding<Bool>, wide: Bool, onDismiss: (() -> Void)? = nil,
                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(PadCoverFlag(isPresented: isPresented, wide: wide, onDismiss: onDismiss, cover: content))
    }
}

private struct PadCoverFlag<Cover: View>: ViewModifier {
    @Binding var isPresented: Bool
    let wide: Bool
    let onDismiss: (() -> Void)?
    let cover: () -> Cover

    func body(content: Content) -> some View {
        if wide {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                cover().interactiveDismissDisabled()
            }
        } else {
            content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss, content: cover)
        }
    }
}

private struct PadCoverItem<Item: Identifiable, Cover: View>: ViewModifier {
    @Binding var item: Item?
    let wide: Bool
    let onDismiss: (() -> Void)?
    let cover: (Item) -> Cover

    func body(content: Content) -> some View {
        if wide {
            content.sheet(item: $item, onDismiss: onDismiss) { item in
                cover(item).interactiveDismissDisabled()
            }
        } else {
            content.fullScreenCover(item: $item, onDismiss: onDismiss, content: cover)
        }
    }
}
