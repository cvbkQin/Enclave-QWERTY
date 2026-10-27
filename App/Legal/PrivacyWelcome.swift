import SwiftUI

// MARK: - 首次启动隐私说明（CP1、CP2）

/// 第一次打开 App 时整页显示：四行说明、《隐私政策》链接、「同意」和「不同意」。
/// 点「不同意」弹系统 alert，可以「同意并继续」或「仅使用基础功能」；不同意也能打字。
struct PrivacyWelcomeView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var asksAgain = false
    @State private var showsPolicy = false
    /// 打开时记下是不是更新后再弹（同意后 seenVersion 就变了，不能每次重新算）。
    @State private var updated = PrivacyConsent.isUpdate

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if updated {
                        // 隐私政策更新后再弹（同意过旧版的人才看到），首次安装不显示。
                        Text(L("隐私说明有更新：新增识意问答联网（Kimi 搜索）", "Privacy notice updated: adds web search in Ask (Kimi search)", "プライバシーの説明を更新しました：質問のウェブ検索（Kimi 検索）を追加"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255)))
                            .padding(.bottom, 20)
                    }
                    Image("AboutIcon")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: AppColor.purple.opacity(0.25), radius: 12, y: 6)
                    Text(L("欢迎使用飞地输入法", "Welcome to Enclave", "Enclave へようこそ"))
                        .font(.system(size: 26, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)
                    Text(L("开始之前，先说清楚你的文字去了哪里", "Before you start, here's where your text goes", "はじめに、文章がどこへ行くのかを説明します"))
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                    VStack(alignment: .leading, spacing: 20) {
                        point(Image(systemName: "iphone"), color: .blue,
                              L("打字只在手机上", "Typing stays on your iPhone", "入力は iPhone の中だけ"),
                              L("打字和候选全部在手机上完成，不联网。", "Typing and candidates are all handled on your iPhone, offline.", "入力も候補もすべて iPhone 上で処理し、通信しません。"))
                        point(Image(systemName: "link"), color: AppColor.purple,
                              L("AI 只连你自己的接口", "AI only talks to your own API", "AI はあなたの API にだけ接続"),
                              L("只有你主动用 AI 时，选中的文字才会发到你自己填写的模型接口。", "Only when you use AI is the selected text sent, to the model API you set up yourself.", "AI を使ったときだけ、選んだ文章をあなたが設定したモデルの API に送ります。"))
                        point(Image(systemName: "server.rack"), color: .green, slashed: true,
                              L("我们没有服务器", "We have no servers", "サーバーはありません"),
                              L("开发者不收集你输入的任何内容。", "The developer collects nothing you type.", "開発者は入力内容を一切収集しません。"))
                        point(Image(systemName: "key"), color: .orange,
                              L("「允许完全访问」只用来", "Allow Full Access is only for", "「フルアクセスを許可」の用途"),
                              L("联网调用你配置的接口、按键震动、和 App 共享设置。", "Calling the API you set up, key haptics, and sharing settings with the app.", "設定した API への接続、キーの振動、アプリとの設定共有だけです。"))
                    }
                    .padding(.top, 28)
                }
                .padding(.horizontal, 28)
                .padding(.top, 84)
                .padding(.bottom, 24)
            }
            VStack(spacing: 14) {
                policyLine
                Button { router.agreePrivacy() } label: {
                    Text(L("同意", "Agree", "同意する"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppColor.purple))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                Button { asksAgain = true } label: {
                    Text(L("不同意", "Don't Agree", "同意しない"))
                        .font(.system(size: 17))
                        .foregroundStyle(AppColor.purple)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .interactiveDismissDisabled()
        .alert(L("不同意也能打字", "You can still type", "同意しなくても入力できます"), isPresented: $asksAgain) {
            Button(L("同意并继续", "Agree and Continue", "同意して続ける")) { router.agreePrivacy() }
                .keyboardShortcut(.defaultAction)
            Button(L("仅使用基础功能", "Basic Features Only", "基本機能のみ使う")) { router.useBasicOnly() }
        } message: {
            Text(L("不同意也可以使用基础拼音输入，AI 功能不可用。之后可以随时在「设置 › 隐私」里同意。",
                   "Without agreeing you can still use basic pinyin input, but AI features are off. You can agree any time in Settings › Privacy.",
                   "同意しなくても基本のピンイン入力は使えますが、AI 機能は使えません。あとから「設定 › プライバシー」でいつでも同意できます。"))
        }
        .sheet(isPresented: $showsPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("完成", "Done", "完了")) { showsPolicy = false }
                        }
                    }
            }
        }
    }

    /// 「点「同意」即表示你已阅读并同意《隐私政策》」，《隐私政策》紫色可点。
    private var policyLine: some View {
        Button { showsPolicy = true } label: {
            (Text(L("点「同意」即表示你已阅读并同意", "By tapping Agree, you accept the ", "「同意する」をタップすると、"))
                .foregroundColor(.secondary)
             + Text(L("《隐私政策》", "Privacy Policy", "プライバシーポリシー")).foregroundColor(AppColor.purple)
             + Text(L("", ".", "に同意したことになります")).foregroundColor(.secondary))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }

    private func point(_ icon: Image, color: Color, slashed: Bool = false, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            icon
                .font(.system(size: 19))
                .foregroundStyle(color)
                .overlay {
                    // 「没有服务器」：服务器图标上画一道斜线。
                    if slashed {
                        Capsule().fill(color).frame(width: 2, height: 26).rotationEffect(.degrees(-45))
                    }
                }
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
