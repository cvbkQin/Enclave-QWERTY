import SwiftUI

// 首次打开的功能演示（FT0–FT16）：隐私同意之后、配置接口（OB1）之前，用 App 里画的模拟键盘把润色、改写、提示词、问答、分词各点一遍。
// 结果全是预设内容：不调用 API、不联网、不扣次数、不计入统计；演示里加的提示词也不写进真的提示词列表。
// 0.93 起按「功能演示动效方案」：每一步是连续过程（按下、处理中、逐字流出、打字替换、删字重打），不再整块换图。
// 小手只做示范；用户自己点了才触发，抬起那一帧才算。

enum FeatureTour {
    private static let seenKey = "featureTour.seen"

    /// 走完或跳过都记下，以后不再自动弹（存在 App Group）。
    static var seen: Bool {
        get { SharedStorage.defaults.bool(forKey: seenKey) }
        set { SharedStorage.defaults.set(newValue, forKey: seenKey) }
    }
}

// MARK: - 预设内容

/// 剧本：三种界面语言各一套。改写和提示词的目标语言：中文、日文版翻成英文，英文版翻成中文。
private struct TourScript {
    var contact: String
    var avatar: String
    var placeholder: String
    var message1: String
    var original: String
    var polished: String
    var askRewrite: String
    var rewritten: String
    var askShorter: String
    var shorter: String
    var promptName: String
    var promptContent: String
    var nineField: String
    var nineResult: String
    var riddleMessage: String
    var riddleField: String
    var riddleAnswer: String
    var riddleRewrite: String
    var riddleReply: String
    var message2: String
    var askTrain: String
    var trainAnswer: String
    var trainWeb: String
    /// 分词面板里的词；hints 是带虚线框提示的几块。
    var words: [String]
    var hints: [Int]
    /// 插入时词和词之间放什么（英文空格，中文、日文不放）。
    var joiner: String

    static var current: TourScript {
        switch Loc.current {
        case .en: return en
        case .ja: return ja
        case .zh, .system: return zh
        }
    }

    static let zh = TourScript(
        contact: "小林", avatar: "林", placeholder: "回复 小林",
        message1: "文件看过了吗？第三页的数据我不太确定。",
        original: "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看",
        polished: "文件我看过了，整体没问题。第三页有个数字好像不太对，麻烦再核对一下。",
        askRewrite: "翻成英文",
        rewritten: "Checked the file, looks fine overall. One number on page 3 seems off. Could you double-check?",
        askShorter: "再简短一点",
        shorter: "File's fine, but one number on page 3 looks off. Can you check?",
        promptName: "英文", promptContent: "翻成自然的英文，意思不变，语气和原文一样。",
        nineField: "好的我下午三点前改好发你",
        nineResult: "Sure, I'll have it fixed and sent to you before 3 p.m.",
        riddleMessage: "出个脑筋急转弯考考我？",
        riddleField: "大象装进冰箱需要几步",
        riddleAnswer: "三步：打开冰箱门，把大象放进去，关上冰箱门。",
        riddleRewrite: "考你一个脑筋急转弯：把大象装进冰箱，一共需要几步？",
        riddleReply: "三步？",
        message2: "另外，周六去杭州，高铁需要多久？",
        askTrain: "上海到杭州高铁最快多久",
        trainAnswer: "最快 45 分钟左右，坐不停站的 G 字头直达车；具体车次和时间以 12306 为准。",
        trainWeb: "最快 45 分钟，G 字头直达车次一天十几趟，早上 7 点前就有。二等座七十多元。来源：12306",
        words: ["最快", "45", "分钟", "，", "G 字头", "直达", "车次", "一天", "十几趟", "，", "早上", "7 点", "前", "就有", "。",
                "二等座", "七十多元", "。", "来源", "：", "12306"],
        hints: [0, 1, 2], joiner: "")

    static let en = TourScript(
        contact: "Alex", avatar: "A", placeholder: "Reply to Alex",
        message1: "Did you get a chance to check the file? I'm not sure about the numbers on page 3.",
        original: "yeah i looked at the file its mostly fine but theres a number on page 3 that looks off can u check again",
        polished: "I've reviewed the file and it looks fine overall. One number on page 3 seems off. Could you double-check it?",
        askRewrite: "Translate into Chinese",
        rewritten: "文件我看过了，整体没问题。第三页有个数字好像不太对，麻烦再核对一下。",
        askShorter: "Make it shorter",
        shorter: "文件没问题，第三页有个数字不对，再核对一下。",
        promptName: "Chinese", promptContent: "Translate into natural Chinese. Keep the meaning and the tone.",
        nineField: "ok ill fix it and send it to u before 3",
        nineResult: "好的，我下午三点前改好发给你。",
        riddleMessage: "Got a riddle for me?",
        riddleField: "how many steps to put an elephant in a fridge",
        riddleAnswer: "Three: open the fridge, put the elephant in, close the door.",
        riddleRewrite: "Here's a riddle for you: how many steps does it take to put an elephant in a fridge?",
        riddleReply: "Three?",
        message2: "Also, I'm going to Paris on Saturday. How long is the train from London?",
        askTrain: "Fastest train from London to Paris",
        trainAnswer: "About 2 hours 16 minutes on a direct Eurostar. Check eurostar.com for exact times.",
        trainWeb: "Fastest is about 2 hours 16 minutes. There are around 15 direct trains a day, the first before 7 a.m. Standard fares start at about £39. Source: eurostar.com",
        words: ["Fastest", "is", "about", "2 hours", "16 minutes", ".", "There", "are", "around", "15", "direct", "trains", "a day", ",",
                "the first", "before", "7 a.m.", ".", "Standard", "fares", "start", "at", "about", "£39", ".", "Source", ":", "eurostar.com"],
        hints: [3, 4], joiner: " ")

    static let ja = TourScript(
        contact: "佐藤さん", avatar: "佐", placeholder: "佐藤さんに返信",
        message1: "資料、見てもらえましたか？3ページ目の数字に少し自信がなくて。",
        original: "資料見たよだいたい大丈夫だけど3ページ目の数字がなんか変な気がするからもう一回見てくれる",
        polished: "資料を確認しました。全体的には問題ありませんが、3ページ目の数字が少し気になります。もう一度ご確認いただけますか。",
        askRewrite: "英語に翻訳",
        rewritten: "Checked the file, looks fine overall. One number on page 3 seems off. Could you double-check?",
        askShorter: "もっと短く",
        shorter: "File's fine, but one number on page 3 looks off. Can you check?",
        promptName: "英語", promptContent: "自然な英語に翻訳。意味と口調はそのまま。",
        nineField: "了解3時までに直して送るね",
        nineResult: "Got it. I'll fix it and send it to you by 3.",
        riddleMessage: "何かなぞなぞ出してよ",
        riddleField: "象を冷蔵庫に入れるには何ステップ",
        riddleAnswer: "3ステップです。冷蔵庫を開ける、象を入れる、扉を閉める。",
        riddleRewrite: "なぞなぞです。象を冷蔵庫に入れるには、何ステップ必要でしょう？",
        riddleReply: "3ステップ？",
        message2: "ちなみに、土曜日に大阪へ行くんですが、新幹線だとどのくらいかかりますか？",
        askTrain: "東京から新大阪まで新幹線で最速何分",
        trainAnswer: "のぞみで最速約 2 時間 21 分です。正確な時刻は JR 東海のサイトでご確認ください。",
        trainWeb: "最速は約 2 時間 21 分。のぞみは 1 時間に最大 12 本、始発は朝 6 時台です。普通車指定席は約 14,700 円。出典：JR 東海",
        words: ["最速", "は", "約", "2 時間", "21 分", "。", "のぞみ", "は", "1 時間", "に", "最大", "12 本", "、", "始発", "は", "朝 6 時台",
                "です", "。", "普通車", "指定席", "は", "約", "14,700 円", "。", "出典", "：", "JR 東海"],
        hints: [3, 4], joiner: "")
}

// MARK: - 步骤

/// 小手能指的地方，也是能点的地方。
private enum TourTarget: Hashable {
    case sparkle, chevron, undo, redo, drawer, magnifier, switchMode, replace, send, search, card, insert, plus, add
    /// 提示词一排：0 润色，1–4 内置，5 演示里加的那条。
    case pill(Int)
    /// 分词面板虚线框的第一块、最后一块（小手横划示范用）。
    case words, wordsEnd
}

private enum TourChapter {
    case polish, rewrite, prompt, answer, words

    var name: String {
        switch self {
        case .polish: return L("润色", "Polish", "整える")
        case .rewrite: return L("改写", "Rewrite", "書き換え")
        case .prompt: return L("提示词", "Prompts", "プロンプト")
        case .answer: return L("问答", "Answer", "回答")
        case .words: return L("分词", "Pick words", "単語選択")
        }
    }

    var text: Color {
        switch self {
        case .polish: return Color(light: 0x5B4BE8, dark: 0xB4A9FF)
        case .rewrite: return Color(light: 0x6D28D9, dark: 0xC4B5FD)
        case .prompt: return Color(light: 0x4338CA, dark: 0xA5B4FC)
        case .answer: return Color(light: 0x0369A1, dark: 0x7DD3FC)
        case .words: return Color(light: 0x047857, dark: 0x6EE7B7)
        }
    }

    var fill: Color {
        switch self {
        case .polish: return Color(light: 0xECEAFD, dark: 0x2E2766)
        case .rewrite: return Color(light: 0xF3E8FF, dark: 0x3B1F66)
        case .prompt: return Color(light: 0xE0E7FF, dark: 0x262A5C)
        case .answer: return Color(light: 0xE0F2FE, dark: 0x0C3448)
        case .words: return Color(light: 0xD1FAE5, dark: 0x063B2C)
        }
    }
}

/// 一步的章节、序号、标题、说明。FT9 分前后两段（part 1：随时换回）。
private struct TourStep {
    var chapter: TourChapter
    var index: Int
    var total: Int
    var title: String
    var detail: String

    static let count = 15

    static func info(_ step: Int, part: Int) -> TourStep {
        switch step {
        case 1: return TourStep(chapter: .polish, index: 1, total: 2,
                                title: L("点击 ✨，润色输入内容", "Tap ✨ to polish your text", "✨ をタップして文章を整える"),
                                detail: L("AI 将修正语病和标点，并直接替换输入框中的文字。", "AI fixes grammar and punctuation and replaces the text in the input field.", "AI が文法と句読点を直し、入力欄の文章をそのまま置き換えます。"))
        case 2: return TourStep(chapter: .polish, index: 2, total: 2,
                                title: L("润色完成，可随时撤销", "Done. You can undo anytime", "完了。いつでも元に戻せます"),
                                detail: L("点击 ↶ 恢复原文；点击 ↷ 重新应用润色结果。", "Tap ↶ to restore the original; tap ↷ to apply the polished text again.", "↶ で元の文章に戻り、↷ で整えた文章を再び適用します。"))
        case 3: return TourStep(chapter: .rewrite, index: 1, total: 4,
                                title: L("点击此处，展开回答卡", "Tap here to open the answer card", "ここをタップして回答カードを開く"),
                                detail: L("展开后，可在识意框中输入修改要求或问题。", "Then type an instruction or a question in the Ask field.", "開いたら、識意欄に修正の指示や質問を入力できます。"))
        case 4: return TourStep(chapter: .rewrite, index: 2, total: 4,
                                title: L("写下要求，点击放大镜", "Write an instruction, then tap the magnifier", "指示を入力して虫めがねをタップ"),
                                detail: L("识意框中已预填修改要求。点击放大镜，AI 按要求改写输入框中的文字。", "An instruction is already in the Ask field. Tap the magnifier and AI rewrites your text as asked.", "識意欄には指示が入力済みです。虫めがねをタップすると、AI が指示どおりに文章を書き換えます。"))
        case 5: return TourStep(chapter: .rewrite, index: 3, total: 4,
                                title: L("点击「替换」，应用结果", "Tap Replace to use the result", "「置換」で結果を反映"),
                                detail: L("改写结果显示在回答卡中。点击「替换」写入输入框；按住上滑可改为「插入」，保留原文。", "The rewrite appears in the card. Tap Replace to put it in the input field; hold and slide up for Insert to keep the original.", "書き換え結果はカードに表示されます。「置換」で入力欄に反映し、長押しして上にスライドすると元の文章を残す「挿入」になります。"))
        case 6: return TourStep(chapter: .rewrite, index: 4, total: 4,
                                title: L("按住放大镜，上下拖动", "Hold the magnifier and slide", "虫めがねを長押しして上下にスライド"),
                                detail: L("可预先指定处理方式：上滑为改写，下滑为问答，松手即执行。请按住放大镜向上拖动。", "Choose the mode in advance: slide up to rewrite, down to answer, and release to run. Hold the magnifier and slide up.", "上で書き換え、下で回答を指定し、指を離すと実行します。虫めがねを長押しして上にスライドしてください。"))
        case 7: return TourStep(chapter: .prompt, index: 1, total: 3,
                                title: L("常用英文发消息？存成一条提示词", "Write in Chinese often? Save it as a prompt", "英語でよく送るなら、プロンプトに保存"),
                                detail: L("不用每次都写「翻成英文」。把它存成提示词，以后点一下就能用。点击「润色 ▾」右侧箭头，再点击「＋」。", "No need to type \"Translate into Chinese\" every time. Save it as a prompt and it's one tap away. Tap the arrow on Polish ▾, then +.", "毎回「英語に翻訳」と書かなくても、プロンプトに保存すればワンタップで使えます。「整える ▾」の矢印をタップし、「＋」をタップしてください。"))
        case 8: return TourStep(chapter: .prompt, index: 2, total: 3,
                                title: L("添加「英文」提示词", "Add a Chinese prompt", "「英語」プロンプトを追加"),
                                detail: L("名称和内容已填好，点击「添加」。名称显示在键盘上，内容是每次发给 AI 的要求。", "The name and prompt are filled in. Tap Add. The name shows on the keyboard; the prompt is sent to AI every time.", "名前と内容は入力済みです。「追加」をタップしてください。名前はキーボードに表示され、内容は毎回 AI に送る指示になります。"))
        case 9 where part == 0: return TourStep(chapter: .prompt, index: 3, total: 3,
                                title: L("切到「英文」，点 ✨ 直接出英文", "Pick Chinese, then tap ✨", "「英語」を選んで ✨"),
                                detail: L("点击「英文」，再点击 ✨，输入框里的中文直接改成英文。", "Tap Chinese, then ✨. Your text turns into Chinese right in the input field.", "「英語」を選んで ✨ をタップすると、入力欄の文章がそのまま英語になります。"))
        case 9: return TourStep(chapter: .prompt, index: 3, total: 3,
                                title: L("随时换回", "Switch back anytime", "いつでも戻せます"),
                                detail: L("点击「润色」即可换回。", "Tap Polish to switch back.", "「整える」をタップすると元に戻ります。"))
        case 10: return TourStep(chapter: .answer, index: 1, total: 5,
                                 title: L("点击放大镜，自动判断", "Tap the magnifier to let it decide", "虫めがねで自動判断"),
                                 detail: L("识意框留空时，放大镜会根据输入框中的文字判断是修改还是回答。", "With the Ask field empty, the magnifier looks at the text in the input field and decides whether to rewrite it or answer it.", "識意欄が空のときは、入力欄の文章から修正か回答かを判断します。"))
        case 11: return TourStep(chapter: .answer, index: 2, total: 5,
                                 title: L("想发送原句时，点击「切换」", "Meant to send it? Tap Switch", "送りたい文なら「切替」"),
                                 detail: L("这句话其实是要发给对方的。点击「切换」，改为润色这句话，而不是回答它。", "You actually want to send this to your friend. Tap Switch to polish the sentence instead of answering it.", "この文は相手に送るものです。「切替」をタップすると、回答ではなく文章を整えます。"))
        case 12: return TourStep(chapter: .answer, index: 3, total: 5,
                                 title: L("替换后发送", "Replace, then send", "置換して送信"),
                                 detail: L("点击「替换」写入输入框，再点击「发送」。", "Tap Replace to put it in the input field, then tap Send.", "「置換」で入力欄に反映し、「送信」をタップします。"))
        case 13: return TourStep(chapter: .answer, index: 4, total: 5,
                                 title: L("输入问题，点击放大镜", "Ask a question, then tap the magnifier", "質問を入力して虫めがねをタップ"),
                                 detail: L("放大镜会自动判断：修改文字，或回答问题。", "It decides on its own: rewrite the text, or answer the question.", "文章の修正か質問への回答かを自動で判断します。"))
        case 14: return TourStep(chapter: .answer, index: 5, total: 5,
                                 title: L("需要实时信息时，联网查询", "Need live info? Search the web", "最新情報が必要なときはウェブ検索"),
                                 detail: L("默认回答基于模型已有知识。点击「使用联网查询」获取最新信息（通义千问、Kimi、智谱 GLM、腾讯混元支持）。", "Answers use the model's own knowledge by default. Tap Search the web for the latest information (supported by Qwen, Kimi, Zhipu GLM and Tencent Hunyuan).", "通常はモデルの知識で回答します。「ウェブで調べる」で最新情報を取得できます（Qwen、Kimi、Zhipu GLM、Tencent Hunyuan に対応）。"))
        default: return TourStep(chapter: .words, index: 1, total: 1,
                                 title: L("长按结果卡，选词插入", "Hold the card to pick words", "カードを長押しして単語を挿入"),
                                 detail: L("只需部分内容时，长按结果卡，点选或横划选中词语，再点击「插入」。", "Need only part of it? Hold the result card, tap or swipe to select words, then tap Insert.", "一部だけ使いたいときは、結果カードを長押しし、タップかスワイプで単語を選んで「挿入」をタップしてください。"))
        }
    }
}

// MARK: - 状态机

/// 演示用的「接口」和键盘状态：照剧本一段段吐字、打字、删字。所有动画都能被跳过、返回打断。
@MainActor
private final class TourModel: ObservableObject {
    enum Mode { case rewrite, answer }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var mine = false
        var typing = false
    }

    let script = TourScript.current
    var reduceMotion = false

    /// 0 欢迎，1–15 演示，16 完成。
    @Published var step = 0
    @Published var part = 0
    /// 正在等用户点哪一颗；nil 时小手不出来。
    @Published var target: TourTarget?
    /// 用户手指按着的那颗。
    @Published var pressed: TourTarget?
    /// 小手示范点下去的那一帧（每 1.5 秒一次）。
    @Published var demoDown = false
    @Published var shakes = 0

    @Published var messages: [Message] = []
    @Published var field = ""
    @Published var fieldDim = false
    @Published var expanded = false
    @Published var card: String?
    @Published var cardMode: Mode?
    @Published var generating = false
    @Published var ask = ""

    @Published var promptsOpen = false
    @Published var customPrompt: String?
    @Published var customPop = false
    @Published var selectedPrompt = 0
    @Published var sheet = false
    @Published var sheetName = ""
    @Published var sheetContent = ""

    @Published var sparkRunning = false
    @Published var sparkDone: Date?
    @Published var undoOn = false
    @Published var redoOn = false
    @Published var undoTurns = 0

    @Published var canSearch = false
    @Published var searching = false
    @Published var searched = false

    @Published var panel = false
    @Published var picked: Set<Int> = []
    @Published var dragPick = false
    @Published var dragging = false
    @Published var sendReady = false

    private var run: Task<Void, Never>?
    private var demo: Task<Void, Never>?
    private var lastTap: TourTarget?

    var activeStyle: Mode? { card != nil && !generating && !searching ? cardMode : nil }

    // MARK: 进退

    func go(_ next: Int) {
        run?.cancel()
        guard next >= 0 else { return }
        part = 0
        target = nil
        pressed = nil
        applyStart(next)
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
        guard (1...TourStep.count).contains(next) else { return }
        run = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.play(next)
                try await self.pause(0.6)
                self.go(next + 1)
            } catch {}
        }
    }

    func stop() {
        run?.cancel()
        demo?.cancel()
    }

    /// 小手每 1.5 秒示范点一下，按钮跟着轻轻按下（不触发）。
    func startDemo() {
        demo?.cancel()
        demo = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.target != nil, self.pressed == nil, !self.reduceMotion else { continue }
                withAnimation(.easeOut(duration: 0.1)) { self.demoDown = true }
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { self.demoDown = false }
            }
        }
    }

    // MARK: 点按

    func pressBegan(_ hit: TourTarget) {
        guard pressed == nil else { return }
        withAnimation(.easeOut(duration: 0.08)) { pressed = hit }
        if hit == target { Self.haptic() }
    }

    func pressEnded(_ hit: TourTarget, inside: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pressed = nil }
        if inside { tap(hit) }
    }

    func tap(_ hit: TourTarget) {
        guard let target else { return }
        if hit == target, hit != .insert || !picked.isEmpty {
            lastTap = hit
        } else {
            wrong()
        }
    }

    func wrong() {
        guard target != nil, !reduceMotion else { return }
        withAnimation(.linear(duration: 0.3)) { shakes += 1 }
    }

    func toggleWord(_ index: Int, on: Bool? = nil) {
        guard panel else { return }
        let select = on ?? !picked.contains(index)
        guard select != picked.contains(index) else { return }
        if select { picked.insert(index) } else { picked.remove(index) }
        Self.haptic()
    }

    func selectAll() {
        guard panel else { return }
        picked = Set(script.words.indices)
        Self.haptic()
    }

    /// FT6：按住放大镜往上拖。只认上滑后松手。
    func drag(_ translation: CGFloat?, ended: Bool) {
        guard step == 6, target == .magnifier else { return }
        if ended {
            dragging = false
            if dragPick { lastTap = .magnifier } else { wrong() }
            dragPick = false
            return
        }
        dragging = true
        let pick = (translation ?? 0) < -16
        if pick && !dragPick { Self.haptic() }
        dragPick = pick
    }

    static func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: 每一步开始时的样子（返回上一步就回到这里）

    private func applyStart(_ n: Int) {
        let s = script
        messages = [Message(text: s.message1)]
        if n >= 11 { messages.append(Message(text: s.riddleMessage)) }
        if n >= 13 {
            messages = [Message(text: s.riddleMessage), Message(text: s.riddleRewrite, mine: true), Message(text: s.riddleReply)]
        }
        if n >= 14 { messages.append(Message(text: s.message2)) }

        switch n {
        case ...1: field = s.original
        case 2: field = s.polished
        case 3...5: field = s.original
        case 6, 7: field = s.rewritten
        case 8, 9: field = s.shorter
        case 10: field = s.nineResult
        case 11, 12: field = s.riddleField
        default: field = ""
        }
        fieldDim = false
        expanded = (4...7).contains(n) || n >= 11
        switch n {
        case 4, 5: ask = s.askRewrite
        case 6: ask = s.askRewrite
        case 7: ask = s.askShorter
        case 14, 15: ask = s.askTrain
        default: ask = ""
        }
        switch n {
        case 5, 6: card = s.rewritten; cardMode = .rewrite
        case 7: card = s.shorter; cardMode = .rewrite
        case 11: card = s.riddleAnswer; cardMode = .answer
        case 12, 13: card = s.riddleRewrite; cardMode = .rewrite
        case 14: card = s.trainAnswer; cardMode = .answer
        case 15: card = s.trainWeb; cardMode = .answer
        default: card = nil; cardMode = nil
        }
        generating = false
        promptsOpen = n == 8 || n == 9
        customPrompt = n >= 9 ? s.promptName : nil
        customPop = false
        selectedPrompt = 0
        sheet = false
        sheetName = ""
        sheetContent = ""
        sparkRunning = false
        sparkDone = nil
        undoOn = n == 2
        redoOn = n == 3
        canSearch = n == 14
        searching = false
        searched = n == 15
        panel = false
        picked = []
        dragPick = false
        dragging = false
        sendReady = false
    }

    // MARK: 剧本

    private func play(_ n: Int) async throws {
        let s = script
        switch n {
        case 1:
            try await wait(.sparkle)
            try await polish(to: s.polished)
            undoOn = true
        case 2:
            try await wait(.undo)
            withAnimation(.easeInOut(duration: 0.3)) { undoTurns += 1 }
            try await retype(\.field, to: s.original)
            undoOn = false
            redoOn = true
        case 3:
            try await wait(.drawer)
            withAnimation(.easeOut(duration: 0.25)) { expanded = true }
            try await pause(0.35)
            try await type(\.ask, s.askRewrite, duration: 0.6)
        case 4:
            try await wait(.magnifier)
            try await generate(.rewrite, s.rewritten)
        case 5:
            try await wait(.replace)
            try await typeReplace(\.field, to: s.rewritten)
        case 6:
            try await retype(\.ask, to: s.askShorter)
            try await wait(.magnifier)
            try await generate(.rewrite, s.shorter)
        case 7:
            try await pause(0.4)
            withAnimation(.easeOut(duration: 0.25)) { expanded = false }
            try await pause(0.3)
            try await typeReplace(\.field, to: s.shorter)
            try await wait(.chevron)
            withAnimation(.easeOut(duration: 0.25)) { promptsOpen = true }
            try await pause(0.3)
            try await wait(.plus)
        case 8:
            withAnimation(.easeOut(duration: 0.3)) { sheet = true }
            try await pause(0.4)
            try await type(\.sheetName, s.promptName, duration: 0.3)
            try await type(\.sheetContent, s.promptContent, duration: 0.9)
            try await wait(.add)
            withAnimation(.easeIn(duration: 0.25)) { sheet = false }
            try await pause(0.3)
            let name = sheetName.trimmingCharacters(in: .whitespacesAndNewlines)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                customPrompt = name.isEmpty ? s.promptName : name
                customPop = true
            }
            Self.haptic()
            try await pause(0.2)
            customPop = false
        case 9:
            try await retype(\.field, to: s.nineField)
            try await wait(.pill(5))
            withAnimation(.easeOut(duration: 0.15)) { selectedPrompt = 5 }
            try await wait(.sparkle)
            try await polish(to: s.nineResult)
            try await pause(0.6)
            withAnimation(.easeOut(duration: 0.25)) { part = 1 }
            try await wait(.pill(0))
            withAnimation(.easeOut(duration: 0.15)) { selectedPrompt = 0 }
            try await pause(0.2)
            withAnimation(.easeOut(duration: 0.25)) { promptsOpen = false }
        case 10:
            try await wait(.drawer)
            withAnimation(.easeOut(duration: 0.25)) { expanded = true }
            try await incoming(s.riddleMessage)
            try await retype(\.field, to: s.riddleField)
            try await wait(.magnifier)
            try await generate(.answer, s.riddleAnswer)
        case 11:
            try await wait(.switchMode)
            withAnimation(.easeInOut(duration: 0.25)) { cardMode = .rewrite }
            try await generate(.rewrite, s.riddleRewrite, delay: 0.5)
        case 12:
            try await wait(.replace)
            try await typeReplace(\.field, to: s.riddleRewrite)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            let sent = field
            withAnimation(.easeOut(duration: 0.3)) {
                sendReady = false
                field = ""
                messages.append(Message(text: sent, mine: true))
            }
            try await pause(0.8)
            withAnimation(.easeOut(duration: 0.3)) { messages.append(Message(text: s.riddleReply)) }
        case 13:
            try await incoming(s.message2)
            try await retype(\.ask, to: s.askTrain)
            try await wait(.magnifier)
            try await generate(.answer, s.trainAnswer)
            withAnimation(.easeIn(duration: 0.3)) { canSearch = true }
        case 14:
            try await wait(.search)
            withAnimation(.easeOut(duration: 0.2)) {
                canSearch = false
                searching = true
            }
            try await pause(1)
            searching = false
            searched = true
            try await stream(s.trainWeb)
        default:
            try await wait(.card)
            withAnimation(.easeOut(duration: 0.25)) { panel = true }
            try await pause(0.3)
            target = .words
            while picked.isEmpty { try await pause(0.05) }
            try await wait(.insert)
            let words = picked.sorted().map { s.words[$0] }.joined(separator: s.joiner)
            withAnimation(.easeOut(duration: 0.15)) { panel = false }
            try await pause(0.2)
            try await type(\.field, words, duration: 0.5)
        }
    }

    // MARK: 动作

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// 等用户点对那一颗（抬起才算）。
    private func wait(_ hit: TourTarget) async throws {
        lastTap = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { target = hit }
        while lastTap != hit { try await pause(0.03) }
        lastTap = nil
        target = nil
    }

    /// 快速模式润色：按钮套流光 0.6 秒 → 原文变淡、结果打出来 → 闪金。
    private func polish(to text: String) async throws {
        sparkRunning = true
        try await pause(0.6)
        try await typeReplace(\.field, to: text)
        sparkRunning = false
        sparkDone = Date()
    }

    /// 回答卡：生成中 → 模式块亮起 → 逐字流出。
    private func generate(_ mode: Mode, _ text: String, delay: Double = 0.6) async throws {
        withAnimation(.easeOut(duration: 0.2)) {
            generating = true
            canSearch = false
            searched = false
        }
        try await pause(delay)
        withAnimation(.easeOut(duration: 0.2)) {
            cardMode = mode
            generating = false
        }
        try await stream(text)
    }

    /// 演示接口按词吐字：中文 2–4 个字一段，英文一个词一段；约 30 字/秒，标点后多停 0.12 秒。
    private func stream(_ text: String) async throws {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { card = text }
            return
        }
        card = ""
        for chunk in Self.chunks(text) {
            card = (card ?? "") + chunk
            let punctuation = chunk.last.map { "，。！？、：；,.!?:;".contains($0) } ?? false
            try await pause(Double(chunk.count) / 30 * Double.random(in: 0.7...1.3) + (punctuation ? 0.12 : 0))
        }
    }

    static func chunks(_ text: String) -> [String] {
        let cjk = text.unicodeScalars.contains { $0.value >= 0x3000 }
        var out: [String] = []
        var current = ""
        var size = Int.random(in: 2...4)
        for char in text {
            current.append(char)
            let breakHere = cjk
                ? current.count >= size || "，。！？、：；".contains(char)
                : char == " "
            if breakHere {
                out.append(current)
                current = ""
                size = Int.random(in: 2...4)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// 结果写进输入框：原文变淡 0.15 秒，新字从左往右打出来（0.6–0.9 秒，按字数）。
    private func typeReplace(_ path: ReferenceWritableKeyPath<TourModel, String>, to text: String) async throws {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { self[keyPath: path] = text }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { fieldDim = true }
        try await pause(0.15)
        self[keyPath: path] = ""
        fieldDim = false
        try await type(path, text, duration: min(max(0.6 + Double(text.count) * 0.004, 0.6), 0.9))
    }

    /// 撤销、换内容：当前文字从尾往前删掉 0.25 秒，再打出新的 0.35 秒。
    private func retype(_ path: ReferenceWritableKeyPath<TourModel, String>, to text: String) async throws {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { self[keyPath: path] = text }
            return
        }
        let old = self[keyPath: path]
        let ticks = 15
        if !old.isEmpty {
            for i in stride(from: ticks - 1, through: 0, by: -1) {
                self[keyPath: path] = String(old.prefix(old.count * i / ticks))
                try await pause(0.25 / Double(ticks))
            }
        }
        try await type(path, text, duration: 0.35)
    }

    private func type(_ path: ReferenceWritableKeyPath<TourModel, String>, _ text: String, duration: Double) async throws {
        let base = self[keyPath: path]
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { self[keyPath: path] = base + text }
            return
        }
        let ticks = max(Int(duration * 60), 1)
        for i in 1...ticks {
            self[keyPath: path] = base + String(text.prefix(text.count * i / ticks))
            try await pause(duration / Double(ticks))
        }
    }

    /// 对方发来新消息：「正在输入…」0.6 秒再弹出。
    private func incoming(_ text: String) async throws {
        withAnimation(.easeOut(duration: 0.25)) { messages.append(Message(text: "", typing: true)) }
        try await pause(0.6)
        withAnimation(.easeOut(duration: 0.25)) {
            messages.removeAll { $0.typing }
            messages.append(Message(text: text))
        }
        try await pause(0.3)
    }
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
    static let askLine = Color(light: 0xC9C0FF, dark: 0x5A4FA0)
    static let caret = Color(light: 0x5B4BE8, dark: 0xB4A9FF)
    static let pillOn = Color(light: 0xEDEBFD, dark: 0x2E2766)
    static let rowFill = Color(light: 0xF4F3FA, dark: 0x232325)
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
    @StateObject private var model = TourModel()
    @State private var summaryShown = 0

    var body: some View {
        ZStack {
            GuideBackground(glow: true)
            switch model.step {
            case 0: welcome
            case TourStep.count + 1: finished
            default: stepPage
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            model.reduceMotion = reduceMotion
            model.startDemo()
        }
        .onDisappear {
            model.stop()
            FeatureTour.seen = true
        }
    }

    // MARK: FT0 欢迎

    private var welcome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L("跳过", "Skip", "スキップ")) { exit(.skip) }
                    .font(.system(size: 15)).foregroundStyle(GuideColor.secondary)
            }
            .padding(.horizontal, 24).frame(height: 50).padding(.top, 8)
            GuidePage {
                VStack(alignment: .leading, spacing: 22) {
                    GuideAppMark(size: 64, corner: 18).padding(.top, 20)
                    GuideTitle(L("功能演示", "Feature Tour", "機能デモ"),
                               subtitle: L("配置 API 之前，可以先通过模拟键盘了解各项 AI 功能，约需 3 分钟。演示结果均为预设内容，不调用 API，也不联网。",
                                           "Before setting up an API, try each AI feature on a simulated keyboard. This takes about 3 minutes. All results are preset; no API is called and nothing goes online.",
                                           "API を設定する前に、模擬キーボードで各 AI 機能をお試しいただけます（約 3 分）。結果はすべてあらかじめ用意したもので、API の呼び出しや通信は行いません。"))
                    GuideCard {
                        overviewRow(1, L("一键润色", "One-tap Polish", "ワンタップで整える"),
                                    L("点击 ✨ 润色输入内容，可随时撤销", "Tap ✨ to polish your text; undo anytime", "✨ で文章を整え、いつでも元に戻せる"), 2, .polish)
                        GuideDivider()
                        overviewRow(2, L("识意 · 改写", "Ask: Rewrite", "識意：書き換え"),
                                    L("展开回答卡，写下要求，点击或拖动放大镜", "Open the answer card, write an instruction, tap or slide the magnifier", "回答カードを開き、指示を書いて虫めがねをタップかスライド"), 4, .rewrite)
                        GuideDivider()
                        overviewRow(3, L("提示词", "Prompts", "プロンプト"),
                                    L("把常用要求存成提示词，点一下就能用", "Save an instruction you use often and run it with one tap", "よく使う指示を保存して、ワンタップで使う"), 3, .prompt)
                        GuideDivider()
                        overviewRow(4, L("识意 · 问答", "Ask: Answer", "識意：回答"),
                                    L("自动判断回答问题，可切换、替换和联网查询", "It answers questions on its own; switch, replace or search the web", "質問には自動で回答。切替・置換・ウェブ検索も"), 5, .answer)
                        GuideDivider()
                        overviewRow(5, L("分词插入", "Pick and Insert Words", "単語を選んで挿入"),
                                    L("长按结果卡，选取部分词语插入输入框", "Hold the result card and insert just the words you need", "結果カードを長押しして、必要な単語だけ挿入"), 1, .words)
                    }
                }
            } bottom: {
                GuidePrimaryButton(L("开始演示", "Start Tour", "デモを始める")) { model.go(1) }
                GuideSecondaryButton(L("跳过，前往设置", "Skip to Setup", "スキップして設定へ")) { exit(.skip) }
            }
        }
    }

    private func overviewRow(_ number: Int, _ title: String, _ detail: String, _ steps: Int, _ chapter: TourChapter) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(chapter.text)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(chapter.fill))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GuideColor.text)
                Text(detail).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(L("\(steps) 步", steps == 1 ? "1 step" : "\(steps) steps", "\(steps) ステップ"))
                .font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    // MARK: FT16 完成

    private static var summary: [(String, String)] { [
        (L("一键润色", "One-tap Polish", "ワンタップで整える"), L("收起状态下点击 ✨，可撤销", "Tap ✨ when collapsed; undo anytime", "閉じた状態で ✨、元に戻せる")),
        (L("识意改写", "Ask: Rewrite", "識意：書き換え"), L("写下要求，点击放大镜；按住上滑改写、下滑问答", "Write an instruction and tap the magnifier; hold and slide up to rewrite, down to answer", "指示を書いて虫めがね。長押しで上は書き換え、下は回答")),
        (L("自定义提示词", "Custom Prompts", "プロンプトの追加"), L("常用要求存成提示词，切过去点 ✨", "Save instructions you use often, pick one and tap ✨", "よく使う指示を保存し、選んで ✨")),
        (L("识意问答", "Ask: Answer", "識意：回答"), L("识意框留空，放大镜自动判断", "Leave the Ask field empty and the magnifier decides", "識意欄が空なら虫めがねが自動で判断")),
        (L("切换、替换与联网查询", "Switch, Replace and Web Search", "切替・置換・ウェブ検索"), L("结果先显示在回答卡中，确认后再写入", "Results show in the card first; you choose what goes in", "結果はまずカードに表示、確認してから反映")),
        (L("分词插入", "Pick and Insert Words", "単語を選んで挿入"), L("长按结果卡，选取部分词语", "Hold the result card to pick words", "結果カードを長押しして単語を選ぶ")),
    ] }

    private var finished: some View {
        GuidePage {
            VStack(alignment: .leading, spacing: 22) {
                GuideAppMark(size: 64, corner: 18).padding(.top, 70)
                GuideTitle(L("演示完成", "Tour complete", "デモ完了"),
                           subtitle: L("以上结果均为预设演示。配置 API 后，即可在任意 App 中使用这些功能。",
                                       "These results were preset. Set up an API to use these features in any app.",
                                       "以上の結果はデモ用に用意したものです。API を設定すると、どのアプリでもこれらの機能を使えます。"))
                GuideCard {
                    ForEach(Array(Self.summary.enumerated()), id: \.offset) { index, row in
                        if index > 0 { GuideDivider() }
                        summaryRow(row.0, row.1)
                            .opacity(index < summaryShown ? 1 : 0)
                    }
                }
            }
        } bottom: {
            GuidePrimaryButton(L("配置 API", "Set Up API", "API を設定")) { exit(.setup) }
            GuideSecondaryButton(L("暂不配置，仅使用打字", "Not Now, Typing Only", "今は設定せず入力のみ使う")) { exit(.later) }
        }
        .onAppear {
            FeatureTour.seen = true
            summaryShown = 0
            for index in 1...Self.summary.count {
                withAnimation(.easeOut(duration: 0.25).delay(reduceMotion ? 0 : 0.08 * Double(index))) { summaryShown = index }
            }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: FT1–FT15

    private var stepPage: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                topBar
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                chat
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                Spacer(minLength: 8)
                TourKeyboard(model: model)
            }
            if model.sheet {
                Color.black.opacity(0.25).ignoresSafeArea().transition(.opacity)
                TourAddSheet(model: model)
                    .transition(.move(edge: .bottom))
            }
        }
        .overlayPreferenceValue(TourFramesKey.self) { anchors in
            GeometryReader { proxy in
                if let target = model.target, let anchor = anchors[target], !(target == .magnifier && model.dragging) {
                    let end = anchors[.wordsEnd].map { proxy[$0] }
                    TourHand(rect: proxy[anchor], bounds: proxy.size, target: target, step: model.step,
                             swipeEnd: end, down: model.demoDown, userPressing: model.pressed != nil,
                             reduceMotion: reduceMotion, shakes: model.shakes)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: target)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.go(model.step - 1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GuideColor.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(GuideColor.card))
            }
            .accessibilityLabel(L("返回", "Back", "戻る"))
            HStack(spacing: 3) {
                ForEach(1...TourStep.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2).fill(index <= model.step ? TourColor.progressOn : TourColor.progressOff).frame(height: 4)
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.step)
            Button(L("跳过", "Skip", "スキップ")) { exit(.skip) }
                .font(.system(size: 15)).foregroundStyle(GuideColor.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .frame(height: 50)
        .padding(.top, 8)
    }

    private var header: some View {
        let info = TourStep.info(model.step, part: model.part)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(info.chapter.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(info.chapter.text)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(info.chapter.fill))
                Text(L("\(info.index) / \(info.total)", "\(info.index) of \(info.total)", "\(info.index) / \(info.total)"))
                    .font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                Spacer()
                Text(L("演示 · 不调用 API", "Demo · No API calls", "デモ · API を使用しません"))
                    .font(.system(size: 11.5)).foregroundStyle(GuideColor.secondary)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(GuideColor.card))
                    .overlay(Capsule().stroke(GuideColor.divider, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(info.title)
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(GuideColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.detail)
                    .font(.system(size: 15)).lineSpacing(4).foregroundStyle(GuideColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id("\(model.step)-\(model.part)")
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 8).combined(with: .opacity), removal: .opacity))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.25), value: "\(model.step)-\(model.part)")
    }

    /// 对话卡：对方的消息（最多留两条）、自己发出的气泡、宿主输入框（绿色光标）。
    private var chat: some View {
        let script = model.script
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(script.avatar).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xFDBA74), Color(hex: 0xF97316)], startPoint: .top, endPoint: .bottom)))
                Text(script.contact).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                Spacer()
                Text(L("演示内容 · 不会发送", "Demo content · Not sent", "デモ内容 · 送信されません"))
                    .font(.system(size: 10.5)).foregroundStyle(GuideColor.secondary)
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(TourColor.bubble))
            }
            ForEach(model.messages.suffix(2)) { message in
                bubble(message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Group {
                if model.field.isEmpty {
                    (Text(script.placeholder).foregroundColor(GuideColor.secondary.opacity(0.7))
                        + Text(model.expanded ? "" : "▏").foregroundColor(TourColor.hostCaret))
                } else {
                    // 识意框激活时宿主没有光标。
                    (Text(model.field) + Text(model.expanded ? "" : "▏").foregroundColor(TourColor.hostCaret))
                        .foregroundStyle(GuideColor.text)
                }
            }
            .font(.system(size: 15.5))
            .lineSpacing(3)
            .opacity(model.fieldDim ? 0.35 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.field))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TourColor.fieldStroke, lineWidth: 1))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GuideColor.card)
            .shadow(color: Color(hex: 0x3C28A0).opacity(0.07), radius: 14, y: 10))
    }

    @ViewBuilder
    private func bubble(_ message: TourModel.Message) -> some View {
        if message.mine {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 14.5)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(UnevenRoundedRect(radius: 16, corner: 5, right: true).fill(TourColor.purple))
            }
        } else {
            Text(message.typing ? L("正在输入…", "Typing…", "入力中…") : message.text)
                .font(.system(size: 14.5))
                .foregroundStyle(message.typing ? GuideColor.secondary : GuideColor.text)
                .lineLimit(3)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(UnevenRoundedRect(radius: 16, corner: 5, right: false).fill(TourColor.bubble))
        }
    }

    private func exit(_ how: Exit) {
        model.stop()
        FeatureTour.seen = true
        onExit(how)
    }
}

/// 消息气泡：对方左下角小圆角，自己右下角小圆角。
private struct UnevenRoundedRect: Shape {
    var radius: CGFloat
    var corner: CGFloat
    var right: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.height / 2), c = min(corner, rect.height / 2)
        let bottomLeft = right ? r : c, bottomRight = right ? c : r
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), radius: bottomRight)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), radius: bottomLeft)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

// MARK: - 按下态

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

    /// 能点的一颗：按下缩 96%、变暗，抬起才算；小手示范按下时轻轻按下（50% 幅度）。
    func tourPress(_ id: TourTarget, model: TourModel) -> some View {
        modifier(TourPress(id: id, model: model))
    }
}

private struct TourPress: ViewModifier {
    let id: TourTarget
    @ObservedObject var model: TourModel

    func body(content: Content) -> some View {
        let pressed = model.pressed == id
        let demo = model.demoDown && model.target == id && model.pressed == nil
        content
            .scaleEffect(pressed ? 0.96 : demo ? 0.98 : 1)
            .brightness(pressed ? -0.08 : demo ? -0.04 : 0)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in model.pressBegan(id) }
                .onEnded { value in
                    let moved = abs(value.translation.width) + abs(value.translation.height)
                    model.pressEnded(id, inside: moved < 30)
                })
            .tourTarget(id)
    }
}

// MARK: - 小手

/// 晃一下：左右 6pt 三个来回。
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// 小手和界面同一个时钟：示范按下的那一帧（down）按钮也轻轻按下；用户自己按着时退到 30%。
/// FT6 示范按住放大镜往上拖，FT15 示范长按结果卡、在虚线框的词上横划。减弱动态效果时静止。
private struct TourHand: View {
    var rect: CGRect
    var bounds: CGSize
    var target: TourTarget
    var step: Int
    var swipeEnd: CGRect?
    var down: Bool
    var userPressing: Bool
    var reduceMotion: Bool
    var shakes: Int

    private static let rippleColor = Color(hex: 0x8B7CF6)

    var body: some View {
        Group {
            if reduceMotion {
                hand(tip: CGPoint(x: rect.midX, y: rect.midY + 4), ripple: false)
            } else if step == 6 && target == .magnifier {
                TimelineView(.animation) { context in
                    dragFrame(phase(context.date, Self.dragPeriod))
                }
            } else if target == .card {
                TimelineView(.animation) { context in
                    holdFrame(phase(context.date, Self.holdPeriod))
                }
            } else if target == .words, let swipeEnd {
                TimelineView(.animation) { context in
                    swipeFrame(phase(context.date, Self.swipePeriod), end: swipeEnd)
                }
            } else {
                hand(tip: CGPoint(x: rect.midX, y: rect.midY + (down ? 0 : 4)), ripple: down)
            }
        }
        .opacity(userPressing ? 0.3 : 1)
        .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
    }

    private func phase(_ date: Date, _ period: Double) -> CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
    }

    private var flipped: Bool { rect.midX > bounds.width / 2 }

    private func hand(tip: CGPoint, ripple: Bool) -> some View {
        let size = CoachHandShape.size, fingertip = CoachHandShape.fingertip
        let dx = size.width / 2 - fingertip.x
        let center = CGPoint(x: tip.x + (flipped ? -dx : dx), y: tip.y + size.height / 2 - fingertip.y)
        return ZStack {
            Circle()
                .fill(Self.rippleColor.opacity(0.16))
                .overlay(Circle().strokeBorder(Self.rippleColor, lineWidth: 2.5))
                .frame(width: ripple ? 56 : 12, height: ripple ? 56 : 12)
                .opacity(ripple ? 0.9 : 0)
                .position(x: rect.midX, y: rect.midY)
                .animation(ripple ? .easeOut(duration: 0.12) : .easeOut(duration: 0.5), value: ripple)
            CoachHandShape.hand(flipped: flipped, scale: down ? 0.92 : 1).position(center)
        }
    }

    /// FT15 一轮 2 秒：按下 → 指尖一圈天蓝进度环 0.45 秒画满 → 环往外撑大淡掉 → 手淡出。
    private static let holdPeriod = 2.0
    private static let holdRing = Color(hex: 0x0EA5E9)
    private static let holdTrack = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)

    private func holdFrame(_ h: CGFloat) -> some View {
        let center = CGPoint(x: rect.minX + 60, y: rect.minY + 18)
        let press = min(h / 0.1, 1)
        let fill = min(max((h - 0.1) / 0.225, 0), 1)
        let pop = min(max((h - 0.325) / 0.175, 0), 1)
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
            let size = CoachHandShape.size, fingertip = CoachHandShape.fingertip
            CoachHandShape.hand(flipped: false, angle: -55)
                .position(x: center.x + 4 + size.width / 2 - fingertip.x, y: center.y + 4 - 3 * press + size.height / 2 - fingertip.y)
        }
        .opacity(fade)
    }

    /// FT15 横划示范一轮 3 秒：从第一块划到最后一块（1.2 秒），回到第一块停着等。
    private static let swipePeriod = 3.0

    private func swipeFrame(_ p: CGFloat, end: CGRect) -> some View {
        let start = CGPoint(x: rect.minX + 6, y: rect.midY)
        let stop = CGPoint(x: end.maxX - 6, y: end.midY)
        let move: CGFloat = p < 0.1 ? 0 : p < 0.5 ? (p - 0.1) / 0.4 : p < 0.6 ? 1 : 0
        let eased = move * move * (3 - 2 * move)
        let point = CGPoint(x: start.x + (stop.x - start.x) * eased, y: start.y + (stop.y - start.y) * eased)
        let size = CoachHandShape.size, fingertip = CoachHandShape.fingertip
        return ZStack {
            if move > 0 && move < 1 || (p >= 0.5 && p < 0.6) {
                Path { path in path.move(to: start); path.addLine(to: point) }
                    .stroke(Self.rippleColor.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            CoachHandShape.hand(flipped: false)
                .position(x: point.x + size.width / 2 - fingertip.x, y: point.y + 4 + size.height / 2 - fingertip.y)
        }
    }

    /// FT6 一轮 2.6 秒：按下 → 按住 → 沿紫线往上拖到「改写」→ 停一下 → 淡出。
    private static let dragPeriod = 2.6
    private static let dragDistance: CGFloat = 42

    @ViewBuilder
    private func dragFrame(_ d: CGFloat) -> some View {
        let start = CGPoint(x: rect.midX, y: rect.midY)
        let move: CGFloat = d < 0.3 ? 0 : d < 0.65 ? (d - 0.3) / 0.35 : 1
        let eased = move * move * (3 - 2 * move)
        let point = CGPoint(x: start.x, y: start.y - Self.dragDistance * eased)
        let press: CGFloat = min(d / 0.12, 1)
        let fade: Double = d < 0.85 ? 1 : Double(1 - (d - 0.85) / 0.15)
        let holding = d >= 0.12 && d < 0.3
        ZStack {
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
            Circle()
                .fill(Color.white.opacity(0.35))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .frame(width: 34, height: 34)
                .scaleEffect(1.25 - 0.25 * press + (holding ? 0.06 * sin((d - 0.12) / 0.18 * .pi) : 0))
                .position(point)
            let size = CoachHandShape.size, fingertip = CoachHandShape.fingertip
            CoachHandShape.hand(flipped: false, angle: -55)
                .position(x: point.x + 20 + size.width / 2 - fingertip.x, y: point.y + 2 + size.height / 2 - fingertip.y)
        }
        .opacity(fade)
    }
}

// MARK: - 模拟键盘

/// App 里画的键盘：提示词一排、AI 栏、回答卡和识意框、九宫格按键；FT15 长按后按键区换成分词面板。只有小手指着的那颗能点。
private struct TourKeyboard: View {
    @ObservedObject var model: TourModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let side: CGFloat = 6

    var body: some View {
        VStack(spacing: 8) {
            if model.expanded {
                answerBlock
                    .padding(.horizontal, side + 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if model.promptsOpen {
                promptRow
                    .padding(.horizontal, side + 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // FT6 放大镜下方弹出的「问答」要盖在按键上面。
            aiBar.padding(.horizontal, side + 2).zIndex(1)
            if model.panel {
                wordPanel.padding(.horizontal, side + 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .onTapGesture { model.wrong() })
        .animation(.easeOut(duration: 0.25), value: model.expanded)
        .animation(.easeOut(duration: 0.25), value: model.promptsOpen)
    }

    // MARK: 提示词一排

    private var promptNames: [String] {
        var names = [L("润色", "Polish", "整える"), L("正式", "Formal", "丁寧"), L("口语", "Casual", "カジュアル"),
                     L("简短", "Concise", "簡潔に"), L("结构", "Bullets", "箇条書き")]
        if let custom = model.customPrompt { names.append(custom) }
        return names
    }

    private var promptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(promptNames.enumerated()), id: \.offset) { index, name in
                    pill(index, name)
                }
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GuideColor.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(TourColor.key))
                    .tourPress(.plus, model: model)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.rowFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(TourColor.ring.opacity(0.5), lineWidth: 1))
    }

    private func pill(_ index: Int, _ name: String) -> some View {
        let selected = model.selectedPrompt == index
        return HStack(spacing: 3) {
            if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            Text(name).font(.system(size: 13.5, weight: selected ? .semibold : .regular)).lineLimit(1)
        }
        .foregroundStyle(selected ? TourColor.purple : GuideColor.text)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(selected ? TourColor.pillOn : TourColor.key))
        .overlay(Capsule().strokeBorder(TourColor.ring, lineWidth: selected ? 1 : 0))
        .scaleEffect(index == 5 && model.customPop ? 0.9 : 1)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .fixedSize()
        .tourPress(.pill(index), model: model)
    }

    // MARK: AI 栏

    private var aiBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.tophalf.inset.filled")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(model.expanded ? TourColor.purple : GuideColor.text)
                .frame(width: 44, height: 34)
                .background(Capsule().fill(model.expanded ? Color(light: 0xEDEBFD, dark: 0x2E2766) : TourColor.key))
                .overlay(Capsule().strokeBorder(TourColor.ring, lineWidth: model.expanded ? 1.5 : 0))
                .tourPress(.drawer, model: model)
            if model.expanded {
                magnifier
                styleKey(answer: false)
                styleKey(answer: true)
            } else {
                joined
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Image(systemName: "arrow.uturn.backward")
                    .rotationEffect(.degrees(Double(model.undoTurns) * -180))
                    .foregroundStyle(model.undoOn ? GuideColor.text : GuideColor.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tourPress(.undo, model: model)
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1).padding(.vertical, 9)
                Image(systemName: "arrow.uturn.forward")
                    .foregroundStyle(model.redoOn ? GuideColor.text : GuideColor.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tourPress(.redo, model: model)
            }
            .font(.system(size: 14, weight: .medium))
            .frame(width: 76, height: 34)
            .background(Capsule().fill(TourColor.key))
        }
    }

    /// 收着：✨ 和「润色 ▾」合成的一颗；左边点 ✨，右边箭头开关提示词一排。名字跟着选中的提示词变。
    private var joined: some View {
        let name = promptNames[min(model.selectedPrompt, promptNames.count - 1)]
        return HStack(spacing: 0) {
            PolishStars(size: 20, running: model.sparkRunning, glowing: !reduceMotion, doneAt: model.sparkDone, tint: AIVisuals.gold)
                .frame(width: 20, height: 20)
                .padding(.trailing, 7)
                .padding(.leading, 12)
                .frame(maxHeight: .infinity)
                .tourPress(.sparkle, model: model)
            HStack(spacing: 0) {
                Text(name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                divider.padding(.horizontal, 3)
                Image(systemName: model.promptsOpen ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .padding(.trailing, 9)
            .frame(maxHeight: .infinity)
            .tourPress(.chevron, model: model)
        }
        .foregroundStyle(.white)
        .frame(height: 34)
        .background(NebulaFill(palette: .join).clipShape(Capsule()))
        .overlay {
            if model.sparkRunning {
                Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                    .blur(radius: 1)
                    .transition(.opacity)
            }
        }
        .fixedSize()
    }

    /// 展开：蓝紫混色的放大镜。FT6 按住往上拖，正上方「改写」、正下方「问答」。
    private var magnifier: some View {
        HStack(spacing: 5) {
            AskIcon().frame(width: 18, height: 18)
            Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 58, height: 34)
        .background(NebulaFill(palette: .ask).clipShape(Capsule()))
        .overlay {
            if model.generating {
                Capsule().strokeBorder(Color(hex: 0x6366F1).opacity(0.4), lineWidth: 3).padding(-3)
            }
        }
        .overlay {
            if model.step == 6 && model.target == .magnifier {
                ZStack {
                    Path { p in p.move(to: CGPoint(x: 29, y: 0)); p.addLine(to: CGPoint(x: 29, y: -24)) }
                        .stroke(TourColor.ring, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    dragOption(L("改写", "Rewrite", "書き換え"), colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], highlighted: true).offset(y: -42)
                    dragOption(L("问答", "Answer", "回答"), colors: [Color(hex: 0x0EA5E9), Color(hex: 0x38BDF8)], highlighted: false).offset(y: 42)
                }
                .frame(width: 58, height: 34)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .scaleEffect(model.pressed == .magnifier || model.dragging ? 0.96 : model.demoDown && model.target == .magnifier ? 0.98 : 1)
        .contentShape(Rectangle())
        // FT6 按住拖；别的步骤手指没怎么动就当点了一下。
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.step == 6 && model.target == .magnifier {
                    model.drag(value.translation.height, ended: false)
                } else {
                    model.pressBegan(.magnifier)
                }
            }
            .onEnded { value in
                if model.step == 6 && model.target == .magnifier {
                    model.drag(nil, ended: true)
                } else {
                    model.pressEnded(.magnifier, inside: abs(value.translation.height) < 12)
                }
            })
        .tourTarget(.magnifier)
    }

    private func dragOption(_ title: String, colors: [Color], highlighted: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle").font(.system(size: 10, weight: .bold))
            Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(width: 64, height: 30)
        .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
        .overlay(Capsule().strokeBorder(Color.white, lineWidth: highlighted && (model.dragPick || reduceMotion) ? 2 : 0))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
    }

    /// 润色 ▾（紫色）、直击要害 ▾（蓝色）；回答卡上是哪种结果，那颗亮边框加 3pt 淡外圈。
    private func styleKey(answer: Bool) -> some View {
        let active = model.activeStyle == (answer ? .answer : .rewrite)
        return HStack(spacing: 3) {
            Image(systemName: answer ? "questionmark.circle" : "pencil").font(.system(size: 14, weight: .semibold))
            Text(answer ? L("直击要害", "To the point", "要点だけ") : L("润色", "Rewrite", "書き換え")).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            divider
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.leading, 7).padding(.trailing, 6)
        .frame(height: 34)
        .background(NebulaFill(palette: answer ? .answer : .rewrite).clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(answer ? Color(hex: 0x7DD3FC) : Color(hex: 0xC4B5FD), lineWidth: active ? 1.5 : 0))
        .background(Capsule().fill((answer ? Color(hex: 0x0EA5E9) : Color(hex: 0x7C3AED)).opacity(active ? 0.25 : 0)).padding(-3))
        .animation(.easeOut(duration: 0.25), value: active)
        .fixedSize()
        .contentShape(Capsule())
        .onTapGesture { model.wrong() }
    }

    // MARK: 回答卡 + 识意框

    private var answerBlock: some View {
        HStack(spacing: 6) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .bold))
                Text(L("替换", "Replace", "置き換え")).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                Rectangle().fill(Color.white.opacity(0.5)).frame(width: 22, height: 1)
                Text(L("插入", "Insert", "挿入")).font(.system(size: 10, weight: .semibold)).opacity(0.45).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], startPoint: .top, endPoint: .bottom)))
            .opacity(model.card == nil || model.generating ? 0.45 : 1)
            .tourPress(.replace, model: model)
            VStack(spacing: 0) {
                cardTop
                    .frame(height: 62)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.45) {
                        if model.target == .card { TourModel.haptic(); model.tap(.card) } else { model.wrong() }
                    }
                    .tourTarget(.card)
                Rectangle().fill(TourColor.askLine).frame(height: 1)
                askRow.frame(height: 40)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(model.cardMode == .answer ? TourColor.answerRing : TourColor.ring, lineWidth: 1.5))
            .animation(.easeInOut(duration: 0.25), value: model.cardMode)
        }
        .frame(height: 103)
    }

    private var cardTop: some View {
        HStack(alignment: .top, spacing: 8) {
            if model.cardMode != nil, !model.generating { modeBlock.transition(.opacity) }
            Group {
                if model.generating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text(L("生成中…", "Generating…", "生成中…")).foregroundStyle(TourColor.purple)
                    }
                } else if model.searching {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .foregroundStyle(Color(hex: 0x0369A1))
                            .rotationEffect(.degrees(reduceMotion ? 0 : 360))
                            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: model.searching)
                        Text(L("正在用 Kimi 联网搜索…", "Searching the web with Kimi…", "Kimi でウェブを検索しています…")).foregroundStyle(Color(hex: 0x0369A1))
                    }
                } else if let card = model.card {
                    Text(card).foregroundStyle(GuideColor.text).lineLimit(2)
                } else {
                    Text(L("结果会出现在这里", "The result shows here", "結果はここに表示されます")).foregroundStyle(GuideColor.secondary.opacity(0.7))
                }
            }
            .font(.system(size: 14.5))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if model.card != nil, !model.generating {
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

    /// 左边模式块：上半「AI问答 / AI改写」，下半「⇄ 切换」；切换时上下翻一下。
    private var modeBlock: some View {
        let answer = model.cardMode == .answer
        let text = answer ? Color(light: 0x0369A1, dark: 0x7DD3FC) : Color(light: 0x4A3BD6, dark: 0xB4A9FF)
        let fill = answer ? Color(light: 0xE0F2FE, dark: 0x0C3448) : Color(light: 0xECEAFD, dark: 0x2E2766)
        return VStack(spacing: 0) {
            Text(answer ? L("AI问答", "AI Q&A", "AI回答") : L("AI改写", "AI edit", "AI書換")).font(.system(size: 10, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotation3DEffect(.degrees(answer ? 0 : 360), axis: (x: 1, y: 0, z: 0))
            Rectangle().fill(text.opacity(0.25)).frame(height: 0.5)
            Text("⇄" + L("切换", "Switch", "切替")).font(.system(size: 10, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tourPress(.switchMode, model: model)
        }
        .foregroundStyle(text)
        .frame(width: 42, height: 46)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(text.opacity(0.3), lineWidth: 0.5))
    }

    /// 识意框（激活：紫色光标）；FT14 右边「使用联网查询」，联网后灰字「已联网 · Kimi」。
    private var askRow: some View {
        HStack(spacing: 8) {
            (Text(model.ask) + Text("▏").foregroundColor(TourColor.caret))
                .font(.system(size: 15))
                .foregroundStyle(GuideColor.text)
                .lineLimit(1)
                .truncationMode(.head)
                // FT11 小手指着「切换」、FT6 放大镜正上方冒出「改写」气泡：字往右让开，不被挡住。
                .padding(.leading, model.target == .switchMode ? 64 : model.step == 6 && model.target == .magnifier ? 120 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.searched {
                Label(L("已联网 · Kimi", "Searched · Kimi", "検索済み · Kimi"), systemImage: "globe")
                    .font(.system(size: 12)).foregroundStyle(GuideColor.secondary).fixedSize()
                    .transition(.opacity)
            } else if model.canSearch {
                Label(L("使用联网查询", "Search the web", "ウェブで調べる"), systemImage: "globe")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0369A1))
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(Color(light: 0xE0F2FE, dark: 0x0C3448)))
                    .overlay(Capsule().strokeBorder(TourColor.answerRing.opacity(0.4), lineWidth: 1))
                    .fixedSize()
                    .tourPress(.search, model: model)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: 按键

    private var keys: some View {
        let gap: CGFloat = 6, height: CGFloat = 42
        return HStack(alignment: .top, spacing: gap) {
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                keyRow(["123", "，。?!", "ABC", "DEF"], height: height)
                keyRow(["#@¥", "GHI", "JKL", "MNO"], height: height)
                keyRow([L("常用", "Saved", "定型"), "PQRS", "TUV", "WXYZ"], height: height)
                GridRow {
                    key(Image(systemName: "face.smiling"), height: height)
                    key(Text(L("中/英", "中/EN", "中/英")), height: height)
                    key(Text(L("空 格", "space", "空白")), height: height).gridCellColumns(2)
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
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(GuideColor.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.key)
                .shadow(color: .black.opacity(0.12), radius: 0, y: 1))
            .contentShape(Rectangle())
            .onTapGesture { model.wrong() }
    }

    @ViewBuilder
    private var returnKey: some View {
        if model.sendReady {
            Text(L("发送", "Send", "送信"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.purple))
                .tourPress(.send, model: model)
                .transition(.opacity)
        } else if model.expanded {
            VStack(spacing: 4) {
                Text(L("改写", "Edit", "修正")).font(.system(size: 10, weight: .semibold)).opacity(0.75)
                Text(L("执行", "Go", "実行")).font(.system(size: 16, weight: .bold))
                Text(L("问答", "Q&A", "質問")).font(.system(size: 10, weight: .semibold)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NebulaFill(palette: .ask).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
            .contentShape(Rectangle())
            .onTapGesture { model.wrong() }
        } else {
            Image(systemName: "return")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TourColor.purple)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.returnFill))
                .contentShape(Rectangle())
                .onTapGesture { model.wrong() }
        }
    }

    // MARK: 分词面板（FT15）

    private var wordPanel: some View {
        let script = model.script
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("已选 \(model.picked.count) 个", "\(model.picked.count) selected", "\(model.picked.count) 個選択"))
                    .font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                Spacer()
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(script.words.enumerated()), id: \.offset) { index, word in
                    wordChip(index, word, hint: script.hints.contains(index) && model.picked.isEmpty, script: script)
                }
            }
            .coordinateSpace(name: "tourWords")
            .onPreferenceChange(TourWordFramesKey.self) { wordFrames = $0 }
            .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("tourWords"))
                .onChanged { value in
                    if let hit = wordFrames.first(where: { $0.value.contains(value.location) })?.key {
                        model.toggleWord(hit, on: true)
                    }
                })
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                Label(L("插入", "Insert", "挿入"), systemImage: "text.insert")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .opacity(model.picked.isEmpty ? 0.45 : 1)
                    .tourPress(.insert, model: model)
                Label(L("复制", "Copy", "コピー"), systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x0E9F6E)))
                    .opacity(model.picked.isEmpty ? 0.45 : 1)
                    .onTapGesture { model.wrong() }
                Text(L("全选", "All", "全選択")).font(.system(size: 14, weight: .semibold)).foregroundStyle(GuideColor.text)
                    .frame(width: 64, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TourColor.key))
                    .onTapGesture { model.selectAll() }
            }
        }
        .padding(10)
        .frame(height: 4 * 42 + 3 * 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(light: 0xF1F0FA, dark: 0x232325)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TourColor.ring.opacity(0.4), lineWidth: 1))
    }

    @State private var wordFrames: [Int: CGRect] = [:]

    private func wordChip(_ index: Int, _ word: String, hint: Bool, script: TourScript) -> some View {
        let picked = model.picked.contains(index)
        return Text(word)
            .font(.system(size: 14))
            .foregroundStyle(picked ? Color.white : GuideColor.text)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(picked ? TourColor.purple : TourColor.key))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(TourColor.purple, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .opacity(hint ? 1 : 0))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: TourWordFramesKey.self, value: [index: proxy.frame(in: .named("tourWords"))])
            })
            .onTapGesture { model.toggleWord(index) }
            .modifier(TourWordAnchor(index: index, hints: script.hints))
    }
}

private struct TourWordFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 虚线框的第一块、最后一块给小手定位。
private struct TourWordAnchor: ViewModifier {
    var index: Int
    var hints: [Int]

    func body(content: Content) -> some View {
        if index == hints.first {
            content.tourTarget(.words)
        } else if index == hints.last {
            content.tourTarget(.wordsEnd)
        } else {
            content
        }
    }
}

// MARK: - 添加提示词（FT8）

/// 真键盘的「＋」会跳去 App；演示里从下面升起半屏卡，样式照 App「编辑提示词」页，只留名称和内容两栏。
private struct TourAddSheet: View {
    @ObservedObject var model: TourModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            HStack {
                Text(L("取消", "Cancel", "キャンセル")).font(.system(size: 16)).foregroundStyle(GuideColor.secondary)
                    .onTapGesture { model.wrong() }
                Spacer()
                Text(L("添加提示词", "Add Prompt", "プロンプトを追加")).font(.system(size: 17, weight: .semibold)).foregroundStyle(GuideColor.text)
                Spacer()
                Text(L("添加", "Add", "追加"))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(TourColor.purple))
                    .tourPress(.add, model: model)
            }
            .padding(.vertical, 6)
            Text(L("名称", "Name", "名前")).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
            TextField("", text: $model.sheetName)
                .font(.system(size: 17))
                .padding(.horizontal, 14).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.field))
            Text(L("显示在键盘 ✨ 旁边，四个字以内最好。", "Shows next to ✨ on the keyboard. Keep it short.", "キーボードの ✨ の横に表示されます。短めがおすすめです。"))
                .font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary)
            Text(L("提示词内容", "Prompt", "プロンプトの内容")).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                .padding(.top, 4)
            TextField("", text: $model.sheetContent, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(3...5)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.field))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(TourColor.purple, lineWidth: 1.5))
            Text(L("写清楚场景和要求，每次点 ✨ 都会带上。演示里添加的提示词不会保存。",
                   "Describe the situation and what you want; it's sent every time you tap ✨. Prompts added in the demo aren't saved.",
                   "場面と要望をはっきり書くと、✨ のたびに一緒に送られます。デモで追加したプロンプトは保存されません。"))
                .font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TopRounded(radius: 22).fill(GuideColor.card).ignoresSafeArea(edges: .bottom))
    }
}

/// 键盘顶部的圆角，底边直角。
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
