import SwiftUI

// 功能演示（T95，design/onboard-v2，对齐清单第 90 条）：隐私同意之后、设置三步之前，在 App 里画的模拟键盘上把功能点一遍。
// 5 章 14 步：润色 2、帮回 3、按要求改 3、问答 3、润色风格 3（11-25 去掉打字一章、对话改成三人群聊，对齐清单第 93 条）。
// 键盘按首页选的布局画（九宫格 / 全键盘）。
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
    static let stepCount = 14

    /// 帮回等待条走满要多久（11-26 08:26 cvbk 改 1.5 秒，对齐清单第 98 条；原来 2 秒）。
    static let helpWait: Double = 1.5
}

// MARK: - 章节

enum TourChapter: Int, CaseIterable, Hashable, Identifiable {
    case polish, helpReply, request, answer, style

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .polish: return L("润色", "Polish", "整える")
        case .helpReply: return L("帮回", "Help Reply", "返信アシスト")
        case .request: return L("按要求改", "Rewrite on Request", "指示で書き換え")
        case .answer: return L("问答", "Ask", "質問")
        case .style: return L("润色风格", "Polish Styles", "整えるスタイル")
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
        }
    }

    /// SF Symbols：润色、按要求改、润色风格紫，帮回绿，问答蓝（和历史里的小方块一样）。
    var symbol: String {
        switch self {
        case .polish: return "sparkles"
        case .helpReply: return "arrowshape.turn.up.left"
        case .request: return "pencil"
        case .answer: return "questionmark.bubble"
        case .style: return "slider.horizontal.3"
        }
    }

    /// 小方块的底色（功能识别色，DESIGN.md 第一节）。
    var color: Color {
        switch self {
        case .polish, .request, .style: return Color(hex: 0x5B4BE8)
        case .helpReply: return Color(hex: 0x34A853)
        case .answer: return Color(hex: 0x007AFF)
        }
    }

    /// 这一章在全部 14 步里的范围。
    var steps: ClosedRange<Int> {
        switch self {
        case .polish: return 1...2
        case .helpReply: return 3...5
        case .request: return 6...8
        case .answer: return 9...11
        case .style: return 12...14
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

/// 一步的标题和说明（第三节）。标题说结果，说明先说怎么做、再说得到什么；按钮名加「」。
struct TourStepText {
    var title: String
    var detail: String

    static func of(_ step: Int) -> TourStepText {
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
            detail: L("长按 Alex 的问题，选「拷贝」。", "Touch and hold Wang Lei's question, then choose \"Copy\".", "Alex さんの質問を長押しして、「コピー」を選びます。"))
        case 4: return TourStepText(
            title: L("回复，已为你拟好", "Your reply, already drafted", "返信は、もう用意できています"),
            detail: L("复制之后，问答右边弹出「帮回」。点一下，按你的语气拟好回复。",
                      "After you copy, \"Reply\" pops up next to Ask. Tap it to draft a reply in your tone.",
                      "コピーすると、「質問」の右に「返信」が出ます。タップすると、あなたの口調で返信を用意します。"))
        case 5: return TourStepText(
            title: L("补一句要求，重写一版", "Add a request, get a new version", "ひと言足して、もう一度"),
            detail: L("在回复下方的框里写下要求，再点「帮回」重写。满意后「替换」发出。",
                      "Write a request in the box below the reply, then tap \"Reply\" again to rewrite it. Tap \"Replace\" and send when you're happy.",
                      "返信の下の欄に指示を書き、もう一度「返信」で書き直します。納得したら「置換」して送信します。"))
        case 6: return TourStepText(
            title: L("说出你的要求", "Say what you want", "指示を伝える"),
            detail: L("展开回答卡，在下方写下想怎么改。", "Open the answer card and write how you want it changed in the box below.", "回答カードを開いて、下の欄にどう直すかを書きます。"))
        case 7: return TourStepText(
            title: L("照你的意思改好", "Rewritten your way", "指示どおりに書き換え"),
            detail: L("点「润色」，按要求改写。「替换」换掉原文；按住「替换」上滑则插入。",
                      "Tap \"Polish\" to rewrite it as asked. \"Replace\" swaps out your text; hold \"Replace\" and slide up to insert instead.",
                      "「整える」で指示どおりに書き換えます。「置換」で元の文と入れ替え、「置換」を長押しして上にスライドすると挿入します。"))
        case 8: return TourStepText(
            title: L("不满意，换个要求", "Not quite? Change the request", "いまいちなら、指示を変える"),
            detail: L("把要求改成「再简短一点」，再点「润色」。满意后「替换」发出。",
                      "Change the request to \"Make it shorter\" and tap \"Polish\" again. Tap \"Replace\" and send when you're happy.",
                      "指示を「もっと短く」に変えて、もう一度「整える」をタップ。よければ「置換」して送信します。"))
        case 9: return TourStepText(
            title: L("有问题，直接问", "Got a question? Just ask", "知りたいことは、そのまま質問"),
            detail: L("在框里写下问题，点「问答」即得答案。", "Write your question in the box and tap \"Ask\" for the answer.", "欄に質問を書いて「質問」をタップすると、答えが出ます。"))
        case 10: return TourStepText(
            title: L("联网，答案更新", "Search the web for fresher answers", "ウェブ検索で、最新の答え"),
            detail: L("需要最新信息时，点「使用联网查询」重新作答。", "When you need the latest information, tap \"Search the web\" to answer again.", "最新の情報が必要なときは、「ウェブで調べる」で答え直します。"))
        case 11: return TourStepText(
            title: L("只取你要的词", "Take just the words you need", "必要な言葉だけ使う"),
            detail: L("长按答案，点选需要的词，再点「插入」。", "Touch and hold the answer, tap the words you need, then tap \"Insert\".", "答えを長押しし、必要な言葉を選んで「挿入」をタップします。"))
        case 12: return TourStepText(
            title: L("换一种语气", "Try a different tone", "口調を変える"),
            detail: L("点润色键旁的 ⌄，选「简短」。同一句话，换个说法。",
                      "Tap the ⌄ next to the Polish key and choose \"Concise\". Same message, said another way.",
                      "整えるキーの横の ⌄ から「簡潔に」を選びます。同じ内容を、別の言い方に。"))
        case 13: return TourStepText(
            title: L("定制你的风格", "Make your own style", "自分のスタイルを作る"),
            detail: L("新建一个「英文」风格，AI 帮你把要求写清楚。问答键的 ⌄ 同样可以换风格。",
                      "Create a \"Chinese\" style and let AI write the instructions clearly. The Ask key's ⌄ lets you switch styles too.",
                      "「英語」スタイルを新しく作り、AI に指示をわかりやすく書いてもらいます。質問キーの ⌄ でもスタイルを切り替えられます。"))
        default: return TourStepText(
            title: L("钉在手边", "Keep it within reach", "手元に固定"),
            detail: L("点图钉，「英文」出现在 AI 栏，一点即用。", "Tap the pin and \"Chinese\" appears on the AI bar, ready in one tap.", "ピンをタップすると「英語」が AI バーに出て、ワンタップで使えます。"))
        }
    }
}

// MARK: - 剧本

/// 群里的一个人：名字、头像上的字、头像颜色（第五节：小林橙 #F59E0B，Alex 玫红 #E5487A）。
struct TourPerson: Equatable {
    var name: String
    var avatar: String
    var color: Color
}

/// 三人群聊「项目组」：你、一个说界面语言的同事（橙）、一个说另一种语言的同事（玫红），14 步连成一段（第三节、OG5）。
/// 三种界面语言各一套，群里总有一个人说另一种语言：中文界面小林 + Alex，英文界面 Alex + Wang Lei，日文界面佐藤さん + Alex。
struct TourScript {
    /// 说界面语言的同事（橙）、说另一种语言的同事（玫红）。
    var local: TourPerson
    var foreign: TourPerson
    /// 对话卡最上面的群名、输入框占位。
    var group: String
    var placeholder: String
    /// 演示开头同事（橙）已经发来的一句。
    var opener: String
    /// 润色：随手打的、润色后的。
    var original: String
    var polished: String
    /// 帮回：玫红那位提问（拷贝这句），橙那位答得含糊；第 1 版（时间地点留空）、识意框里的要求（关键词）、第 2 版。
    var helpQuestion: String
    var helpVague: String
    var helpReply: String
    var helpAsk: String
    var helpReply2: String
    /// 按要求改：同事让你在群里发集合通知、输入框随手打的、要求、结果；第 3 步换的要求、更短的第 2 版。
    var requestMessage: String
    var requestField: String
    var requestAsk: String
    var requestResult: String
    var requestAsk2: String
    var requestResult2: String
    /// 问答：对方问的、识意框里的问题、未联网的回答、联网的回答、分词面板里的词和虚线框提示的几块。
    var foodMessage: String
    var foodAsk: String
    var foodAnswer: String
    var foodWeb: String
    var words: [String]
    var hints: [Int]
    /// 插入时词和词之间放什么。
    var joiner: String
    /// 润色风格：玫红那位用另一种语言提醒带伞、随手打的、「简短」之后、新风格的名字、建议标签、AI 优化后的内容、翻好之后（发给他）。
    var styleMessage: String
    var styleField: String
    var styleShort: String
    var promptName: String
    var tags: [String]
    var improvedContent: String
    var styleTranslated: String
    /// 模拟键盘的标点键用中文标点（中文、日文界面）还是英文标点。
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

    private static let orange = Color(hex: 0xF59E0B)
    private static let rose = Color(hex: 0xE5487A)

    static let zh = TourScript(
        local: TourPerson(name: "小林", avatar: "林", color: orange),
        foreign: TourPerson(name: "Alex", avatar: "A", color: rose),
        group: "项目组（3 人）", placeholder: "发到 项目组",
        opener: "明早九点开周会，记得准时到哦。",
        original: "明天的会我晚点到 要先送孩子 你们先开始吧",
        polished: "明天的会我会晚一点到，要先送孩子上学，你们先开始就好。",
        helpQuestion: "Hey, when and where are we meeting on Friday?",
        helpVague: "好像是下午吧？在哪儿我也不太确定。",
        helpReply: "We're meeting at [place] at [time] on Friday.",
        helpAsk: "周五下午三点，楼下集合，英文，客气",
        helpReply2: "We're meeting downstairs at 3 p.m. on Friday. See you there!",
        requestMessage: "谢啦！那你在群里发个集合通知吧。",
        requestField: "周五下午三点楼下集合 记得带身份证 别迟到",
        requestAsk: "写成正式通知",
        requestResult: "各位同事：周五下午三点在公司楼下集合，请携带身份证，准时出发。",
        requestAsk2: "再简短一点",
        requestResult2: "周五下午三点楼下集合，带好身份证，准时出发。",
        foodMessage: "团建在上海，有什么必吃的？",
        foodAsk: "上海有什么必吃的美食",
        foodAnswer: "上海菜偏甜，浓油赤酱。常被推荐的有生煎、蟹粉小笼、葱油拌面、红烧肉。具体去哪家、最近口碑如何，可以联网查一下。",
        foodWeb: "最近口碑好的：早餐吃生煎、蟹粉小笼，豫园、黄河路一带最集中；本帮菜点红烧肉、油爆虾、腌笃鲜；小吃试试葱油拌面。热门老店饭点要排队，建议错峰去。",
        words: ["早餐", "吃", "生煎", "、", "蟹粉小笼", "，", "豫园", "、", "黄河路", "一带", "最集中", "；", "本帮菜", "点", "红烧肉", "、",
                "油爆虾", "、", "腌笃鲜", "；", "小吃", "试试", "葱油拌面", "。", "热门", "老店", "饭点", "要排队", "，", "错峰去"],
        hints: [2, 4], joiner: "、",
        styleMessage: "Bring an umbrella on Friday, rain is in the forecast.",
        styleField: "好的我知道了 到时候我会带伞的 谢谢你提醒我",
        styleShort: "好，会带伞，谢谢提醒。",
        promptName: "英文",
        tags: ["翻成英文", "保持原意", "语气礼貌", "适合发微信", "不加新内容", "语气轻松", "适合发邮件", "先说结论"],
        improvedContent: "把输入的中文翻成自然、地道的英文。保持原意，不增不减，语气和原文一致；只输出译文。",
        styleTranslated: "OK, I'll bring an umbrella. Thanks for the reminder!",
        chinesePunct: true)

    static let en = TourScript(
        local: TourPerson(name: "Alex", avatar: "A", color: orange),
        foreign: TourPerson(name: "Wang Lei", avatar: "王", color: rose),
        group: "Project team (3)", placeholder: "Message Project team",
        opener: "Team meeting at 9 tomorrow, please be on time.",
        original: "ill be late tmrw gotta drop off my kid first start without me",
        polished: "I'll be a little late tomorrow, as I need to drop my kid off at school first. Please start without me.",
        helpQuestion: "问一下，周五几点、在哪儿集合？",
        helpVague: "Afternoon, I think? Not sure where.",
        helpReply: "我们周五[时间]在[地点]集合。",
        helpAsk: "Fri 3 p.m., downstairs, Chinese, polite",
        helpReply2: "周五下午三点在楼下集合，到时见！",
        requestMessage: "Thanks! Could you post a meetup notice in the group?",
        requestField: "fri 3pm downstairs bring ID dont be late",
        requestAsk: "Make it a formal notice",
        requestResult: "Hi all, we'll meet downstairs at 3 p.m. on Friday. Please bring your ID and be on time.",
        requestAsk2: "Make it shorter",
        requestResult2: "Friday 3 p.m., downstairs. Bring your ID and be on time.",
        foodMessage: "The outing is in Shanghai. Any must-try food?",
        foodAsk: "must-try food in Shanghai",
        foodAnswer: "Shanghai food leans sweet and rich. Often recommended: shengjian buns, crab xiaolongbao, scallion oil noodles and red-braised pork. For where to go and recent reviews, try searching the web.",
        foodWeb: "Well reviewed lately: shengjian buns and crab xiaolongbao for breakfast, mostly around Yuyuan and Huanghe Road; red-braised pork and oil-fried shrimp for local dishes; scallion oil noodles as a snack. Popular shops queue at mealtimes, so go off-peak.",
        words: ["shengjian buns", "and", "crab xiaolongbao", "for breakfast", ",", "around", "Yuyuan", "and", "Huanghe Road", ";", "red-braised pork",
                "and", "oil-fried shrimp", ";", "scallion oil noodles", "as a snack", ".", "Popular shops", "queue", "at mealtimes", ",", "go off-peak"],
        hints: [0, 2], joiner: ", ",
        styleMessage: "周五记得带伞，天气预报说有雨。",
        styleField: "ok got it ill bring an umbrella then thanks for reminding me",
        styleShort: "OK, I'll bring one. Thanks!",
        promptName: "Chinese",
        tags: ["Translate into Chinese", "Keep the meaning", "Polite tone", "For chat apps", "No new content", "Casual tone", "For email", "Lead with the point"],
        improvedContent: "Translate the input into natural, idiomatic Chinese. Keep the meaning without adding or removing anything, match the original tone, and output only the translation.",
        styleTranslated: "好的，我会带伞，谢谢提醒！",
        chinesePunct: false)

    static let ja = TourScript(
        local: TourPerson(name: "佐藤さん", avatar: "佐", color: orange),
        foreign: TourPerson(name: "Alex", avatar: "A", color: rose),
        group: "プロジェクト（3 人）", placeholder: "プロジェクトへ送信",
        opener: "明日 9 時から定例です。遅れないようにお願いします。",
        original: "明日の会議ちょっと遅れる 子ども送ってから行く 先に始めてて",
        polished: "明日の会議は少し遅れます。子どもを学校に送ってから向かいますので、先に始めていてください。",
        helpQuestion: "Hey, when and where are we meeting on Friday?",
        helpVague: "午後だったかな？場所はちょっとわからないです。",
        helpReply: "We're meeting at [place] at [time] on Friday.",
        helpAsk: "金曜15時、会社の下、英語、丁寧に",
        helpReply2: "We're meeting downstairs at 3 p.m. on Friday. See you there!",
        requestMessage: "ありがとう！グループに集合のお知らせを出してもらえますか？",
        requestField: "金曜15時 会社の下に集合 身分証持参 遅刻しないで",
        requestAsk: "正式なお知らせに",
        requestResult: "皆さま、金曜15時に会社の下に集合です。身分証をお持ちのうえ、時間厳守でお願いします。",
        requestAsk2: "もっと短く",
        requestResult2: "金曜15時、会社の下に集合。身分証持参、時間厳守で。",
        foodMessage: "イベントは上海です。絶対食べるべきものは？",
        foodAsk: "上海で絶対食べたいもの",
        foodAnswer: "上海料理は甘めで濃い味付けです。生煎（焼き小籠包）、蟹みそ小籠包、葱油拌麺、紅焼肉がよくすすめられます。どの店がいいかは、ウェブで調べてみてください。",
        foodWeb: "最近評判のいいもの：朝は生煎と蟹みそ小籠包で、豫園や黄河路あたりに多いです。上海料理なら紅焼肉と油爆蝦、軽食なら葱油拌麺。人気店は食事時に並ぶので、時間をずらすのがおすすめです。",
        words: ["朝は", "生煎", "と", "蟹みそ小籠包", "で", "、", "豫園", "や", "黄河路", "あたり", "に多い", "。", "上海料理", "なら", "紅焼肉", "と",
                "油爆蝦", "、", "軽食", "なら", "葱油拌麺", "。", "人気店", "は", "食事時に", "並ぶ", "ので", "時間を", "ずらして"],
        hints: [1, 3], joiner: "、",
        styleMessage: "Bring an umbrella on Friday, rain is in the forecast.",
        styleField: "わかった 当日は傘持っていくね 教えてくれてありがとう",
        styleShort: "了解、傘を持っていきます。ありがとう！",
        promptName: "英語",
        tags: ["英語に翻訳", "意味はそのまま", "丁寧な口調", "チャット向け", "内容を足さない", "気軽な口調", "メール向け", "結論から"],
        improvedContent: "入力された文章を自然で正確な英語に翻訳。意味はそのまま、足したり削ったりせず、口調も原文に合わせる。訳文だけを出力。",
        styleTranslated: "Got it, I'll bring an umbrella. Thanks for the reminder!",
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

    /// 触点怎么示范：点一下、按住。
    enum Gesture { case tap, hold }

    var gesture: Gesture {
        switch self {
        case .peerBubble, .card: return .hold
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

    /// 群里谁说的：说界面语言的同事（橙），还是说另一种语言的那位（玫红）。
    enum Speaker: Equatable { case local, foreign }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var mine = false
        /// 别人发的是哪一位（名字、头像）；我方的是 nil。
        var from: Speaker?
        var typing = false
        /// 能拷贝的那条（帮回第 1 步 Alex 的问题）：右边一直留着「已拷贝」的位置，拷贝后只是显出来。
        /// 原来拷贝后才插进去，气泡变窄要重新折行，和菜单淡出叠在一起闪一下（PR #109 模拟器）。
        var copyable = false
        /// 旁边的「已拷贝」。
        var copied = false
    }

    /// 回答卡里的一版：帮回第 3 步补了要求后有两版，右边「2/2」能翻。
    struct Version: Equatable {
        var text: String
        var mode: CardMode
    }

    let script = TourScript.current
    var reduceMotion = false
    /// 从设置里看（单看一章或从头播放）：放完回章节页，没有完成页。
    var replay = false

    @Published var layout: KeyboardLayout = .qwerty
    /// 这次放哪几步（全部 14 步，或者某一章）。
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
    /// 触点示范按下、按住。
    @Published var demoDown = false
    @Published var shakes = 0

    // 对话和宿主输入框
    @Published var messages: [Message] = []
    @Published var field = ""
    /// 输入框里的字是 AI 刚写进去的：逐字浮现（从这一刻开始，每字多少秒）。
    @Published var fieldStream: (start: Date, perChar: Double)?
    @Published var fieldDim = false
    @Published var sendReady = false
    /// 长按对方那条：描边、上面弹出编辑菜单。
    @Published var bubbleMenu = false
    /// 气泡上方让出放菜单的那一格。和 bubbleMenu 分开：拷贝后菜单先原地淡出，再收这一格。
    @Published var bubbleLifted = false

    // 回答卡和识意框
    @Published var expanded = false
    @Published var versions: [Version] = []
    @Published var versionIndex = 0
    @Published var cardStream: (start: Date, perChar: Double)?
    @Published var generating = false
    /// 带着识意框的要求重新生成：卡头「AI 正在改写…」（帮回是「AI 正在帮回…」），上一版虚掉。
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
    /// 帮回第 2 步：点帮回后回答卡升起，上半格绿色笔刷 1.5 秒扫满再自动回（等待条，OM2、help-reply/again 二之二）。nil 是没在等。
    @Published var helpWaitStart: Date?
    /// 等待条走满的那一刻：尽头一亮碎成光点、白光刷过、卡边绿光一闪，同时开始帮回。
    @Published var helpArrived: Date?
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

    private var run: Task<Void, Never>?
    private var demo: Task<Void, Never>?
    private var lastTap: TourTarget?
    /// 用户自己在分词面板里选好、发出去的词（返回、往后走时留着）。
    private var sentWords: String?

    // MARK: 开始、进退

    /// 放哪几章：nil 是全部 14 步。
    func start(layout: KeyboardLayout, chapter: TourChapter?) {
        self.layout = layout
        plan = chapter.map { Array($0.steps) } ?? Array(1...FeatureTour.stepCount)
        go(0, forward: true)
    }

    func go(_ index: Int, forward: Bool) {
        run?.cancel()
        target = nil
        pressed = nil
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

    /// 触点每 1.6 秒示范一下：点一下或按住。按钮跟着轻轻按下（不触发）。
    func startDemo() {
        demo?.cancel()
        demo = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard let self, !Task.isCancelled else { return }
                guard let target = self.target, self.pressed == nil, !self.reduceMotion else { continue }
                withAnimation(.easeOut(duration: 0.1)) { self.demoDown = true }
                switch target.gesture {
                case .tap:
                    try? await Task.sleep(nanoseconds: 140_000_000)
                case .hold:
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { self.demoDown = false }
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

    // MARK: 每一步开始时的样子（返回上一步、单看一章就从这里开始）

    private func applyStart(_ n: Int) {
        let s = script
        var list = [Message(text: s.opener, from: .local)]
        if n >= 3 { list.append(Message(text: s.polished, mine: true)) }
        if n >= 4 {
            list.append(Message(text: s.helpQuestion, from: .foreign, copyable: true, copied: n <= 5))
            list.append(Message(text: s.helpVague, from: .local))
        }
        if n >= 6 { list.append(Message(text: s.helpReply2, mine: true)) }
        if n >= 7 { list.append(Message(text: s.requestMessage, from: .local)) }
        if n >= 9 { list.append(Message(text: s.requestResult2, mine: true)) }
        if n >= 10 { list.append(Message(text: s.foodMessage, from: .local)) }
        if n >= 12 { list.append(Message(text: sentWords ?? s.hintWords, mine: true)) }
        if n >= 13 { list.append(Message(text: s.styleMessage, from: .foreign)) }
        messages = list

        switch n {
        case 1: field = s.original
        case 2: field = s.polished
        case 7: field = s.requestField
        // 按要求改第 2 步替换后先不发，第 3 步从正式通知那版开始改。
        case 8: field = s.requestResult
        case 13, 14: field = s.styleShort
        default: field = ""
        }
        fieldStream = nil
        fieldDim = false
        sendReady = false
        bubbleMenu = false
        bubbleLifted = false

        expanded = [5, 7, 8, 9, 10, 11].contains(n)
        switch n {
        case 5: versions = [Version(text: s.helpReply, mode: .help)]
        case 8: versions = [Version(text: s.requestResult, mode: .rewrite)]
        case 10: versions = [Version(text: s.foodAnswer, mode: .answer)]
        case 11: versions = [Version(text: s.foodWeb, mode: .answer)]
        default: versions = []
        }
        versionIndex = max(versions.count - 1, 0)
        cardStream = nil
        generating = false
        regenerating = false
        cardTall = n == 11
        switch n {
        case 7, 8: ask = s.requestAsk
        case 10, 11: ask = s.foodAsk
        default: ask = ""
        }
        askEditing = false
        askDim = false
        canSearch = n == 10
        searching = false
        searched = n == 11
        panel = false
        picked = []

        sparkRunning = false
        sparkDone = nil
        askRunning = false
        askDone = nil
        helpShown = n == 4 || n == 5
        helpRunning = false
        helpDone = nil
        helpWaitStart = nil
        helpArrived = nil
        undoOn = n == 2
        redoOn = false

        promptsOpen = n == 14
        selectedPrompt = n >= 13 ? 3 : 0
        customPrompt = n >= 14 ? s.promptName : nil
        pinnedCustom = false
        pinRunning = false
        pinDone = nil
        appPage = false
        sheetName = ""
        sheetContent = ""
        pickedTags = []
        improving = false
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
            // 群里 Alex 用英文提问，小林用中文答得含糊；长按的是 Alex 那句（倒数第二条）。
            try await pause(0.3)
            try await incoming(s.helpQuestion, from: .foreign, copyable: true)
            try await incoming(s.helpVague, from: .local)
            try await wait(.peerBubble)
            withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                bubbleMenu = true
                bubbleLifted = true
            }
            try await wait(.copy)
            // 先让菜单在原地淡出、「已拷贝」显出来，再收回菜单那一格。原来三件事挤在一个 0.2 秒动画里：
            // 菜单一边淡出一边跟着气泡往下滑，「已拷贝」插进来把气泡挤得重新折行，叠在一起闪一下（PR #109 模拟器）。
            withAnimation(.easeOut(duration: 0.15)) {
                bubbleMenu = false
                if let index = messages.firstIndex(where: { $0.copyable }) { messages[index].copied = true }
            }
            try await pause(0.15)
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.25)) { bubbleLifted = false }
            try await pause(0.3)
            // 刚复制：问答右边弹出帮回键（第 89 条）。
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.8)) { helpShown = true }
            try await pause(0.6)
        case 4:
            try await wait(.helpKey)
            // 回答卡升起：卡头「回 AI 帮回 · 正式」，正文是 Alex 那句原话；上半格绿色笔刷 1.5 秒扫满（等待条，OM2），
            // 碰到右边的那一刻整张卡闪一下、卡边绿了再淡掉，同时开始帮回（卡头「AI 正在帮回…」，原话虚掉，键上星星闪）；约 0.4 秒后出字。
            withAnimation(cardMotion) { expanded = true }
            try await pause(0.35)
            helpWaitStart = Date()
            try await pause(FeatureTour.helpWait)
            helpArrived = Date()
            helpRunning = true
            try await pause(0.4)
            // 第 1 版：AI 不知道时间地点，先把回答写好，时间、地点留空（第 3 步用关键词补上）。
            try await stream(Version(text: s.helpReply, mode: .help), perChar: 0.048)
            helpRunning = false
            helpDone = Date()
            helpWaitStart = nil
            helpArrived = nil
            try await pause(0.6)
        case 5:
            try await wait(.askField)
            withAnimation(.easeOut(duration: 0.2)) { askEditing = true }
            try await pause(0.2)
            try await type(\.ask, s.helpAsk, duration: 0.8)
            // 写好要求再点「帮回」（12:30 cvbk）：回的还是 Alex 那句，识意框的字当要求；识意框有字，不等，马上回（help-reply/again 第二节）。
            try await wait(.helpKey)
            helpRunning = true
            withAnimation(.easeOut(duration: 0.2)) { regenerating = true }
            try await pause(reduceMotion ? 0.6 : 1.2)
            withAnimation(.easeOut(duration: 0.2)) {
                regenerating = false
                askEditing = false
                askDim = true
            }
            try await stream(Version(text: s.helpReply2, mode: .help), perChar: 0.04)
            helpRunning = false
            helpDone = Date()
            try await wait(.replace)
            try await typeReplace(to: versions.indices.contains(versionIndex) ? versions[versionIndex].text : s.helpReply2)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send()
            // 发送以后帮回键缩小淡出，后面的键补位；回答卡收起。
            try await pause(0.3)
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.9)) { helpShown = false }
            try await pause(0.3)
            withAnimation(cardMotion) {
                expanded = false
                versions = []
                ask = ""
                askDim = false
            }
        case 6:
            // 小林让你在群里发集合通知；你先随手打一句，再展开回答卡写要求。
            try await pause(0.3)
            try await incoming(s.requestMessage, from: .local)
            try await type(\.field, s.requestField, duration: 0.6)
            try await wait(.drawer)
            withAnimation(cardMotion) { expanded = true }
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
            // 先不发：第 3 步再点润色，改的是输入框里这句正式通知（真键盘 execute 改的是输入框里的字）。
            try await typeReplace(to: s.requestResult)
        case 8:
            // 不满意，换个要求：识意框里「写成正式通知」逐字删掉，填「再简短一点」，再点润色出更短的第 2 版（2/2）。
            try await wait(.askField)
            withAnimation(.easeOut(duration: 0.2)) { askEditing = true }
            try await pause(0.2)
            try await retype(\.ask, to: s.requestAsk2)
            try await wait(.sparkle)
            sparkRunning = true
            withAnimation(.easeOut(duration: 0.2)) { regenerating = true }
            try await pause(reduceMotion ? 0.6 : 1.2)
            withAnimation(.easeOut(duration: 0.2)) {
                regenerating = false
                askEditing = false
                askDim = true
            }
            try await stream(Version(text: s.requestResult2, mode: .rewrite), perChar: 0.04)
            sparkRunning = false
            sparkDone = Date()
            try await wait(.replace)
            try await typeReplace(to: versions.indices.contains(versionIndex) ? versions[versionIndex].text : s.requestResult2)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send()
        case 9:
            try await pause(0.3)
            try await incoming(s.foodMessage, from: .local)
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
        case 10:
            try await wait(.search)
            askRunning = true
            withAnimation(.easeOut(duration: 0.2)) {
                canSearch = false
                searching = true
            }
            try await pause(1)
            withAnimation(cardMotion) {
                searching = false
                searched = true
                cardTall = true
            }
            versions = []
            try await stream(Version(text: s.foodWeb, mode: .answer), perChar: 0.026)
            askRunning = false
            askDone = Date()
        case 11:
            try await wait(.card)
            withAnimation(cardMotion) {
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
            withAnimation(cardMotion) { expanded = false }
        case 12:
            try await pause(0.3)
            // Alex 用英文提醒带伞：先用「简短」润一下，第 3 步再用新建的「英文」风格回他。
            try await incoming(s.styleMessage, from: .foreign)
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
        case 13:
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
        default:
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
            // 翻好的英文发给 Alex（11-25 加）。
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send()
        }
    }

    // MARK: 动作

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// 回答卡展开、收起、变高：键盘变高、对话卡底边跟着键盘顶一起动，同一个弹簧（OC2）；减弱动态效果时 0.2 秒。
    private var cardMotion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)
    }

    /// 等用户点对那一处（抬起才算）。
    private func wait(_ hit: TourTarget) async throws {
        lastTap = nil
        target = hit
        while lastTap != hit { try await pause(0.03) }
        lastTap = nil
        target = nil
        demoDown = false
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
    private func incoming(_ text: String, from speaker: Speaker, copyable: Bool = false) async throws {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { messages.append(Message(text: "", from: speaker, typing: true)) }
        try await pause(reduceMotion ? 0.4 : 0.8)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.72)) {
            messages.removeAll { $0.typing }
            messages.append(Message(text: text, from: speaker, copyable: copyable))
        }
        try await pause(0.4)
    }
}
