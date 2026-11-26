import SwiftUI

// 第一次打开「自动保存复制的内容」的确认卡（T97 方案 B；11-26 对齐清单第 95 条重做，design/clipboard-autosave CA4）：
// 屏幕中间的纯色卡片，盖住整个 App（包括底部标签栏），底下压黑。文字靠左，底部「取消」「开启」两个胶囊按钮一直看得到。
// 不用玻璃、不用半屏弹层；部署目标 iOS 16，所以挂在根视图上一层覆盖（RootView），不用 fullScreenCover。

/// 谁要弹卡就调 present，根视图上的 AutoSaveConsentHost 负责画。点「开启」才执行 onTurnOn；点卡片外面不关。
final class AutoSaveConsent: ObservableObject {
    static let shared = AutoSaveConsent()

    @Published private(set) var presented = false
    private var onTurnOn: (() -> Void)?

    func present(onTurnOn: @escaping () -> Void) {
        self.onTurnOn = onTurnOn
        presented = true
    }

    func finish(turnOn: Bool) {
        let action = onTurnOn
        onTurnOn = nil
        presented = false
        if turnOn { action?() }
    }
}

/// 挂在 RootView 上：卡片出来时压黑 22%（深色 45%）0.2 秒淡入；卡片 1.06 → 1 倍同时淡入，spring(0.35, 0.85)；
/// 收起 0.18 秒淡出、缩到 0.96。减弱动态效果时只淡入淡出。
struct AutoSaveConsentHost: View {
    @ObservedObject private var consent = AutoSaveConsent.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if consent.presented {
                Color.black.opacity(colorScheme == .dark ? 0.45 : 0.22)
                    .ignoresSafeArea()
                    // 点卡片外面不关：一定要选一个。也挡住底下的点按。
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
                GeometryReader { geo in
                    AutoSaveConsentCard(maxHeight: max(240, geo.size.height - 80)) { consent.finish(turnOn: $0) }
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .transition(cardTransition)
            }
        }
    }

    private var cardTransition: AnyTransition {
        if reduceMotion { return .opacity.animation(.easeInOut(duration: 0.2)) }
        return .asymmetric(
            insertion: .scale(scale: 1.06).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.85)),
            removal: .scale(scale: 0.96).combined(with: .opacity).animation(.easeIn(duration: 0.18)))
    }
}

/// 卡片（CA4 ②）：宽 338（iPad 360），圆角 32，白底（深色 #2C2C2E），浅色阴影 y 10、模糊 36、黑 12%。
/// 从上到下靠左：图标、标题、副标题、四行说明，底部两个胶囊按钮。系统字号调大放不下时只有说明那几行滑动。
struct AutoSaveConsentCard: View {
    var maxHeight: CGFloat
    var finish: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var titleFocused: Bool

    private var dark: Bool { colorScheme == .dark }
    private static let purple = Color(hex: 0x5B4BE8)
    private var width: CGFloat { UIDevice.current.userInterfaceIdiom == .pad ? 360 : 338 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
            // 说明放得下就不滑；放不下（大字号）时只有这一段滑动。
            ViewThatFits(in: .vertical) {
                rows.padding(.horizontal, 24)
                ScrollView { rows.padding(.horizontal, 24) }
            }
            .padding(.top, 16)
            buttons
                .padding(.top, 22)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: maxHeight)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(dark ? Color(hex: 0x2C2C2E) : .white))
        .shadow(color: .black.opacity(dark ? 0 : 0.12), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { titleFocused = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(dark ? Color(hex: 0xC4B5FD) : Self.purple)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(dark ? Color(hex: 0x2E2766) : Color(hex: 0xE4E0FC)))
                .accessibilityHidden(true)
            Text(L("打开自动保存？", "Turn on Auto-Save?", "自動保存をオンにしますか？"))
                .font(.system(size: 20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(L("键盘显示时，自动读取你新复制的文字，存进剪贴板记录。",
                   "While the keyboard is showing, it reads newly copied text and saves it to clipboard history.",
                   "キーボード表示中に、新しくコピーしたテキストを読み取ってクリップボード履歴に保存します。"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("bell", L("每次读取，系统都会在顶部提示「飞地输入法粘贴自…」", "Each time, iOS shows \"Enclave pasted from…\" at the top",
                          "読み取るたびに、iOS が上部に「Enclave が…からペースト」と表示します"))
            row("lock", L("密码管理器复制的密码、纯数字（如验证码）不保存",
                          "Passwords from password managers and digit-only text (like codes) aren't saved",
                          "パスワード管理アプリのパスワードや数字だけのテキスト（確認コードなど）は保存しません"))
            row(DeviceName.current == "iPad" ? "ipad" : "iphone",
                L("只存在这台 \(DeviceName.current) 上，24 小时后删除，不上传", "Kept only on this \(DeviceName.current), deleted after 24 hours, never uploaded",
                  "この \(DeviceName.current) にだけ保存し、24 時間後に削除します。アップロードはしません"))
            row("switch.2", L("随时可以在这里关掉", "You can turn it off here at any time", "ここでいつでもオフにできます"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(dark ? Color(hex: 0xB4A9FF) : Self.purple)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 左「取消」#EEEEF2（深色 #3A3A3C）黑字（深色白字）17 常规，右「开启」#5B4BE8 白字 17 中粗；各 48 高，中间隔 10，不描边、没有光泽。
    private var buttons: some View {
        HStack(spacing: 10) {
            Button { finish(false) } label: {
                Text(L("取消", "Cancel", "キャンセル"))
                    .font(.system(size: 17))
                    .foregroundStyle(dark ? Color.white : Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(dark ? Color(hex: 0x3A3A3C) : Color(hex: 0xEEEEF2))
            Button { finish(true) } label: {
                Text(L("开启", "Turn On", "オンにする"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.purple)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}
