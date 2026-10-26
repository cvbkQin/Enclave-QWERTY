import StoreKit
import SwiftUI
import UIKit

/// 设置顶部的 AI 卡（PB3）：试用剩几天和进度格、解锁按钮、一句说明。点整张卡进解锁页。
struct EnclaveAICard: View {
    @ObservedObject private var unlock = UnlockStore.shared

    var body: some View {
        DashCard {
            // 备案口径是开发者不提供模型服务，卡片标题只写「AI」。
            DashCardHeader(icon: "sparkles", title: "AI", color: DashColor.ai, note: state)
            HStack(alignment: .center) {
                big
                Spacer(minLength: 8)
                if !unlocked {
                    Text(unlock.unlockTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(DashColor.ai))
                }
            }
            if case .trial(let days, _) = unlock.access {
                // 14 天试用画成 7 格，一格两天。
                DashSegments(total: 7, done: Int((Double(days) / 2).rounded(.up)))
            }
            Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unlocked: Bool {
        if case .unlocked = unlock.access { return true }
        return false
    }

    private var state: String {
        switch unlock.access {
        case .trial: return L("试用中", "Trial", "無料体験中")
        case .expired: return L("试用已结束", "Trial ended", "無料体験終了")
        case .unlocked: return L("已解锁", "Unlocked", "購入済み")
        }
    }

    @ViewBuilder
    private var big: some View {
        switch unlock.access {
        case .trial(let days, _): DashBigNumber(value: "\(days)", unit: L("天 · 试用剩余", "days left", "日・残り"))
        case .expired: DashBigNumber(value: "\(AIAccess.usesLeftToday)", unit: L("次 · 今天还剩", "left today", "回・今日の残り"))
        case .unlocked: DashBigNumber(value: "∞", unit: L("不限次数", "No limits", "回数無制限"))
        }
    }

    private var detail: String {
        let uses = AIAccess.dailyFreeUses
        switch unlock.access {
        case .trial(_, let ends):
            return L("\(Loc.monthDay(ends))结束，之后每天免费 \(uses) 次。一次买断，不限次数。", "Ends \(Loc.monthDay(ends)), then \(uses) free a day. One-time purchase, no limits.", "\(Loc.monthDay(ends))に終了し、その後は 1 日 \(uses) 回無料。買い切りで回数無制限。")
        case .expired:
            return L("每天免费 \(uses) 次，明天 0 点恢复。一次买断，不限次数。", "\(uses) free a day, reset at midnight. One-time purchase, no limits.", "1 日 \(uses) 回無料、0 時にリセット。買い切りで回数無制限。")
        case .unlocked:
            return L("一次买断，不限次数。谢谢支持。", "One-time purchase, no limits. Thank you.", "買い切りで回数無制限。ありがとうございます。")
        }
    }
}

/// 设置（PB3）：AI 卡；语言、日间 / 夜间、拼音词库；开启键盘指南、使用指引；隐私、关于。
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var deployer = RimeDeployer.shared

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            List {
                Section {
                } header: {
                    VStack(spacing: 12) {
                        TabTitle(caption: "\(L("飞地输入法", "Enclave", "Enclave")) \(AboutView.version)", title: L("设置", "Settings", "設定"))
                        // 整张卡可点，不要列表行的箭头。
                        Button { router.settingsPath.append(.unlock) } label: { EnclaveAICard() }
                            .buttonStyle(.plain)
                    }
                    .dashFormCard()
                }
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.language) {
                        DashRow(icon: "globe", color: DashColor.input, title: L("语言", "Language", "言語"),
                                value: router.language == .system ? L("跟随 iPhone", "iPhone", "iPhone に従う") : router.language.nativeName)
                    }
                    Picker(selection: $store.settings.appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    } label: {
                        DashRow(icon: "circle.lefthalf.filled", color: DashColor.input, title: L("日间 / 夜间", "Appearance", "外観"))
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text(L("只改飞地输入法 App。键盘跟着正在打字的 App 变深浅，和系统键盘一样。", "Applies to the Enclave app. The keyboard matches the app you are typing in, like the system keyboard.", "Enclave App に適用されます。キーボードは入力中の App に合わせて変わります。"))
                }
                // 键盘、拼音词库和常用词从首页进。
                Section {
                    NavigationLink(value: AppRouter.SettingsPage.guide) {
                        DashRow(icon: "questionmark.circle", color: DashColor.ai, title: L("开启键盘指南", "Keyboard setup guide", "キーボードの設定ガイド"))
                    }
                    NavigationLink(value: AppRouter.SettingsPage.playground) {
                        DashRow(icon: "flask", color: DashColor.ai, title: L("使用指引", "Guide", "使い方ガイド"),
                                value: L("试过 \(LabScene.triedCount)/\(LabScene.all.count)", "Tried \(LabScene.triedCount)/\(LabScene.all.count)", "\(LabScene.triedCount)/\(LabScene.all.count) 試した"))
                    }
                }
                Section {
                    if SharedStorage.usesClipboardConfig {
                    DashRow(icon: "link", color: DashColor.system, title: L("App 与键盘共享配置", "Shared with keyboard", "キーボードと設定を共有"),
                            value: SharedStorage.isShared ? L("已开启", "On", "オン") : L("不可用", "Unavailable", "利用不可"))
                    if !SharedStorage.isShared { SharedConfigBanner().listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
                    }
                    NavigationLink(value: AppRouter.SettingsPage.privacy) {
                        DashRow(icon: "lock", color: DashColor.system, title: L("隐私", "Privacy", "プライバシー"),
                                value: router.privacyAgreed ? L("已同意", "Agreed", "同意済み") : L("未同意", "Not agreed", "未同意"))
                    }
                    NavigationLink(value: AppRouter.SettingsPage.about) {
                        DashRow(icon: "info.circle", color: DashColor.system, title: L("关于飞地输入法", "About Enclave", "Enclave について"), value: AboutView.version)
                    }
                }
            }
            .navigationTitle(L("设置", "Settings", "設定"))
            .tabRootPage()
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
                case .privacyPolicy: PrivacyPolicyView()
                case .licenses: LicensesView()
                }
            }
        }
    }
}

// MARK: - 模型接口

/// 首页「接口」小卡上的服务商名字：认得出的写服务商，自定义的写地址里的主机名。
enum ProviderName {
    static func of(_ baseURL: String) -> String {
        let provider = Provider.detect(baseURL)
        guard provider == .custom else { return provider.title }
        return URL(string: baseURL)?.host ?? provider.title
    }
}

/// 常用服务商，选了自动填地址和模型。
/// 中国大陆店面不列 OpenAI（没有在国内备案），换成已备案的通义千问；其他地区不变。
enum Provider: CaseIterable, Identifiable {
    case deepseek, openai, qwen, ollama, custom

    /// 服务商卡片按这个顺序排，2×2。
    static var shown: [Provider] {
        Storefront.isMainlandChina ? [.deepseek, .qwen, .ollama, .custom] : [.deepseek, .openai, .ollama, .custom]
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .qwen: return L("通义千问", "Qwen", "Qwen")
        case .ollama: return "Ollama"
        case .custom: return L("自定义", "Custom", "カスタム")
        }
    }

    var subtitle: String {
        switch self {
        case .deepseek: return "api.deepseek.com"
        case .openai: return "api.openai.com"
        case .qwen: return "dashscope.aliyuncs.com"
        case .ollama: return L("局域网的电脑", "A computer on your network", "ローカルネットのPC")
        case .custom: return "vLLM、LM Studio"
        }
    }

    var preset: (baseURL: String, model: String)? {
        switch self {
        case .deepseek: return ("https://api.deepseek.com/v1", "deepseek-flash")
        case .openai: return ("https://api.openai.com/v1", "gpt-4o-mini")
        case .qwen: return ("https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus")
        case .ollama: return ("http://192.168.1.100:11434/v1", "qwen2.5:7b")
        case .custom: return nil
        }
    }

    static func detect(_ baseURL: String) -> Provider {
        if baseURL.contains("api.deepseek.com") { return .deepseek }
        if baseURL.contains("api.openai.com") { return .openai }
        if baseURL.contains("dashscope.aliyuncs.com") { return .qwen }
        if baseURL.contains(":11434") { return .ollama }
        return .custom
    }
}

struct ModelSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    /// 没同意隐私政策时点「测试」：和键盘里的锁卡片一样，先去同意。
    @State private var needsPrivacy = false
    @State private var provider: Provider = .custom
    @State private var importResult: Bool?
    @State private var recent: [UsageStats.Request] = []
    /// 测试连接成功、这个地址还没同意过时弹出的确认（P05）。
    @State private var consentEndpoint: ConsentPrompt?

    private struct ConsentPrompt: Identifiable {
        let endpoint: String
        var id: String { endpoint }
    }

    var body: some View {
        Form {
            Section {
            } header: {
                VStack(spacing: 12) {
                    TabTitle(caption: apiCaption, title: L("接口", "API", "API"))
                    statusCard
                }
                .dashFormCard()
            }
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("服务商", "Provider", "サービス"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Provider.shown) { item in
                            ProviderCard(provider: item, selected: provider == item) { choose(item) }
                        }
                    }
                }
                .dashFormCard()
            }
            Section {
                LabeledField(title: L("API 地址", "API URL", "API の URL"), text: $store.settings.baseURL, placeholder: "https://api.deepseek.com/v1", keyboard: .URL)
                LabeledField(title: L("模型", "Model", "モデル"), text: $store.settings.model, placeholder: "deepseek-flash")
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
            if SharedStorage.usesClipboardConfig {
                Section {
                    Button(importResult == false ? L("剪贴板里没有飞地输入法配置", "No Enclave settings on the clipboard", "クリップボードに Enclave の設定がありません") : importResult == true ? L("已导入", "Imported", "読み込みました") : L("从剪贴板导入配置", "Import settings from clipboard", "クリップボードから設定を読み込む")) {
                        importConfig()
                    }
                    .font(.footnote)
                    .foregroundStyle(importResult == false ? Color.orange : AppColor.purple)
                }
            }
        }
        .navigationTitle(L("接口", "API", "API"))
        .tabRootPage()
        .alert(L("用 AI 之前，先同意隐私政策", "Agree to the Privacy Policy to use AI", "AI を使う前にプライバシーポリシーに同意してください"), isPresented: $needsPrivacy) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("阅读并同意", "Read and Agree", "読んで同意する")) { router.showsPrivacyWelcome = true }
        } message: {
            Text(L("同意后才能测试接口和使用 AI。拼音输入不受影响。", "Agree first to test the API and use AI. Pinyin input still works.", "同意すると API のテストと AI が使えます。ピンイン入力はそのまま使えます。"))
        }
        .onAppear {
            provider = Provider.detect(store.settings.baseURL)
            recent = UsageStats.polishRecent
        }
        .onChange(of: store.test) { _ in recent = UsageStats.polishRecent }
        .onChange(of: store.test) { test in
            guard case .success = test, let endpoint = ConsentStore.endpoint(of: store.settings.baseURL),
                  !ConsentStore.isConsented(endpoint) else { return }
            consentEndpoint = ConsentPrompt(endpoint: endpoint)
        }
        .sheet(item: $consentEndpoint) { prompt in
            ConsentSheet(provider: Provider.detect(store.settings.baseURL).title, endpoint: prompt.endpoint) {
                ConsentStore.grant(prompt.endpoint)
                consentEndpoint = nil
            } later: {
                consentEndpoint = nil
            }
            .presentationDetents([.large])
        }
    }

    /// 顶部状态卡（PB2）：连接状态、最近一次耗时、「测试」，最近 10 次请求的小曲线。
    /// 标题上的灰字：「DeepSeek · deepseek-flash」，没配好时「还没设置」。
    private var apiCaption: String {
        guard store.settings.isConfigured else { return L("还没设置", "Not set up", "未設定") }
        return ProviderName.of(store.settings.baseURL) + " · " + store.settings.model
    }

    private var statusCard: some View {
        DashCard {
            HStack(spacing: 6) {
                Circle().fill(status.color).frame(width: 7, height: 7)
                Text(status.text).font(.subheadline.weight(.semibold)).foregroundStyle(status.color).lineLimit(2)
                Spacer(minLength: 8)
            }
            HStack(alignment: .firstTextBaseline) {
                if let seconds = lastSeconds {
                    DashBigNumber(value: String(format: "%.1f", seconds),
                                  unit: lastFailed ? L("秒 · 最近一次失败", "s · last request failed", "秒・直近は失敗") : L("秒 · 最近一次", "s · last request", "秒・直近"))
                        .foregroundStyle(lastFailed ? Color.secondary : Color.primary)
                } else {
                    DashBigNumber(value: "–", unit: L("还没有请求", "No requests yet", "リクエストなし"))
                }
                Spacer(minLength: 8)
                Button {
                    if router.privacyAgreed {
                        Task { await store.runTest() }
                    } else {
                        needsPrivacy = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if store.test == .running { ProgressView().controlSize(.small) }
                        Text(L("测试", "Test", "テスト"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashColor.ai)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(DashColor.ai.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(!store.settings.isConfigured || store.test == .running)
            }
            DashSparkline(values: recent.map { Double($0.ms) }, color: recent.allSatisfy(\.ok) ? DashColor.ok : .orange)
            Text(recentSummary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    /// 测试刚失败时显示错误；否则看最近一次请求，再不然看上次测试。
    private var status: (text: String, color: Color) {
        guard store.settings.isConfigured else { return (L("还没配置，先选服务商、填地址", "Not set up. Pick a provider and fill in the URL", "未設定です。サービスを選んで URL を入力してください"), DashColor.system) }
        switch store.test {
        case .running: return (L("正在测试…", "Testing…", "テスト中…"), .orange)
        case .failure(let message): return (message, .red)
        case .success: return (L("已连接", "Connected", "接続済み"), DashColor.ok)
        case .idle: break
        }
        if let last = recent.last { return last.ok ? (L("已连接", "Connected", "接続済み"), DashColor.ok) : (L("最近一次请求失败", "Last request failed", "直近のリクエストは失敗"), .red) }
        switch store.lastTestOK {
        case true?: return (L("已连接", "Connected", "接続済み"), DashColor.ok)
        case false?: return (L("连不上", "Can't connect", "接続できません"), .red)
        case nil: return (L("还没测试", "Not tested", "未テスト"), DashColor.system)
        }
    }

    /// 最近一次（测试或请求）失败：大数字变灰，单位写「失败」。
    private var lastFailed: Bool {
        if case .failure = store.test { return true }
        if case .success = store.test { return false }
        return recent.last.map { !$0.ok } ?? false
    }

    private var lastSeconds: Double? {
        if case .success(_, let seconds) = store.test { return seconds }
        return recent.last.map { Double($0.ms) / 1000 }
    }

    private var recentSummary: String {
        let model = store.settings.model
        guard !recent.isEmpty else { return L("点「测试」或在键盘上点 ✨，这里会画出最近 10 次请求的耗时。", "Tap Test or ✨ on the keyboard to chart your last 10 requests.", "「テスト」かキーボードの ✨ で、直近 10 回のリクエスト時間がここに表示されます。") }
        let failed = recent.filter { !$0.ok }.count
        let head = failed == 0
            ? L("最近 \(recent.count) 次请求都成功", "Last \(recent.count) requests succeeded", "直近 \(recent.count) 回すべて成功")
            : L("最近 \(recent.count) 次请求有 \(failed) 次失败", "\(failed) of the last \(recent.count) requests failed", "直近 \(recent.count) 回中 \(failed) 回失敗")
        return model.isEmpty ? head : head + " · " + model
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

/// 服务商卡片：名字和地址，选中的描紫边、右上打勾。
private struct ProviderCard: View {
    var provider: Provider
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(provider.title).font(.body.weight(.semibold))
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(DashColor.ai) }
                }
                Text(provider.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DashColor.ai, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
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
            // B 卡片放在 Section 的 header 里，分组的大圆角裁不到，四角完整（见 dashFormCard）。
            if KeyboardStatus.fullAccess == false {
                Section {
                } header: {
                    NotSyncedBanner().dashFormCard()
                }
            }
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("中文布局", "Chinese layout", "中国語の配列"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                    HStack(spacing: 12) {
                        ForEach([KeyboardLayout.nineKey, .qwerty]) { layout in
                            LayoutCard(layout: layout, selected: store.settings.keyboardLayout == layout) {
                                store.settings.keyboardLayout = layout
                            }
                        }
                    }
                }
                .dashFormCard()
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
                PredictionToggle()
            }
            TouchCalibrationSection(layout: store.settings.keyboardLayout)
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
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                NotSyncedBanner()
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
    @State private var typingStats: TypingStats.Summary?
    @ObservedObject private var grammar = GrammarDownloader.shared
    @State private var confirmDeleteGrammar = false

    var body: some View {
        DashPage {
            dictionaryCard
            grammarCard
            speedCard
        }
        .navigationTitle(L("拼音词库", "Pinyin dictionary", "ピンイン辞書"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deployer.state) {
            size = await Task.detached { RimeDeployer.diskSize() }.value
        }
        .onAppear {
            typingStats = TypingStats.summary
            grammar.refresh()
        }
        .confirmationDialog(L("删除整句模型？", "Delete the sentence model?", "文章モデルを削除しますか？"), isPresented: $confirmDeleteGrammar, titleVisibility: .visible) {
            Button(L("删除", "Delete", "削除"), role: .destructive) { grammar.delete() }
        }
    }

    // MARK: - 万象拼音

    private var dictionaryCard: some View {
        let status = PinyinStatus.current(deployer)
        return DashCard {
            DashCardHeader(icon: "character.book.closed", title: L("万象拼音", "Wanxiang Pinyin", "万象ピンイン"), color: DashColor.input)
            VStack(alignment: .leading, spacing: 8) {
                Text("● " + status.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(status.color)
                Text(L("在本机编译，键盘要开「允许完全访问」才能读到。", "Built on this iPhone. The keyboard needs Allow Full Access to read it.", "この iPhone 上で作成します。キーボードが読むには「フルアクセスを許可」が必要です。"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                if case .failed(let message) = deployer.state {
                    Text(message).font(.system(size: 13)).foregroundStyle(.red)
                }
                HStack(spacing: 8) {
                    Button(deployer.state == .deploying ? L("正在部署…", "Installing…", "インストール中…") : L("重新部署词库", "Reinstall dictionary", "辞書を再インストール")) { deployer.deploy() }
                        .font(.system(size: 15, weight: .semibold))
                        .disabled(deployer.state == .deploying)
                    if deployer.state == .deploying { ProgressView() }
                }
            }
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
        if !store.settings.fuzzyPinyin.isEmpty {
            parts.append(L("模糊拼音 \(store.settings.fuzzyPinyin.count) 组", "\(store.settings.fuzzyPinyin.count) fuzzy pairs", "あいまい入力 \(store.settings.fuzzyPinyin.count) 組"))
        }
        return parts.isEmpty ? L("万象拼音词库，CC BY 4.0", "Wanxiang Pinyin, CC BY 4.0", "万象ピンイン、CC BY 4.0") : parts.joined(separator: " · ")
    }

    // MARK: - 整句模型

    /// 下载后整句首选更准。下载中大数字是进度，下完是大小。
    private var grammarCard: some View {
        DashCard {
            DashCardHeader(icon: "sparkles", title: L("整句模型", "Sentence model", "文章モデル"), color: DashColor.input, note: "CC BY 4.0")
            VStack(alignment: .leading, spacing: 10) {
                switch grammar.state {
                case .downloading(let received, let expected):
                    DashBigNumber(value: "\(Int(Double(received) / Double(max(expected, 1)) * 100))",
                                    unit: L("% · 正在下载", "% · Downloading", "% · ダウンロード中"))
                    ProgressView(value: Double(received), total: Double(max(expected, 1)))
                    Button(L("取消", "Cancel", "キャンセル")) { grammar.cancel() }
                        .font(.system(size: 15, weight: .semibold))
                default:
                    if grammar.installed {
                        DashBigNumber(value: GrammarModel.installedSize.map { "\($0 / 1_000_000)" } ?? "–",
                                        unit: grammar.enabled ? L("MB · 已下载", "MB · Downloaded", "MB · ダウンロード済み") : L("MB · 已下载 · 已关闭", "MB · Downloaded · Off", "MB · ダウンロード済み · オフ"))
                        // 关掉时模型留着，随时再打开，方便对比。切换后重新部署词库。
                        Toggle(L("使用整句模型", "Use sentence model", "文章モデルを使う"),
                               isOn: Binding(get: { grammar.enabled }, set: { grammar.setEnabled($0) }))
                            .tint(AppColor.purple)
                            .disabled(deployer.state == .deploying)
                        Text(L("长句一次打对的更多，键盘内存会多用一些。", "Whole sentences come out right more often; the keyboard uses a little more memory.", "長い文が一度で正しく出やすくなります。キーボードのメモリ使用は少し増えます。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button(L("删除模型", "Delete model", "モデルを削除"), role: .destructive) { confirmDeleteGrammar = true }
                            .font(.system(size: 13, weight: .semibold))
                            .disabled(deployer.state == .deploying)
                    } else {
                        DashBigNumber(value: "380", unit: L("MB · 未下载", "MB · Not downloaded", "MB · 未ダウンロード"))
                        Text(L("按词和词常在一起出现的统计挑出最通顺的整句，整句打完首选更准。完全在本机运行，不联网。从万象的 GitHub 下载，下载时不要退出 App。",
                               "Picks the most natural sentence from statistics of which words go together, so whole sentences come out right more often. Runs fully on this iPhone, offline. Downloaded from Wanxiang's GitHub; keep the app open meanwhile.",
                               "語と語のつながりの統計から自然な文を選ぶので、文をまとめて入力したときの第一候補が正確になります。すべて端末内で動作し、通信しません。万象の GitHub からダウンロードします。完了まで App を閉じないでください。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button(L("下载", "Download", "ダウンロード")) { grammar.download() }
                            .font(.system(size: 15, weight: .semibold))
                            .disabled(deployer.state == .deploying)
                    }
                }
                if case .failed(let message) = grammar.state {
                    Text(message).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - 打字速度

    private var speedCard: some View {
        DashCard {
            DashCardHeader(icon: "keyboard", title: L("打字速度", "Typing speed", "入力の速さ"), color: DashColor.input,
                           note: typingStats.map { L("最近 \($0.count) 个按键", "Last \($0.count) keys", "直近 \($0.count) キー") })
            if let stats = typingStats {
                VStack(alignment: .leading, spacing: 12) {
                    let smooth = stats.medianTotal <= 30
                    HStack(alignment: .firstTextBaseline) {
                        DashBigNumber(value: String(format: "%.0f", stats.medianTotal), unit: L("毫秒 · 一般", "ms · typical", "ミリ秒 · 通常"))
                        Spacer()
                        Text(smooth ? L("感觉不到卡", "Feels instant", "遅れを感じない") : L("有点卡", "A bit slow", "少し遅い"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(smooth ? DashColor.ok : Color.orange)
                    }
                    LatencyScale(typical: stats.medianTotal, slow: stats.slowTotal, slowest: stats.slowestTotal)
                    HStack(alignment: .top) {
                        TypingSmallStat(value: Self.milliseconds(stats.medianEngine), label: L("其中拼音引擎", "Pinyin engine", "うちエンジン"))
                        if let memory = stats.memoryWithModel ?? stats.memory {
                            TypingSmallStat(value: String(format: "%.0f/%.0f", memory.median, memory.peak),
                                            label: L("内存 MB 一般/最高", "Memory MB typ/peak", "メモリ MB 通常/最大"))
                        }
                        TypingSmallStat(value: "\(stats.memoryWarnings)", label: L("内存警告", "Memory warnings", "メモリ警告"))
                    }
                    HStack(spacing: 4) {
                        Text(L("从手指离开按键到候选出来。30 毫秒以内基本感觉不到。", "From lifting your finger to candidates shown. Under 30 ms feels instant.", "指を離してから候補が出るまで。30 ミリ秒以内ならほぼ感じません。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button(L("清空记录", "Clear", "記録を消去")) {
                            TypingStats.clear()
                            typingStats = nil
                        }
                        .font(.system(size: 13, weight: .semibold))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    DashBigNumber(value: "0", unit: L("个按键", "keys", "キー"))
                    Text(L("用飞地输入法打几个拼音，这里就有数据了。键盘要开「允许完全访问」才记得下。", "Type some pinyin with the Enclave keyboard and your stats show up here. The keyboard needs Allow Full Access to record them.", "Enclave キーボードでピンインを入力すると、ここに記録が表示されます。「フルアクセスを許可」が必要です。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func milliseconds(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }
}

/// 从绿到红的刻度条，标出一般、较慢 10%、最慢三个位置。刻度到 100ms，更慢的贴着最右边。
private struct LatencyScale: View {
    var typical: Double
    var slow: Double
    var slowest: Double
    private let maxValue = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [DashColor.ok, .yellow, Color.orange, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle().fill(Color.primary).frame(width: 2, height: 16)
                            .offset(x: position([typical, slow, slowest][index], width) - 1)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            // 三个值常挤在一起，标签不贴着刻度，排成一行写在下面。
            HStack(spacing: 12) {
                legend(L("一般", "Typical", "通常"), typical)
                legend(L("较慢 10%", "Slow 10%", "遅い10%"), slow)
                legend(L("最慢", "Slowest", "最大"), slowest)
            }
        }
    }

    private func position(_ value: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max(value / maxValue, 0), 1)) * width
    }

    private func legend(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(String(format: "%.0f ms", value)).fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
    }
}

// MARK: - 隐私、关于

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


/// 保存接口时的确认（P05）：「同意」记下这个地址，键盘里第一次润色就不再问；「暂不」什么都不记。
private struct ConsentSheet: View {
    let provider: String
    let endpoint: String
    let agree: () -> Void
    let later: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x5B4BE8))
                    .padding(.top, 28)
                Text(L("允许把文字发送到这个接口？", "Allow sending text to this API?", "この API に文章を送信しますか？"))
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                VStack(spacing: 0) {
                    row(L("服务商", "Provider", "サービス"), provider)
                    Divider().padding(.leading, 14)
                    row(L("地址", "Address", "アドレス"), endpoint, mono: true)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                VStack(alignment: .leading, spacing: 14) {
                    point("text.alignleft", L("发送什么", "What's sent", "送るもの"),
                          L("只在你点「润色」或「再润」时，发送输入框里的文字（选中时只发选中的部分）和你写的要求。",
                            "Only when you tap Polish or Rewrite: the text in the field (just the selection, if any) and your prompt.",
                            "「整える」か「別の案」をタップしたときだけ、入力欄の文章（選択時はその部分だけ）と指示を送ります。"))
                    point("arrow.up.forward", L("发到哪里", "Where it goes", "送り先"),
                          L("直接发到上面这个地址，由服务商按它的隐私政策处理。", "Straight to the address above, handled under the provider's privacy policy.",
                            "上のアドレスに直接送られ、サービスのプライバシーポリシーに従って処理されます。"))
                    point("lock.shield", L("飞地输入法不经手", "Enclave never sees it", "Enclave は関与しません"),
                          L("飞地输入法没有自己的服务器，不收集、不保存你的文字。", "Enclave has no servers and doesn't collect or keep your text.",
                            "Enclave はサーバーを持たず、文章を収集・保存しません。"))
                }
                Button(action: agree) {
                    Text(L("同意", "Allow", "同意する"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x5B4BE8)))
                }
                .buttonStyle(.plain)
                Button(L("暂不", "Not now", "今はしない"), action: later)
                    .font(.system(size: 16))
                Text(L("可以随时在「设置 › 隐私」撤回", "You can withdraw anytime in Settings › Privacy", "「設定 › プライバシー」でいつでも撤回できます"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(mono ? .system(.subheadline, design: .monospaced) : .subheadline).lineLimit(1).truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x4A3BD6))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(hex: 0xECEAFD)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
