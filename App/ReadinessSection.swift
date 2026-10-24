import SwiftUI
import UIKit

/// 设置页顶部的「准备情况」：键盘加了没有、完全访问、拼音词库、共享配置。
struct ReadinessSection: View {
    var apiConfigured: Bool
    @ObservedObject private var deployer = RimeDeployer.shared
    @Environment(\.scenePhase) private var scenePhase
    /// 从系统设置回来时重新读一遍。
    @State private var refresh = UUID()

    var body: some View {
        Section {
            row(keyboardAdded ? .done : .missing, "已添加 Enclave 键盘") {
                if !keyboardAdded { openSettingsButton("去添加") }
            }
            fullAccessRow
            row(pinyinState, "拼音词库") {
                Text(pinyinText).foregroundStyle(.secondary)
            }
            row(apiConfigured ? .done : .missing, "模型接口") {
                Text(apiConfigured ? "已配置" : "在下面填写").foregroundStyle(.secondary)
            }
            row(SharedStorage.isShared ? .done : .missing, "App 与键盘共享配置") {
                Text(SharedStorage.isShared ? "已开启" : "不可用").foregroundStyle(.secondary)
            }
        } header: {
            Text("准备情况")
        }
        .id(refresh)
        .onChange(of: scenePhase) { if $0 == .active { refresh = UUID() } }
    }

    private enum Mark { case done, missing, unknown }

    /// 已开启是绿色 ✓；从没用过键盘是灰色圆点，右边灰字「用一次键盘后确认」；记录为未开启是橙色 !，右边「去开启」。
    @ViewBuilder
    private var fullAccessRow: some View {
        switch KeyboardStatus.fullAccess {
        case true?:
            row(.done, "允许完全访问") { EmptyView() }
        case false?:
            row(.missing, "允许完全访问") { openSettingsButton("去开启") }
        case nil:
            row(.unknown, "允许完全访问") { Text("用一次键盘后确认").foregroundStyle(.secondary) }
        }
    }

    private func row<Trailing: View>(_ mark: Mark, _ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            switch mark {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .missing:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .unknown:
                Image(systemName: "circle.fill").foregroundStyle(Color.secondary.opacity(0.4))
            }
            Text(title)
            Spacer()
            trailing().font(.footnote)
        }
    }

    private func openSettingsButton(_ title: String) -> some View {
        Button(title) { AppSettings.open() }
            .buttonStyle(.borderless)
    }

    /// 系统把用户加的键盘记在 AppleKeyboards 里，第三方键盘是扩展的 bundle id。
    private var keyboardAdded: Bool {
        guard let app = Bundle.main.bundleIdentifier else { return false }
        let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        return keyboards.contains("\(app).keyboard")
    }

    private var pinyinState: Mark {
        if case .failed = deployer.state { return .missing }
        return deployer.needsDeploy ? .unknown : .done
    }

    private var pinyinText: String {
        switch deployer.state {
        case .deploying: return "正在部署…"
        case .failed: return "部署失败"
        default: return deployer.needsDeploy ? "未部署" : "拼音词库 · 已就绪"
        }
    }
}

enum AppSettings {
    /// iOS 只允许跳到本 App 的设置页（里面有「键盘 › 允许完全访问」），不能直接跳到 通用 › 键盘。
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
