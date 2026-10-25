import SwiftUI
import UIKit

/// App 里用的品牌色。
enum AppColor {
    static let purple = Color(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255)
    static let violet = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
    static let gold = Color(red: 0xFD / 255, green: 0xE6 / 255, blue: 0x8A / 255)
    /// 键盘常用词的星标 #FF9F0A。
    static let keyboardStar = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    static let softFill = purple.opacity(0.12)
    /// 建议标签：字 #4A3BD6；未选白底 #DCD6FB 细圈，选中 #ECEAFD 底 #8B7CF6 细圈。
    static let deepPurple = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xC4 / 255, green: 0xB5 / 255, blue: 0xFD / 255, alpha: 1)
        : UIColor(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255, alpha: 1) })
    static let chipRing = Color(red: 0xDC / 255, green: 0xD6 / 255, blue: 0xFB / 255)
    static let chipSelectedRing = Color(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255)
    static let chipSelectedFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.24, green: 0.21, blue: 0.40, alpha: 1)
        : UIColor(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255, alpha: 1) })
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
        case .deploying: return PinyinStatus(text: L("正在部署", "Installing", "インストール中"), color: .orange)
        case .failed: return PinyinStatus(text: L("部署失败", "Install failed", "インストール失敗"), color: .red)
        default:
            return deployer.needsDeploy ? PinyinStatus(text: L("未部署", "Not installed", "未インストール"), color: .orange) : PinyinStatus(text: L("已就绪", "Ready", "準備完了"), color: .green)
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
            Label(L("键盘读不到 App 里的设置", "The keyboard can't read the app's settings", "キーボードがアプリの設定を読み込めません"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L("当前签名没有拿到 App Group。复制配置后，在键盘里点「从剪贴板导入配置」，导入后剪贴板会自动清空。", "This build has no App Group. Copy the settings, then tap \"Import settings from clipboard\" in the keyboard. The clipboard is cleared afterward.", "このビルドでは App Group が使えません。設定をコピーして、キーボードで「クリップボードから設定を読み込む」をタップしてください。読み込み後にクリップボードは消去されます。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(copied ? L("已复制", "Copied", "コピーしました") : L("复制配置", "Copy settings", "設定をコピー")) {
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

/// 键盘没开完全访问时，App 里改的设置读不到（P10）：「键盘」「模糊拼音」页顶部的黄色提示条。
struct NotSyncedBanner: View {
    var body: some View {
        if KeyboardStatus.fullAccess == false {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(hex: 0xFF9500)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("这些设置还没同步到键盘", "These settings aren't on the keyboard yet", "この設定はまだキーボードに反映されていません"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x3A2E10))
                    Text(L("键盘没开「允许完全访问」，读不到 App 里的设置，目前用默认值。拼音布局可以在键盘上长按「中/英」切换。",
                           "Allow Full Access is off, so the keyboard can't read the app's settings and uses defaults. Touch and hold 中/英 on the keyboard to switch the pinyin layout.",
                           "「フルアクセスを許可」がオフのため、キーボードはアプリの設定を読めず初期設定で動いています。ピンインの配列はキーボードの「中/英」を長押しで切り替えられます。"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(hex: 0x6B5A2E))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("去开启", "Turn On", "オンにする")) { AppSettings.open() }
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xFFF4D6)))
        }
    }
}
