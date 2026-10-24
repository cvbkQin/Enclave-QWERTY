import SwiftUI
import UIKit

/// App 里用的品牌色。
enum AppColor {
    static let purple = Color(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255)
    static let violet = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
    static let gold = Color(red: 0xFD / 255, green: 0xE6 / 255, blue: 0x8A / 255)
    static let softFill = purple.opacity(0.12)
    static let heroGradient = LinearGradient(colors: [Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255), violet],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum AppSettings {
    /// iOS 只允许跳到本 App 的设置页（里面有「键盘 › 允许完全访问」），不能直接跳到 通用 › 键盘。
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// 键盘能不能用：加没加键盘、完全访问、模型接口。
enum Readiness {
    /// 系统把用户加的键盘记在 AppleKeyboards 里，第三方键盘是扩展的 bundle id。
    static var keyboardAdded: Bool {
        guard let app = Bundle.main.bundleIdentifier else { return false }
        let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        return keyboards.contains("\(app).keyboard")
    }

    /// 键盘出现时记下来的；nil 表示键盘还没用过。
    static var fullAccess: Bool? { KeyboardStatus.fullAccess }

    /// 还没完成的步骤数（添加键盘、完全访问、模型接口）。
    static func remainingSteps(apiConfigured: Bool) -> Int {
        [keyboardAdded, fullAccess == true, apiConfigured].filter { !$0 }.count
    }
}

/// 设置列表行前面的彩色方块图标。
struct RowIcon: View {
    var systemName: String
    var color: Color
    var size: CGFloat = 29

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(color))
    }
}

/// 设置列表的一行：图标、标题、右边灰字。
struct IconRow: View {
    var systemName: String
    var color: Color
    var title: String
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: systemName, color: color)
            Text(title)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
        }
    }
}

/// 拼音词库现在的状态，首页、设置、词库页都用。
struct PinyinStatus {
    var text: String
    var color: Color

    @MainActor
    static func current(_ deployer: RimeDeployer) -> PinyinStatus {
        switch deployer.state {
        case .deploying: return PinyinStatus(text: "正在部署", color: .orange)
        case .failed: return PinyinStatus(text: "部署失败", color: .red)
        default:
            return deployer.needsDeploy ? PinyinStatus(text: "未部署", color: .orange) : PinyinStatus(text: "已就绪", color: .green)
        }
    }
}

/// 全宽紫色主按钮。
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.purple.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)))
    }
}

/// 共享配置不可用时首页顶部的提示条。
struct SharedConfigBanner: View {
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("键盘读不到 App 里的设置", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("当前签名没有拿到 App Group。复制配置后，在键盘里点「从剪贴板导入配置」，导入后剪贴板会自动清空。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(copied ? "已复制" : "复制配置") {
                if let string = SettingsStore.exportString() {
                    UIPasteboard.general.string = string
                    copied = true
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}
