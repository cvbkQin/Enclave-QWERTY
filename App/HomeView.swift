import SwiftUI

/// 首页：准备好了显示就绪卡片和当前配置；没准备好换成分步引导。
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    /// 从系统设置回来时重新读一遍键盘状态。
    @State private var refresh = UUID()

    var body: some View {
        NavigationStack(path: $router.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if Readiness.remainingSteps(apiConfigured: store.settings.isConfigured) == 0 {
                        Text("Enclave").font(.largeTitle.bold()).padding(.top, 8)
                        Dashboard()
                    } else {
                        Text("欢迎使用").font(.largeTitle.bold()).padding(.top, 8)
                        OnboardingSteps()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .id(refresh)
            }
            .background(Color(.systemGroupedBackground))
            // 自己画大标题，导航栏标题写「首页」，这样二级页的返回按钮叫「首页」。
            .navigationTitle("首页")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppRouter.HomePage.self) { page in
                switch page {
                case .keyboard: KeyboardSettingsView()
                case .commonWords: CommonWordsView()
                case .lab: LabView()
                case .scene(let index): SceneView(index: index)
                }
            }
            // 键盘页里的「模糊拼音」。
            .navigationDestination(for: AppRouter.SettingsPage.self) { page in
                if page == .fuzzy { FuzzyPinyinView() }
            }
            .onChange(of: scenePhase) { if $0 == .active { refresh = UUID() } }
        }
    }
}

/// 首页试用最后几天的橙色提醒条（U7）。
private struct TrialBanner: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var unlock = UnlockStore.shared

    var body: some View {
        if case .trial(let days, _) = unlock.access, unlock.access.isEndingSoon {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: 0xC93400))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("试用还剩 \(days) 天", "\(days) days left in your free trial", "無料体験は残り \(days) 日"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("到期后 AI 每天限 \(AIAccess.dailyFreeUses) 次，打字免费",
                           "After that, AI is limited to \(AIAccess.dailyFreeUses) a day. Typing stays free",
                           "終了後の AI は 1 日 \(AIAccess.dailyFreeUses) 回まで。入力は無料です"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button { router.openSettings(.unlock) } label: {
                    Text(L("\(unlock.displayPrice) 解锁", "Unlock \(unlock.displayPrice)", "\(unlock.displayPrice)で購入"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(Color(hex: 0xFF8A00)))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 1, green: 0.54, blue: 0, alpha: 0.16)
                    : UIColor(red: 1, green: 0xF4 / 255, blue: 0xE5 / 255, alpha: 1)
            })))
        }
    }
}

/// 准备好以后的首页：就绪卡片、当前配置四宫格、小技巧。
private struct Dashboard: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var words = CommonWordsModel()

    var body: some View {
        if !SharedStorage.isShared { SharedConfigBanner() }
        hero
        TrialBanner()
        sectionTitle("当前配置")
        ModelRow(model: store.settings.model, status: modelStatus) { router.openModel() }
        HStack(spacing: 12) {
            ConfigCard(icon: "keyboard", color: .blue, label: "键盘", value: store.settings.keyboardLayout.shortTitle,
                       detail: "布局、模糊拼音、震动", dot: nil) { router.openHome(.keyboard) }
            ConfigCard(icon: "text.book.closed", color: .green, label: "常用词", value: "\(words.all.count) 个",
                       detail: wordsDetail, dot: nil) { router.openHome(.commonWords) }
        }
        .onAppear { words.reload() }
        sectionTitle("小技巧")
        VStack(alignment: .leading, spacing: 8) {
            Text("· 选中一段文字再点润色，只改选中的部分")
            Text("· 点「\(store.settings.selectedStyle?.name ?? "风格")▾」写要求，比如「更委婉」「翻成英文」")
            Text("· 长按结果卡片可以复制")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("准备就绪").font(.caption).opacity(0.8)
                Text("键盘可以用了").font(.title2.bold())
                Text("在任意输入框切到 Enclave，写完点「✨ 润色」。")
                    .font(.footnote).opacity(0.85)
                    .padding(.trailing, 70)
                Button {
                    router.openHome(.lab)
                } label: {
                    Label("场景实验室", systemImage: "flask")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.purple)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppColor.gold)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppColor.heroGradient))
    }

    /// 测试过才知道连不连得上；没测过显示「还没测试」。
    private var modelStatus: (text: String, color: Color) {
        switch store.test {
        case .success: return ("连接正常", .green)
        case .failure: return ("连不上", .red)
        case .running: return ("正在测试", .orange)
        case .idle:
            switch store.lastTestOK {
            case true?: return ("连接正常", .green)
            case false?: return ("连不上", .red)
            case nil: return ("还没测试", Color.secondary.opacity(0.6))
            }
        }
    }

    private var wordsDetail: String {
        let manual = words.count(.manual), imported = words.count(.imported)
        if manual + imported == 0 { return words.all.isEmpty ? "还没有，点进去添加" : "来自系统文本替换" }
        return "手动 \(manual) · 导入 \(imported)"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).padding(.leading, 4).padding(.bottom, -6)
    }
}

/// 首页「接口」整行：模型名和连接状态，点进「接口」标签。
private struct ModelRow: View {
    var model: String
    var status: (text: String, color: Color)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RowIcon(systemName: "cpu", color: AppColor.purple, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("接口").font(.caption).foregroundStyle(.secondary)
                    Text(model.isEmpty ? "未配置" : model).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 7, height: 7)
                    Text(status.text).font(.footnote.weight(.semibold)).foregroundStyle(status.color)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}

/// 首页的一张卡片，点了跳到对应页面。
private struct ConfigCard: View {
    var icon: String
    var color: Color
    var label: String
    var value: String
    var detail: String
    var dot: Color?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    RowIcon(systemName: icon, color: color, size: 26)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 6)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value.isEmpty ? "未配置" : value).font(.headline).lineLimit(1).foregroundStyle(.primary)
                HStack(spacing: 4) {
                    if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}

/// 开启键盘的三步：添加键盘、允许完全访问、配置模型接口；下面是词库部署进度。首页和「开启键盘指南」共用。
struct OnboardingSteps: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        let done = [Readiness.keyboardAdded, Readiness.fullAccess == true, store.settings.isConfigured]
        let remaining = done.filter { !$0 }.count
        let current = done.firstIndex(of: false)
        VStack(alignment: .leading, spacing: 12) {
            Text(remaining == 0 ? "三步都完成了，键盘可以用了。" : "还差 \(remaining) 步就能用 AI 润色，打字现在就能用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(3 - remaining), total: 3).tint(AppColor.purple)
            if !SharedStorage.isShared { SharedConfigBanner() }
            StepCard(number: 1, title: "添加 Enclave 键盘", done: done[0], current: current == 0) {
                Text("打开系统设置 › 通用 › 键盘 › 键盘 › 添加新键盘，选 Enclave。")
            }
            StepCard(number: 2, title: "允许完全访问", done: done[1], current: current == 1) {
                Text("键盘要联网才能调用你的模型。进入 Enclave 设置 › 键盘，打开「允许完全访问」。")
                Button("打开 Enclave 设置") { AppSettings.open() }
                    .buttonStyle(StepButtonStyle(prominent: current == 1))
                Text(Readiness.fullAccess == false ? "键盘上次出现时完全访问还没打开。" : "用一次键盘后，这里会自动打勾。")
                    .font(.caption)
                    .foregroundStyle(Readiness.fullAccess == false ? Color.orange : Color.secondary)
            }
            StepCard(number: 3, title: "配置模型接口", done: done[2], current: current == 2) {
                Text("填 API 地址和 Key，或者从剪贴板导入配置。")
                Button("去配置") { router.openModel() }
                    .buttonStyle(StepButtonStyle(prominent: current == 2))
            }
            DeployCard()
        }
    }
}

private struct StepCard<Content: View>: View {
    var number: Int
    var title: String
    var done: Bool
    var current: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.footnote.bold())
                        .foregroundStyle(current ? .white : .secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(current ? AppColor.purple : Color.clear))
                        .overlay(Circle().strokeBorder(current ? Color.clear : Color.secondary.opacity(0.5)))
                }
                Text(title).font(.headline).foregroundStyle(done ? .secondary : .primary)
            }
            if !done {
                VStack(alignment: .leading, spacing: 10) { content }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(AppColor.purple, lineWidth: current ? 1.5 : 0))
    }
}

/// 当前这一步是实心紫色按钮，后面的步骤是淡紫底。
private struct StepButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : AppColor.purple)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(prominent ? AppColor.purple : AppColor.softFill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 拼音词库部署进度。编译没有真实进度，按大约一分钟估一条进度条。
private struct DeployCard: View {
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: "character.book.closed", color: .orange)
            switch deployer.state {
            case .deploying:
                VStack(alignment: .leading, spacing: 6) {
                    Text("正在部署拼音词库…").font(.subheadline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = context.date.timeIntervalSince(deployer.startedAt ?? context.date)
                        HStack {
                            ProgressView(value: min(elapsed / 60, 0.95)).tint(.orange)
                            Text("约 \(max(5, 60 - Int(elapsed))) 秒").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text("拼音词库部署失败").font(.subheadline)
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("重试") { deployer.deploy() }.font(.subheadline.weight(.semibold))
            default:
                Text(deployer.needsDeploy ? "拼音词库还没部署" : "拼音词库已就绪").font(.subheadline)
                Spacer()
                if deployer.needsDeploy {
                    Button("部署") { deployer.deploy() }.font(.subheadline.weight(.semibold))
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
