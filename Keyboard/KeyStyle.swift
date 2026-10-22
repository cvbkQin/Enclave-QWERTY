import SwiftUI
import UIKit

/// 键盘尺寸，参照 iOS 自带键盘。键盘高度也从这里算。
enum KeyboardMetrics {
    /// 一个按键格子的高度（含上下间隙），按键本身是 42。
    static let slotHeight: CGFloat = 52
    static let keyInsetX: CGFloat = 3
    static let keyInsetY: CGFloat = 5
    static let keysHeight: CGFloat = slotHeight * 4

    static let topRow: CGFloat = 38
    static let previewHeight: CGFloat = 62
    static let actionRow: CGFloat = 34
    static let instructionRow: CGFloat = 32
    static let panelSpacing: CGFloat = 5
    static let panelTop: CGFloat = 6
    static let sidePadding: CGFloat = 3

    static var collapsedHeight: CGFloat { topRow + keysHeight + 2 }
    /// 展开后没有顶栏：预览行、操作行、要求行，下面是按键。
    static var expandedHeight: CGFloat {
        panelTop + previewHeight + actionRow + instructionRow + panelSpacing * 3 + keysHeight + 2
    }
}

/// 按键颜色，深浅色模式分别取 iOS 键盘的配色。
enum KeyStyle {
    static let charKey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.42, alpha: 1) : .white })
    static let functionKey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) })
    static let shadow = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0, alpha: 0.6) : UIColor(red: 0.53, green: 0.54, blue: 0.56, alpha: 1) })
    static let cornerRadius: CGFloat = 8.5

    static let letterFont = Font.system(size: 23)
    static let symbolFont = Font.system(size: 21)
    static let nineKeyFont = Font.system(size: 18, weight: .medium)
    static let functionFont = Font.system(size: 16)
    static let iconFont = Font.system(size: 18, weight: .regular)
}

/// 按键外观：圆角、底色、底部细阴影。外面留出间隙，间隙也能点到这个键，和系统键盘一样没有死区。
struct KeyCap<Content: View>: View {
    var fill: Color
    var content: Content

    init(fill: Color, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                    .fill(fill)
                    .shadow(color: KeyStyle.shadow, radius: 0, x: 0, y: 1)
            )
            .padding(.horizontal, KeyboardMetrics.keyInsetX)
            .padding(.vertical, KeyboardMetrics.keyInsetY)
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
        KeyCap(fill: pressed ? KeyStyle.charKey : KeyStyle.functionKey) {
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
