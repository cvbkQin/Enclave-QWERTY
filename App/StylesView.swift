import StoreKit
import SwiftUI

/// 「AI」标签（第 51 条，效果图 design/ai-page/AT1–AT4）：顶上分段「接口 | 提示词」，每次冷启动停在「接口」。
/// 接口：润色和问答两张接口卡（各带最近 20 次）→「和润色用同一个接口」→ 联网搜索 → 键盘里的 AI。
/// 提示词（第 54 条，效果图 design/prompts-tab/PT1–PT4）：「润色风格 N | 问答风格 N」两个标签，各一个带本周次数的列表，
/// 「编辑」就地排序、删除、加回预设；点一行进编辑页。
struct AITab: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.aiPath) {
            AIView()
                .navigationDestination(for: AppRouter.AIPage.self) { page in
                    switch page {
                    case .api(let answer): ModelSettingsView(answer: answer)
                    case .resultKey: ResultKeySettingsView()
                    case .recent(let answer): RecentRequestsView(answer: answer)
                    }
                }
        }
    }
}

#if DEBUG
/// 截图用（-promptsDebug）：提示词停在某个样子。
enum PromptsDebug {
    static var scene: String?
}
#endif

struct AIView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    /// 没同意隐私政策时点「测试连接」：先去同意。
    @State private var needsPrivacy = false
    /// 大陆店面从「禁止」改成「开 / 每次询问」前的确认框（AP4）：选的那一档。
    @State private var pendingWebMode: WebSearchMode?
    /// 测试连接成功、这个地址还没同意过时弹出的确认（P05）。
    @State private var consentEndpoint: ConsentPrompt?
    @State private var recent: [UsageStats.Request] = []
    @State private var answerRecent: [UsageStats.Request] = []
    /// 打开这一条的编辑页：「＋ 新建」之后、截图用（-promptsDebug）。
    @State private var debugEditing: UUID?
    @State private var editingAnswerStyle: UUID?

    private struct ConsentPrompt: Identifiable {
        let endpoint: String
        var id: String { endpoint }
    }

    private var locked: Bool { BuiltinAPI.isInternalBuild }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if router.aiSegment == .api {
                    Section {
                    } header: {
                        VStack(alignment: .leading, spacing: 12) {
                            AISectionTitle(text: L("润色和问答", "Polish and Q&A", "整える・質問"))
                            apiCard(answer: false)
                            apiCard(answer: true)
                        }
                        .dashFormCard()
                    }
                    Section {
                        SameAPIToggle(locked: locked)
                    }
                    webSearchSection
                    KeyboardAISection()
                } else {
                    Section {
                    } header: {
                        PromptKindTabs(kind: $router.promptKind,
                                       polishCount: store.settings.styles.count,
                                       answerCount: store.settings.answerStyles.count)
                    }
                    PromptListSections(answer: router.promptKind == .answer, settings: $store.settings) { id in
                        if router.promptKind == .answer { editingAnswerStyle = id } else { debugEditing = id }
                    } add: {
                        addStyle(answer: router.promptKind == .answer)
                    }
                }
            }
            .tint(DashColor.ai)
            .onAppear { openAnswerWebSearch(proxy) }
            .onChange(of: router.showsAnswerWebSearch) { _ in openAnswerWebSearch(proxy) }
        }
        .pinnedTabTitle(caption: caption, title: "AI") {
            Picker("", selection: $router.aiSegment) {
                Text(L("接口", "API", "API")).tag(AppRouter.AISegment.api)
                Text(L("提示词", "Prompts", "プロンプト")).tag(AppRouter.AISegment.prompts)
            }
            .pickerStyle(.segmented)
            .frame(height: 34)
        }
        .navigationTitle("AI")
        .tabRootPage()
        .onAppear {
            reloadRecent()
            #if DEBUG
            applyDebugScene()
            #endif
        }
        // 键盘里用过再切回 App：柱子跟着更新。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in reloadRecent() }
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
        // 「＋ 新建」后没改名也没填内容就返回：这条空的不留。
        .navigationDestination(isPresented: Binding(get: { debugEditing != nil }, set: { if !$0 {
            NewPromptCleanup.dropIfBlank(debugEditing, answer: false, settings: &store.settings)
            debugEditing = nil
        } })) {
            if let index = store.settings.styles.firstIndex(where: { $0.id == debugEditing }) {
                StyleEditor(style: $store.settings.styles[index], settings: $store.settings)
            }
        }
        .navigationDestination(isPresented: Binding(get: { editingAnswerStyle != nil }, set: { if !$0 {
            NewPromptCleanup.dropIfBlank(editingAnswerStyle, answer: true, settings: &store.settings)
            editingAnswerStyle = nil
        } })) {
            if let index = store.settings.answerStyles.firstIndex(where: { $0.id == editingAnswerStyle }) {
                AnswerStyleEditor(style: $store.settings.answerStyles[index], settings: $store.settings)
            }
        }
    }

    private func reloadRecent() {
        recent = UsageStats.polishRecent
        answerRecent = UsageStats.answerRecent
    }

    // MARK: 提示词（第 54 条）

    /// 「＋ 添加润色风格 / 问答风格」：先加一条空的，直接进编辑页；什么都没填就返回时去掉（NewPromptCleanup）。
    private func addStyle(answer: Bool) {
        if answer {
            let style = StylePreset(name: NewPromptCleanup.answerName, prompt: "")
            store.settings.answerStyles.append(style)
            editingAnswerStyle = style.id
        } else {
            let style = StylePreset(name: NewPromptCleanup.polishName, prompt: "")
            store.settings.styles.append(style)
            debugEditing = style.id
        }
    }

    /// 键盘「去开启」：切到问答页，滚到「联网搜索」。
    private func openAnswerWebSearch(_ proxy: ScrollViewProxy) {
        guard router.showsAnswerWebSearch else { return }
        router.showsAnswerWebSearch = false
        router.aiSegment = .api
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { proxy.scrollTo("webSearch", anchor: .center) }
        }
    }

    /// 标题上的灰字：「润色 DeepSeek · 问答 Kimi」，同一个接口时「润色、问答都用 DeepSeek」。
    private var caption: String {
        guard store.settings.isConfigured else { return L("还没设置", "Not set up", "未設定") }
        let main = ProviderName.of(store.settings.baseURL)
        guard store.settings.usesAnswerEndpoint else {
            return L("润色、问答都用 \(main)", "Polish & Q&A: \(main)", "整える・質問とも \(main)")
        }
        let ask = ProviderName.of(store.settings.answerBaseURL)
        return L("润色 \(main) · 问答 \(ask)", "Polish \(main) · Q&A \(ask)", "整える \(main)・質問 \(ask)")
    }

    // MARK: 接口卡

    /// 接口卡（AT1）：小字「润色 / 问答」+ 右上状态；大字服务商 + 灰字模型（问答能联网时右边蓝字「● 可联网」）；
    /// 「19/20 成功 · 平均 1.0 秒」+「最近 20 次 ›」和 20 根小柱；「测试连接」「更改接口 ›」。
    /// 问答和润色用同一个时显示润色那家，写「和润色用同一个」，没有「更改接口」，统计照样记问答自己的。内测版只有「测试连接」。
    private func apiCard(answer: Bool) -> some View {
        let ownAnswer = answer && store.settings.separateAnswer
        let configured = ownAnswer ? store.settings.usesAnswerEndpoint : store.settings.isConfigured
        let baseURL = ownAnswer ? store.settings.answerBaseURL : store.settings.baseURL
        let model = ownAnswer ? store.settings.answerModel : store.settings.model
        let state = ownAnswer ? store.answerTest : store.test
        let status = self.status(ownAnswer)
        let missing = ownAnswer ? store.answerMissingModel : store.missingModel
        return DashCard {
            HStack(spacing: 6) {
                Text(answer ? L("问答", "Q&A", "質問") : L("润色", "Polish", "整える"))
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Circle().fill(status.color).frame(width: 7, height: 7)
                    Text(status.text).lineLimit(1)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(status.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(configured ? ProviderName.of(baseURL) : L("还没设置", "Not set up", "未設定"))
                    .font(.system(size: 26, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                if configured {
                    Text(model).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if answer, configured, store.settings.answerSearch != nil {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x0A84FF)).frame(width: 7, height: 7)
                        Text(L("可联网", "Web", "ウェブ可"))
                    }
                    .font(.footnote).foregroundStyle(Color(hex: 0x0A84FF))
                    .fixedSize()
                }
            }
            if answer, !store.settings.separateAnswer {
                Text(L("和润色用同一个", "Same as Polish", "整えると同じ")).font(.footnote).foregroundStyle(.secondary)
            }
            recentSummary(answer ? answerRecent : recent, answer: answer)
            if let error = status.error {
                Text(error).font(.footnote).foregroundStyle(.red).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                cardButton {
                    HStack(spacing: 6) {
                        if state == .running { ProgressView().controlSize(.small) }
                        Text(L("测试连接", "Test", "接続テスト"))
                    }
                } action: {
                    if router.privacyAgreed {
                        Task { ownAnswer ? await store.runAnswerTest() : await store.runTest() }
                    } else {
                        needsPrivacy = true
                    }
                }
                .disabled(!configured || state == .running)
                // 和润色用同一个时问答页没有自己的接口详情。
                if !locked && (!answer || store.settings.separateAnswer) {
                    cardButton {
                        Text(configured ? L("更改接口 ›", "Change ›", "API を変更 ›") : L("去设置 ›", "Set Up ›", "設定する ›"))
                    } action: {
                        router.aiPath.append(AppRouter.AIPage.api(answer: answer))
                    }
                }
            }
            if !locked, let missing {
                missingModelTip(missing) { router.aiPath.append(AppRouter.AIPage.api(answer: ownAnswer)) }
            }
        }
    }

    /// 接口卡里的统计和 20 根小柱，点了进「最近 20 次」。还没有记录时只写一行灰字。
    @ViewBuilder
    private func recentSummary(_ requests: [UsageStats.Request], answer: Bool) -> some View {
        let open = { router.aiPath.append(AppRouter.AIPage.recent(answer: answer)) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if requests.isEmpty {
                    Text(L("还没有调用记录", "No requests yet", "まだ呼び出しはありません")).font(.system(size: 14)).foregroundStyle(.secondary)
                } else {
                    RecentStatsText(requests: requests, slowest: false)
                }
                Spacer(minLength: 6)
                Button(action: open) {
                    Text(L("最近 \(UsageStats.recentLimit) 次 ›", "Last \(UsageStats.recentLimit) ›", "直近 \(UsageStats.recentLimit) 回 ›"))
                        .font(.system(size: 14)).foregroundStyle(DashColor.ai)
                }
                .buttonStyle(.plain)
            }
            if !requests.isEmpty {
                RecentBars(requests: requests, height: 30)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: open)
            }
        }
        .padding(.top, 2)
    }

    private func cardButton<Label: View>(@ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DashColor.ai)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DashColor.ai.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    /// 右上状态：● 连接正常 · 0.8 秒 / 连不上 / 还没测试。测试刚失败时下面红字写原因。
    private func status(_ ownAnswer: Bool) -> (text: String, color: Color, error: String?) {
        let configured = ownAnswer ? store.settings.usesAnswerEndpoint : store.settings.isConfigured
        guard configured else { return (L("未设置", "Not set up", "未設定"), DashColor.system, nil) }
        let state = ownAnswer ? store.answerTest : store.test
        let requests = ownAnswer ? answerRecent : recent
        func connected(_ seconds: Double?) -> (String, Color, String?) {
            let text = L("连接正常", "Connected", "接続 OK")
            guard let seconds else { return (text, DashColor.ok, nil) }
            return (text + " · " + L("\(String(format: "%.1f", seconds)) 秒", "\(String(format: "%.1f", seconds)) s", "\(String(format: "%.1f", seconds)) 秒"), DashColor.ok, nil)
        }
        let failed = L("连不上", "Can't connect", "接続できません")
        switch state {
        case .running: return (L("正在测试…", "Testing…", "テスト中…"), .orange, nil)
        case .failure(let message): return (failed, .red, message)
        case .success(_, let seconds): return connected(seconds)
        case .idle: break
        }
        if let last = requests.last {
            return last.ok ? connected(Double(last.ms) / 1000) : (L("最近一次失败", "Last request failed", "直近は失敗"), .red, nil)
        }
        if !ownAnswer {
            switch store.lastTestOK {
            case true?: return connected(nil)
            case false?: return (failed, .red, nil)
            case nil: break
            }
        }
        return (L("还没测试", "Not tested", "未テスト"), DashColor.system, nil)
    }

    /// 接口卡里的橙色提示（ML5）：连得上，但服务商的列表里已经没有这个模型。「选择其他模型」进接口详情。
    private func missingModelTip(_ model: String, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xFF9500))
                Text(L("服务商的模型列表里没有 \(model)，这个模型可能已下线。现在仍能连接，但随时可能停止服务。",
                       "\(model) isn't in the provider's model list and may be retired. It still connects for now but could stop working anytime.",
                       "サービスのモデル一覧に \(model) がありません。提供終了の可能性があります。今は接続できますが、いつ停止するかわかりません。"))
                    .font(.footnote)
                    .foregroundStyle(Color(light: 0x7C2D12, dark: 0xFDBA74))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: choose) {
                Text(L("选择其他模型", "Choose another model", "別のモデルを選ぶ"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xC2410C))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Color(.systemBackground)))
                    .overlay(Capsule().stroke(Color(hex: 0xFF9500), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(light: 0xFFF4E5, dark: 0x3A2810)))
    }

    // MARK: 联网搜索

    /// 联网搜索（AP2–AP4 + QP1）：上面「联网调用」三段，下面「调用偏好」5 档条。问答接口不能联网时整组变灰，设置值保留。
    private var webSearchSection: some View {
        let provider = store.settings.answerSearch
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("联网调用", "Web search", "ウェブ検索")).font(.system(size: 17, weight: .semibold))
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
                Divider()
                SearchTendencyCard(settings: $store.settings)
            }
            .padding(.vertical, 6)
            .opacity(provider == nil ? 0.45 : 1)
            .disabled(provider == nil)
        } header: {
            AISectionTitle(text: L("联网搜索", "Web search", "ウェブ検索"))
        } footer: {
            Text(webSearchFooter(provider))
        }
        .id("webSearch")
    }

    private func webSearchFooter(_ provider: SearchProvider?) -> String {
        guard let provider else {
            let name = ProviderName.of(store.settings.forAnswers.baseURL)
            return L("\(name) 不能联网，问答只用模型自己的知识。想联网，请选通义千问、Kimi、智谱 GLM 或腾讯混元。", "\(name) can't search the web, so answers use only the model's own knowledge. To search, choose Qwen, Kimi, Zhipu GLM or Tencent Hunyuan.", "\(name) はウェブ検索できないため、回答はモデル自身の知識だけを使います。検索するには Qwen・Kimi・Zhipu GLM・Tencent Hunyuan を選んでください。")
        }
        let lead = L("只对问答有效。", "Q&A only. ", "質問だけに使います。")
        let mode: String
        switch store.settings.webSearchMode ?? .off {
        case .on: mode = L("需要联网时直接搜；第一次用这家服务商时，键盘上先问你一次。", "When it does, it searches right away; the first time with a provider, the keyboard asks you once.", "必要なときはそのまま検索します。そのサービスを初めて使うときは、キーボードで一度確認します。")
        case .ask: mode = L("需要联网时，键盘上先问你一次，点「允许」才搜。", "When it does, the keyboard asks you first and searches only if you tap Allow.", "必要なときはキーボードで先に確認し、「許可」したときだけ検索します。")
        case .off: mode = L("不联网。遇到要最新信息的问题，键盘上会提示你，可以去开启，也可以直接回答。", "No web search. When a question needs current info, the keyboard tells you, and you can turn it on or answer anyway.", "ウェブ検索はしません。最新情報が必要な質問では、キーボードでお知らせします。オンにするか、そのまま回答できます。")
        }
        let tail = L("\n每次搜索把问题发给 \(provider.name) 的搜索服务，约 ¥0.01，从你的 \(provider.name) 账户扣。润色不调用联网搜索。", "\nEach search sends your question to \(provider.name) search, billed to your \(provider.name) account. Polish never calls web search.", "\n検索のたびに質問を \(provider.name) の検索サービスに送り、\(provider.name) のアカウントに課金されます。整えるではウェブ検索を使いません。")
        return lead + mode + tail
    }

    #if DEBUG
    private func applyDebugScene() {
        guard let scene = PromptsDebug.scene else { return }
        PromptsDebug.scene = scene == "optimized" ? scene : nil
        store.settings.styles = StylePreset.defaults
        switch scene {
        case "missing":
            store.settings.styles.removeAll { $0.name == "正式" || $0.name == "结构" }
        case "empty":
            let blank = StylePreset(name: NewPromptCleanup.polishName, prompt: "")
            store.settings.styles.append(blank)
            debugEditing = blank.id
        case "optimized":
            let custom = StylePreset(name: "客户", prompt: "发给客户的，客气点，别太啰嗦")
            store.settings.styles.append(custom)
            debugEditing = custom.id
        default: break
        }
    }
    #endif
}

/// 润色风格一行下面的一句说明（列表和下拉共用）。
enum PolishPromptSections {
    /// 一句说明：自带的 5 条用固定的说明，自己加的显示提示词内容。
    static func summary(_ style: StylePreset) -> String {
        if let builtIn = StyleSuggestions.builtIn(style), builtIn.prompt == style.prompt {
            switch style.name {
            case "润色": return L("不加额外要求，按原文的语气改顺、改通", "No extra instructions. Smooths the text in its own tone", "追加の指示なし。元の語調のまま読みやすく整えます")
            case "正式": return L("书面、得体、礼貌，适合工作沟通和对外发送", "Written, polite and proper, for work and outside contacts", "書き言葉で丁寧に。仕事や社外向けに")
            case "口语": return L("像本人平时说话一样自然随意", "Natural and casual, the way you talk", "普段話すように自然でカジュアルに")
            case "简短": return L("只留核心意思，能一句说清就一句", "Just the point, in one sentence if possible", "要点だけ。できれば一文で")
            case "结构": return L("提炼关键信息，整理成编号要点", "Pulls out the key points as a numbered list", "要点を抜き出して番号付きで整理")
            default: break
            }
        }
        return style.prompt.isEmpty ? L("不加额外要求，按原文的语气改顺、改通", "No extra instructions. Smooths the text in its own tone", "追加の指示なし。元の語調のまま読みやすく整えます") : style.prompt
    }
}

/// 问答风格内容空着时的说明。
enum AnswerStyleSections {
    static let answerFallback = L("简短直接，几句话说清楚", "Brief and direct, in a few sentences", "短く率直に、数文で")
}

/// 键盘 AI 栏上的「✨」和「名字 ▾」的小样，提示词页和编辑页用。
struct KeyboardChipPreview: View {
    var name: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 24)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], startPoint: .leading, endPoint: .trailing)))
            HStack(spacing: 2) {
                Text(name).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(maxWidth: 92)
            .frame(height: 24)
            .background(Capsule().fill(DashColor.card))
            .overlay(Capsule().strokeBorder(Color(.systemGray4), lineWidth: 0.5))
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct StyleEditor: View {
    @Binding var style: StylePreset
    @Binding var settings: EnclaveSettings
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var optimizer = PromptOptimizer()
    @FocusState private var editingPrompt: Bool

    private var builtIn: StylePreset? { StyleSuggestions.builtIn(style) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField(L("名称", "Name", "名前"), text: $style.name)
                    Text(L("键盘上显示", "On keyboard", "キーボード")).font(.caption).foregroundStyle(.secondary)
                    KeyboardChipPreview(name: style.displayName)
                }
            } header: {
                Text(L("名称", "Name", "名前"))
            } footer: {
                Text(L("显示在键盘 ✨ 旁边和「润色风格 ⌄」的下拉里，四个字以内最好。", "Shown next to ✨ on the keyboard and in its polish style ⌄ menu. Keep it short.", "キーボードの ✨ の横と「整えるスタイル ⌄」のメニューに表示されます。短めがおすすめです。"))
            }
            Section {
                TextEditor(text: $style.prompt)
                    .focused($editingPrompt)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if style.prompt.isEmpty {
                            Text(L("比如：翻成日语，发给客户，客气一点", "e.g. Translate into Japanese for a client, keep it polite", "例：日本語に訳して、お客様向けに丁寧に"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                PromptOptimizeButton(optimizer: optimizer, prompt: style.prompt, name: style.displayName, answer: false)
            } header: {
                Text(L("提示词内容", "Prompt", "プロンプトの内容"))
            } footer: {
                Text(L("写清楚场景和要求，什么都可以写，比如「翻成日语，发给客户，客气一点」。每次点 ✨ 都会带上。", "Describe the situation and what you want. Anything goes, like \"translate into Japanese for a client, keep it polite\". It's sent every time you tap ✨.", "場面と要望をはっきり書きます。何でも書けます（例：「日本語に訳して、お客様向けに丁寧に」）。✨ をタップするたびに送られます。"))
            }
            if let result = optimizer.result {
                PromptOptimizedSection(optimizer: optimizer, result: result, prompt: $style.prompt)
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                        Text(L("建议", "Suggestions", "候補"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.deepPurple)
                    SuggestionChips(tags: StyleSuggestions.tags(for: style), prompt: $style.prompt)
                    Text(builtIn == nil ? L("点一下加进提示词，再点一下拿掉。自己加的提示词显示通用建议。", "Tap to add to the prompt, tap again to remove. Prompts you added show general suggestions.", "タップでプロンプトに追加、もう一度タップで外します。追加したプロンプトには汎用の候補を表示します。") : L("点一下加进提示词，再点一下拿掉。", "Tap to add to the prompt, tap again to remove.", "タップでプロンプトに追加、もう一度タップで外します。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // 和上面分组标题、说明文字对齐。
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Section {
                if let builtIn {
                    Button(L("恢复这条的默认内容", "Restore default text", "元の内容に戻す")) { style.prompt = builtIn.prompt }
                        .disabled(style.prompt == builtIn.prompt)
                }
                Button(L("设为默认润色风格", "Set as default", "デフォルトにする")) { settings.selectedStyleID = style.id }
                    .disabled(settings.selectedStyle?.id == style.id)
                Button(L("删除这条润色风格", "Delete polish style", "この整えるスタイルを削除"), role: .destructive) {
                    let id = style.id
                    dismiss()
                    // 先退回列表再删，免得正在显示的编辑页绑定到已删除的项。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        settings.styles.removeAll { $0.id == id }
                        if settings.selectedStyleID == id { settings.selectedStyleID = nil }
                    }
                }
                .disabled(settings.styles.count <= 1)
            }
        }
        .navigationTitle(L("编辑润色风格", "Edit polish style", "整えるスタイルを編集"))
        .doneEditingButton(editingPrompt)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { optimizer.cancel() }
        #if DEBUG
        .onAppear {
            guard PromptsDebug.scene == "optimized" else { return }
            PromptsDebug.scene = nil
            optimizer.result = PromptOptimizer.Result(
                prompt: "这段话要发给客户。语气礼貌客气，称呼用「您」；表达简洁，去掉重复和口语词，保留原文里的时间、数字和具体安排。",
                suggestions: ["开头加问候", "结尾加致谢", "先说结论"])
        }
        #endif
    }
}

// MARK: - AI 优化（润色风格 PR2、问答风格 PT4 共用）

/// 提示词框下面一行：「✨ AI 优化」，生成中显示转圈，出错写一行红字。
/// 问答风格（PT4）：第一次带橙色「新」小标签，下面一行灰字说明。
struct PromptOptimizeButton: View {
    @ObservedObject var optimizer: PromptOptimizer
    let prompt: String
    let name: String
    let answer: Bool
    @EnvironmentObject private var store: AppStore
    @AppStorage("answerOptimizeSeen") private var answerOptimizeSeen = false

    var body: some View {
        let empty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // 按钮和下面的说明 / 红字放在同一行里上下排，中间不要分隔线。
        VStack(alignment: .leading, spacing: 4) {
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                if answer { answerOptimizeSeen = true }
                if optimizer.running {
                    optimizer.cancel()
                } else {
                    optimizer.run(name: name, prompt: prompt, answer: answer, settings: store.settings, apiKey: store.apiKey)
                }
            } label: {
                HStack(spacing: 6) {
                    if optimizer.running {
                        ProgressView().controlSize(.small)
                        Text(L("AI 正在优化…点一下取消", "Optimizing… tap to cancel", "AI が最適化中…タップでキャンセル"))
                    } else {
                        Image(systemName: "sparkles")
                        Text(answer ? L("AI 优化", "Improve with AI", "AI で改善") : L("AI 优化提示词", "Improve with AI", "AI で改善"))
                        if answer && !answerOptimizeSeen {
                            Text(L("新", "New", "新"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(empty && !optimizer.running ? Color.secondary : AppColor.deepPurple)
            }
            .disabled(empty && !optimizer.running)
            .buttonStyle(.borderless)
            if empty && !optimizer.running {
                Text(L("先写几个字，AI 再帮你改清楚", "Write a few words first, then AI can sharpen it", "数文字書いてから AI で整えられます"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else if answer && !optimizer.running && optimizer.error == nil {
                Text(L("让 AI 把这段要求改得更清楚，和润色提示词一样", "Let AI make these instructions clearer, just like polish prompts", "整えるプロンプトと同じく、AI がこの指示をわかりやすくします"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if let error = optimizer.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

/// AI 给的结果：优化后的整段（「用这一版」替换掉现在的），下面几条还能补的要求（点一下加进去）。
struct PromptOptimizedSection: View {
    @ObservedObject var optimizer: PromptOptimizer
    let result: PromptOptimizer.Result
    @Binding var prompt: String

    var body: some View {
        Section {
            Text(result.prompt)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColor.chipSelectedFill))
                .listRowSeparator(.hidden)
            HStack(spacing: 12) {
                Button(L("用这一版", "Use this", "これを使う")) {
                    prompt = result.prompt
                    optimizer.result = nil
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L("不用了", "Dismiss", "使わない")) { optimizer.result = nil }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
            if !result.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("还可以加上", "You could also add", "追加するなら"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    // 加进淡紫框里这一版，「用这一版」时一起带上。
                    SuggestionChips(tags: result.suggestions,
                                    prompt: Binding(get: { optimizer.result?.prompt ?? "" },
                                                    set: { optimizer.result?.prompt = $0 }))
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }
        } header: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text(L("AI 优化结果", "AI suggestion", "AI の提案"))
            }
        } footer: {
            Text(L("「用这一版」会换掉上面的内容；下面的建议点一下加进这一版。", "\"Use this\" replaces the text above. Tap a suggestion to add it to this version.", "「これを使う」で上の内容を置き換えます。下の候補はタップでこの案に追加します。"))
        }
    }
}

/// 编辑页的「AI 优化」：把名称和提示词（问答风格的「怎么回答」）发给接口页配置的模型，让它改得更清楚具体，另给几条能补的要求。
@MainActor
final class PromptOptimizer: ObservableObject {
    struct Result: Equatable {
        var prompt: String
        var suggestions: [String]
    }

    @Published var result: Result?
    @Published private(set) var running = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?

    func run(name: String, prompt: String, answer: Bool = false, settings: EnclaveSettings, apiKey: String) {
        error = nil
        result = nil
        // 没同意隐私政策、没配置接口、到期后今天次数用完，都不发请求。
        guard PrivacyConsent.isAgreed else {
            error = L("先在首页同意隐私说明，才能用 AI。", "Agree to the privacy notice on the Home tab first.", "まずホームでプライバシーの説明に同意してください。")
            return
        }
        guard settings.isConfigured else {
            error = LLMError.notConfigured.errorDescription
            return
        }
        guard AIAccess.current.allowsAI else {
            error = L("今天的 AI 次数用完了，明天再试，或在 App 里解锁。", "You've used today's AI uses. Try tomorrow or unlock in the app.", "今日の AI の回数を使い切りました。明日もう一度試すか、アプリで購入してください。")
            return
        }
        running = true
        let client = LLMClient(settings: settings, apiKey: apiKey)
        let messages = Self.messages(name: name, prompt: prompt, answer: answer)
        let start = Date()
        task = Task { [weak self] in
            var raw = ""
            var failure: String?
            var reason: String?
            do {
                for try await piece in client.stream(messages) { raw += piece }
            } catch is CancellationError {
                failure = nil
            } catch {
                failure = error.localizedDescription
                reason = UsageStats.Request.Failure.of(error)
            }
            guard let self, !Task.isCancelled else { return }
            self.running = false
            let ok = failure == nil
            UsageStats.recordRequest(ms: Int(Date().timeIntervalSince(start) * 1000), ok: ok, model: client.settings.model, error: reason)
            if let failure { self.error = failure; return }
            if let parsed = Self.parse(ModelOutput.clean(raw)) {
                self.result = parsed
                AIAccess.recordUse()
            } else {
                self.error = L("模型没按格式回复，再试一次。", "The model's reply wasn't usable. Try again.", "モデルの応答を読み取れませんでした。もう一度試してください。")
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
    }

    static func messages(name: String, prompt: String, answer: Bool = false) -> [ChatMessage] {
        if answer { return answerMessages(name: name, prompt: prompt) }
        let system = """
        你是提示词编辑助手。用户在输入法里给「AI 润色」功能写了一条提示词，每次润色时它会和要改的那段文字一起发给模型。
        帮用户把这条提示词改得更清楚、具体、能照着做：
        - 保持用户原来的意图、语气和语言（用户写中文就用中文，写英文就用英文），不要加用户没提过的新要求；
        - 写成给模型的指令，一两句话到一小段，不超过 150 字，不用 markdown、不用标题；
        - 不要写「请润色下面的文字」这类开头，原文会另外附上。
        另外给 2 到 4 条用户还可以补充的要求，每条 12 个字以内，能直接接在提示词后面。
        严格按这个格式输出，不要别的内容：
        【优化后】
        （优化后的提示词）
        【建议】
        - （一条要求）
        - （一条要求）
        """
        return [.system(system), .user("名称：\(name)\n提示词：\(prompt)")]
    }

    /// 问答风格（PT4）：把这段问答风格要求改清楚；建议用问答的（附上出处、不超过三句、举个例子、用中文回答…）。
    static func answerMessages(name: String, prompt: String) -> [ChatMessage] {
        let system = """
        你是提示词编辑助手。用户在输入法里给「AI 问答」功能写了一段问答风格要求，每次提问时它会和问题一起发给模型，规定模型怎么回答。
        帮用户把这段问答风格要求改得更清楚、具体、能照着做：
        - 保持用户原来的意图和语言（用户写中文就用中文，写英文就用英文），不要加用户没提过的新要求；
        - 写成给模型的指令，一两句话到一小段，不超过 150 字，不用 markdown、不用标题；
        - 只说怎么回答（长短、结构、语气、要不要举例或给出处），不要写「请回答下面的问题」这类开头，问题会另外附上。
        另外给 2 到 4 条用户还可以补充的回答要求，比如「附上出处」「不超过三句」「举个例子」「用中文回答」，每条 12 个字以内，能直接接在后面。
        严格按这个格式输出，不要别的内容：
        【优化后】
        （优化后的问答风格要求）
        【建议】
        - （一条要求）
        - （一条要求）
        """
        return [.system(system), .user("名称：\(name)\n问答风格要求：\(prompt)")]
    }

    /// 取出「【优化后】」和「【建议】」两段；没有「【优化后】」就当失败。
    static func parse(_ text: String) -> Result? {
        guard let head = text.range(of: "【优化后】") else { return nil }
        let rest = text[head.upperBound...]
        let tips = rest.range(of: "【建议】")
        let body = String(tips.map { rest[..<$0.lowerBound] } ?? rest).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        var suggestions: [String] = []
        if let tips {
            for line in rest[tips.upperBound...].split(whereSeparator: \.isNewline) {
                var item = line.trimmingCharacters(in: .whitespaces)
                while let first = item.first, "-•*·0123456789.、 ".contains(first) { item.removeFirst() }
                item = item.trimmingCharacters(in: CharacterSet(charactersIn: "。；; "))
                if !item.isEmpty, !suggestions.contains(item), suggestions.count < 4 { suggestions.append(item) }
            }
        }
        return Result(prompt: body, suggestions: suggestions)
    }
}

/// 问答那页的天蓝：字 #0284C7、浅底 #E0F2FE。
enum AnswerColor {
    static let text = Color(hex: 0x0284C7)
    static let soft = Color(hex: 0xE0F2FE)
}

/// 调用偏好（QP1–QP4，原「联网倾向」）：5 档的条，只能停在档上；下面说明框跟着档位换。联网调用是「禁止」时整张变灰、不能拖。
struct SearchTendencyCard: View {
    @Binding var settings: EnclaveSettings
    @Environment(\.colorScheme) private var colorScheme

    private var off: Bool { (settings.webSearchMode ?? .off) == .off }
    private var level: Int { settings.tendency }

    static let names = [L("不联网", "Never", "しない"), L("很少", "Rarely", "少なめ"), L("适中", "Balanced", "ふつう"),
                        L("积极", "Often", "多め"), L("尽量查", "When unsure", "できるだけ")]

    var body: some View {
        let accent = off ? Color(.systemGray) : AnswerColor.text
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(off ? Color(.systemGray5) : AnswerColor.soft))
                Text(L("调用偏好", "Search preference", "検索の頻度"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(off ? .secondary : .primary)
                Spacer(minLength: 8)
                Text(Self.names[level] + (level == 2 ? L("（默认）", " (default)", "（デフォルト）") : ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            TendencySlider(level: Binding(get: { level }, set: { settings.searchTendency = $0 }), disabled: off)
                .frame(height: 26)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    Text(Self.names[i])
                        .font(.system(size: 12, weight: i == level && !off ? .semibold : .regular))
                        .foregroundStyle(i == level && !off ? AnswerColor.text : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            // 档名和条上的圆点对齐：两端各收进半个滑块。
            .padding(.horizontal, -8)
            Text(detail)
                .font(.system(size: 13.5))
                .foregroundStyle(level == 4 && !off ? Color(hex: 0x8A4B00) : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(level == 4 && !off ? Color(hex: 0xFFF4E0) : Color(.systemGray6)))
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        if off {
            return L("联网调用是「禁止」，这根条不起作用。在上面改成「开」或「每次询问」", "Web search is Off, so this has no effect. Switch it to On or Ask each time above.", "ウェブ検索が「オフ」なので、この設定は効きません。上で「オン」か「毎回確認」にしてください")
        }
        switch level {
        case 0: return L("直接回答，不去搜。想查时点回答旁边的「使用联网查询」", "Answers without searching. To look something up, tap Search the web next to the answer.", "検索せずに答えます。調べたいときは回答の横の「ウェブで調べる」をタップ")
        case 1: return L("只有你说「查一下」，或问今天的天气、实时价格、汇率、比分时才联网", "Searches only when you ask it to, or for today's weather, live prices, exchange rates and scores.", "「調べて」と頼んだときや、今日の天気・リアルタイムの価格・為替・スコアを聞いたときだけ検索します")
        case 3: return L("在「适中」基础上，产品、公司、人物、政策这类近一两年可能变过的现状也会去查", "On top of Balanced, also checks the current state of products, companies, people and policies that may have changed lately.", "「ふつう」に加えて、製品・会社・人物・制度など、ここ1〜2年で変わったかもしれない現状も調べます")
        case 4: return L("在「积极」基础上，自己没把握的具体事实（数字、日期、时刻表、参数）也去查。事实类问题基本都会联网，费用会多一些。", "On top of Often, also checks specific facts it isn't sure of (numbers, dates, timetables, specs). Most factual questions will search, so it costs a bit more.", "「多め」に加えて、自信のない具体的な事実（数字・日付・時刻表・仕様）も調べます。事実を聞く質問はほぼ検索するので、費用が少し増えます。")
        default: return L("答案取决于最近几天到几周会变的事（天气、行情、新闻、刚发布的产品）才联网；拿不准就直接回答", "Searches when the answer depends on things that change over days or weeks (weather, markets, news, new releases). If unsure, it just answers.", "答えが数日〜数週間で変わること（天気・相場・ニュース・新製品）によるときだけ検索します。迷ったらそのまま答えます")
        }
    }
}

/// 5 档的条：轨道 6 高 #E5E5EA，已选部分 #7DD3FC→#0284C7，档位 6pt 小圆点（已过白、未到 #C7C7CC），26pt 白色滑块带阴影。
private struct TendencySlider: View {
    @Binding var level: Int
    var disabled: Bool

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 13
            let width = geo.size.width - inset * 2
            let x = { (i: Int) in inset + width * CGFloat(i) / 4 }
            let mid = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color(hex: 0xE5E5EA))
                    .frame(width: width, height: 6)
                    .position(x: inset + width / 2, y: mid)
                Capsule().fill(disabled ? AnyShapeStyle(Color(.systemGray3))
                               : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x7DD3FC), Color(hex: 0x0284C7)], startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(x(level) - inset, 6), height: 6)
                    .position(x: inset + max(x(level) - inset, 6) / 2, y: mid)
                ForEach(0..<5, id: \.self) { i in
                    Circle().fill(i <= level ? Color.white : Color(hex: 0xC7C7CC))
                        .frame(width: 6, height: 6)
                        .position(x: x(i), y: mid)
                }
                Circle().fill(Color.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(disabled ? 0.08 : 0.2), radius: 3, y: 1)
                    .position(x: x(level), y: mid)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !disabled else { return }
                let step = Int(((value.location.x - inset) / width * 4).rounded())
                let next = min(max(step, 0), 4)
                if next != level {
                    level = next
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            })
        }
        .opacity(disabled ? 0.6 : 1)
        .accessibilityElement()
        .accessibilityLabel(L("调用偏好", "Search preference", "検索の頻度"))
        .accessibilityValue(SearchTendencyCard.names[level])
        .accessibilityAdjustableAction { direction in
            guard !disabled else { return }
            switch direction {
            case .increment: level = min(level + 1, 4)
            case .decrement: level = max(level - 1, 0)
            @unknown default: break
            }
        }
    }
}

/// 编辑一条问答风格：名字、提示词（空着就按「简短直接，几句话说清楚」），设为默认、删除。
struct AnswerStyleEditor: View {
    @Binding var style: StylePreset
    @Binding var settings: EnclaveSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var optimizer = PromptOptimizer()
    @FocusState private var editingPrompt: Bool

    private var builtIn: StylePreset? { StylePreset.answerDefaults.first { $0.name == style.name } }

    var body: some View {
        Form {
            Section {
                TextField(L("名称", "Name", "名前"), text: $style.name)
            } header: {
                Text(L("名称", "Name", "名前"))
            } footer: {
                Text(L("显示在键盘「问答 ⌄」的下拉里；问答键上固定写「问答」。", "Shown in the keyboard's Ask ⌄ menu. The key itself always reads Ask.", "キーボードの「質問 ⌄」のメニューに表示されます。キーには常に「質問」と表示されます。"))
            }
            Section {
                TextEditor(text: $style.prompt)
                    .focused($editingPrompt)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if style.prompt.isEmpty {
                            Text(AnswerStyleSections.answerFallback)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                PromptOptimizeButton(optimizer: optimizer, prompt: style.prompt, name: style.displayName, answer: true)
            } header: {
                Text(L("怎么回答", "How to answer", "答え方"))
            } footer: {
                Text(L("每次问答都会带上，比如「先给结论，一般不超过三句」。空着就按「简短直接，几句话说清楚」回答。只管问答，改写不受影响。", "Sent with every question, e.g. \"lead with the answer, three sentences at most\". Empty means brief and direct. Rewrites aren't affected.", "質問のたびに送られます（例：「結論から、3文以内で」）。空なら短く率直に答えます。書き換えには影響しません。"))
            }
            if let result = optimizer.result {
                PromptOptimizedSection(optimizer: optimizer, result: result, prompt: $style.prompt)
            }
            Section {
                if let builtIn {
                    Button(L("恢复这条的默认内容", "Restore default text", "元の内容に戻す")) { style.prompt = builtIn.prompt }
                        .disabled(style.prompt == builtIn.prompt)
                }
                Button(L("设为默认问答风格", "Set as default", "デフォルトにする")) { settings.selectedAnswerStyleID = style.id }
                    .disabled(settings.selectedAnswerStyle?.id == style.id)
                Button(L("删除这条问答风格", "Delete answer style", "この回答スタイルを削除"), role: .destructive) {
                    let id = style.id
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        settings.answerStyles.removeAll { $0.id == id }
                        if settings.selectedAnswerStyleID == id { settings.selectedAnswerStyleID = nil }
                    }
                }
                .disabled(settings.answerStyles.count <= 1)
            }
        }
        .navigationTitle(L("编辑问答风格", "Edit answer style", "回答スタイルを編集"))
        .doneEditingButton(editingPrompt)
        .onDisappear { optimizer.cancel() }
    }
}
