import SwiftUI
import UIKit

/// 键盘尺寸，按 iOS 26 自带简体拼音键盘在 402pt 宽的 iPhone 上量出来的。键盘高度也从这里算。
enum KeyboardMetrics {
    /// 一个按键格子的高度（含上下间隙）：行距 54，按键本身 43。
    static let slotHeight: CGFloat = 54
    static let keyInsetX: CGFloat = 3.1
    static let keyInsetY: CGFloat = 5.5
    static let keysHeight: CGFloat = slotHeight * 4
    /// 全键盘 Shift、删除键画出来的宽度（触摸范围仍是 1.5 格）。
    static let shiftKeyWidth: CGFloat = 45
    /// 九宫格的键 72.6×44（iOS 26 实测），五列等宽。
    static let nineKeyInsetX: CGFloat = 3.15
    static let nineKeyInsetY: CGFloat = 5

    static let topRow: CGFloat = 42
    static let previewHeight: CGFloat = 62
    /// 键盘被系统压矮时，预览行最多缩到这么高，保证按键和操作行完整显示。
    static let minPreviewHeight: CGFloat = 30
    static let actionRow: CGFloat = 32
    static let instructionRow: CGFloat = 32
    /// 顶栏和要求行里圆形/胶囊按钮的高度（展开键、润色）。
    static let chipHeight: CGFloat = 32
    static let panelSpacing: CGFloat = 5
    static let panelTop: CGFloat = 6
    static let sidePadding: CGFloat = 3.7

    static var collapsedHeight: CGFloat { topRow + keysHeight }
    /// 展开后没有顶栏：预览行、操作行、要求行，下面是按键。
    static var expandedHeight: CGFloat {
        panelTop + previewHeight + actionRow + instructionRow + panelSpacing * 3 + keysHeight
    }
}

/// 按键颜色，取自 iOS 26 键盘：字符键和功能键同色，没有阴影；按下的功能键变灰。
enum KeyStyle {
    static let charKey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 71 / 255, green: 71 / 255, blue: 73 / 255, alpha: 1) : .white })
    static let functionKey = charKey
    static let pressedKey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.43, alpha: 1) : UIColor(red: 0.70, green: 0.72, blue: 0.76, alpha: 1) })
    static let cornerRadius: CGFloat = 8.5

    static let letterFont = Font.system(size: 24)
    static let symbolFont = Font.system(size: 22)
    static let nineKeyFont = Font.system(size: 15.5)
    static let functionFont = Font.system(size: 17)
    static let iconFont = Font.system(size: 19, weight: .regular)
}

/// 按键外观：圆角、底色、底部细阴影。外面留出间隙，间隙也能点到这个键，和系统键盘一样没有死区。
struct KeyCap<Content: View>: View {
    var fill: Color
    var insetX = KeyboardMetrics.keyInsetX
    var insetY = KeyboardMetrics.keyInsetY
    var content: Content

    init(fill: Color, insetX: CGFloat = KeyboardMetrics.keyInsetX, insetY: CGFloat = KeyboardMetrics.keyInsetY,
         @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.insetX = insetX
        self.insetY = insetY
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .padding(.horizontal, insetX)
            .padding(.vertical, insetY)
            .contentShape(Rectangle())
    }
}

/// 字符键：浅色底。
struct CharKey: View {
    var title: String
    var font: Font = KeyStyle.letterFont
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyCap(fill: KeyStyle.charKey) {
                Text(title).font(font).foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 功能键：深色底，可高亮成蓝色。
struct FunctionKey: View {
    var title: String?
    var systemImage: String?
    var highlighted = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyCap(fill: highlighted ? Color.accentColor : KeyStyle.functionKey) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage).font(KeyStyle.iconFont)
                    } else {
                        Text(title ?? "").font(KeyStyle.functionFont)
                    }
                }
                .foregroundStyle(highlighted ? Color.white : Color.primary)
            }
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 按住会连续触发的按键（删除键）。
struct RepeatingKey: View {
    var systemImage: String
    var action: () -> Void
    @State private var timer: Timer?
    @State private var pressed = false

    var body: some View {
        KeyCap(fill: pressed ? KeyStyle.pressedKey : KeyStyle.functionKey) {
            Image(systemName: systemImage).font(KeyStyle.iconFont).foregroundStyle(Color.primary)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard timer == nil else { return }
                    pressed = true
                    action()
                    timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        Task { @MainActor in
                            // 手指已经抬起就不再开始连发。
                            guard timer != nil else { return }
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                                Task { @MainActor in action() }
                            }
                        }
                    }
                }
                .onEnded { _ in
                    pressed = false
                    timer?.invalidate()
                    timer = nil
                }
        )
    }
}

/// 按下时键帽变成另一种底色，接近系统键盘的反馈。
struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
    }
}
