import SwiftUI
import UIKit

/// 设置顶部「Enclave AI」行（U5/U6）：渐变星星图标，右边按试用状态变色。
struct EnclaveAIRow: View {
    @ObservedObject private var unlock = UnlockStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(
                    LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Enclave AI").font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(status.text).font(.system(size: 14, weight: .medium)).foregroundStyle(status.color).lineLimit(1)
        }
        .frame(minHeight: 58)
    }

    private var subtitle: String {
        switch unlock.access {
        case .trial(_, let ends):
            return L("\(Loc.monthDay(ends)) 结束", "Ends \(Loc.monthDay(ends))", "\(Loc.monthDay(ends))に終了")
        case .expired:
            return L("今天已用 \(AIAccess.usesToday) / \(AIAccess.dailyFreeUses) 次",
                     "\(AIAccess.usesToday) of \(AIAccess.dailyFreeUses) used today",
                     "今日 \(AIAccess.usesToday) / \(AIAccess.dailyFreeUses) 回使用")
        case .unlocked:
            return L("一次买断 · 不限次数", "One-time purchase · No limits", "買い切り・回数制限なし")
        }
    }

    private var status: (text: String, color: Color) {
        switch unlock.access {
        case .trial(let days, _):
            return (L("试用剩余 \(days) 天", "\(days) days left", "残り \(days) 日"),
                    Color(hex: unlock.access.isEndingSoon ? 0xC93400 : 0x5B4BE8))
        case .expired: return (L("试用已结束", "Trial ended", "無料体験が終了"), Color(hex: 0xD70015))
        case .unlocked: return (L("已解锁", "Unlocked", "購入済み"), Color(hex: 0x248A3D))
        }
    }
}

/// 设置：拼音词库；开启键盘指南、场景实验室；共享配置、隐私、关于。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            List {
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.unlock) { EnclaveAIRow() }
                }
                // 键盘和常用词从首页进。
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.pinyin) {
                        IconRow(systemName: "character.book.closed", color: .orange, title: "拼音词库", value: "万象拼音")
                    }
                }
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.guide) {
                        IconRow(systemName: "questionmark", color: .green, title: "开启键盘指南")
                    }
                    NavigationLink(value: AppRouter.SettingsPage.playground) {
                        IconRow(systemName: "flask", color: Color(red: 0.69, green: 0.32, blue: 0.87), title: "场景实验室",
                                value: "\(LabScene.all.count) 个场景")
                    }
                }
                Section {
                    IconRow(systemName: "link", color: .gray, title: "App 与键盘共享配置",
                            value: SharedStorage.isShared ? "已开启" : "不可用")
                    if !SharedStorage.isShared { SharedConfigBanner().listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
                    NavigationLink(value: AppRouter.SettingsPage.privacy) {
                        IconRow(systemName: "lock", color: .gray, title: "隐私")
                    }
                    NavigationLink(value: AppRouter.SettingsPage.about) {
                        IconRow(systemName: "info", color: .gray, title: "关于 Enclave", value: AboutView.version)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationDestination(for: AppRouter.SettingsPage.self) { page in
                switch page {
                case .keyboard: KeyboardSettingsView()
                case .fuzzy: FuzzyPinyinView()
                case .pinyin: PinyinView()
                case .guide:
                    ScrollView {
                        OnboardingSteps().padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle("开启键盘指南")
                    .navigationBarTitleDisplayMode(.inline)
                case .playground: LabView()
                case .privacy: PrivacyView()
                case .about: AboutView()
                case .unlock: UnlockView()
                }
            }
        }
    }
}

// MARK: - 模型接口

/// 常用服务商，选了自动填地址和模型。
private enum Provider: CaseIterable, Identifiable {
    case deepseek, openai, ollama, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama"
        case .custom: return "自定义"
        }
    }

    var preset: (baseURL: String, model: String)? {
        switch self {
        case .deepseek: return ("https://api.deepseek.com/v1", "deepseek-chat")
        case .openai: return ("https://api.openai.com/v1", "gpt-4o-mini")
        case .ollama: return ("http://192.168.1.100:11434/v1", "qwen2.5:7b")
        case .custom: return nil
        }
    }

    static func detect(_ baseURL: String) -> Provider {
        if baseURL.contains("api.deepseek.com") { return .deepseek }
        if baseURL.contains("api.openai.com") { return .openai }
        if baseURL.contains(":11434") { return .ollama }
        return .custom
    }
}

struct ModelSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var provider: Provider = .custom
    @State private var importResult: Bool?

    var body: some View {
        Form {
            Section("服务商") {
                HStack(spacing: 8) {
                    ForEach(Provider.allCases) { item in
                        Button { choose(item) } label: {
                            Text(item.title)
                                .font(.subheadline.weight(provider == item ? .semibold : .regular))
                                .foregroundStyle(provider == item ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Capsule().fill(provider == item ? AppColor.purple : Color(.secondarySystemGroupedBackground)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledField(title: "API 地址", text: $store.settings.baseURL, placeholder: "https://api.deepseek.com/v1", keyboard: .URL)
                LabeledField(title: "模型", text: $store.settings.model, placeholder: "deepseek-chat")
                HStack {
                    Text("API Key")
                    SecureField("自建服务可以留空", text: $store.apiKey)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("连接")
            } footer: {
                Text(provider == .ollama
                     ? "把地址里的 IP 换成运行 Ollama 的电脑的局域网地址，地址填到 /v1。"
                     : "选一个服务商会自动填好地址。自建 Ollama / vLLM / LM Studio 选「自定义」，地址填到 /v1。")
                    + Text("API Key 只存在本机钥匙串里，不经过任何第三方服务器。")
            }
            Section {
                Stepper(value: $store.settings.temperature, in: 0...1.5, step: 0.1) {
                    HStack {
                        Text("温度")
                        Spacer()
                        Text(store.settings.temperature, format: .number.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $store.settings.maxTokens, in: 256...8192, step: 256) {
                    HStack {
                        Text("最大输出")
                        Spacer()
                        Text("\(store.settings.maxTokens)").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("生成参数")
            } footer: {
                Text("温度越低越稳定，润色建议 0.2–0.5。")
            }
            Section {
                VStack(spacing: 10) {
                    Button {
                        Task { await store.runTest() }
                    } label: {
                        HStack(spacing: 8) {
                            if store.test == .running { ProgressView().tint(.white) }
                            Text(store.test == .running ? "正在测试…" : "测试连接")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!store.settings.isConfigured || store.test == .running)
                    testResult
                    Button(importResult == false ? "剪贴板里没有 Enclave 配置" : importResult == true ? "已导入" : "从剪贴板导入配置") {
                        importConfig()
                    }
                    .font(.footnote)
                    .foregroundStyle(importResult == false ? Color.orange : AppColor.purple)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("模型接口")
        .onAppear { provider = Provider.detect(store.settings.baseURL) }
    }

    @ViewBuilder
    private var testResult: some View {
        switch store.test {
        case .success(_, let seconds):
            Label("连接成功，用时 \(seconds, format: .number.precision(.fractionLength(1))) 秒", systemImage: "checkmark")
                .font(.footnote)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failure(let message):
            Label(message, systemImage: "xmark")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    private func choose(_ item: Provider) {
        if item != provider, let preset = item.preset {
            store.settings.baseURL = preset.baseURL
            store.settings.model = preset.model
        }
        provider = item
    }

    private func importConfig() {
        guard let string = UIPasteboard.general.string, SettingsStore.importString(string) else {
            importResult = false
            return
        }
        store.reload()
        provider = Provider.detect(store.settings.baseURL)
        importResult = true
    }
}

private struct LabeledField: View {
    var title: String
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(title)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

// MARK: - 键盘

struct KeyboardSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach([KeyboardLayout.nineKey, .qwerty]) { layout in
                        LayoutCard(layout: layout, selected: store.settings.keyboardLayout == layout) {
                            store.settings.keyboardLayout = layout
                        }
                    }
                }
                // 卡片放在普通行里，离分组的大圆角远一点，描边不会被裁。
                .padding(.vertical, 6)
            } header: {
                Text("中文布局")
            } footer: {
                Text("英文总是用全键盘。")
            }
            Section("拼音") {
                NavigationLink(value: AppRouter.SettingsPage.fuzzy) {
                    HStack {
                        Text("模糊拼音")
                        Spacer()
                        Text(store.settings.fuzzyPinyin.isEmpty ? "未开启" : "已开 \(store.settings.fuzzyPinyin.count) 组")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("按键反馈") {
                Toggle("按键震动", isOn: $store.settings.keyHaptics)
                Toggle(isOn: $store.settings.keySound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("按键声音")
                        Text("手机静音时不响").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("动画") {
                Toggle(isOn: $store.settings.polishAnimation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("润色时的发光动画")
                        Text("系统开了「减弱动态效果」时自动关闭").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(AppColor.purple)
        .navigationTitle("键盘")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 布局选择卡片：上面一张简化的键盘图示，下面名称和勾选圈。
private struct LayoutCard: View {
    var layout: KeyboardLayout
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                illustration
                    .padding(8)
                    .frame(height: 76)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemGray5)))
                HStack {
                    Text(layout.shortTitle).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AppColor.purple : Color.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? AppColor.softFill.opacity(0.5) : Color(.systemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? AppColor.purple : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var illustration: some View {
        let rows = layout == .nineKey ? [4, 4, 4, 4] : [10, 9, 7, 5]
        return VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, count in
                HStack(spacing: 3) {
                    ForEach(0..<count, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(.systemBackground))
                    }
                }
                .padding(.horizontal, layout == .qwerty && count < 10 ? CGFloat(10 - count) * 3 : 0)
            }
        }
    }
}

// MARK: - 模糊拼音

struct FuzzyPinyinView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var deployer = RimeDeployer.shared
    @State private var selection: Set<FuzzyPinyin> = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header("快速选择")
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([FuzzyPinyin.Preset.off, .retroflex, .nasal]) { presetChip($0) }
                    }
                    presetChip(.southern)
                }
                header("声母")
                grid(FuzzyPinyin.initials)
                header("韵母")
                grid(FuzzyPinyin.finals)
                Text("例：开了 z = zh，打 zi 也会出「知」。开得越多，候选越杂，按自己的口音选几组就好。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Button(deployer.state == .deploying ? "正在部署…" : "应用并重新部署词库") {
                    store.settings.fuzzyPinyin = selection
                    deployer.deploy()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(deployer.state == .deploying || (selection == store.settings.fuzzyPinyin && !deployer.needsDeploy))
                .padding(.top, 8)
                Group {
                    if case .failed(let message) = deployer.state {
                        Text(message).foregroundStyle(.red)
                    } else if deployer.state == .done && selection == store.settings.fuzzyPinyin {
                        Text("已生效，切回键盘就能用。").foregroundStyle(.green)
                    } else {
                        Text("改动后要重新部署一次词库才生效，约 1 分钟。").foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("模糊拼音")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            selection = store.settings.fuzzyPinyin
            loaded = true
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
    }

    private func presetChip(_ preset: FuzzyPinyin.Preset) -> some View {
        let on = selection == preset.groups
        return Button { selection = preset.groups } label: {
            Text(preset.title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(on ? AppColor.purple : Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private func grid(_ items: [FuzzyPinyin]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            ForEach(items) { item in
                let on = selection.contains(item)
                Button {
                    if on { selection.remove(item) } else { selection.insert(item) }
                } label: {
                    HStack {
                        Text(item.title).font(.body.monospaced())
                            .foregroundStyle(on ? AppColor.purple : Color.primary)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? AppColor.purple : Color.secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? AppColor.softFill : Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(on ? AppColor.purple : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 拼音词库

struct PinyinView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var deployer = RimeDeployer.shared
    @State private var size: Int64?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    RowIcon(systemName: "character.book.closed", color: .orange, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("万象拼音").font(.headline)
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if deployer.state == .deploying {
                        ProgressView()
                    } else {
                        let status = PinyinStatus.current(deployer)
                        Text(status.text).font(.subheadline.weight(.semibold)).foregroundStyle(status.color)
                    }
                }
                .padding(.vertical, 6)
                if case .failed(let message) = deployer.state {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                if !store.settings.fuzzyPinyin.isEmpty {
                    HStack {
                        Text("模糊拼音")
                        Spacer()
                        Text("已开 \(store.settings.fuzzyPinyin.count) 组").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button(deployer.state == .deploying ? "正在部署…" : "重新部署词库") { deployer.deploy() }
                    .disabled(deployer.state == .deploying)
            } footer: {
                Text("词库在本机编译，第一次打开 App 时自动部署，大约一分钟，期间不要退出 App。词库出错或更新后再点重新部署。键盘需要打开「允许完全访问」才能读到词库。")
            }
        }
        .navigationTitle("拼音词库")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deployer.state) {
            size = await Task.detached { RimeDeployer.diskSize() }.value
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let date = RimeDeployer.deployedAt, !deployer.needsDeploy {
            parts.append(date.formatted(.dateTime.month().day()) + " 部署")
        }
        if let size, size > 0 {
            parts.append("约 " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? "万象拼音词库，CC BY 4.0" : parts.joined(separator: " · ")
    }
}

// MARK: - 隐私、关于

struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Text("打字和拼音候选全部在手机上完成，不联网。")
                Text("只有点「✨ 润色」或「再润」时，输入框里的文字和你写的要求才会发给你自己配置的模型接口，Enclave 没有自己的服务器。")
                Text("API Key 只存在本机钥匙串里。")
                Text("「允许完全访问」只用来联网调用模型、按键震动，以及和 App 共享设置。")
            }
            .font(.subheadline)
        }
        .navigationTitle("隐私")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section {
                HStack { Text("版本"); Spacer(); Text(Self.version).foregroundStyle(.secondary) }
            }
            LicensesSection()
        }
        .navigationTitle("关于 Enclave")
        .navigationBarTitleDisplayMode(.inline)
    }
}
