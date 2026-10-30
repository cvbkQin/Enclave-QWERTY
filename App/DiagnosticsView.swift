import SwiftUI
import UIKit

// 内测版：诊断与反馈（DF1–DF5）。记录由 Shared/CrashLog.swift 收；这里列出来、看详情，反馈走 App 内的表单（FB8）。
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
    @State private var entries = CrashLog.entries()
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    TintIcon(systemName: "lock", color: DashColor.ai)
                    (Text(L("这里记录 App 和键盘最近 30 天的闪退、被系统关闭和卡顿，用于排查问题。记录只保存在这台手机上，",
                            "This lists app and keyboard crashes, closures by iOS, and freezes from the last 30 days, to help track down problems. Records stay on this iPhone, ",
                            "App とキーボードの直近 30 日のクラッシュ、システムによる終了、フリーズを記録し、問題の調査に使います。記録はこの iPhone だけに保存され、"))
                     + Text(L("不会自动上传", "are never uploaded automatically", "自動でアップロードされることはなく")).bold()
                     + Text(L("，也不包含你输入的任何文字。只有你在「反馈问题」里打开「附上最近的诊断记录」并提交时，才会附上。",
                              ", and contain nothing you typed. They're attached only when you turn on Attach recent diagnostics in Send Feedback and send it.",
                              "、入力した文字も含みません。「フィードバック」で「最近の診断記録を添付」をオンにして送信したときだけ添付されます。")))
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
                            DiagnosticDetailView(entry: entry)
                        } label: {
                            EntryRow(entry: entry)
                        }
                    }
                } header: {
                    Text(L("最近记录 · \(entries.count) 条", "Recent · \(entries.count)", "最近の記録 · \(entries.count) 件"))
                }
            }
            Section {
                NavigationLink { FeedbackFormView(entries: entries) } label: {
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
                Text(L("在 App 里填好直接提交给开发者，不用打开邮件。可以选择附上最近的记录。",
                       "Fill it in and send it to the developer right in the app, no email needed. You can choose to attach recent records.",
                       "App 内で入力してそのまま開発者に送れます。メールは不要です。最近の記録を添付することもできます。"))
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
                NavigationLink { FeedbackFormView(entries: [entry]) } label: {
                    Label(L("反馈这一条", "Report this record", "この記録をフィードバック"), systemImage: "envelope")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(L("记录详情", "Record", "記録の詳細"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 反馈附带的信息

enum FeedbackInfo {
    static var version: String { "\(AboutView.version) (\(AboutView.build))" }
    static var os: String { "iOS \(UIDevice.current.systemVersion)" }

    /// 机型代号，例如 iPhone16,1。
    static var device: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
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
