import SwiftUI
import StoreKit
import UIKit

// 接口配置页重排（11-03 交付 CF1–CF5，功能对照表「接口配置页重排」）：一开始是空的，只列自己添加的配置。
// 「＋ 添加配置」直接进新建配置页（T102 NC1：名称 / 连接 / 联网测试 / 生成参数），地址从「常用 API 地址」里点一下就填好（NC2），保存后进列表。
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
                    TemplateLogo(template: ConfigTemplate.of(item), size: 30, corner: 8)
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
            Text(L("填上 API 地址和 Key 就能用，常用服务商的地址点一下就填好。可以加好几个，随时切换。",
                   "Enter an API URL and key to get started. Common providers fill in with one tap. Add as many as you like and switch any time.",
                   "API の URL とキーを入れるだけ。よく使うサービスはタップで入力できます。いくつでも追加して切り替えられます。"))
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

// MARK: - 常用 API 地址（T102 NC2）

/// 浅紫胶囊、紫字（「常用 API 地址」「拉取模型」）：浅色 #5B4BE8，深色 #B4A9FF。
private let linkPurple = Color(light: 0x5B4BE8, dark: 0xB4A9FF)

/// 服务商 logo：原来几家照 ProviderLogo；新加的几家用字（豆、文、M、阶、硅），LM Studio 和 Ollama 一样黑底。
struct TemplateLogo: View {
    var template: ConfigTemplate
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        if let mark {
            Text(mark.letter)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(mark.color))
                .accessibilityHidden(true)
        } else {
            ProviderLogo(provider: template.provider, size: size, corner: corner)
        }
    }

    private var mark: (letter: String, color: Color)? {
        switch template {
        case .doubao: return (L("豆", "D", "D"), Color(hex: 0x1F6BFF))
        case .wenxin: return (L("文", "E", "E"), Color(hex: 0x2932E1))
        case .minimax: return ("M", Color(hex: 0xE5484D))
        case .stepfun: return (L("阶", "S", "S"), Color(hex: 0x0E9F9A))
        case .siliconflow: return (L("硅", "S", "S"), Color(hex: 0x7C3AED))
        case .lmstudio: return ("L", Color(light: 0x111111, dark: 0x3A3A3C))
        default: return nil
        }
    }
}

/// 地址按钮前的小标签：紫「非中国大陆」、蓝「中国大陆」、灰「通用」。
struct SideTag: View {
    var side: APISide

    var body: some View {
        Text(side.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
            .fixedSize()
    }

    private var text: Color {
        switch side {
        case .global: return linkPurple
        case .china: return Color(hex: 0x0A84FF)
        case .universal: return .secondary
        }
    }

    private var fill: Color {
        switch side {
        case .global: return AppColor.softFill
        case .china: return Color(hex: 0x0A84FF).opacity(0.12)
        case .universal: return Color(.tertiarySystemFill)
        }
    }
}

/// 地址按钮：浅灰底 + 0.5pt 细边、圆角 11；按下或正在用时浅紫底加 1.5pt 紫框。
private struct EndpointButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let on = selected || configuration.isPressed
        return configuration.label
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(on ? AppColor.softFill : Color(light: 0xF2F2F7, dark: 0x3A3A3C)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(on ? DashColor.ai : Color.primary.opacity(0.1), lineWidth: on ? 1.5 : 0.5))
    }
}

/// 「常用 API 地址」列表：搜索、每家一块（每个地址一个按钮）、「自己电脑上」一组。点一个按钮填入地址、列表收起。
struct CommonURLSheet: View {
    /// 配置页现在填的地址：对上的那个按钮写「✓ 正在用」。
    var current: String
    var onPick: (ConfigTemplate, APIEndpoint) -> Void
    var onTutorial: (ConfigTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var currentURL: String {
        var text = current.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private func matches(_ template: ConfigTemplate) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let words = [template.title, template.defaultName, template.platform(side: .china), template.platform(side: .global)]
            + template.endpoints.map(\.url)
        return words.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let providers = ConfigTemplate.catalog.filter(matches)
        let locals = ConfigTemplate.local.filter(matches)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchField
                    Text(L("点一行，自动填好 API 地址。同一家的中国大陆站和非中国大陆站是两个平台，在哪个站申请的 Key 就点哪一行：两边的 Key 不通用。",
                           "Tap a row to fill in its URL. A provider's Mainland China and overseas sites are separate platforms: pick the one where you got your key. Keys don't work across the two.",
                           "タップすると URL が入ります。中国本土と海外は別のプラットフォームです。キーを取得した方を選んでください。両方のキーは共通ではありません。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                    if !providers.isEmpty {
                        groupHeader(L("服务商", "Providers", "サービス"))
                        VStack(spacing: 0) {
                            ForEach(providers) { template in
                                providerBlock(template)
                                if template != providers.last { Divider().padding(.leading, 54) }
                            }
                        }
                        .background(card)
                    }
                    if !locals.isEmpty {
                        groupHeader(L("自己电脑上", "On your computer", "自分のパソコン"))
                        VStack(spacing: 0) {
                            ForEach(locals) { template in
                                localRow(template)
                                if template != locals.last { Divider().padding(.leading, 54) }
                            }
                        }
                        .background(card)
                        footnote(L("填好后把地址里的 IP 换成运行它的电脑的局域网地址。",
                                   "Then replace the IP with the local address of the computer running it.",
                                   "入力後、IP を動かしているパソコンのローカルアドレスに置き換えてください。"))
                    }
                    if providers.isEmpty && locals.isEmpty {
                        Text(L("没有找到「\(query)」。也可以回到配置页直接填地址。",
                               "Nothing matches “\(query)”. You can also type the URL on the setup page.",
                               "「\(query)」は見つかりません。設定ページで URL を直接入力することもできます。"))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    // 只大陆店面显示，只有中文；「自己电脑上」那组不算服务商（05 备案核对）。
                    if Storefront.isMainlandChina {
                        footnote("列表里的服务商均已完成生成式人工智能服务备案。飞地输入法不提供模型，用你自己的 API Key 直接连接服务商。")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: PadWidth.content)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(L("常用 API 地址", "Common API URLs", "よく使う API の URL"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("关闭", "Close", "閉じる"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(.secondary)
            TextField(L("搜索服务商", "Search providers", "サービスを検索"), text: $query)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
        .padding(.top, 8)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 7)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func providerBlock(_ template: ConfigTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TemplateLogo(template: template, size: 30, corner: 8)
                Text(template.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                if template.hasTutorial {
                    Button { onTutorial(template) } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "book").font(.system(size: 11, weight: .semibold))
                            Text(L("教程", "Guide", "ガイド")).font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(linkPurple)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(template.title)教程", "\(template.title) guide", "\(template.title) ガイド"))
                }
            }
            VStack(spacing: 6) {
                ForEach(template.endpoints, id: \.self) { endpoint in
                    endpointButton(template, endpoint)
                }
            }
            .padding(.leading, 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func endpointButton(_ template: ConfigTemplate, _ endpoint: APIEndpoint) -> some View {
        let inUse = endpoint.url == currentURL
        return Button { onPick(template, endpoint) } label: {
            HStack(spacing: 8) {
                SideTag(side: endpoint.side)
                Text(endpoint.host)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                useLabel(inUse)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(EndpointButtonStyle(selected: inUse))
        .accessibilityLabel("\(template.title) · \(endpoint.side.label) · \(endpoint.host)")
        .accessibilityAddTraits(inUse ? .isSelected : [])
    }

    /// 右边「填入 ›」；正在用的写「✓ 正在用」。
    @ViewBuilder
    private func useLabel(_ inUse: Bool) -> some View {
        if inUse {
            HStack(spacing: 2) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                Text(L("正在用", "In use", "使用中"))
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(linkPurple)
            .fixedSize()
        } else {
            HStack(spacing: 2) {
                Text(L("填入", "Use", "入力"))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(linkPurple)
            .fixedSize()
        }
    }

    private func localRow(_ template: ConfigTemplate) -> some View {
        let endpoint = template.endpoints[0]
        let inUse = endpoint.url == currentURL
        return Button { onPick(template, endpoint) } label: {
            HStack(spacing: 10) {
                TemplateLogo(template: template, size: 30, corner: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                    Text(endpoint.host).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                useLabel(inUse)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ConfigTemplate {
    /// 有分步教程的几家。千问 AI 平台的教程还没写，先不显示入口；新加的几家没有教程。
    var hasTutorial: Bool { self != .qwenAI && provider != .custom && GuideTutorial.of(provider) != nil }
}

/// 地址输入框：UITextField 才能选中一段文字（本机服务选中示例 IP，一打就替换）。等宽 14。
private struct URLTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// 设了就聚焦并选中这段文字，处理完清掉。
    @Binding var select: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        if field.placeholder != placeholder { field.placeholder = placeholder }
        guard let target = select else { return }
        DispatchQueue.main.async {
            select = nil
            field.becomeFirstResponder()
            let range = ((field.text ?? "") as NSString).range(of: target)
            guard range.location != NSNotFound,
                  let start = field.position(from: field.beginningOfDocument, offset: range.location),
                  let end = field.position(from: start, offset: range.length) else { return }
            field.selectedTextRange = field.textRange(from: start, to: end)
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: URLTextField

        init(_ parent: URLTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - 新建 / 编辑配置（CF3、CF3b；T102 NC1 改顺序和服务商卡）

struct ConfigEditor: View {
    /// 编辑已有的；nil 是新建。
    let existing: SavedAPI?
    /// 新建时预先填好哪一家（引导里选了 Ollama）；nil 是空白。
    let initialTemplate: ConfigTemplate?
    /// 从问答页进来：模型下拉只列能联网的（MF）。
    let answer: Bool
    /// 打开教程：哪一家、哪一边（跟这条配置的地址走）。
    var onTutorial: (Provider, APISide?) -> Void
    var onClose: () -> Void

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter

    @State private var name: String
    /// 名称是自动填的服务商名（没自己改过）：换服务商时跟着换。
    @State private var autoName: String?
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var temperature: Double
    @State private var maxTokens: Int
    @State private var modelMenuOpen = false
    @State private var typingModel = false
    @State private var connection: Connection = .idle
    @State private var probe: Probe
    @State private var needsPrivacy = false
    @State private var confirmDelete = false
    /// 开着 Key 同步时删方案：系统确认框（B11），其他设备上的方案和 Key 也会删。
    @State private var confirmSyncedDelete = false
    /// 开着 Key 同步、这条的 Key 还在从 iCloud 钥匙串同步过来（别的设备刚改过）：从什么时候开始等的（02 复审第二轮）。
    @State private var keyPendingSince: Date?
    /// 最后改这条的是哪台设备（脚注里说「从『iPad Air』同步来的」）。
    @State private var keySource: String?
    @State private var showsCommonURLs = false
    /// 从列表填了地址：地址框浅紫底加紫框亮 0.8 秒。
    @State private var urlFlash = false
    /// 地址下面一行灰字：换了服务商清空了什么、本机服务要换 IP。
    @State private var urlNote: String?
    /// 上面那行灰字是哪个地址的：地址再改就收起。
    @State private var notedURL: String?
    /// 让地址框聚焦并选中这段文字（本机服务的示例 IP）。
    @State private var urlSelection: String?
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

    init(existing: SavedAPI?, template: ConfigTemplate? = nil, answer: Bool,
         onTutorial: @escaping (Provider, APISide?) -> Void, onClose: @escaping () -> Void) {
        self.existing = existing
        self.initialTemplate = existing == nil ? template : nil
        self.answer = answer
        self.onTutorial = onTutorial
        self.onClose = onClose
        let defaults = EnclaveSettings()
        if let existing {
            let kind = ConfigTemplate.of(existing)
            _name = State(initialValue: existing.name)
            _autoName = State(initialValue: Self.isAutoName(existing.name, for: kind) ? existing.name : nil)
            _baseURL = State(initialValue: existing.baseURL)
            _model = State(initialValue: existing.model)
            _apiKey = State(initialValue: existing.apiKey ?? "")
            _temperature = State(initialValue: existing.temperature ?? defaults.temperature)
            _maxTokens = State(initialValue: existing.maxTokens ?? kind.maxTokens)
        } else {
            let auto = template.map { SavedAPIStore.uniqueName($0.defaultName) }
            _name = State(initialValue: auto ?? "")
            _autoName = State(initialValue: auto)
            _baseURL = State(initialValue: template?.baseURL ?? "")
            _model = State(initialValue: "")
            _apiKey = State(initialValue: "")
            _temperature = State(initialValue: defaults.temperature)
            _maxTokens = State(initialValue: template?.maxTokens ?? defaults.maxTokens)
        }
        let url = existing?.baseURL ?? template?.baseURL ?? "", model = existing?.model ?? ""
        _probe = State(initialValue: Self.storedProbe(baseURL: url, model: model))
    }

    /// 名称还是服务商名（或「Kimi 2」这样加了号的）：算自动填的。
    private static func isAutoName(_ name: String, for template: ConfigTemplate) -> Bool {
        let base = template.defaultName
        if name == base { return true }
        guard name.hasPrefix(base + " ") else { return false }
        return Int(name.dropFirst(base.count + 1)) != nil
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
    /// 按地址认是哪家（服务商卡、教程、拉模型提示都按它）。
    private var detected: ConfigTemplate { ConfigTemplate.detect(trimmedURL) }
    private var side: APISide? { detected.side(of: trimmedURL) }

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
                    TextField(text: $name, prompt: Text(L("比如：公司 Kimi", "e.g. Work Kimi", "例：仕事用 Kimi"))) {
                        Text(L("名称", "Name", "名前"))
                    }
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
                    Button(role: .destructive) {
                        if Keychain.syncsToICloud { confirmSyncedDelete = true } else { confirmDelete = true }
                    } label: {
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
        .onChange(of: baseURL) { _ in
            fieldsChanged()
            if trimmedURL != notedURL { urlNote = nil }
        }
        .onChange(of: model) { _ in fieldsChanged() }
        .onChange(of: apiKey) { _ in connection = .idle }
        .sheet(isPresented: $showsCommonURLs) {
            CommonURLSheet(current: trimmedURL) { template, endpoint in
                pick(template, endpoint)
            } onTutorial: { template in
                // 正好是现在地址的那家：跟现在地址那一边；否则按 App Store 地区。
                let tutorialSide: APISide? = template == detected ? side : nil
                showsCommonURLs = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onTutorial(template.provider, tutorialSide) }
            }
        }
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
            Button(L("删除", "Delete", "削除"), role: .destructive) { deleteExisting() }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        }
        // 开着 Key 同步：其他设备上的方案和 Key 也会删（B11，02 复审第二轮）。
        .alert(SyncedDeleteText.title(name), isPresented: $confirmSyncedDelete) {
            Button(L("删除", "Delete", "削除"), role: .destructive) { deleteExisting() }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(SyncedDeleteText.message)
        }
        .onAppear(perform: prepareInitialTemplate)
        .task {
            // 等同步的时间在这里读（读钥匙串），不放进 init：SwiftUI 会多次调 init（04 四审可选 10）。
            guard let existing, Keychain.syncsToICloud, let since = existing.keyPendingSince else { return }
            keyPendingSince = since
            keySource = await ICloudSync.apiSource(existing.id)
        }
    }

    /// 引导里选了一家进来：和从列表里选一样，本机服务选中 IP，云服务光标跳到 Key。
    private func prepareInitialTemplate() {
        guard let template = initialTemplate, trimmedURL == template.baseURL, urlNote == nil else { return }
        if template.isLocal {
            setNote(ipNote(template))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { urlSelection = ConfigTemplate.sampleIP }
        } else if apiKey.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { keyFocused = true }
        }
    }

    private func deleteExisting() {
        if let existing { store.deleteSavedAPI(existing.id) }
        onClose()
    }

    /// Key 栏空着、Key 在等 iCloud 钥匙串同步过来。
    private var keyWaiting: Bool { apiKey.isEmpty && keyPendingSince != nil }
    /// 等了 24 小时还没到：提示换成去查系统设置。
    private var keyOverdue: Bool { keyPendingSince.map { Date().timeIntervalSince($0) > 86400 } ?? false }

    /// Key 栏的灰色占位字：等同步时是「正在从 iCloud 钥匙串同步…」，左边一个小时钟（02 复审第二轮）；
    /// 本机服务「自建服务可以留空」，其他「必填」。
    private var keyPrompt: Text {
        if keyWaiting && !keyOverdue {
            return Text("\(Image(systemName: "clock")) ") + Text(L("正在从 iCloud 钥匙串同步…", "Syncing from iCloud Keychain…", "iCloud キーチェーンから同期中…"))
        }
        if detected.isLocal { return Text(L("自建服务可以留空", "Optional for self-hosted", "セルフホストなら空欄で可")) }
        return Text(L("必填", "Required", "必須"))
    }

    /// 连接那一组脚注最前面：Key 还没同步过来时说一句。
    private var keyNote: String? {
        guard keyWaiting else { return nil }
        if keyOverdue {
            return L("Key 没同步过来。看看 iPhone 设置 › Apple 账户 › iCloud › 密码 有没有打开，或者在这里直接填。",
                     "The key didn't sync. Check that Passwords is on in Settings › Apple Account › iCloud, or enter it here.",
                     "キーが同期されませんでした。設定 › Apple アカウント › iCloud › パスワード がオンか確認するか、ここに直接入力してください。")
        }
        let source = keySource ?? L("另一台设备", "another device", "別のデバイス")
        return L("这个接口方案是从「\(source)」同步来的，Key 还没到。iCloud 钥匙串一般几分钟内同步好；等不及可以在这里直接填。",
                 "This API setup was synced from “\(source)” and its key hasn't arrived yet. iCloud Keychain usually syncs within a few minutes; you can also enter the key here.",
                 "この API の設定は「\(source)」から同期されましたが、キーはまだ届いていません。iCloud キーチェーンは通常数分で同期されます。待てない場合はここに直接入力できます。")
    }

    /// 脚注里说 Key 存在哪：开着 Key 同步时在 iCloud 钥匙串里。
    private var keyStorageNote: String {
        Keychain.syncsToICloud
            ? L("API Key 存在 iCloud 钥匙串里，端到端加密。", " The API key is stored in iCloud Keychain, end-to-end encrypted.", "API キーは iCloud キーチェーンに保存され、エンドツーエンドで暗号化されます。")
            : L("API Key 只存在本机钥匙串里。", " The API key stays in this iPhone's keychain.", "API キーはこの iPhone のキーチェーンにだけ保存されます。")
    }

    /// 地址或模型改了：连接结果作废，联网结果换成这一组记下的（没测过就是未测试）。
    private func fieldsChanged() {
        connection = .idle
        if probe != .running { probe = Self.storedProbe(baseURL: trimmedURL, model: trimmedModel) }
        modelMenuOpen = false
    }

    // MARK: 从常用地址里选了一家（NC1 ④，NC2 ⑧⑩）

    private func pick(_ template: ConfigTemplate, _ endpoint: APIEndpoint) {
        let oldTemplate = detected, oldSide = side, oldURL = trimmedURL
        showsCommonURLs = false
        guard endpoint.url != oldURL else { return }
        baseURL = endpoint.url
        typingModel = false
        let switched = template != oldTemplate
        var notes: [String] = []
        if existing != nil && !oldURL.isEmpty {
            // 编辑已有配置时换一家：Key 和模型清空；同一家换了另一边：Key 清空（两边的 Key 不通用）。
            if switched {
                apiKey = ""
                model = ""
                notes.append(L("换成了\(template.title)：模型和 API Key 已清空。点「取消」原来的配置不变。",
                               "Switched to \(template.title): model and API key cleared. Tap Cancel to keep the original setup.",
                               "\(template.title) に切り替えました。モデルと API キーを消去しました。「キャンセル」で元の設定のままです。"))
            } else if endpoint.side != oldSide {
                apiKey = ""
                notes.append(L("换成了\(template.title)（\(endpoint.side.label)）：API Key 已清空，两边的 Key 不通用。点「取消」原来的配置不变。",
                               "Switched to \(template.title) (\(endpoint.side.label)): API key cleared, since keys don't work across sites. Tap Cancel to keep the original setup.",
                               "\(template.title)（\(endpoint.side.label)）に切り替えました。キーは共通ではないため API キーを消去しました。「キャンセル」で元の設定のままです。"))
            }
        } else if switched {
            model = ""
        }
        if switched {
            maxTokens = template.maxTokens
            let current = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || name == autoName {
                let auto = SavedAPIStore.uniqueName(template.defaultName, in: SavedAPIStore.all.filter { $0.id != existing?.id })
                name = auto
                autoName = auto
            }
        }
        if template.isLocal {
            notes.append(ipNote(template))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { urlSelection = ConfigTemplate.sampleIP }
        } else if apiKey.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { keyFocused = true }
        }
        setNote(notes.isEmpty ? nil : notes.joined(separator: "\n"))
        withAnimation(.easeOut(duration: 0.15)) { urlFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.4)) { urlFlash = false }
        }
    }

    private func setNote(_ note: String?) {
        urlNote = note
        notedURL = note == nil ? nil : trimmedURL
    }

    private func ipNote(_ template: ConfigTemplate) -> String {
        L("把选中的 IP 换成运行 \(template.title) 的电脑的局域网地址。",
          "Replace the selected IP with the local address of the computer running \(template.title).",
          "選択中の IP を \(template.title) を動かしているパソコンのローカルアドレスに置き換えてください。")
    }

    // MARK: 服务商卡（按地址认）

    private var providerCard: some View {
        let template = detected
        let empty = trimmedURL.isEmpty
        return HStack(spacing: 12) {
            TemplateLogo(template: empty ? .custom : template, size: 42, corner: 11)
            VStack(alignment: .leading, spacing: 3) {
                Text(cardTitle)
                    .font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text(cardSubtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                    if !empty, template.hasTutorial {
                        Button { onTutorial(template.provider, side) } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "book").font(.system(size: 11, weight: .semibold))
                                Text(L("配置教程", "Setup guide", "設定ガイド")).font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(linkPurple)
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
        .animation(.easeOut(duration: 0.2), value: template)
    }

    private var cardTitle: String {
        if trimmedURL.isEmpty { return L("新的接口", "New API", "新しい API") }
        return detected == .custom ? L("自定义", "Custom", "カスタム") : detected.title
    }

    /// 「平台 · 中国大陆」；认不出写主机名；本机服务写「自己电脑上」。
    private var cardSubtitle: String {
        if trimmedURL.isEmpty {
            return L("填 API 地址，或者从「常用 API 地址」里选", "Enter a URL, or pick one from Common API URLs", "URL を入力するか、「よく使う API の URL」から選んでください")
        }
        let template = detected
        if template == .custom { return URL(string: trimmedURL)?.host ?? trimmedURL }
        if template.isLocal { return template.platform(side: nil) }
        var parts = [template.platform(side: side)]
        if let side, side != .universal { parts.append(side.label) }
        return parts.joined(separator: " · ")
    }

    // MARK: 连接（地址 → Key → 模型 → 测试连接）

    private var connectionSection: some View {
        Section {
            urlRow
            keyRow
            modelRow
            testConnectionRow
        } header: {
            Text(L("连接", "Connection", "接続"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let keyNote { Text(keyNote) }
                Text(L("地址填好后点「拉取模型」，从服务商那里列出能用的模型。",
                       "After entering the URL, tap Fetch Models to list the provider's models.",
                       "URL を入れたら「モデルを取得」で使えるモデルを一覧にします。"))
                    + Text(keyStorageNote)
            }
        }
    }

    /// 上面一行「API 地址」+ 右上浅紫胶囊「☰ 常用 API 地址」；下面整行输入框。
    private var urlRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("API 地址", "API URL", "API の URL"))
                Spacer(minLength: 8)
                Button { showsCommonURLs = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet").font(.system(size: 12, weight: .semibold))
                        Text(L("常用 API 地址", "Common API URLs", "よく使う API の URL")).lineLimit(1)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(linkPurple)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(AppColor.softFill))
                }
                .buttonStyle(.borderless)
            }
            URLTextField(text: $baseURL, placeholder: "https://…/v1", select: $urlSelection)
                .frame(height: 40)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(urlFlash ? AppColor.softFill : Color(.tertiarySystemFill)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DashColor.ai, lineWidth: urlFlash ? 1.5 : 0))
                .accessibilityLabel(L("API 地址", "API URL", "API の URL"))
            if let urlNote {
                Text(urlNote)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var keyRow: some View {
        HStack {
            Text("API Key")
            // 不用 SecureField：系统会把地址 + 密码框当成登录表单，保存时弹「保存密码？」。
            // 改成普通输入框，没在编辑时盖上只露头尾的「sk-••••••3f9a」（CF3）。
            ZStack(alignment: .trailing) {
                TextField(text: $apiKey, prompt: keyPrompt) { Text("API Key") }
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($keyFocused)
                    // 不编辑时完全藏起原文（0.01 放大截图还能读出来）；点击由上面的掩码字接，点了进编辑。
                    .opacity(keyFocused || apiKey.isEmpty ? 1 : 0)
                if !keyFocused, !apiKey.isEmpty {
                    Text(Self.masked(apiKey))
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                        .onTapGesture { keyFocused = true }
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
    }

    /// 服务商说过不支持列模型（/models 不通）：只能手填。
    private var unsupported: Bool { !trimmedURL.isEmpty && ModelList.isUnsupported(trimmedURL) }
    private var showsMenu: Bool { !trimmedURL.isEmpty && !unsupported }

    private var modelPlaceholder: String {
        if detected.isLocal { return "qwen2.5:7b" }
        return detected.model.isEmpty ? L("模型名", "Model name", "モデル名") : detected.model
    }

    private func toggleMenu() {
        if router.privacyAgreed {
            withAnimation(.easeOut(duration: 0.2)) { modelMenuOpen.toggle() }
        } else {
            needsPrivacy = true
        }
    }

    /// 模型空着：右边浅紫胶囊「⤓ 拉取模型」（地址没填时灰着）；选好后是「模型名 ▼」；点了就地展开下拉（AC3、MF）。
    private var modelRow: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Text(L("模型", "Model", "モデル"))
                Spacer(minLength: 8)
                if typingModel || unsupported {
                    TextField(modelPlaceholder, text: $model)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($modelFocused)
                } else if trimmedModel.isEmpty {
                    Button(action: toggleMenu) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 12, weight: .semibold))
                            Text(L("拉取模型", "Fetch Models", "モデルを取得")).lineLimit(1)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(linkPurple)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(AppColor.softFill))
                        .overlay(Capsule().strokeBorder(DashColor.ai, lineWidth: modelMenuOpen ? 1.5 : 0))
                    }
                    .buttonStyle(.borderless)
                    .disabled(trimmedURL.isEmpty)
                    .opacity(trimmedURL.isEmpty ? 0.45 : 1)
                } else {
                    Button(action: toggleMenu) {
                        HStack(spacing: 6) {
                            Text(trimmedModel)
                                .foregroundStyle(Color.primary)
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
        // 名称空着：用服务商名（重名加 2），认不出的用主机名。
        let template = detected
        let fallback = template == .custom ? (URL(string: trimmedURL)?.host ?? template.defaultName) : template.defaultName
        item.name = finalName.isEmpty ? SavedAPIStore.uniqueName(fallback, in: SavedAPIStore.all.filter { $0.id != existing?.id }) : finalName
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

/// 开着 Key 同步时删接口方案的确认框（B11，02 复审第二轮）：左滑删除和编辑页的「删除」共用。
enum SyncedDeleteText {
    static func title(_ name: String) -> String {
        L("删除接口方案「\(name)」？", "Delete API setup “\(name)”?", "API の設定「\(name)」を削除しますか？")
    }

    static var message: String {
        L("开着 Key 同步：其他设备上这个方案和它的 Key 也会一起删掉。", "Key sync is on: this setup and its key are also deleted on your other devices.",
          "キーの同期がオンです：ほかのデバイスでもこの設定とキーが削除されます。")
    }
}
