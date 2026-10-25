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
            let uses = AIAccess.dailyFreeUses
            return AIAccess.usesLeftToday > 0
                ? L("试用已结束 · 每天免费 \(uses) 次", "Trial ended · \(uses) free a day", "無料体験終了 · 1 日 \(uses) 回無料")
                : L("明天 0 点恢复 \(uses) 次 · 解锁不限次数", "\(uses) more at midnight · unlock for unlimited",
                    "0 時に \(uses) 回に戻ります · 購入で無制限")
        case .unlocked:
            return L("一次买断 · 不限次数", "One-time purchase · No limits", "買い切り・回数制限なし")
        }
    }

    private var status: (text: String, color: Color) {
        switch unlock.access {
        case .trial(let days, _):
            return (L("试用剩余 \(days) 天", "\(days) days left", "残り \(days) 日"),
                    Color(hex: unlock.access.isEndingSoon ? 0xC93400 : 0x5B4BE8))
        case .expired:
            let left = AIAccess.usesLeftToday
            return left > 0
                ? (L("今天剩 \(left) 次", "\(left) left today", "今日あと \(left) 回"), Color(hex: 0xC93400))
                : (L("今天已用完", "None left today", "今日の分は終了"), Color(hex: 0xD70015))
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
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.language) {
                        IconRow(systemName: "globe", color: Color(hex: 0x007AFF), title: L("语言", "Language", "言語"),
                                value: router.language == .system ? nil : router.language.nativeName)
                    }
                }
                // 键盘和常用词从首页进。
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.pinyin) {
                        IconRow(systemName: "character.book.closed", color: .orange, title: L("拼音词库", "Pinyin dictionary", "ピンイン辞書"), value: L("万象拼音", "Wanxiang Pinyin", "万象ピンイン"))
                    }
                }
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.guide) {
                        IconRow(systemName: "questionmark", color: .green, title: L("开启键盘指南", "Keyboard setup guide", "キーボードの設定ガイド"))
                    }
                    NavigationLink(value: AppRouter.SettingsPage.playground) {
                        IconRow(systemName: "flask", color: Color(red: 0.69, green: 0.32, blue: 0.87), title: L("场景实验室", "Playground", "お試しラボ"),
                                value: L("\(LabScene.all.count) 个场景", "\(LabScene.all.count) scenes", "\(LabScene.all.count) 個のシーン"))
                    }
                }
                Section {
                    if SharedStorage.usesClipboardConfig {
                    IconRow(systemName: "link", color: .gray, title: L("App 与键盘共享配置", "Shared with keyboard", "キーボードと設定を共有"),
                            value: SharedStorage.isShared ? L("已开启", "On", "オン") : L("不可用", "Unavailable", "利用不可"))
                    if !SharedStorage.isShared { SharedConfigBanner().listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
                    }
                    NavigationLink(value: AppRouter.SettingsPage.privacy) {
                        IconRow(systemName: "lock", color: .gray, title: L("隐私", "Privacy", "プライバシー"))
                    }
                    NavigationLink(value: AppRouter.SettingsPage.about) {
                        IconRow(systemName: "info", color: .gray, title: L("关于 Enclave", "About Enclave", "Enclave について"), value: AboutView.version)
                    }
                }
            }
            .navigationTitle(L("设置", "Settings", "設定"))
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
                    .navigationTitle(L("开启键盘指南", "Keyboard setup guide", "キーボードの設定ガイド"))
                    .navigationBarTitleDisplayMode(.inline)
                case .playground: LabView()
                case .privacy: PrivacyView()
                case .about: AboutView()
                case .unlock: UnlockView()
                case .language: LanguageView()
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
        case .custom: return L("自定义", "Custom", "カスタム")
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
            Section(L("服务商", "Provider", "サービス")) {
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
                LabeledField(title: L("API 地址", "API URL", "API の URL"), text: $store.settings.baseURL, placeholder: "https://api.deepseek.com/v1", keyboard: .URL)
                LabeledField(title: L("模型", "Model", "モデル"), text: $store.settings.model, placeholder: "deepseek-chat")
                HStack {
                    Text("API Key")
                    SecureField(L("自建服务可以留空", "Optional for self-hosted", "セルフホストなら空欄で可"), text: $store.apiKey)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text(L("连接", "Connection", "接続"))
            } footer: {
                Text(provider == .ollama
                     ? L("把地址里的 IP 换成运行 Ollama 的电脑的局域网地址，地址填到 /v1。", "Replace the IP with the local address of the computer running Ollama. The URL ends with /v1. ", "IP を Ollama を動かしているパソコンのローカルアドレスに置き換えます。URL は /v1 までです。")
                     : L("选一个服务商会自动填好地址。自建 Ollama / vLLM / LM Studio 选「自定义」，地址填到 /v1。", "Pick a provider to fill in the URL. For self-hosted Ollama, vLLM or LM Studio, choose Custom. The URL ends with /v1. ", "サービスを選ぶと URL が入力されます。セルフホストの Ollama / vLLM / LM Studio は「カスタム」を選び、URL は /v1 までです。"))
                    + Text(L("API Key 只存在本机钥匙串里，不经过任何第三方服务器。", "Your API key stays in this iPhone's keychain and never passes through a third-party server.", "API キーはこの iPhone のキーチェーンにだけ保存され、第三者のサーバーを通りません。"))
            }
            Section {
                Stepper(value: $store.settings.temperature, in: 0...1.5, step: 0.1) {
                    HStack {
                        Text(L("温度", "Temperature", "温度"))
                        Spacer()
                        Text(store.settings.temperature, format: .number.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $store.settings.maxTokens, in: 256...8192, step: 256) {
                    HStack {
                        Text(L("最大输出", "Max output", "最大出力"))
                        Spacer()
                        Text("\(store.settings.maxTokens)").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("生成参数", "Generation", "生成パラメータ"))
            } footer: {
                Text(L("温度越低越稳定，润色建议 0.2–0.5。", "Lower is steadier. 0.2–0.5 works well for polishing.", "低いほど安定します。整えるには 0.2〜0.5 がおすすめです。"))
            }
            Section {
                VStack(spacing: 10) {
                    Button {
                        Task { await store.runTest() }
                    } label: {
                        HStack(spacing: 8) {
                            if store.test == .running { ProgressView().tint(.white) }
                            Text(store.test == .running ? L("正在测试…", "Testing…", "テスト中…") : L("测试连接", "Test connection", "接続をテスト"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!store.settings.isConfigured || store.test == .running)
                    testResult
                    if SharedStorage.usesClipboardConfig {
                    Button(importResult == false ? L("剪贴板里没有 Enclave 配置", "No Enclave settings on the clipboard", "クリップボードに Enclave の設定がありません") : importResult == true ? L("已导入", "Imported", "読み込みました") : L("从剪贴板导入配置", "Import settings from clipboard", "クリップボードから設定を読み込む")) {
                        importConfig()
                    }
                    .font(.footnote)
                    .foregroundStyle(importResult == false ? Color.orange : AppColor.purple)
                    .padding(.top, 4)
                    }
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(L("模型接口", "Model API", "モデル API"))
        .onAppear { provider = Provider.detect(store.settings.baseURL) }
    }

    @ViewBuilder
    private var testResult: some View {
        switch store.test {
        case .success(_, let seconds):
            Label(L("连接成功，用时 \(String(format: "%.1f", seconds)) 秒", "Connected in \(String(format: "%.1f", seconds)) s", "接続できました（\(String(format: "%.1f", seconds)) 秒）"), systemImage: "checkmark")
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
                Text(L("中文布局", "Chinese layout", "中国語の配列"))
            } footer: {
                Text(L("英文总是用全键盘。", "English always uses QWERTY.", "英語は常に QWERTY です。"))
            }
            Section(L("拼音", "Pinyin", "ピンイン")) {
                NavigationLink(value: AppRouter.SettingsPage.fuzzy) {
                    HStack {
                        Text(L("模糊拼音", "Fuzzy pinyin", "あいまい入力"))
                        Spacer()
                        Text(store.settings.fuzzyPinyin.isEmpty ? L("未开启", "Off", "オフ") : L("已开 \(store.settings.fuzzyPinyin.count) 组", "\(store.settings.fuzzyPinyin.count) on", "\(store.settings.fuzzyPinyin.count) 組オン"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(L("按键反馈", "Key feedback", "キーのフィードバック")) {
                Toggle(L("按键震动", "Haptics", "触覚"), isOn: $store.settings.keyHaptics)
                Toggle(isOn: $store.settings.keySound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("按键声音", "Sounds", "サウンド"))
                        Text(L("手机静音时不响", "Silent when the iPhone is muted", "消音モードでは鳴りません")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section(L("动画", "Animation", "アニメーション")) {
                Toggle(isOn: $store.settings.polishAnimation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("润色时的发光动画", "Glow while polishing", "整えるときの光るアニメーション"))
                        Text(L("系统开了「减弱动态效果」时自动关闭", "Turns off automatically with Reduce Motion", "「視差効果を減らす」がオンのときは自動でオフ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(AppColor.purple)
        .navigationTitle(L("键盘", "Keyboard", "キーボード"))
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
                header(L("快速选择", "Presets", "プリセット"))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach([FuzzyPinyin.Preset.off, .retroflex, .nasal]) { presetChip($0) }
                    }
                    presetChip(.southern)
                }
                header(L("声母", "Initials", "声母"))
                grid(FuzzyPinyin.initials)
                header(L("韵母", "Finals", "韻母"))
                grid(FuzzyPinyin.finals)
                Text(L("例：开了 z = zh，打 zi 也会出「知」。开得越多，候选越杂，按自己的口音选几组就好。", "Example: with z = zh on, typing zi also gives 知. More pairs mean noisier candidates, so pick just the ones that match your accent.", "例：z = zh をオンにすると zi でも「知」が出ます。増やすほど候補が増えるので、なまりに合うものだけ選びましょう。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Button(deployer.state == .deploying ? L("正在部署…", "Installing…", "インストール中…") : L("应用并重新部署词库", "Apply and reinstall dictionary", "適用して辞書を再インストール")) {
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
                        Text(L("已生效，切回键盘就能用。", "Done. Switch back to the keyboard to use it.", "反映されました。キーボードに戻ると使えます。")).foregroundStyle(.green)
                    } else {
                        Text(L("改动后要重新部署一次词库才生效，约 1 分钟。", "Changes take effect after reinstalling the dictionary, about 1 minute.", "変更は辞書の再インストール後に反映されます（約 1 分）。")).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("模糊拼音", "Fuzzy pinyin", "あいまい入力"))
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
                        Text(L("万象拼音", "Wanxiang Pinyin", "万象ピンイン")).font(.headline)
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
                        Text(L("模糊拼音", "Fuzzy pinyin", "あいまい入力"))
                        Spacer()
                        Text(L("已开 \(store.settings.fuzzyPinyin.count) 组", "\(store.settings.fuzzyPinyin.count) on", "\(store.settings.fuzzyPinyin.count) 組オン")).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button(deployer.state == .deploying ? L("正在部署…", "Installing…", "インストール中…") : L("重新部署词库", "Reinstall dictionary", "辞書を再インストール")) { deployer.deploy() }
                    .disabled(deployer.state == .deploying)
            } footer: {
                Text(L("词库在本机编译，第一次打开 App 时自动部署，大约一分钟，期间不要退出 App。词库出错或更新后再点重新部署。键盘需要打开「允许完全访问」才能读到词库。", "The dictionary is built on this iPhone the first time you open the app, in about a minute. Keep the app open meanwhile. Reinstall if it has problems or after an update. The keyboard needs Allow Full Access to read it.", "辞書は初回起動時にこの iPhone 上で作成されます（約 1 分）。その間アプリを閉じないでください。不具合や更新のあとは再インストールしてください。キーボードが辞書を読むには「フルアクセスを許可」が必要です。"))
            }
        }
        .navigationTitle(L("拼音词库", "Pinyin dictionary", "ピンイン辞書"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deployer.state) {
            size = await Task.detached { RimeDeployer.diskSize() }.value
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let date = RimeDeployer.deployedAt, !deployer.needsDeploy {
            parts.append(L("\(Loc.monthDay(date)) 部署", "Installed \(Loc.monthDay(date))", "\(Loc.monthDay(date))にインストール"))
        }
        if let size, size > 0 {
            parts.append(L("约 ", "About ", "約 ") + ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? L("万象拼音词库，CC BY 4.0", "Wanxiang Pinyin, CC BY 4.0", "万象ピンイン、CC BY 4.0") : parts.joined(separator: " · ")
    }
}

// MARK: - 隐私、关于

struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Text(L("打字和拼音候选全部在手机上完成，不联网。", "Typing and pinyin candidates happen entirely on your iPhone, offline.", "入力とピンインの候補はすべて iPhone 上で処理され、通信しません。"))
                Text(L("只有点「✨ 润色」或「再润」时，输入框里的文字和你写的要求才会发给你自己配置的模型接口，Enclave 没有自己的服务器。", "Only when you tap ✨ Polish or Rewrite are the text in the field and your prompt sent to the model API you set up. Enclave has no servers of its own.", "「✨ 整える」か「別の案」をタップしたときだけ、入力欄の文章と指示が自分で設定したモデル API に送られます。Enclave は独自のサーバーを持ちません。"))
                Text(L("API Key 只存在本机钥匙串里。", "Your API key stays in this iPhone's keychain.", "API キーはこの iPhone のキーチェーンにだけ保存されます。"))
                Text(L("「允许完全访问」只用来联网调用模型、按键震动，以及和 App 共享设置。", "Allow Full Access is used only to reach your model, for haptics, and to share settings with the app.", "「フルアクセスを許可」は、モデルとの通信、触覚、アプリとの設定共有にだけ使います。"))
            }
            .font(.subheadline)
        }
        .navigationTitle(L("隐私", "Privacy", "プライバシー"))
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
                HStack { Text(L("版本", "Version", "バージョン")); Spacer(); Text(Self.version).foregroundStyle(.secondary) }
            }
            LicensesSection()
        }
        .navigationTitle(L("关于 Enclave", "About Enclave", "Enclave について"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 语言（L2）：跟随 iPhone / 简体中文 / English / 日本語，选完马上生效；下面一组说明会改哪些。
struct LanguageView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button { router.language = language } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.nativeName).foregroundStyle(.primary)
                                if language == .system {
                                    Text(L("现在是\(Loc.system.nativeName)", "Currently \(Loc.system.nativeName)",
                                           "現在は\(Loc.system.nativeName)"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if router.language == language {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color(hex: 0x5B4BE8))
                            }
                        }
                    }
                }
            }
            Section(L("会改哪些", "What changes", "変わるもの")) {
                LabeledContent(L("App 界面、键盘里的 AI 文字", "App and keyboard AI text", "アプリとキーボードの AI 表示"),
                               value: L("跟这里一致", "Follow this setting", "この設定に合わせる"))
                LabeledContent(L("拼音按键", "Pinyin keys", "ピンインのキー"), value: L("一直是中文", "Always Chinese", "常に中国語"))
                LabeledContent(L("润色结果", "Polish results", "整えた結果"), value: L("不受影响", "Not affected", "影響なし"))
            }
        }
        .navigationTitle(L("语言", "Language", "言語"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
