import SwiftUI

// MARK: - 首次配置：「设置飞地输入法」三步（T95，design/onboard-v2 OG4，取代欢迎页四步 WL1–WL9）

/// 三步各自做到哪了：添加输入法、完全访问、连接 AI（润色和问答共用一个接口）。
/// 完全访问 App 读不到，键盘打开时写共享标记（KeyboardStatus.fullAccess），App 回前台读到才打勾；
/// 去过系统设置还没读到时算「等确认」，不挡第 3 步。
enum WelcomeSetup {
    private static let fullAccessVisitedKey = "welcome.fullAccessVisited"
    private static let answerDecidedKey = "welcome.answerDecided"
    private static let migratedKey = "welcome.migrated"

    /// 点过「去设置中开启」。
    static var fullAccessVisited: Bool {
        get { SharedStorage.defaults.bool(forKey: fullAccessVisitedKey) }
        set { SharedStorage.defaults.set(newValue, forKey: fullAccessVisitedKey) }
    }

    /// 问答怎么配已经定了：T95 起润色测通就算（问答默认和润色用同一个）。
    static var answerDecided: Bool {
        get { SharedStorage.defaults.bool(forKey: answerDecidedKey) }
        set { SharedStorage.defaults.set(newValue, forKey: answerDecidedKey) }
    }

    /// 0.94 及以前已经配好润色接口的：问答一直跟润色走，算定过。只做一次。
    static func migrate(configured: Bool) {
        guard !SharedStorage.defaults.bool(forKey: migratedKey) else { return }
        if configured { answerDecided = true }
        SharedStorage.defaults.set(true, forKey: migratedKey)
    }

    enum StepState: Equatable { case todo, current, pending, done }

    /// 三步的完成情况。没同意隐私政策（只用基础打字）时只看前两步。
    struct Progress: Equatable {
        var keyboard: Bool
        var fullAccess: Bool
        var fullAccessPending: Bool
        /// 连接 AI：润色接口配好且测通过。
        var ai: Bool

        @MainActor
        init(store: AppStore) {
            keyboard = Readiness.keyboardAdded
            fullAccess = Readiness.fullAccess == true
            fullAccessPending = !fullAccess && WelcomeSetup.fullAccessVisited
            ai = store.settings.isConfigured && store.lastTestOK == true
        }

        var done: [Bool] { [keyboard, fullAccess, ai] }

        /// 现在做哪一步：第一个没做完、也不在等确认的；都没有时为 nil。
        var current: Int? {
            done.indices.first { !done[$0] && !($0 == 1 && fullAccessPending) }
        }

        func state(_ index: Int) -> StepState {
            if done[index] { return .done }
            if index == 1 && fullAccessPending { return .pending }
            return current == index ? .current : .todo
        }

        /// 首页换回摘要：三步都好；只用基础打字的只看前两步。
        func allDone(privacyAgreed: Bool) -> Bool {
            privacyAgreed ? !done.contains(false) : keyboard && fullAccess
        }
    }
}

/// 「设置飞地输入法」：引导里（演示完「开始设置」进来，右上「跳过」由外面的顶栏给）、设置 › 首次设置、
/// 首页（没设置好时整页显示，没有跳过和底下那行文字按钮）共用。
struct WelcomeSetupView: View {
    /// 在引导里：底部多一行「暂时跳过，只用打字」，三步都好时显示「开始使用」。
    var inGuide: Bool
    /// 引导里的跳转：选服务商、关掉引导。首页里为 nil，改用 router.setupGuide 打开引导。
    var openGuidePage: ((SetupGuidePage) -> Void)?
    var finish: () -> Void = {}

    init(inGuide: Bool, openGuidePage: ((SetupGuidePage) -> Void)? = nil, finish: @escaping () -> Void = {}) {
        self.inGuide = inGuide
        self.openGuidePage = openGuidePage
        self.finish = finish
    }

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 画在页面上的进度：从系统设置回来、测通以后换成新的，用弹簧收起这步、展开下一步。
    @State private var snapshot: WelcomeSetup.Progress?
    @State private var shown = false

    /// 首页只用基础打字时只显示前两步（第 3 步要联网，没同意隐私政策用不了）。
    private var stepCount: Int { router.privacyAgreed || inGuide ? 3 : 2 }

    var body: some View {
        let progress = snapshot ?? WelcomeSetup.Progress(store: store)
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Text(L("设置飞地输入法", "Set Up Enclave", "Enclave を設定"))
                            .font(.system(size: 22, weight: .bold))
                        Text(L("只需三步。打字无需设置，AI 用你自己的接口。",
                               "Just three steps. Typing needs no setup; AI uses your own API.",
                               "3 ステップだけ。入力は設定不要、AI は自分の API を使います。"))
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, inGuide ? 4 : 40)
                    .tourEntrance(0, shown)
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(spacing: 0) {
                            ForEach(0..<stepCount, id: \.self) { index in
                                if index > 0 { Divider().padding(.leading, 56) }
                                row(index, progress)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourUI.group))
                        Text(L("进度会保留，随时回来继续。", "Your progress is saved. Come back any time.", "進み具合は保存されます。いつでも続きからどうぞ。"))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 24)
                    .tourEntrance(1, shown)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: PadWidth.content)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 4) { buttons(progress) }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: PadWidth.content)
                .tourEntrance(2, shown)
        }
        .background(TourUI.page.ignoresSafeArea())
        .onAppear {
            snapshot = WelcomeSetup.Progress(store: store)
            DispatchQueue.main.async { shown = true }
        }
        .onChange(of: scenePhase) { if $0 == .active { update() } }
        .onReceive(store.objectWillChange) { _ in DispatchQueue.main.async { update() } }
    }

    /// 读一遍现在的进度：变了就用弹簧换（做完那步编号弹出绿勾、说明收起，下一步展开）。
    private func update() {
        let next = WelcomeSetup.Progress(store: store)
        guard next != snapshot else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)) { snapshot = next }
    }

    // MARK: 一步一行

    private func title(_ index: Int) -> String {
        switch index {
        case 0: return L("添加飞地输入法", "Add Enclave", "Enclave を追加")
        case 1: return L("允许完全访问", "Allow Full Access", "フルアクセスを許可")
        default: return L("连接 AI", "Connect AI", "AI を接続")
        }
    }

    /// 当前那步展开的说明。
    private func detail(_ index: Int) -> String {
        switch index {
        case 0:
            return L("前往 设置 › 通用 › 键盘 › 键盘 › 添加新键盘，选择「\(Loc.nameInSettings)」。",
                     "Go to Settings › General › Keyboard › Keyboards › Add New Keyboard, then choose \(Loc.nameInSettings).",
                     "設定 › 一般 › キーボード › キーボード › 新しいキーボードを追加 で「\(Loc.nameInSettings)」を選びます。")
        case 1:
            return L("在 设置 › \(Loc.nameInSettings) › 键盘 中开启。AI 联网时需要它，打字不受影响。",
                     "Turn it on in Settings › \(Loc.nameInSettings) › Keyboards. AI needs it to go online; typing works either way.",
                     "設定 › \(Loc.nameInSettings) › キーボード でオンにします。AI の通信に必要で、入力には影響しません。")
        default:
            return L("选一家服务商，按教程取得 Key，粘贴后自动测试。润色和问答共用这一个。",
                     "Pick a provider, get a key with the guide, and paste it to test automatically. Polish and Q&A share it.",
                     "サービスを選び、ガイドに沿ってキーを取得して貼り付けると自動でテストします。整えると質問で共用します。")
        }
    }

    /// 做完的、等确认的：标题下一行灰字。
    private func doneDetail(_ index: Int, _ state: WelcomeSetup.StepState) -> String {
        switch index {
        case 0: return L("已添加", "Added", "追加済み")
        case 1:
            return state == .pending
                ? L("去过设置了？在任意 App 里用一次飞地输入法，这里会自动打勾",
                    "Been to Settings? Use Enclave once in any app and this gets checked",
                    "設定しましたか？どこかの App で Enclave を一度使うと、自動でチェックが付きます")
                : L("已开启", "On", "オン")
        default: return ProviderName.of(store.settings.baseURL) + " · " + store.settings.model
        }
    }

    /// 一行：编号（当前紫色实心、做完绿勾、等确认橙圈、没轮到灰色描边）+ 标题；当前那步展开说明和插图。
    private func row(_ index: Int, _ progress: WelcomeSetup.Progress) -> some View {
        let state = progress.state(index)
        return HStack(alignment: .top, spacing: 12) {
            SetupStepMark(number: index + 1, state: state)
            VStack(alignment: .leading, spacing: 4) {
                Text(title(index))
                    .font(.system(size: 17, weight: state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .todo ? Color.secondary : Color.primary)
                    .frame(minHeight: 28, alignment: .leading)
                if state == .done || state == .pending {
                    Text(doneDetail(index, state))
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                if state == .current {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(detail(index)).font(.system(size: 15)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if index == 2 {
                            Text(L("DeepSeek、Kimi、通义千问、智谱均有分步教程，约 3 分钟。",
                                   "DeepSeek, Kimi, Qwen and Zhipu have step-by-step guides, about 3 minutes.",
                                   "DeepSeek・Kimi・Qwen・Zhipu の手順ガイド付き、約 3 分。"))
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if store.settings.isConfigured && router.privacyAgreed { configBox }
                        } else {
                            WelcomeIllustration(step: index + 1)
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 已经填了地址和模型、还没测通（自己的模型、自定义地址，或上次测试失败）：地址、模型、Key 三行和测试结果。
    private var configBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            configLine(L("地址", "URL", "URL"), store.settings.baseURL)
            configLine(L("模型", "Model", "モデル"), store.settings.model)
            configLine("Key", store.apiKey.isEmpty ? L("（不需要）", "(none)", "（不要）") : maskedKey)
            switch store.test {
            case .running:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("正在测试…", "Testing…", "テスト中…"))
                }
                .font(.system(size: 13)).foregroundStyle(.secondary)
            case .success(_, let seconds):
                Label(L("连接正常 · \(String(format: "%.1f", seconds)) 秒", "Connected · \(String(format: "%.1f", seconds)) s", "接続 OK · \(String(format: "%.1f", seconds)) 秒"),
                      systemImage: "checkmark")
                    .font(.system(size: 13)).foregroundStyle(Color(.systemGreen))
            case .failure(let message):
                Text(message).font(.system(size: 13)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            case .idle:
                if store.lastTestOK == false {
                    Text(L("上次测试失败", "Last test failed", "前回のテストは失敗")).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.systemGroupedBackground)))
    }

    private func configLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Text(value).font(.system(size: 15)).foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
        }
    }

    private var maskedKey: String {
        let key = store.apiKey
        guard key.count > 10 else { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    // MARK: 底部按钮（文字跟着当前那步交叉淡化）

    @ViewBuilder
    private func buttons(_ progress: WelcomeSetup.Progress) -> some View {
        let current = progress.current.flatMap { $0 < stepCount ? $0 : nil }
        Group {
            switch current {
            case 0?:
                GuidePrimaryButton(L("去设置中添加", "Add in Settings", "設定で追加")) { AppSettings.open() }
                skipButton
            case 1?:
                GuidePrimaryButton(L("去设置中开启", "Turn On in Settings", "設定でオン")) {
                    WelcomeSetup.fullAccessVisited = true
                    AppSettings.open()
                }
                skipButton
            case 2?:
                if !router.privacyAgreed {
                    GuidePrimaryButton(L("先阅读并同意隐私政策", "Review the Privacy Policy First", "先にプライバシーポリシーを確認")) { openPrivacy() }
                } else if store.settings.isConfigured {
                    GuidePrimaryButton(store.test == .running ? L("测试中…", "Testing…", "テスト中…") : L("测试连接", "Test Connection", "接続をテスト"),
                                       enabled: store.test != .running) { Task { await store.runTest() } }
                    GuideSecondaryButton(L("改地址和模型", "Change URL and Model", "URL とモデルを変更")) { openAPI() }
                } else {
                    GuidePrimaryButton(L("选择服务商", "Choose a Provider", "サービスを選ぶ")) { open(.provider) }
                    GuideSecondaryButton(L("已有 Key 或自有模型", "I Have a Key or My Own Model", "キーがある・自分のモデル")) { openAPI() }
                }
            default:
                if inGuide {
                    GuidePrimaryButton(L("开始使用", "Start Using Enclave", "使いはじめる")) { finish() }
                }
            }
        }
        .id(current ?? -1)
        .transition(.opacity)
    }

    @ViewBuilder
    private var skipButton: some View {
        if inGuide {
            GuideSecondaryButton(L("暂时跳过，只用打字", "Skip for Now, Just Type", "あとで。入力だけ使う")) { finish() }
        }
    }

    /// 引导里在引导内翻页；首页打开引导到那一页。
    private func open(_ page: SetupGuidePage) {
        if let openGuidePage { openGuidePage(page) } else { router.setupGuide = page }
    }

    private func openAPI() {
        if inGuide { finish() }
        router.openModel(detail: true)
    }

    private func openPrivacy() {
        if inGuide { finish() }
        router.openSettings(.privacy)
    }
}

/// 一步前面的编号：当前紫色实心，做完绿勾（0.6 → 1 弹出、勾线 0.3 秒画出），等确认橙圈，没轮到灰色描边。
private struct SetupStepMark: View {
    let number: Int
    let state: WelcomeSetup.StepState

    var body: some View {
        ZStack {
            switch state {
            case .done:
                SetupCheckBadge()
                    .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity)
                        .animation(.spring(response: 0.36, dampingFraction: 0.6)))
            case .current:
                Text("\(number)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Circle().fill(TourUI.accent))
                    .transition(.opacity)
            case .pending:
                Text("\(number)").font(.system(size: 15, weight: .bold)).foregroundStyle(WelcomeColor.pendingText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(WelcomeColor.pendingFill))
                    .overlay(Circle().strokeBorder(WelcomeColor.pending, lineWidth: 1.5))
                    .transition(.opacity)
            case .todo:
                Text("\(number)").font(.system(size: 15)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color(.systemGray3), lineWidth: 1.5))
                    .transition(.opacity)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

/// 绿底白勾：勾线一笔画出。
private struct SetupCheckBadge: View {
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        Circle().fill(Color(.systemGreen))
            .overlay(
                TourCheckShape()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.4, height: size * 0.32))
            .frame(width: size, height: size)
            .onAppear {
                if reduceMotion { drawn = true } else { withAnimation(.easeOut(duration: 0.3).delay(0.12)) { drawn = true } }
            }
    }
}

// MARK: - 一切就绪（OG4 ⑨）：润色测通后进来

/// 大绿勾、「AI」一组（润色：服务商 · 模型，问答：与润色相同）、不能联网时组下一行脚注、「试试润色」。
/// 只有主按钮「开始使用」（前两步没做完时是「返回设置」），贴底；「去使用指引练习」11-26 去掉（对齐清单第 96 条，SO2）。
struct GuideReadyPage: View {
    @ObservedObject var store: AppStore
    /// 前两步做完了。
    let ready: Bool
    let primary: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var drawn = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color(.systemGreen))
                            TourCheckShape()
                                .trim(from: 0, to: drawn ? 1 : 0)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                                .frame(width: 28, height: 22)
                        }
                        .frame(width: 72, height: 72)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.4)
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.62), value: shown)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.36), value: drawn)
                        Text(L("一切就绪", "You're All Set", "準備完了"))
                            .font(.system(size: 22, weight: .bold))
                            .padding(.top, 6)
                            .tourEntrance(1, shown)
                        Text(L("在任何 App 中切换到飞地输入法，即可使用。", "Switch to Enclave in any app to start using it.", "どの App でも Enclave に切り替えれば使えます。"))
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .tourEntrance(2, shown)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    VStack(alignment: .leading, spacing: 8) {
                        header("AI")
                        VStack(spacing: 0) {
                            line(L("润色", "Polish", "整える"), ProviderName.of(store.settings.baseURL) + " · " + store.settings.model)
                            Divider().padding(.leading, 16)
                            line(L("问答", "Q&A", "質問"), answerValue)
                        }
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourUI.group))
                        if let note = offlineNote {
                            Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 28)
                    .tourEntrance(3, shown)
                    VStack(alignment: .leading, spacing: 8) {
                        header(L("试试润色", "Try Polish", "整えるを試す"))
                        TryPolishCard(store: store)
                    }
                    .padding(.top, 24)
                    .tourEntrance(4, shown)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: PadWidth.content)
                .frame(maxWidth: .infinity)
            }
            GuidePrimaryButton(ready ? L("开始使用", "Start Using Enclave", "使いはじめる") : L("返回设置", "Back to Setup", "設定に戻る"), action: primary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: PadWidth.content)
            .tourEntrance(5, shown)
        }
        .background(TourUI.page.ignoresSafeArea())
        .onAppear {
            DispatchQueue.main.async { shown = true }
            if reduceMotion {
                drawn = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drawn = true }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 16)
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 17))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 17)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    /// 问答：默认和润色共用，显示「与润色相同」；另配了的显示那一家。
    private var answerValue: String {
        guard store.settings.usesAnswerEndpoint else { return L("与润色相同", "Same as Polish", "整えると同じ") }
        return ProviderName.of(store.settings.answerBaseURL) + " · " + store.settings.answerModel
    }

    /// 问答和润色共用、润色那家不能联网时（例如 DeepSeek）的一行脚注；能联网的、自己的模型不写。
    private var offlineNote: String? {
        guard !store.settings.usesAnswerEndpoint else { return nil }
        let provider = Provider.detect(store.settings.baseURL)
        if provider == .custom || provider == .ollama || store.settings.searchProvider != nil { return nil }
        let name = provider.title
        return L("\(name) 不支持联网搜索。需要查询最新信息时，可在 接口和提示词 › 问答 改用千问、Kimi 或智谱。",
                 "\(name) can't search the web. For the latest information, switch Q&A to Qwen, Kimi or Zhipu under API & Prompts › Q&A.",
                 "\(name) はウェブ検索できません。最新情報が必要なら、API とプロンプト › 質問 で Qwen・Kimi・Zhipu に切り替えられます。")
    }
}

enum WelcomeColor {
    static let green = Color(hex: 0x2BB673)
    static let currentRow = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x5B4BE8).withAlphaComponent(0.18) : UIColor(hex: 0xF5F3FF) })
    static let pending = Color(hex: 0xE8A23A)
    static let pendingText = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF5B95C) : UIColor(hex: 0x9A5B00) })
    static let pendingFill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xE8A23A).withAlphaComponent(0.16) : UIColor(hex: 0xFFF6E6) })
    static let warnText = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF5B95C) : UIColor(hex: 0xB45309) })
    static let warnFill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xE8A23A).withAlphaComponent(0.16) : UIColor(hex: 0xFFF6E6) })
}

/// 第 1、2 步下面的教程插图（紫框 + 编号圆点，同引导页）：系统设置的键盘列表、两个开关。
struct WelcomeIllustration: View {
    let step: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "gearshape").font(.system(size: 11))
                Text(step == 1 ? L("设置 › 键盘 › 添加新键盘", "Settings › Keyboards › Add New Keyboard", "設定 › キーボード › 新しいキーボードを追加")
                               : L("设置 › \(Loc.nameInSettings) › 键盘", "Settings › \(Loc.nameInSettings) › Keyboards", "設定 › \(Loc.nameInSettings) › キーボード"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(GuideColor.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .overlay(alignment: .bottom) { Divider().padding(.horizontal, 14) }
            VStack(alignment: .leading, spacing: 8) {
                if step == 1 {
                    Text(L("第三方键盘", "Third-party keyboards", "他社製キーボード")).font(.system(size: 11)).foregroundStyle(GuideColor.secondary)
                    marked(1) { item(Loc.nameInSettings) }
                    Text(L("其他键盘…", "Other keyboards…", "その他のキーボード…")).font(.system(size: 12)).foregroundStyle(GuideColor.secondary)
                } else {
                    toggleRow(Loc.nameInSettings)
                    marked(2) { toggleRow(L("允许完全访问", "Allow Full Access", "フルアクセスを許可")) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 系统列表的样子（T95，OG4）：浅灰圆角底，不用渐变。
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.systemGroupedBackground)))
        .accessibilityHidden(true)
    }

    private func item(_ title: String) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(GuideColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).frame(height: 34)
    }

    private func toggleRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(GuideColor.text)
            Spacer()
            Capsule().fill(Color(.systemGreen)).frame(width: 34, height: 20)
                .overlay(alignment: .trailing) { Circle().fill(.white).frame(width: 16, height: 16).padding(2) }
        }
        .padding(.horizontal, 10).frame(height: 34)
    }

    /// 紫色描边 + 右上角编号圆点。
    private func marked<Content: View>(_ number: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TourUI.accent, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(TourUI.accent))
                    .offset(x: -40, y: -10)
            }
    }
}

// MARK: - 试试润色（一切就绪页里）

/// 预填一段口语原文，点「润色这句」才真的调用一次（不自动调）；成功上下分原文 / 润色后，失败一行红字和「再试一次」。
struct TryPolishCard: View {
    @ObservedObject var store: AppStore

    private static let sample = "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看"

    private enum Phase: Equatable { case idle, running, done(String, TimeInterval), failed(String) }
    @State private var phase: Phase = .idle

    init(store: AppStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch phase {
            case .done(let result, let seconds):
                block(L("原文", "Original", "原文"), Self.sample, primary: false)
                Divider()
                block(L("润色后", "Polished", "整えた後"), result, primary: true)
                Text(ProviderName.of(store.settings.baseURL) + " · " + L("\(String(format: "%.1f", seconds)) 秒", "\(String(format: "%.1f", seconds)) s", "\(String(format: "%.1f", seconds)) 秒"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            default:
                block(L("原文", "Original", "原文"), Self.sample, primary: true)
                if case .failed(let message) = phase {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { Task { await run() } } label: {
                    HStack(spacing: 6) {
                        if phase == .running { ProgressView().controlSize(.small) }
                        Text(phase == .running ? L("正在润色…", "Polishing…", "整え中…")
                             : phase == .idle ? L("润色这句", "Polish This", "これを整える") : L("再试一次", "Try Again", "もう一度"))
                    }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(TourUI.accentText)
                    .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .disabled(phase == .running)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourUI.group))
    }

    private func block(_ label: String, _ text: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 17)).foregroundStyle(primary ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run() async {
        guard PrivacyConsent.isAgreed else { return }
        phase = .running
        let start = Date()
        let client = LLMClient(settings: store.settings, apiKey: store.apiKey)
        var raw = ""
        do {
            for try await piece in client.stream(Prompts.polish(Self.sample, style: store.settings.selectedStyle)) { raw += piece }
            let text = ModelOutput.clean(raw)
            phase = text.isEmpty
                ? .failed(L("没试成功：连上了，但模型没有返回内容。", "Didn't work: connected, but the model returned nothing.", "うまくいきませんでした：接続できましたが、モデルから応答がありませんでした。"))
                : .done(text, Date().timeIntervalSince(start))
        } catch {
            let failure = LLMFailure.of(error)
            let provider = ProviderName.of(store.settings.baseURL)
            phase = .failed(L("没试成功：", "Didn't work: ", "うまくいきませんでした：") + failure.title(provider: provider)
                             + L("，", ". ", "。") + failure.note(provider: provider) + L("，键盘里也一样。", ". The keyboard works the same way.", "。キーボードでも同じです。"))
        }
    }
}
