import MessageUI
import SwiftUI
import UIKit

// 内测版：诊断与反馈（DF1–DF5）。记录由 Shared/CrashLog.swift 收；这里列出来、看详情、发反馈邮件。
// 只在内测版（INTERNAL_BUILD=YES）出现。

/// 内测版设置页顶上的 AI 卡（DF1）：内置接口今天的用量，不显示试用和解锁。
struct BuiltinUsageCard: View {
    var body: some View {
        DashCard {
            DashCardHeader(icon: "sparkles", title: "AI", color: DashColor.ai, note: L("内置接口", "Built-in API", "内蔵 API"))
            usageRow(L("润色", "Rewrite", "書き換え"), BuiltinAPI.used(.polish), BuiltinAPI.Kind.polish.limit)
            usageRow(L("问答", "Answers", "回答"), BuiltinAPI.used(.answer), BuiltinAPI.Kind.answer.limit)
            Text(L("内测版的接口由开发者统一提供，每天可润色 100 次、问答 50 次，零点重置。",
                   "The beta's API is provided by the developer: 100 rewrites and 50 answers a day, reset at midnight.",
                   "ベータ版の API は開発者が提供します。1 日に書き換え 100 回、回答 50 回まで、0 時にリセットされます。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func usageRow(_ title: String, _ used: Int, _ limit: Int) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 40, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(light: 0xECEAFD, dark: 0x2E2766))
                    Capsule().fill(Color(hex: 0x5B4BE8))
                        .frame(width: proxy.size.width * min(CGFloat(used) / CGFloat(max(limit, 1)), 1))
                }
            }
            .frame(height: 8)
            Text("\(min(used, limit)) / \(limit)").monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(min(used, limit)) / \(limit)")
    }
}

extension CrashLog.Entry {
    var title: String {
        let place = isKeyboard ? L("键盘", "Keyboard", "キーボード") : "App"
        let what: String
        switch kind {
        case .crash: what = L("闪退", "Crashed", "クラッシュ")
        case .memory: what = L("内存超限，被系统关闭", "Closed by iOS for using too much memory", "メモリ超過でシステムが終了")
        case .hang: what = L("卡住超过 2 秒", "Froze for over 2 seconds", "2 秒以上フリーズ")
        }
        return "\(place) · \(what)"
    }

    var icon: (name: String, color: Color) {
        switch kind {
        case .crash: return ("bolt.fill", Color(hex: 0xFF3B30))
        case .memory: return ("memorychip", Color(hex: 0xFF9500))
        case .hang: return ("clock", Color(hex: 0x8E8E93))
        }
    }

    /// 「今天 14:32」「昨天 21:47」「10-25 09:10」。
    var shortTime: String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("今天 ", "Today ", "今日 ") + time }
        if calendar.isDateInYesterday(date) { return L("昨天 ", "Yesterday ", "昨日 ") + time }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)) + " " + time
    }

    var subtitle: String {
        ([shortTime, version] + (screen.map { [$0] } ?? [])).joined(separator: " · ")
    }

    /// 邮件正文里的一行：「10-28 14:32 键盘 · 闪退（抽屉展开 · 分词面板）」。
    var mailLine: String {
        let stamp = date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)).replacingOccurrences(of: "/", with: "-")
            + " " + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(stamp) \(title)" + (screen.map { "（\($0)）" } ?? "")
    }
}

/// 设置里「诊断与反馈」那一行右边：有记录时橙字「N 条记录」，没有时灰字「无记录」。
struct DiagnosticsRow: View {
    @State private var count = CrashLog.entries().count

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemName: "waveform.path.ecg", color: Color(hex: 0xFF9500))
            Text(L("诊断与反馈", "Diagnostics & feedback", "診断とフィードバック"))
            Spacer(minLength: 8)
            Text(count > 0 ? L("\(count) 条记录", "\(count) records", "\(count) 件") : L("无记录", "None", "記録なし"))
                .foregroundStyle(count > 0 ? Color(hex: 0xFF9500) : Color.secondary)
                .lineLimit(1)
        }
        .onAppear { count = CrashLog.entries().count }
    }
}

// MARK: - 诊断与反馈页（DF2 / DF5）

struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var entries = CrashLog.entries()
    @State private var confirmClear = false
    @State private var feedback: Feedback?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    TintIcon(systemName: "lock", color: DashColor.ai)
                    (Text(L("这里记录 App 和键盘最近 30 天的闪退、被系统关闭和卡顿，用于排查问题。记录只保存在这台手机上，",
                            "This lists app and keyboard crashes, closures by iOS, and freezes from the last 30 days, to help track down problems. Records stay on this iPhone, ",
                            "App とキーボードの直近 30 日のクラッシュ、システムによる終了、フリーズを記録し、問題の調査に使います。記録はこの iPhone だけに保存され、"))
                     + Text(L("不会自动上传", "are never uploaded automatically", "自動でアップロードされることはなく")).bold()
                     + Text(L("，也不包含你输入的任何文字。只有你点「反馈问题」并亲自发送邮件时，才会附上。",
                              ", and contain nothing you typed. They're attached only when you tap Send Feedback and send the email yourself.",
                              "、入力した文字も含みません。「フィードバック」から自分でメールを送るときだけ添付されます。")))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            if entries.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(DashColor.ok)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(DashColor.ok.opacity(0.14)))
                        Text(L("最近 30 天没有异常记录", "No problems in the last 30 days", "直近 30 日の異常はありません")).font(.headline)
                        Text(L("遇到问题也可以直接反馈", "You can still send feedback anytime", "問題があればそのままフィードバックできます"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink {
                            DiagnosticDetailView(entry: entry) { feedback = Feedback(entries: [entry]) }
                        } label: {
                            EntryRow(entry: entry)
                        }
                    }
                } header: {
                    Text(L("最近记录 · \(entries.count) 条", "Recent · \(entries.count)", "最近の記録 · \(entries.count) 件"))
                }
            }
            Section {
                Button { feedback = Feedback(entries: entries) } label: {
                    Label(L("反馈问题", "Send feedback", "フィードバック"), systemImage: "envelope")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x7B6BFA), Color(hex: 0x5B4BE8), Color(hex: 0x4A3BD6)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text(L("将打开邮件，自动附上版本号、机型、系统版本和最近的记录。你可以补充说明和截图，确认后再发送。",
                       "Opens an email with the version, device, iOS version and recent records attached. Add details and screenshots, then send it yourself.",
                       "バージョン、機種、iOS バージョン、最近の記録を添付したメールを開きます。説明やスクリーンショットを追加して、自分で送信してください。"))
            }
            if !entries.isEmpty {
                Section {
                    Button(L("清除全部记录", "Clear all records", "すべての記録を消去"), role: .destructive) { confirmClear = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(L("诊断与反馈", "Diagnostics & feedback", "診断とフィードバック"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = CrashLog.entries() }
        .confirmationDialog(L("清除全部记录？", "Clear all records?", "すべての記録を消去しますか？"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("清除", "Clear", "消去"), role: .destructive) {
                CrashLog.clear()
                entries = []
            }
        }
        .sheet(item: $feedback) { FeedbackSheet(feedback: $0, settings: store.settings) }
    }
}

private struct EntryRow: View {
    let entry: CrashLog.Entry

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemName: entry.icon.name, color: entry.icon.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(2)
                Text(entry.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 记录详情（DF3）

private struct DiagnosticDetailView: View {
    let entry: CrashLog.Entry
    var report: () -> Void

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    TintIcon(systemName: entry.icon.name, color: entry.icon.color, size: 56)
                    Text(entry.title).font(.title3.bold()).multilineTextAlignment(.center)
                    Text(entry.date.formatted(.dateTime.month().day().hour().minute())).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section(L("基本信息", "Details", "基本情報")) {
                LabeledContent(L("版本", "Version", "バージョン"), value: entry.version + L(" · 内测版", " · Beta", " · ベータ"))
                LabeledContent(L("机型", "Device", "機種"), value: entry.device ?? FeedbackInfo.device)
                LabeledContent(L("系统", "iOS", "iOS"), value: entry.os ?? FeedbackInfo.os)
                LabeledContent(L("当时界面", "Screen", "画面"), value: entry.screen ?? "—")
            }
            Section {
                Text(entry.summary)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L("技术信息", "Technical info", "技術情報"))
            } footer: {
                Text(L("由系统（MetricKit）生成，只含程序运行信息，不含输入内容。", "Generated by iOS (MetricKit). Contains only app runtime info, nothing you typed.",
                       "iOS（MetricKit）が生成した、アプリの動作情報のみです。入力内容は含みません。"))
            }
            Section {
                Button(action: report) {
                    Label(L("反馈这条记录", "Report this record", "この記録をフィードバック"), systemImage: "envelope")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(L("记录详情", "Record", "記録の詳細"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 反馈邮件（DF4）

struct Feedback: Identifiable {
    let id = UUID()
    var entries: [CrashLog.Entry]
}

enum FeedbackInfo {
    static var version: String { "\(AboutView.version) (\(AboutView.build))" }
    static var os: String { "iOS \(UIDevice.current.systemVersion)" }

    /// 机型代号，例如 iPhone16,1。
    static var device: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    static func subject() -> String {
        L("飞地输入法内测反馈 · ", "Enclave beta feedback · ", "Enclave ベータフィードバック · ") + version
    }

    /// 正文：留给用户写的地方 + 自动附上的信息（不写接口地址和 Key）。
    static func body(entries: [CrashLog.Entry], settings: EnclaveSettings) -> String {
        let rewrite = Provider.detect(settings.baseURL).title
        let answer = settings.separateAnswer ? Provider.detect(settings.answerBaseURL).title : rewrite
        var lines = [
            L("请描述遇到的问题（在什么 App 里、做了什么操作）：", "Please describe the problem (which app, what you did):", "問題の内容（どの App で何をしたか）："),
            "", "", "",
            L("—— 以下由飞地输入法自动附上，可删改 ——", "—— Added by Enclave; feel free to edit ——", "—— 以下は Enclave が自動で追加しました。編集できます ——"),
            L("版本：", "Version: ", "バージョン：") + version + L(" 内测版", " beta", " ベータ"),
            L("机型：", "Device: ", "機種：") + "\(device) · \(os)",
            L("键盘：", "Keyboard: ", "キーボード：") + "\(settings.keyboardLayout.title) · "
                + L("改写接口 ", "rewrite ", "書き換え ") + rewrite + " · " + L("问答接口 ", "answers ", "回答 ") + answer,
        ]
        if entries.isEmpty {
            lines.append(L("最近记录：无", "Recent records: none", "最近の記録：なし"))
        } else {
            lines.append(L("最近记录（\(entries.count) 条）：", "Recent records (\(entries.count)):", "最近の記録（\(entries.count) 件）："))
            lines += entries.enumerated().map { "\($0.offset + 1). \($0.element.mailLine)" }
        }
        return lines.joined(separator: "\n")
    }

    /// 附件「诊断记录.json」：每条的摘要和系统给的完整诊断。
    static func attachment(entries: [CrashLog.Entry]) -> Data? {
        guard !entries.isEmpty else { return nil }
        let items: [[String: Any]] = entries.map { entry in
            var item: [String: Any] = [
                "source": entry.source, "kind": entry.kind.rawValue, "date": ISO8601DateFormatter().string(from: entry.date),
                "version": entry.version, "os": entry.os ?? "", "device": entry.device ?? "", "screen": entry.screen ?? "",
                "summary": entry.summary,
            ]
            if let data = CrashLog.detail(entry), let json = try? JSONSerialization.jsonObject(with: data) { item["metricKit"] = json }
            return item
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    static let attachmentName = L("诊断记录.json", "diagnostics.json", "診断記録.json")
}

/// 有邮件账号用系统写邮件页；没有就用分享面板（文字 + 附件）。
private struct FeedbackSheet: View {
    let feedback: Feedback
    let settings: EnclaveSettings

    var body: some View {
        let text = FeedbackInfo.body(entries: feedback.entries, settings: settings)
        let attachment = FeedbackInfo.attachment(entries: feedback.entries)
        if MFMailComposeViewController.canSendMail() {
            MailComposer(subject: FeedbackInfo.subject(), body: text, attachment: attachment)
                .ignoresSafeArea()
        } else {
            ShareSheet(items: shareItems(body: text, attachment: attachment))
        }
    }

    private func shareItems(body: String, attachment: Data?) -> [Any] {
        var items: [Any] = [FeedbackInfo.subject() + "\n" + LegalInfo.email + "\n\n" + body]
        if let attachment {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(FeedbackInfo.attachmentName)
            if (try? attachment.write(to: url, options: .atomic)) != nil { items.append(url) }
        }
        return items
    }
}

private struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let attachment: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([LegalInfo.email])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let attachment {
            controller.addAttachmentData(attachment, mimeType: "application/json", fileName: FeedbackInfo.attachmentName)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
