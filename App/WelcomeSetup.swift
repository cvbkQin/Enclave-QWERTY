import SwiftUI

// MARK: - 首次配置：欢迎页四步（WL1–WL4、WL9，0.95 起取代首页的三张步骤卡）

/// 欢迎页四步各自做到哪了：添加输入法、完全访问、润色接口、问答接口。
/// 完全访问 App 读不到，键盘打开时写共享标记（KeyboardStatus.fullAccess），App 回前台读到才打勾；
/// 去过系统设置还没读到时算「等确认」，不挡后面的步骤。
enum WelcomeSetup {
    private static let fullAccessVisitedKey = "welcome.fullAccessVisited"
    private static let answerDecidedKey = "welcome.answerDecided"
    private static let migratedKey = "welcome.migrated"

    /// 点过「打开完全访问」。
    static var fullAccessVisited: Bool {
        get { SharedStorage.defaults.bool(forKey: fullAccessVisitedKey) }
        set { SharedStorage.defaults.set(newValue, forKey: fullAccessVisitedKey) }
    }

    /// 第 4 步选过「和润色用同一个」。另配了问答接口的看接口本身。
    static var answerDecided: Bool {
        get { SharedStorage.defaults.bool(forKey: answerDecidedKey) }
        set { SharedStorage.defaults.set(newValue, forKey: answerDecidedKey) }
    }

    /// 0.94 及以前已经配好润色接口的：问答一直跟润色走，第 4 步算做过，首页不突然变回欢迎页。只做一次。
    static func migrate(configured: Bool) {
        guard !SharedStorage.defaults.bool(forKey: migratedKey) else { return }
        if configured { answerDecided = true }
        SharedStorage.defaults.set(true, forKey: migratedKey)
    }

    enum StepState: Equatable { case todo, current, pending, done }

    /// 四步的完成情况。没同意隐私政策（只用基础打字）时只看前两步，接口两步不算。
    struct Progress {
        var keyboard: Bool
        var fullAccess: Bool
        var fullAccessPending: Bool
        var polish: Bool
        var answer: Bool

        @MainActor
        init(store: AppStore) {
            keyboard = Readiness.keyboardAdded
            fullAccess = Readiness.fullAccess == true
            fullAccessPending = !fullAccess && WelcomeSetup.fullAccessVisited
            polish = store.settings.isConfigured && store.lastTestOK == true
            answer = WelcomeSetup.answerDecided || (store.settings.usesAnswerEndpoint && !store.answerApiKey.isEmpty)
        }

        var done: [Bool] { [keyboard, fullAccess, polish, answer] }

        /// 现在做哪一步：第一个没做完、也不在等确认的；都没有时为 nil。
        var current: Int? {
            done.indices.first { !done[$0] && !($0 == 1 && fullAccessPending) }
        }

        func state(_ index: Int) -> StepState {
            if done[index] { return .done }
            if index == 1 && fullAccessPending { return .pending }
            return current == index ? .current : .todo
        }

        /// 首页换回摘要：四步都好；只用基础打字的只看前两步。
        func allDone(privacyAgreed: Bool) -> Bool {
            privacyAgreed ? !done.contains(false) : keyboard && fullAccess
        }
    }
}

/// 欢迎页：引导里（功能演示「开始设置」进来，右上跳过由外面的顶栏给）和首页（没设置好时整页显示，没有跳过）共用。
struct WelcomeSetupView: View {
    /// 在引导里：底部多一行「先跳过，只用打字」，四步都好时显示「开始使用」。
    var inGuide: Bool
    /// 引导里的跳转：教程、问答服务商、关掉引导。首页里为 nil，改用 router.setupGuide 打开引导。
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
    /// 从系统设置回来时重新读一遍键盘状态。
    @State private var refresh = UUID()

    var body: some View {
        let progress = WelcomeSetup.Progress(store: store)
        ZStack {
            if !inGuide { GuideBackground(glow: true) }
            GuidePage {
                VStack(alignment: .leading, spacing: 0) {
                    GuideAppMark(size: 52, corner: 15)
                        .padding(.top, inGuide ? 12 : 40)
                    GuideTitle(L("欢迎使用飞地输入法", "Welcome to Enclave", "Enclave へようこそ"),
                               subtitle: L("四步设置好，就能在任何 App 里用 AI。打字现在就能用。",
                                           "Four steps and you can use AI in any app. Typing works right now.",
                                           "4 ステップで、どの App でも AI が使えます。入力はすぐに使えます。"))
                        .padding(.top, 18)
                    progressBar(progress).padding(.top, 18)
                    GuideCard { steps(progress) }
                        .padding(.top, 16)
                    illustration(progress).padding(.top, 16)
                }
                .id(refresh)
            } bottom: {
                buttons(progress)
            }
        }
        .onChange(of: scenePhase) { if $0 == .active { refresh = UUID() } }
    }

    // MARK: 进度条：做完的段主色

    private func progressBar(_ progress: WelcomeSetup.Progress) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(progress.done[i] ? GuideColor.purple : GuideColor.progressOff).frame(height: 4)
            }
        }
    }

    // MARK: 四行

    @ViewBuilder
    private func steps(_ progress: WelcomeSetup.Progress) -> some View {
        VStack(spacing: 0) {
            row(0, progress, title: L("添加飞地输入法", "Add the Enclave keyboard", "Enclave キーボードを追加"),
                detail: progress.keyboard ? L("已添加", "Added", "追加済み")
                    : L("系统设置 › 通用 › 键盘 › 键盘 › 添加新键盘，选飞地输入法",
                        "Settings › General › Keyboard › Keyboards › Add New Keyboard, then choose Enclave",
                        "設定 › 一般 › キーボード › キーボード › 新しいキーボードを追加 で Enclave を選択"))
            divider
            row(1, progress, title: L("允许完全访问", "Allow Full Access", "フルアクセスを許可"),
                detail: progress.fullAccess ? L("已打开", "On", "オン")
                    : progress.fullAccessPending
                        ? L("去过设置了？在任意 App 里用一次飞地输入法，这里会自动打勾",
                            "Been to Settings? Use Enclave once in any app and this gets checked",
                            "設定しましたか？どこかの App で Enclave を一度使うと、自動でチェックが付きます")
                        : L("系统设置 › 飞地输入法 › 键盘，打开「允许完全访问」，AI 联网时要用",
                            "Settings › Enclave › Keyboards, turn on Allow Full Access. AI needs it to go online",
                            "設定 › Enclave › キーボード で「フルアクセスを許可」をオン。AI の通信に必要です"))
            divider
            row(2, progress, title: L("润色接口", "Polish API", "整える API"), detail: polishDetail(progress)) {
                if progress.state(2) == .current && store.settings.isConfigured { configBox }
            }
            divider
            row(3, progress, title: L("问答接口", "Answer API", "回答 API"), detail: answerDetail(progress)) {
                if progress.state(3) == .current { answerHint }
                if progress.state(3) == .done && inGuide {
                    Button { finish(); router.openAI(answer: true) } label: {
                        Text(L("可在 AI 页改", "Change on the AI tab", "AI タブで変更できます"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(GuideColor.chipText)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Capsule().fill(GuideColor.chipFill))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
    }

    private var divider: some View {
        Rectangle().fill(GuideColor.divider).frame(height: 1).padding(.horizontal, 12)
    }

    private func row(_ index: Int, _ progress: WelcomeSetup.Progress, title: String, detail: String) -> some View {
        row(index, progress, title: title, detail: detail) { EmptyView() }
    }

    /// 一行：编号圆（做完变绿勾、等确认是橙圈）+ 标题 + 灰字。当前步整行浅紫底并展开说明；没轮到的只显示标题。
    private func row<Extra: View>(_ index: Int, _ progress: WelcomeSetup.Progress, title: String, detail: String,
                                  @ViewBuilder extra: () -> Extra) -> some View {
        let state = progress.state(index)
        return HStack(alignment: .top, spacing: 14) {
            mark(index, state)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state == .done ? GuideColor.secondary : GuideColor.text)
                    .frame(minHeight: 28)
                if state != .todo {
                    Text(detail).font(.system(size: 13.5)).foregroundStyle(GuideColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                extra()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(state == .current ? WelcomeColor.currentRow : .clear))
    }

    private func mark(_ index: Int, _ state: WelcomeSetup.StepState) -> some View {
        Group {
            switch state {
            case .done:
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Circle().fill(WelcomeColor.green))
            case .current:
                Text("\(index + 1)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Circle().fill(GuideColor.purple))
                    .shadow(color: GuideColor.purple.opacity(0.35), radius: 8, y: 4)
            case .pending:
                Text("\(index + 1)").font(.system(size: 14, weight: .bold)).foregroundStyle(WelcomeColor.pendingText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(WelcomeColor.pendingFill))
                    .overlay(Circle().strokeBorder(WelcomeColor.pending, lineWidth: 1.5))
            case .todo:
                Text("\(index + 1)").font(.system(size: 14, weight: .semibold)).foregroundStyle(GuideColor.chipText)
                    .frame(width: 28, height: 28).background(Circle().fill(GuideColor.chipFill))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 第 3 步：润色接口

    private func polishDetail(_ progress: WelcomeSetup.Progress) -> String {
        if progress.polish {
            return [ProviderName.of(store.settings.baseURL), store.settings.model, L("连接正常", "Connected", "接続 OK")].joined(separator: " · ")
        }
        return L("改写、润色、翻译用它。填你自己的 API Key，跟着教程大约 3 分钟",
                 "Used to rewrite, polish and translate. Add your own API key, about 3 minutes with the guide",
                 "書き換え・整える・翻訳に使います。自分の API キーを入れます。ガイドに沿って約 3 分")
    }

    /// 已经填了地址和模型、还没测通（自己的模型、自定义地址，或上次测试失败）：地址、模型、Key 三行和测试结果（WL3b）。
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
                .font(.system(size: 13.5)).foregroundStyle(GuideColor.secondary)
            case .success(_, let seconds):
                Label(L("连接正常 · \(String(format: "%.1f", seconds)) 秒", "Connected · \(String(format: "%.1f", seconds)) s", "接続 OK · \(String(format: "%.1f", seconds)) 秒"),
                      systemImage: "checkmark")
                    .font(.system(size: 13.5)).foregroundStyle(WelcomeColor.green)
            case .failure(let message):
                Text(message).font(.system(size: 13)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            case .idle:
                if store.lastTestOK == false {
                    Text(L("上次测试失败", "Last test failed", "前回のテストは失敗")).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GuideColor.card))
        .padding(.top, 6)
    }

    private func configLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 13.5)).foregroundStyle(GuideColor.secondary).frame(width: 40, alignment: .leading)
            Text(value).font(.system(size: 14)).foregroundStyle(GuideColor.text).lineLimit(1).truncationMode(.middle)
        }
    }

    private var maskedKey: String {
        let key = store.apiKey
        guard key.count > 10 else { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    // MARK: 第 4 步：问答接口

    /// 润色那家能不能联网（沿用接口页的判断）：能联网、不能联网、自己的模型。
    private enum PolishKind { case searchable(String), offline(String), own }

    private var polishKind: PolishKind {
        let provider = Provider.detect(store.settings.baseURL)
        if provider == .custom || provider == .ollama { return .own }
        if let search = store.settings.searchProvider { return .searchable(search.name) }
        return .offline(provider.title)
    }

    private func answerDetail(_ progress: WelcomeSetup.Progress) -> String {
        if progress.answer {
            let answers = store.settings.forAnswers
            let same = !store.settings.usesAnswerEndpoint
                || (store.settings.answerBaseURL == store.settings.baseURL && store.settings.answerModel == store.settings.model)
            let online = answers.searchProvider != nil
                ? L("能联网", "Can search the web", "ウェブ検索できる") : L("不能联网", "No web search", "ウェブ検索なし")
            return same
                ? L("和润色用同一个", "Same as Polish", "整えると同じ") + " · " + online
                : [ProviderName.of(answers.baseURL), answers.model, online].joined(separator: " · ")
        }
        return L("问问题、查天气新闻用它，可以和润色用同一个，也可以另配一个能联网的",
                 "Used to answer questions and check weather or news. Use the same one as Polish, or add one that can search the web",
                 "質問や天気・ニュースの確認に使います。整えると同じものでも、ウェブ検索できる別のものでもかまいません")
    }

    private var answerHint: some View {
        let warns: Bool
        let text: String
        switch polishKind {
        case .offline(let name):
            warns = true
            text = L("\(name) 不能联网搜索。问答也用它的话，查不了天气、新闻这类最新消息。",
                     "\(name) can't search the web. If answers use it too, it can't look up the latest weather or news.",
                     "\(name) はウェブ検索できません。回答にも使うと、天気やニュースなどの最新情報は調べられません。")
        case .searchable(let name):
            warns = false
            text = L("\(name) 可以联网搜索，问答直接用它就行。", "\(name) can search the web, so answers can use it as is.", "\(name) はウェブ検索できるので、回答にもそのまま使えます。")
        case .own:
            warns = true
            text = L("自己的模型不能联网搜索，问答只能回答它已知道的。", "Your own model can't search the web, so answers use only what it already knows.", "自分のモデルはウェブ検索できないため、回答はモデルが知っている範囲だけです。")
        }
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: warns ? "exclamationmark.triangle" : "globe").font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(warns ? WelcomeColor.warnText : GuideColor.chipText)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(warns ? WelcomeColor.warnFill : GuideColor.chipFill))
        .padding(.top, 6)
    }

    /// 「和润色用同一个」：直接打开 AI › 问答的「和润色用同一个接口」（润色那一步已经测过连通）。
    /// 问答接口原来填的地址、模型、Key 留着，以后关掉开关还能用。
    private func useSameForAnswers() {
        store.settings.separateAnswer = false
        WelcomeSetup.answerDecided = true
        refresh = UUID()
    }

    // MARK: 教程插图：跟当前步换（第 1、2 步）

    @ViewBuilder
    private func illustration(_ progress: WelcomeSetup.Progress) -> some View {
        switch progress.current {
        case 0?: WelcomeIllustration(step: 1)
        case 1?: WelcomeIllustration(step: 2)
        default: EmptyView()
        }
    }

    // MARK: 底部按钮

    @ViewBuilder
    private func buttons(_ progress: WelcomeSetup.Progress) -> some View {
        switch progress.current {
        case 0?:
            GuidePrimaryButton(L("去系统设置添加", "Add in Settings", "設定で追加")) { AppSettings.open() }
            skipButton
        case 1?:
            GuidePrimaryButton(L("打开完全访问", "Turn On Full Access", "フルアクセスをオン")) {
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
                GuidePrimaryButton(L("跟着教程配置润色", "Set Up Polish with the Guide", "ガイドで整えるを設定")) { open(.provider) }
                GuideSecondaryButton(L("已有 Key，或用自己的模型", "I have a key, or use my own model", "キーがある・自分のモデルを使う")) { openAPI() }
            }
        case 3?:
            switch polishKind {
            case .offline:
                GuidePrimaryButton(L("配一个能联网的", "Add One That Can Search", "検索できるものを設定")) { open(.answerProvider) }
                GuideSecondaryButton(L("先不联网，和润色用同一个", "No web search for now, same as Polish", "今は検索なしで、整えると同じ")) { useSameForAnswers() }
            case .searchable:
                GuidePrimaryButton(L("和润色用同一个", "Same as Polish", "整えると同じものを使う")) { useSameForAnswers() }
                GuideSecondaryButton(L("另配一个", "Add Another", "別のものを設定")) { open(.answerProvider) }
            case .own:
                GuidePrimaryButton(L("和润色用同一个", "Same as Polish", "整えると同じものを使う")) { useSameForAnswers() }
                GuideSecondaryButton(L("配一个能联网的", "Add one that can search", "検索できるものを設定")) { open(.answerProvider) }
            }
        default:
            if inGuide {
                GuidePrimaryButton(L("开始使用", "Start Using Enclave", "使いはじめる")) { finish() }
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var skipButton: some View {
        if inGuide {
            GuideSecondaryButton(L("先跳过，只用打字", "Skip for now, just type", "あとで。入力だけ使う")) { finish() }
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
private struct WelcomeIllustration: View {
    @Environment(\.colorScheme) private var colorScheme
    let step: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "gearshape").font(.system(size: 11))
                Text(step == 1 ? L("设置 › 键盘 › 添加新键盘", "Settings › Keyboards › Add New Keyboard", "設定 › キーボード › 新しいキーボードを追加")
                               : L("设置 › 飞地输入法 › 键盘", "Settings › Enclave › Keyboards", "設定 › Enclave › キーボード"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(GuideColor.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(GuideColor.field)
            VStack(alignment: .leading, spacing: 8) {
                if step == 1 {
                    Text(L("第三方键盘", "Third-party keyboards", "他社製キーボード")).font(.system(size: 11)).foregroundStyle(GuideColor.secondary)
                    marked(1) { item(L("飞地输入法", "Enclave", "Enclave")) }
                    Text(L("其他键盘…", "Other keyboards…", "その他のキーボード…")).font(.system(size: 12)).foregroundStyle(GuideColor.secondary)
                } else {
                    toggleRow(L("飞地输入法", "Enclave", "Enclave"))
                    marked(2) { toggleRow(L("允许完全访问", "Allow Full Access", "フルアクセスを許可")) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GuideColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(
            colorScheme == .dark
                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A2160), Color(hex: 0x1C1C1E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xEAE6FF), Color(hex: 0xF4F2FF), Color(hex: 0xFBFAFF)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.9))))
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
            Capsule().fill(WelcomeColor.green).frame(width: 34, height: 20)
                .overlay(alignment: .trailing) { Circle().fill(.white).frame(width: 16, height: 16).padding(2) }
        }
        .padding(.horizontal, 10).frame(height: 34)
    }

    /// 紫色描边 + 右上角编号圆点。
    private func marked<Content: View>(_ number: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(GuideColor.purple, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(GuideColor.purple))
                    .offset(x: -40, y: -10)
            }
    }
}

// MARK: - 润色配好：试一次润色（WL5–WL7，OB7 完成页里）

/// 预填一段口语原文，点了才真的调用一次（不自动调）；成功上下分原文 / 润色后，失败一行红字和「再试一次」。
struct TryPolishCard: View {
    @ObservedObject var store: AppStore

    private static let sample = "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看"

    private enum Phase: Equatable { case idle, running, done(String, TimeInterval), failed(String) }
    @State private var phase: Phase = .idle

    init(store: AppStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        GuideCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xFFE9A8))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                            LinearGradient(colors: [Color(hex: 0x8A7BFF), Color(hex: 0x5B4BE8)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    Text(L("试一下润色", "Try Polish", "整えるを試す")).font(.system(size: 16, weight: .semibold)).foregroundStyle(GuideColor.text)
                    Spacer(minLength: 4)
                    if case .done(_, let seconds) = phase {
                        Text(ProviderName.of(store.settings.baseURL) + " · " + L("\(String(format: "%.1f", seconds)) 秒", "\(String(format: "%.1f", seconds)) s", "\(String(format: "%.1f", seconds)) 秒"))
                            .font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary).lineLimit(1)
                    }
                }
                switch phase {
                case .done(let result, _):
                    block(L("原文", "Original", "原文"), Self.sample, highlighted: false)
                    block(L("润色后", "Polished", "整えた後"), result, highlighted: true)
                    Label(L("在任何 App 里点 ✨ 就是这个效果", "Tap ✨ in any app for the same result", "どの App でも ✨ を押すとこうなります"), systemImage: "checkmark")
                        .font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                        .labelStyle(TintedIconLabel(tint: WelcomeColor.green))
                default:
                    Text(Self.sample).font(.system(size: 15)).foregroundStyle(GuideColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.field))
                    if case .failed(let message) = phase {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { Task { await run() } } label: {
                            Label(L("再试一次", "Try Again", "もう一度"), systemImage: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(GuideColor.chipText)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.chipFill))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { Task { await run() } } label: {
                            HStack(spacing: 6) {
                                if phase == .running { ProgressView().tint(.white).controlSize(.small) } else { Image(systemName: "sparkle") }
                                Text(phase == .running ? L("正在润色…", "Polishing…", "整え中…") : L("润色这句", "Polish This", "これを整える"))
                            }
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                                LinearGradient(colors: [Color(hex: 0x7B6BFA), Color(hex: 0x5B4BE8), Color(hex: 0x4A3BD6)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        }
                        .buttonStyle(.plain)
                        .disabled(phase == .running)
                        Text(L("用你刚填的 Key 真的调用一次", "Makes one real call with the key you just added", "入れたキーで実際に 1 回呼び出します"))
                            .font(.system(size: 12)).foregroundStyle(GuideColor.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
        }
    }

    private func block(_ label: String, _ text: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(highlighted ? GuideColor.chipText : GuideColor.secondary)
            Text(text).font(.system(size: 15)).foregroundStyle(highlighted ? GuideColor.text : GuideColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(highlighted ? GuideColor.chipFill : GuideColor.field))
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

/// Label 的图标单独上色（绿勾 + 灰字）。
private struct TintedIconLabel: LabelStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
