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
                        // 测过并且失败时 AI 这一步不算完成，和设置向导页一致。
                        let left = Readiness.remainingSteps(apiConfigured: store.settings.isConfigured && store.lastTestOK != false)
                        HStack(spacing: 12) {
                            DashRow(icon: "questionmark.circle", color: DashColor.ai, title: L("设置向导", "Setup guide", "設定ガイド"))
                            Text(left == 0 ? L("已完成", "Done", "完了") : L("还差 \(left) 步", "\(left) left", "あと \(left) ステップ"))
                                .foregroundStyle(left == 0 ? Color.secondary : Color(hex: 0xD97706))
                                .lineLimit(1)
                        }
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
                case .guide: SetupWizardView()
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
/// 所有地区都列 DeepSeek、Kimi、通义千问，加上跑在自己电脑上的 Ollama（0.86 起，原来只有中国大陆店面这样）；
/// 没有「自定义」卡片，自己改了地址或模型就四个都不选中，算自定义。OpenAI 和自定义只留着认旧设置的地址。
enum Provider: CaseIterable, Identifiable {
    case deepseek, openai, kimi, qwen, glm, ollama, custom

    /// 服务商卡片按这个顺序排，2×2。
    static let shown: [Provider] = [.deepseek, .kimi, .qwen, .ollama]
    /// 问答页的服务商：前三家能联网（千问、Kimi、智谱），DeepSeek 不能联网。都是国内已备案的服务商。
    static let answerShown: [Provider] = [.qwen, .kimi, .glm, .deepseek]
    /// 引导里选服务商（TU0）：前四家有分步教程，Ollama、其他直接去接口页。
    static let guideShown: [Provider] = [.deepseek, .kimi, .qwen, .glm, .ollama, .custom]

    /// 现在填的地址和模型对得上哪个预设：地址和模型都和预设一样才算；Ollama 只认 11434 端口（IP 本来就要改）。
    /// 对不上时返回 nil（四个都不选中）。answer：按问答页的预设比（Kimi 问答用 K3）。
    static func matching(baseURL: String, model: String, answer: Bool = false) -> Provider? {
        func trimmed(_ text: String) -> String {
            var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            while text.hasSuffix("/") { text.removeLast() }
            return text
        }
        let found = (answer ? answerShown : shown).first { provider in
            if provider == .ollama { return baseURL.contains(":11434") }
            guard let preset = answer ? provider.answerPreset : provider.preset else { return false }
            // Kimi、千问、智谱的国内、国际两个地址都算（两边的 Key 不通用）。
            let urls = provider == .kimi ? [Provider.kimiChina, Provider.kimiGlobal]
                : provider == .qwen ? [Provider.qwenChina, Provider.qwenGlobal]
                : provider == .glm ? [Provider.glmChina, Provider.glmGlobal] : [preset.baseURL]
            return urls.contains(trimmed(baseURL)) && trimmed(model) == preset.model
        }
        return found
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .kimi: return "Kimi"
        case .qwen: return L("通义千问", "Qwen", "Qwen")
        case .glm: return L("智谱 GLM", "Zhipu GLM", "Zhipu GLM")
        case .ollama: return "Ollama"
        case .custom: return L("自定义", "Custom", "カスタム")
        }
    }

    /// 卡片上名字下面的灰字（AP1、AP2）。
    var subtitle: String {
        switch self {
        case .deepseek: return "api.deepseek.com"
        case .openai: return "api.openai.com"
        case .kimi: return L("月之暗面开放平台", "Moonshot AI platform", "Moonshot AI プラットフォーム")
        case .qwen: return L("阿里云百炼", "Alibaba Cloud Model Studio", "Alibaba Cloud Model Studio")
        case .glm: return L("智谱开放平台", "Z.ai platform", "Z.ai プラットフォーム")
        case .ollama: return L("自己电脑上", "Your own computer", "自分のパソコン")
        case .custom: return "vLLM、LM Studio"
        }
    }

    /// Kimi 国内站（platform.moonshot.cn）和国际站（platform.moonshot.ai）的 Key 不通用：大陆店面填 .cn，其他地区填 .ai。
    static let kimiChina = "https://api.moonshot.cn/v1"
    static let kimiGlobal = "https://api.moonshot.ai/v1"
    /// Kimi 预设：润色用高速版（能力一样、快 2～3 倍），单独设问答接口时问答用 K3。
    static let kimiAnswerModel = "kimi-k3.1-pro"
    /// 千问（阿里云百炼）同样分国内站和国际站（新加坡）。
    static let qwenChina = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    static let qwenGlobal = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    /// 智谱：国内开放平台（open.bigmodel.cn）和国际站 Z.ai。
    static let glmChina = "https://open.bigmodel.cn/api/paas/v4"
    static let glmGlobal = "https://api.z.ai/api/paas/v4"

    var preset: (baseURL: String, model: String)? {
        switch self {
        case .deepseek: return ("https://api.deepseek.com/v1", "deepseek-flash")
        case .openai: return ("https://api.openai.com/v1", "gpt-4o-mini")
        case .kimi: return (Storefront.isMainlandChina ? Self.kimiChina : Self.kimiGlobal, "kimi-k3.1-pro-highspeed")
        case .qwen: return (Storefront.isMainlandChina ? Self.qwenChina : Self.qwenGlobal, "qwen-plus")
        case .glm: return (Storefront.isMainlandChina ? Self.glmChina : Self.glmGlobal, "glm-5.3")
        case .ollama: return ("http://192.168.1.100:11434/v1", "qwen2.5:7b")
        case .custom: return nil
        }
    }

    /// 问答页的预设：Kimi 用 K3（润色的预设是更快的高速版），别的和润色一样。千问 qwen-plus 支持联网。
    var answerPreset: (baseURL: String, model: String)? {
        guard let preset else { return nil }
        return self == .kimi ? (preset.baseURL, Self.kimiAnswerModel) : preset
    }

    /// 问答能联网（千问、Kimi、智谱）。
    var canSearch: Bool { self == .kimi || self == .qwen || self == .glm }

    /// 选这个服务商时最大输出填多少（Kimi K3、智谱会先思考，思考也算在里面）。
    var maxTokens: Int { self == .kimi || self == .glm ? 4096 : EnclaveSettings().maxTokens }

    static func detect(_ baseURL: String) -> Provider {
        if baseURL.contains("api.deepseek.com") { return .deepseek }
        if baseURL.contains("api.openai.com") { return .openai }
        if baseURL.contains("api.moonshot.cn") || baseURL.contains("api.moonshot.ai") { return .kimi }
        if baseURL.contains("dashscope.aliyuncs.com") || baseURL.contains("dashscope-intl.aliyuncs.com") { return .qwen }
        if baseURL.contains("bigmodel.cn") || baseURL.contains("api.z.ai") { return .glm }
        if baseURL.contains(":11434") { return .ollama }
        return .custom
    }
}

/// 接口页（AP1–AP5）：顶上分段「改写 · 润色 | 问答」，两页各自一张状态卡；两页都有「我的预设」。
/// 改写页：状态卡 → 我的预设 → 服务商（DeepSeek、Kimi、千问、Ollama）→ 连接（地址 / 模型 / Key / 生成参数）。
/// 问答页：状态卡 →「和改写用同一个接口」→ 我的预设 → 服务商（千问、Kimi、智谱可联网，DeepSeek 不联网）→ 连接 → 联网调用。
struct ModelSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    /// 没同意隐私政策时点「测试」：和键盘里的锁卡片一样，先去同意。
    @State private var needsPrivacy = false
    @State private var importResult: Bool?
    @State private var recent: [UsageStats.Request] = []
    @State private var answerRecent: [UsageStats.Request] = []
    /// 记住上次停的那页。
    @AppStorage("apiPage") private var pageRaw = APIPage.main.rawValue
    /// 大陆店面从「禁止」改成「开 / 每次询问」前的确认框（AP4）：选的那一档。
    @State private var pendingWebMode: WebSearchMode?
    /// 测试连接成功、这个地址还没同意过时弹出的确认（P05）。
    @State private var consentEndpoint: ConsentPrompt?
    /// 「存为预设」弹框（AP5）。
    @State private var savingPreset = false
    @State private var presetName = ""
    /// 点了预设、当前配置还没存：先问一次。
    @State private var pendingPreset: SavedAPI?
    @State private var duplicateName: String?
    @State private var renaming: SavedAPI?
    @State private var renameText = ""

    private enum APIPage: String { case main, answer }

    private struct ConsentPrompt: Identifiable {
        let endpoint: String
        var id: String { endpoint }
    }

    private var page: APIPage { APIPage(rawValue: pageRaw) ?? .main }
    private var answer: Bool { page == .answer }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 12) {
                        TabTitle(caption: apiCaption, title: L("接口", "API", "API"))
                        Picker("", selection: $pageRaw) {
                            Text(L("改写 · 润色", "Rewrite", "書き換え")).tag(APIPage.main.rawValue)
                            Text(L("问答", "Ask", "質問")).tag(APIPage.answer.rawValue)
                        }
                        .pickerStyle(.segmented)
                        Text(answer
                             ? L("识意判断是问答时用这一页的接口回答。可以想久一点、可以联网，用和改写不同的服务商或模型。", "When Ask decides it's a question, this API answers it. It can think longer and search the web, using a different provider or model from Rewrite.", "質問だと判断されたときはこのページの API で答えます。じっくり考えたりウェブ検索したりでき、書き換えと別のサービスやモデルを使えます。")
                             : L("点 ✨ 润色、识意改写都用这一页的接口。要快，选不带深度思考的模型。", "✨ Polish and Ask rewrites use this API. Speed matters, so pick a model without deep thinking.", "✨ で整える・質問での書き換えはこの API を使います。速さ重視なので、深い思考のないモデルを選んでください。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        statusCard
                    }
                    .dashFormCard()
                }
                if answer {
                    answerSections
                } else {
                    mainSections
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
            .onAppear { openAnswerWebSearch(proxy) }
            .onChange(of: router.showsAnswerWebSearch) { _ in openAnswerWebSearch(proxy) }
        }
        .navigationTitle(L("接口", "API", "API"))
        .tabRootPage()
        .alert(L("打开联网调用？", "Turn on web search?", "ウェブ検索をオンにしますか？"), isPresented: Binding(
            get: { pendingWebMode != nil }, set: { if !$0 { pendingWebMode = nil } })) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) { pendingWebMode = nil }
            Button(L("打开", "Turn On", "オンにする")) {
                store.settings.webSearchMode = pendingWebMode
                pendingWebMode = nil
            }
        } message: {
            if let provider = store.settings.answerSearch {
                Text(L("需要联网时，问题会发给 \(provider.name) 的搜索服务（\(provider.company)）。每次约 0.01 元，从你的 \(provider.name) 账户扣。可以随时改回「禁止」。",
                       "When the web is needed, your question goes to \(provider.name) search (\(provider.company)), billed to your \(provider.name) account. You can switch back to Off at any time.",
                       "ウェブが必要なとき、質問は \(provider.name) の検索サービス（\(provider.company)）に送られ、\(provider.name) のアカウントに課金されます。いつでも「オフ」に戻せます。"))
            }
        }
        .alert(L("用 AI 之前，先同意隐私政策", "Agree to the Privacy Policy to use AI", "AI を使う前にプライバシーポリシーに同意してください"), isPresented: $needsPrivacy) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("阅读并同意", "Read and Agree", "読んで同意する")) { router.showsPrivacyWelcome = true }
        } message: {
            Text(L("同意后才能测试接口和使用 AI。拼音输入不受影响。", "Agree first to test the API and use AI. Pinyin input still works.", "同意すると API のテストと AI が使えます。ピンイン入力はそのまま使えます。"))
        }
        .alert(L("存为预设", "Save as preset", "設定を保存"), isPresented: $savingPreset) {
            TextField(L("名字", "Name", "名前"), text: $presetName)
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) { pendingPreset = nil }
            Button(L("保存", "Save", "保存")) { savePreset() }
        } message: {
            Text(L("保存地址、模型和 Key。Key 存进钥匙串。", "Saves the URL, model and key. The key goes into the Keychain.", "URL、モデル、キーを保存します。キーはキーチェーンに保存されます。"))
        }
        .alert(L("已经存过了：\(duplicateName ?? "")", "Already saved: \(duplicateName ?? "")", "保存済みです：\(duplicateName ?? "")"), isPresented: Binding(
            get: { duplicateName != nil }, set: { if !$0 { duplicateName = nil } })) {
            Button(L("好", "OK", "OK"), role: .cancel) { duplicateName = nil }
        }
        .alert(L("改名", "Rename", "名前を変更"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("名字", "Name", "名前"), text: $renameText)
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) { renaming = nil }
            Button(L("保存", "Save", "保存")) {
                if let item = renaming { store.renameSavedAPI(item.id, to: renameText) }
                renaming = nil
            }
        }
        .confirmationDialog(L("当前配置还没存，要先存吗？", "Your current setup isn't saved. Save it first?", "今の設定は保存されていません。先に保存しますか？"),
                            isPresented: Binding(get: { pendingPreset != nil && !savingPreset }, set: { if !$0 && !savingPreset { pendingPreset = nil } }),
                            titleVisibility: .visible) {
            Button(L("存为预设", "Save as preset", "設定を保存")) {
                presetName = defaultPresetName
                savingPreset = true
            }
            Button(L("不存，直接换", "Switch without saving", "保存せずに切り替え")) {
                if let item = pendingPreset { store.applySavedAPI(item, answer: answer) }
                pendingPreset = nil
            }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) { pendingPreset = nil }
        }
        .onAppear {
            recent = UsageStats.polishRecent
            answerRecent = UsageStats.answerRecent
        }
        .onChange(of: store.test) { _ in recent = UsageStats.polishRecent }
        .onChange(of: store.answerTest) { _ in answerRecent = UsageStats.answerRecent }
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

    /// 键盘「去开启」：切到问答页，滚到「联网调用」。
    private func openAnswerWebSearch(_ proxy: ScrollViewProxy) {
        guard router.showsAnswerWebSearch else { return }
        router.showsAnswerWebSearch = false
        pageRaw = APIPage.answer.rawValue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { proxy.scrollTo("webSearch", anchor: .center) }
        }
    }

    /// 标题上的灰字：「改写 DeepSeek · 问答 Kimi」，同一个接口时「改写、问答都用 DeepSeek」。
    private var apiCaption: String {
        guard store.settings.isConfigured else { return L("还没设置", "Not set up", "未設定") }
        let main = ProviderName.of(store.settings.baseURL)
        guard store.settings.usesAnswerEndpoint else {
            return L("改写、问答都用 \(main)", "Rewrite & Ask: \(main)", "書き換え・質問とも \(main)")
        }
        let ask = ProviderName.of(store.settings.answerBaseURL)
        return L("改写 \(main) · 问答 \(ask)", "Rewrite \(main) · Ask \(ask)", "書き換え \(main)・質問 \(ask)")
    }

    // MARK: 改写 · 润色页

    @ViewBuilder
    private var mainSections: some View {
        presetsSection
        Section {
        } header: {
            providerGrid(Provider.shown, selected: selectedProvider, badges: false) { choose($0) }
        } footer: {
            if Storefront.isMainlandChina {
                // 审核和合规：国区只列已完成生成式人工智能服务备案的模型；App 自己不提供模型。
                Text("DeepSeek（杭州深度求索人工智能基础技术研究有限公司）、Kimi（北京月之暗面科技有限公司）、通义千问（阿里云）均已完成生成式人工智能服务备案。Ollama 在你自己的电脑上运行。飞地输入法不提供模型，用你自己的 API Key 直接连接服务商。")
            }
        }
        Section {
            LabeledField(title: L("API 地址", "API URL", "API の URL"), text: $store.settings.baseURL, placeholder: "https://api.deepseek.com/v1", keyboard: .URL)
            LabeledField(title: L("模型", "Model", "モデル"), text: $store.settings.model, placeholder: "deepseek-flash")
            keyField($store.apiKey)
            NavigationLink {
                GenerationSettingsView()
            } label: {
                HStack {
                    Text(L("生成参数", "Generation", "生成パラメータ"))
                    Spacer()
                    Text(generationSummary).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("连接", "Connection", "接続"))
        } footer: {
            Text(selectedProvider == .ollama
                 ? L("把地址里的 IP 换成运行 Ollama 的电脑的局域网地址，地址填到 /v1。", "Replace the IP with the local address of the computer running Ollama. The URL ends with /v1. ", "IP を Ollama を動かしているパソコンのローカルアドレスに置き換えます。URL は /v1 までです。")
                 : L("选一个服务商会自动填好地址和模型；改了就算自定义，上面不再选中。", "Pick a provider to fill in the URL and model. Edit them and it counts as custom. ", "サービスを選ぶと URL とモデルが入力されます。書き換えるとカスタム扱いになります。"))
                + Text(L("API Key 只存在本机钥匙串里，不经过任何第三方服务器。", "Your API key stays in this iPhone's keychain and never passes through a third-party server.", "API キーはこの iPhone のキーチェーンにだけ保存され、第三者のサーバーを通りません。"))
        }
    }

    private var generationSummary: String {
        let temperature = String(format: "%.1f", store.settings.temperature)
        return store.settings.usesFixedTemperature
            ? L("最多 \(store.settings.maxTokens)", "Max \(store.settings.maxTokens)", "最大 \(store.settings.maxTokens)")
            : L("温度 \(temperature) · 最多 \(store.settings.maxTokens)", "Temp \(temperature) · Max \(store.settings.maxTokens)", "温度 \(temperature)・最大 \(store.settings.maxTokens)")
    }

    // MARK: 问答页

    @ViewBuilder
    private var answerSections: some View {
        Section {
            Toggle(isOn: Binding(get: { !store.settings.separateAnswer }, set: { store.settings.separateAnswer = !$0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("和改写用同一个接口", "Same API as Rewrite", "書き換えと同じ API"))
                    Text(sharedSubtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .tint(AppColor.purple)
        }
        if store.settings.separateAnswer {
            presetsSection
            Section {
            } header: {
                providerGrid(Provider.answerShown, selected: selectedAnswerProvider, badges: true) { chooseAnswer($0) }
            } footer: {
                if Storefront.isMainlandChina {
                    Text("通义千问（阿里云）、Kimi（北京月之暗面科技有限公司）、智谱 GLM（北京智谱华章科技股份有限公司）、DeepSeek（杭州深度求索人工智能基础技术研究有限公司）均已完成生成式人工智能服务备案。飞地输入法不提供模型，用你自己的 API Key 直接连接服务商。")
                }
            }
            Section {
                LabeledField(title: L("API 地址", "API URL", "API の URL"), text: $store.settings.answerBaseURL, placeholder: Provider.kimi.preset?.baseURL ?? "", keyboard: .URL)
                LabeledField(title: L("模型", "Model", "モデル"), text: $store.settings.answerModel, placeholder: Provider.kimiAnswerModel)
                keyField($store.answerApiKey)
            } header: {
                Text(L("连接", "Connection", "接続"))
            } footer: {
                Text(L("Ollama 这类自己电脑上的模型，直接在这里填地址就行，算自定义、不联网。", "For a model on your own computer, such as Ollama, just enter its URL here. It counts as custom and can't search the web.", "Ollama など自分のパソコンのモデルは、ここに URL を入力するだけです。カスタム扱いで、ウェブ検索はしません。"))
            }
        }
        webSearchSection
    }

    /// 「和改写用同一个接口」下面的灰字：改写那边的服务商 · 模型 · 能不能联网。
    private var sharedSubtitle: String {
        guard store.settings.isConfigured else { return L("改写还没设置", "Rewrite isn't set up", "書き換えは未設定") }
        let web = store.settings.searchProvider != nil
            ? L("可联网", "Can search", "検索可")
            : L("不联网", "No web search", "検索なし")
        return "\(ProviderName.of(store.settings.baseURL)) · \(store.settings.model) · \(web)"
    }

    /// 联网调用（AP2–AP4）：分段「开 | 每次询问 | 禁止」；问答接口不能联网时整组变灰，设置值保留。
    private var webSearchSection: some View {
        let provider = store.settings.answerSearch
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("联网调用", "Web search", "ウェブ検索"), systemImage: "globe")
                    .labelStyle(WebSearchLabelStyle())
                Picker("", selection: Binding(
                    get: { store.settings.webSearchMode ?? .off },
                    set: { mode in
                        // 大陆店面从「禁止」改成可以联网，先确认；改回「禁止」不用。
                        if Storefront.isMainlandChina, mode != .off, (store.settings.webSearchMode ?? .off) == .off {
                            pendingWebMode = mode
                        } else {
                            store.settings.webSearchMode = mode
                        }
                    })) {
                    ForEach(WebSearchMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            .opacity(provider == nil ? 0.45 : 1)
            .disabled(provider == nil)
        } footer: {
            Text(webSearchFooter(provider))
        }
        .id("webSearch")
    }

    private func webSearchFooter(_ provider: SearchProvider?) -> String {
        guard let provider else {
            let name = ProviderName.of(store.settings.forAnswers.baseURL)
            return L("\(name) 不能联网，问答只用模型自己的知识。想联网，请选通义千问、Kimi 或智谱 GLM。", "\(name) can't search the web, so answers use only the model's own knowledge. To search, choose Qwen, Kimi or Zhipu GLM.", "\(name) はウェブ検索できないため、回答はモデル自身の知識だけを使います。検索するには Qwen・Kimi・Zhipu GLM を選んでください。")
        }
        let lead = L("由模型自己判断这个问题要不要联网（问天气、新闻、价格这类才会搜）。", "The model decides whether a question needs the web (only things like weather, news or prices). ", "質問にウェブが必要かはモデルが判断します（天気・ニュース・価格などのときだけ検索）。")
        let mode: String
        switch store.settings.webSearchMode ?? .off {
        case .on: mode = L("需要联网时直接搜；第一次用这家服务商时，键盘上先问你一次。", "When it does, it searches right away; the first time with a provider, the keyboard asks you once.", "必要なときはそのまま検索します。そのサービスを初めて使うときは、キーボードで一度確認します。")
        case .ask: mode = L("需要联网时，键盘上先问你一次，点「允许」才搜。", "When it does, the keyboard asks you first and searches only if you tap Allow.", "必要なときはキーボードで先に確認し、「許可」したときだけ検索します。")
        case .off: mode = L("不联网。遇到要最新信息的问题，键盘上会提示你，可以去开启，也可以直接回答。", "No web search. When a question needs current info, the keyboard tells you, and you can turn it on or answer anyway.", "ウェブ検索はしません。最新情報が必要な質問では、キーボードでお知らせします。オンにするか、そのまま回答できます。")
        }
        let tail = L("\n每次搜索把问题发给 \(provider.name) 的搜索服务，约 ¥0.01，从你的 \(provider.name) 账户扣。改写不调用联网搜索。", "\nEach search sends your question to \(provider.name) search, billed to your \(provider.name) account. Rewrites never call web search.", "\n検索のたびに質問を \(provider.name) の検索サービスに送り、\(provider.name) のアカウントに課金されます。書き換えではウェブ検索を使いません。")
        return lead + mode + tail
    }

    private var selectedAnswerProvider: Provider? {
        Provider.matching(baseURL: store.settings.answerBaseURL, model: store.settings.answerModel, answer: true)
    }

    private func chooseAnswer(_ item: Provider) {
        guard item != selectedAnswerProvider, let preset = item.answerPreset else { return }
        store.settings.answerBaseURL = preset.baseURL
        store.settings.answerModel = preset.model
    }

    // MARK: 我的预设（AP1、AP2、AP5）

    /// 两页共用一份列表，点了只换当前这一页。当前页三样都和某条一样才打勾。
    private var presetsSection: some View {
        let current = store.currentSavedAPI(answer: answer)
        return Section {
            ForEach(store.savedAPIs) { item in
                Button { tapPreset(item, current: current) } label: {
                    PresetRow(item: item, current: item.id == current?.id)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.deleteSavedAPI(item.id) } label: {
                        Text(L("删除", "Delete", "削除"))
                    }
                    Button {
                        renameText = item.name
                        renaming = item
                    } label: {
                        Text(L("改名", "Rename", "名前を変更"))
                    }
                    .tint(Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255))
                }
            }
            Button {
                presetName = defaultPresetName
                savingPreset = true
            } label: {
                Label(L("把当前配置存为预设", "Save current setup as preset", "今の設定を保存"), systemImage: "plus")
                    .foregroundStyle(AppColor.purple)
            }
            .disabled(!pageConfigured)
        } header: {
            Text(L("我的预设", "My presets", "保存した設定"))
        } footer: {
            Text(L("点一下就换成这一套地址、模型和 Key，只换这一页。两页共用这份列表。左滑改名或删除。Key 只存在本机钥匙串里，这里只显示尾号。", "Tap to switch this page to that URL, model and key. Both pages share this list. Swipe left to rename or delete. Keys stay in this iPhone's keychain; only the last 4 characters are shown.", "タップするとこのページだけその URL・モデル・キーに切り替わります。2 つのページで同じリストを使います。左にスワイプで名前変更・削除。キーは本機のキーチェーンにだけ保存され、末尾だけ表示します。"))
        }
    }

    private var pageConfigured: Bool {
        answer ? store.settings.usesAnswerEndpoint : store.settings.isConfigured
    }

    /// 默认名字「服务商 · 模型」，自定义地址用主机名。
    private var defaultPresetName: String {
        let url = answer ? store.settings.answerBaseURL : store.settings.baseURL
        let model = answer ? store.settings.answerModel : store.settings.model
        return ProviderName.of(url) + " · " + model.trimmingCharacters(in: .whitespaces)
    }

    private func tapPreset(_ item: SavedAPI, current: SavedAPI?) {
        guard item.id != current?.id else { return }
        // 当前配置没存成任何预设、和预设都不一样：先问一次。
        if current == nil, pageConfigured {
            pendingPreset = item
        } else {
            store.applySavedAPI(item, answer: answer)
        }
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = store.saveAPI(name: name.isEmpty ? defaultPresetName : name, answer: answer)
        if case .duplicate(let existing) = result {
            duplicateName = existing.name
        }
        // 「先存再换」：存好以后换成刚才点的那条。
        if let item = pendingPreset {
            store.applySavedAPI(item, answer: answer)
            pendingPreset = nil
        }
    }

    // MARK: 共用

    private func keyField(_ key: Binding<String>) -> some View {
        HStack {
            Text("API Key")
            SecureField(L("自建服务可以留空", "Optional for self-hosted", "セルフホストなら空欄で可"), text: key)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func providerGrid(_ items: [Provider], selected: Provider?, badges: Bool, choose: @escaping (Provider) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("服务商", "Provider", "サービス"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    ProviderCard(provider: item, selected: selected == item,
                                 badge: badges ? (item.canSearch ? .web : .noWeb) : nil,
                                 tutorial: GuideTutorial.of(item) == nil ? nil : { router.openTutorial(item, answer: answer) }) { choose(item) }
                }
            }
        }
        .dashFormCard()
    }

    /// 顶部状态卡（PB2）：连接状态、最近一次耗时、「测试」，最近 10 次请求的小曲线。各页只统计各自的请求；
    /// 问答页开着「和改写用同一个接口」时就是改写那张。
    private var statusCard: some View {
        let ownAnswer = answer && store.settings.separateAnswer
        let configured = ownAnswer ? store.settings.usesAnswerEndpoint : store.settings.isConfigured
        let requests = ownAnswer ? answerRecent : recent
        let state = ownAnswer ? store.answerTest : store.test
        let seconds = Self.lastSeconds(state, requests)
        let failed = Self.lastFailed(state, requests)
        let status = ownAnswer ? answerStatus : mainStatus
        let model = ownAnswer ? store.settings.answerModel : store.settings.model
        return DashCard {
            HStack(spacing: 6) {
                Circle().fill(status.color).frame(width: 7, height: 7)
                Text(status.text).font(.subheadline.weight(.semibold)).foregroundStyle(status.color).lineLimit(2)
                Spacer(minLength: 8)
            }
            HStack(alignment: .firstTextBaseline) {
                // 没配置时旧的请求记录不算数，不显示。
                if configured, let seconds {
                    DashBigNumber(value: String(format: "%.1f", seconds),
                                  unit: failed ? L("秒 · 最近一次失败", "s · last request failed", "秒・直近は失敗") : L("秒 · 最近一次", "s · last request", "秒・直近"))
                        .foregroundStyle(failed ? Color.secondary : Color.primary)
                } else {
                    DashBigNumber(value: "–", unit: L("还没有请求", "No requests yet", "リクエストなし"))
                }
                Spacer(minLength: 8)
                Button {
                    if router.privacyAgreed {
                        Task { ownAnswer ? await store.runAnswerTest() : await store.runTest() }
                    } else {
                        needsPrivacy = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if state == .running { ProgressView().controlSize(.small) }
                        Text(L("测试", "Test", "テスト"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashColor.ai)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(DashColor.ai.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(!configured || state == .running)
            }
            if configured {
                DashSparkline(values: requests.map { Double($0.ms) }, color: requests.allSatisfy(\.ok) ? DashColor.ok : .orange)
                Text(Self.summary(requests, model: model)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    /// 测试刚失败时显示错误；否则看最近一次请求，再不然看上次测试。「已连接 DeepSeek」带上服务商名字。
    private var mainStatus: (text: String, color: Color) {
        guard store.settings.isConfigured else { return (L("还没配置，先选服务商、填地址", "Not set up. Pick a provider and fill in the URL", "未設定です。サービスを選んで URL を入力してください"), DashColor.system) }
        let connected = L("已连接 \(ProviderName.of(store.settings.baseURL))", "Connected to \(ProviderName.of(store.settings.baseURL))", "\(ProviderName.of(store.settings.baseURL)) に接続済み")
        switch store.test {
        case .running: return (L("正在测试…", "Testing…", "テスト中…"), .orange)
        case .failure(let message): return (message, .red)
        case .success: return (connected, DashColor.ok)
        case .idle: break
        }
        if let last = recent.last { return last.ok ? (connected, DashColor.ok) : (L("最近一次请求失败", "Last request failed", "直近のリクエストは失敗"), .red) }
        switch store.lastTestOK {
        case true?: return (connected, DashColor.ok)
        case false?: return (L("连不上", "Can't connect", "接続できません"), .red)
        case nil: return (L("还没测试", "Not tested", "未テスト"), DashColor.system)
        }
    }

    private var answerStatus: (text: String, color: Color) {
        guard store.settings.usesAnswerEndpoint else {
            return (L("还没配置，先选服务商、填地址", "Not set up. Pick a provider and fill in the URL", "未設定です。サービスを選んで URL を入力してください"), DashColor.system)
        }
        let name = ProviderName.of(store.settings.answerBaseURL)
        let connected = L("已连接 \(name)", "Connected to \(name)", "\(name) に接続済み")
        switch store.answerTest {
        case .running: return (L("正在测试…", "Testing…", "テスト中…"), .orange)
        case .failure(let message): return (message, .red)
        case .success: return (connected, DashColor.ok)
        case .idle: break
        }
        if let last = answerRecent.last { return last.ok ? (connected, DashColor.ok) : (L("最近一次请求失败", "Last request failed", "直近のリクエストは失敗"), .red) }
        return (L("还没测试", "Not tested", "未テスト"), DashColor.system)
    }

    /// 最近一次（测试或请求）失败：大数字变灰，单位写「失败」。
    private static func lastFailed(_ test: AppStore.TestState, _ requests: [UsageStats.Request]) -> Bool {
        if case .failure = test { return true }
        if case .success = test { return false }
        return requests.last.map { !$0.ok } ?? false
    }

    private static func lastSeconds(_ test: AppStore.TestState, _ requests: [UsageStats.Request]) -> Double? {
        if case .success(_, let seconds) = test { return seconds }
        return requests.last.map { Double($0.ms) / 1000 }
    }

    private static func summary(_ recent: [UsageStats.Request], model: String) -> String {
        guard !recent.isEmpty else { return L("点「测试」或在键盘上点 ✨，这里会画出最近 10 次请求的耗时。", "Tap Test or ✨ on the keyboard to chart your last 10 requests.", "「テスト」かキーボードの ✨ で、直近 10 回のリクエスト時間がここに表示されます。") }
        let failed = recent.filter { !$0.ok }.count
        let head = failed == 0
            ? L("最近 \(recent.count) 次请求都成功", "Last \(recent.count) requests succeeded", "直近 \(recent.count) 回すべて成功")
            : L("最近 \(recent.count) 次请求有 \(failed) 次失败", "\(failed) of the last \(recent.count) requests failed", "直近 \(recent.count) 回中 \(failed) 回失敗")
        return model.isEmpty ? head : head + " · " + model
    }

    /// 卡片选中哪个跟着地址和模型走：自己改过就不选中预设。
    private var selectedProvider: Provider? {
        Provider.matching(baseURL: store.settings.baseURL, model: store.settings.model)
    }

    private func choose(_ item: Provider) {
        guard item != selectedProvider else { return }
        if let preset = item.preset {
            store.settings.baseURL = preset.baseURL
            store.settings.model = preset.model
            // 生成参数跟着预设走：温度回到默认；Kimi K3 先思考，思考也算在最大输出里，给 4096，其他家 1024。
            store.settings.temperature = EnclaveSettings().temperature
            store.settings.maxTokens = item.maxTokens
        }
    }

    private func importConfig() {
        guard let string = UIPasteboard.general.string, SettingsStore.importString(string) else {
            importResult = false
            return
        }
        store.reload()
        importResult = true
    }
}

/// 「联网调用」那一行：🌐 紫色图标 + 17pt 标题。
private struct WebSearchLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(AppColor.purple)
            configuration.title
        }
    }
}

/// 我的预设一行：左边 20pt 宽的勾选列（正在用的紫色勾、名字加粗），名字 17pt，下面 13pt 灰字「主机 · 模型 · Key 尾号 xxxx」。
private struct PresetRow: View {
    var item: SavedAPI
    var current: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255))
                .opacity(current ? 1 : 0)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 17, weight: current ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var detail: String {
        let host = URL(string: item.baseURL)?.host.map { host in
            URL(string: item.baseURL)?.port.map { "\(host):\($0)" } ?? host
        } ?? item.baseURL
        let key = item.keySuffix.map { L("Key 尾号 \($0)", "Key …\($0)", "キー末尾 \($0)") } ?? L("无 Key", "No key", "キーなし")
        return "\(host) · \(item.model) · \(key)"
    }
}

/// 改写页「生成参数」二级页：温度、最大输出。
private struct GenerationSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Stepper(value: $store.settings.temperature, in: 0...1.5, step: 0.1) {
                        HStack {
                            Text(L("温度", "Temperature", "温度"))
                            Spacer()
                            Text(store.settings.temperature, format: .number.precision(.fractionLength(1)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Kimi K 系列：温度变灰不能调，数值留着，换回别的模型恢复；下面的说明不跟着变淡。
                    .disabled(store.settings.usesFixedTemperature)
                    .opacity(store.settings.usesFixedTemperature ? 0.45 : 1)
                    if store.settings.usesFixedTemperature {
                        Text(L("Kimi K 系列用固定温度，这里不生效", "Kimi K models use a fixed temperature; this setting is ignored", "Kimi K シリーズは温度が固定のため、この設定は使われません"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255))
                    }
                }
                Stepper(value: $store.settings.maxTokens, in: 256...8192, step: 256) {
                    HStack {
                        Text(L("最大输出", "Max output", "最大出力"))
                        Spacer()
                        Text("\(store.settings.maxTokens)").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(L("温度越低越稳定，润色建议 0.2–0.5。", "Lower is steadier. 0.2–0.5 works well for polishing.", "低いほど安定します。整えるには 0.2〜0.5 がおすすめです。"))
            }
        }
        .navigationTitle(L("生成参数", "Generation", "生成パラメータ"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 服务商卡片：名字和说明，选中的描紫边、右上打勾。问答页的卡片下面再加「🌐 可联网」/「不联网」小标签。
private struct ProviderCard: View {
    enum Badge { case web, noWeb }

    var provider: Provider
    var selected: Bool
    var badge: Badge? = nil
    /// 右下角「配置教程」（有教程的四家）；点它不选中这一格。
    var tutorial: (() -> Void)? = nil
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
                // 问答页：可联网标签和「配置教程」同一行；改写页没有标签，也留出这一行。
                if let badge {
                    badgeView(badge).padding(.top, 5)
                } else if tutorial != nil {
                    Color.clear.frame(height: 18).padding(.top, 5)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DashColor.ai, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if let tutorial {
                // 12.5pt semibold #5B4BE8，前面 12pt 书本图标。
                Button(action: tutorial) {
                    HStack(spacing: 3) {
                        Image(systemName: "book").font(.system(size: 12, weight: .semibold))
                        Text(L("配置教程", "Setup guide", "設定ガイド")).font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255))
                    .frame(height: 18)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("\(provider.title) 配置教程", "\(provider.title) setup guide", "\(provider.title) 設定ガイド"))
            }
        }
    }

    /// 可联网：#E3F4EA 底、#248A3D 字；不联网：#F2F2F7 底、#8E8E93 字。高 18、圆角 5、11pt semibold。
    private func badgeView(_ badge: Badge) -> some View {
        let web = badge == .web
        return HStack(spacing: 3) {
            if web { Image(systemName: "globe").font(.system(size: 9.5, weight: .semibold)) }
            Text(web ? L("可联网", "Web search", "検索可") : L("不联网", "No web", "検索なし"))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(web ? Color(red: 0x24 / 255, green: 0x8A / 255, blue: 0x3D / 255) : Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255))
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(web ? Color(red: 0xE3 / 255, green: 0xF4 / 255, blue: 0xEA / 255) : Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)))
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
    /// 打开「处理长文本」前的二次确认。
    @State private var confirmLongText = false

    var body: some View {
        Form {
            // B 卡片放在 Section 的 header 里，分组的大圆角裁不到，四角完整（见 dashFormCard）。
            if KeyboardStatus.fullAccess == false {
                Section {
                } header: {
                    NotSyncedBanner().dashFormCard()
                }
            }
            // 主要语言（EM1/EM2）：小标题 + 白卡里的三段选择，脚注随选项变。
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("主要语言", "Primary language", "主な言語"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                    Picker(L("主要语言", "Primary language", "主な言語"), selection: $store.settings.inputLanguage) {
                        ForEach(InputLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
                }
                .dashFormCard()
            } footer: {
                Text(languageFooter)
            }
            if store.settings.inputLanguage != .englishOnly {
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
            }
            Section(L("英文", "English", "英語")) {
                EnglishSuggestionsToggle()
                Toggle(isOn: $store.settings.autoCapitalize) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("句首自动大写", "Auto-capitalization", "文頭を自動で大文字に"))
                        Text(L("句子开头的第一个字母自动大写", "Capitalizes the first letter of each sentence", "文の最初の文字を自動で大文字にします"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            TouchCalibrationSection(layout: store.settings.inputLanguage == .englishOnly ? .qwerty : store.settings.keyboardLayout)
            Section(L("按键反馈", "Key feedback", "キーのフィードバック")) {
                Toggle(L("按键震动", "Haptics", "触覚"), isOn: $store.settings.keyHaptics)
                Toggle(isOn: $store.settings.keySound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("按键声音", "Sounds", "サウンド"))
                        Text(L("手机静音时不响", "Silent when the iPhone is muted", "消音モードでは鳴りません")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("结果卡左边的按钮", "Button beside the result", "結果の左のボタン"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                    HStack(spacing: 12) {
                        ForEach(ResultKeyAction.allCases) { action in
                            ResultKeyCard(action: action, settings: store.settings,
                                          selected: store.settings.resultKeyPrimary == action) {
                                store.settings.resultKeyPrimary = action
                            }
                        }
                    }
                }
                .dashFormCard()
            } footer: {
                Text(resultKeyFooter)
            }
            Section {
                // 打开要再确认一次：长文本处理慢、更容易改错，替换的范围也更大。
                Toggle(isOn: Binding(get: { store.settings.longText },
                                     set: { on in if on { confirmLongText = true } else { store.settings.longText = false } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("处理长文本", "Process long text", "長い文章も処理"))
                        Text(L("关着时 AI 只读光标前约 100 字", "When off, AI reads about 100 characters before the cursor", "オフのとき AI はカーソル前の約 100 字だけを読みます"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("AI 读取范围", "What AI reads", "AI が読む範囲"))
            } footer: {
                Text(L("没选中文字时，AI 只处理光标前约 100 字，按整句截取；打开后约 200 字。文字越长越慢、越容易改错，替换前请看一遍结果。替换只换送去处理的那一段，其余不动；要处理整段，先全选再点 ✨。",
                       "With nothing selected, AI handles about 100 characters before the cursor, cut at whole sentences; about 200 when on. Longer text is slower and easier to get wrong, so check the result first. Replace only changes the part that was sent; to handle a whole passage, select it first, then tap ✨.",
                       "何も選択していないとき、AI はカーソル前の約 100 字を文単位で処理します。オンで約 200 字。長いほど遅く、誤りやすいので、置き換える前に結果を確認してください。置き換えは送った部分だけで、残りはそのままです。全体は全選択してから ✨ をタップします。"))

            }
            .alert(L("打开「处理长文本」？", "Turn on Process long text?", "「長い文章も処理」をオンにしますか？"), isPresented: $confirmLongText) {
                Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
                Button(L("打开", "Turn On", "オンにする")) { store.settings.longText = true }
            } message: {
                Text(L("AI 每次会读光标前约 200 字。文字越长，生成越慢、越容易改错，替换的范围也越大。替换前请先看一遍结果，不对可以撤销。",
                       "AI will read about 200 characters before the cursor. Longer text is slower, more likely to be changed by mistake, and Replace changes more at once. Check the result before replacing; you can undo.",
                       "AI はカーソル前の約 200 字を読みます。長いほど時間がかかり、誤って書き換えられやすく、置き換える範囲も広くなります。置き換える前に結果を確認してください。取り消しもできます。"))
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

    /// 点一下做什么、怎么换到另一个，随设置变。
    private var resultKeyFooter: String {
        let settings = store.settings
        let tap = settings.resultKeyPrimary == .replace
            ? L("点一下把结果换掉输入框里的话", "Tap to replace the text in the field with the result", "タップで入力欄の文を結果に置き換えます")
            : L("点一下把结果接在输入框里的话后面", "Tap to add the result after the text in the field", "タップで入力欄の文の後ろに結果を追加します")
        let other = settings.resultKeyPrimary.other
        let detail = other == .insert
            ? L("插入（接在原来的话后面）", "insert (add it after the existing text)", "挿入（元の文の後ろに追加）")
            : L("替换（换掉原来的话）", "replace (swap out the existing text)", "置き換え（元の文と入れ替え）")
        let swipe = L("按住往上推", "Hold and push up to ", "長押しで上に押すと")
        return L("\(tap)；\(swipe)\(detail)。", "\(tap). \(swipe)\(detail).", "\(tap)。\(swipe)\(detail)。")
    }

    private var languageFooter: String {
        switch store.settings.inputLanguage {
        case .chinese: return L("打开键盘先是拼音，按「中/英」切到英文。", "The keyboard opens in pinyin. Tap 中/英 for English.", "キーボードはピンインで開きます。「中/英」で英語に切り替えます。")
        case .englishFirst: return L("打开键盘先是英文，按「中/英」切到拼音。", "The keyboard opens in English. Tap 中/英 for pinyin.", "キーボードは英語で開きます。「中/英」でピンインに切り替えます。")
        case .englishOnly: return L("只有英文全键盘，不打拼音。「中/英」键换成逗号，长按出 ' ? !", "English QWERTY only, no pinyin. The 中/英 key becomes a comma; hold it for ' ? !", "英語の QWERTY のみで、ピンインは使いません。「中/英」キーはカンマになり、長押しで ' ? ! が出ます。")
        }
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

/// 「结果卡左边的按钮」二选一卡片（SET1、SET2）：上面画出键和结果卡的样子、往哪滑换成什么，下面名称和勾选圈。
private struct ResultKeyCard: View {
    var action: ResultKeyAction
    var settings: EnclaveSettings
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        miniKey
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(.systemBackground))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(AppColor.purple.opacity(0.35), lineWidth: 1))
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Capsule().fill(AppColor.purple.opacity(0.18)).frame(height: 5)
                                    Capsule().fill(AppColor.purple.opacity(0.18)).frame(width: 40, height: 5)
                                }
                                .padding(8)
                            }
                    }
                    .frame(height: 44)
                    HStack(spacing: 3) {
                        Image(systemName: up ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .semibold))
                        Text(hint).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.systemGray5)))
                HStack {
                    Text(action.title).font(.subheadline.weight(.semibold))
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

    private var pop: Bool { settings.resultKeySwipe == .pop }
    private var up: Bool { !pop && settings.resultKeyWheelUp }

    private var hint: String {
        let other = action.other.title
        if pop { return L("往下划：下方弹出\(other)", "Slide down: pop up \(other)", "下へ：\(other)") }
        return up ? L("往上滑：\(other)", "Slide up: \(other)", "上へ：\(other)")
                  : L("往下滑：\(other)", "Slide down: \(other)", "下へ：\(other)")
    }

    /// 缩小的键：主功能在正中，滚轮时另一个在边上露一点，弹出时下面一个 ▾。
    private var miniKey: some View {
        let colors: [Color] = action == .replace
            ? [Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255), Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)]
            : [Color(red: 0x0E / 255, green: 0x74 / 255, blue: 0x90 / 255), Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)]
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            label(action).offset(y: pop ? -4 : 0)
            if pop {
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.white).offset(y: 12)
            } else {
                label(action.other).opacity(0.5).blur(radius: 0.6).offset(y: up ? 17 : -17)
            }
        }
        .frame(width: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func label(_ action: ResultKeyAction) -> some View {
        HStack(spacing: 2) {
            Image(systemName: action.systemImage).font(.system(size: 8, weight: .bold))
            Text(action.title).font(.system(size: 10, weight: .bold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.white)
        .padding(.horizontal, 2)
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
    /// 整句模型的下载地址，空着就用默认的 GitHub 地址。
    @State private var grammarURL = GrammarModel.customDownloadURL ?? ""
    /// 下载地址框平时收起；填过自定义地址或下载失败过就直接展开。
    @State private var showsGrammarURL = GrammarModel.customDownloadURL != nil
    @State private var englishEnabled = Predictor.englishEnabled

    var body: some View {
        DashPage {
            dictionaryCard
            grammarCard
            englishCard
            speedCard
        }
        .navigationTitle(L("词库", "Dictionaries", "辞書"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deployer.state) {
            size = await Task.detached { RimeDeployer.diskSize() }.value
        }
        .onAppear {
            typingStats = TypingStats.summary
            grammar.refresh()
            englishEnabled = Predictor.englishEnabled
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
                        Text(L("按词和词常在一起出现的统计挑出最通顺的整句，整句打完首选更准。完全在本机运行，不联网。默认从万象的 GitHub 下载，断了会自动重试、接着下。",
                               "Picks the most natural sentence from statistics of which words go together, so whole sentences come out right more often. Runs fully on this iPhone, offline. Downloaded from Wanxiang's GitHub by default; if the connection drops it retries and picks up where it left off.",
                               "語と語のつながりの統計から自然な文を選ぶので、文をまとめて入力したときの第一候補が正確になります。すべて端末内で動作し、通信しません。デフォルトでは万象の GitHub からダウンロードし、途切れたら自動で再試行して続きから再開します。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Button(grammar.canResume ? L("继续下载", "Resume download", "続きから") : L("下载", "Download", "ダウンロード")) { grammar.download() }
                            .font(.system(size: 15, weight: .semibold))
                            .disabled(deployer.state == .deploying)
                        grammarURLField
                    }
                }
                if case .failed(let message) = grammar.state {
                    Text(message).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
        }
    }

    /// 下载地址：GitHub 在大陆常常很慢或打不开，可以换成镜像或自己的服务器。改了地址旧进度作废。
    @ViewBuilder
    private var grammarURLField: some View {
        if showsGrammarURL || isGrammarFailed {
            grammarURLEditor
        } else {
            Button(L("下载太慢？换个下载地址", "Slow? Use another download address", "遅いときは別のアドレスへ")) { showsGrammarURL = true }
                .font(.system(size: 13))
                .foregroundStyle(AppColor.purple)
                .buttonStyle(.plain)
        }
    }

    private var isGrammarFailed: Bool {
        if case .failed = grammar.state { return true }
        return false
    }

    private var grammarURLEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("下载地址", "Download address", "ダウンロード元")).font(.system(size: 13, weight: .semibold))
            TextField(GrammarModel.defaultDownloadURL.absoluteString, text: $grammarURL)
                .font(.system(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
                .onSubmit { saveGrammarURL() }
                .onChange(of: grammarURL) { _ in saveGrammarURL() }
            Text(L("空着就用上面灰字的 GitHub 地址。下不动时可以换成镜像地址，文件要是同一个 .gram。",
                   "Leave empty to use the GitHub address shown in gray. If it's too slow, use a mirror of the same .gram file.",
                   "空欄なら灰色の GitHub のアドレスを使います。遅いときは同じ .gram ファイルのミラーを指定できます。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func saveGrammarURL() {
        let old = GrammarModel.downloadURL
        GrammarModel.customDownloadURL = grammarURL
        if GrammarModel.downloadURL != old { grammar.discardProgress() }
    }

    // MARK: - 英文词库

    /// 英文单词表和联想数据随键盘内置，不用下载，这里只能开关。
    private var englishCard: some View {
        DashCard {
            DashCardHeader(icon: "textformat.abc", title: L("英文词库", "English words", "英語辞書"), color: DashColor.input, note: L("已内置", "Built in", "内蔵"))
            DashBigNumber(value: L("6 万", "60k", "6 万"), unit: L("个单词 · 1.6 MB", "words · 1.6 MB", "語 · 1.6 MB"))
            Toggle(L("英文补全和联想", "English suggestions", "英語の候補と予測"),
                   isOn: Binding(get: { englishEnabled }, set: { englishEnabled = $0; Predictor.englishEnabled = $0 }))
                .tint(AppColor.purple)
            Text(L("英文状态下打字时补全单词（tomo → tomorrow），打完一个词接着推荐下一个。单词表来自万象拼音（CC BY 4.0），词组搭配来自 Tatoeba 例句（CC BY 2.0 FR）。",
                   "Completes words as you type in English (tomo → tomorrow) and suggests the next word. Word list from Wanxiang Pinyin (CC BY 4.0); word pairs from Tatoeba sentences (CC BY 2.0 FR).",
                   "英語入力中に単語を補完し（tomo → tomorrow）、次の単語を予測します。単語リストは万象ピンイン（CC BY 4.0）、語のつながりは Tatoeba の例文（CC BY 2.0 FR）から。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
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
                    if let launch = stats.launch {
                        HStack(alignment: .top) {
                            TypingSmallStat(value: Self.milliseconds(launch.appear),
                                            label: L("冷启动到弹出", "Cold start to shown", "コールド起動→表示"))
                            TypingSmallStat(value: Self.milliseconds(launch.ready),
                                            label: L("冷启动到能打拼音", "Cold start to pinyin ready", "コールド起動→入力可"))
                            TypingSmallStat(value: "\(launch.count)", label: L("冷启动次数", "Cold starts", "コールド起動回数"))
                        }
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
