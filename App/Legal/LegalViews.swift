import SwiftUI
import UIKit

// MARK: - 设置 › 隐私（P06）

/// 打字不联网的说明，已同意的接口和撤回，本机记录的清除，权限状态，最后进隐私政策。
struct PrivacyView: View {
    @State private var consent = ConsentStore.consented
    @State private var confirm: ClearTarget?
    @State private var cleared: ClearTarget?

    private enum ClearTarget: Identifiable {
        case history, learning
        var id: Self { self }
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("打字不联网", "Typing stays offline", "入力は通信しません")).font(.headline)
                        Text(L("拼音和候选都在手机上算。只有你点「润色」或「再润」时，才把文字发给你自己配置的接口，飞地输入法没有自己的服务器。",
                               "Pinyin and candidates are worked out on your iPhone. Text is sent only when you tap Polish or Rewrite, straight to the API you set up. Enclave has no servers.",
                               "ピンインと候補は iPhone 上で処理します。「整える」か「別の案」をタップしたときだけ、自分で設定した API に文章を送ります。Enclave はサーバーを持ちません。"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(L("AI 发送", "AI sending", "AI の送信")) {
                if let consent {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("已同意发送到", "Allowed to send to", "送信を許可した API"))
                        Text("\(consent.endpoint) · \(Loc.fullDate(consent.date))")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Button(L("撤回同意", "Withdraw consent", "同意を撤回"), role: .destructive) {
                        ConsentStore.revoke()
                        self.consent = nil
                    }
                    .foregroundStyle(Color(hex: 0xFF3B30))
                } else {
                    Text(L("还没有同意过", "Not allowed yet", "まだ許可していません")).foregroundStyle(.secondary)
                }
            }

            Section {
                clearRow(L("润色历史", "Polish history", "整えた履歴"), target: .history)
                clearRow(L("拼音学习记录", "Pinyin learning", "ピンインの学習データ"), target: .learning)
            } header: {
                Text(L("保存在这台手机上", "Stored on this iPhone", "この iPhone に保存"))
            } footer: {
                Text(L("API Key 只存在本机钥匙串里。", "Your API key stays in this iPhone's keychain.", "API キーはこの iPhone のキーチェーンにだけ保存されます。"))
            }

            Section(L("权限", "Permissions", "権限")) {
                NavigationLink(value: AppRouter.SettingsPage.guide) {
                    HStack {
                        Text(L("允许完全访问", "Allow Full Access", "フルアクセスを許可"))
                        Spacer()
                        Text(KeyboardStatus.fullAccess == true ? L("已开启", "On", "オン") : L("未开启", "Off", "オフ"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink(value: AppRouter.SettingsPage.privacyPolicy) {
                    Text(L("隐私政策", "Privacy Policy", "プライバシーポリシー"))
                }
            }
        }
        .navigationTitle(L("隐私", "Privacy", "プライバシー"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { consent = ConsentStore.consented }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("清除", "Clear", "消去"), role: .destructive) {
                guard let target = confirm else { return }
                switch target {
                case .history: SessionStore.save(nil)
                case .learning: RimeStore.clearLearning()
                }
                cleared = target
            }
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .history: return L("清除润色历史？", "Clear polish history?", "整えた履歴を消去しますか？")
        case .learning: return L("清除拼音学习记录？候选会回到默认的顺序。", "Clear pinyin learning? Candidates go back to the default order.",
                                 "ピンインの学習データを消去しますか？候補は初期の順番に戻ります。")
        case nil: return ""
        }
    }

    private func clearRow(_ title: String, target: ClearTarget) -> some View {
        HStack {
            Text(title)
            Spacer()
            if cleared == target {
                Label(L("已清除", "Cleared", "消去しました"), systemImage: "checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button(L("清除", "Clear", "消去")) { confirm = target }
                    .foregroundStyle(Color(hex: 0xFF3B30))
            }
        }
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
        case .zh, .system: return "Enclave 隐私政策"
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

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image("AboutIcon")
                        .resizable()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    Text(L("飞地输入法", "Enclave", "Enclave")).font(.title3.bold())
                    Text(L("版本 \(Self.version)", "Version \(Self.version)", "バージョン \(Self.version)"))
                        .font(.footnote)
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
