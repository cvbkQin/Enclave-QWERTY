import SwiftUI
import StoreKit

// 接口配置页重排（11-03 交付 CF1–CF5，功能对照表「接口配置页重排」）：一开始是空的，只列自己添加的配置。
// 「＋ 添加配置」弹出服务商模板（CF2），选一家进新建配置页（CF3，名称 / 连接 / 联网测试 / 生成参数），保存后进列表。
// 润色、问答共用一组配置，各自记正在用哪一条（按地址 + 模型 + Key 认）。

// MARK: - 列表里的一条（CF4、CF5）

/// 每行 logo、名称（正在用的加粗），下行等宽小字「模型 · 地址」；右边 ✓（正在用）和 ›。
/// 问答页名称后面按联网测试结果加标签：可联网 / 不能联网（整行 45% 透明，仍可选）/ 联网未测试。
struct ConfigRow: View {
    var item: SavedAPI
    var current: Bool
    var answer: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void

    var body: some View {
        let probe = WebSearchProbe.stored(baseURL: item.baseURL, model: item.model)
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    ProviderLogo(provider: ConfigTemplate.of(item).provider, size: 30, corner: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.system(size: 16, weight: current ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if answer { WebProbeTag(verdict: probe) }
                        }
                        Text(detail)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if current {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DashColor.ai)
                    }
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(current ? .isSelected : [])
            Button(action: onEdit) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("编辑「\(item.name)」", "Edit “\(item.name)”", "「\(item.name)」を編集"))
        }
        .opacity(answer && probe == .offline ? 0.45 : 1)
    }

    private var detail: String {
        let url = URL(string: item.baseURL)
        let host = url?.host.map { host in url?.port.map { "\(host):\($0)" } ?? host } ?? item.baseURL
        return "\(item.model) · \(host)"
    }
}

/// 问答页名称后的小标签：🌐 可联网（绿）/ 不能联网（灰）/ 联网未测试（描边灰字）。
struct WebProbeTag: View {
    var verdict: WebSearchProbe.Verdict?

    var body: some View {
        switch verdict {
        case .online:
            HStack(spacing: 2) {
                Image(systemName: "globe").font(.system(size: 9, weight: .semibold))
                Text(L("可联网", "Web", "検索可")).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Color(light: 0x248A3D, dark: 0x6EE7A0))
            .padding(.horizontal, 5).frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(light: 0xE3F4EA, dark: 0x173A24)))
            .fixedSize()
        case .offline:
            Text(L("不能联网", "No web", "検索不可")).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color(light: 0x8E8E93, dark: 0xAEAEB2))
                .padding(.horizontal, 5).frame(height: 17)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(light: 0xF2F2F7, dark: 0x2C2C2E)))
                .fixedSize()
        case nil:
            Text(L("联网未测试", "Web untested", "検索未テスト")).font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color(light: 0x8E8E93, dark: 0xAEAEB2))
                .padding(.horizontal, 5).frame(height: 17)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(light: 0xC7C7CC, dark: 0x48484A), lineWidth: 0.5))
                .fixedSize()
        }
    }
}

// MARK: - 空状态（CF1）

struct EmptyConfigCard: View {
    var locked: Bool
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "powerplug")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(L("还没有接口配置", "No API setups yet", "API の設定はまだありません"))
                .font(.system(size: 17, weight: .semibold))
            Text(L("选一家服务商，填上 API Key 就能用。可以加好几个，随时切换。",
                   "Pick a provider and enter your API key. Add as many as you like and switch any time.",
                   "サービスを選んで API キーを入力するだけ。いくつでも追加して切り替えられます。"))
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAdd) {
                Label(L("添加配置", "Add setup", "設定を追加"), systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DashColor.ai))
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .opacity(locked ? 0.45 : 1)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
    }
}

// MARK: - 添加配置（CF2，底部弹层）

/// 「选一家服务商，自动填好地址和推荐模型」：每行 logo、名称、副标题、右边「📖 教程」和 ›；下面「自己搭的服务」一组只有自定义。
struct AddConfigSheet: View {
    var onPick: (ConfigTemplate) -> Void
    var onTutorial: (ConfigTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(ConfigTemplate.providers) { template in row(template) }
            } header: {
                Text(L("选一家服务商，自动填好地址和推荐模型", "Pick a provider to fill in the URL and a recommended model", "サービスを選ぶと URL とおすすめモデルが入ります"))
                    .textCase(nil)
            } footer: {
                Text(L("千问的两个平台 Key 不通用：在哪儿申请的 Key 就选哪个。",
                       "The two Qwen platforms use different keys: pick the one where you got your key.",
                       "Qwen の 2 つのプラットフォームはキーが共通ではありません。キーを取得した方を選んでください。"))
            }
            Section {
                row(.custom)
            } header: {
                Text(L("自己搭的服务", "Self-hosted", "セルフホスト")).textCase(nil)
            } footer: {
                if Storefront.isMainlandChina {
                    Text("DeepSeek、Kimi、通义千问、智谱 GLM、腾讯混元均已完成生成式人工智能服务备案。飞地输入法不提供模型，用你自己的 API Key 直接连接服务商。")
                }
            }
        }
        .navigationTitle(L("添加配置", "Add setup", "設定を追加"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(L("关闭", "Close", "閉じる"))
            }
        }
    }

    private func row(_ template: ConfigTemplate) -> some View {
        HStack(spacing: 10) {
            Button { onPick(template) } label: {
                HStack(spacing: 10) {
                    ProviderLogo(provider: template.provider, size: 30, corner: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        Text(template.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if template.hasTutorial {
                Button { onTutorial(template) } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "book").font(.system(size: 11, weight: .semibold))
                        Text(L("教程", "Guide", "ガイド")).font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Color(light: 0x5B4BE8, dark: 0xB4A9FF))
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { onPick(template) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}

extension ConfigTemplate {
    /// 有分步教程的几家。千问 AI 平台的教程还没写，先不显示入口。
    var hasTutorial: Bool { self != .qwenAI && GuideTutorial.of(provider) != nil }
}

// MARK: - 新建 / 编辑配置（CF3、CF3b）

struct ConfigEditor: View {
    /// 编辑已有的；nil 是新建。
    let existing: SavedAPI?
    let template: ConfigTemplate
    /// 从问答页进来：模型下拉只列能联网的（MF）。
    let answer: Bool
    var onTutorial: (ConfigTemplate) -> Void
    var onClose: () -> Void

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter

    @State private var name: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var temperature: Double
    @State private var maxTokens: Int
    @State private var modelMenuOpen = false
    @State private var typingModel: Bool
    @State private var connection: Connection = .idle
    @State private var probe: Probe
    @State private var needsPrivacy = false
    @State private var confirmDelete = false
    @FocusState private var modelFocused: Bool
    @FocusState private var keyFocused: Bool

    /// 只露前 3 位和后 4 位：「sk-••••••3f9a」。
    static func masked(_ key: String) -> String {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count > 8 else { return String(repeating: "•", count: max(key.count, 4)) }
        return String(key.prefix(3)) + String(repeating: "•", count: 6) + String(key.suffix(4))
    }

    enum Connection: Equatable { case idle, running, ok(Double), failed(String) }
    enum Probe: Equatable { case untested, running, online, offline, failed }

    init(existing: SavedAPI?, template: ConfigTemplate, answer: Bool,
         onTutorial: @escaping (ConfigTemplate) -> Void, onClose: @escaping () -> Void) {
        self.existing = existing
        self.template = template
        self.answer = answer
        self.onTutorial = onTutorial
        self.onClose = onClose
        let defaults = EnclaveSettings()
        if let existing {
            _name = State(initialValue: existing.name)
            _baseURL = State(initialValue: existing.baseURL)
            _model = State(initialValue: existing.model)
            _apiKey = State(initialValue: existing.apiKey ?? "")
            _temperature = State(initialValue: existing.temperature ?? defaults.temperature)
            _maxTokens = State(initialValue: existing.maxTokens ?? template.maxTokens)
        } else {
            _name = State(initialValue: SavedAPIStore.uniqueName(template.defaultName))
            _baseURL = State(initialValue: template.baseURL)
            _model = State(initialValue: template.model)
            _apiKey = State(initialValue: "")
            _temperature = State(initialValue: defaults.temperature)
            _maxTokens = State(initialValue: template.maxTokens)
        }
        _typingModel = State(initialValue: template == .custom && existing == nil)
        let url = existing?.baseURL ?? template.baseURL, model = existing?.model ?? template.model
        _probe = State(initialValue: Self.storedProbe(baseURL: url, model: model))
    }

    private static func storedProbe(baseURL: String, model: String) -> Probe {
        switch WebSearchProbe.stored(baseURL: baseURL, model: model) {
        case .online: return .online
        case .offline: return .offline
        case nil: return .untested
        }
    }

    private var trimmedURL: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedURL.isEmpty && !trimmedModel.isEmpty }
    private var custom: Bool { template == .custom }

    /// 用这一页填的值拼一份设置：测试连接、联网测试、模型下拉都按它走。
    private var draftSettings: EnclaveSettings {
        var settings = store.settings
        settings.baseURL = trimmedURL
        settings.model = trimmedModel
        settings.temperature = temperature
        settings.maxTokens = maxTokens
        return settings
    }

    var body: some View {
        Form {
            Section {
            } header: {
                providerCard.dashFormCard()
            }
            Section {
                HStack {
                    TextField(L("名称", "Name", "名前"), text: $name)
                    Text(L("在列表里显示", "Shown in the list", "一覧に表示")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("名称", "Name", "名前"))
            }
            connectionSection
            webSection
            generationSection
            if existing != nil {
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text(L("删除这个配置", "Delete this setup", "この設定を削除")).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? L("新建配置", "New setup", "新しい設定") : L("编辑配置", "Edit setup", "設定を編集"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("取消", "Cancel", "キャンセル")) { onClose() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("保存", "Save", "保存")) { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onChange(of: baseURL) { _ in fieldsChanged() }
        .onChange(of: model) { _ in fieldsChanged() }
        .onChange(of: apiKey) { _ in connection = .idle }
        .alert(L("用 AI 之前，先同意隐私政策", "Agree to the Privacy Policy to use AI", "AI を使う前にプライバシーポリシーに同意してください"), isPresented: $needsPrivacy) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("阅读并同意", "Read and Agree", "読んで同意する")) {
                onClose()
                router.showsPrivacyWelcome = true
            }
        } message: {
            Text(L("同意后才能测试接口和使用 AI。拼音输入不受影响。", "Agree first to test the API and use AI. Pinyin input still works.", "同意すると API のテストと AI が使えます。ピンイン入力はそのまま使えます。"))
        }
        .confirmationDialog(L("删除「\(name)」？", "Delete “\(name)”?", "「\(name)」を削除しますか？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("删除", "Delete", "削除"), role: .destructive) {
                if let existing { store.deleteSavedAPI(existing.id) }
                onClose()
            }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        }
    }

    /// 地址或模型改了：连接结果作废，联网结果换成这一组记下的（没测过就是未测试）。
    private func fieldsChanged() {
        connection = .idle
        if probe != .running { probe = Self.storedProbe(baseURL: trimmedURL, model: trimmedModel) }
        modelMenuOpen = false
    }

    // MARK: 服务商卡

    private var providerCard: some View {
        HStack(spacing: 12) {
            ProviderLogo(provider: template.provider, size: 42, corner: 11)
            VStack(alignment: .leading, spacing: 3) {
                Text(custom ? L("自定义", "Custom", "カスタム") : template.title)
                    .font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text(template.platform).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    if template.hasTutorial {
                        Button { onTutorial(template) } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "book").font(.system(size: 11, weight: .semibold))
                                Text(L("配置教程", "Setup guide", "設定ガイド")).font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(Color(light: 0x5B4BE8, dark: 0xB4A9FF))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
    }

    // MARK: 连接

    private var connectionSection: some View {
        Section {
            HStack {
                Text(L("API 地址", "API URL", "API の URL"))
                TextField(custom ? "http://192.168.1.100:11434/v1" : template.baseURL, text: $baseURL)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            modelRow
            HStack {
                Text("API Key")
                // 不用 SecureField：系统会把地址 + 密码框当成登录表单，保存时弹「保存密码？」。
                // 改成普通输入框，没在编辑时盖上只露头尾的「sk-••••••3f9a」（CF3）。
                ZStack(alignment: .trailing) {
                    TextField(L("自建服务可以留空", "Optional for self-hosted", "セルフホストなら空欄で可"), text: $apiKey)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($keyFocused)
                        .opacity(keyFocused || apiKey.isEmpty ? 1 : 0)
                    if !keyFocused, !apiKey.isEmpty {
                        Text(Self.masked(apiKey))
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                if apiKey.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                        DispatchQueue.main.async { apiKey = text }
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                    .tint(DashColor.ai)
                    .controlSize(.small)
                }
            }
            testConnectionRow
        } header: {
            Text(L("连接", "Connection", "接続"))
        } footer: {
            Text(custom
                 ? L("Ollama 这类自己电脑上的模型：把地址里的 IP 换成运行它的电脑的局域网地址，地址填到 /v1。", "For a model on your own computer, such as Ollama, replace the IP with that computer's local address. The URL ends with /v1.", "Ollama など自分のパソコンのモデルは、IP をそのパソコンのローカルアドレスに置き換えます。URL は /v1 までです。")
                 : L("地址和模型是\(template.title)的推荐值，可以直接改，不影响别的配置。", "The URL and model are \(template.title)'s recommended values. Edit them freely; other setups aren't affected.", "URL とモデルは \(template.title) のおすすめ値です。自由に変えられ、ほかの設定には影響しません。"))
                + Text(L("API Key 只存在本机钥匙串里。", " The API key stays in this iPhone's keychain.", "API キーはこの iPhone のキーチェーンにだけ保存されます。"))
        }
    }

    private var showsMenu: Bool { !trimmedURL.isEmpty && !ModelList.isUnsupported(trimmedURL) }

    private var modelRow: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Text(L("模型", "Model", "モデル"))
                Spacer(minLength: 8)
                if showsMenu && !typingModel {
                    Button {
                        if router.privacyAgreed {
                            withAnimation(.easeOut(duration: 0.2)) { modelMenuOpen.toggle() }
                        } else {
                            needsPrivacy = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(trimmedModel.isEmpty ? L("选择模型", "Choose a model", "モデルを選択") : trimmedModel)
                                .foregroundStyle(trimmedModel.isEmpty ? Color.secondary : Color.primary)
                                .lineLimit(1).truncationMode(.middle)
                            Image(systemName: modelMenuOpen ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DashColor.ai, lineWidth: modelMenuOpen ? 1.5 : 0))
                    }
                    .buttonStyle(.borderless)
                } else {
                    TextField(custom ? "qwen2.5:7b" : template.model, text: $model)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($modelFocused)
                }
            }
            if modelMenuOpen && showsMenu && !typingModel {
                ModelDropdown(baseURL: trimmedURL, apiKey: apiKey, current: trimmedModel, answer: answer) { picked in
                    model = picked
                    withAnimation(.easeOut(duration: 0.2)) { modelMenuOpen = false }
                } onManual: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        modelMenuOpen = false
                        typingModel = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { modelFocused = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
            }
        }
    }

    /// 「测试连接」整行浅紫按钮，右边结果「● 通了 · 0.9 秒」/ 失败原因。
    private var testConnectionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { runConnectionTest() } label: {
                    Group {
                        if connection == .running {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L("测试连接", "Test connection", "接続テスト"))
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DashColor.ai)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DashColor.ai.opacity(0.12)))
                }
                .buttonStyle(.borderless)
                .disabled(!canSave || connection == .running)
                if case .ok(let seconds) = connection {
                    HStack(spacing: 4) {
                        Circle().fill(DashColor.ok).frame(width: 7, height: 7)
                        Text(L("通了 · \(String(format: "%.1f", seconds)) 秒", "OK · \(String(format: "%.1f", seconds)) s", "OK・\(String(format: "%.1f", seconds)) 秒"))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DashColor.ok)
                    .fixedSize()
                }
            }
            if case .failed(let message) = connection {
                Text(message).font(.system(size: 12.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runConnectionTest() {
        guard router.privacyAgreed else { needsPrivacy = true; return }
        connection = .running
        let settings = draftSettings, key = apiKey
        Task { @MainActor in
            let start = Date()
            var raw = ""
            do {
                for try await piece in LLMClient(settings: settings, apiKey: key).stream([.user("只回复两个字：你好")], retries: 0) { raw += piece }
                connection = ModelOutput.clean(raw).isEmpty
                    ? .failed(L("连上了，但模型没有返回内容。", "Connected, but the model returned nothing.", "接続できましたが、モデルから応答がありませんでした。"))
                    : .ok(Date().timeIntervalSince(start))
            } catch {
                connection = .failed(AppStore.testFailureText(error, UsageStats.Request.Failure.of(error)))
            }
        }
    }

    // MARK: 联网（CF3b）

    private var webSection: some View {
        Section {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("联网", "Web search", "Web 検索"))
                    Text(L("问一句今天的新闻试试 · 每次约 1 分钱", "Asks about today to check · about ¥0.01 each time", "今日のことを聞いて確認・1 回約 0.01 元"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                probeStatus
            }
        } header: {
            Text(L("联网（问答用）", "Web search (for Q&A)", "Web 検索（質問用）"))
        } footer: {
            Text(L("结果按「地址 + 模型」记住，换了任一项要重新测。不能联网的也能用来问答，只是答不了最新消息。",
                   "The result is remembered per URL + model; change either and test again. Models without web search still answer, just not about the latest news.",
                   "結果は URL + モデルごとに記録され、どちらかを変えると再テストが必要です。Web 検索できないモデルも質問には使えますが、最新情報には答えられません。"))
        }
    }

    @ViewBuilder
    private var probeStatus: some View {
        switch probe {
        case .untested:
            HStack(spacing: 8) {
                Text(L("未测试", "Not tested", "未テスト")).font(.system(size: 13)).foregroundStyle(.secondary)
                probeButton(L("测试", "Test", "テスト"), filled: true)
            }
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L("正在问「今天上海天气」", "Asking about today's weather", "今日の天気を質問中"))
                    .font(.system(size: 12.5)).foregroundStyle(DashColor.ai).lineLimit(2)
            }
            .frame(maxWidth: 150, alignment: .trailing)
        case .online:
            HStack(spacing: 8) {
                WebProbeTag(verdict: .online)
                probeButton(L("重测", "Retest", "再テスト"), filled: false)
            }
        case .offline:
            HStack(spacing: 8) {
                Text(L("这个模型不能联网", "This model can't search", "このモデルは検索不可")).font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0xD97706)).lineLimit(2).multilineTextAlignment(.trailing)
                probeButton(L("重测", "Retest", "再テスト"), filled: false)
            }
        case .failed:
            HStack(spacing: 6) {
                Text(L("没测成", "Test failed", "テスト失敗")).font(.system(size: 13)).foregroundStyle(.secondary)
                probeButton(L("重试", "Retry", "再試行"), filled: false)
            }
        }
    }

    private func probeButton(_ title: String, filled: Bool) -> some View {
        Button { runProbe() } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? .white : DashColor.ai)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(filled ? DashColor.ai : DashColor.ai.opacity(0.12)))
        }
        .buttonStyle(.borderless)
        .disabled(!canSave)
    }

    private func runProbe() {
        guard router.privacyAgreed else { needsPrivacy = true; return }
        probe = .running
        let settings = draftSettings, key = apiKey
        Task { @MainActor in
            do {
                let verdict = try await WebSearchProbe.run(settings: settings, apiKey: key)
                // 测的时候改了地址或模型：这次结果不算这一组的。
                guard settings.baseURL == trimmedURL, settings.model == trimmedModel else {
                    probe = Self.storedProbe(baseURL: trimmedURL, model: trimmedModel)
                    return
                }
                probe = verdict == .online ? .online : .offline
            } catch {
                probe = .failed
            }
        }
    }

    // MARK: 生成参数

    private var generationSection: some View {
        let fixed = draftSettings.usesFixedTemperature
        return Section {
            HStack(spacing: 12) {
                Text(L("温度", "Temperature", "温度"))
                Slider(value: $temperature, in: 0...1.5, step: 0.1).tint(DashColor.ai)
                Text(String(format: "%.1f", temperature))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .disabled(fixed)
            .opacity(fixed ? 0.45 : 1)
            HStack(spacing: 12) {
                Text(L("最多字数", "Max output", "最大出力"))
                Text("\(maxTokens)").font(.system(size: 15, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Stepper("", value: $maxTokens, in: 256...8192, step: 256).labelsHidden()
            }
        } header: {
            Text(L("生成参数", "Generation", "生成パラメータ"))
        } footer: {
            Text(fixed
                 ? L("Kimi K 系列用固定温度，温度不生效。", "Kimi K models use a fixed temperature.", "Kimi K シリーズは温度が固定です。")
                 : L("温度越低越稳定，润色建议 0.2–0.5。跟着这个配置走。", "Lower is steadier; 0.2–0.5 works well for polishing. Saved with this setup.", "低いほど安定します。整えるには 0.2〜0.5。この設定ごとに保存されます。"))
        }
    }

    // MARK: 保存

    private func save() {
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = existing ?? SavedAPI(name: "", baseURL: "", model: "")
        item.name = finalName.isEmpty ? SavedAPIStore.uniqueName(template.defaultName) : finalName
        item.baseURL = trimmedURL
        item.model = trimmedModel
        item.template = template.rawValue
        item.temperature = temperature
        item.maxTokens = maxTokens
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing == nil {
            store.addConfig(item, apiKey: key, answer: answer)
        } else {
            store.updateConfig(item, apiKey: key)
        }
        onClose()
    }
}
