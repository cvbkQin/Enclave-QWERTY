import PhotosUI
import StoreKit
import SwiftUI

// MARK: - 反馈问题：App 内填表提交（FB1–FB8，执行清单 A4）

/// 提交到 enclavekb.cn 的反馈接口（05 定的约定，见 compliance/A3-A4-服务器与反馈合规.md 第 2 节）：
/// POST JSON，整个请求不超过 6MB；截图放 images（base64 的 JPEG，最多 3 张，每张不超过 1.5MB）。
/// 服务器转成邮件发给开发者，正文不留存。
enum FeedbackAPI {
    static let url = URL(string: "https://enclavekb.cn/api/feedback")!
    static let maxBytes = 6 * 1024 * 1024
    static let maxImageBytes = 1_500_000
    static let maxImages = 3
    static let maxMessage = 1000

    enum Category: String { case bug, suggestion }

    enum Failure: Error, Equatable {
        /// 400：内容为空或太长。
        case invalid
        /// 413：超过上限，少放截图或去掉诊断记录再试。
        case tooLarge
        /// 429：发得太频繁。
        case rateLimited
        /// 502（服务器转发失败）、其他服务器错误。不给「改用邮件」：开发者邮箱不在反馈里显示（cvbk）。
        case server
        /// 网络不通、超时。
        case network
    }

    /// 发一次。成功返回；失败抛 Failure。
    static func submit(category: Category, message: String, contact: String, images: [Data], diagnostics: Any?) async throws {
        var body: [String: Any] = [
            "category": category.rawValue,
            "message": message,
            "meta": meta,
        ]
        if !contact.isEmpty { body["contact"] = contact }
        if !images.isEmpty { body["images"] = images.map { $0.base64EncodedString() } }
        if let diagnostics { body["diagnostics"] = diagnostics }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { throw Failure.invalid }
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        #if DEBUG
        if let mock = mockResult { try await mock(); return }
        #endif
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.network
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return
        case 400: throw Failure.invalid
        case 413: throw Failure.tooLarge
        case 429: throw Failure.rateLimited
        default: throw Failure.server
        }
    }

    /// 会一起发送的版本机型信息：不含 API Key、接口地址，也不含输入过的文字。
    static var meta: [String: String] {
        [
            "version": AboutView.devLabel ?? AboutView.version,
            "build": AboutView.build,
            "channel": channel,
            "device": FeedbackInfo.device,
            "os": FeedbackInfo.os,
            "locale": Locale.preferredLanguages.first ?? Loc.locale.identifier,
            "storefront": UserDefaults.standard.string(forKey: "storefront.country") ?? "",
            "keyboard": SettingsStore.load().keyboardLayout.shortTitle,
            "providers": FeedbackForm.providers(SettingsStore.load()),
        ]
    }

    /// 哪种包：开发版、内测、公测、正式。
    static var channel: String {
        #if DEBUG
        return "dev"
        #else
        if BuiltinAPI.isInternalBuild { return "internal" }
        if BuiltinAPI.isPublicBuild { return "public" }
        return "store"
        #endif
    }

    /// 截图压成长边 1600 的 JPEG；还超过 1.5MB 就降质量再压。
    static func compress(_ image: UIImage) -> Data? {
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longSide, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in [0.8, 0.6, 0.4, 0.25] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxImageBytes { return data }
        }
        return nil
    }

    #if DEBUG
    /// 模拟器测试（接口要等 enclavekb.cn 网站备案后才打得开）：-feedbackMock ok / invalid / 413 / 429 / 502 / network。
    static var mockResult: (() async throws -> Void)? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-feedbackMock"), args.indices.contains(i + 1) else { return nil }
        let mode = args[i + 1]
        return {
            try await Task.sleep(nanoseconds: 1_200_000_000)
            switch mode {
            case "invalid": throw Failure.invalid
            case "413": throw Failure.tooLarge
            case "429": throw Failure.rateLimited
            case "502": throw Failure.server
            case "network": throw Failure.network
            default: return
            }
        }
    }
    #endif
}

struct FeedbackForm {
    /// 「润色 / 问答」那一行：服务商名，不写地址和 Key。
    static func providers(_ settings: EnclaveSettings) -> String {
        guard settings.isConfigured else { return L("未设置", "Not set up", "未設定") }
        let rewrite = Provider.detect(settings.baseURL).title
        let answer = settings.usesAnswerEndpoint ? Provider.detect(settings.answerBaseURL).title : rewrite
        return "\(rewrite) / \(answer)"
    }
}

/// 表单页（FB3–FB8）。entries：内测版从「诊断与反馈」进来时可以附上的诊断记录（从某条记录进来时只有那一条）。
struct FeedbackFormView: View {
    var entries: [CrashLog.Entry]

    init(entries: [CrashLog.Entry] = []) {
        self.entries = entries
    }

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var category: FeedbackAPI.Category = .bug
    @State private var message = ""
    @State private var contact = ""
    /// 附上诊断记录：默认关（合规要求），注明不含输入文字。
    @State private var attachDiagnostics = false
    /// 截图（选填，最多 3 张）：缩略图和压好的 JPEG。从相册选（PhotosPicker，不要相册权限）。
    @State private var screenshots: [Screenshot] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var sending = false
    @State private var failure: FeedbackAPI.Failure?
    @State private var sent = false
    @State private var sentWithContact = false
    @State private var showsPolicy = false
    /// 中国大陆店面：收件邮箱在境外（Google），按个人信息保护法第 39 条要单独同意。每次提交都要勾，不和隐私政策同意合在一起。
    @State private var agreesOverseas = false
    private var needsOverseasConsent: Bool { Storefront.isMainlandChina }
    private var canSubmit: Bool { !trimmed.isEmpty && !sending && (!needsOverseasConsent || agreesOverseas) }
    @FocusState private var focused: Bool

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if sent { sentPage } else { form }
        }
        .navigationTitle(L("反馈问题", "Send Feedback", "フィードバック"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPolicy) { NavigationStack { PrivacyPolicyView() } }
    }

    // MARK: 表单

    private var form: some View {
        List {
            Section {
                Picker(L("类型", "Type", "種類"), selection: $category) {
                    Text(L("遇到问题", "Problem", "問題")).tag(FeedbackAPI.Category.bug)
                    Text(L("功能建议", "Suggestion", "要望")).tag(FeedbackAPI.Category.suggestion)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(placeholder).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $message)
                        .focused($focused)
                        .submitLabel(.return)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .onChange(of: message) { text in
                            if text.count > FeedbackAPI.maxMessage { message = String(text.prefix(FeedbackAPI.maxMessage)) }
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(verbatim: "\(message.count) / \(FeedbackAPI.maxMessage)").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("说明", "Description", "内容"))
            }
            .disabled(sending)
            Section {
                screenshotRow
            } header: {
                Text(L("截图（选填，最多 3 张）", "Screenshots (optional, up to 3)", "スクリーンショット（任意、3 枚まで）"))
            }
            .disabled(sending)
            Section {
                HStack(spacing: 12) {
                    Text(L("联系方式", "Contact", "連絡先"))
                    TextField(L("邮箱或微信，选填", "Email or WeChat, optional", "メールまたは WeChat（任意）"), text: $contact)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: contact) { if $0.count > 200 { contact = String($0.prefix(200)) } }
                }
            } footer: {
                Text(L("选填。想要回复就留一个；不留也能提交。", "Optional. Leave one if you'd like a reply; you can send without it.", "任意。返信が必要なら入力してください。なくても送信できます。"))
            }
            .disabled(sending)
            Section {
                LabeledContent(L("版本", "Version", "バージョン"), value: versionText)
                LabeledContent(L("机型", "Device", "機種"), value: "\(FeedbackInfo.device) · \(FeedbackInfo.os)")
                LabeledContent(L("键盘", "Keyboard", "キーボード"), value: store.settings.keyboardLayout.shortTitle)
                LabeledContent(L("润色 / 问答", "Polish / Answers", "整える / 回答"), value: FeedbackForm.providers(store.settings))
                if !entries.isEmpty {
                    Toggle(isOn: $attachDiagnostics) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("附上最近的诊断记录", "Attach recent diagnostics", "最近の診断記録を添付"))
                            Text(L("\(entries.count) 条 · 闪退和卡顿记录，不含你输入的文字", "\(entries.count) · crash and hang records, nothing you typed", "\(entries.count) 件 · クラッシュとフリーズの記録、入力した文字は含みません"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(DashColor.ok)
                    .disabled(sending)
                }
            } header: {
                Text(L("会一起发送", "Sent along", "一緒に送信"))
            } footer: {
                Text(L("用来排查问题。不会发送 API Key、接口地址，也不包含你输入过的任何文字。",
                       "Used to track down problems. Never includes your API key, API address, or anything you typed.",
                       "問題の調査に使います。API キー、API のアドレス、入力した文字は送信しません。"))
            }
            Section {
                if needsOverseasConsent { overseasConsent }
                if let failure { failureBanner(failure) }
                Button { Task { await submit() } } label: {
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(.white) }
                        Text(sending ? L("正在提交…", "Sending…", "送信中…")
                             : failure != nil ? L("重新提交", "Send Again", "もう一度送信") : L("提交", "Send", "送信"))
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                        LinearGradient(colors: [Color(hex: 0x7B6BFA), Color(hex: 0x5B4BE8), Color(hex: 0x4A3BD6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .opacity(canSubmit || sending ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Button { showsPolicy = true } label: {
                    (Text(L("提交即表示你同意按", "By sending, you agree that this is handled under the ", "送信すると、"))
                     + Text(L("《隐私政策》", "Privacy Policy", "プライバシーポリシー")).foregroundColor(GuideColor.purple)
                     + Text(L("处理以上信息。", ".", "に従って上記の情報が扱われることに同意したものとみなされます。")))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: failure)
    }

    private var screenshotRow: some View {
        HStack(spacing: 12) {
            ForEach(screenshots) { shot in
                Image(uiImage: shot.thumbnail)
                    .resizable().scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { screenshots.removeAll { $0.id == shot.id } } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(.systemGray))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: -8)
                        .accessibilityLabel(L("删除截图", "Remove screenshot", "スクリーンショットを削除"))
                    }
            }
            if screenshots.count < FeedbackAPI.maxImages {
                PhotosPicker(selection: $picked, maxSelectionCount: FeedbackAPI.maxImages - screenshots.count,
                             matching: .images) {
                    VStack(spacing: 2) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                        Text(L("添加", "Add", "追加")).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 60, height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(.tertiary))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .onChange(of: picked) { items in
            guard !items.isEmpty else { return }
            picked = []
            Task {
                for item in items {
                    guard screenshots.count < FeedbackAPI.maxImages,
                          let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = FeedbackAPI.compress(image) else { continue }
                    screenshots.append(Screenshot(thumbnail: image.preparingThumbnail(of: CGSize(width: 180, height: 180)) ?? image, jpeg: jpeg))
                }
            }
        }
    }

    /// 必勾项：不显示邮箱地址，措辞和隐私政策「反馈」一节的境外说明一致。
    private var overseasConsent: some View {
        Button { agreesOverseas.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: agreesOverseas ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(agreesOverseas ? GuideColor.purple : Color.secondary)
                Text(L("我同意将以上反馈信息传输至境外，由开发者使用的 Google 邮箱（Google LLC，美国）接收处理。",
                       "I agree that this feedback is sent outside mainland China, to the developer's Google mailbox (Google LLC, USA).",
                       "上記のフィードバックが中国本土の外へ送られ、開発者が使う Google のメール（Google LLC、米国）で受け取られることに同意します。"))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .accessibilityAddTraits(agreesOverseas ? .isSelected : [])
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 12, trailing: 4))
        .listRowBackground(Color.clear)
    }

    private var placeholder: String {
        category == .bug
            ? L("说说遇到了什么：在哪个 App 里、做了什么、出了什么问题", "What happened: which app, what you did, what went wrong", "どの App で、何をして、何が起きたか")
            : L("说说你希望飞地输入法多一个什么功能，用在什么时候", "What would you like Enclave to do, and when would you use it", "Enclave にどんな機能があるとよいか、どんなときに使うか")
    }

    /// 「0.95 (95)」；内测、公测加版本名。
    private var versionText: String {
        let base = FeedbackInfo.version
        if BuiltinAPI.isInternalBuild { return base + L(" 内测版", " beta", " ベータ") }
        if BuiltinAPI.isPublicBuild { return base + L(" 公测版", " public beta", " パブリックベータ") }
        return base
    }

    private func failureBanner(_ failure: FeedbackAPI.Failure) -> some View {
        Label(failureText(failure), systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.08)))
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
            .listRowBackground(Color.clear)
    }

    private func failureText(_ failure: FeedbackAPI.Failure) -> String {
        switch failure {
        case .network:
            return L("没发出去：网络不通。填的内容都还在，连上网再点一次。", "Not sent: no network. Everything you entered is still here; connect and try again.", "送信できませんでした：ネットワークにつながりません。入力内容はそのままです。接続してからもう一度お試しください。")
        case .server:
            return L("没发出去：服务暂时不可用，稍后再试。", "Not sent: the service is unavailable right now. Try again later.", "送信できませんでした：サービスが一時的に使えません。後でお試しください。")
        case .rateLimited:
            return L("提交太频繁，稍后再试。", "Too many submissions. Try again later.", "送信が多すぎます。後でお試しください。")
        case .tooLarge:
            // 没有诊断记录时「附上最近的诊断记录」开关不显示，提示里也不提它。
            if entries.isEmpty {
                return L("没发出去：内容太大。少放几张截图再试。", "Not sent: too large. Remove a screenshot and try again.", "送信できませんでした：サイズが大きすぎます。スクリーンショットを減らしてお試しください。")
            }
            return L("没发出去：内容太大。少放几张截图，或关掉「附上最近的诊断记录」再试。", "Not sent: too large. Remove a screenshot or turn off Attach recent diagnostics and try again.", "送信できませんでした：サイズが大きすぎます。スクリーンショットを減らすか、「最近の診断記録を添付」をオフにしてお試しください。")
        case .invalid:
            return L("没发出去：说明是空的或太长，或者截图格式不对，改一下再提交。", "Not sent: the description is empty or too long, or a screenshot couldn't be read.", "送信できませんでした：内容が空か長すぎるか、スクリーンショットを読み取れませんでした。")
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        focused = false
        sending = true
        failure = nil
        let diagnostics: Any? = attachDiagnostics
            ? FeedbackInfo.attachment(entries: entries).flatMap { try? JSONSerialization.jsonObject(with: $0) }.map { ["records": $0] }
            : nil
        do {
            try await FeedbackAPI.submit(category: category, message: trimmed,
                                         contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
                                         images: screenshots.map(\.jpeg), diagnostics: diagnostics)
            sentWithContact = !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            message = ""
            contact = ""
            screenshots = []
            attachDiagnostics = false
            agreesOverseas = false
            sent = true
        } catch {
            failure = error as? FeedbackAPI.Failure ?? .network
        }
        sending = false
    }

    // MARK: 成功（FB6）

    private var sentPage: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DashColor.ok)
                .frame(width: 72, height: 72)
                .background(Circle().fill(DashColor.ok.opacity(0.14)))
            Text(L("收到了，谢谢", "Got it, thank you", "受け取りました。ありがとうございます"))
                .font(.title2.bold())
            Text(sentWithContact
                 ? L("我们会认真看每一条。你留了联系方式，有进展会联系你。", "We read every one. You left a contact, so we'll reach out when there's news.", "すべて目を通します。連絡先をいただいたので、進展があればご連絡します。")
                 : L("我们会认真看每一条。", "We read every one.", "すべて目を通します。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button { dismiss() } label: {
                Text(L("完成", "Done", "完了"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GuideColor.chipText)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GuideColor.chipFill))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// 一张截图：缩略图给表单看，jpeg 是压好要上传的。
private struct Screenshot: Identifiable {
    let id = UUID()
    let thumbnail: UIImage
    let jpeg: Data
}
