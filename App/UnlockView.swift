import StoreKit
import SwiftUI

/// AI 解锁页：试用中（U1）、试用结束（U2）、已解锁（U3）。
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                UnlockHeroCard(access: unlock.access, baseURL: unlocked ? store.settings.baseURL : "")
                if unlocked {
                    currentModel
                    featureList(unlocked: true)
                    purchaseInfo
                } else {
                    ownModel
                    sellingPoints
                    featureList(unlocked: false)
                }
            }
            .padding(16)
            .padding(.bottom, unlocked ? 0 : 120)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            if !unlocked { PurchaseBar(unlock: unlock) }
        }
        // 备案口径是开发者不提供模型服务：只写「AI」，和设置页的卡片一致。
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("恢复购买", "Restore Purchases", "購入を復元")) { Task { await unlock.restore() } }
                    .disabled(unlock.purchasing)
            }
        }
        .alert(item: $unlock.message) { message in
            Alert(title: Text(message.title), message: message.detail.map { Text($0) },
                  dismissButton: .default(Text(L("知道了", "Got it", "OK"))))
        }
        .task { await unlock.refresh() }
    }

    // MARK: - 用你自己的模型

    private var ownModel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: L("用你自己的模型", "Use your own model", "自分のモデルを使う"),
                          subtitle: L("键盘把文字直接发到你配置的接口", "The keyboard sends text straight to the API you set up",
                                      "キーボードは設定した API に直接テキストを送ります"))
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    FlowNode(icon: "keyboard", title: L("飞地输入法", "Enclave keyboard", "Enclave キーボード"),
                             subtitle: L("你的手机", "Your iPhone", "あなたの iPhone"))
                    VStack(spacing: 4) {
                        Text(L("直连 HTTPS", "Direct HTTPS", "HTTPS で直接"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5B4BE8))
                            .lineLimit(1)
                            .fixedSize()
                        Line()
                            .stroke(Color(hex: 0x5B4BE8).opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(height: 1.5)
                            .overlay(alignment: .trailing) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x5B4BE8))
                                    .offset(x: 3)
                            }
                    }
                    .frame(minWidth: 64)
                    FlowNode(icon: "server.rack", title: L("你的模型接口", "Your model API", "あなたのモデル API"),
                             subtitle: L("api.你的服务商", "api.your-provider", "api.ご利用のサービス"))
                }
                Text(L("无第三方中转", "No third-party relay", "第三者の中継なし"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                ProviderChips()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    // MARK: - 四个卖点

    private var sellingPoints: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            PointCard(icon: "lock.shield", color: Color(hex: 0x34C759),
                      title: L("文字不经过我们", "Your text skips us", "文章は Enclave を通りません"),
                      detail: L("无第三方中转，不收集、不保存你写的东西", "No third-party relay. Nothing you write is collected or stored",
                                "第三者の中継なし。書いた内容を収集・保存しません"))
            PointCard(icon: "yensign.circle", color: Color(hex: 0xFF9500),
                      title: L("用多少付多少", "Pay only for what you use", "使った分だけ"),
                      detail: L("模型费用直接付给服务商，飞地输入法不加价、不抽成", "Model fees go straight to your provider, with no markup",
                                "モデル料金はサービスに直接支払い、上乗せや手数料はありません"))
            PointCard(icon: "desktopcomputer", color: Color(hex: 0x007AFF),
                      title: L("本地模型也行", "Local models work too", "ローカルモデルも OK"),
                      detail: L("Ollama、LM Studio 跑在自己电脑上，文字不出家门", "Run Ollama or LM Studio on your own computer and keep text at home",
                                "Ollama や LM Studio を自分のパソコンで動かせば、文章は外に出ません"))
            PointCard(icon: "arrow.triangle.2.circlepath", color: Color(hex: 0x7C3AED),
                      title: L("随时换模型", "Switch models anytime", "いつでもモデルを変更"),
                      detail: L("只改地址和 Key，提示词和要求照常用", "Just change the URL and key. Your prompts keep working",
                                "URL とキーを変えるだけで、プロンプトはそのまま使えます"))
        }
    }

    // MARK: - 解锁后可以用 / 已解锁

    private func featureList(unlocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(unlocked ? L("已解锁", "Unlocked", "購入済み") : L("解锁后不限次数", "Unlimited after unlock", "購入で回数無制限"))
                .font(.system(size: 17, weight: .semibold))
            VStack(spacing: 0) {
                ForEach(Array(Self.features.enumerated()), id: \.offset) { index, feature in
                    if index > 0 { Divider().padding(.leading, 56) }
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                                unlocked
                                    ? AnyShapeStyle(Color(hex: 0x34C759))
                                    : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing))))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.system(size: 15, weight: .medium))
                            Text(feature.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if unlocked {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x248A3D))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            if !unlocked {
                Text(L("打字、拼音、常用词一直免费，不受试用影响", "Typing, pinyin and My Words are always free",
                       "入力・ピンイン・ユーザ辞書はずっと無料です"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private struct Feature { let icon: String; let title: String; let detail: String }

    private static var features: [Feature] {
        [
            Feature(icon: "sparkles", title: L("润色", "Polish", "整える"),
                    detail: L("整理输入框里的话，选中一段只改那一段", "Tidy up what you typed. Select a part to change only that part",
                              "入力した文章を整えます。選択した部分だけ直すこともできます")),
            Feature(icon: "slider.horizontal.3", title: L("按要求改", "Custom changes", "指示して直す"),
                    detail: L("「委婉一点」「翻成英文」，配合风格一起用", "\"Softer\", \"In English\", together with a style",
                              "「やわらかく」「英語に」など、文体と組み合わせて使えます")),
            Feature(icon: "pencil.line", title: L("帮我写", "Help me write", "下書きを作成"),
                    detail: L("输入框空着时，按要求直接写一段", "With an empty field, write a draft from your prompt",
                              "入力欄が空のとき、指示どおりに文章を書きます")),
            Feature(icon: "arrow.clockwise", title: L("再润", "Rewrite", "別の案"),
                    detail: L("不满意再来一版，上下翻着挑", "Get another version and flip between them",
                              "別の案を出して、上下に切り替えて選べます")),
        ]
    }

    // MARK: - 已解锁：正在用的模型、购买记录

    private var currentModel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("正在用的模型", "Current model", "使用中のモデル")).font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RowIcon(systemName: "cpu", color: Color(hex: 0x5B4BE8), size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.settings.model.isEmpty ? L("还没配置", "Not set up", "未設定") : store.settings.model)
                            .font(.system(size: 15, weight: .semibold))
                        Text(store.settings.baseURL.isEmpty ? "—" : store.settings.baseURL)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if case .success = store.test {
                        Label(L("连接正常", "Connected", "接続済み"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0x248A3D))
                            .labelStyle(.titleAndIcon)
                    }
                }
                Button { router.openModel(detail: true) } label: {
                    Text(L("换个模型", "Change model", "モデルを変更"))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x5B4BE8))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var purchaseInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                if case .unlocked(let date?) = unlock.access {
                    InfoRow(title: L("购买时间", "Purchased", "購入日"), value: Loc.fullDate(date))
                    Divider().padding(.leading, 14)
                }
                InfoRow(title: L("购买方式", "Purchase", "購入方法"),
                        value: L("App Store · 一次买断", "App Store · One-time purchase", "App Store・買い切り"))
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            Text(L("购买记录由 App Store 管理，换手机后会自动恢复。", "Your purchase is kept by the App Store and comes back on a new iPhone.",
                   "購入履歴は App Store が管理し、機種変更後も自動で復元されます。"))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - 顶部渐变卡片

struct UnlockHeroCard: View {
    let access: AIAccess
    /// 已解锁时显示用户真实地址，其他状态显示示意地址。
    let baseURL: String

    private var unlocked: Bool {
        if case .unlocked = access { return true }
        return false
    }

    private var subtitle: String {
        let uses = AIAccess.dailyFreeUses
        switch access {
        case .unlocked:
            return L("谢谢支持。AI 功能一直能用，模型随你换。", "Thanks for your support. AI features are yours to keep, with any model.",
                     "ご購入ありがとうございます。AI 機能はずっと使え、モデルも自由に変えられます。")
        case .expired:
            return L("试用结束后每天免费用 \(uses) 次。一次买断，不限次数。", "After the trial: \(uses) free uses a day. Pay once for unlimited.",
                     "無料体験のあとも 1 日 \(uses) 回まで無料。買い切りで回数無制限。")
        case .trial:
            return L("接上你自己的模型润色。一次买断，没有订阅。", "Polish with your own model. One-time purchase, no subscription.",
                     "自分のモデルで文章を整えます。買い切りで、サブスクはありません。")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.16)))
            Text("AI")
                .font(.system(size: 12, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(Color(hex: 0xB9B2FF))
                .padding(.top, 4)
            Text(unlocked ? L("AI 润色已解锁", "AI Polish is unlocked", "AI 機能を購入済みです")
                          : L("解锁 AI 润色", "Unlock AI Polish", "AI 機能のロックを解除"))
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 14.5))
                .foregroundStyle(Color(hex: 0xDCD8FF))
                .fixedSize(horizontal: false, vertical: true)
            statusCapsule
            Text("base_url = \(baseURL.isEmpty ? L("https://你的接口/v1", "https://your-api/v1", "https://あなたの API/v1") : baseURL)")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Color(hex: 0xDCD8FF))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.22)))
                .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1E1B4B), Color(hex: 0x3730A3), Color(hex: 0x6D28D9)],
                               startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
                RadialGradient(colors: [Color(hex: 0xA78BFA).opacity(0.55), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 220)
                RadialGradient(colors: [Color(hex: 0xEC4899).opacity(0.28), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 200)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var statusCapsule: some View {
        let (icon, text, color, fill): (String, String, Color, Color) = {
            switch access {
            case .trial(let days, let ends):
                return ("clock", L("试用剩余 \(days) 天 · \(Loc.monthDay(ends)) 结束",
                                   "Free trial · \(days) days left · Ends \(Loc.monthDay(ends))",
                                   "無料体験 残り \(days) 日・\(Loc.monthDay(ends))に終了"),
                        Color(hex: 0xE4E0FF), .white.opacity(0.14))
            case .expired:
                let left = AIAccess.usesLeftToday
                let text = left > 0
                    ? L("试用已结束 · 今天还能用 \(left) 次", "Trial ended · \(left) free uses left today", "無料体験終了 · 今日あと \(left) 回")
                    : L("试用已结束 · 今天已用完", "Trial ended · none left today", "無料体験終了 · 今日の分は終了")
                return ("lock.fill", text, Color(hex: 0xFFD3CF), .white.opacity(0.14))
            case .unlocked:
                return ("checkmark", L("已解锁", "Unlocked", "購入済み"), Color(hex: 0xB7F5C8),
                        Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255).opacity(0.22))
            }
        }()
        return Label(text, systemImage: icon)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(fill))
            .padding(.top, 2)
    }
}

// MARK: - 底部购买栏

private struct PurchaseBar: View {
    @ObservedObject var unlock: UnlockStore

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let price = unlock.displayPrice {
                        Text(price).font(.system(size: 24, weight: .bold))
                    }
                    Text(L("一次买断 · 没有订阅 · 不按次收费", "One-time · No subscription", "買い切り・サブスクなし"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Button { Task { await unlock.buy() } } label: {
                    HStack(spacing: 6) {
                        if unlock.purchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text("✦")
                            Text(L("解锁", "Unlock", "購入する"))
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 168, height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                        LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(.plain)
                .disabled(unlock.purchasing)
            }
            HStack(spacing: 4) {
                Text(L("通过 Apple ID 付款 · 同一 Apple ID 的设备都能用", "Paid with your Apple Account · Works on all your devices",
                       "Apple アカウントで支払い・同じアカウントの端末で使えます"))
                Text("·")
                Button(L("隐私政策", "Privacy Policy", "プライバシーポリシー")) { AppRouter.shared.settingsPath.append(.privacyPolicy) }
                Text("·")
                Link(L("用户协议", "Terms of Use", "利用規約"), destination: LegalLinks.terms)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
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
        case .failed(let reason): return reason
        }
    }
}

// MARK: - 小组件

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

private struct FlowNode: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(hex: 0x5B4BE8))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: 0x5B4BE8).opacity(0.12)))
            Text(title).font(.system(size: 12.5, weight: .semibold)).multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct ProviderChips: View {
    /// 中国大陆店面不列 OpenAI，换成智谱。
    private let names = ["DeepSeek", Storefront.isMainlandChina ? L("智谱", "Zhipu", "Zhipu") : "OpenAI", L("通义千问", "Qwen", "Qwen"), "Kimi",
                         L("Ollama 本地", "Ollama (local)", "Ollama（ローカル）"), "LM Studio"]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
            Text(L("+ 任意 OpenAI 兼容接口", "+ Any OpenAI-compatible API", "+ OpenAI 互換の API なら何でも"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(hex: 0x5B4BE8))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .overlay(Capsule().stroke(Color(hex: 0x5B4BE8).opacity(0.6), lineWidth: 1))
        }
    }
}

private struct PointCard: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.14)))
            Text(title).font(.system(size: 14.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer()
            Text(value).font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }
}
