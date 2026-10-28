import SwiftUI

// 首次打开的功能演示（FT0–FT11）：隐私同意之后、配置接口（OB1）之前，用 App 里画的模拟键盘把润色、识意、切换、替换、
// 拖动放大镜、联网查询、分词插入各点一遍。结果全是预设内容：不调用 API、不联网、不扣次数、不计入统计。
// 每步只有小手指着的那颗能点，点别处小手原地晃一下；点对了模拟 0.8 秒「处理中」再出结果。

enum FeatureTour {
    private static let seenKey = "featureTour.seen"

    /// 走完或跳过都记下，以后不再自动弹（存在 App Group）。
    static var seen: Bool {
        get { SharedStorage.defaults.bool(forKey: seenKey) }
        set { SharedStorage.defaults.set(newValue, forKey: seenKey) }
    }
}

// MARK: - 预设内容

private enum TourText {
    static let original = "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看"
    static let polished = "文件我看过了，整体没问题。第三页有个数字好像不太对，麻烦再核对一下。"
    static let critique = "主要有三处：整段没有标点，阅读吃力；「大概没啥问题」偏口语，不够严谨；「你再看看」语气略生硬，可改为「麻烦再核对一下」。"
    static let english = "Checked the file, looks fine overall. One number on page 3 seems off. Could you double-check?"
    static let trainAnswer = "最快 45 分钟左右，坐不停站的 G 字头直达车；具体车次和时间以 12306 为准。"
    static let trainWeb = "最快 45 分钟，G 字头直达车次一天十几趟，早上 7 点前就有。二等座七十多元。来源：12306"
    static let message1 = "文件看过了吗？第三页的数据我不太确定。"
    static let message2 = "另外，周六去杭州，高铁需要多久？"
    static let askProblem = "这段话有什么问题"
    static let askEnglish = "翻成英文"
    static let askTrain = "上海到杭州高铁最快多久"
    /// FT10 分词面板里的词，前三个预先选好。
    static let words = ["最快", "45", "分钟", "，", "G 字头", "直达", "车次", "一天", "十几趟", "，", "早上", "7 点", "前", "就有", "。",
                        "二等座", "七十多元", "。", "来源", "：", "12306"]
    static let inserted = "最快45分钟"
}

/// 小手能指的地方。
private enum TourTarget: Hashable {
    case sparkle, undo, drawer, magnifier, switchMode, replace, search, card, insert
}

/// 每一步开始时的样子；返回上一步就回到那一步开始时。
private struct TourState: Equatable {
    var messages: [String] = [TourText.message1]
    var field = TourText.original
    var expanded = false
    var card: String?
    var cardAnswer = false
    var ask = ""
    var canSearch = false
    var searched = false
    var panel = false

    static func start(_ step: Int) -> TourState {
        var s = TourState()
        switch step {
        case ...1: break
        case 2: s.field = TourText.polished
        case 3: break
        case 4: s.expanded = true; s.ask = TourText.askProblem
        case 5: s.expanded = true; s.ask = TourText.askProblem; s.card = TourText.critique; s.cardAnswer = true
        case 6: s.expanded = true; s.ask = TourText.askProblem; s.card = TourText.polished
        case 7: s.expanded = true; s.field = TourText.polished; s.ask = TourText.askEnglish
        case 8:
            s.expanded = true; s.messages = [TourText.message1, TourText.message2]; s.field = TourText.polished
            s.ask = TourText.askTrain; s.card = TourText.english
        case 9:
            s.expanded = true; s.messages = [TourText.message1, TourText.message2]; s.field = ""
            s.ask = TourText.askTrain; s.card = TourText.trainAnswer; s.cardAnswer = true; s.canSearch = true
        default:
            s.expanded = true; s.messages = [TourText.message2]; s.field = ""
            s.ask = TourText.askTrain; s.card = TourText.trainWeb; s.cardAnswer = true; s.searched = true
        }
        return s
    }
}

/// 一步的章节、标题、说明、小手指着哪颗。
private struct TourStep {
    enum Chapter { case polish, ask, words }
    var chapter: Chapter
    var index: Int
    var total: Int
    var title: String
    var detail: String
    var target: TourTarget
    /// 点了以后要不要先「处理中」0.8 秒。
    var processes: Bool

    static let all: [TourStep] = [
        TourStep(chapter: .polish, index: 1, total: 2, title: "点击 ✨，润色输入内容",
                 detail: "AI 将修正语病和标点，并直接替换输入框中的文字。", target: .sparkle, processes: true),
        TourStep(chapter: .polish, index: 2, total: 2, title: "润色完成，可随时撤销",
                 detail: "点击 ↶ 恢复原文；点击 ↷ 重新应用润色结果。", target: .undo, processes: false),
        TourStep(chapter: .ask, index: 1, total: 7, title: "点击此处，展开回答卡",
                 detail: "展开后，可在识意框中输入修改要求或问题。", target: .drawer, processes: false),
        TourStep(chapter: .ask, index: 2, total: 7, title: "输入内容，点击放大镜",
                 detail: "识意框中已预填一句话。点击放大镜后，将自动判断是修改文字还是回答问题。", target: .magnifier, processes: true),
        TourStep(chapter: .ask, index: 3, total: 7, title: "处理方式不符时，点击「切换」",
                 detail: "回答卡左侧标示本次的处理方式。本次按问答处理；如需直接修改原文，点击「切换」改为改写。", target: .switchMode, processes: true),
        TourStep(chapter: .ask, index: 4, total: 7, title: "点击「替换」，应用结果",
                 detail: "改写结果显示在回答卡中。点击「替换」写入输入框；按住上滑可改为「插入」，保留原文。", target: .replace, processes: false),
        TourStep(chapter: .ask, index: 5, total: 7, title: "按住放大镜，上下拖动",
                 detail: "可预先指定处理方式：上滑为改写，下滑为问答，松手即执行。请按住放大镜向上拖动。", target: .magnifier, processes: true),
        TourStep(chapter: .ask, index: 6, total: 7, title: "输入问题，点击放大镜",
                 detail: "放大镜会自动判断：修改文字，或回答问题。", target: .magnifier, processes: true),
        TourStep(chapter: .ask, index: 7, total: 7, title: "需要实时信息时，联网查询",
                 detail: "默认回答基于模型已有知识。点击「使用联网查询」获取最新信息（通义千问、Kimi、智谱 GLM 支持）。", target: .search, processes: true),
        TourStep(chapter: .words, index: 1, total: 1, title: "长按结果卡，选词插入",
                 detail: "只需部分内容时，长按结果卡，选中词语后点击「插入」。", target: .card, processes: false),
    ]
}

// MARK: - 颜色

private enum TourColor {
    static let keyboard = Color(light: 0xD9DAE0, dark: 0x2B2B2D)
    static let key = Color(light: 0xFFFFFF, dark: 0x5A5A5E)
    static let returnFill = Color(light: 0xE8E5FB, dark: 0x3A3550)
    static let purple = Color(hex: 0x5B4BE8)
    static let ring = Color(hex: 0x8B7CF6)
    static let answerRing = Color(hex: 0x38BDF8)
    static let bubble = Color(light: 0xF2F1F7, dark: 0x2C2C2E)
    static let field = Color(light: 0xF6F5FA, dark: 0x2C2C2E)
    static let fieldStroke = Color(light: 0xE6E3F0, dark: 0x3A3A3C)
    static let hostCaret = Color(hex: 0x34C759)
    static let progressOn = Color(light: 0x5B4BE8, dark: 0xB4A9FF)
    static let progressOff = Color(light: 0xDDD9EE, dark: 0x35304D)
    static let cardFill = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let hair = Color(light: 0xE5E5EA, dark: 0x3A3A3C)
    static let askLine = Color(light: 0xC9C0FF, dark: 0x5A4FA0)
    static let caret = Color(light: 0x5B4BE8, dark: 0xB4A9FF)
}

// MARK: - 整个演示

struct FeatureTourView: View {
    enum Exit {
        /// 「开始演示」前跳过、任意一步「跳过」。
        case skip
        /// 完成页「配置 API」。
        case setup
        /// 完成页「暂不配置，仅使用打字」。
        case later
    }

    var onExit: (Exit) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 欢迎，1–10 演示，11 完成。
    @State private var step = 0
    @State private var state = TourState.start(1)
    @State private var processing = false
    /// 只有这一颗能点；FT10 先指结果卡，面板开了再指「插入」。
    @State private var target: TourTarget = .sparkle
    /// 点错了：小手原地晃一下。
    @State private var shakes = 0
    /// FT7 手指按住放大镜往上拖到了「改写」。
    @State private var dragPick = false
    @State private var dragging = false

    var body: some View {
        ZStack {
            GuideBackground(glow: true)
            switch step {
            case 0: welcome
            case 11: finished
            default: stepPage
            }
        }
        .interactiveDismissDisabled()
        .onDisappear { FeatureTour.seen = true }
    }

    // MARK: FT0 欢迎

    private var welcome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("跳过") { exit(.skip) }
                    .font(.system(size: 15)).foregroundStyle(GuideColor.secondary)
            }
            .padding(.horizontal, 24).frame(height: 50).padding(.top, 8)
            GuidePage {
                VStack(alignment: .leading, spacing: 22) {
                    GuideAppMark(size: 64, corner: 18).padding(.top, 20)
                    GuideTitle("功能演示", subtitle: "配置 API 之前，可以先通过模拟键盘了解各项 AI 功能，约需 1 分钟。演示结果均为预设内容，不调用 API，也不联网。")
                    GuideCard {
                        overviewRow(1, "一键润色", "点击 ✨ 润色输入内容，可随时撤销", "2 步", .polish)
                        GuideDivider()
                        overviewRow(2, "识意：改写与问答", "展开回答卡，点击或拖动放大镜执行，结果可切换", "7 步", .ask)
                        GuideDivider()
                        overviewRow(3, "分词插入", "长按结果卡，选取部分词语插入输入框", "1 步", .words)
                    }
                }
            } bottom: {
                GuidePrimaryButton("开始演示") { go(1) }
                GuideSecondaryButton("跳过，前往设置") { exit(.skip) }
            }
        }
    }

    private func overviewRow(_ number: Int, _ title: String, _ detail: String, _ steps: String, _ chapter: TourStep.Chapter) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Self.chapterText(chapter))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.chapterFill(chapter)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GuideColor.text)
                Text(detail).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(steps).font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary)
        }
        .padding(16)
    }

    // MARK: FT11 完成

    private var finished: some View {
        GuidePage {
            VStack(alignment: .leading, spacing: 22) {
                GuideAppMark(size: 64, corner: 18).padding(.top, 70)
                GuideTitle("演示完成", subtitle: "以上结果均为预设演示。配置 API 后，即可在任意 App 中使用这些功能。")
                GuideCard {
                    summaryRow("一键润色", "收起状态下点击 ✨，可撤销")
                    GuideDivider()
                    summaryRow("识意", "点击放大镜自动判断；按住上滑改写、下滑问答")
                    GuideDivider()
                    summaryRow("切换、替换与联网查询", "结果先显示在回答卡中，确认后再写入")
                    GuideDivider()
                    summaryRow("分词插入", "长按结果卡，选取部分词语")
                }
            }
        } bottom: {
            GuidePrimaryButton("配置 API") { exit(.setup) }
            GuideSecondaryButton("暂不配置，仅使用打字") { exit(.later) }
        }
    }

    private func summaryRow(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x30A46C))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(hex: 0x30A46C).opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(GuideColor.text)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: FT1–FT10

    private var current: TourStep { TourStep.all[min(max(step, 1), 10) - 1] }

    private var stepPage: some View {
        VStack(spacing: 0) {
            topBar
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)
            chat
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Spacer(minLength: 8)
            TourKeyboard(state: state, step: step, processing: processing, target: target,
                         dragPick: dragPick, reduceMotion: reduceMotion,
                         tap: tap, wrong: wrong, longPress: { tap(.card) }, drag: drag)
        }
        .overlayPreferenceValue(TourFramesKey.self) { anchors in
            GeometryReader { proxy in
                // FT7 手指自己按着拖的时候不再示范。
                if !processing, !(step == 7 && dragging), let anchor = anchors[target] {
                    TourHand(rect: proxy[anchor], bounds: proxy.size, dragDemo: step == 7, holdDemo: target == .card,
                             reduceMotion: reduceMotion, shakes: shakes)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: target)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { go(step - 1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GuideColor.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GuideColor.card))
            }
            .accessibilityLabel("返回")
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2).fill(index <= step ? TourColor.progressOn : TourColor.progressOff).frame(height: 4)
                }
            }
            Button("跳过") { exit(.skip) }
                .font(.system(size: 15)).foregroundStyle(GuideColor.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .frame(height: 50)
        .padding(.top, 8)
    }

    private var header: some View {
        let info = current
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(Self.chapterName(info.chapter))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Self.chapterText(info.chapter))
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(Self.chapterFill(info.chapter)))
                Text("\(info.index) / \(info.total)").font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                Spacer()
                Text("演示 · 不调用 API")
                    .font(.system(size: 11.5)).foregroundStyle(GuideColor.secondary)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(GuideColor.card))
                    .overlay(Capsule().stroke(GuideColor.divider, lineWidth: 1))
            }
            Text(info.title)
                .font(.system(size: 24, weight: .bold)).foregroundStyle(GuideColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(info.detail)
                .font(.system(size: 15)).lineSpacing(4).foregroundStyle(GuideColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 对话卡：小林的消息 + 宿主输入框（绿色光标）。
    private var chat: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("林").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xFDBA74), Color(hex: 0xF97316)], startPoint: .top, endPoint: .bottom)))
                Text("小林").font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                Spacer()
                Text("演示内容 · 不会发送")
                    .font(.system(size: 10.5)).foregroundStyle(GuideColor.secondary)
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(TourColor.bubble))
            }
            ForEach(Array(state.messages.enumerated()), id: \.offset) { _, message in
                Text(message)
                    .font(.system(size: 14.5)).foregroundStyle(GuideColor.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(UnevenRoundedRect(radius: 16, bottomLeft: 5).fill(TourColor.bubble))
            }
            Group {
                if state.field.isEmpty {
                    Text("回复 小林").foregroundStyle(GuideColor.secondary.opacity(0.7))
                } else {
                    // 识意框激活时宿主没有光标。
                    (Text(state.field) + Text(hostCaretVisible ? "▏" : "").foregroundColor(TourColor.hostCaret))
                        .foregroundStyle(GuideColor.text)
                }
            }
            .font(.system(size: 15.5))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.field))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TourColor.fieldStroke, lineWidth: 1))
            .animation(.easeOut(duration: 0.2), value: state.field)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GuideColor.card)
            .shadow(color: Color(hex: 0x3C28A0).opacity(0.07), radius: 14, y: 10))
    }

    private var hostCaretVisible: Bool { !state.expanded }

    // MARK: 点按

    private func tap(_ hit: TourTarget) {
        guard !processing, (1...10).contains(step) else { return }
        guard hit == target else { return wrong() }
        let info = current
        if step == 10 {
            if hit == .card {
                withAnimation(.easeOut(duration: 0.2)) { state.panel = true }
                target = .insert
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    state.panel = false
                    state.field = TourText.inserted
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { go(11) }
            }
            return
        }
        if step == 7 && !dragPick { return wrong() }
        if info.processes {
            processing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                processing = false
                finish(step)
            }
        } else {
            finish(step)
        }
    }

    /// 这一步点对了：结果换成下一步开始时的样子，小手飞到下一颗。
    private func finish(_ done: Int) {
        guard done == step else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            state = TourState.start(done + 1)
            step = done + 1
        }
        dragPick = false
        if step <= 10 { target = TourStep.all[step - 1].target }
        if step == 11 { FeatureTour.seen = true }
    }

    private func wrong() {
        if reduceMotion { return }
        withAnimation(.linear(duration: 0.3)) { shakes += 1 }
    }

    /// FT7：按住放大镜往上拖。只认上滑后松手。
    private func drag(_ translation: CGFloat?, ended: Bool) {
        guard step == 7, !processing else { return }
        if ended {
            dragging = false
            if dragPick { tap(.magnifier) } else { wrong() }
            return
        }
        dragging = true
        dragPick = (translation ?? 0) < -16
    }

    private func go(_ next: Int) {
        guard next >= 0 else { return }
        processing = false
        dragPick = false
        withAnimation(.easeInOut(duration: 0.22)) {
            step = next
            if (1...10).contains(next) { state = TourState.start(next) }
        }
        if (1...10).contains(next) { target = TourStep.all[next - 1].target }
    }

    private func exit(_ how: Exit) {
        FeatureTour.seen = true
        onExit(how)
    }

    // MARK: 章节胶囊

    private static func chapterName(_ chapter: TourStep.Chapter) -> String {
        switch chapter {
        case .polish: return "润色"
        case .ask: return "识意"
        case .words: return "分词"
        }
    }

    fileprivate static func chapterText(_ chapter: TourStep.Chapter) -> Color {
        switch chapter {
        case .polish: return Color(light: 0x5B4BE8, dark: 0xB4A9FF)
        case .ask: return Color(light: 0x0369A1, dark: 0x7DD3FC)
        case .words: return Color(light: 0x047857, dark: 0x6EE7B7)
        }
    }

    fileprivate static func chapterFill(_ chapter: TourStep.Chapter) -> Color {
        switch chapter {
        case .polish: return Color(light: 0xECEAFD, dark: 0x2E2766)
        case .ask: return Color(light: 0xE0F2FE, dark: 0x0C3448)
        case .words: return Color(light: 0xD1FAE5, dark: 0x063B2C)
        }
    }
}

/// 对方消息气泡：左下角小圆角（16/16/16/5）。
private struct UnevenRoundedRect: Shape {
    var radius: CGFloat
    var bottomLeft: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.height / 2), b = min(bottomLeft, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - b), radius: b)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

// MARK: - 小手

private struct TourFramesKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func tourTarget(_ target: TourTarget) -> some View {
        // 合并而不是覆盖：「⇄ 切换」在回答卡里面，外层回答卡的标记不能把它盖掉。
        transformAnchorPreference(key: TourFramesKey.self, value: .bounds) { $0[target] = $1 }
    }
}

/// 晃一下：左右 6pt 三个来回。
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// 和键盘「一键应用」的小手指一样：1.4 秒点一下，每次落下扩出一圈水波；在右半边时整只手翻过来。
/// FT7 示范按住放大镜往上拖到「改写」。减弱动态效果时静止。
private struct TourHand: View {
    var rect: CGRect
    var bounds: CGSize
    var dragDemo: Bool
    /// FT10 长按结果卡：手指按住，指尖下一圈进度环 0.5 秒转满。
    var holdDemo = false
    var reduceMotion: Bool
    var shakes: Int

    private static let period = 1.4
    private static let rippleColor = Color(hex: 0x8B7CF6)

    var body: some View {
        Group {
            if reduceMotion {
                hand(tip: CGPoint(x: rect.midX, y: rect.midY + 4), ripple: nil)
            } else {
                TimelineView(.animation) { context in
                    if dragDemo {
                        let d = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.dragPeriod) / Self.dragPeriod)
                        dragFrame(d)
                    } else if holdDemo {
                        let h = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.holdPeriod) / Self.holdPeriod)
                        holdFrame(h)
                    } else {
                        let t = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period)
                        let offset: CGFloat = 4 - 7 * (1 - cos(2 * .pi * t)) / 2
                        hand(tip: CGPoint(x: rect.midX, y: rect.midY + offset), ripple: t)
                    }
                }
            }
        }
        .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
    }

    private var flipped: Bool { rect.midX > bounds.width / 2 }

    /// FT10 一轮 2 秒，和宣传视频一样：按下 0.2 秒 → 指尖一圈天蓝进度环 0.5 秒转满（圈里的底色跟着变深）→
    /// 闭合时环往外撑大、0.35 秒淡掉 → 手停一下再淡出。
    private static let holdPeriod = 2.0
    private static let holdRing = Color(hex: 0x0EA5E9)
    private static let holdTrack = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)

    private func holdFrame(_ h: CGFloat) -> some View {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let press = min(h / 0.1, 1)
        let fill = min(max((h - 0.1) / 0.25, 0), 1)
        let pop = min(max((h - 0.35) / 0.175, 0), 1)
        let radius: CGFloat = 24 + 10 * pop
        let fade: Double = h < 0.75 ? 1 : max(0, Double(1 - (h - 0.75) / 0.15))
        return ZStack {
            if h >= 0.1 && pop < 1 {
                ZStack {
                    Circle().fill(Self.holdTrack.opacity(0.12 + 0.2 * Double(fill)))
                    Circle().stroke(Self.holdTrack.opacity(0.25), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: fill)
                        .stroke(Self.holdRing, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: radius * 2, height: radius * 2)
                .opacity(Double(1 - pop))
                .position(center)
            }
            hand(tip: CGPoint(x: center.x, y: center.y + 4 - 3 * press), ripple: nil)
        }
        .opacity(fade)
    }

    /// FT7 一轮 2.6 秒：按下（灰圈缩进去）→ 按住不动 → 沿紫色虚线往上拖到「改写」→ 停一下 → 淡出。
    private static let dragPeriod = 2.6
    /// 放大镜中心到「改写」中心。
    private static let dragDistance: CGFloat = 42

    @ViewBuilder
    private func dragFrame(_ d: CGFloat) -> some View {
        let start = CGPoint(x: rect.midX, y: rect.midY)
        // 0–0.12 按下，0.12–0.3 按住，0.3–0.65 上拖，0.65–0.85 停在「改写」，0.85–1 淡出。
        let move: CGFloat = d < 0.3 ? 0 : d < 0.65 ? (d - 0.3) / 0.35 : 1
        let eased = move * move * (3 - 2 * move)
        let point = CGPoint(x: start.x, y: start.y - Self.dragDistance * eased)
        let press: CGFloat = min(d / 0.12, 1)
        let fade: Double = d < 0.85 ? 1 : Double(1 - (d - 0.85) / 0.15)
        let holding = d >= 0.12 && d < 0.3
        ZStack {
            // 走过的路：一道渐亮的紫线，头上一个箭头。
            if move > 0 {
                Path { p in p.move(to: start); p.addLine(to: point) }
                    .stroke(Self.rippleColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .opacity(0.85)
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Self.rippleColor)
                    .position(x: point.x, y: point.y - 24)
                    .opacity(move < 1 ? 1 : 0)
            }
            // 手指按着的灰圈：按下时缩进去，按住时轻轻一跳。
            Circle()
                .fill(Color.white.opacity(0.35))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .frame(width: 34, height: 34)
                .scaleEffect(1.25 - 0.25 * press + (holding ? 0.06 * sin((d - 0.12) / 0.18 * .pi) : 0))
                .position(point)
            // 手从右边斜着伸过来，按下时也不压放大镜正下方的「问答」。
            let size = CoachHandShape.size, fingertip = CoachHandShape.fingertip
            CoachHandShape.hand(flipped: false, angle: -55)
                .position(x: point.x + 20 + size.width / 2 - fingertip.x, y: point.y + 2 + size.height / 2 - fingertip.y)
        }
        .opacity(fade)
    }

    private func hand(tip: CGPoint, ripple t: CGFloat?) -> some View {
        let size = CoachHandShape.size, fingertip = CoachHandShape.fingertip
        let dx = size.width / 2 - fingertip.x
        let center = CGPoint(x: tip.x + (flipped ? -dx : dx), y: tip.y + size.height / 2 - fingertip.y)
        return ZStack {
            if let t {
                let grow: CGFloat = 1 - (1 - t) * (1 - t)
                Circle()
                    .fill(Self.rippleColor.opacity(0.16))
                    .overlay(Circle().strokeBorder(Self.rippleColor, lineWidth: 2.5))
                    .frame(width: 12 + 44 * grow, height: 12 + 44 * grow)
                    .opacity(Double(1 - t))
                    .position(x: rect.midX, y: rect.midY)
            }
            CoachHandShape.hand(flipped: flipped).position(center)
        }
    }
}

// MARK: - 模拟键盘

/// App 里画的键盘：AI 栏、回答卡和识意框、九宫格按键；FT10 长按后按键区换成分词面板。只有小手指着的那颗能点。
private struct TourKeyboard: View {
    var state: TourState
    var step: Int
    var processing: Bool
    var target: TourTarget
    var dragPick: Bool
    var reduceMotion: Bool
    var tap: (TourTarget) -> Void
    var wrong: () -> Void
    var longPress: () -> Void
    var drag: (CGFloat?, Bool) -> Void

    private let side: CGFloat = 6

    var body: some View {
        VStack(spacing: 8) {
            if state.expanded {
                answerBlock
                    .padding(.horizontal, side + 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // FT7 放大镜下方弹出的「问答」要盖在按键上面。
            aiBar.padding(.horizontal, side + 2).zIndex(1)
            if state.panel {
                wordPanel.padding(.horizontal, side + 2)
            } else {
                keys.padding(.horizontal, side)
            }
            HStack {
                Image(systemName: "globe")
                Spacer()
                Image(systemName: "mic")
            }
            .font(.system(size: 22))
            .foregroundStyle(GuideColor.text)
            .padding(.horizontal, 24)
            .frame(height: 40)
            .padding(.bottom, 22)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(
            TourColor.keyboard
                .clipShape(TopRounded(radius: 26))
                .contentShape(Rectangle())
                .onTapGesture { wrong() })
        .animation(.easeOut(duration: 0.25), value: state.expanded)
    }

    // MARK: AI 栏

    private var aiBar: some View {
        HStack(spacing: 6) {
            Button { tap(.drawer) } label: {
                Image(systemName: "rectangle.tophalf.inset.filled")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(state.expanded ? TourColor.purple : GuideColor.text)
                    .frame(width: 44, height: 34)
                    .background(Capsule().fill(state.expanded ? Color(light: 0xEDEBFD, dark: 0x2E2766) : TourColor.key))
                    .overlay(Capsule().strokeBorder(TourColor.ring, lineWidth: state.expanded ? 1.5 : 0))
            }
            .tourTarget(.drawer)
            if state.expanded {
                magnifier
                styleKey(answer: false)
                styleKey(answer: true)
            } else {
                joined
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { tap(.undo) } label: {
                    Image(systemName: "arrow.uturn.backward").frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }
                .tourTarget(.undo)
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1).padding(.vertical, 9)
                Button { wrong() } label: {
                    Image(systemName: "arrow.uturn.forward").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(step == 2 ? GuideColor.text : GuideColor.secondary.opacity(0.6))
            .frame(width: 76, height: 34)
            .background(Capsule().fill(TourColor.key))
        }
        .buttonStyle(.plain)
    }

    /// 收着：✨ 和「润色 ▾」合成的一颗。
    private var joined: some View {
        HStack(spacing: 0) {
            Group {
                if processing && step == 1 {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    PolishStars(size: 20, running: false, glowing: false, doneAt: nil, tint: AIVisuals.gold)
                }
            }
            .frame(width: 20, height: 20)
            .padding(.trailing, 6)
            .tourTarget(.sparkle)
            Text("润色").font(.system(size: 13.5, weight: .semibold)).padding(.trailing, 4)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(NebulaFill(palette: .join).clipShape(Capsule()))
        .contentShape(Capsule())
        .onTapGesture(coordinateSpace: .local) { point in point.x < 46 ? tap(.sparkle) : wrong() }
    }

    /// 展开：蓝紫星团的放大镜。FT7 按住往上拖，正上方「改写」、正下方「问答」。
    private var magnifier: some View {
        HStack(spacing: 5) {
            if processing && target == .magnifier {
                ProgressView().tint(.white).scaleEffect(0.7)
            } else {
                AskIcon().frame(width: 18, height: 18)
                Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 58, height: 34)
        .background(NebulaFill(palette: .ask).clipShape(Capsule()))
        .overlay {
            if step == 7 && !processing {
                ZStack {
                    // 放大镜到「改写」之间一道紫色虚线。
                    Path { p in p.move(to: CGPoint(x: 29, y: 0)); p.addLine(to: CGPoint(x: 29, y: -24)) }
                        .stroke(TourColor.ring, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    dragOption("改写", colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], highlighted: true).offset(y: -42)
                    dragOption("问答", colors: [Color(hex: 0x0EA5E9), Color(hex: 0x38BDF8)], highlighted: false).offset(y: 42)
                }
                .frame(width: 58, height: 34)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        // FT7 按住拖；别的步骤手指没怎么动就当点了一下。
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { if step == 7 { drag($0.translation.height, false) } }
            .onEnded { value in
                if step == 7 { drag(nil, true) } else if abs(value.translation.height) < 12 { tap(.magnifier) }
            })
        .tourTarget(.magnifier)
    }

    private func dragOption(_ title: String, colors: [Color], highlighted: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle").font(.system(size: 10, weight: .bold))
            Text(title).font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(width: 58, height: 30)
        .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
        .overlay(Capsule().strokeBorder(Color.white, lineWidth: highlighted && (dragPick || reduceMotion) ? 2 : 0))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    /// 润色 ▾（紫色星团）、直击要害 ▾（蓝色星团）；回答卡上是哪种结果，那颗亮边框。
    private func styleKey(answer: Bool) -> some View {
        let active = state.card != nil && state.cardAnswer == answer
        return HStack(spacing: 4) {
            Image(systemName: answer ? "questionmark.circle" : "pencil").font(.system(size: 14, weight: .semibold))
            Text(answer ? "直击要害" : "润色").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.leading, 9).padding(.trailing, 8)
        .frame(height: 34)
        .background(NebulaFill(palette: answer ? .answer : .rewrite).clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(answer ? Color(hex: 0x7DD3FC) : Color(hex: 0xC4B5FD), lineWidth: active ? 1.5 : 0))
        .shadow(color: active ? (answer ? Color(hex: 0x0EA5E9) : Color(hex: 0x7C3AED)).opacity(0.5) : .clear, radius: 6)
        .fixedSize()
        .contentShape(Capsule())
        .onTapGesture { wrong() }
    }

    // MARK: 回答卡 + 识意框

    private var answerBlock: some View {
        HStack(spacing: 6) {
            Button { tap(.replace) } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .bold))
                    Text("替换").font(.system(size: 13, weight: .bold))
                    Rectangle().fill(Color.white.opacity(0.5)).frame(width: 22, height: 1)
                    Text("插入").font(.system(size: 10, weight: .semibold)).opacity(0.45)
                }
                .foregroundStyle(.white)
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], startPoint: .top, endPoint: .bottom)))
                .opacity(state.card == nil ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .tourTarget(.replace)
            VStack(spacing: 0) {
                cardTop
                    .frame(height: 62)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.5) { if target == .card { longPress() } else { wrong() } }
                    .tourTarget(.card)
                Rectangle().fill(TourColor.askLine).frame(height: 1)
                askRow.frame(height: 40)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(state.cardAnswer ? TourColor.answerRing : TourColor.ring, lineWidth: 1.5))
        }
        .frame(height: 103)
    }

    private var cardTop: some View {
        HStack(alignment: .top, spacing: 8) {
            if state.card != nil, !processing { modeBlock }
            Group {
                if processing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("正在处理…").foregroundStyle(TourColor.purple)
                    }
                } else if let card = state.card {
                    Text(card).foregroundStyle(GuideColor.text).lineLimit(2)
                } else {
                    Text("结果会出现在这里").foregroundStyle(GuideColor.secondary.opacity(0.7))
                }
            }
            .font(.system(size: 14.5))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if state.card != nil {
                VStack {
                    Image(systemName: "doc.on.doc")
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .font(.system(size: 12))
                .foregroundStyle(GuideColor.secondary)
            }
        }
        .padding(8)
    }

    /// 左边模式块：上半「AI问答 / AI改写」，下半「⇄ 切换」。
    private var modeBlock: some View {
        let text = state.cardAnswer ? Color(light: 0x0369A1, dark: 0x7DD3FC) : Color(light: 0x4A3BD6, dark: 0xB4A9FF)
        let fill = state.cardAnswer ? Color(light: 0xE0F2FE, dark: 0x0C3448) : Color(light: 0xECEAFD, dark: 0x2E2766)
        return VStack(spacing: 0) {
            Text(state.cardAnswer ? "AI问答" : "AI改写").font(.system(size: 10, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(text.opacity(0.25)).frame(height: 0.5)
            Button { tap(.switchMode) } label: {
                Text("⇄切换").font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tourTarget(.switchMode)
        }
        .foregroundStyle(text)
        .frame(width: 38, height: 46)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(text.opacity(0.3), lineWidth: 0.5))
    }

    /// 识意框（激活：紫色光标）；FT9 右边「使用联网查询」，联网后灰字「已联网 · Kimi」。
    private var askRow: some View {
        HStack(spacing: 8) {
            (Text(state.ask) + Text("▏").foregroundColor(TourColor.caret))
                .font(.system(size: 15))
                .foregroundStyle(GuideColor.text)
                .lineLimit(1)
                .truncationMode(.head)
                // FT5 小手指着「切换」、FT7 放大镜正上方冒出「改写」气泡：字往右让开，不被挡住。
                .padding(.leading, step == 5 || step == 7 ? 64 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            if state.searched {
                Label("已联网 · Kimi", systemImage: "globe").font(.system(size: 12)).foregroundStyle(GuideColor.secondary).fixedSize()
            } else if state.canSearch {
                Button { tap(.search) } label: {
                    Label("使用联网查询", systemImage: "globe")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0369A1))
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(Capsule().fill(Color(light: 0xE0F2FE, dark: 0x0C3448)))
                        .overlay(Capsule().strokeBorder(TourColor.answerRing.opacity(0.4), lineWidth: 1))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .tourTarget(.search)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: 按键

    private var askActive: Bool { state.expanded }

    private var keys: some View {
        let gap: CGFloat = 6, height: CGFloat = 42
        return HStack(alignment: .top, spacing: gap) {
            // 四列等宽，空格占两列。
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                keyRow(["123", "，。?!", "ABC", "DEF"], height: height)
                keyRow(["#@¥", "GHI", "JKL", "MNO"], height: height)
                keyRow(["常用", "PQRS", "TUV", "WXYZ"], height: height)
                GridRow {
                    key(Image(systemName: "face.smiling"), height: height)
                    key(Text("中/英"), height: height)
                    key(Text("空 格"), height: height).gridCellColumns(2)
                }
            }
            VStack(spacing: gap) {
                key(Image(systemName: "delete.left"), height: height)
                key(Text("^^"), height: height)
                returnKey.frame(height: height * 2 + gap)
            }
            .frame(width: 66)
        }
    }

    private func keyRow(_ titles: [String], height: CGFloat) -> some View {
        GridRow {
            ForEach(titles, id: \.self) { key(Text($0), height: height) }
        }
    }

    private func key<Label: View>(_ label: Label, height: CGFloat) -> some View {
        label
            .font(.system(size: 17))
            .foregroundStyle(GuideColor.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.key)
                .shadow(color: .black.opacity(0.12), radius: 0, y: 1))
            .contentShape(Rectangle())
            .onTapGesture { wrong() }
    }

    @ViewBuilder
    private var returnKey: some View {
        if askActive {
            VStack(spacing: 4) {
                Text("改写").font(.system(size: 10, weight: .semibold)).opacity(0.75)
                Text("执行").font(.system(size: 16, weight: .bold))
                Text("问答").font(.system(size: 10, weight: .semibold)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NebulaFill(palette: .ask).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
            .contentShape(Rectangle())
            .onTapGesture { wrong() }
        } else {
            Image(systemName: "return")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TourColor.purple)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.returnFill))
                .contentShape(Rectangle())
                .onTapGesture { wrong() }
        }
    }

    // MARK: 分词面板（FT10）

    private var wordPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已选 3 个").font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                Spacer()
                Text("长按结果卡打开").font(.system(size: 12)).foregroundStyle(GuideColor.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(TourText.words.enumerated()), id: \.offset) { index, word in
                    let picked = index < 3
                    Text(word)
                        .font(.system(size: 14))
                        .foregroundStyle(picked ? Color.white : GuideColor.text)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(picked ? TourColor.purple : TourColor.key))
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                Button { tap(.insert) } label: {
                    Label("插入", systemImage: "text.insert")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], startPoint: .leading, endPoint: .trailing)))
                }
                .tourTarget(.insert)
                Button { wrong() } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x0E9F6E)))
                }
                Button { wrong() } label: {
                    Text("全选").font(.system(size: 14, weight: .semibold)).foregroundStyle(GuideColor.text)
                        .frame(width: 64, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TourColor.key))
                }
                Button { wrong() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(GuideColor.text)
                        .frame(width: 64, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TourColor.key))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(height: 4 * 42 + 3 * 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(light: 0xF1F0FA, dark: 0x232325)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TourColor.ring.opacity(0.4), lineWidth: 1))
    }
}

/// 键盘顶部 26 的圆角，底边直角。
private struct TopRounded: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
