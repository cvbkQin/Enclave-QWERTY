import StoreKit
import SwiftUI
import UIKit

// MARK: - 首次启动引导：连上你自己的 AI 接口（OB1–OB7）

/// 引导看过没有（走完、跳过都算），存在 App Group 里，以后不再自动弹；首页 OB8 卡片兜底。
enum SetupGuide {
    private static let seenKey = "setupGuide.seen"

    static var seen: Bool {
        get { SharedStorage.defaults.bool(forKey: seenKey) }
        set { SharedStorage.defaults.set(newValue, forKey: seenKey) }
    }

    /// 「1 元可调用约 500 次」只在中国大陆店面显示。
    static var showsPrice: Bool { Storefront.isMainlandChina }
}

enum SetupGuidePage: Identifiable, Hashable {
    case intro, provider, step(Int), done

    var id: String {
        switch self {
        case .intro: return "intro"
        case .provider: return "provider"
        case .step(let n): return "step\(n)"
        case .done: return "done"
        }
    }
}

/// 引导里的颜色：字 #14121F / 次要 #6E6A80 / 分隔线 #ECEAF3；页面 #F6F5FA，白卡；深色白卡 #1C1C1E、页面 #000。
enum GuideColor {
    static let text = dynamic(0x14121F, .label)
    static let secondary = dynamic(0x6E6A80, .secondaryLabel)
    static let divider = dynamic(0xECEAF3, .separator)
    static let page = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : UIColor(hex: 0xF6F5FA) })
    static let card = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x1C1C1E) : .white })
    static let purple = Color(hex: 0x5B4BE8)
    static let chipFill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x5B4BE8).withAlphaComponent(0.25) : UIColor(hex: 0xECEAFD) })
    static let chipText = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xB4A9FF) : UIColor(hex: 0x4A3BD6) })
    static let progressOff = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x3A3A3C) : UIColor(hex: 0xDDD9EE) })
    static let field = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x2C2C2E) : UIColor(hex: 0xF6F5FA) })

    private static func dynamic(_ light: UInt32, _ dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct SetupGuideView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    @State private var page: SetupGuidePage
    @State private var history: [SetupGuidePage] = []
    @State private var provider: Provider = .deepseek

    init(start: SetupGuidePage) {
        _page = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            GuideBackground(glow: page == .intro || page == .provider || page == .done)
            VStack(spacing: 0) {
                if page != .intro && page != .done { topBar }
                content
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .interactiveDismissDisabled()
        .animation(.easeInOut(duration: 0.22), value: page)
    }

    // MARK: 顶栏：左上返回、右上跳过

    private var topBar: some View {
        HStack {
            if !history.isEmpty {
                Button { back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GuideColor.text)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(GuideColor.card.opacity(0.85)))
                }
                .accessibilityLabel(L("返回", "Back", "戻る"))
            }
            Spacer()
            Button(L("跳过", "Skip", "スキップ")) { finish() }
                .font(.system(size: 15))
                .foregroundStyle(GuideColor.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(height: 50)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .intro: intro
        case .provider: providerPage
        case .step(let n): GuideStepView(step: n, next: { go(n < 4 ? .step(n + 1) : .done) }, store: store)
        case .done: done
        }
    }

    // MARK: OB1 说明

    private var intro: some View {
        GuidePage {
            VStack(alignment: .leading, spacing: 20) {
                GuideAppMark(size: 64, corner: 19)
                    .padding(.top, 40)
                GuideTitle(L("AI 润色需要\n你自己的 API Key", "AI needs\nyour own API key", "AI 機能には\n自分の API キーが必要です"),
                           subtitle: L("飞地输入法不自带 AI，也没有服务器。填一个你自己申请的 Key 才能用润色、翻译和按要求改；不填，AI 功能用不了。",
                                       "Enclave has no built-in AI and no servers. Add a key you got yourself to polish, translate and rewrite. Without one, AI features don't work.",
                                       "Enclave には AI もサーバーもありません。自分で取得したキーを入れると、整える・翻訳・指示どおりの書き換えが使えます。入れないと AI 機能は使えません。"))
                GuideCard {
                    GuideRow(icon: "keyboard", color: Color(hex: 0x0A84FF),
                             title: L("打字不用任何配置", "Typing needs no setup", "入力は設定なしで使えます"),
                             detail: L("拼音、英文、常用词，现在就能用。", "Pinyin, English and My Words work right away.", "ピンイン、英語、ユーザ辞書はすぐに使えます。"))
                    GuideDivider()
                    GuideRow(icon: "link", color: GuideColor.purple,
                             title: L("Key 只存在这台手机上", "Your key stays on this iPhone", "キーはこの iPhone にだけ保存"),
                             detail: L("文字直接发到你选的服务商，不经过我们。", "Text goes straight to the provider you pick, never through us.", "文章は選んだサービスに直接送られ、私たちを経由しません。"))
                    GuideDivider()
                    GuideRow(icon: "checkmark", color: Color(hex: 0x30A46C),
                             title: L("跟着教程 3 分钟搞定", "About 3 minutes with the guide", "ガイドに沿って約 3 分"),
                             detail: L("内置 DeepSeek 分步教程，从注册到测试连接。", "A step-by-step DeepSeek guide, from sign-up to a test call.", "DeepSeek の手順ガイド付き。登録から接続テストまで。"))
                }
                if SetupGuide.showsPrice { PriceCard() }
            }
        } bottom: {
            GuidePrimaryButton(L("开始设置", "Set Up", "設定をはじめる")) { go(.provider) }
            GuideSecondaryButton(L("先跳过，只用打字", "Skip for now, just type", "あとで。入力だけ使う")) { finish() }
        }
    }

    // MARK: OB2 选服务商

    private var providerPage: some View {
        GuidePage {
            VStack(alignment: .leading, spacing: 20) {
                GuideTitle(L("选一个服务商", "Pick a provider", "サービスを選ぶ"),
                           subtitle: L("第一次用就选 DeepSeek，每一步都有图。", "New to this? Pick DeepSeek. Every step has a picture.", "はじめてなら DeepSeek を。手順はすべて図解付きです。"))
                VStack(spacing: 12) {
                    ForEach(Provider.shown) { item in
                        GuideProviderCard(provider: item, selected: provider == item) { provider = item }
                    }
                }
            }
            .padding(.top, 4)
        } bottom: {
            GuidePrimaryButton(L("继续", "Continue", "続ける")) { chooseProvider() }
        }
    }

    // MARK: OB7 完成

    private var done: some View {
        GuidePage {
            VStack(spacing: 20) {
                ZStack(alignment: .bottomTrailing) {
                    GuideAppMark(size: 80, corner: 40)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(hex: 0x30A46C)))
                        .overlay(Circle().stroke(GuideColor.card, lineWidth: 3))
                        .offset(x: 4, y: 4)
                }
                .padding(.top, 90)
                VStack(spacing: 10) {
                    Text(L("AI 已经连上", "AI is connected", "AI につながりました"))
                        .font(.system(size: 30, weight: .bold)).kerning(-0.4)
                        .foregroundStyle(GuideColor.text)
                    Text(ProviderName.of(store.settings.baseURL) + " · " + store.settings.model + "\n"
                         + L("最后把键盘加上，就能在任何 App 里用了", "Add the keyboard and you can use it in any app", "最後にキーボードを追加すれば、どの App でも使えます"))
                        .font(.system(size: 16)).lineSpacing(4)
                        .foregroundStyle(GuideColor.secondary)
                        .multilineTextAlignment(.center)
                }
                GuideCard {
                    GuideNumberRow(1, L("添加飞地输入法", "Add Enclave", "Enclave を追加"),
                                   L("系统设置 › 通用 › 键盘", "Settings › General › Keyboard", "設定 › 一般 › キーボード"))
                    GuideDivider()
                    GuideNumberRow(2, L("允许完全访问", "Allow Full Access", "フルアクセスを許可"),
                                   L("AI 联网时要用", "Needed to reach your AI", "AI への接続に必要"))
                }
            }
        } bottom: {
            GuidePrimaryButton(L("去添加键盘", "Add Keyboard", "キーボードを追加")) {
                finish()
                AppSettings.open()
            }
            GuideSecondaryButton(L("稍后", "Later", "あとで")) { finish() }
        }
    }

    // MARK: 跳转

    private func go(_ next: SetupGuidePage) {
        history.append(page)
        page = next
    }

    private func back() {
        guard let previous = history.popLast() else { return }
        page = previous
    }

    /// 走完或跳过：记下看过，关掉引导。
    private func finish() {
        SetupGuide.seen = true
        router.setupGuide = nil
    }

    /// 选 DeepSeek 走教程；其他服务商填好预设，进接口设置页。
    private func chooseProvider() {
        if let preset = provider.preset {
            store.settings.baseURL = preset.baseURL
            store.settings.model = preset.model
        }
        if provider == .deepseek {
            go(.step(1))
        } else {
            finish()
            router.openModel()
        }
    }
}

// MARK: - OB3–OB6 DeepSeek 教程

private struct GuideStepView: View {
    let step: Int
    let next: () -> Void
    @ObservedObject var store: AppStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        GuidePage {
            VStack(alignment: .leading, spacing: 20) {
                progress
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(GuideColor.text)
                if step < 4 {
                    GuideIllustration(step: step)
                    GuideNumberedList(items: items)
                    if step == 2 && SetupGuide.showsPrice { PriceCard() }
                    linkButton
                } else {
                    GuideKeyStep(store: store)
                }
            }
        } bottom: {
            if step < 4 {
                GuidePrimaryButton(L("下一步", "Next", "次へ"), action: next)
            } else {
                GuidePrimaryButton(L("完成", "Done", "完了"), enabled: store.test.isSuccess, action: next)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L("DeepSeek 教程", "DeepSeek guide", "DeepSeek ガイド"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GuideColor.chipText)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(GuideColor.chipFill))
                Text("\(step) / 4").font(.system(size: 13, weight: .medium)).foregroundStyle(GuideColor.secondary)
            }
            HStack(spacing: 5) {
                ForEach(1...4, id: \.self) { index in
                    Capsule().fill(index <= step ? GuideColor.purple : GuideColor.progressOff).frame(height: 4)
                }
            }
        }
    }

    private var title: String {
        switch step {
        case 1: return L("注册并登录", "Sign up and sign in", "登録してログイン")
        case 2: return L("充一点钱", "Add a little credit", "少しチャージする")
        case 3: return L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー")
        default: return L("粘贴 Key，测一下", "Paste the key and test", "キーを貼り付けてテスト")
        }
    }

    private var items: [String] {
        switch step {
        case 1: return [L("在 Safari 里打开 DeepSeek 开放平台", "Open the DeepSeek Platform in Safari", "Safari で DeepSeek Platform を開く"),
                        L("手机号或邮箱收验证码，第一次登录就是注册", "Get a code by phone or email. Your first sign-in creates the account", "電話番号かメールでコードを受け取る。初回ログインで登録完了"),
                        L("登录好了回到这里", "Come back here once you're signed in", "ログインしたらここに戻る")]
        case 2: return [L("左边点「充值」", "Tap Top up on the left", "左の「Top up」をタップ"),
                        L("充最少的金额就行，用支付宝或微信付", "The smallest amount is enough", "最小金額で十分です")]
        default: return [L("左边点「API keys」", "Tap API keys on the left", "左の「API keys」をタップ"),
                         L("点「创建 API key」，名字填「飞地输入法」", "Tap Create API key and name it Enclave", "「Create API key」で名前を Enclave に"),
                         L("点「复制」。Key 只显示这一次", "Tap Copy. The key is shown only once", "「Copy」をタップ。キーは一度しか表示されません")]
        }
    }

    private var link: (title: String, url: String) {
        switch step {
        case 1: return (L("打开 platform.deepseek.com", "Open platform.deepseek.com", "platform.deepseek.com を開く"), "https://platform.deepseek.com")
        case 2: return (L("打开充值页", "Open Top up", "チャージページを開く"), "https://platform.deepseek.com/top_up")
        default: return (L("打开 API keys 页", "Open API keys", "API keys ページを開く"), "https://platform.deepseek.com/api_keys")
        }
    }

    private var linkButton: some View {
        Button {
            if let url = URL(string: link.url) { openURL(url) }
        } label: {
            HStack(spacing: 6) {
                Text(link.title).font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.up.forward.square").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(GuideColor.purple)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(GuideColor.card))
            .overlay(Capsule().stroke(GuideColor.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// OB6：粘贴 Key（写进钥匙串），地址和模型已经填好，粘贴后自动测试连接。
private struct GuideKeyStep: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GuideCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("API Key").font(.system(size: 15, weight: .semibold)).foregroundStyle(GuideColor.text)
                        Spacer()
                        Text(L("存在钥匙串里", "Saved in Keychain", "キーチェーンに保存")).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(masked)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(store.apiKey.isEmpty ? GuideColor.secondary : GuideColor.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.field))
                        Button { paste() } label: {
                            Label(L("粘贴", "Paste", "貼り付け"), systemImage: "doc.on.clipboard")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(.systemBackground))
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary))
                        }
                        .buttonStyle(.plain)
                    }
                    (Text(L("地址 ", "URL ", "URL ")) + Text("api.deepseek.com").bold()
                     + Text(L("　模型 ", "   Model ", "　モデル ")) + Text(store.settings.model).bold())
                        .font(.system(size: 12.5))
                        .foregroundStyle(GuideColor.secondary)
                }
                .padding(16)
            }
            if store.test != .idle { result }
        }
        // 直接跳到这一步（比如 -setupGuide deepseek）时还没套 DeepSeek 预设，补上。
        .onAppear {
            if store.settings.baseURL.isEmpty, let preset = Provider.deepseek.preset {
                store.settings.baseURL = preset.baseURL
                store.settings.model = preset.model
            }
        }
    }

    /// sk-7f3a••••••••c21e
    private var masked: String {
        let key = store.apiKey
        guard key.count > 10 else { return key.isEmpty ? "sk-…" : String(repeating: "•", count: key.count) }
        return String(key.prefix(6)) + String(repeating: "•", count: 10) + String(key.suffix(4))
    }

    private func paste() {
        #if DEBUG
        // 模拟器里点不到系统的粘贴授权框：-guideKey <值> 直接当作剪贴板内容。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-guideKey"), args.indices.contains(i + 1) {
            store.apiKey = args[i + 1]
            // sk-fake-success：不联网，直接显示成功卡片，方便截图。
            if args[i + 1] == "sk-fake-success" {
                store.fakeTestSuccess()
            } else {
                Task { await store.runTest() }
            }
            return
        }
        #endif
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        store.apiKey = text
        Task { await store.runTest() }
    }

    @ViewBuilder
    private var result: some View {
        let ok = store.test.isSuccess
        HStack(spacing: 12) {
            Group {
                if store.test == .running {
                    ProgressView()
                } else {
                    Image(systemName: ok ? "checkmark" : "exclamationmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(ok ? Color(hex: 0x30A46C) : Color(hex: 0xFF3B30)))
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(resultTitle).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GuideColor.text)
                if let detail = resultDetail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if store.test != .running {
                Button(L("重新测试", "Test again", "再テスト")) { Task { await store.runTest() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GuideColor.purple)
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(ok || store.test == .running ? GuideColor.card : Color(hex: 0xFF3B30).opacity(0.10)))
    }

    private var resultTitle: String {
        switch store.test {
        case .running: return L("正在测试…", "Testing…", "テスト中…")
        case .success: return L("连接正常", "Connected", "接続できました")
        default: return L("没连上", "Couldn't connect", "接続できませんでした")
        }
    }

    private var resultDetail: String? {
        switch store.test {
        case .success(_, let seconds):
            let text = String(format: "%.1f", seconds)
            return L("模型回复用了 \(text) 秒", "The model replied in \(text) s", "モデルの応答 \(text) 秒")
        case .failure(let message):
            switch store.testFailure {
            case .unauthorized: return L("Key 不对，回第 3 步重新复制", "The key is wrong. Go back to step 3 and copy it again", "キーが正しくありません。手順 3 に戻ってコピーし直してください")
            case .noBalance: return L("余额不足，回第 2 步充值", "Not enough credit. Go back to step 2 to top up", "残高が足りません。手順 2 に戻ってチャージしてください")
            case .network: return L("网络不通，检查一下网络再试", "No network. Check your connection and try again", "ネットワークにつながりません。接続を確認して再試行してください")
            default: return message
            }
        default: return nil
        }
    }
}

extension AppStore.TestState {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - 示意图：浅紫展台里一个假的 Safari 页面（不放真实截图）

private struct GuideIllustration: View {
    @Environment(\.colorScheme) private var colorScheme
    let step: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill").font(.system(size: 9))
                Text("platform.deepseek.com").font(.system(size: 12))
            }
            .foregroundStyle(GuideColor.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(GuideColor.field)
            Group {
                if step == 1 { login } else { console }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
        }
        .background(GuideColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(
            colorScheme == .dark
                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A2160), Color(hex: 0x1C1C1E)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xEAE6FF), Color(hex: 0xF4F2FF), Color(hex: 0xFBFAFF)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.9))))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var login: some View {
        VStack(spacing: 8) {
            Text(L("登录 DeepSeek 开放平台", "Sign in to DeepSeek Platform", "DeepSeek Platform にログイン"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(GuideColor.text)
            fakeField(L("手机号 / 邮箱", "Phone / email", "電話 / メール"))
            fakeField(L("验证码", "Code", "コード"))
            highlighted(1) {
                Text(L("登录 / 注册", "Sign in / Sign up", "ログイン / 登録"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 150, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x4D6BFE)))
            }
        }
        .padding(.horizontal, 30)
    }

    private var console: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                sideItem(L("用量信息", "Usage", "使用量"), marked: false)
                sideItem("API keys", marked: step == 3)
                sideItem(L("充值", "Top up", "Top up"), marked: step == 2)
                sideItem(L("接口文档", "Docs", "Docs"), marked: false)
            }
            .padding(12)
            .frame(width: 96, alignment: .leading)
            Rectangle().fill(GuideColor.divider).frame(width: 1)
            VStack(alignment: .leading, spacing: 10) {
                if step == 2 { topUp } else { keys }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topUp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("充值", "Top up", "Top up")).font(.system(size: 13, weight: .semibold)).foregroundStyle(GuideColor.text)
            HStack(spacing: 6) {
                ForEach(["¥10", "¥50", "¥100"], id: \.self) { amount in
                    Text(amount).font(.system(size: 11)).foregroundStyle(GuideColor.text)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(amount == "¥10" ? Color(hex: 0x4D6BFE) : GuideColor.divider))
                }
            }
            Text(L("去支付", "Pay", "支払う")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x4D6BFE)))
        }
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API keys").font(.system(size: 13, weight: .semibold)).foregroundStyle(GuideColor.text)
            highlighted(2) {
                Text(L("创建 API key", "Create API key", "Create API key")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x4D6BFE)))
            }
            HStack(spacing: 6) {
                Text("sk-7f3a••••c21e").font(.system(size: 10, design: .monospaced)).foregroundStyle(GuideColor.text)
                    .padding(.horizontal, 6).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(GuideColor.field))
                highlighted(3) {
                    Text(L("复制", "Copy", "Copy")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x4D6BFE))
                        .padding(.horizontal, 7).frame(height: 22)
                }
            }
        }
    }

    private func sideItem(_ title: String, marked: Bool) -> some View {
        Group {
            if marked {
                highlighted(1) {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x4D6BFE))
                        .padding(.horizontal, 6).frame(height: 22)
                }
            } else {
                Text(title).font(.system(size: 11)).foregroundStyle(GuideColor.secondary).frame(height: 22)
            }
        }
    }

    private func fakeField(_ placeholder: String) -> some View {
        Text(placeholder).font(.system(size: 11)).foregroundStyle(GuideColor.secondary)
            .padding(.horizontal, 8)
            .frame(width: 150, height: 24, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(GuideColor.divider))
    }

    /// 要点的地方：紫色描边 + 右上角紫色编号圆点。
    private func highlighted<Content: View>(_ number: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(GuideColor.purple, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(GuideColor.purple))
                    .offset(x: 9, y: -9)
            }
    }
}

// MARK: - 共用部件

/// 页面：可滚动的内容 + 底部按钮。
private struct GuidePage<Content: View, Bottom: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            VStack(spacing: 6) { bottom }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }
}

/// 说明、选服务商、完成页顶部的淡紫光晕；教程页纯底色。
private struct GuideBackground: View {
    let glow: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GuideColor.page
                if glow {
                    let colors: [Color] = scheme == .dark
                        ? [Color(hex: 0x2A2160), .black]
                        : [Color(hex: 0xE4DEFF), Color(hex: 0xF1EEFC), Color(hex: 0xF6F5FA)]
                    EllipticalGradient(colors: colors, center: UnitPoint(x: 0.5, y: -0.08),
                                       startRadiusFraction: 0, endRadiusFraction: 0.7)
                        .frame(width: proxy.size.width * 1.3, height: proxy.size.height * 0.55 * 2)
                        .position(x: proxy.size.width / 2, y: -proxy.size.height * 0.08)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct GuideTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .bold)).kerning(-0.4).lineSpacing(3)
                .foregroundStyle(GuideColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 16)).lineSpacing(4)
                .foregroundStyle(GuideColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 品牌渐变圆角方块（或圆）+ 黄色四角星。
private struct GuideAppMark: View {
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x8A7BFF), Color(hex: 0x5B4BE8), Color(hex: 0x3F2FC4)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "sparkle").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color(hex: 0xFFE9A8)))
            .shadow(color: GuideColor.purple.opacity(0.3), radius: 14, y: 8)
    }
}

private struct GuideCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GuideColor.card)
                .shadow(color: Color(hex: 0x14121F).opacity(0.04), radius: 1, y: 1)
                .shadow(color: Color(hex: 0x3C28A0).opacity(0.07), radius: 14, y: 10))
    }
}

private struct GuideDivider: View {
    var body: some View {
        Rectangle().fill(GuideColor.divider).frame(height: 1).padding(.leading, 64)
    }
}

/// 卡片里的一行：34pt 浅色方块 + 线条图标，标题 + 灰字。
private struct GuideRow: View {
    let icon: String
    let color: Color
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GuideColor.text)
                if let detail {
                    Text(detail).font(.system(size: 13.5)).foregroundStyle(GuideColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// 「1 元可调用约 500 次」（只在中国大陆店面显示）。
private struct PriceCard: View {
    var body: some View {
        GuideCard {
            GuideRow(icon: "yensign.circle", color: Color(hex: 0xD97706), title: "1 元可调用约 500 次")
        }
    }
}

private struct GuideNumberRow: View {
    let number: Int
    let title: String
    let detail: String

    init(_ number: Int, _ title: String, _ detail: String) {
        self.number = number
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)").font(.system(size: 14, weight: .bold)).foregroundStyle(GuideColor.chipText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(GuideColor.chipFill))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GuideColor.text)
                Text(detail).font(.system(size: 13.5)).foregroundStyle(GuideColor.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct GuideNumberedList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(GuideColor.purple)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(GuideColor.purple.opacity(0.5), lineWidth: 1.5))
                    Text(item).font(.system(size: 15.5)).foregroundStyle(GuideColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }
        }
    }
}

/// 服务商卡片：渐变字母方块 + 名字 + 灰字说明 + 单选圈；选中描紫边。
private struct GuideProviderCard: View {
    let provider: Provider
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(letter).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(gradient))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(GuideColor.text)
                        if provider == .deepseek {
                            Text(L("推荐", "Recommended", "おすすめ")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 7).frame(height: 18)
                                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x7B6BFA), Color(hex: 0x4A3BD6)], startPoint: .leading, endPoint: .trailing)))
                        }
                    }
                    Text(detail).font(.system(size: 13)).foregroundStyle(GuideColor.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(selected ? GuideColor.purple : GuideColor.divider, lineWidth: 1.5)
                    if selected {
                        Circle().fill(GuideColor.purple)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GuideColor.card)
                .shadow(color: Color(hex: 0x14121F).opacity(0.04), radius: 1, y: 1)
                .shadow(color: Color(hex: 0x3C28A0).opacity(0.07), radius: 14, y: 10)
                .shadow(color: Color(hex: 0x5B4BE8).opacity(selected ? 0.16 : 0), radius: 14, y: 10))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? GuideColor.purple : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var name: String {
        provider == .custom ? L("其他服务商", "Other provider", "その他のサービス") : provider.title
    }

    private var letter: String {
        switch provider {
        case .deepseek: return "D"
        case .openai: return "O"
        case .kimi: return "K"
        case .qwen: return L("通", "Q", "Q")
        case .glm: return "Z"
        case .ollama: return "O"
        case .custom: return "+"
        }
    }

    private var gradient: LinearGradient {
        let colors: [Color]
        switch provider {
        case .deepseek: colors = [Color(hex: 0x6A7DFF), Color(hex: 0x4D6BFE)]
        case .qwen: colors = [Color(hex: 0x8A6BFF), Color(hex: 0x5B4BE8)]
        case .kimi: colors = [Color(hex: 0x2B2B33), Color(hex: 0x0B0B12)]
        case .glm: colors = [Color(hex: 0x4F7BFF), Color(hex: 0x2D55E0)]
        case .openai, .ollama: colors = [Color(hex: 0x3A3A3C), Color(hex: 0x111111)]
        case .custom: colors = [Color(hex: 0xC7C2DD), Color(hex: 0xA39DBE)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var detail: String {
        switch provider {
        case .deepseek:
            return SetupGuide.showsPrice ? "国内直接用 · 1 元可调用约 500 次" : L("国内直接用", "Cheap and fast", "安くて速い")
        case .qwen: return L("阿里云百炼账号", "Alibaba Cloud Model Studio account", "Alibaba Cloud Model Studio のアカウント")
        case .kimi: return L("月之暗面开放平台账号", "Moonshot AI platform account", "Moonshot AI のアカウント")
        case .glm: return L("智谱开放平台账号", "Zhipu / Z.ai platform account", "Zhipu / Z.ai のアカウント")
        case .openai: return L("OpenAI 账号", "OpenAI account", "OpenAI のアカウント")
        case .ollama: return L("在自己电脑上跑模型", "Run a model on your own computer", "自分のパソコンでモデルを動かす")
        case .custom: return L("填 API 地址、模型名和 Key", "Enter the API URL, model and key", "API の URL、モデル名、キーを入力")
        }
    }
}

/// 主按钮：高 54、圆角 16，135° 紫色渐变，白字。
struct GuidePrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
                    enabled
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x7B6BFA), Color(hex: 0x5B4BE8), Color(hex: 0x4A3BD6)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color(.systemGray3))))
                .shadow(color: Color(hex: 0x5B4BE8).opacity(enabled ? 0.32 : 0), radius: 12, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct GuideSecondaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15.5)).foregroundStyle(GuideColor.secondary)
                .frame(maxWidth: .infinity).frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 设置向导（设置 › 设置向导，GD2–GD4）

/// 添加键盘、允许完全访问、连上 AI 三步，和首页 OnboardingSteps 用同一份完成状态。
struct SetupWizardView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var deployer = RimeDeployer.shared
    /// 从系统设置回来时重新读一遍键盘状态。
    @State private var refresh = UUID()

    private static let green = Color(hex: 0x2BB673)

    var body: some View {
        let done = [Readiness.keyboardAdded, Readiness.fullAccess == true, aiReady]
        let remaining = done.filter { !$0 }.count
        let current = done.firstIndex(of: false)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GuideTitle(L("设置向导", "Setup Guide", "設定ガイド"),
                           subtitle: remaining == 0
                               ? L("都设置好了，在任何 App 里切到飞地输入法就能用 AI。", "All set. Switch to Enclave in any app to use AI.", "設定完了。どの App でも Enclave に切り替えれば AI が使えます。")
                               : L("三步做完，就能在任何 App 里用 AI。打字现在就能用。", "Finish three steps to use AI in any app. You can already type.", "3 ステップで、どの App でも AI が使えます。入力はすぐに使えます。"))
                progress(done: done, remaining: remaining)
                    .padding(.top, 22)
                GuideCard {
                    stepRow(0, done: done[0], current: current == 0,
                            title: L("添加飞地输入法", "Add the Enclave keyboard", "Enclave キーボードを追加"),
                            detail: done[0] ? L("已添加", "Added", "追加済み")
                                : L("系统设置 › 通用 › 键盘 › 添加新键盘，选飞地输入法", "Settings › General › Keyboard › Add New Keyboard, then choose Enclave", "設定 › 一般 › キーボード › 新しいキーボードを追加 で Enclave を選択"))
                    stepDivider
                    stepRow(1, done: done[1], current: current == 1,
                            title: L("允许完全访问", "Allow Full Access", "フルアクセスを許可"),
                            detail: done[1] ? L("已打开", "On", "オン")
                                : fullAccessOff ? L("键盘上次出现时还没打开。AI 要联网才能用。", "It was still off the last time the keyboard appeared. AI needs network access.", "前回キーボードを表示したときはオフでした。AI には通信が必要です。")
                                : L("AI 要联网才能用。用一次键盘后这里会自动打勾。", "AI needs network access. This gets checked after you use the keyboard once.", "AI には通信が必要です。キーボードを一度使うと自動でチェックが付きます。"),
                            warns: !done[1] && fullAccessOff) {
                        if !done[1] {
                            pill(L("打开系统设置", "Open Settings", "設定を開く"), prominent: current == 1) { AppSettings.open() }
                        }
                    }
                    stepDivider
                    stepRow(2, done: done[2], current: current == 2,
                            title: L("连上 AI", "Connect AI", "AI を接続"),
                            detail: done[2] || testFailed ? aiSummary
                                : L("填你自己的 API Key，跟着教程大约 3 分钟。", "Add your own API key. About 3 minutes with the guide.", "自分の API キーを入れます。ガイドに沿って約 3 分。"),
                            warns: testFailed) {
                        if testFailed {
                            HStack(spacing: 8) {
                                pill(store.test == .running ? L("测试中…", "Testing…", "テスト中…") : L("重新测试", "Test Again", "再テスト"),
                                     prominent: current == 2) { Task { await store.runTest() } }
                                    .disabled(store.test == .running)
                                pill(L("重新设置 AI", "Set Up AI Again", "AI を設定し直す"), prominent: false) { openGuide() }
                            }
                        } else if done[2] {
                            pill(L("重新设置 AI", "Set Up AI Again", "AI を設定し直す"), prominent: false) { openGuide() }
                        } else {
                            HStack(spacing: 8) {
                                pill(L("跟着教程设置", "Follow the Guide", "ガイドで設定"), prominent: current == 2) { openGuide() }
                                pill(L("已有 Key", "I Have a Key", "キーがある"), prominent: false) { router.openModel() }
                            }
                        }
                    }
                }
                .padding(.top, 16)
                if !done[1] && fullAccessOff {
                    Text(L("系统设置 › 飞地输入法 › 键盘，打开「允许完全访问」。用一次键盘后这里会自动打勾。",
                           "Settings › Enclave › Keyboards, then turn on Allow Full Access. This gets checked after you use the keyboard once.",
                           "設定 › Enclave › キーボード で「フルアクセスを許可」をオンにします。キーボードを一度使うと自動でチェックが付きます。"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(GuideColor.secondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 12)
                }
                if deployer.state != .done && (deployer.state != .idle || deployer.needsDeploy) {
                    DeployCard().padding(.top, 16)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .id(refresh)
        }
        .background(GuideBackground(glow: true))
        // 导航栏透明、不写标题，大标题在页面里。
        .navigationTitle(L("设置向导", "Setup Guide", "設定ガイド"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { if $0 == .active { refresh = UUID() } }
    }

    private var fullAccessOff: Bool { Readiness.fullAccess == false }

    /// 配好了就算完成；只有测过并且失败才算没完成（和首页「AI 还没连上」卡一致）。
    private var aiReady: Bool { store.settings.isConfigured && store.lastTestOK != false }
    private var testFailed: Bool { store.settings.isConfigured && store.lastTestOK == false }

    private var stepDivider: some View {
        Rectangle().fill(GuideColor.divider).frame(height: 1).padding(.horizontal, 18)
    }

    /// 「DeepSeek · deepseek-flash · 连接正常」
    private var aiSummary: String {
        let state: String
        switch store.lastTestOK {
        case true?: state = L("连接正常", "Connected", "接続 OK")
        case false?: state = L("上次测试失败", "Last test failed", "前回のテストは失敗")
        case nil: state = L("还没测试", "Not tested", "未テスト")
        }
        return [ProviderName.of(store.settings.baseURL), store.settings.model, state].joined(separator: " · ")
    }

    /// 从选服务商开始，已有的 Key 不动。
    private func openGuide() {
        if router.privacyAgreed { router.setupGuide = .provider } else { router.settingsPath.append(.privacy) }
    }

    private func progress(done: [Bool], remaining: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(remaining == 0 ? L("三步都做完了", "All three steps done", "3 ステップ完了") : L("还差 \(remaining) 步", "\(remaining) left", "あと \(remaining) ステップ"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(remaining == 0 ? Self.green : GuideColor.chipText)
            HStack(spacing: 5) {
                // 哪一步做完哪一段上色，不按顺序填。
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(remaining == 0 ? Self.green : done[i] ? GuideColor.purple : GuideColor.progressOff)
                        .frame(height: 4)
                }
            }
        }
    }

    private func stepRow(_ index: Int, done: Bool, current: Bool, title: String, detail: String, warns: Bool = false) -> some View {
        stepRow(index, done: done, current: current, title: title, detail: detail, warns: warns) { EmptyView() }
    }

    private func stepRow<Actions: View>(_ index: Int, done: Bool, current: Bool, title: String, detail: String, warns: Bool = false,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 14) {
            stepMark(index, done: done, current: current)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(done ? GuideColor.secondary : GuideColor.text)
                Text(detail).font(.system(size: 13.5))
                    .foregroundStyle(warns ? Color(hex: 0xD97706) : GuideColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions().padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func stepMark(_ index: Int, done: Bool, current: Bool) -> some View {
        Group {
            if done {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Circle().fill(Self.green))
            } else if current {
                Text("\(index + 1)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Circle().fill(GuideColor.purple))
                    .shadow(color: GuideColor.purple.opacity(0.35), radius: 8, y: 4)
            } else {
                Text("\(index + 1)").font(.system(size: 14, weight: .semibold)).foregroundStyle(GuideColor.secondary)
                    .frame(width: 28, height: 28).overlay(Circle().strokeBorder(GuideColor.divider, lineWidth: 1.5))
            }
        }
    }

    private func pill(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : GuideColor.chipText)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(prominent
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x7B6BFA), Color(hex: 0x5B4BE8), Color(hex: 0x4A3BD6)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(GuideColor.chipFill)))
                .shadow(color: GuideColor.purple.opacity(prominent ? 0.3 : 0), radius: 8, y: 5)
        }
        .buttonStyle(.plain)
    }
}
