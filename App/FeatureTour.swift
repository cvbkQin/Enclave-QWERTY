import SwiftUI

// 功能演示（T95，design/onboard-v2，对齐清单第 90 条）：隐私同意之后、设置三步之前，在 App 里画的模拟键盘上把功能点一遍。
// 6 章 16 步：润色 2、帮回 3、按要求改 2、问答 3、润色风格 3、打字 3。键盘按首页选的布局画（九宫格 / 全键盘）。
// 结果全是预设内容：不调用 API、不联网、不扣次数、不计入统计；演示里加的风格不写进真的风格列表。
// 触点只做示范；用户自己点对了才往下走，点别处轻晃。每章第一步前有章节过场。
// 这个文件：章节、步骤文案、剧本（三种语言）、状态机。页面在 FeatureTourPages.swift，模拟键盘在 TourKeyboard.swift。

enum FeatureTour {
    private static let seenKey = "featureTour.seen"

    /// 走完或跳过都记下，以后不再自动弹（存在 App Group）。
    static var seen: Bool {
        get { SharedStorage.defaults.bool(forKey: seenKey) }
        set { SharedStorage.defaults.set(newValue, forKey: seenKey) }
    }

    /// 全部步数。
    static let stepCount = 16
}

// MARK: - 章节

enum TourChapter: Int, CaseIterable, Hashable, Identifiable {
    case polish, helpReply, request, answer, style, typing

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .polish: return L("润色", "Polish", "整える")
        case .helpReply: return L("帮回", "Help Reply", "返信アシスト")
        case .request: return L("按要求改", "Rewrite on Request", "指示で書き換え")
        case .answer: return L("问答", "Ask", "質問")
        case .style: return L("润色风格", "Polish Styles", "整えるスタイル")
        case .typing: return L("打字", "Typing", "入力")
        }
    }

    /// 首页章节列表和章节过场共用的副标题。
    var subtitle: String {
        switch self {
        case .polish: return L("随手打的话，一点变得体", "Quick notes, made polished in one tap", "思いつきの文が、ワンタップで整う")
        case .helpReply: return L("复制对方的话，回复随即拟好", "Copy their message, get a reply drafted", "相手の言葉をコピーすると、返信が用意される")
        case .request: return L("说一句要求，照你的意思改", "Say what you want, get it rewritten", "ひと言指示すれば、そのとおりに書き換え")
        case .answer: return L("不离开键盘，直接得到答案", "Get answers without leaving the keyboard", "キーボードのまま答えが手に入る")
        case .style: return L("定下你的语气，一点套用", "Set your tone, apply it in one tap", "自分の口調を決めて、ワンタップで適用")
        case .typing: return L("标点、声调与光标，尽在指尖", "Punctuation, accents and the cursor at your fingertips", "句読点・アクセント・カーソルも指先で")
        }
    }

    /// SF Symbols：润色、按要求改、润色风格紫，帮回绿，问答蓝，打字灰（和历史里的小方块一样）。
    var symbol: String {
        switch self {
        case .polish: return "sparkles"
        case .helpReply: return "arrowshape.turn.up.left"
        case .request: return "pencil"
        case .answer: return "questionmark.bubble"
        case .style: return "slider.horizontal.3"
        case .typing: return "keyboard"
        }
    }

    /// 小方块的底色（功能识别色，DESIGN.md 第一节）。
    var color: Color {
        switch self {
        case .polish, .request, .style: return Color(hex: 0x5B4BE8)
        case .helpReply: return Color(hex: 0x34A853)
        case .answer: return Color(hex: 0x007AFF)
        case .typing: return Color(.systemGray)
        }
    }

    /// 这一章在全部 16 步里的范围。
    var steps: ClosedRange<Int> {
        switch self {
        case .polish: return 1...2
        case .helpReply: return 3...5
        case .request: return 6...7
        case .answer: return 8...10
        case .style: return 11...13
        case .typing: return 14...16
        }
    }

    var stepCount: Int { steps.count }

    static func of(_ step: Int) -> TourChapter {
        allCases.first { $0.steps.contains(step) } ?? .polish
    }
}

/// 章节小方块：功能色底、白色 SF Symbol。首页 30、步骤页 22、章节过场 76（圆角 18）。
struct TourChapterIcon: View {
    let chapter: TourChapter
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: chapter.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size >= 60 ? 18 : size * 0.24, style: .continuous).fill(chapter.color))
            .accessibilityHidden(true)
    }
}

// MARK: - 步骤文案

/// 一步的标题和说明（第三节）。标题说结果，说明先说怎么做、再说得到什么；按钮名加「」。打字一章按布局分两套。
struct TourStepText {
    var title: String
    var detail: String

    static func of(_ step: Int, layout: KeyboardLayout) -> TourStepText {
        let nine = layout == .nineKey
        switch step {
        case 1: return TourStepText(
            title: L("一点，整句通顺", "One tap, and it reads well", "ワンタップで自然な文に"),
            detail: L("随手打的一句。点「润色」，语序和标点一并理顺。",
                      "A quick note, typed as it came. Tap \"Polish\" to fix the word order and punctuation together.",
                      "思いつくまま打った一文。「整える」をタップすると、語順も句読点もまとめて整います。"))
        case 2: return TourStepText(
            title: L("不满意，随时撤回", "Not quite right? Undo anytime", "気に入らなければ、すぐ戻せる"),
            detail: L("点 ↶ 回到原文，点 ↷ 再改回来。满意了就发出。",
                      "Tap ↶ to go back to the original and ↷ to bring the change back. Send it when you're happy.",
                      "↶ で元の文に、↷ で整えた文に戻ります。納得したら送信します。"))
        case 3: return TourStepText(
            title: L("先复制对方的话", "First, copy their message", "まず相手の言葉をコピー"),
            detail: L("长按小林这句，选「拷贝」。", "Touch and hold Alex's message, then choose \"Copy\".", "佐藤さんのメッセージを長押しして、「コピー」を選びます。"))
        case 4: return TourStepText(
            title: L("回复，已为你拟好", "Your reply, already drafted", "返信は、もう用意できています"),
            detail: L("复制之后，问答右边弹出「帮回」。点一下，按你的语气拟好回复。",
                      "After you copy, \"Reply\" pops up next to Ask. Tap it to draft a reply in your tone.",
                      "コピーすると、「質問」の右に「返信」が出ます。タップすると、あなたの口調で返信を用意します。"))
        case 5: return TourStepText(
            title: L("补一句要求，重写一版", "Add a request, get a new version", "ひと言足して、もう一度"),
            detail: L("在回复下方的框里写下要求，点「润色」重新生成。满意后「替换」发出。",
                      "Write a request in the box below the reply, then tap \"Polish\" to write it again. Tap \"Replace\" and send when you're happy.",
                      "返信の下の欄に指示を書き、「整える」で書き直します。納得したら「置換」して送信します。"))
        case 6: return TourStepText(
            title: L("说出你的要求", "Say what you want", "指示を伝える"),
            detail: L("展开回答卡，在下方写下想怎么改。", "Open the answer card and write how you want it changed in the box below.", "回答カードを開いて、下の欄にどう直すかを書きます。"))
        case 7: return TourStepText(
            title: L("照你的意思改好", "Rewritten your way", "指示どおりに書き換え"),
            detail: L("点「润色」，按要求改写。「替换」换掉原文；按住「替换」上滑则插入。",
                      "Tap \"Polish\" to rewrite it as asked. \"Replace\" swaps out your text; hold \"Replace\" and slide up to insert instead.",
                      "「整える」で指示どおりに書き換えます。「置換」で元の文と入れ替え、「置換」を長押しして上にスライドすると挿入します。"))
        case 8: return TourStepText(
            title: L("有问题，直接问", "Got a question? Just ask", "知りたいことは、そのまま質問"),
            detail: L("在框里写下问题，点「问答」即得答案。", "Write your question in the box and tap \"Ask\" for the answer.", "欄に質問を書いて「質問」をタップすると、答えが出ます。"))
        case 9: return TourStepText(
            title: L("联网，答案更新", "Search the web for fresher answers", "ウェブ検索で、最新の答え"),
            detail: L("需要最新信息时，点「使用联网查询」重新作答。", "When you need the latest information, tap \"Search the web\" to answer again.", "最新の情報が必要なときは、「ウェブで調べる」で答え直します。"))
        case 10: return TourStepText(
            title: L("只取你要的词", "Take just the words you need", "必要な言葉だけ使う"),
            detail: L("长按答案，点选需要的词，再点「插入」。", "Touch and hold the answer, tap the words you need, then tap \"Insert\".", "答えを長押しし、必要な言葉を選んで「挿入」をタップします。"))
        case 11: return TourStepText(
            title: L("换一种语气", "Try a different tone", "口調を変える"),
            detail: L("点润色键旁的 ⌄，选「简短」。同一句话，换个说法。",
                      "Tap the ⌄ next to the Polish key and choose \"Concise\". Same message, said another way.",
                      "整えるキーの横の ⌄ から「簡潔に」を選びます。同じ内容を、別の言い方に。"))
        case 12: return TourStepText(
            title: L("定制你的风格", "Make your own style", "自分のスタイルを作る"),
            detail: L("新建一个「英文」风格，AI 帮你把要求写清楚。问答键的 ⌄ 同样可以换风格。",
                      "Create a \"Chinese\" style and let AI write the instructions clearly. The Ask key's ⌄ lets you switch styles too.",
                      "「英語」スタイルを新しく作り、AI に指示をわかりやすく書いてもらいます。質問キーの ⌄ でもスタイルを切り替えられます。"))
        case 13: return TourStepText(
            title: L("钉在手边", "Keep it within reach", "手元に固定"),
            detail: L("点图钉，「英文」出现在 AI 栏，一点即用。", "Tap the pin and \"Chinese\" appears on the AI bar, ready in one tap.", "ピンをタップすると「英語」が AI バーに出て、ワンタップで使えます。"))
        case 14: return nine
            ? TourStepText(title: L("滑一下，出标点", "Swipe for punctuation", "スワイプで句読点"),
                           detail: L("按住「，。?!」，上滑句号，右滑问号，下滑叹号，左滑逗号。",
                                     "Hold \"，。?!\" and swipe up for a period, right for a question mark, down for an exclamation mark, left for a comma.",
                                     "「，。?!」を押したまま、上で句点、右で疑問符、下で感嘆符、左で読点。"))
            : TourStepText(title: L("长按，挑标点", "Hold to pick punctuation", "長押しで句読点を選ぶ"),
                           detail: L("按住「，。」不动，松手是逗号；左右滑动，挑问号、句号等。",
                                     "Hold \"，。\" and let go for a comma, or slide left or right for a question mark, period and more.",
                                     "「，。」を押したまま離すと読点。左右にスライドすると疑問符や句点などを選べます。"))
        case 15: return nine
            ? TourStepText(title: L("滑一下，出字母", "Swipe for a letter", "スワイプで文字"),
                           detail: L("按住 DEF，左滑 D，上滑 E，右滑 F。", "Hold DEF and swipe left for D, up for E, right for F.", "DEF を押したまま、左で D、上で E、右で F。"))
            : TourStepText(title: L("长按，带声调", "Hold for accents", "長押しでアクセント"),
                           detail: L("按住 e，右滑选 ē é ě è ê，左滑是 3。", "Hold e and slide right for é è ê ë ē, or left for 3.", "e を押したまま右にスライドで é è ê ë ē、左で 3。"))
        default: return nine
            ? TourStepText(title: L("常用语与剪贴板", "Saved phrases and clipboard", "定型文とクリップボード"),
                           detail: L("点「常用 / 剪贴板」，左边常用语，右边最近拷贝的内容，点一条即上屏。",
                                     "Tap \"Saved / Clipboard\": saved phrases on the left, recent copies on the right. Tap one to enter it.",
                                     "「定型 / クリップボード」をタップ。左に定型文、右に最近コピーしたもの。タップすると入力されます。"))
            : TourStepText(title: L("按住空格，移动光标", "Hold space to move the cursor", "スペース長押しでカーソル移動"),
                           detail: L("键盘变为触控板，左右滑动即可移动光标。", "The keyboard turns into a trackpad. Slide left or right to move the cursor.",
                                     "キーボードがトラックパッドになり、左右にスライドするとカーソルが動きます。"))
        }
    }
}

// MARK: - 剧本

/// 和同事（中文：小林）一段连着的对话，三种界面语言各一套。改写的目标语言：中文、日文版翻成英文，英文版翻成中文。
struct TourScript {
    var contact: String
    var avatar: String
    var placeholder: String
    /// 演示开头对方已经发来的一句。
    var opener: String
    /// 润色：随手打的、润色后的。
    var original: String
    var polished: String
    /// 帮回：对方问的、第一版、补的要求、第二版。
    var helpMessage: String
    var helpReply: String
    var helpAsk: String
    var helpReply2: String
    /// 按要求改：对方托的事（输入框预填同一句）、要求、结果。
    var requestMessage: String
    var requestAsk: String
    var requestResult: String
    /// 问答：对方问的、识意框里的问题、未联网的回答、联网的回答、分词面板里的词和虚线框提示的几块。
    var foodMessage: String
    var foodAsk: String
    var foodAnswer: String
    var foodWeb: String
    var words: [String]
    var hints: [Int]
    /// 插入时词和词之间放什么。
    var joiner: String
    /// 润色风格：对方的话、随手打的、「简短」之后、新风格的名字、建议标签、AI 优化后的内容、「英文」之后。
    var styleMessage: String
    var styleField: String
    var styleShort: String
    var promptName: String
    var tags: [String]
    var improvedContent: String
    var styleTranslated: String
    /// 打字：对方的话、输入框里已经打好的、常用语、剪贴板。
    var typingMessage: String
    var typingField: String
    var phrases: [String]
    var clips: [String]
    /// 打字一章用中文标点（中文、日文界面）还是英文标点。
    var chinesePunct: Bool

    /// 选中的词连起来：标点那几块不要。
    func join(_ picked: [Int]) -> String {
        picked.sorted().map { words[$0] }
            .filter { word in !word.allSatisfy { $0.isPunctuation || $0 == "·" } }
            .joined(separator: joiner)
    }

    /// 没自己选时（返回、单看后面的章）发出去的词：虚线框那几块。
    var hintWords: String { join(hints) }

    static var current: TourScript {
        switch Loc.current {
        case .en: return en
        case .ja: return ja
        case .zh, .system: return zh
        }
    }

    static let zh = TourScript(
        contact: "小林", avatar: "林", placeholder: "回复 小林",
        opener: "明早九点开周会，记得准时到哦。",
        original: "明天的会我晚点到 要先送孩子 你们先开始吧",
        polished: "明天的会我会晚一点到，要先送孩子上学，你们先开始就好。",
        helpMessage: "没问题。对了，周五团建你去吗？",
        helpReply: "去的！周五见，要我带点什么吗？",
        helpAsk: "再热情一点",
        helpReply2: "去呀！好期待周五～要我带点零食过去吗？",
        requestMessage: "帮我跟 Alex 说一声，会议改到下午三点，地点不变。",
        requestAsk: "翻成英文",
        requestResult: "The meeting has been moved to 3 p.m. Same place.",
        foodMessage: "团建在上海，有什么必吃的？",
        foodAsk: "上海有什么必吃的美食",
        foodAnswer: "上海菜偏甜，浓油赤酱。常被推荐的有生煎、蟹粉小笼、葱油拌面、红烧肉。具体去哪家、最近口碑如何，可以联网查一下。",
        foodWeb: "最近口碑好的：早餐吃生煎、蟹粉小笼，豫园、黄河路一带最集中；本帮菜点红烧肉、油爆虾、腌笃鲜；小吃试试葱油拌面。热门老店饭点要排队，建议错峰去。",
        words: ["早餐", "吃", "生煎", "、", "蟹粉小笼", "，", "豫园", "、", "黄河路", "一带", "最集中", "；", "本帮菜", "点", "红烧肉", "、",
                "油爆虾", "、", "腌笃鲜", "；", "小吃", "试试", "葱油拌面", "。", "热门", "老店", "饭点", "要排队", "，", "错峰去"],
        hints: [2, 4], joiner: "、",
        styleMessage: "周五记得带伞，天气预报说有雨。",
        styleField: "好的我知道了 到时候我会带伞的 谢谢你提醒我",
        styleShort: "好，会带伞，谢谢提醒。",
        promptName: "英文",
        tags: ["翻成英文", "保持原意", "语气礼貌", "适合发微信", "不加新内容", "语气轻松", "适合发邮件", "先说结论"],
        improvedContent: "把输入的中文翻成自然、地道的英文。保持原意，不增不减，语气和原文一致；只输出译文。",
        styleTranslated: "OK, I'll bring an umbrella. Thanks for the reminder!",
        typingMessage: "周五下午三点，楼下集合",
        typingField: "收到",
        phrases: ["好的，马上到", "收到，谢谢", "在开会，稍后回复"],
        clips: ["周五下午三点，楼下集合", "上海市黄浦区豫园路 85 号", "The meeting has been moved to 3 p.m."],
        chinesePunct: true)

    static let en = TourScript(
        contact: "Alex", avatar: "A", placeholder: "Reply to Alex",
        opener: "Team meeting at 9 tomorrow, please be on time.",
        original: "ill be late tmrw gotta drop off my kid first start without me",
        polished: "I'll be a little late tomorrow, as I need to drop my kid off at school first. Please start without me.",
        helpMessage: "No problem. By the way, are you coming to the team outing on Friday?",
        helpReply: "Count me in! See you Friday. Should I bring anything?",
        helpAsk: "More excited",
        helpReply2: "Absolutely! Can't wait for Friday. Want me to bring some snacks?",
        requestMessage: "Can you tell Wang Lei the meeting moved to 3 p.m.? Same place.",
        requestAsk: "Translate into Chinese",
        requestResult: "会议改到下午三点，地点不变。",
        foodMessage: "The outing is in Shanghai. Any must-try food?",
        foodAsk: "must-try food in Shanghai",
        foodAnswer: "Shanghai food leans sweet and rich. Often recommended: shengjian buns, crab xiaolongbao, scallion oil noodles and red-braised pork. For where to go and recent reviews, try searching the web.",
        foodWeb: "Well reviewed lately: shengjian buns and crab xiaolongbao for breakfast, mostly around Yuyuan and Huanghe Road; red-braised pork and oil-fried shrimp for local dishes; scallion oil noodles as a snack. Popular shops queue at mealtimes, so go off-peak.",
        words: ["shengjian buns", "and", "crab xiaolongbao", "for breakfast", ",", "around", "Yuyuan", "and", "Huanghe Road", ";", "red-braised pork",
                "and", "oil-fried shrimp", ";", "scallion oil noodles", "as a snack", ".", "Popular shops", "queue", "at mealtimes", ",", "go off-peak"],
        hints: [0, 2], joiner: ", ",
        styleMessage: "Bring an umbrella on Friday, rain is in the forecast.",
        styleField: "ok got it ill bring an umbrella then thanks for reminding me",
        styleShort: "OK, I'll bring one. Thanks!",
        promptName: "Chinese",
        tags: ["Translate into Chinese", "Keep the meaning", "Polite tone", "For chat apps", "No new content", "Casual tone", "For email", "Lead with the point"],
        improvedContent: "Translate the input into natural, idiomatic Chinese. Keep the meaning without adding or removing anything, match the original tone, and output only the translation.",
        styleTranslated: "好的，我会带伞，谢谢提醒！",
        typingMessage: "Friday 3 p.m., meet downstairs.",
        typingField: "Got it",
        phrases: ["On my way", "Got it, thanks", "In a meeting, will reply later"],
        clips: ["Friday 3 p.m., meet downstairs.", "85 Yuyuan Road, Huangpu, Shanghai", "会议改到下午三点，地点不变。"],
        chinesePunct: false)

    static let ja = TourScript(
        contact: "佐藤さん", avatar: "佐", placeholder: "佐藤さんに返信",
        opener: "明日 9 時から定例です。遅れないようにお願いします。",
        original: "明日の会議ちょっと遅れる 子ども送ってから行く 先に始めてて",
        polished: "明日の会議は少し遅れます。子どもを学校に送ってから向かいますので、先に始めていてください。",
        helpMessage: "了解です。ところで、金曜のチームイベントは来ますか？",
        helpReply: "行きます！金曜日、楽しみにしています。何か持っていきましょうか？",
        helpAsk: "もっと元気に",
        helpReply2: "もちろん行きます！金曜が待ちきれません～お菓子でも持っていきましょうか？",
        requestMessage: "Alex に、会議は午後 3 時に変更、場所は同じと伝えてもらえますか？",
        requestAsk: "英語に翻訳",
        requestResult: "The meeting has been moved to 3 p.m. Same place.",
        foodMessage: "イベントは上海です。絶対食べるべきものは？",
        foodAsk: "上海で絶対食べたいもの",
        foodAnswer: "上海料理は甘めで濃い味付けです。生煎（焼き小籠包）、蟹みそ小籠包、葱油拌麺、紅焼肉がよくすすめられます。どの店がいいかは、ウェブで調べてみてください。",
        foodWeb: "最近評判のいいもの：朝は生煎と蟹みそ小籠包で、豫園や黄河路あたりに多いです。上海料理なら紅焼肉と油爆蝦、軽食なら葱油拌麺。人気店は食事時に並ぶので、時間をずらすのがおすすめです。",
        words: ["朝は", "生煎", "と", "蟹みそ小籠包", "で", "、", "豫園", "や", "黄河路", "あたり", "に多い", "。", "上海料理", "なら", "紅焼肉", "と",
                "油爆蝦", "、", "軽食", "なら", "葱油拌麺", "。", "人気店", "は", "食事時に", "並ぶ", "ので", "時間を", "ずらして"],
        hints: [1, 3], joiner: "、",
        styleMessage: "金曜は雨の予報なので、傘を忘れずに。",
        styleField: "わかった 当日は傘持っていくね 教えてくれてありがとう",
        styleShort: "了解、傘を持っていきます。ありがとう！",
        promptName: "英語",
        tags: ["英語に翻訳", "意味はそのまま", "丁寧な口調", "チャット向け", "内容を足さない", "気軽な口調", "メール向け", "結論から"],
        improvedContent: "入力された文章を自然で正確な英語に翻訳。意味はそのまま、足したり削ったりせず、口調も原文に合わせる。訳文だけを出力。",
        styleTranslated: "Got it, I'll bring an umbrella. Thanks for the reminder!",
        typingMessage: "金曜 15 時、下に集合",
        typingField: "了解",
        phrases: ["すぐ行きます", "了解、ありがとう", "会議中なので後で返信します"],
        clips: ["金曜 15 時、下に集合", "上海市黄浦区豫園路 85 号", "The meeting has been moved to 3 p.m."],
        chinesePunct: true)
}

// MARK: - 能点的地方

/// 触点能指的地方，也是能点的地方。
enum TourTarget: Hashable {
    /// AI 栏：润色键名字那半边、润色键的 ⌄、问答键、弹出的帮回键、▭、撤销重做、固定的「英文」。
    case sparkle, chevron, askKey, helpKey, drawer, undo, redo, pinned
    /// 回答卡：替换键、结果卡（长按出分词）、识意框、「使用联网查询」；分词面板虚线框那一块、「插入」。
    case replace, card, askField, search, words, insert
    /// 回车位的「发送」。
    case send
    /// 对话：长按对方那条、编辑菜单里的「拷贝」。
    case peerBubble, copy
    /// 润色风格下拉：某一条、某一条的图钉、最底下「＋」。
    case pill(Int), pin(Int), addStyle
    /// 模拟的 App 风格页：建议标签、「AI 优化」、「完成」。
    case tag(Int), improve, done
    /// 打字：按住「，。」（九宫格「，。?!」）、按住 e（九宫格 DEF）、按住空格、「常用 / 剪贴板」、面板里的一条。
    case punct, letter, space, clipKey, clipItem

    /// 触点怎么示范：点一下、按住、按住再滑。
    enum Gesture { case tap, hold, slide }

    var gesture: Gesture {
        switch self {
        case .peerBubble, .card: return .hold
        case .punct, .letter, .space: return .slide
        default: return .tap
        }
    }
}

// MARK: - 状态机

/// 演示用的「接口」和键盘状态：照剧本一段段出字、打字、删字。所有动画都能被跳过、返回打断。
@MainActor
final class TourModel: ObservableObject {
    enum Page: Equatable { case welcome, interlude(TourChapter), step, finished, exit }
    enum CardMode: Equatable { case rewrite, answer, help }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var mine = false
        var typing = false
        /// 旁边的「已拷贝」。
        var copied = false
    }

    /// 回答卡里的一版：帮回第 3 步补了要求后有两版，右边「2/2」能翻。
    struct Version: Equatable {
        var text: String
        var mode: CardMode
    }

    /// 打字一章按住键弹出来的：一排（全键盘）或十字（九宫格）。
    struct Popup: Equatable {
        enum Kind: Equatable { case row(AlternatesRow), cross([CrossArm: String], center: String) }
        var kind: Kind
        /// 弹出时那颗键在键盘里的位置。
        var key: CGRect
        /// 一排：现在选中第几格（从左数）；十字：选中的方向（nil 是中间，松手不打）。
        var index = 0
        var arm: CrossArm?
    }

    enum CrossArm: CaseIterable, Hashable { case left, up, right, down }

    let script = TourScript.current
    var reduceMotion = false
    /// 从设置里看（单看一章或从头播放）：放完回章节页，没有完成页。
    var replay = false

    @Published var layout: KeyboardLayout = .qwerty
    /// 这次放哪几步（全部 16 步，或者某一章）。
    @Published private(set) var plan: [Int] = Array(1...FeatureTour.stepCount)
    @Published private(set) var position = 0
    @Published var page: Page = .welcome

    var step: Int { plan.indices.contains(position) ? plan[position] : 1 }
    var chapter: TourChapter { TourChapter.of(step) }
    /// 进度条：这一步放完算到哪。
    var progress: Double { Double(position + 1) / Double(max(plan.count, 1)) }

    /// 正在等用户点哪一处；nil 时触点不出来。
    @Published var target: TourTarget?
    /// 用户手指按着的那一处。
    @Published var pressed: TourTarget?
    /// 触点示范按下、按住时往旁边滑了多少（0…1）。
    @Published var demoDown = false
    @Published var demoSlide: CGFloat = 0
    @Published var shakes = 0

    // 对话和宿主输入框
    @Published var messages: [Message] = []
    @Published var field = ""
    /// 输入框里的字是 AI 刚写进去的：逐字浮现（从这一刻开始，每字多少秒）。
    @Published var fieldStream: (start: Date, perChar: Double)?
    @Published var fieldDim = false
    /// 光标离末尾几个字（全键盘按住空格挪光标）。
    @Published var caretBack = 0
    @Published var sendReady = false
    /// 长按对方那条：描边、上面弹出编辑菜单。
    @Published var bubbleMenu = false

    // 回答卡和识意框
    @Published var expanded = false
    @Published var versions: [Version] = []
    @Published var versionIndex = 0
    @Published var cardStream: (start: Date, perChar: Double)?
    @Published var generating = false
    /// 帮回第 3 步：卡头「AI 正在改写…」，上一版虚掉。
    @Published var regenerating = false
    @Published var cardTall = false
    @Published var ask = ""
    @Published var askEditing = false
    /// 重新生成后，留在识意框里的要求变灰。
    @Published var askDim = false
    @Published var canSearch = false
    @Published var searching = false
    @Published var searched = false
    @Published var panel = false
    @Published var picked: Set<Int> = []

    // AI 栏
    @Published var sparkRunning = false
    @Published var sparkDone: Date?
    @Published var askRunning = false
    @Published var askDone: Date?
    @Published var helpShown = false
    @Published var helpRunning = false
    @Published var helpDone: Date?
    @Published var undoOn = false
    @Published var redoOn = false
    @Published var undoTurns = 0

    // 润色风格
    @Published var promptsOpen = false
    @Published var selectedPrompt = 0
    @Published var customPrompt: String?
    @Published var pinnedCustom = false
    @Published var pinRunning = false
    @Published var pinDone: Date?
    @Published var appPage = false
    @Published var sheetName = ""
    @Published var sheetContent = ""
    @Published var pickedTags: Set<Int> = []
    @Published var improving = false

    // 打字
    @Published var popup: Popup?
    @Published var trackpad = false
    @Published var clipboardOpen = false

    private var run: Task<Void, Never>?
    private var demo: Task<Void, Never>?
    private var lastTap: TourTarget?
    /// 用户自己在分词面板里选好、发出去的词（返回、往后走时留着）。
    private var sentWords: String?
    /// 打字一章用户自己打出来的标点、字母。
    private var typedPunct: String?
    private var typedLetter: String?

    // MARK: 开始、进退

    /// 放哪几章：nil 是全部 16 步。
    func start(layout: KeyboardLayout, chapter: TourChapter?) {
        self.layout = layout
        plan = chapter.map { Array($0.steps) } ?? Array(1...FeatureTour.stepCount)
        go(0, forward: true)
    }

    func go(_ index: Int, forward: Bool) {
        run?.cancel()
        target = nil
        pressed = nil
        popup = nil
        guard index >= 0 else {
            withAnimation(.easeInOut(duration: 0.3)) { page = replay ? .exit : .welcome }
            return
        }
        guard index < plan.count else {
            withAnimation(.easeInOut(duration: 0.3)) { page = replay ? .exit : .finished }
            return
        }
        position = index
        let n = plan[index]
        applyStart(n)
        let chapter = TourChapter.of(n)
        let interlude = forward && n == chapter.steps.lowerBound
        run = Task { [weak self] in
            guard let self else { return }
            do {
                if interlude {
                    withAnimation(.easeInOut(duration: 0.3)) { self.page = .interlude(chapter) }
                    try await self.pause(self.reduceMotion ? 1.3 : 1.8)
                }
                withAnimation(.easeInOut(duration: 0.35)) { self.page = .step }
                try await self.pause(0.35)
                try await self.play(n)
                try await self.pause(0.7)
                self.go(index + 1, forward: true)
            } catch {}
        }
    }

    func back() { go(position - 1, forward: false) }
    func skip() { go(plan.count, forward: true) }

    func stop() {
        run?.cancel()
        demo?.cancel()
    }

    /// 触点每 1.6 秒示范一下：点一下、按住，或按住往旁边滑。按钮跟着轻轻按下（不触发）。
    func startDemo() {
        demo?.cancel()
        demo = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard let self, !Task.isCancelled else { return }
                guard let target = self.target, self.pressed == nil, self.popup == nil, !self.trackpad, !self.reduceMotion else { continue }
                withAnimation(.easeOut(duration: 0.1)) { self.demoDown = true }
                switch target.gesture {
                case .tap:
                    try? await Task.sleep(nanoseconds: 140_000_000)
                case .hold:
                    try? await Task.sleep(nanoseconds: 800_000_000)
                case .slide:
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 0.5)) { self.demoSlide = 1 }
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    self.demoDown = false
                    self.demoSlide = 0
                }
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = nil }
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

    /// 回答卡右边翻版本（帮回第 3 步出了第 2 版以后，▲ 能翻回第 1 版）。不算哪一步，随时能翻。
    func flipVersion(_ delta: Int) {
        let next = versionIndex + delta
        guard versions.indices.contains(next), cardStream == nil, !regenerating else { return }
        withAnimation(.easeOut(duration: 0.2)) { versionIndex = next }
    }

    static func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: 打字一章：按住、滑、松手

    /// 按住「，。」/ e（全键盘一排）或「，。?!」/ DEF（九宫格十字）：弹出来。
    func holdBegan(_ hit: TourTarget, key: CGRect, containerWidth: CGFloat) {
        guard popup == nil else { return }
        guard hit == target else { return wrong() }
        Self.haptic()
        let kind: Popup.Kind
        let chinese = script.chinesePunct
        if layout == .nineKey {
            kind = hit == .punct
                ? .cross([.left: chinese ? "，" : ",", .up: chinese ? "。" : ".", .right: chinese ? "？" : "?", .down: chinese ? "！" : "!"], center: "，。?!")
                : .cross([.left: "D", .up: "E", .right: "F"], center: "DEF")
        } else {
            let row = hit == .punct
                ? QuickPunct.row(chinese: chinese)
                : AlternatesRow.letter("e", digit: "3", accents: chinese ? ["ē", "é", "ě", "è", "ê"] : ["é", "è", "ê", "ë", "ē"],
                                       onLeftHalf: key.midX < containerWidth / 2)
                ?? AlternatesRow(main: "e", left: [], right: [])
            kind = .row(row)
        }
        var next = Popup(kind: kind, key: key)
        if case .row(let row) = kind {
            next.index = row.arranged(centerX: key.midX, cellWidth: key.width, containerWidth: containerWidth).selected
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { popup = next }
    }

    /// 手指滑动：一排按横向位移换格，十字按方向（离开中间 18pt 才算）。
    func holdMoved(_ translation: CGSize, containerWidth: CGFloat) {
        guard var current = popup else { return }
        switch current.kind {
        case .row(let row):
            let arranged = row.arranged(centerX: current.key.midX, cellWidth: current.key.width, containerWidth: containerWidth)
            let index = arranged.selected + Int((translation.width / current.key.width).rounded())
            current.index = min(max(index, 0), arranged.options.count - 1)
        case .cross(let options, _):
            let dx = translation.width, dy = translation.height
            var arm: CrossArm?
            if hypot(dx, dy) > 18 {
                arm = abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down)
            }
            current.arm = arm.flatMap { options[$0] == nil ? nil : $0 }
        }
        if current != popup {
            if current.index != popup?.index || current.arm != popup?.arm { UISelectionFeedbackGenerator().selectionChanged() }
            popup = current
        }
    }

    /// 松手：打出选中的。十字停在中间松手是取消，再按一次。
    func holdEnded(containerWidth: CGFloat) {
        guard let current = popup else { return }
        var typed: String?
        switch current.kind {
        case .row(let row):
            let options = row.arranged(centerX: current.key.midX, cellWidth: current.key.width, containerWidth: containerWidth).options
            typed = options.indices.contains(current.index) ? options[current.index] : nil
        case .cross(let options, _):
            typed = current.arm.flatMap { options[$0] }
        }
        withAnimation(.easeOut(duration: 0.15)) { popup = nil }
        guard let typed, let hit = target else { return }
        field += typed
        if hit == .punct { typedPunct = typed } else { typedLetter = typed }
        lastTap = hit
    }

    /// 全键盘按住空格：键盘变灰成触控板，左右滑挪光标（14pt 一个字）。
    func trackpadBegan() {
        guard target == .space else { return wrong() }
        Self.haptic()
        withAnimation(.easeOut(duration: 0.2)) { trackpad = true }
    }

    func trackpadMoved(_ dx: CGFloat) {
        guard trackpad else { return }
        let back = min(max(Int((-dx / 14).rounded()), 0), field.count)
        if back != caretBack {
            UISelectionFeedbackGenerator().selectionChanged()
            caretBack = back
        }
    }

    func trackpadEnded() {
        guard trackpad else { return }
        withAnimation(.easeOut(duration: 0.2)) { trackpad = false }
        if caretBack > 0 { lastTap = .space }
    }

    /// 九宫格「常用 / 剪贴板」面板里点一条：上屏。
    func pickClip(_ text: String) {
        guard target == .clipItem else { return wrong() }
        Self.haptic()
        field += text
        lastTap = .clipItem
    }

    // MARK: 每一步开始时的样子（返回上一步、单看一章就从这里开始）

    private func applyStart(_ n: Int) {
        let s = script
        var list = [Message(text: s.opener)]
        if n >= 3 { list.append(Message(text: s.polished, mine: true)) }
        if n >= 4 { list.append(Message(text: s.helpMessage, copied: n <= 5)) }
        if n >= 6 { list.append(Message(text: s.helpReply2, mine: true)) }
        if n >= 7 { list.append(Message(text: s.requestMessage)) }
        if n >= 8 { list.append(Message(text: s.requestResult, mine: true)) }
        if n >= 9 { list.append(Message(text: s.foodMessage)) }
        if n >= 11 { list.append(Message(text: sentWords ?? s.hintWords, mine: true)) }
        if n >= 12 { list.append(Message(text: s.styleMessage)) }
        if n >= 15 { list.append(Message(text: s.typingMessage)) }
        messages = list

        switch n {
        case 1: field = s.original
        case 2: field = s.polished
        case 7: field = s.requestMessage
        case 12, 13: field = s.styleShort
        case 15: field = s.typingField + (typedPunct ?? (s.chinesePunct ? "，" : ","))
        case 16: field = s.typingField + (typedPunct ?? (s.chinesePunct ? "，" : ",")) + (typedLetter ?? (layout == .nineKey ? "E" : "é"))
        default: field = ""
        }
        fieldStream = nil
        fieldDim = false
        caretBack = 0
        sendReady = false
        bubbleMenu = false

        expanded = [5, 7, 8, 9, 10].contains(n)
        switch n {
        case 5: versions = [Version(text: s.helpReply, mode: .help)]
        case 9: versions = [Version(text: s.foodAnswer, mode: .answer)]
        case 10: versions = [Version(text: s.foodWeb, mode: .answer)]
        default: versions = []
        }
        versionIndex = max(versions.count - 1, 0)
        cardStream = nil
        generating = false
        regenerating = false
        cardTall = n == 10
        switch n {
        case 7: ask = s.requestAsk
        case 9, 10: ask = s.foodAsk
        default: ask = ""
        }
        askEditing = false
        askDim = false
        canSearch = n == 9
        searching = false
        searched = n == 10
        panel = false
        picked = []

        sparkRunning = false
        sparkDone = nil
        askRunning = false
        askDone = nil
        helpShown = n == 4 || n == 5
        helpRunning = false
        helpDone = nil
        undoOn = n == 2
        redoOn = false

        promptsOpen = n == 13
        selectedPrompt = n >= 12 ? 3 : 0
        customPrompt = n >= 13 ? s.promptName : nil
        pinnedCustom = n >= 14
        pinRunning = false
        pinDone = nil
        appPage = false
        sheetName = ""
        sheetContent = ""
        pickedTags = []
        improving = false

        popup = nil
        trackpad = false
        clipboardOpen = false
        demoSlide = 0
        demoDown = false
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
            try await wait(.redo)
            try await retype(\.field, to: s.polished)
            redoOn = false
            undoOn = true
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send()
        case 3:
            try await pause(0.3)
            try await incoming(s.helpMessage)
            try await wait(.peerBubble)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) { bubbleMenu = true }
            try await wait(.copy)
            withAnimation(.easeOut(duration: 0.2)) {
                bubbleMenu = false
                if let last = messages.indices.last { messages[last].copied = true }
            }
            try await pause(0.45)
            // 刚复制：问答右边弹出帮回键（第 89 条）。
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.8)) { helpShown = true }
            try await pause(0.6)
        case 4:
            try await wait(.helpKey)
            helpRunning = true
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)) { expanded = true }
            try await pause(0.3)
            try await generate(Version(text: s.helpReply, mode: .help), perChar: 0.048, delay: 0.5)
            helpRunning = false
            helpDone = Date()
            try await pause(0.6)
        case 5:
            try await wait(.askField)
            withAnimation(.easeOut(duration: 0.2)) { askEditing = true }
            try await pause(0.2)
            try await type(\.ask, s.helpAsk, duration: 0.6)
            try await wait(.sparkle)
            // 回答卡开着时点润色：识意框里的字当要求，接着改帮回那一版（execute(extraInstruction:)）。
            sparkRunning = true
            withAnimation(.easeOut(duration: 0.2)) { regenerating = true }
            try await pause(reduceMotion ? 0.6 : 1.2)
            withAnimation(.easeOut(duration: 0.2)) {
                regenerating = false
                askEditing = false
                askDim = true
            }
            try await stream(Version(text: s.helpReply2, mode: .rewrite), perChar: 0.04)
            sparkRunning = false
            sparkDone = Date()
            try await wait(.replace)
            try await typeReplace(to: versions.indices.contains(versionIndex) ? versions[versionIndex].text : s.helpReply2)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send()
            // 发送以后帮回键缩小淡出，后面的键补位；回答卡收起。
            try await pause(0.3)
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.9)) { helpShown = false }
            try await pause(0.3)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                expanded = false
                versions = []
                ask = ""
                askDim = false
            }
        case 6:
            try await pause(0.3)
            try await incoming(s.requestMessage)
            try await type(\.field, s.requestMessage, duration: 0.4)
            try await wait(.drawer)
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)) { expanded = true }
            try await pause(0.3)
            try await wait(.askField)
            withAnimation(.easeOut(duration: 0.2)) { askEditing = true }
            try await pause(0.2)
            try await type(\.ask, s.requestAsk, duration: 0.5)
        case 7:
            try await wait(.sparkle)
            sparkRunning = true
            withAnimation(.easeOut(duration: 0.2)) { askEditing = false }
            try await generate(Version(text: s.requestResult, mode: .rewrite), perChar: 0.026, delay: 0.6)
            sparkRunning = false
            sparkDone = Date()
            try await wait(.replace)
            try await typeReplace(to: s.requestResult)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send()
        case 8:
            try await pause(0.3)
            try await incoming(s.foodMessage)
            try await wait(.askField)
            withAnimation(.easeOut(duration: 0.2)) { askEditing = true }
            try await pause(0.2)
            try await type(\.ask, s.foodAsk, duration: 0.5)
            try await wait(.askKey)
            askRunning = true
            withAnimation(.easeOut(duration: 0.2)) { askEditing = false }
            try await generate(Version(text: s.foodAnswer, mode: .answer), perChar: 0.026, delay: 0.6)
            askRunning = false
            askDone = Date()
            withAnimation(.easeOut(duration: 0.3)) { canSearch = true }
        case 9:
            try await wait(.search)
            askRunning = true
            withAnimation(.easeOut(duration: 0.2)) {
                canSearch = false
                searching = true
            }
            try await pause(1)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                searching = false
                searched = true
                cardTall = true
            }
            versions = []
            try await stream(Version(text: s.foodWeb, mode: .answer), perChar: 0.026)
            askRunning = false
            askDone = Date()
        case 10:
            try await wait(.card)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) {
                cardTall = false
                panel = true
            }
            try await pause(0.3)
            target = .words
            while picked.isEmpty { try await pause(0.05) }
            try await wait(.insert)
            let words = s.join(Array(picked))
            sentWords = words
            withAnimation(.easeOut(duration: 0.15)) { panel = false }
            try await pause(0.2)
            try await type(\.field, words, duration: 0.4)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send()
            try await pause(0.3)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { expanded = false }
        case 11:
            try await pause(0.3)
            try await incoming(s.styleMessage)
            try await type(\.field, s.styleField, duration: 0.4)
            try await wait(.chevron)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { promptsOpen = true }
            try await wait(.pill(3))
            withAnimation(.easeOut(duration: 0.2)) {
                selectedPrompt = 3
                promptsOpen = false
            }
            try await pause(0.2)
            try await wait(.sparkle)
            try await polish(to: s.styleShort)
        case 12:
            try await wait(.chevron)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { promptsOpen = true }
            try await wait(.addStyle)
            // 风格在 App 里管：键盘下沉，模拟的 App 风格页升起（名字已填好）。
            withAnimation(.easeOut(duration: 0.35)) {
                promptsOpen = false
                appPage = true
            }
            try await pause(0.45)
            try await type(\.sheetName, s.promptName, duration: 0.3)
            try await wait(.tag(0))
            withAnimation(.easeOut(duration: 0.15)) { pickedTags = [0] }
            try await type(\.sheetContent, s.tags[0], duration: 0.3)
            try await wait(.improve)
            withAnimation(.easeOut(duration: 0.2)) { improving = true }
            try await pause(0.8)
            improving = false
            try await retype(\.sheetContent, to: s.improvedContent)
            try await wait(.done)
        case 13:
            // App 页下沉、键盘升回，下拉还开着，末尾多出「英文」。
            withAnimation(.easeOut(duration: 0.35)) { appPage = false }
            try await pause(0.35)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { promptsOpen = true }
            try await pause(0.2)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { customPrompt = s.promptName }
            try await wait(.pin(5))
            withAnimation(.easeOut(duration: 0.15)) { pinnedCustom = true }
            try await pause(0.25)
            withAnimation(.easeOut(duration: 0.2)) { promptsOpen = false }
            try await pause(0.3)
            try await wait(.pinned)
            pinRunning = true
            try await pause(0.6)
            try await typeReplace(to: s.styleTranslated)
            pinRunning = false
            pinDone = Date()
            try await pause(0.6)
        case 14:
            try await pause(0.3)
            try await incoming(s.typingMessage)
            try await type(\.field, s.typingField, duration: 0.3)
            try await wait(.punct)
        case 15:
            try await wait(.letter)
        default:
            if layout == .nineKey {
                try await wait(.clipKey)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { clipboardOpen = true }
                try await pause(0.3)
                try await wait(.clipItem)
                try await pause(0.3)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { clipboardOpen = false }
            } else {
                try await wait(.space)
            }
        }
    }

    // MARK: 动作

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// 等用户点对那一处（抬起才算）。
    private func wait(_ hit: TourTarget) async throws {
        lastTap = nil
        target = hit
        while lastTap != hit { try await pause(0.03) }
        lastTap = nil
        target = nil
        demoDown = false
        demoSlide = 0
    }

    /// 润色写进输入框：键执行中 0.6 秒 → 原文变淡 → 结果逐字浮现 → 成功动效。
    private func polish(to text: String) async throws {
        sparkRunning = true
        try await pause(0.6)
        try await typeReplace(to: text)
        sparkRunning = false
        sparkDone = Date()
    }

    /// 回答卡：生成中 → 逐字浮现。
    private func generate(_ version: Version, perChar: Double, delay: Double) async throws {
        withAnimation(.easeOut(duration: 0.2)) {
            generating = true
            versions = []
        }
        try await pause(delay)
        withAnimation(.easeOut(duration: 0.2)) { generating = false }
        try await stream(version, perChar: perChar)
    }

    /// AI 结果出字：逐字淡入（每字 0.3 秒），整段不超过 1.5 秒。
    private func stream(_ version: Version, perChar: Double) async throws {
        versions.append(version)
        withAnimation(.easeOut(duration: 0.2)) { versionIndex = versions.count - 1 }
        guard !reduceMotion else { return }
        let step = Self.charStep(version.text, perChar)
        cardStream = (Date(), step)
        try await pause(Self.streamDuration(version.text, step))
        cardStream = nil
    }

    static func charStep(_ text: String, _ perChar: Double) -> Double {
        min(perChar, 1.2 / Double(max(text.count - 1, 1)))
    }

    static func streamDuration(_ text: String, _ step: Double) -> Double {
        Double(max(text.count - 1, 0)) * step + 0.3
    }

    /// 结果写进输入框：原文变淡 0.15 秒，新字逐字浮现（26 毫秒一字）。
    private func typeReplace(to text: String) async throws {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { field = text }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { fieldDim = true }
        try await pause(0.15)
        let step = Self.charStep(text, 0.026)
        field = text
        fieldDim = false
        fieldStream = (Date(), step)
        try await pause(Self.streamDuration(text, step))
        fieldStream = nil
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

    /// 像用户自己打字一样，一段段打出来。
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

    /// 点了「发送」：输入框清空，新气泡从右下角弹进对话。
    private func send() async throws {
        let sent = field
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)) {
            sendReady = false
            field = ""
            messages.append(Message(text: sent, mine: true))
        }
        try await pause(0.5)
    }

    /// 对方发来新消息：先出「正在输入」三个点，再弹出气泡。
    private func incoming(_ text: String) async throws {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { messages.append(Message(text: "", typing: true)) }
        try await pause(reduceMotion ? 0.4 : 0.8)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.72)) {
            messages.removeAll { $0.typing }
            messages.append(Message(text: text))
        }
        try await pause(0.4)
    }
}
