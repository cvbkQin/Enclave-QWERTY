import SwiftUI

/// 「提示词」标签（原「风格」）。
struct StylesTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            StylesView(settings: $store.settings)
        }
    }
}

#if DEBUG
/// 截图用（-promptsDebug）：提示词页停在某个样子。
enum PromptsDebug {
    static var scene: String?
}
#endif

/// 提示词（PR1，原「风格」）：顶部说明小卡、全部提示词（每行本周次数）、添加、恢复默认。
/// 左滑删除，「编辑」拖动排序；这里的顺序就是键盘「润色▾」里的顺序。存储还是 StylePreset。
struct StylesView: View {
    @Binding var settings: EnclaveSettings
    @State private var confirmReset = false
    /// 每条提示词本周执行的次数，进页面时读一次。
    @State private var weekCounts: [UUID: Int] = [:]
    /// 截图用：直接打开这一条的编辑页。
    @State private var debugEditing: UUID?

    var body: some View {
        List {
            Section {
                HowItWorksCard(name: settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える"))
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                TabTitle(caption: caption, title: L("提示词", "Prompts", "プロンプト"))
                    // 标题到第一张卡片和首页一样约 18pt。
                    .padding(.bottom, 11)
                    .dashFormCard()
            }
            Section {
                ForEach($settings.styles) { $style in
                    NavigationLink {
                        StyleEditor(style: $style, settings: $settings)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(style.displayName).font(.body)
                                    if style.id == settings.selectedStyle?.id {
                                        DashTag(text: L("默认", "Default", "デフォルト"), color: DashColor.ai)
                                    }
                                }
                                Text(Self.summary(style))
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(L("\(weekCounts[style.id] ?? 0) 次", "\(weekCounts[style.id] ?? 0)×", "\(weekCounts[style.id] ?? 0) 回"))
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 2)
                        // 分隔线都从名字左边开始，不要有的通栏。
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                }
                .onDelete { settings.styles.remove(atOffsets: $0) }
                .onMove { settings.styles.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text(L("全部提示词", "All prompts", "すべてのプロンプト"))
                    Spacer()
                    // 系统的编辑按钮（PH2 挪到分组标题右边）：自己管 editMode 时拖过一次后再拖、点 ⊖ 都没反应。
                    EditButton()
                        .font(.system(size: 15))
                        .tint(DashColor.ai)
                        .environment(\.locale, Loc.locale)
                        .textCase(nil)
                }
            } footer: {
                Text(L("顺序就是键盘「\(settings.selectedStyle?.displayName ?? "润色") ▾」里的顺序。次数是本周的。",
                       "This is the order in the keyboard's \(settings.selectedStyle?.displayName ?? "Polish") ▾ menu. Counts are for this week.",
                       "キーボードの「\(settings.selectedStyle?.displayName ?? "整える") ▾」もこの順番です。回数は今週の分です。"))
            }

            if !missingDefaults.isEmpty {
                Section {
                    ForEach(missingDefaults) { preset in
                        Button {
                            // 换个新 id：本周次数从 0 算，不和删掉的那条混在一起。
                            settings.styles.append(StylePreset(name: preset.name, prompt: preset.prompt))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.displayName).font(.body).foregroundStyle(.primary)
                                    Text(Self.summary(preset)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Label(L("加回", "Restore", "戻す"), systemImage: "arrow.uturn.backward")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DashColor.ai)
                            }
                        }
                    }
                } header: {
                    Text(L("删掉的预设", "Deleted presets", "削除したプリセット"))
                } footer: {
                    Text(L("加回到列表最后，内容是默认的；你自己的提示词不受影响。", "Adds it back at the end with its default text. Your own prompts stay as they are.", "デフォルトの内容でリストの最後に戻します。自分のプロンプトはそのままです。"))
                }
            }
            Section {
                Button {
                    settings.styles.append(StylePreset(name: L("新提示词", "New prompt", "新しいプロンプト"), prompt: ""))
                } label: {
                    Label(L("添加提示词", "Add prompt", "プロンプトを追加"), systemImage: "plus")
                }
            }
            Section {
                Button(L("恢复默认提示词", "Restore default prompts", "デフォルトのプロンプトに戻す")) { confirmReset = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .tint(DashColor.ai)
        .confirmationDialog(L("恢复成默认的 5 条提示词？你改过和添加的会被删掉。", "Restore the 5 default prompts? Prompts you changed or added will be removed.", "デフォルトの 5 つのプロンプトに戻しますか？変更・追加したものは削除されます。"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("恢复默认提示词", "Restore default prompts", "デフォルトのプロンプトに戻す"), role: .destructive) {
                settings.styles = StylePreset.defaults
                settings.selectedStyleID = nil
            }
        }
        .navigationTitle(L("提示词", "Prompts", "プロンプト"))
        .tabRootPage()
        .onAppear {
            weekCounts = Dictionary(uniqueKeysWithValues: settings.styles.map { ($0.id, UsageStats.week("polish.style.\($0.id.uuidString)")) })
            #if DEBUG
            applyDebugScene()
            #endif
        }
        .navigationDestination(isPresented: Binding(get: { debugEditing != nil }, set: { if !$0 { debugEditing = nil } })) {
            if let index = settings.styles.firstIndex(where: { $0.id == debugEditing }) {
                StyleEditor(style: $settings.styles[index], settings: $settings)
            }
        }
    }

    #if DEBUG
    private func applyDebugScene() {
        guard let scene = PromptsDebug.scene else { return }
        PromptsDebug.scene = scene == "optimized" ? scene : nil
        settings.styles = StylePreset.defaults
        switch scene {
        case "missing":
            settings.styles.removeAll { $0.name == "正式" || $0.name == "结构" }
        case "empty":
            let blank = StylePreset(name: L("新提示词", "New prompt", "新しいプロンプト"), prompt: "")
            settings.styles.append(blank)
            debugEditing = blank.id
        case "optimized":
            let custom = StylePreset(name: "客户", prompt: "发给客户的，客气点，别太啰嗦")
            settings.styles.append(custom)
            debugEditing = custom.id
        default: break
        }
    }
    #endif

    /// 自带的 5 条里被删掉的：名字和内容都找不到了才算（改了名或改了内容的还在列表里）。
    /// 「润色」默认内容为空：列表里还有任何一条内容为空就算没删，免得改名后加回变成两条空的。
    private var missingDefaults: [StylePreset] {
        StylePreset.defaults.filter { preset in
            !settings.styles.contains { $0.name == preset.name || $0.prompt == preset.prompt }
        }
    }

    /// 标题上的灰字：「5 条 · 默认「润色」」。
    private var caption: String {
        let name = settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")
        let count = settings.styles.count
        return L("\(count) 条 · 默认「\(name)」", "\(count) prompts · Default: \(name)", "\(count) 件 · デフォルト「\(name)」")
    }

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

/// 顶部说明小卡：左边画键盘上的「✨ + 润色▾」，右边一句怎么用。
private struct HowItWorksCard: View {
    var name: String

    var body: some View {
        HStack(spacing: 12) {
            KeyboardChipPreview(name: name)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGray6)))
            Text(L("点 ✨，用当前这条提示词改输入框里的话；点名字换一条。", "Tap ✨ to run the current prompt on your text. Tap the name to switch.", "✨ で、いまのプロンプトを入力欄の文章に使います。名前をタップで切り替え。"))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
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

private struct StyleEditor: View {
    @Binding var style: StylePreset
    @Binding var settings: EnclaveSettings
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var optimizer = PromptOptimizer()

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
                Text(L("显示在键盘 ✨ 旁边，四个字以内最好。", "Shown next to ✨ on the keyboard. Keep it short.", "キーボードの ✨ の横に表示されます。短めがおすすめです。"))
            }
            Section {
                TextEditor(text: $style.prompt)
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
                optimizeButton
            } header: {
                Text(L("提示词内容", "Prompt", "プロンプトの内容"))
            } footer: {
                Text(L("写清楚场景和要求，什么都可以写，比如「翻成日语，发给客户，客气一点」。每次点 ✨ 都会带上。", "Describe the situation and what you want. Anything goes, like \"translate into Japanese for a client, keep it polite\". It's sent every time you tap ✨.", "場面と要望をはっきり書きます。何でも書けます（例：「日本語に訳して、お客様向けに丁寧に」）。✨ をタップするたびに送られます。"))
            }
            if let result = optimizer.result {
                optimizedSection(result)
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
                Button(L("设为默认提示词", "Set as default", "デフォルトにする")) { settings.selectedStyleID = style.id }
                    .disabled(settings.selectedStyle?.id == style.id)
                Button(L("删除这条提示词", "Delete prompt", "このプロンプトを削除"), role: .destructive) {
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
        .navigationTitle(L("编辑提示词", "Edit prompt", "プロンプトを編集"))
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

    // MARK: AI 优化

    /// 提示词框下面一行：「✨ AI 优化」，生成中显示转圈，出错写一行红字。
    @ViewBuilder
    private var optimizeButton: some View {
        let empty = style.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if optimizer.running {
                optimizer.cancel()
            } else {
                optimizer.run(name: style.displayName, prompt: style.prompt, settings: store.settings, apiKey: store.apiKey)
            }
        } label: {
            HStack(spacing: 6) {
                if optimizer.running {
                    ProgressView().controlSize(.small)
                    Text(L("AI 正在优化…点一下取消", "Optimizing… tap to cancel", "AI が最適化中…タップでキャンセル"))
                } else {
                    Image(systemName: "sparkles")
                    Text(L("AI 优化提示词", "Improve with AI", "AI で改善"))
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(empty && !optimizer.running ? Color.secondary : AppColor.deepPurple)
        }
        .disabled(empty && !optimizer.running)
        if empty && !optimizer.running {
            Text(L("先写几个字，AI 再帮你改清楚", "Write a few words first, then AI can sharpen it", "数文字書いてから AI で整えられます"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        if let error = optimizer.error {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    /// AI 给的结果：优化后的整段（「用这一版」替换掉现在的），下面几条还能补的要求（点一下加进去）。
    private func optimizedSection(_ result: PromptOptimizer.Result) -> some View {
        Section {
            Text(result.prompt)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColor.chipSelectedFill))
            HStack(spacing: 12) {
                Button(L("用这一版", "Use this", "これを使う")) {
                    style.prompt = result.prompt
                    optimizer.result = nil
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L("不用了", "Dismiss", "使わない")) { optimizer.result = nil }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
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
            }
        } header: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text(L("AI 优化结果", "AI suggestion", "AI の提案"))
            }
        } footer: {
            Text(L("「用这一版」会换掉上面的提示词内容；下面的建议点一下加进这一版。", "\"Use this\" replaces the prompt above. Tap a suggestion to add it to this version.", "「これを使う」で上のプロンプトを置き換えます。下の候補はタップでこの案に追加します。"))
        }
    }
}

/// 编辑提示词页的「AI 优化」：把名称和提示词发给接口页配置的模型，让它改得更清楚具体，另给几条能补的要求。
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

    func run(name: String, prompt: String, settings: EnclaveSettings, apiKey: String) {
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
        let messages = Self.messages(name: name, prompt: prompt)
        let start = Date()
        task = Task { [weak self] in
            var raw = ""
            var failure: String?
            do {
                for try await piece in client.stream(messages) { raw += piece }
            } catch is CancellationError {
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            guard let self, !Task.isCancelled else { return }
            self.running = false
            let ok = failure == nil
            UsageStats.recordRequest(ms: Int(Date().timeIntervalSince(start) * 1000), ok: ok)
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

    static func messages(name: String, prompt: String) -> [ChatMessage] {
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
