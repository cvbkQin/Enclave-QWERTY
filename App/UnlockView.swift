import StoreKit
import SwiftUI

/// AI 解锁页（R5，design/app-redesign，11-22 交付）：系统分组列表，没开始试用、试用中、试用结束、已解锁四种状态。
/// 一屏只有一个实色按钮：没开始试用时是「开始 14 天免费试用」，买断是下面的文字按钮；试用中和到期后是「US$2.99 一次买断」。
/// 买成功、试用开始后不弹 App 自己的卡：Apple 会弹确认和「已完成」，页面原地变成新状态。
/// 入口：设置顶部「AI」卡片、首页最后几天的提醒条、键盘提示卡里的「去解锁」（enclave://unlock）。
struct UnlockView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var unlock = UnlockStore.shared

    private var unlocked: Bool {
        if case .unlocked = unlock.access { return true }
        return false
    }

    var body: some View {
        List {
            header
            status
            if unlocked { currentModel }
            features
            ownModel
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if !unlocked { PurchaseBar(unlock: unlock) }
        }
        // 备案口径是开发者不提供模型服务：只写「AI」，和设置页的卡片一致。
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("恢复购买", "Restore", "購入を復元")) { Task { await unlock.restore() } }
                    .disabled(unlock.purchasing)
            }
        }
        .alert(item: $unlock.message) { message in
            Alert(title: Text(message.title), message: message.detail.map { Text($0) },
                  dismissButton: .default(Text(L("知道了", "Got it", "OK"))))
        }
        .task { await unlock.refresh() }
    }

    // MARK: - 头部：图标、标题、一句话

    private var header: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(HIG.accentFill))
                    .accessibilityHidden(true)
                Text(unlocked ? L("AI 润色和问答已解锁", "AI Polish & Ask unlocked", "AI 機能を購入済みです")
                              : L("AI 润色和问答", "AI Polish & Ask", "AI で整える・質問する"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(L("用你自己的模型。文字直接发到你配置的接口，不经过我们。",
                       "Use your own model. Your text goes straight to the API you set up, never through us.",
                       "自分のモデルを使います。文章は設定した API に直接送られ、当方を通りません。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    // MARK: - 第一组：今天还剩几次 / 试用剩几天 / 购买记录

    @ViewBuilder
    private var status: some View {
        let uses = AIAccess.dailyFreeUses
        switch unlock.access {
        case .notStarted, .expired:
            let left = AIAccess.usesLeftToday
            Section {
                ValueRow(title: L("还能免费用", "Free uses left", "今日の無料の残り"),
                         value: L("\(left) / \(uses) 次", "\(left) / \(uses)", "\(left) / \(uses) 回"),
                         color: left > 0 ? HIG.accentText : HIG.warning, emphasized: true)
            } header: {
                Text(L("今天", "Today", "今日"))
            } footer: {
                Text(unlock.access == .notStarted
                     ? L("每天 0 点恢复 \(uses) 次。打字、拼音、常用词一直免费。", "Resets to \(uses) at midnight. Typing, pinyin and My Words are always free.",
                         "毎日 0 時に \(uses) 回に戻ります。入力・ピンイン・ユーザ辞書はずっと無料です。")
                     : L("试用已结束。每天 0 点恢复 \(uses) 次，打字、拼音、常用词一直免费。", "Your trial has ended. Resets to \(uses) at midnight. Typing, pinyin and My Words are always free.",
                         "無料体験は終了しました。毎日 0 時に \(uses) 回に戻ります。入力・ピンイン・ユーザ辞書はずっと無料です。"))
            }
        case .trial(let days, let ends):
            Section {
                ValueRow(title: L("试用剩余", "Trial left", "無料体験の残り"),
                         value: L("\(days) 天", days == 1 ? "1 day" : "\(days) days", "\(days) 日"),
                         color: unlock.access.isEndingSoon ? HIG.warning : HIG.accentText, emphasized: true)
                ValueRow(title: L("用到", "Until", "期限"), value: Loc.monthDay(AIAccess.lastTrialDay(ends: ends)))
            } header: {
                Text(L("试用", "Free trial", "無料体験"))
            } footer: {
                Text(L("到期不扣费、不续订，之后每天免费 \(uses) 次。", "Nothing is charged and nothing renews. Afterwards you get \(uses) free uses a day.",
                       "終了しても料金はかからず、更新もされません。その後は 1 日 \(uses) 回まで無料です。"))
            }
        case .unlocked(let date):
            Section {
                if let date {
                    ValueRow(title: L("购买时间", "Purchased", "購入日"), value: Loc.fullDate(date))
                }
                ValueRow(title: L("购买方式", "Purchase", "購入方法"),
                         value: L("App Store · 一次买断", "App Store · One-time", "App Store・買い切り"))
            } header: {
                Text(L("已解锁", "Unlocked", "購入済み"))
            } footer: {
                Text(L("购买记录由 App Store 管理，换手机后会自动恢复。", "Your purchase is kept by the App Store and comes back on a new iPhone.",
                       "購入履歴は App Store が管理し、機種変更後も自動で復元されます。"))
            }
        }
    }

    // MARK: - 已解锁：正在用的模型

    private var currentModel: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.settings.model.isEmpty ? L("还没配置", "Not set up", "未設定") : store.settings.model)
                Text(store.settings.baseURL.isEmpty ? "—" : store.settings.baseURL)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 2)
            Button(L("换个模型", "Change model", "モデルを変更")) { router.openModel(detail: true) }
                .foregroundStyle(HIG.accentText)
        } header: {
            Text(L("正在用的模型", "Current model", "使用中のモデル"))
        }
    }

    // MARK: - 功能

    private var features: some View {
        Section {
            FeatureRow(icon: "sparkles", title: L("润色", "Polish", "整える"),
                       detail: L("整理输入框里的话，选中一段只改那一段", "Tidy up what you typed. Select a part to change only that part",
                                 "入力した文章を整えます。選択した部分だけ直すこともできます"))
            FeatureRow(icon: "questionmark.bubble", title: L("问答", "Ask", "質問"),
                       detail: L("直接回答你写的问题", "Answers the question you typed", "書いた質問にそのまま答えます"))
            FeatureRow(icon: "doc.text", title: L("帮我写", "Write for me", "代わりに書く"),
                       detail: L("输入框空着时，按要求写一段", "When the field is empty, writes a passage to your request",
                                 "入力欄が空のとき、指示どおりに文章を書きます"))
            FeatureRow(icon: "arrow.clockwise", title: L("再润", "Rewrite", "別の案"),
                       detail: L("不满意再来一版，上下翻着挑", "Get another version and flip between them",
                                 "別の案を出して、上下に切り替えて選べます"))
        } header: {
            Text(unlocked ? L("可以用", "Included", "使える機能") : L("解锁后不限次数", "Unlimited after unlock", "購入で回数無制限"))
        }
    }

    // MARK: - 用你自己的模型

    private var ownModel: some View {
        Section {
            FeatureRow(icon: "lock.shield", title: L("文字不经过我们", "Your text skips us", "文章は当方を通りません"),
                       detail: L("没有第三方中转，不收集、不保存", "No third-party relay. Nothing is collected or stored",
                                 "第三者の中継なし。収集も保存もしません"))
            FeatureRow(icon: "yensign.circle", title: L("用多少付多少", "Pay only for what you use", "使った分だけ"),
                       detail: L("模型费用直接付给服务商", "Model fees go straight to your provider", "モデル料金はサービスに直接支払います"))
        } header: {
            Text(L("用你自己的模型", "Use your own model", "自分のモデルを使う"))
        }
    }
}

// MARK: - 列表行

/// 左边标题、右边值；最重要的那个数字用品牌紫（用完、最后几天用橙）。
private struct ValueRow: View {
    let title: String
    let value: String
    var color: Color = .secondary
    var emphasized = false

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// SF 图标（品牌紫）+ 标题 + 一句说明。
private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(HIG.accentText)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 底部购买栏

private struct PurchaseBar: View {
    @ObservedObject var unlock: UnlockStore

    private var notStarted: Bool { unlock.access == .notStarted }

    var body: some View {
        VStack(spacing: 10) {
            terms
            Button {
                Task {
                    if notStarted { await unlock.startTrial() } else { await unlock.buy() }
                }
            } label: {
                ZStack {
                    if unlock.purchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(notStarted ? L("开始 \(AIAccess.trialDays) 天免费试用", "Start \(AIAccess.trialDays)-day free trial",
                                            "\(AIAccess.trialDays) 日間の無料体験を始める")
                                        : unlock.buyTitle)
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            .tint(HIG.accentFill)
            .disabled(unlock.purchasing)
            if notStarted {
                Button { Task { await unlock.buy() } } label: {
                    Text(L("或 ", "Or ", "または ") + unlock.buyTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HIG.accentText)
                .disabled(unlock.purchasing)
                .padding(.top, -6)
            }
            legal
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// 按钮正上方的说明（审核指南 3.1.1）：没开始试用时写试用多长、到期怎样（第一句加粗）；买断价格在下面的文字按钮上。
    @ViewBuilder
    private var terms: some View {
        let uses = AIAccess.dailyFreeUses
        let days = AIAccess.trialDays
        VStack(spacing: 2) {
            if notStarted {
                Text(L("免费试用 \(days) 天，AI 不限次数。", "Free for \(days) days with unlimited AI.", "\(days) 日間無料、AI は回数無制限。"))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(L("到期不扣费、不续订，之后每天免费 \(uses) 次。", "Nothing is charged or renewed. Then \(uses) free uses a day.",
                       "終了しても料金はかからず、更新もされません。その後は 1 日 \(uses) 回まで無料です。"))
            } else {
                Text(L("一次买断，以后都不限次数。没有订阅。", "Pay once for unlimited use. No subscription.", "一度の購入でずっと回数無制限。サブスクはありません。"))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var legal: some View {
        HStack(spacing: 4) {
            Text(L("通过 Apple ID 付款", "Paid via Apple Account", "Apple アカウントで支払い"))
            Text("·")
            Button(L("隐私政策", "Privacy Policy", "プライバシーポリシー")) { AppRouter.shared.settingsPath.append(.privacyPolicy) }
                .foregroundStyle(HIG.accentText)
            Text("·")
            Link(L("用户协议", "Terms of Use", "利用規約"), destination: LegalLinks.terms)
                .foregroundStyle(HIG.accentText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// 用户协议用 Apple 的标准 EULA；隐私政策在 App 里的「隐私」页。
enum LegalLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let icp = URL(string: "https://beian.miit.gov.cn/")!
}

extension UnlockStore.Message {
    var title: String {
        switch self {
        case .unlocked: return L("已解锁", "Unlocked", "購入済み")
        case .pending: return L("等家长批准", "Waiting for approval", "保護者の承認待ち")
        case .notFound: return L("没有找到购买记录", "No purchase found", "購入履歴が見つかりません")
        case .offline: return L("暂时连不上 App Store", "Can't reach the App Store", "App Store に接続できません")
        case .unavailable: return L("App Store 里暂时买不到", "Not available in the App Store yet", "App Store でまだ購入できません")
        case .failed: return L("没有完成购买", "Purchase not completed", "購入できませんでした")
        }
    }

    var detail: String? {
        switch self {
        case .unlocked: return L("AI 功能不再限次数。", "AI features no longer have a daily limit.", "AI 機能の回数制限がなくなりました。")
        case .pending: return L("批准后会自动解锁。", "It unlocks automatically once approved.", "承認されると自動で使えるようになります。")
        case .notFound: return L("这个 Apple ID 还没有买过 AI 解锁。", "This Apple Account hasn't unlocked AI.",
                                 "この Apple アカウントでは AI を購入していません。")
        case .offline: return L("没有扣款，稍后再试。", "You weren't charged. Try again later.", "料金は請求されていません。後でもう一度お試しください。")
        case .unavailable: return L("App Store 没有返回 AI 解锁这个商品，没有扣款。", "The App Store didn't return the AI unlock. You weren't charged.",
                                    "App Store から AI 購入の商品が返されませんでした。料金は請求されていません。")
        case .failed(let reason): return reason
        }
    }
}
