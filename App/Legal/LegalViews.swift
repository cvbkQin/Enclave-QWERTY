import SwiftUI
import UIKit

// MARK: - 设置 › 隐私（P06）

/// 隐私政策（离线全文）、同意情况和撤回 / 阅读并同意（CP4、CP5），已同意的接口地址，本机记录的清除。
struct PrivacyView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var consent = ConsentStore.consented
    @State private var confirm: ClearTarget?
    @State private var cleared: Set<ClearTarget> = []
    @State private var confirmsRevoke = false

    private enum ClearTarget: Identifiable {
        case history, learning, stats
        var id: Self { self }
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRouter.SettingsPage.privacyPolicy) {
                    Text(L("隐私政策", "Privacy Policy", "プライバシーポリシー"))
                }
            } footer: {
                Text(L("完整文本放在 App 里，不联网也能看。", "The full text is in the app, so you can read it offline.", "全文はアプリ内にあり、オフラインでも読めます。"))
            }

            Section(L("隐私政策同意情况", "Privacy Policy consent", "プライバシーポリシーへの同意")) {
                HStack {
                    Text(L("状态", "Status", "状態"))
                    Spacer()
                    Text(router.privacyAgreed ? L("已同意", "Agreed", "同意済み") : L("未同意 · 仅基础功能", "Not agreed · Basic only", "未同意・基本機能のみ"))
                        .foregroundStyle(.secondary)
                }
                if router.privacyAgreed {
                    HStack {
                        Text(L("同意的版本", "Version", "同意した版"))
                        Spacer()
                        Text(agreedVersionText).foregroundStyle(.secondary)
                    }
                }
            }

            if router.privacyAgreed {
                Section {
                    Button(L("撤回同意", "Withdraw Consent", "同意を撤回"), role: .destructive) { confirmsRevoke = true }
                        .foregroundStyle(Color(hex: 0xFF3B30))
                } footer: {
                    Text(L("撤回后只能用基础拼音输入，AI 功能关闭；设置、常用词和接口都留着，重新同意就能接着用。",
                           "After withdrawing, only basic pinyin input works and AI is off. Your settings, words and API stay, so you can pick up again by agreeing.",
                           "撤回すると基本のピンイン入力だけになり、AI 機能はオフになります。設定・単語・API はそのまま残り、再び同意すれば続けて使えます。"))
                }
            } else {
                Section {
                    Button { router.showsPrivacyWelcome = true } label: {
                        Text(L("阅读并同意", "Read and Agree", "読んで同意する")).fontWeight(.semibold).foregroundStyle(AppColor.purple)
                    }
                } footer: {
                    Text(L("同意后可以使用 AI 润色。", "Agree to use AI features.", "同意すると AI 機能が使えます。"))
                }
            }

            // 按接口地址的发送确认（键盘里首次发送前那张卡），隐私政策写了可以在这里撤回。
            if let consent {
                Section(L("AI 发送", "AI sending", "AI の送信")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("已同意发送到", "Allowed to send to", "送信を許可した API"))
                        Text("\(consent.endpoint) · \(Loc.fullDate(consent.date))")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Button(L("撤回这个地址", "Withdraw for this address", "このアドレスへの許可を撤回"), role: .destructive) {
                        ConsentStore.revoke()
                        self.consent = nil
                    }
                    .foregroundStyle(Color(hex: 0xFF3B30))
                }
            }

            Section {
                clearRow(L("清除使用统计", "Clear Usage Stats", "利用統計を消去"), target: .stats)
                clearRow(L("清除 AI 历史", "Clear AI History", "AI の履歴を消去"), target: .history)
                clearRow(L("清除拼音学习记录", "Clear Pinyin Learning", "ピンインの学習データを消去"), target: .learning)
            } header: {
                Text(L("本地数据", "Data on this iPhone", "この iPhone のデータ"))
            } footer: {
                Text(L("统计只存在这台手机上，留 30 天，不上传。删除 App 会清除全部数据。",
                       "Stats stay on this iPhone for 30 days and are never uploaded. Deleting the app removes all data.",
                       "統計はこの iPhone にだけ 30 日間保存され、送信されません。アプリを削除するとすべて消えます。"))
            }
        }
        .navigationTitle(L("隐私", "Privacy", "プライバシー"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { consent = ConsentStore.consented }
        .alert(L("撤回同意？", "Withdraw consent?", "同意を撤回しますか？"), isPresented: $confirmsRevoke) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("撤回同意", "Withdraw Consent", "同意を撤回"), role: .destructive) { router.revokePrivacy() }
        } message: {
            Text(L("AI 功能会关闭，拼音输入不受影响。", "AI features turn off. Pinyin input keeps working.", "AI 機能はオフになります。ピンイン入力はそのまま使えます。"))
        }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("清除", "Clear", "消去"), role: .destructive) {
                guard let target = confirm else { return }
                switch target {
                case .history: SessionStore.save(nil)
                case .learning: RimeStore.clearLearning()
                case .stats: UsageStats.clearStats()
                }
                cleared.insert(target)
            }
        }
    }

    /// 「第 1 版 · 10月26日」。
    private var agreedVersionText: String {
        let version = PrivacyConsent.agreedVersion
        let date = PrivacyConsent.agreedDate.map { " · " + Loc.monthDay($0) } ?? ""
        return L("第 \(version) 版", "Version \(version)", "第 \(version) 版") + date
    }

    private var confirmTitle: String {
        switch confirm {
        case .history: return L("清除 AI 历史？", "Clear AI history?", "AI の履歴を消去しますか？")
        case .learning: return L("清除拼音学习记录？候选会回到默认的顺序。", "Clear pinyin learning? Candidates go back to the default order.",
                                 "ピンインの学習データを消去しますか？候補は初期の順番に戻ります。")
        case .stats: return L("清除使用统计？首页的次数和图表会从零开始。", "Clear usage stats? The counts and charts on Home start over.",
                              "利用統計を消去しますか？ホームの回数とグラフはゼロからになります。")
        case nil: return ""
        }
    }

    /// 红字整行按钮（CP4），清除后换成灰色「已清除」。
    private func clearRow(_ title: String, target: ClearTarget) -> some View {
        Button { confirm = target } label: {
            HStack {
                Text(title).foregroundStyle(cleared.contains(target) ? Color.secondary : Color(hex: 0xFF3B30))
                Spacer()
                if cleared.contains(target) {
                    Label(L("已清除", "Cleared", "消去しました"), systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(cleared.contains(target))
    }
}

extension RimeStore {
    /// 拼音学习记录是用户目录里的 *.userdb，删掉后引擎下次启动会重新建。
    /// 没开完全访问时键盘用自己的目录，App 删不到，那份在关掉键盘后也不会同步过来。
    static func clearLearning() {
        guard let paths else { return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: paths.user, includingPropertiesForKeys: nil)) ?? []
        for url in items where url.lastPathComponent.contains(".userdb") {
            try? fm.removeItem(at: url)
        }
    }
}

// MARK: - 隐私政策（P07）

/// 顶部中文 / English / 日本語切换，默认跟界面语言；白色卡片，标题、生效日期、分节正文。
struct PrivacyPolicyView: View {
    @State private var language: AppLanguage = Loc.current == .system ? .zh : Loc.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $language) {
                    Text("中文").tag(AppLanguage.zh)
                    Text("English").tag(AppLanguage.en)
                    Text("日本語").tag(AppLanguage.ja)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.system(size: 22, weight: .bold))
                    Text(effective).font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(PolicyBlock.parse(PrivacyPolicy.text(language)).enumerated()), id: \.offset) { _, block in
                        block.view
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("隐私政策", "Privacy Policy", "プライバシーポリシー"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch language {
        case .en: return "Enclave Privacy Policy"
        case .ja: return "Enclave プライバシーポリシー"
        case .zh, .system: return "飞地输入法隐私政策"
        }
    }

    private var effective: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        switch language {
        case .en:
            formatter.locale = Locale(identifier: "en_US")
            return "Effective date: " + formatter.string(from: PrivacyPolicy.effectiveDate)
        case .ja:
            formatter.locale = Locale(identifier: "ja_JP")
            return "施行日：" + formatter.string(from: PrivacyPolicy.effectiveDate)
        case .zh, .system:
            formatter.locale = Locale(identifier: "zh_CN")
            return "生效日期：" + formatter.string(from: PrivacyPolicy.effectiveDate)
        }
    }
}

/// 把隐私政策的 Markdown 拆成标题和段落；段落里的加粗用系统的 Markdown 解析。
private enum PolicyBlock {
    case heading(String), subheading(String), paragraph(String)

    static func parse(_ text: String) -> [PolicyBlock] {
        text.components(separatedBy: "\n\n").compactMap { chunk in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if trimmed.hasPrefix("### ") { return .subheading(String(trimmed.dropFirst(4))) }
            if trimmed.hasPrefix("## ") { return .heading(String(trimmed.dropFirst(3))) }
            return .paragraph(trimmed)
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .heading(let text):
            Text(text).font(.system(size: 16, weight: .semibold)).padding(.top, 6)
        case .subheading(let text):
            Text(text).font(.system(size: 14.5, weight: .semibold))
        case .paragraph(let text):
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 关于（P08）

struct AboutView: View {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// 开发版标签（0.93_1 这样），正式、内测、公测包为空。
    static var devLabel: String? {
        (Bundle.main.object(forInfoDictionaryKey: "EnclaveDevLabel") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image("AboutIcon")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(L("飞地输入法", "Enclave", "Enclave")).font(.system(size: 20, weight: .bold))
                    Text(Self.devLabel.map { L("开发版 \($0)（\(Self.build)）", "Dev \($0) (\(Self.build))", "開発版 \($0)（\(Self.build)）") }
                         ?? L("版本 \(Self.version)（\(Self.build)）", "Version \(Self.version) (\(Self.build))", "バージョン \(Self.version)（\(Self.build)）"))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink(value: AppRouter.SettingsPage.privacyPolicy) {
                    Text(L("隐私政策", "Privacy Policy", "プライバシーポリシー"))
                }
                Link(destination: LegalLinks.terms) {
                    rowLink(L("用户协议", "Terms of Use", "利用規約"))
                }
                if let mail = URL(string: "mailto:\(LegalInfo.email)"), LegalInfo.email.contains("@") {
                    Link(destination: mail) {
                        rowLink(L("联系我们", "Contact Us", "お問い合わせ"))
                    }
                }
            }
            Section {
                NavigationLink(value: AppRouter.SettingsPage.licenses) {
                    HStack {
                        Text(L("万象拼音 · 拼音词库", "Wanxiang Pinyin · Dictionary", "万象ピンイン · 辞書"))
                        Spacer()
                        Text("CC BY 4.0").foregroundStyle(.secondary)
                    }
                }
                NavigationLink(value: AppRouter.SettingsPage.licenses) {
                    HStack {
                        Text(L("Tatoeba · 英文联想", "Tatoeba · English suggestions", "Tatoeba · 英語の予測"))
                        Spacer()
                        Text("CC BY 2.0 FR").foregroundStyle(.secondary)
                    }
                }
                NavigationLink(value: AppRouter.SettingsPage.licenses) {
                    HStack {
                        Text(L("开源许可", "Open Source Licenses", "オープンソースライセンス"))
                        Spacer()
                        Text(L("\(OpenSource.components.count) 项", "\(OpenSource.components.count)", "\(OpenSource.components.count) 件"))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("致谢", "Acknowledgements", "謝辞"))
            } footer: {
                Text(OpenSource.wanxiangAttribution)
            }
            // ICP 备案号（CP6）：号码下来之前整组不显示。
            if !LegalInfo.icpNumber.isEmpty {
                Section {
                    Link(destination: LegalLinks.icp) {
                        HStack {
                            Text(L("ICP备案号", "ICP filing", "ICP 届出番号")).foregroundStyle(.primary)
                            Spacer()
                            Text(LegalInfo.icpNumber).font(.system(size: 15)).foregroundStyle(AppColor.purple)
                            Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(AppColor.purple)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("关于飞地输入法", "About Enclave", "Enclave について"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rowLink(_ title: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 开源许可（P09）

/// 顶部「数据」卡片写全万象拼音 CC BY 4.0 要求的署名；下面是软件组件，点进去看版权声明和许可全文。
struct LicensesView: View {
    var body: some View {
        List {
            Section(L("数据", "Data", "データ")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("万象拼音", "Wanxiang Pinyin", "万象ピンイン")).font(.headline)
                    info(L("作者", "Author", "作者"), "amzxyz")
                    info(L("来源", "Source", "出典"), "github.com/amzxyz/rime_wanxiang")
                    info(L("许可", "License", "ライセンス"),
                         L("知识共享 署名 4.0 国际（CC BY 4.0）", "Creative Commons Attribution 4.0 International (CC BY 4.0)",
                           "クリエイティブ・コモンズ 表示 4.0 国際（CC BY 4.0）"))
                    info(L("改动", "Changes", "変更点"),
                         L("去掉了拼音声调，并按词频删减了词条。", "Tone marks removed and entries trimmed by frequency.", "声調を除き、頻度に応じて語を削っています。"))
                    Text(L("原作品按现状提供，不附带任何担保；改动由飞地输入法做出，与原作者无关。",
                           "The original work is provided as is, without warranty of any kind. Changes were made by Enclave and are not endorsed by the original author.",
                           "原著作物は現状のまま提供され、いかなる保証もありません。変更は Enclave によるもので、原作者とは関係ありません。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("creativecommons.org/licenses/by/4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                        .font(.footnote)
                }
                .padding(.vertical, 4)
            }
            Section(L("软件组件", "Software", "ソフトウェア")) {
                ForEach(OpenSource.components) { component in
                    NavigationLink {
                        LicenseText(component: component)
                    } label: {
                        HStack {
                            Text(component.name)
                            Spacer()
                            Text(component.license.name).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("开源许可", "Open Source Licenses", "オープンソースライセンス"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).fixedSize().frame(minWidth: 64, alignment: .leading)
            Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LicenseText: View {
    let component: OpenSource.Component

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(component.copyright).font(.subheadline.weight(.semibold))
                if let url = URL(string: component.url) {
                    Link(component.url, destination: url).font(.footnote)
                }
                Text(component.license.text(copyright: component.copyright))
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
