import SwiftUI

// 功能演示的几页（T95，design/onboard-v2 OG2、OG3，动效 OM1–OM3）：演示首页、章节过场、步骤页、演示完成，
// 以及 设置 › 功能演示 的章节页。样子照 DESIGN.md：系统分组列表、一个实色主按钮、第二个动作是文字按钮，没有渐变和光晕。

/// 引导里几页共用的颜色和字号（系统字号档：标题 22、正文 17、说明 15、脚注 13）。
enum TourUI {
    /// 品牌紫：浅色 #5B4BE8，深色底色 #8B80F9。
    static let accent = Color(light: 0x5B4BE8, dark: 0x8B80F9)
    /// 紫色的字：深色 #B4A9FF。
    static let accentText = Color(light: 0x5B4BE8, dark: 0xB4A9FF)
    static let page = Color(.systemGroupedBackground)
    static let group = Color(.secondarySystemGroupedBackground)
    static let green = Color(.systemGreen)
    /// 缓动 cubic-bezier(.2, .8, .2, 1)。
    static func ease(_ duration: Double) -> Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: duration) }
}

// MARK: - 整个演示

struct FeatureTourView: View {
    enum Exit {
        /// 首页「跳过演示」。
        case skip
        /// 完成页「开始设置」。
        case setup
        /// 完成页「稍后」；从设置里看的放完。
        case later
    }

    /// 从设置里看：nil 是首次打开（先进演示首页）；.some(nil) 从头播放；.some(章) 只放这一章。
    var replay: TourChapter??
    var onExit: (Exit) -> Void

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = TourModel()

    var body: some View {
        ZStack {
            TourUI.page.ignoresSafeArea()
            switch model.page {
            case .welcome:
                TourWelcomePage(model: model, onSkip: { exit(.skip) })
                    .transition(.opacity)
            case .interlude(let chapter):
                TourInterlude(chapter: chapter, number: chapter.rawValue + 1)
                    .id(chapter)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .offset(y: -24).combined(with: .opacity)))
            case .step:
                TourStepPage(model: model)
                    .transition(.opacity)
            case .finished, .exit:
                TourFinishedPage(onSetup: { exit(.setup) }, onLater: { exit(.later) })
                    .transition(.opacity)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            model.reduceMotion = reduceMotion
            model.layout = store.settings.keyboardLayout
            model.startDemo()
            if let replay {
                model.replay = true
                model.start(layout: store.settings.keyboardLayout, chapter: replay)
            }
        }
        .onChange(of: model.page) { page in
            if page == .finished { FeatureTour.seen = true }
            if page == .exit { exit(.later) }
        }
        .onDisappear {
            model.stop()
            if replay == nil { FeatureTour.seen = true }
        }
    }

    private func exit(_ how: Exit) {
        model.stop()
        if replay == nil { FeatureTour.seen = true }
        onExit(how)
    }
}

// MARK: - 进场：由上到下依次出现（淡入、上移 14、模糊 6 → 0）

private struct TourEntrance: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : TourUI.ease(0.56).delay(0.06 * Double(index)), value: shown)
    }
}

extension View {
    func tourEntrance(_ index: Int, _ shown: Bool) -> some View { modifier(TourEntrance(index: index, shown: shown)) }
}

/// 文字替换：旧的淡出、上移 6、模糊 5；新的晚 0.15 秒从下方 6 由模糊变清晰。
private struct TourSwap: ViewModifier {
    var y: CGFloat
    var blur: CGFloat
    var opacity: Double
    func body(content: Content) -> some View { content.offset(y: y).blur(radius: blur).opacity(opacity) }
}

extension AnyTransition {
    static func tourSwap(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(.easeInOut(duration: 0.2)) }
        return .asymmetric(
            insertion: .modifier(active: TourSwap(y: 6, blur: 5, opacity: 0), identity: TourSwap(y: 0, blur: 0, opacity: 1))
                .animation(TourUI.ease(0.42).delay(0.15)),
            removal: .modifier(active: TourSwap(y: -6, blur: 5, opacity: 0), identity: TourSwap(y: 0, blur: 0, opacity: 1))
                .animation(.easeIn(duration: 0.24)))
    }
}

/// 页面底部：一个实色主按钮，下面一个文字按钮。
private struct TourButtons: View {
    let primary: String
    let action: () -> Void
    var secondary: String?
    var secondaryAction: () -> Void = {}

    var body: some View {
        VStack(spacing: 4) {
            GuidePrimaryButton(primary, action: action)
            if let secondary { GuideSecondaryButton(secondary, action: secondaryAction) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: PadWidth.content)
    }
}

/// 分组标题、脚注（13pt 灰字，和系统分组列表一样左缩进 16）。
private struct TourGroupNote: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

/// 章节一行：小方块、章名和副标题、右边几步或打勾。矮屏只留章名。
private struct TourChapterRow<Trailing: View>: View {
    let chapter: TourChapter
    var compact = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            TourChapterIcon(chapter: chapter, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(chapter.name).font(.system(size: 17)).foregroundStyle(.primary).lineLimit(1)
                if !compact {
                    Text(chapter.subtitle).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(minHeight: compact ? 44 : 56)
        .contentShape(Rectangle())
    }
}

private func stepsLabel(_ count: Int) -> String {
    L("\(count) 步", count == 1 ? "1 step" : "\(count) steps", "\(count) ステップ")
}

/// 分组：系统分组列表那样的白底圆角 10，行间细线从文字左边开始。
private struct TourGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourUI.group))
            .padding(.horizontal, 16)
    }
}

private struct TourRowDivider: View {
    var inset: CGFloat = 58
    var body: some View { Divider().padding(.leading, inset) }
}

// MARK: - OG2 ① 演示首页「认识飞地输入法」

private struct TourWelcomePage: View {
    @ObservedObject var model: TourModel
    let onSkip: () -> Void
    @EnvironmentObject private var store: AppStore
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            // 一屏放下，不滚动：矮屏（SE）章节只留章名和步数，卡片收矮。
            let compact = proxy.size.height < 640
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(L("认识飞地输入法", "Meet Enclave", "Enclave を知る"))
                        .font(.system(size: 22, weight: .bold))
                    Text(L("跟着指引点一遍，约 3 分钟，全程不联网。", "Follow along for about 3 minutes. Nothing goes online.", "ガイドに沿って約 3 分。通信は一切しません。"))
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, compact ? 12 : 24)
                .tourEntrance(0, shown)
                VStack(alignment: .leading, spacing: 6) {
                    TourGroupNote(text: L("选择你习惯的键盘", "Choose your keyboard", "使い慣れたキーボードを選ぶ"))
                    HStack(spacing: 12) {
                        ForEach([KeyboardLayout.nineKey, .qwerty]) { layout in
                            LayoutCard(layout: layout, selected: store.settings.keyboardLayout == layout,
                                       detail: layout == .qwerty ? Text(store.settings.doublePinyin?.shortTitle ?? L("全拼", "Full pinyin", "全拼")) : nil,
                                       illustrationHeight: compact ? 50 : 64) {
                                store.settings.keyboardLayout = layout
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    TourGroupNote(text: L("演示和输入法都用这个布局，可在 键盘 › 中文布局 更改。",
                                          "The tour and the keyboard both use this layout. Change it under Keyboard › Chinese layout.",
                                          "デモとキーボードの両方でこの配列を使います。キーボード › 中国語の配列 で変更できます。"))
                }
                .padding(.top, compact ? 14 : 22)
                .tourEntrance(1, shown)
                VStack(alignment: .leading, spacing: 6) {
                    TourGroupNote(text: L("6 个章节 · 16 步", "6 chapters · 16 steps", "6 章 · 16 ステップ"))
                    TourGroup {
                        ForEach(TourChapter.allCases) { chapter in
                            if chapter != .polish { TourRowDivider() }
                            TourChapterRow(chapter: chapter, compact: compact) {
                                Text(stepsLabel(chapter.stepCount)).font(.system(size: 15)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, compact ? 14 : 22)
                .tourEntrance(2, shown)
                Spacer(minLength: 8)
                TourButtons(primary: L("开始", "Start", "はじめる"), action: {
                    model.start(layout: store.settings.keyboardLayout, chapter: nil)
                }, secondary: L("跳过演示", "Skip Tour", "デモをスキップ"), secondaryAction: onSkip)
                    .tourEntrance(3, shown)
            }
            .frame(maxWidth: PadWidth.content)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onAppear { DispatchQueue.main.async { shown = true } }
    }
}

// MARK: - 章节过场（每章第一步前）

private struct TourInterlude: View {
    let chapter: TourChapter
    let number: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            TourChapterIcon(chapter: chapter, size: 76)
                .scaleEffect(shown || reduceMotion ? 1 : 0.55)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.68), value: shown)
                .padding(.bottom, 8)
            Text(L("第 \(number) 章", "Chapter \(number)", "第 \(number) 章"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                .tourEntrance(1, shown)
            Text(chapter.name).font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
                .tourEntrance(2, shown)
            Text(chapter.subtitle).font(.system(size: 17)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .tourEntrance(3, shown)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            DispatchQueue.main.async { shown = true }
            if !reduceMotion { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
    }
}

// MARK: - OG3 步骤页

private struct TourStepPage: View {
    @ObservedObject var model: TourModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboardShown = false

    /// 矮屏（iPhone SE 等）：收紧边距、说明只留一行。
    private var compact: Bool { UIScreen.main.bounds.height < 700 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            header
                .padding(.horizontal, 20)
                .padding(.top, compact ? 4 : 12)
            Group {
                if model.appPage {
                    Spacer(minLength: 8)
                    TourAppPage(model: model)
                        .transition(.move(edge: .bottom))
                } else {
                    // 对话卡占满说明和键盘之间的地方（像聊天窗口：消息贴着输入框往上排）。
                    // 原来对话卡按消息多高就多高、下面放 Spacer：消息区量不出高，只剩 1pt，卡片下面却空一大块
                    // （0.97_13 真机、SE 模拟器）。
                    TourChat(model: model, compact: compact)
                        .padding(.horizontal, 16)
                        .padding(.top, compact ? 8 : 14)
                        .padding(.bottom, 8)
                    TourKeyboard(model: model)
                        .offset(y: keyboardShown || reduceMotion ? 0 : 360)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: PadWidth.content)
        }
        .frame(maxWidth: .infinity)
        .overlayPreferenceValue(TourFramesKey.self) { anchors in
            TourTouchLayer(model: model, anchors: anchors)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.86)) { keyboardShown = true }
        }
    }

    /// 顶上一行：左「‹」返回、中间系统进度条、右「跳过」。
    private var topBar: some View {
        HStack(spacing: 14) {
            Button { model.back() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TourUI.accentText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("返回", "Back", "戻る"))
            ProgressView(value: model.progress)
                .tint(TourUI.accent)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: model.progress)
            Button(L("跳过", "Skip", "スキップ")) { model.skip() }
                .font(.system(size: 17)).foregroundStyle(TourUI.accentText)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .padding(.trailing, 20)
    }

    private var header: some View {
        let chapter = model.chapter
        let text = TourStepText.of(model.step, layout: model.layout)
        let index = model.step - chapter.steps.lowerBound + 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TourChapterIcon(chapter: chapter, size: 22)
                ZStack(alignment: .leading) {
                    Text(chapter.name + " · " + L("\(index) / \(chapter.stepCount)", "\(index) of \(chapter.stepCount)", "\(index) / \(chapter.stepCount)"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .id("n-\(model.step)")
                        .transition(.tourSwap(reduceMotion: reduceMotion))
                }
            }
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.title)
                        .font(.system(size: 22, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text.detail)
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : nil)
                        .fixedSize(horizontal: false, vertical: !compact)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("t-\(model.step)")
                .transition(.tourSwap(reduceMotion: reduceMotion))
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: model.step)
    }
}

// MARK: - 对话卡

/// 白色圆角 12 的卡片：联系人一行、右上「演示内容 · 不会发送」，下面消息和宿主输入框（绿色光标）。
private struct TourChat: View {
    @ObservedObject var model: TourModel
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let script = model.script
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(script.avatar).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(.systemOrange)))
                Text(script.contact).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(L("演示内容 · 不会发送", "Demo content · Not sent", "デモ内容 · 送信されません"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            // 消息贴底，放不下时最早的从顶上出去并裁掉；顶边 18pt 用卡片底色渐隐（放得下时那里是空的，看不出来）。
            // 消息区本身占满卡片里剩下的高，不量消息多高。编辑菜单占着气泡上方自己那一格，在消息区里面。
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.messages) { message in
                    TourBubble(model: model, message: message,
                               isLast: message.id == model.messages.last(where: { !$0.mine && !$0.typing })?.id)
                        .transition(message.mine
                            ? .scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity)
                            : .scale(scale: 0.92, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
            .overlay(alignment: .top) {
                LinearGradient(colors: [TourUI.group, TourUI.group.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                    .allowsHitTesting(false)
            }
            hostField
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourUI.group))
    }

    /// 宿主输入框：绿色光标在末尾（全键盘按住空格时跟着挪）；识意框在编辑时宿主没有光标。
    private var hostField: some View {
        let script = model.script
        let caret = !model.askEditing && !model.expanded
        let text = model.field
        let split = text.index(text.endIndex, offsetBy: -min(model.caretBack, text.count))
        return Group {
            if text.isEmpty {
                (Text(caret ? "▏" : "").foregroundColor(TourColor.hostCaret) + Text(script.placeholder).foregroundColor(Color(.placeholderText)))
            } else if let stream = model.fieldStream {
                TourStreamText(text: text, start: stream.start, perChar: stream.perChar, color: .primary)
            } else {
                (Text(String(text[..<split])).foregroundColor(.primary)
                 + Text(caret || model.trackpad ? "▏" : "").foregroundColor(TourColor.hostCaret)
                 + Text(String(text[split...])).foregroundColor(.primary))
            }
        }
        .font(.system(size: 17))
        .lineSpacing(2)
        .opacity(model.fieldDim ? 0.35 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: 66, alignment: .bottom)
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator), lineWidth: 1))
    }
}

/// 一条消息：我方紫底白字靠右，对方灰底靠左；「正在输入」是三个点。
/// 对方最新那条：帮回第 1 步长按它出编辑菜单（拷贝 / 翻译 / 更多），拷贝后旁边「已拷贝」。
private struct TourBubble: View {
    @ObservedObject var model: TourModel
    let message: TourModel.Message
    let isLast: Bool

    var body: some View {
        if message.mine {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.system(size: 15)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TourUI.accent))
            }
        } else if message.typing {
            HStack {
                TourTypingDots()
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TourColor.bubble))
                Spacer()
            }
        } else {
            HStack(spacing: 8) {
                peerBubble
                if message.copied {
                    Text(L("已拷贝", "Copied", "コピー済み"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(Color(.darkGray)))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer(minLength: 32)
            }
        }
    }

    /// 编辑菜单高 40，和气泡隔 8。
    private static let menuSpace: CGFloat = 48

    private var peerBubble: some View {
        let selecting = isLast && model.bubbleMenu
        let holdable = isLast && model.target == .peerBubble
        let pressedDemo = holdable && model.demoDown && model.pressed == nil
        // 长按只认气泡本身。菜单不能放进长按那一层里：长按层的 contentShape 只有气泡那么大，
        // 菜单在气泡外面，点上去收不到（0.97_13 真机「拷贝」点不动、按下也不变暗）。
        // 菜单出来时气泡上方让出一格放菜单（OG3 ④），不盖住上面那条。
        return Text(message.text)
            .font(.system(size: 15)).foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TourColor.bubble))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(TourUI.accent, lineWidth: selecting ? 2 : 0))
            .scaleEffect(model.pressed == .peerBubble && isLast ? 0.97 : pressedDemo ? 0.985 : 1)
            .modifier(TourHoldable(enabled: isLast, target: .peerBubble, model: model))
            .padding(.top, selecting ? Self.menuSpace : 0)
            .overlay(alignment: .topLeading) {
                if selecting {
                    TourEditMenu(model: model)
                        .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
    }
}

/// 系统样子的编辑菜单：拷贝 | 翻译 | 更多 ›，只有「拷贝」能点。
private struct TourEditMenu: View {
    @ObservedObject var model: TourModel

    var body: some View {
        HStack(spacing: 0) {
            // 按下时整格变灰，同系统菜单；只靠 tourPress 的缩放和变暗，黑字上几乎看不出来。
            Text(L("拷贝", "Copy", "コピー")).padding(.horizontal, 14).frame(height: 40)
                .background(model.pressed == .copy ? Color(.systemFill) : .clear)
                .tourPress(.copy, model: model)
            Divider().frame(height: 40)
            Text(L("翻译", "Translate", "翻訳")).padding(.horizontal, 14).frame(height: 40)
                .onTapGesture { model.wrong() }
            Divider().frame(height: 40)
            Text(L("更多 ›", "More ›", "その他 ›")).padding(.horizontal, 14).frame(height: 40)
                .onTapGesture { model.wrong() }
        }
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .fixedSize()
    }
}

/// 长按（0.45 秒）：对方气泡、回答卡。按下时轻轻缩一点，按对了才算。
struct TourHoldable: ViewModifier {
    let enabled: Bool
    let target: TourTarget
    @ObservedObject var model: TourModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.45, pressing: { down in
                    if down { model.pressBegan(target) } else if model.pressed == target {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { model.pressed = nil }
                    }
                }, perform: {
                    if model.target == target { TourModel.haptic(); model.tap(target) } else { model.wrong() }
                })
                .tourTarget(target)
        } else {
            content
        }
    }
}

/// 对方「正在输入」：三个灰点依次起伏。
private struct TourTypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = reduceMotion ? 0 : max(0, sin((t * 2 * .pi / 1.1) - Double(i) * 0.7))
                    Circle().fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.45 + 0.45 * wave)
                        .offset(y: -2.5 * wave)
                }
            }
        }
        .accessibilityLabel(L("正在输入", "Typing", "入力中"))
    }
}

/// AI 结果逐字浮现：每个字从透明到不透明 0.3 秒，一个比一个晚 perChar 秒（iOS 16：Text 拼接，每个字一个透明度）。
struct TourStreamText: View {
    let text: String
    let start: Date
    let perChar: Double
    var color: Color = .primary

    var body: some View {
        TimelineView(.animation) { context in
            compose(context.date.timeIntervalSince(start))
        }
    }

    private func compose(_ elapsed: Double) -> Text {
        var result = Text("")
        for (index, character) in text.enumerated() {
            let alpha = min(max((elapsed - Double(index) * perChar) / 0.3, 0), 1)
            result = result + Text(String(character)).foregroundColor(color.opacity(alpha))
        }
        return result
    }
}

// MARK: - 触点（取代小手）

/// 白色半透明圆点 38pt：进场从下方 26 缩放 0.7 → 1；换一处走一段微弧线；示范按下缩到 0.78，松开弹回并有一圈紫色细环扩散。
/// 该点的地方先出一圈紫色淡圆，扩大 1.9 倍淡出，1 秒一次。减弱动态效果：不走弧线、不出光晕，直接淡出淡入到下一处。
private struct TourTouchLayer: View {
    @ObservedObject var model: TourModel
    let anchors: [TourTarget: Anchor<CGRect>]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var from: CGPoint?
    @State private var to: CGPoint?
    @State private var progress: CGFloat = 1
    @State private var entered = false
    @State private var rippleAt: Date?

    private static let size: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            let rect = model.target.flatMap { anchors[$0] }.map { proxy[$0] }
            let hidden = rect == nil || model.popup != nil || model.trackpad
            let center = rect.map { CGPoint(x: $0.midX, y: $0.midY) }
            ZStack {
                if let rect, !hidden, !reduceMotion, !model.demoDown, model.pressed == nil {
                    TourHalo().position(x: rect.midX, y: rect.midY)
                }
                if let to {
                    // 缩放、位移先作用在圆点自己身上，再放到弧线上的位置（放过位置后整层是全屏大小，缩放会跑偏）。
                    touch
                        .scaleEffect(entered || reduceMotion ? 1 : 0.7)
                        .offset(x: slideOffset(rect), y: entered || reduceMotion ? 0 : 26)
                        .opacity(hidden ? 0 : (model.pressed != nil ? 0.3 : 1))
                        .animation(.easeOut(duration: 0.2), value: hidden)
                        .modifier(TourArcPlace(from: from ?? to, to: to, progress: progress))
                }
            }
            .modifier(ShakeEffect(animatableData: CGFloat(model.shakes)))
            .onAppear { move(to: center) }
            .onChange(of: center) { move(to: $0) }
        }
        .onChange(of: model.demoDown) { down in
            if !down, !reduceMotion { rippleAt = Date() }
        }
    }

    private var touch: some View {
        ZStack {
            if let rippleAt {
                TimelineView(.animation) { context in
                    let p = min(context.date.timeIntervalSince(rippleAt) / 0.5, 1)
                    Circle().strokeBorder(TourUI.accentText, lineWidth: 1.5)
                        .frame(width: Self.size, height: Self.size)
                        .scaleEffect(1 + 0.9 * p)
                        .opacity(0.8 * (1 - p))
                }
            }
            Circle()
                .fill(Color.white.opacity(0.55))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                .frame(width: Self.size, height: Self.size)
                .scaleEffect(model.demoDown ? 0.78 : 1)
                .animation(model.demoDown ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.6), value: model.demoDown)
        }
    }

    /// 按住再滑的示范：「，。」、e 往右滑一格，空格往左滑一段。
    private func slideOffset(_ rect: CGRect?) -> CGFloat {
        guard let target = model.target, target.gesture == .slide, let rect else { return 0 }
        switch target {
        case .space: return -60 * model.demoSlide
        default: return (model.layout == .nineKey ? -rect.width * 0.6 : rect.width) * model.demoSlide
        }
    }

    private func move(to point: CGPoint?) {
        guard let point else { return }
        if to == nil || reduceMotion {
            // 第一次出来：从下方 26pt、0.7 倍弹进来。
            from = nil
            to = point
            progress = 1
            if !entered { withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : TourUI.ease(0.42)) { entered = true } }
            return
        }
        guard point != to else { return }
        from = to
        to = point
        progress = 0
        withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 0.62)) { progress = 1 }
    }
}

/// 沿一段微弧线从 from 走到 to（二次贝塞尔，控制点在中点往上抬距离的 15%）。
private struct TourArcPlace: ViewModifier, Animatable {
    var from: CGPoint
    var to: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let distance = hypot(to.x - from.x, to.y - from.y)
        let control = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - distance * 0.15)
        let t = progress, u = 1 - progress
        let point = CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                            y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
        return content.position(point)
    }
}

/// 该点的地方：一圈紫色淡圆扩大 1.9 倍淡出，1 秒一次。
private struct TourHalo: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation) { context in
            let p = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle()
                .fill(scheme == .dark ? Color(hex: 0xB4A9FF).opacity(0.24) : Color(hex: 0x5B4BE8).opacity(0.22))
                .frame(width: 38, height: 38)
                .scaleEffect(1 + 0.9 * p)
                .opacity(1 - p)
        }
    }
}

/// 点错了：左右 6pt 三个来回。
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 6), y: 0))
    }
}

// MARK: - OG2 ② 演示完成

private struct TourFinishedPage: View {
    let onSetup: () -> Void
    let onLater: () -> Void
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var checkDrawn = false
    @State private var rowsChecked = 0

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 640
            let setUp = WelcomeSetup.Progress(store: store).allDone(privacyAgreed: router.privacyAgreed)
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(TourUI.green)
                        TourCheckShape()
                            .trim(from: 0, to: checkDrawn ? 1 : 0)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .padding(compact ? 18 : 21)
                    }
                    .frame(width: compact ? 56 : 64, height: compact ? 56 : 64)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.4)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.62), value: shown)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.36), value: checkDrawn)
                    Text(L("演示完成", "Tour Complete", "デモ完了"))
                        .font(.system(size: 22, weight: .bold))
                        .tourEntrance(1, shown)
                    Text(setUp
                         ? L("设置都已完成，在任何 App 中切换到飞地输入法即可使用。", "Setup is complete. Switch to Enclave in any app to use it.", "設定は完了しています。どの App でも Enclave に切り替えて使えます。")
                         : L("还差三步：添加输入法、开启完全访问、连接 AI。打字现在就能用。",
                             "Three steps to go: add the keyboard, turn on Full Access and connect AI. Typing works right now.",
                             "あと 3 ステップ：キーボードの追加、フルアクセスのオン、AI の接続。入力はすぐに使えます。"))
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .tourEntrance(2, shown)
                }
                .padding(.top, compact ? 16 : 32)
                VStack(alignment: .leading, spacing: 6) {
                    TourGroupNote(text: L("已看完", "Completed", "見終わった章"))
                    TourGroup {
                        ForEach(TourChapter.allCases) { chapter in
                            let checked = chapter.rawValue < rowsChecked
                            if chapter != .polish { TourRowDivider() }
                            TourChapterRow(chapter: chapter, compact: compact) {
                                TourCheckShape()
                                    .trim(from: 0, to: checked ? 1 : 0)
                                    .stroke(TourUI.green, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                    .frame(width: 14, height: 11)
                                    .scaleEffect(checked ? 1 : 0.8)
                                    .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.45), value: checked)
                            }
                            .opacity(chapter.rawValue < rowsChecked || reduceMotion && shown ? 1 : 0)
                            .offset(y: chapter.rawValue < rowsChecked || reduceMotion ? 0 : 12)
                            .animation(reduceMotion ? .easeInOut(duration: 0.2) : TourUI.ease(0.45), value: rowsChecked)
                        }
                    }
                    TourGroupNote(text: L("想重温某一章，可前往 设置 › 功能演示。", "To revisit a chapter, go to Settings › Feature Tour.", "章を見直すには、設定 › 機能デモ へ。"))
                }
                .padding(.top, compact ? 16 : 28)
                .tourEntrance(3, shown)
                Spacer(minLength: 8)
                TourButtons(primary: L("开始设置", "Start Setup", "設定をはじめる"), action: onSetup,
                            secondary: L("稍后", "Later", "あとで"), secondaryAction: onLater)
                    .tourEntrance(4, shown)
            }
            .frame(maxWidth: PadWidth.content)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onAppear {
            DispatchQueue.main.async { shown = true }
            Task { @MainActor in
                if reduceMotion {
                    checkDrawn = true
                    rowsChecked = TourChapter.allCases.count
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                checkDrawn = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                for count in 1...TourChapter.allCases.count {
                    rowsChecked = count
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
                try? await Task.sleep(nanoseconds: 260_000_000)
                TourModel.haptic()
            }
        }
    }
}

/// 勾：一笔画出（trim 动画）。
struct TourCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

// MARK: - OG2 ③ 设置 › 功能演示

/// 和首次打开同样 6 章：点一章只看这一章，看完回到这页；「从头播放」放全部 16 步。这里不改设置，键盘只显示。
struct TourChaptersView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L("键盘", "Keyboard", "キーボード"))
                    Spacer()
                    Text(store.settings.keyboardLayout.shortTitle).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("演示键盘", "Tour keyboard", "デモのキーボード"))
            } footer: {
                Text(L("与 键盘 › 中文布局 一致。", "Matches Keyboard › Chinese layout.", "キーボード › 中国語の配列 と同じです。"))
            }
            Section {
                ForEach(TourChapter.allCases) { chapter in
                    Button { router.setupGuide = .tourReplay(chapter) } label: {
                        HStack(spacing: 12) {
                            TourChapterIcon(chapter: chapter, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(chapter.name).foregroundStyle(.primary)
                                Text(chapter.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(stepsLabel(chapter.stepCount)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(L("6 个章节 · 约 3 分钟", "6 chapters · About 3 min", "6 章 · 約 3 分"))
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            GuidePrimaryButton(L("从头播放", "Play from the Start", "最初から再生")) { router.setupGuide = .tourReplay(nil) }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: PadWidth.content)
                .frame(maxWidth: .infinity)
                .background(TourUI.page)
        }
        .navigationTitle(L("功能演示", "Feature Tour", "機能デモ"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
