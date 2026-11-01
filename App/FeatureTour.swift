import SwiftUI

// 首次打开的功能演示（FT0–FT22）：隐私同意之后、配置接口（OB1）之前，用 App 里画的模拟键盘把润色、改写、提示词、问答、分词各点一遍。
// 结果全是预设内容：不调用 API、不联网、不扣次数、不计入统计；演示里加的提示词也不写进真的提示词列表。
// 0.93 起按「功能演示动效方案」：每一步是连续过程（按下、处理中、出字、打字替换、删字重打），不再整块换图；提示词去模拟的 App 页添加。
// 21 步版：问答用上海美食；第五章「分词 · 插入」3 步，最后演示按住替换键上滑插入；发送后界面依次下滑淡出，再进完成页。
// 润色、改写、提示词三章的对方是说英文的同事 Alex（英文界面是说中文的同事），气泡下带译文；改写、提示词两章各发送一次。
// 小手只做示范；用户自己点了才触发，抬起那一帧才算。
// v308（11-01）按新 AI 栏改：没有放大镜、按住拖动、自动判断和「切换」；润色键、问答键点名字执行、点 ⌄ 弹风格下拉；
// 第三章在下拉里点图钉把「英文」固定到 AI 栏；回答卡标题带风格名和联网标签。剧本见 design/tour/v5/功能演示剧本-新AI栏.md。

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
/// 润色、改写、提示词三章（FT1–FT11）的对方说另一种语言（peer，气泡下带译文，像微信翻译）；问答一章（FT12 起）换回 contact。
private struct TourScript {
    var peer: String
    var peerAvatar: String
    var peerPlaceholder: String
    var peerMessage: String
    var peerMessageNote: String
    /// FT6 发出后对方的回复；FT11 发出后对方的道谢。
    var peerReply: String
    var peerReplyNote: String
    var peerThanks: String
    var peerThanksNote: String
    var contact: String
    var avatar: String
    var placeholder: String
    var original: String
    var polished: String
    var askRewrite: String
    var rewritten: String
    var askShorter: String
    var shorter: String
    var promptName: String
    /// FT9 点了「保持原意」之后的提示词内容；FT10「AI 优化提示词」的预设结果。
    var taggedContent: String
    var improvedContent: String
    /// 提示词编辑页的建议标签（十个）：第一个是提示词本身，第二个是「保持原意」。
    var tags: [String]
    var nineField: String
    var nineResult: String
    var riddleMessage: String
    var riddleField: String
    var riddleAnswer: String
    var riddleRewrite: String
    var riddleReply: String
    var foodMessage: String
    var askFood: String
    var foodAnswer: String
    var foodWeb: String
    var foodPoints: String
    /// 分词面板里的词（从「列要点」的回答切）；hints 是带虚线框提示的几块。
    var words: [String]
    var hints: [Int]
    /// 插入时词和词之间放什么（英文空格，中文、日文不放）。
    var joiner: String
    /// FT20 发出选好的词后对方问去哪家；FT21 输入框里先打的半句，按住替换键上滑把店名接在后面。
    var shopMessage: String
    var askShop: String
    var shops: String
    var insertLead: String

    /// 选中的词连起来：英文逗号、冒号前不加空格。
    func join(_ picked: [String]) -> String {
        picked.reduce("") { text, word in
            text.isEmpty || joiner.isEmpty || [",", ":", "."].contains(word) ? text + word : text + joiner + word
        }
    }

    static var current: TourScript {
        switch Loc.current {
        case .en: return en
        case .ja: return ja
        case .zh, .system: return zh
        }
    }

    static let zh = TourScript(
        peer: "Alex", peerAvatar: "A", peerPlaceholder: "Reply to Alex",
        peerMessage: "Checked the file? Not sure about page 3.", peerMessageNote: "文件看过了吗？第三页我不太确定。",
        peerReply: "You're right. Can you resend it today?", peerReplyNote: "你说得对。今天能改好再发我吗？",
        peerThanks: "Perfect, thanks!", peerThanksNote: "太好了，谢谢！",
        contact: "小林", avatar: "林", placeholder: "回复 小林",
        original: "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看",
        polished: "文件我看过了，整体没问题。第三页有个数字好像不太对，麻烦再核对一下。",
        askRewrite: "翻成英文",
        rewritten: "Checked the file, looks fine overall. One number on page 3 seems off. Could you double-check?",
        askShorter: "再简短一点",
        shorter: "File's fine, but one number on page 3 looks off. Can you check?",
        promptName: "英文",
        taggedContent: "翻成英文，保持原意。",
        improvedContent: "把输入的中文翻成自然、地道的英文。保持原意，不增不减，语气和原文一致；只输出译文。",
        tags: ["翻成英文", "保持原意", "语气礼貌", "适合发微信", "不加新内容", "语气轻松", "适合发邮件", "先说结论", "语气委婉一点", "可以加表情"],
        nineField: "好的我下午三点前改好发你",
        nineResult: "Sure, I'll have it fixed and sent to you before 3 p.m.",
        riddleMessage: "出个脑筋急转弯考考我？",
        riddleField: "大象装进冰箱需要几步",
        riddleAnswer: "三步：打开冰箱门，把大象放进去，关上冰箱门。",
        riddleRewrite: "考你一个脑筋急转弯：把大象装进冰箱，一共需要几步？",
        riddleReply: "三步，打开冰箱，把大象放进去，关上冰箱",
        foodMessage: "下周去上海，有什么美食么？",
        askFood: "上海有什么必吃的美食",
        foodAnswer: "上海菜偏甜，浓油赤酱。常被推荐的有小笼包、生煎包、红烧肉、葱油拌面、蟹壳黄、排骨年糕。具体去哪家、最近口碑怎么样，我这里没有最新信息，可以联网查一下。",
        foodWeb: "最近口碑好的上海美食：早餐首选小笼包和生煎包，豫园、黄河路一带最集中；本帮菜推荐红烧肉、油爆虾、腌笃鲜；小吃可以试葱油拌面和排骨年糕。热门老店饭点常要排队半小时以上，建议错峰去。",
        foodPoints: "· 必吃：小笼包、生煎包、葱油拌面\n· 本帮菜：红烧肉、油爆虾、腌笃鲜\n· 去哪吃：豫园、黄河路一带\n· 提示：老店饭点要排队，错峰去",
        words: ["·", "必吃", "：", "小笼包", "、", "生煎包", "、", "葱油拌面", "·", "本帮菜", "：", "红烧肉", "、", "油爆虾", "、", "腌笃鲜",
                "·", "去哪吃", "：", "豫园", "、", "黄河路", "一带", "·", "提示", "：", "老店", "饭点", "要排队", "，", "错峰去"],
        hints: [3, 5, 7], joiner: "",
        shopMessage: "小笼包去哪家好？",
        askShop: "上海小笼包哪家好吃",
        shops: "· 南翔馒头店：豫园老店，招牌蟹粉小笼\n· 佳家汤包：黄河路，现包现蒸\n· 鼎泰丰：新天地，环境好、排队少",
        insertLead: "可以去这几家：")

    static let en = TourScript(
        peer: "Wang Lei", peerAvatar: "王", peerPlaceholder: "Reply to Wang Lei",
        peerMessage: "文件看过了吗？第三页我不太确定。", peerMessageNote: "Checked the file? Not sure about page 3.",
        peerReply: "你说得对。今天能改好再发我吗？", peerReplyNote: "You're right. Can you resend it today?",
        peerThanks: "太好了，谢谢！", peerThanksNote: "Perfect, thanks!",
        contact: "Alex", avatar: "A", placeholder: "Reply to Alex",
        original: "yeah i looked at the file its mostly fine but theres a number on page 3 that looks off can u check again",
        polished: "I've reviewed the file and it looks fine overall. One number on page 3 seems off. Could you double-check it?",
        askRewrite: "Translate into Chinese",
        rewritten: "文件我看过了，整体没问题。第三页有个数字好像不太对，麻烦再核对一下。",
        askShorter: "Make it shorter",
        shorter: "文件没问题，第三页有个数字不对，再核对一下。",
        promptName: "Chinese",
        taggedContent: "Translate into Chinese. Keep the meaning.",
        improvedContent: "Translate the input into natural, idiomatic Chinese. Keep the meaning without adding or removing anything, match the original tone, and output only the translation.",
        tags: ["Translate into Chinese", "Keep the meaning", "Polite tone", "For chat apps", "No new content", "Casual tone", "For email", "Lead with the point", "Softer tone", "Emoji OK"],
        nineField: "ok ill fix it and send it to u before 3",
        nineResult: "好的，我下午三点前改好发给你。",
        riddleMessage: "Got a riddle for me?",
        riddleField: "how many steps to put an elephant in a fridge",
        riddleAnswer: "Three: open the fridge, put the elephant in, close the door.",
        riddleRewrite: "Here's a riddle for you: how many steps does it take to put an elephant in a fridge?",
        riddleReply: "Three: open the fridge, put the elephant in, close the fridge.",
        foodMessage: "I'm going to Shanghai next week. Any good food there?",
        askFood: "must-try food in Shanghai",
        foodAnswer: "Shanghai food leans sweet and rich, with lots of soy braising. Often recommended: xiaolongbao (soup dumplings), shengjianbao (pan-fried buns), red-braised pork, scallion oil noodles, crab-shell sesame cakes and pork chop rice cakes. I don't have the latest on where to go or recent reviews, so try searching the web.",
        foodWeb: "Well-reviewed Shanghai food lately: for breakfast, xiaolongbao and shengjianbao, mostly around Yuyuan Garden and Huanghe Road. For local dishes, red-braised pork, oil-fried shrimp and yanduxian soup. For snacks, scallion oil noodles and pork chop rice cakes. Popular old shops often have 30-minute queues at mealtimes, so go off-peak.",
        foodPoints: "· Must-try: xiaolongbao, shengjianbao, scallion oil noodles\n· Local dishes: red-braised pork, oil-fried shrimp, yanduxian soup\n· Where: around Yuyuan Garden and Huanghe Road\n· Tip: old shops queue at mealtimes, go off-peak",
        words: ["·", "Must-try", ":", "xiaolongbao", ",", "shengjianbao", ",", "scallion oil noodles", "·", "Local dishes", ":", "red-braised pork", ",",
                "oil-fried shrimp", ",", "yanduxian soup", "·", "Where", ":", "around", "Yuyuan Garden", "and", "Huanghe Road",
                "·", "Tip", ":", "old shops", "queue", "at mealtimes", ",", "go off-peak"],
        hints: [3, 5, 7], joiner: " ",
        shopMessage: "Where should I go for xiaolongbao?",
        askShop: "best xiaolongbao in Shanghai",
        shops: "· Nanxiang Mantou Dian: old shop at Yuyuan, famous crab xiaolongbao\n· Jiajia Tangbao: Huanghe Road, made to order\n· Din Tai Fung: Xintiandi, nice setting, shorter queues",
        insertLead: "Try these places:")

    static let ja = TourScript(
        peer: "Alex", peerAvatar: "A", peerPlaceholder: "Alex に返信",
        peerMessage: "Checked the file? Not sure about page 3.", peerMessageNote: "資料、見てもらえました？3ページ目がちょっと気になって。",
        peerReply: "You're right. Can you resend it today?", peerReplyNote: "確かに。今日中に直して送ってもらえますか？",
        peerThanks: "Perfect, thanks!", peerThanksNote: "助かります、ありがとう！",
        contact: "佐藤さん", avatar: "佐", placeholder: "佐藤さんに返信",
        original: "資料見たよだいたい大丈夫だけど3ページ目の数字がなんか変な気がするからもう一回見てくれる",
        polished: "資料を確認しました。全体的には問題ありませんが、3ページ目の数字が少し気になります。もう一度ご確認いただけますか。",
        askRewrite: "英語に翻訳",
        rewritten: "Checked the file, looks fine overall. One number on page 3 seems off. Could you double-check?",
        askShorter: "もっと短く",
        shorter: "File's fine, but one number on page 3 looks off. Can you check?",
        promptName: "英語",
        taggedContent: "英語に翻訳。意味はそのまま。",
        improvedContent: "入力された文章を自然で正確な英語に翻訳。意味はそのまま、足したり削ったりせず、口調も原文に合わせる。訳文だけを出力。",
        tags: ["英語に翻訳", "意味はそのまま", "丁寧な口調", "チャット向け", "内容を足さない", "気軽な口調", "メール向け", "結論から", "やわらかい口調", "絵文字OK"],
        nineField: "了解3時までに直して送るね",
        nineResult: "Got it. I'll fix it and send it to you by 3.",
        riddleMessage: "何かなぞなぞ出してよ",
        riddleField: "象を冷蔵庫に入れるには何ステップ",
        riddleAnswer: "3ステップです。冷蔵庫を開ける、象を入れる、扉を閉める。",
        riddleRewrite: "なぞなぞです。象を冷蔵庫に入れるには、何ステップ必要でしょう？",
        riddleReply: "3ステップ。冷蔵庫を開けて、象を入れて、冷蔵庫を閉める",
        foodMessage: "来週上海に行くんですが、おいしいものありますか？",
        askFood: "上海で絶対食べたいもの",
        foodAnswer: "上海料理は甘めで、濃い醤油味が特徴です。よくすすめられるのは小籠包、生煎包（焼き小籠包）、紅焼肉、葱油拌麺、蟹殻黄、排骨年糕など。どの店がいいか、最近の評判は手元に最新情報がないので、ウェブで調べてみてください。",
        foodWeb: "最近評判のいい上海グルメ：朝ごはんなら小籠包と生煎包で、豫園や黄河路あたりに集まっています。上海料理なら紅焼肉、油爆蝦、腌篤鮮。軽食なら葱油拌麺や排骨年糕も。人気の老舗は食事時に 30 分以上並ぶことが多いので、時間をずらすのがおすすめです。",
        foodPoints: "· 必食：小籠包、生煎包、葱油拌麺\n· 上海料理：紅焼肉、油爆蝦、腌篤鮮\n· どこで：豫園、黄河路あたり\n· ヒント：老舗は食事時に混むので時間をずらして",
        words: ["·", "必食", "：", "小籠包", "、", "生煎包", "、", "葱油拌麺", "·", "上海料理", "：", "紅焼肉", "、", "油爆蝦", "、", "腌篤鮮",
                "·", "どこで", "：", "豫園", "、", "黄河路", "あたり", "·", "ヒント", "：", "老舗は", "食事時に", "混むので", "時間を", "ずらして"],
        hints: [3, 5, 7], joiner: "",
        shopMessage: "小籠包はどこの店がいいですか？",
        askShop: "上海で小籠包がおいしい店",
        shops: "· 南翔饅頭店：豫園の老舗、名物は蟹みそ小籠包\n· 佳家湯包：黄河路、注文後に包んで蒸す\n· 鼎泰豊：新天地、きれいで比較的すいている",
        insertLead: "このあたりがおすすめです：")
}

// MARK: - 步骤

/// 小手能指的地方，也是能点的地方。
private enum TourTarget: Hashable {
    /// sparkle：润色键名字那半边（收起、展开都是它）；chevron：润色键的 ⌄；askKey：问答键名字那半边。
    case sparkle, chevron, askKey, undo, redo, drawer, replace, send, search, card, insert
    /// 润色风格下拉：某一条右边的图钉、最底下「＋ 添加润色风格」；AI 栏上固定的「✨ 英文」。
    case pin(Int), addStyle, pinned
    /// 模拟的 App 提示词页：「添加提示词」「✨ AI 优化提示词」「用这一版」「完成」。
    case addPrompt, improve, useVersion, done
    /// 编辑页的建议标签。
    case tag(Int)
    /// 结果卡右下展开、问答键的 ⌄、问答风格下拉里的一条（0 直击要害，1 详细，2 列要点，3 通俗）。
    case expand, answerStyle
    case answerPill(Int)
    /// 润色风格下拉里的一条：0 润色，1–4 内置，5 演示里加的那条。
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
        case .prompt: return L("润色风格", "Polish styles", "整えるスタイル")
        case .answer: return L("问答", "Answer", "回答")
        case .words: return L("分词 · 插入", "Pick & Insert", "単語・挿入")
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
        case .rewrite: return Color(light: 0xEDE9FE, dark: 0x3B1F66)
        case .prompt: return Color(light: 0xE0E7FF, dark: 0x262A5C)
        case .answer: return Color(light: 0xE0F2FE, dark: 0x0C3448)
        case .words: return Color(light: 0xD1FAE5, dark: 0x063B2C)
        }
    }
}

/// 一步的章节、序号、标题、说明。FT6 分两段（part 1：替换后发送）；FT11 分三段（part 1：发送，part 2：随时换回）。
/// 21 步版：问答用上海美食，第五章「分词 · 插入」3 步（长按选词插入、接着问去哪家、按住替换键上滑插入）。
private struct TourStep {
    var chapter: TourChapter
    var index: Int
    var total: Int
    var title: String
    var detail: String

    static let count = 21

    static func info(_ step: Int, part: Int) -> TourStep {
        switch step {
        case 1: return TourStep(chapter: .polish, index: 1, total: 2,
                                title: L("点击「✨ 润色」，润色输入内容", "Tap ✨ Polish to polish your text", "「✨ 整える」をタップして文章を整える"),
                                detail: L("AI 将修正语病和标点，并直接替换输入框中的文字。", "AI fixes grammar and punctuation and replaces the text in the input field.", "AI が文法と句読点を直し、入力欄の文章をそのまま置き換えます。"))
        case 2: return TourStep(chapter: .polish, index: 2, total: 2,
                                title: L("润色完成，可随时撤销", "Done. You can undo anytime", "完了。いつでも元に戻せます"),
                                detail: L("点击 ↶ 恢复原文；点击 ↷ 重新应用润色结果。", "Tap ↶ to restore the original; tap ↷ to apply the polished text again.", "↶ で元の文章に戻り、↷ で整えた文章を再び適用します。"))
        case 3: return TourStep(chapter: .rewrite, index: 1, total: 4,
                                title: L("点击此处，展开回答卡", "Tap here to open the answer card", "ここをタップして回答カードを開く"),
                                detail: L("展开后，可以在下面的框里写修改要求或问题。", "Then type an instruction or a question in the box below.", "開いたら、下の欄に修正の指示や質問を入力できます。"))
        case 4: return TourStep(chapter: .rewrite, index: 2, total: 4,
                                title: L("写下要求，点击「✨ 润色」", "Write an instruction, then tap ✨ Polish", "指示を書いて「✨ 整える」をタップ"),
                                detail: L("下面框里的要求会一起带上，AI 按要求改写输入框里的话。", "The instruction in the box below goes along, and AI rewrites your text as asked.", "下の欄の指示もいっしょに送られ、AI が指示どおりに文章を書き換えます。"))
        case 5: return TourStep(chapter: .rewrite, index: 3, total: 4,
                                title: L("点击「替换」，应用结果", "Tap Replace to use the result", "「置換」で結果を反映"),
                                detail: L("改写结果显示在回答卡中。点击「替换」写入输入框；按住上滑可改为「插入」，保留原文。", "The rewrite appears in the card. Tap Replace to put it in the input field; hold and slide up for Insert to keep the original.", "書き換え結果はカードに表示されます。「置換」で入力欄に反映し、長押しして上にスライドすると元の文章を残す「挿入」になります。"))
        case 6 where part == 1: return TourStep(chapter: .rewrite, index: 4, total: 4,
                                title: L("改个要求，再点一次", "Change the instruction and tap again", "指示を変えてもう一度"),
                                detail: L("满意后点击「替换」，再点击「发送」。", "Happy with it? Tap Replace, then Send.", "よければ「置換」、続いて「送信」をタップします。"))
        case 6: return TourStep(chapter: .rewrite, index: 4, total: 4,
                                title: L("改个要求，再点一次", "Change the instruction and tap again", "指示を変えてもう一度"),
                                detail: L("把要求改成「再简短一点」，再点击「✨ 润色」。", "The instruction now says \"Make it shorter\". Tap ✨ Polish again.", "指示を「もっと短く」に変えて、もう一度「✨ 整える」をタップします。"))
        case 7: return TourStep(chapter: .prompt, index: 1, total: 5,
                                title: L("常用英文发消息？加一个润色风格", "Write in Chinese often? Add a polish style", "英語でよく送るなら、整えるスタイルを追加"),
                                detail: L("不用每次都写「翻成英文」。点击「✨ 润色」右边的 ⌄，再点击「＋ 添加润色风格」。", "No need to type \"Translate into Chinese\" every time. Tap the ⌄ next to ✨ Polish, then tap + Add Polish Style.", "毎回「英語に翻訳」と書かなくても大丈夫です。「✨ 整える」の右の ⌄ をタップし、「＋ 整えるスタイルを追加」をタップします。"))
        case 8: return TourStep(chapter: .prompt, index: 2, total: 5,
                                title: L("在 App 里添加润色风格", "Add one in the app", "アプリで追加"),
                                detail: L("润色风格都在 App 的「AI › 润色风格」里管理，可以改名、改内容、调顺序。点击「添加润色风格」。", "Polish styles are managed under AI › Polish styles in the app, where you can rename, edit and reorder them. Tap Add Polish Style.", "整えるスタイルはアプリの「AI › 整えるスタイル」で管理し、名前や内容、並び順を変えられます。「整えるスタイルを追加」をタップしてください。"))
        case 9: return TourStep(chapter: .prompt, index: 3, total: 5,
                                title: L("点建议标签，快速补充要求", "Tap a suggestion to add to it", "候補タグで指示をすばやく追加"),
                                detail: L("名称和内容已填好。点一下建议标签，就接到内容后面；再点一下去掉。点击「保持原意」。", "The name and prompt are filled in. Tap a suggestion to add it to the prompt; tap again to remove it. Tap Keep the meaning.", "名前と内容は入力済みです。候補タグをタップするとプロンプトの後ろに付き、もう一度タップすると外れます。「意味はそのまま」をタップしてください。"))
        case 10: return TourStep(chapter: .prompt, index: 4, total: 5,
                                 title: L("AI 帮你把要求写清楚", "Let AI write it clearly", "AI が指示を整理"),
                                 detail: L("点击「✨ AI 优化提示词」，AI 会把要求改得更完整。看完点击「用这一版」，再点击「完成」。", "Tap ✨ Improve with AI and AI makes the instruction more complete. Tap Use This, then Done.", "「✨ AI でプロンプトを改善」をタップすると、AI が指示をより分かりやすくします。「これを使う」、続いて「完了」をタップしてください。"))
        case 11 where part == 0: return TourStep(chapter: .prompt, index: 5, total: 5,
                                 title: L("固定到 AI 栏，一键出英文", "Pin it for one-tap Chinese", "AI バーに固定して、ワンタップで英語に"),
                                 detail: L("点击「英文」右边的图钉，AI 栏多出一颗「✨ 英文」。点击它，输入框里的中文直接改成英文。", "Tap the pin next to Chinese, and ✨ Chinese appears on the AI bar. Tap it and your text turns into Chinese in the input field.", "「英語」の右のピンをタップすると、AI バーに「✨ 英語」が出ます。タップすると入力欄の文章がそのまま英語になります。"))
        case 11: return TourStep(chapter: .prompt, index: 5, total: 5,
                                 title: L("发给对方", "Send it", "相手に送る"),
                                 detail: L("点击「发送」，发给对方。润色键还是「润色」，不用换回。", "Tap Send to send it. The polish key still says Polish; nothing to switch back.", "「送信」をタップして相手に送ります。整えるキーは「整える」のままなので、戻す必要はありません。"))
        case 12: return TourStep(chapter: .answer, index: 1, total: 7,
                                 title: L("点击「问答」，直接回答", "Tap Ask to get an answer", "「質問」をタップしてすぐ回答"),
                                 detail: L("输入框里是个问题？点「问答」，回答卡自动展开并回答。", "Is your text a question? Tap Ask and the answer card opens with the answer.", "入力欄の文章が質問なら、「質問」をタップすると回答カードが開いて答えます。"))
        case 13: return TourStep(chapter: .answer, index: 2, total: 7,
                                 title: L("其实想发给对方？点击「✨ 润色」", "Meant to send it? Tap ✨ Polish", "相手に送りたいなら「✨ 整える」"),
                                 detail: L("想把这句发出去，不想要答案？点润色键，改写这句话。", "Want to send this instead of getting an answer? Tap the polish key to rewrite the sentence.", "答えではなく、この文を送りたいときは整えるキーで書き直します。"))
        case 14: return TourStep(chapter: .answer, index: 3, total: 7,
                                 title: L("替换后发送", "Replace, then send", "置換して送信"),
                                 detail: L("点击「替换」写入输入框，再点击「发送」。", "Tap Replace to put it in the input field, then tap Send.", "「置換」で入力欄に反映し、「送信」をタップします。"))
        case 15: return TourStep(chapter: .answer, index: 4, total: 7,
                                 title: L("输入问题，点击「问答」", "Type a question, then tap Ask", "質問を入力して「質問」をタップ"),
                                 detail: L("在下面的框里写问题，点「问答」就回答。", "Write your question in the box below and tap Ask to get an answer.", "下の欄に質問を書いて「質問」をタップすると回答します。"))
        case 16: return TourStep(chapter: .answer, index: 5, total: 7,
                                 title: L("回答显示不全？点击展开", "Answer cut off? Expand it", "回答が収まらないときは展開"),
                                 detail: L("结果卡默认显示 2 行。点击右下角的展开按钮可显示 4 行，内容再长可在卡片里上下滑动。", "The result card shows 2 lines by default. Tap the expand button at the bottom right to show 4; scroll inside the card for more.", "結果カードは通常 2 行表示です。右下の展開ボタンで 4 行になり、さらに長い場合はカード内をスクロールできます。"))
        case 17: return TourStep(chapter: .answer, index: 6, total: 7,
                                 title: L("需要实时信息时，联网查询", "Need live info? Search the web", "最新情報が必要なときはウェブ検索"),
                                 detail: L("默认回答基于模型已有知识。点击「使用联网查询」获取最新信息（通义千问、Kimi、智谱 GLM、腾讯混元支持）。", "Answers use the model's own knowledge by default. Tap Search the web for the latest information (supported by Qwen, Kimi, Zhipu GLM and Tencent Hunyuan).", "通常はモデルの知識で回答します。「ウェブで調べる」で最新情報を取得できます（Qwen、Kimi、Zhipu GLM、Tencent Hunyuan に対応）。"))
        case 18: return TourStep(chapter: .answer, index: 7, total: 7,
                                 title: L("想要更有条理？换个问答风格", "Want it tidier? Change the answer style", "整理したいときは回答スタイルを変更"),
                                 detail: L("点击「问答」右边的 ⌄，选「列要点」，再点击「问答」重新回答。", "Tap the ⌄ next to Ask, pick Key points, then tap Ask to answer again.", "「質問」の右の ⌄ で「要点を列挙」を選び、もう一度「質問」をタップします。"))
        case 19: return TourStep(chapter: .words, index: 1, total: 3,
                                 title: L("长按结果卡，选词插入", "Hold the card to pick words", "カードを長押しして単語を挿入"),
                                 detail: L("只需部分内容时，长按结果卡，点选或横划选中词语，再点击「插入」。", "Need only part of it? Hold the result card, tap or swipe to select words, then tap Insert.", "一部だけ使いたいときは、結果カードを長押しし、タップかスワイプで単語を選んで「挿入」をタップしてください。"))
        case 20: return TourStep(chapter: .words, index: 2, total: 3,
                                 title: L("发送后，接着问去哪家", "Send it, then ask where to go", "送信して、お店を聞く"),
                                 detail: L("点击「发送」。小林想知道去哪家吃，框里已填好问题，点击「问答」。", "Tap Send. Alex wants to know where to eat; the question is already in the box, so tap Ask.", "「送信」をタップします。佐藤さんがお店を知りたがっています。欄に質問が入っているので、「質問」をタップしてください。"))
        default: return TourStep(chapter: .words, index: 3, total: 3,
                                 title: L("按住替换键上滑，插入回答", "Hold Replace and slide up to insert", "置換キーを上にスライドして挿入"),
                                 detail: L("点一下「替换」会换掉输入框里的话。按住往上滑到「插入」再松手，回答接在原来的字后面。", "Tapping Replace swaps out your text. Hold it, slide up to Insert and let go, and the answer goes after what you wrote.", "「置換」をタップすると入力欄の文章が置き換わります。長押しして「挿入」まで上にスライドして離すと、回答が元の文章の後ろに入ります。"))
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
        /// 对方消息下面的译文。
        var note: String?
        var mine = false
        var typing = false
    }

    let script = TourScript.current
    var reduceMotion = false

    /// 0 欢迎，1–21 演示，22 完成。
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

    /// 润色风格下拉开着（FT7、FT11）；演示里加的那条风格；「✨ 英文」固定到 AI 栏、刚弹进来那一下；它正在出字。
    @Published var promptsOpen = false
    @Published var customPrompt: String?
    @Published var customPop = false
    @Published var pinnedCustom = false
    @Published var pinRunning = false
    @Published var selectedPrompt = 0
    /// 模拟的 App 提示词页：列表或添加页；nil 时显示键盘。
    enum AppPage { case list, edit }
    @Published var appPage: AppPage?
    @Published var sheetName = ""
    @Published var sheetContent = ""
    @Published var pickedTags: Set<Int> = []
    @Published var improving = false
    @Published var improved: String?

    /// 结果卡展开到 4 行；问答风格下拉开着；当前问答风格（0 直击要害，2 列要点）。
    @Published var cardTall = false
    @Published var answerStylesOpen = false
    @Published var answerStyle = 0
    /// 回答卡标题上的风格：重新回答时才跟上 answerStyle（FT18 选完「列要点」，标题等点了「问答」再换）。
    @Published var cardAnswerStyle = 0

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
    /// FT21 发送后的收场：1 顶栏、2 标题说明、3 对话卡依次下滑淡出，4 键盘沉到屏幕外。
    @Published var outro = 0

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
                // 收场动画播完 0.1 秒就进完成页。
                try await self.pause(next == TourStep.count ? 0.1 : 0.6)
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
        // FT21 只认按住替换键上滑，点一下不算。
        if hit == target, hit != .insert || !picked.isEmpty, dragTarget != hit {
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

    /// 这一步要按住往上拖的那一颗：FT21 替换键（上滑插入）。
    var dragTarget: TourTarget? { step == TourStep.count ? .replace : nil }

    /// FT21：按住往上拖。只认上滑过 16 后松手。
    func drag(_ translation: CGFloat?, ended: Bool) {
        guard let hit = dragTarget, target == hit else { return }
        if ended {
            dragging = false
            if dragPick { lastTap = hit } else { wrong() }
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
        // 从上一步顺着走过来时，留住用户自己选的词（返回时用虚线框那一段）。
        let fromPrevious = step == n - 1
        let sentWords = messages.last(where: \.mine)?.text
        let typedWords = field
        switch n {
        case ...6: messages = [Message(text: s.peerMessage, note: s.peerMessageNote)]
        case 7...10: messages = [Message(text: s.shorter, mine: true), Message(text: s.peerReply, note: s.peerReplyNote)]
        case 11: messages = [Message(text: s.shorter, mine: true), Message(text: s.peerReply, note: s.peerReplyNote)]
        default: messages = []
        }
        if n >= 13 { messages = [Message(text: s.riddleMessage)] }
        if n >= 15 {
            messages = [Message(text: s.riddleMessage), Message(text: s.riddleRewrite, mine: true), Message(text: s.riddleReply)]
        }
        if n >= 16 { messages.append(Message(text: s.foodMessage)) }
        if n >= 21 {
            messages += [Message(text: fromPrevious ? sentWords ?? pickedHints : pickedHints, mine: true), Message(text: s.shopMessage)]
        }

        switch n {
        case ...1: field = s.original
        case 2: field = s.polished
        case 3...5: field = s.original
        case 6: field = s.rewritten
        case 13, 14: field = s.riddleField
        case 20: field = fromPrevious && !typedWords.isEmpty ? typedWords : pickedHints
        default: field = ""
        }
        fieldDim = false
        expanded = (4...7).contains(n) || n >= 13
        switch n {
        case 4, 5, 6: ask = s.askRewrite
        case 7: ask = s.askShorter
        // FT12 点「问答」时自动填进识意框的那句，一直留到 FT15 换成新问题。
        case 13...15: ask = s.riddleField
        case 16...20: ask = s.askFood
        case 21: ask = s.askShop
        default: ask = ""
        }
        switch n {
        case 5, 6: card = s.rewritten; cardMode = .rewrite
        case 7: card = s.shorter; cardMode = .rewrite
        case 13: card = s.riddleAnswer; cardMode = .answer
        case 14: card = s.riddleRewrite; cardMode = .rewrite
        case 16, 17: card = s.foodAnswer; cardMode = .answer
        case 18: card = s.foodWeb; cardMode = .answer
        case 19, 20: card = s.foodPoints; cardMode = .answer
        case 21: card = s.shops; cardMode = .answer
        default: card = nil; cardMode = nil
        }
        generating = false
        promptsOpen = (8...11).contains(n)
        customPrompt = n >= 11 ? s.promptName : nil
        customPop = false
        pinnedCustom = n >= 12
        pinRunning = false
        selectedPrompt = 0
        appPage = n == 9 || n == 10 ? .edit : nil
        sheetName = n == 10 ? s.promptName : ""
        sheetContent = n == 10 ? s.taggedContent : ""
        pickedTags = n == 10 ? [0, 1] : []
        improving = false
        improved = nil
        sparkRunning = false
        sparkDone = nil
        undoOn = n == 2
        redoOn = n == 3
        canSearch = n == 16 || n == 17
        searching = false
        searched = n >= 18
        cardTall = (17...19).contains(n) || n == 21
        answerStylesOpen = false
        answerStyle = n >= 19 ? 2 : 0
        cardAnswerStyle = answerStyle
        panel = false
        picked = []
        dragPick = false
        dragging = false
        sendReady = false
        outro = 0
    }

    /// 返回到 FT20 时输入框里的词：虚线框那一段（含中间的顿号）。
    private var pickedHints: String {
        guard let first = script.hints.first, let last = script.hints.last else { return "" }
        return script.join(Array(script.words[first...last]))
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
            try await wait(.sparkle)
            try await generate(.rewrite, s.rewritten)
        case 5:
            try await wait(.replace)
            try await typeReplace(\.field, to: s.rewritten)
        case 6:
            try await retype(\.ask, to: s.askShorter)
            try await wait(.sparkle)
            try await generate(.rewrite, s.shorter)
            try await pause(0.4)
            withAnimation(.easeOut(duration: 0.25)) { part = 1 }
            try await wait(.replace)
            try await typeReplace(\.field, to: s.shorter)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send(reply: s.peerReply, note: s.peerReplyNote)
        case 7:
            try await pause(0.4)
            withAnimation(.easeOut(duration: 0.25)) { expanded = false }
            try await pause(0.3)
            try await wait(.chevron)
            withAnimation(.easeOut(duration: 0.2)) { promptsOpen = true }
            try await pause(0.3)
            // 下拉最底下「＋ 添加润色风格」去 App（v308）。
            try await wait(.addStyle)
        case 8:
            // 润色风格在 App 里管：键盘下沉，模拟的 App 润色风格页升起。
            withAnimation(.easeOut(duration: 0.35)) { appPage = .list }
            try await pause(0.4)
            try await wait(.addPrompt)
        case 9:
            withAnimation(.easeOut(duration: 0.3)) { appPage = .edit }
            try await pause(0.4)
            try await type(\.sheetName, s.promptName, duration: 0.3)
            try await type(\.sheetContent, s.tags[0], duration: 0.4)
            withAnimation(.easeOut(duration: 0.15)) { pickedTags = [0] }
            try await wait(.tag(1))
            withAnimation(.easeOut(duration: 0.15)) { pickedTags = [0, 1] }
            try await retype(\.sheetContent, to: s.taggedContent)
        case 10:
            try await wait(.improve)
            withAnimation(.easeOut(duration: 0.2)) { improving = true }
            try await pause(0.8)
            improving = false
            improved = ""
            let ticks = 24
            for i in 1...ticks {
                improved = String(s.improvedContent.prefix(s.improvedContent.count * i / ticks))
                try await pause(Self.typeDuration(s.improvedContent) / Double(ticks))
            }
            try await wait(.useVersion)
            withAnimation(.easeOut(duration: 0.2)) {
                sheetContent = s.improvedContent
                improved = nil
            }
            try await wait(.done)
        case 11:
            // App 页下沉、键盘升回，下拉还开着，末尾多出「英文」。
            withAnimation(.easeOut(duration: 0.35)) { appPage = nil }
            try await pause(0.4)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                customPrompt = sheetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? s.promptName : sheetName
            }
            try await pause(0.2)
            // 点图钉：变实心、轻震，下拉收起，「✨ 英文」弹进 AI 栏（0.9→1，0.2 秒）。
            try await wait(.pin(5))
            Self.haptic()
            withAnimation(.easeOut(duration: 0.15)) { pinnedCustom = true }
            try await pause(0.25)
            // 下拉收起的同时，「✨ 英文」从 0.9 倍弹进 AI 栏。
            withAnimation(.easeOut(duration: 0.2)) { promptsOpen = false }
            try await pause(0.25)
            try await retype(\.field, to: s.nineField)
            // 点「✨ 英文」：按它的风格出英文，润色键还写「润色」。
            try await wait(.pinned)
            pinRunning = true
            try await pause(0.6)
            try await typeReplace(\.field, to: s.nineResult)
            pinRunning = false
            try await pause(0.4)
            withAnimation(.easeOut(duration: 0.25)) { part = 1 }
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send(reply: s.peerThanks, note: s.peerThanksNote)
        case 12:
            // 收着点「问答」：回答卡升起，识意框填上输入框里的这句，回答它。
            try await incoming(s.riddleMessage)
            try await retype(\.field, to: s.riddleField)
            try await wait(.askKey)
            withAnimation(.easeOut(duration: 0.25)) { expanded = true }
            try await pause(0.3)
            try await type(\.ask, s.riddleField, duration: 0.3)
            try await generate(.answer, s.riddleAnswer)
        case 13:
            // 识意框里是自动填进去的问题，点润色键不把它当要求，只改写输入框里的话。
            try await wait(.sparkle)
            try await generate(.rewrite, s.riddleRewrite, delay: 0.5)
        case 14:
            try await wait(.replace)
            try await typeReplace(\.field, to: s.riddleRewrite)
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send(reply: s.riddleReply)
        case 15:
            try await incoming(s.foodMessage)
            try await retype(\.ask, to: s.askFood)
            try await wait(.askKey)
            try await generate(.answer, s.foodAnswer)
            withAnimation(.easeIn(duration: 0.3)) { canSearch = true }
        case 16:
            try await wait(.expand)
            withAnimation(.easeOut(duration: 0.25)) { cardTall = true }
        case 17:
            try await wait(.search)
            withAnimation(.easeOut(duration: 0.2)) {
                canSearch = false
                searching = true
            }
            try await pause(1)
            searching = false
            searched = true
            try await stream(s.foodWeb)
        case 18:
            try await wait(.answerStyle)
            withAnimation(.easeOut(duration: 0.2)) { answerStylesOpen = true }
            try await wait(.answerPill(2))
            // 选完只收起，不自动执行；键上还写「问答」。
            withAnimation(.easeOut(duration: 0.2)) {
                answerStyle = 2
                answerStylesOpen = false
            }
            try await wait(.askKey)
            // 沿用这次联网，重新回答。
            try await generate(.answer, s.foodPoints, keepSearched: true)
        case 19:
            try await wait(.card)
            withAnimation(.easeOut(duration: 0.25)) {
                cardTall = false
                panel = true
            }
            try await pause(0.3)
            target = .words
            while picked.isEmpty { try await pause(0.05) }
            try await wait(.insert)
            let words = s.join(picked.sorted().map { s.words[$0] })
            withAnimation(.easeOut(duration: 0.15)) { panel = false }
            try await pause(0.2)
            try await type(\.field, words, duration: 0.5)
        case 20:
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            try await send(reply: s.shopMessage)
            try await retype(\.ask, to: s.askShop)
            try await wait(.askKey)
            withAnimation(.easeOut(duration: 0.25)) { cardTall = true }
            // 沿用联网和「列要点」。
            try await generate(.answer, s.shops, keepSearched: true)
        default:
            try await type(\.field, s.insertLead, duration: 0.35)
            try await wait(.replace)
            // 上滑插入：原来的字不动，回答换行接在后面。
            try await type(\.field, "\n" + s.shops, duration: Self.typeDuration(s.shops))
            withAnimation(.easeOut(duration: 0.2)) { sendReady = true }
            try await wait(.send)
            let sent = field
            withAnimation(.easeOut(duration: 0.3)) {
                sendReady = false
                field = ""
                messages.append(Message(text: sent, mine: true))
            }
            try await pause(0.9)
            // 收场：顶栏、标题说明、对话卡从上往下依次下滑淡出，键盘沉到屏幕外。
            for block in 1...3 {
                withAnimation(.easeIn(duration: 0.28)) { outro = block }
                try await pause(0.06)
            }
            try await pause(0.16)
            withAnimation(.easeIn(duration: 0.35)) { outro = 4 }
            try await pause(0.35)
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
    private func generate(_ mode: Mode, _ text: String, delay: Double = 0.6, keepSearched: Bool = false) async throws {
        withAnimation(.easeOut(duration: 0.2)) {
            generating = true
            canSearch = false
            if !keepSearched { searched = false }
        }
        try await pause(delay)
        withAnimation(.easeOut(duration: 0.2)) {
            cardMode = mode
            if mode == .answer { cardAnswerStyle = answerStyle }
            generating = false
        }
        try await stream(text)
    }

    /// 演示接口出字：和写进输入框一样快，0.25–0.4 秒从左往右打出来（cvbk 10-29：回答卡里出字要快）。
    private func stream(_ text: String) async throws {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { card = text }
            return
        }
        card = ""
        let ticks = max(Int(Self.typeDuration(text) * 60), 1)
        for i in 1...ticks {
            card = String(text.prefix(text.count * i / ticks))
            try await pause(Self.typeDuration(text) / Double(ticks))
        }
    }

    static func typeDuration(_ text: String) -> Double {
        min(0.25 + Double(text.count) * 0.0015, 0.4)
    }

    /// 结果写进输入框：原文变淡 0.15 秒，新字从左往右打出来（0.25–0.4 秒，按字数，和真键盘写入一样快）。
    private func typeReplace(_ path: ReferenceWritableKeyPath<TourModel, String>, to text: String) async throws {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { self[keyPath: path] = text }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { fieldDim = true }
        try await pause(0.15)
        self[keyPath: path] = ""
        fieldDim = false
        try await type(path, text, duration: Self.typeDuration(text))
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

    /// 点了「发送」：输入框清空，气泡上移进对话；0.8 秒后对方回复。
    private func send(reply: String, note: String? = nil) async throws {
        let sent = field
        withAnimation(.easeOut(duration: 0.3)) {
            sendReady = false
            field = ""
            messages.append(Message(text: sent, mine: true))
        }
        try await pause(0.8)
        try await incoming(reply, note: note)
    }

    /// 对方发来新消息：「正在输入…」0.6 秒再弹出。
    private func incoming(_ text: String, note: String? = nil) async throws {
        withAnimation(.easeOut(duration: 0.25)) { messages.append(Message(text: "", typing: true)) }
        try await pause(0.6)
        withAnimation(.easeOut(duration: 0.25)) {
            messages.removeAll { $0.typing }
            messages.append(Message(text: text, note: note))
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
    /// 回复输入框：白底加一圈深一点的边，和灰底的对方气泡分开。
    static let field = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let fieldStroke = Color(light: 0xC7C7CC, dark: 0x48484A)
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
        /// 完成页「开始设置」。
        case setup
        /// 完成页「暂不配置，仅使用打字」；从设置里再看时完成页的「完成」。
        case later
    }

    /// 从设置里再看一次（tourReplay）：完成页只有「完成」，点了直接退出，不进接口配置。
    var replay = false
    var onExit: (Exit) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = TourModel()
    /// 完成页进场（各块的先后靠各自的 delay）。
    @State private var doneShown = false
    /// 完成页已经浮上来的总结卡片条数：一条一条往上浮，前一条还在动时下一条就开始（时间有重叠）。
    @State private var rowsShown = 0
    /// 对话区里气泡排起来的总高度：超出限高时顶上渐隐。
    @State private var messagesHeight: CGFloat = 0
    /// 对话区实际露出来的高度（矮屏放不下时比 limit 还小）。
    @State private var messagesShown: CGFloat = 0
    /// 矮屏（iPhone SE 等）：演示页收紧上边距、聊天只留最新一条，免得键盘把顶栏挤出屏幕。
    /// 按屏幕高度判断：页面本身超高时量出来的是内容高度，不准。
    private var compact: Bool { UIScreen.main.bounds.height < 700 }

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

    /// 首页一屏放下，不滚动（iPhone SE 也一样）：矮屏收紧边距、行高。
    private var welcome: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            VStack(alignment: .leading, spacing: compact ? 16 : 22) {
                HStack(alignment: .top, spacing: 14) {
                    GuideAppMark(size: 52, corner: 15)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("功能演示", "Feature Tour", "機能デモ"))
                            .font(.system(size: compact ? 26 : 30, weight: .bold)).foregroundStyle(GuideColor.text)
                        Text(L("21 步 · 约 4 分钟", "21 steps · About 4 min", "21 ステップ · 約 4 分"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(light: 0x4A3BD6, dark: 0xB4A9FF))
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(Color(light: 0xECEAFD, dark: 0x2E2766)))
                            .overlay(Capsule().strokeBorder(Color(light: 0xDCD6FB, dark: 0x463C8F), lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                    Button(L("跳过", "Skip", "スキップ")) { exit(.skip) }
                        .font(.system(size: 15)).foregroundStyle(GuideColor.secondary)
                }
                Text(L("配置 API 之前，先在模拟键盘上把各项 AI 功能操作一遍。结果均为预设内容，不调用 API，也不联网。",
                       "Before setting up an API, try each AI feature on a simulated keyboard. All results are preset; no API is called and nothing goes online.",
                       "API を設定する前に、模擬キーボードで各 AI 機能を一通り操作できます。結果はすべてあらかじめ用意したもので、API の呼び出しや通信は行いません。"))
                    .font(.system(size: 15)).lineSpacing(3).foregroundStyle(GuideColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GuideCard {
                    overviewRow(1, L("一键润色", "One-tap Polish", "ワンタップで整える"),
                                L("点「✨ 润色」，可随时撤销", "Tap ✨ Polish; undo anytime", "「✨ 整える」で整え、いつでも元に戻せる"), 2, .polish, compact)
                    GuideDivider()
                    overviewRow(2, L("识意 · 改写", "Ask: Rewrite", "識意：書き換え"),
                                L("写下要求，点润色键按要求改写", "Write an instruction; the polish key rewrites as asked", "指示を書き、整えるキーで書き換え"), 4, .rewrite, compact)
                    GuideDivider()
                    overviewRow(3, L("润色风格", "Polish styles", "整えるスタイル"),
                                L("添加风格，固定到 AI 栏一键直达", "Add a style and pin it to the AI bar", "スタイルを追加して AI バーに固定"), 5, .prompt, compact)
                    GuideDivider()
                    overviewRow(4, L("识意 · 问答", "Ask: Answer", "識意：回答"),
                                L("点「问答」直接回答，可联网、换风格", "Tap Ask to answer; search the web, change style", "「質問」ですぐ回答、検索・スタイル変更"), 7, .answer, compact)
                    GuideDivider()
                    overviewRow(5, L("分词 · 插入", "Pick & Insert", "単語・挿入"),
                                L("长按选词插入；按住替换键上滑插入", "Hold to pick words; slide Replace up to insert", "長押しで単語を挿入、置換キーを上で挿入"), 3, .words, compact)
                }
                Spacer(minLength: 8)
                VStack(spacing: compact ? 8 : 12) {
                    GuidePrimaryButton(L("开始演示", "Start Tour", "デモを始める")) { model.go(1) }
                    GuideSecondaryButton(L("跳过，前往设置", "Skip to Setup", "スキップして設定へ")) { exit(.skip) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, compact ? 24 : 58)
            .padding(.bottom, compact ? 16 : 30)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private func overviewRow(_ number: Int, _ title: String, _ detail: String, _ steps: Int, _ chapter: TourChapter, _ compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(chapter.text)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(chapter.fill))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GuideColor.text).lineLimit(1)
                Text(detail).font(.system(size: 13)).foregroundStyle(GuideColor.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            Text(L("\(steps) 步", steps == 1 ? "1 step" : "\(steps) steps", "\(steps) ステップ"))
                .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x9A96AA))
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: compact ? 56 : 62)
    }

    // MARK: FT22 完成（v4）

    /// 五章各一张小卡片：标题和下面一排小标签，和首页对应。
    private static var summary: [(TourChapter, String, [String])] { [
        (.polish, L("一键润色", "One-tap Polish", "ワンタップで整える"),
         [L("点 ✨ 润色", "Tap ✨", "✨ で整える"), L("撤销", "Undo", "元に戻す"), L("重做", "Redo", "やり直し")]),
        (.rewrite, L("识意 · 改写", "Ask: Rewrite", "識意：書き換え"),
         [L("按要求改写", "By instruction", "指示で書き換え"), L("替换", "Replace", "置換"), L("发送", "Send", "送信")]),
        (.prompt, L("润色风格", "Polish styles", "整えるスタイル"),
         [L("添加风格", "Add a style", "スタイル追加"), L("AI 优化", "AI help", "AI 改善"), L("固定到 AI 栏", "Pin to AI bar", "AI バーに固定")]),
        (.answer, L("识意 · 问答", "Ask: Answer", "識意：回答"),
         [L("一键问答", "One-tap Ask", "ワンタップ質問"), L("展开", "Expand", "展開"), L("联网", "Web", "検索"), L("换风格", "Style", "スタイル")]),
        (.words, L("分词 · 插入", "Pick & Insert", "単語・挿入"),
         [L("长按选词", "Hold to pick", "長押しで選ぶ"), L("上滑插入", "Slide to insert", "上スライドで挿入")]),
    ] }

    /// 完成页一屏放下，不滚动（iPhone SE 也一样）。进场：标题区从左飞入 → 五张卡片连成一道波往上浮 → 依次打勾 → 提示和按钮浮上来。
    private var finished: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            let icon: CGFloat = compact ? 52 : 72
            VStack(spacing: 0) {
                VStack(spacing: compact ? 8 : 12) {
                    GuideAppMark(size: icon, corner: icon * 21 / 72)
                        .background(Circle()
                            .fill(RadialGradient(colors: [Color(red: 123 / 255, green: 107 / 255, blue: 250 / 255).opacity(0.28), .clear],
                                                 center: .center, startRadius: 0, endRadius: icon / 2 + 14))
                            .frame(width: icon + 28, height: icon + 28))
                    Text(L("演示完成", "Tour complete", "デモ完了"))
                        .font(.system(size: compact ? 26 : 32, weight: .bold)).foregroundStyle(GuideColor.text)
                        .frame(height: compact ? 32 : 38)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        Text(L("21 步全部完成", "All 21 steps done", "21 ステップ完了")).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(light: 0x047857, dark: 0x6EE7B7))
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(Color(light: 0xD1FAE5, dark: 0x063B2C)))
                    .overlay(Capsule().strokeBorder(Color(light: 0xA7F3D0, dark: 0x0B5A43), lineWidth: 1))
                }
                .frame(maxWidth: .infinity)
                .offset(x: doneShown || reduceMotion ? 0 : -72)
                .opacity(doneShown ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.72), value: doneShown)
                Spacer(minLength: compact ? 12 : 20).frame(maxHeight: 40)
                VStack(spacing: compact ? 8 : 10) {
                    ForEach(Array(Self.summary.enumerated()), id: \.offset) { index, row in
                        // 整条（编号、标题、标签、圆圈）先看不见，再往上浮出来；圆圈在这一条快停稳时打勾。
                        let shown = index < rowsShown
                        summaryCard(index, row.0, row.1, row.2, compact, checked: shown)
                            .offset(y: shown || reduceMotion ? 0 : 28)
                            .opacity(shown ? 1 : 0)
                            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: Self.rowRise), value: shown)
                    }
                }
                Spacer(minLength: compact ? 10 : 16)
                VStack(spacing: compact ? 10 : 14) {
                    if replay {
                        GuidePrimaryButton(L("完成", "Done", "完了")) { exit(.later) }
                    } else {
                    HStack(spacing: 6) {
                        Image(systemName: "key").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(light: 0x5B4BE8, dark: 0xB4A9FF))
                        Text(L("设置好后，即可在任意 App 中使用这些功能", "Finish setup to use these in any app", "設定が終われば、どのアプリでも使えます"))
                            .font(.system(size: compact ? 13 : 14, weight: .semibold))
                            .foregroundStyle(Color(light: 0x3B2FC9, dark: 0xDCD6FF))
                            // 矮屏（SE）一行放不下时略缩小，不出省略号。
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, compact ? 12 : 16).frame(height: 38)
                    .background(Capsule().fill(Color(light: 0xECEAFD, dark: 0x25204F)))
                    GuidePrimaryButton(L("开始设置", "Start Setup", "設定をはじめる")) { exit(.setup) }
                    GuideSecondaryButton(L("暂不配置，仅使用打字", "Not Now, Typing Only", "今は設定せず入力のみ使う")) { exit(.later) }
                    }
                }
                .offset(y: doneShown || reduceMotion ? 0 : 12)
                .opacity(doneShown ? 1 : 0)
                .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.3).delay(reduceMotion ? 0.6 : Self.checksEnd), value: doneShown)
            }
            .padding(.horizontal, 20)
            .padding(.top, compact ? 26 : 64)
            .padding(.bottom, compact ? 16 : 30)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onAppear {
            FeatureTour.seen = true
            doneShown = false
            rowsShown = 0
            // 先按没进场的样子画一帧，再放动画：标题区和按钮靠各自的 delay，卡片一条一条放出来。
            DispatchQueue.main.async { doneShown = true }
            Task { @MainActor in
                if reduceMotion {
                    rowsShown = Self.summary.count
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.cardsStart * 1_000_000_000))
                for count in 1...Self.summary.count {
                    rowsShown = count
                    if count < Self.summary.count {
                        try? await Task.sleep(nanoseconds: UInt64(Self.rowGap * 1_000_000_000))
                    }
                }
                // 最后一个勾打完轻震一下。
                try? await Task.sleep(nanoseconds: UInt64((Self.checkDelay + Self.checkDraw) * 1_000_000_000))
                TourModel.haptic()
            }
        }
    }

    /// 标题区开始 0.25 秒后第一条起浮；每条从看不见往上浮 0.45 秒，下一条隔 0.18 秒就开始（前后重叠）；
    /// 每条起浮 0.3 秒后它的圆圈打勾（0.2 秒画完）。最后一个勾打完，提示和按钮浮上来。
    private static let cardsStart = 0.25
    private static let rowGap = 0.18
    private static let rowRise = 0.45
    private static let checkDelay = 0.3
    private static let checkDraw = 0.2
    private static var checksEnd: Double { cardsStart + rowGap * Double(summary.count - 1) + checkDelay + checkDraw }

    private func summaryCard(_ index: Int, _ chapter: TourChapter, _ title: String, _ tags: [String], _ compact: Bool, checked: Bool) -> some View {
        let checkAnimation: Animation? = reduceMotion ? nil : .easeOut(duration: Self.checkDraw).delay(Self.checkDelay)
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(chapter.text)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(chapter.fill))
            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(GuideColor.text).lineLimit(1)
                HStack(spacing: compact ? 3 : 4) {
                    ForEach(tags, id: \.self) { tag in
                        // 标签不截断：SE 上「问答」一行五个标签，收紧间距放下。
                        Text(tag)
                            .font(.system(size: 11.5)).foregroundStyle(GuideColor.secondary).lineLimit(1).fixedSize()
                            .padding(.horizontal, compact ? 4 : 7).frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(light: 0xF2F2F7, dark: 0x2C2C2E)))
                    }
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().strokeBorder(Color(light: 0xD1D1D6, dark: 0x48484A), lineWidth: 1.5)
                Circle().fill(chapter.text).opacity(checked ? 1 : 0)
                CheckShape()
                    .trim(from: 0, to: checked ? 1 : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .padding(7)
            }
            .frame(width: 24, height: 24)
            .animation(checkAnimation, value: checked)
        }
        .padding(.horizontal, 14)
        .frame(height: compact ? 54 : 66)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(light: 0xFFFFFF, dark: 0x1C1C1E))
            .shadow(color: Color(hex: 0x3C28A0).opacity(0.06), radius: 10, y: 6))
    }

    // MARK: FT1–FT21

    private var stepPage: some View {
        VStack(spacing: 0) {
            topBar
                .modifier(TourOutro(gone: model.outro >= 1))
            header
                .padding(.horizontal, side)
                .padding(.top, compact ? 4 : 14)
                .modifier(TourOutro(gone: model.outro >= 2))
            if model.appPage != nil {
                // FT8–FT10：键盘下沉，模拟的 App 提示词页升起。
                Spacer(minLength: 8)
                TourAppPage(model: model)
                    .transition(.move(edge: .bottom))
            } else {
                if compact {
                    // 矮屏放不下时聊天卡从上面收，留住最新一条和输入框，顶栏不被键盘挤出屏幕。
                    chat
                        .padding(.horizontal, side)
                        .padding(.top, 10)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottom)
                        .clipped()
                        .modifier(TourOutro(gone: model.outro >= 3))
                } else {
                    chat
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .modifier(TourOutro(gone: model.outro >= 3))
                    Spacer(minLength: 8)
                }
                TourKeyboard(model: model)
                    .offset(y: model.outro >= 4 ? UIScreen.main.bounds.height * 0.7 : 0)
                    .transition(.move(edge: .bottom))
            }
        }
        .overlayPreferenceValue(TourFramesKey.self) { anchors in
            GeometryReader { proxy in
                if let target = model.target, let anchor = anchors[target], !model.dragging {
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
            // 演示中途「跳过」直接到完成页（不播收场，完成页进场照播）。
            Button(L("跳过", "Skip", "スキップ")) { model.go(TourStep.count + 1) }
                .font(.system(size: 15)).foregroundStyle(GuideColor.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, side)
        .frame(height: compact ? 30 : 50)
        .padding(.top, compact ? 0 : 8)
    }

    /// 步骤页左右边距：矮屏 16（SE 规格），其余 20。
    private var side: CGFloat { compact ? 16 : 20 }

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
                if compact {
                    // 矮屏（SE 等）只留一行标题，说明不显示，给对话卡让地方；读屏照样读完整说明。
                    Text(info.title)
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(GuideColor.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(height: 26)
                        .accessibilityLabel(info.title + "。" + info.detail)
                } else {
                    Text(info.title)
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(GuideColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(info.detail)
                        .font(.system(size: 15)).lineSpacing(4).foregroundStyle(GuideColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        // 润色、改写、提示词三章和说另一种语言的同事聊，问答一章换回原来的联系人。
        let peer = model.step <= 11
        return VStack(alignment: .leading, spacing: 10) {
            // 矮屏结果卡展开时键盘很高，省掉联系人这一行。
            // 矮屏不要联系人这一行，只留气泡和输入框。
            if !compact {
                HStack(spacing: 8) {
                    Text(peer ? script.peerAvatar : script.avatar).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(LinearGradient(colors: peer ? [Color(hex: 0x7DD3FC), Color(hex: 0x2563EB)] : [Color(hex: 0xFDBA74), Color(hex: 0xF97316)], startPoint: .top, endPoint: .bottom)))
                        .id(peer)
                        .transition(.opacity)
                    Text(peer ? script.peer : script.contact).font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                    Spacer()
                    Text(L("演示内容 · 不会发送", "Demo content · Not sent", "デモ内容 · 送信されません"))
                        .font(.system(size: 10.5)).foregroundStyle(GuideColor.secondary)
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(Capsule().fill(TourColor.bubble))
                }
            }
            // 发出去的消息都留在对话里；对话区限高，放不下时最早的从顶上滚出去、顶上 24 渐隐，输入框始终露出来。
            // 矮屏不定死高度：整张卡放不下时由外面压对话区（minHeight 0），能露几条露几条。
            let limit: CGFloat = model.cardTall && !compact ? 64 : 132
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.messages.suffix(4)) { message in
                    bubble(message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in
                Color.clear.onAppear { messagesHeight = geo.size.height }
                    .onChange(of: geo.size.height) { messagesHeight = $0 }
            })
            // 矮屏整张卡放不下时先压对话区（minHeight 0），不把卡片顶边和联系人一行裁掉。
            // 上限取内容高和 limit 里小的那个：消息少时对话区跟着内容收，不在气泡上面空一截。
            .frame(minHeight: 0, maxHeight: min(messagesHeight, limit), alignment: .bottom)
            .background(GeometryReader { geo in
                Color.clear.onAppear { messagesShown = geo.size.height }
                    .onChange(of: geo.size.height) { messagesShown = $0 }
            })
            .clipped()
            .mask(VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: messagesHeight > messagesShown + 0.5 ? min(24, messagesShown) : 0)
                Color.black
            })
            Group {
                if model.field.isEmpty {
                    (Text(peer ? script.peerPlaceholder : script.placeholder).foregroundColor(GuideColor.secondary.opacity(0.7))
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
            // 最多露 3 行，再多像聊天 App 一样在框里往上滚，露出最新的字。
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: 62, alignment: .bottom)
            // 只问理想高度：一两行时框跟着字收，不撑满 62 在字上面空一截。
            .fixedSize(horizontal: false, vertical: true)
            .clipped()
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.field))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(TourColor.fieldStroke, lineWidth: 1))
        }
        .padding(compact ? 10 : 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GuideColor.card)
            .shadow(color: Color(hex: 0x3C28A0).opacity(0.07), radius: 14, y: 10))
    }

    /// 矮屏且回答卡展开：聊天区很小，对方气泡只留一行原文，不显示译文。
    private var tightChat: Bool { compact && model.expanded }

    @ViewBuilder
    private func bubble(_ message: TourModel.Message) -> some View {
        if message.mine {
            // 我方：靠右、实心紫底白字、右下小尾巴，最宽约八成。
            HStack {
                Spacer(minLength: 56)
                Text(message.text)
                    .font(.system(size: 14.5)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(UnevenRoundedRect(radius: 16, corner: 5, right: true).fill(TourColor.purple))
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.typing ? L("正在输入…", "Typing…", "入力中…") : message.text)
                        .font(.system(size: 14.5))
                        .foregroundStyle(message.typing ? GuideColor.secondary : GuideColor.text)
                        .lineLimit(tightChat ? 1 : 3)
                    // 像微信翻译：细线下面一行小「译」标签和译文。矮屏展开回答卡时放不下，只留原文一行。
                    if let note = message.note, !message.typing, !tightChat {
                        Rectangle().fill(TourColor.fieldStroke).frame(height: 1)
                        HStack(spacing: 6) {
                            Text(L("译", "Translated", "翻訳"))
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color(hex: 0x9A96AA))
                                .padding(.horizontal, 4).frame(height: 16)
                                .background(RoundedRectangle(cornerRadius: 4).fill(TourColor.field))
                            Text(note).font(.system(size: 13)).foregroundStyle(GuideColor.secondary).lineLimit(2)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(UnevenRoundedRect(radius: 16, corner: 5, right: false).fill(TourColor.bubble))
                // 对方：靠左、浅灰底、左下小尾巴，最宽约八成。
                Spacer(minLength: 56)
            }
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

/// 收场：往下滑 24 并淡出。
private struct TourOutro: ViewModifier {
    var gone: Bool
    func body(content: Content) -> some View {
        content.offset(y: gone ? 24 : 0).opacity(gone ? 0 : 1)
    }
}

/// 完成页的勾：一笔画出（trim 动画）。
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

// MARK: - 按下态

/// 模拟键盘里润色键（false）、问答键（true）的位置，风格下拉和它左对齐。
private struct TourKeyFramesKey: PreferenceKey {
    static var defaultValue: [Bool: CGRect] = [:]
    static func reduce(value: inout [Bool: CGRect], nextValue: () -> [Bool: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 风格下拉里的一条：问答风格那几条能点（FT18 选「列要点」），润色风格只看不点。
private struct TourMenuRow: ViewModifier {
    let index: Int
    let answer: Bool
    @ObservedObject var model: TourModel

    func body(content: Content) -> some View {
        content.tourPress(answer ? .answerPill(index) : .pill(index), model: model)
    }
}

/// 润色风格下拉里每条右边的图钉：FT11 点「英文」那颗固定到 AI 栏。
private struct TourMenuPin: ViewModifier {
    let index: Int
    let answer: Bool
    @ObservedObject var model: TourModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if answer {
            content
        } else {
            content.tourPress(.pin(index), model: model)
        }
    }
}

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
/// FT19 示范长按结果卡、在虚线框的词上横划，FT21 示范按住替换键往上推。减弱动态效果时静止。
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
            } else if step == TourStep.count && target == .replace {
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
        // 翻转是绕指尖镜像（CoachHandShape.hand 的 anchor），指尖在框里的位置不变，所以框心不随翻转改。
        let center = CGPoint(x: tip.x + dx, y: tip.y + size.height / 2 - fingertip.y)
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

    /// FT19 一轮 2 秒：按下 → 指尖一圈天蓝进度环 0.45 秒画满 → 环往外撑大淡掉 → 手淡出。
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

    /// FT19 横划示范一轮 3 秒：从第一块划到最后一块（1.2 秒），回到第一块停着等。
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

/// App 里画的键盘：提示词一排、AI 栏、回答卡和识意框、九宫格按键；FT19 长按后按键区换成分词面板。只有小手指着的那颗能点。
private struct TourKeyboard: View {
    @ObservedObject var model: TourModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let side: CGFloat = 6
    /// 矮屏（SE 等）：按键行高 42 → 36，分词面板跟着矮，给对话卡让地方。
    private var compact: Bool { UIScreen.main.bounds.height < 700 }
    private var keyHeight: CGFloat { compact ? 36 : 42 }

    var body: some View {
        VStack(spacing: 8) {
            if model.expanded {
                answerBlock
                    .padding(.horizontal, side + 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            aiBar.padding(.horizontal, side + 2).zIndex(1)
            if model.panel {
                wordPanel.padding(.horizontal, side + 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                keys.padding(.horizontal, side)
                    // 风格下拉从被点的那颗键下面往下弹，盖在按键上（同真键盘 KB1）。
                    .overlay(alignment: .topLeading) { dropdown }
                    .zIndex(2)
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
        .coordinateSpace(name: "tourKeyboard")
        .onPreferenceChange(TourKeyFramesKey.self) { frames in
            if frames != keyFrames { keyFrames = frames }
        }
        .background(
            TourColor.keyboard
                .clipShape(TopRounded(radius: compact ? 22 : 26))
                .contentShape(Rectangle())
                .onTapGesture { model.wrong() })
        .animation(.easeOut(duration: 0.25), value: model.expanded)
        .animation(.easeOut(duration: 0.25), value: model.promptsOpen)
    }

    // MARK: 风格下拉

    private var promptNames: [String] {
        var names = [L("润色", "Polish", "整える"), L("正式", "Formal", "丁寧"), L("口语", "Casual", "カジュアル"),
                     L("简短", "Concise", "簡潔に"), L("结构", "Bullets", "箇条書き")]
        if let custom = model.customPrompt { names.append(custom) }
        return names
    }

    /// 润色键 / 问答键在 AI 栏里的位置（键盘自己的坐标），下拉的左边和它对齐。
    @State private var keyFrames: [Bool: CGRect] = [:]

    @ViewBuilder
    private var dropdown: some View {
        if model.promptsOpen || model.answerStylesOpen {
            let answer = model.answerStylesOpen
            let x = min(max(4, keyFrames[answer]?.minX ?? 60), UIScreen.main.bounds.width - 220)
            styleMenu(answer: answer)
                .offset(x: x, y: 4)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    /// 小屏（SE）每行 28，6 条风格加「＋」整个下拉不超出键盘底边。
    private var menuRow: CGFloat { compact ? 28 : 32 }

    /// 宽 216、圆角 12：小标题，每条右边一颗图钉（演示里只有「英文」那颗能点），当前那条打勾；润色那一个最底下「＋ 添加润色风格」。
    private func styleMenu(answer: Bool) -> some View {
        let names = answer ? Self.answerStyles : promptNames
        let selected = answer ? model.answerStyle : model.selectedPrompt
        return VStack(alignment: .leading, spacing: 0) {
            Text((answer ? L("问答风格", "Answer style", "回答スタイル") : L("润色风格", "Polish style", "整えるスタイル"))
                 + L(" · 点图钉固定到 AI 栏", " · Pin to the AI bar", " · ピンで AI バーに固定"))
                .font(.system(size: 11)).foregroundStyle(GuideColor.secondary).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 10).frame(height: compact ? 20 : 24)
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                let on = index == selected
                let pinned = !answer && index == 5 && model.pinnedCustom
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 14.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? TourColor.purple : GuideColor.text).lineLimit(1)
                    if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(TourColor.purple) }
                    Spacer(minLength: 4)
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(pinned ? TourColor.purple : GuideColor.secondary.opacity(0.7))
                        .frame(width: 30, height: menuRow)
                        .modifier(TourMenuPin(index: index, answer: answer, model: model))
                }
                .padding(.leading, 10)
                .frame(height: menuRow)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? TourColor.pillOn : .clear))
                .transition(.opacity)
                .modifier(TourMenuRow(index: index, answer: answer, model: model))
            }
            if !answer {
                Label(L("添加润色风格", "Add Polish Style", "整えるスタイルを追加"), systemImage: "plus")
                    .font(.system(size: 14.5)).foregroundStyle(TourColor.purple).lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: menuRow, alignment: .leading)
                    .tourPress(.addStyle, model: model)
            }
        }
        .padding(5)
        .frame(width: 216)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.cardFill)
            .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.22), radius: 12, y: 8))
    }

    // MARK: AI 栏

    /// 一排（AK4、AK5）：▭ ｜ 润色键、问答键、竖线、固定的「✨ 英文」｜撤销重做。窄屏放不下时中间那段跟着小手要点的键滚过去（演示里不让手指拖）。
    private var aiBar: some View {
        // 同真键盘方案 A（v309）：间距 5、▭ 宽 36、⌄ 区 24、撤销重做小胶囊 64。
        // 滑动区自带左右 5 的内边（给亮边留地方），所以它和两边之间不再加间距，看上去也是 5。
        HStack(spacing: 0) {
            Image(systemName: "rectangle.tophalf.inset.filled")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(model.expanded ? TourColor.purple : GuideColor.text)
                .frame(width: 36, height: 34)
                .background(Capsule().fill(model.expanded ? Color(light: 0xEDEBFD, dark: 0x2E2766) : TourColor.key))
                .overlay(Capsule().strokeBorder(TourColor.ring, lineWidth: model.expanded ? 1.5 : 0))
                .tourPress(.drawer, model: model)
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        mainKey(answer: false).id(TourTarget.sparkle)
                        mainKey(answer: true).id(TourTarget.askKey)
                        // FT11 点图钉后下拉先收起，「✨ 英文」再弹进来。
                        if model.pinnedCustom && !model.promptsOpen {
                            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1, height: 20)
                            pinnedKey.id(TourTarget.pinned)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 44)
                }
                .scrollDisabled(true)
                .onChange(of: model.target) { target in
                    guard let target, [TourTarget.sparkle, .askKey, .pinned, .chevron, .answerStyle].contains(target) else { return }
                    let id: TourTarget = target == .chevron ? .sparkle : target == .answerStyle ? .askKey : target
                    withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo(id) }
                }
                // 换一步先回到最左（FT11 滚到「✨ 英文」后，FT12 润色键要完整露出来）。
                .onChange(of: model.step) { _ in reader.scrollTo(TourTarget.sparkle, anchor: .leading) }
            }
            .frame(height: 44)
            HStack(spacing: 0) {
                Image(systemName: "arrow.uturn.backward")
                    .rotationEffect(.degrees(Double(model.undoTurns) * -180))
                    .foregroundStyle(model.undoOn ? GuideColor.text : GuideColor.secondary.opacity(0.6))
                    .padding(.leading, 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .tourPress(.undo, model: model)
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1, height: 16)
                Image(systemName: "arrow.uturn.forward")
                    .foregroundStyle(model.redoOn ? GuideColor.text : GuideColor.secondary.opacity(0.6))
                    .padding(.trailing, 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .tourPress(.redo, model: model)
            }
            .font(.system(size: 16, weight: .medium))
            .frame(width: 64, height: 34)
            .background(Capsule().fill(TourColor.key))
        }
        .animation(.easeOut(duration: 0.2), value: model.pinnedCustom)
    }

    /// 润色键「✨ 润色 ⌄」、问答键「[问答图标] 问答 ⌄」：竖线左边点了执行，右边 ⌄ 弹风格下拉。结果来自哪颗，那颗带亮边。
    private func mainKey(answer: Bool) -> some View {
        let active = !model.pinRunning && model.activeStyle == (answer ? .answer : .rewrite)
        let open = answer ? model.answerStylesOpen : model.promptsOpen
        let title = answer ? L("问答", "Ask", "質問") : promptNames[min(model.selectedPrompt, promptNames.count - 1)]
        return HStack(spacing: 0) {
            HStack(spacing: 3) {
                if answer {
                    AskIcon(size: 17)
                } else {
                    PolishStars(size: 17, running: model.sparkRunning, glowing: !reduceMotion, doneAt: model.sparkDone, tint: AIVisuals.gold)
                        .frame(width: 17, height: 17)
                }
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .padding(.leading, 9).padding(.trailing, 5)
            .frame(maxHeight: .infinity)
            .tourPress(answer ? .askKey : .sparkle, model: model)
            Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
            Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                .frame(width: 24).frame(maxHeight: .infinity)
                .tourPress(answer ? .answerStyle : .chevron, model: model)
        }
        .foregroundStyle(.white)
        .frame(height: 34)
        .background(NebulaFill(palette: answer ? .answer : .rewrite).clipShape(Capsule()))
        .overlay {
            if !answer && model.sparkRunning {
                Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5).blur(radius: 1).transition(.opacity)
            }
        }
        .overlay {
            Capsule().strokeBorder(answer ? Color(hex: 0x4C8FF8) : Color(hex: 0xA78BFA), lineWidth: 2)
                .padding(-4)
                .opacity(active ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.25), value: active)
        .fixedSize()
        .background(GeometryReader { geo in
            Color.clear.preference(key: TourKeyFramesKey.self, value: [answer: geo.frame(in: .named("tourKeyboard"))])
        })
    }

    /// 固定在 AI 栏的「✨ 英文」：浅紫底主色字，没有 ⌄；点了按这个风格出字。
    private var pinnedKey: some View {
        HStack(spacing: 4) {
            PolishStars(size: 15, running: model.pinRunning, glowing: !reduceMotion, doneAt: nil, tint: TourColor.purple)
                .frame(width: 15, height: 15)
            Text(model.customPrompt ?? model.script.promptName).font(.system(size: 14.5, weight: .semibold)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(TourColor.purple)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(TourColor.pillOn))
        .overlay {
            if model.pinRunning {
                Capsule().strokeBorder(TourColor.ring, lineWidth: 1.5).transition(.opacity)
            }
        }
        .tourPress(.pinned, model: model)
    }

    static var answerStyles: [String] {
        [L("直击要害", "To the point", "要点だけ"), L("详细", "Detailed", "詳しく"), L("列要点", "Key points", "要点を列挙"), L("通俗", "Plain words", "やさしく")]
    }

    // MARK: 回答卡 + 识意框

    private var answerBlock: some View {
        HStack(spacing: 6) {
            replaceKey
            VStack(spacing: 0) {
                cardTop
                    .frame(height: model.cardTall ? 120 : 82)
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
        .frame(height: model.cardTall ? 161 : 123)
        .animation(.easeOut(duration: 0.25), value: model.cardTall)
    }

    /// 替换键：点一下替换；FT21 按住往上滑过 16，「插入」转到正中、换插入色加白边，松手插入（同真键盘）。
    private var replaceKey: some View {
        let sliding = model.dragTarget == .replace && model.target == .replace
        let inserting = sliding && model.dragPick
        let pressed = model.pressed == .replace || model.dragging && sliding
        let demo = model.demoDown && model.target == .replace && model.pressed == nil
        return VStack(spacing: 4) {
            if inserting {
                Text(L("替换", "Replace", "置き換え")).font(.system(size: 10, weight: .semibold)).opacity(0.45).lineLimit(1).minimumScaleFactor(0.6)
                Rectangle().fill(Color.white.opacity(0.5)).frame(width: 22, height: 1)
                Image(systemName: "text.insert").font(.system(size: 15, weight: .bold))
                Text(L("插入", "Insert", "挿入")).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .bold))
                Text(L("替换", "Replace", "置き換え")).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                Rectangle().fill(Color.white.opacity(0.5)).frame(width: 22, height: 1)
                Text(L("插入", "Insert", "挿入")).font(.system(size: 10, weight: .semibold)).opacity(0.45).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: inserting ? [Color(hex: 0x0891B2), Color(hex: 0x2563EB)] : [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)],
                                 startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white, lineWidth: inserting ? 2 : 0))
        .animation(.easeOut(duration: 0.15), value: inserting)
        .opacity(model.card == nil || model.generating ? 0.45 : 1)
        // FT21：键上方一道紫色虚线和向上箭头，提示往上推。
        .overlay(alignment: .top) {
            if sliding {
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .heavy))
                    Rectangle().fill(.clear).frame(width: 1.5, height: 22)
                        .overlay(Path { p in p.move(to: CGPoint(x: 0.75, y: 0)); p.addLine(to: CGPoint(x: 0.75, y: 22)) }
                            .stroke(TourColor.ring, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                }
                .foregroundStyle(TourColor.ring)
                .offset(y: -30)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .scaleEffect(pressed ? 0.96 : demo ? 0.98 : 1)
        .brightness(pressed && !inserting ? -0.08 : demo ? -0.04 : 0)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if sliding {
                    model.drag(value.translation.height, ended: false)
                } else {
                    model.pressBegan(.replace)
                }
            }
            .onEnded { value in
                if sliding {
                    model.drag(nil, ended: true)
                } else {
                    let moved = abs(value.translation.width) + abs(value.translation.height)
                    model.pressEnded(.replace, inside: moved < 30)
                }
            })
        .tourTarget(.replace)
    }

    private var cardTop: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
            // 正文上面一行标题（AK2）：改写「✨ AI 改写 · 润色」，问答「[问答图标] AI 回答 · 直击要害」+ 未联网 / 已联网。
            if model.cardMode != nil, !model.generating, model.card != nil || model.searching {
                cardHeader.transition(.opacity)
            }
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
                    Text(card).foregroundStyle(GuideColor.text).lineLimit(model.cardTall ? 4 : 2)
                } else {
                    Text(L("结果会出现在这里", "The result shows here", "結果はここに表示されます")).foregroundStyle(GuideColor.secondary.opacity(0.7))
                }
            }
            .font(.system(size: 14.5))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if model.card != nil, !model.generating {
                VStack {
                    Image(systemName: "doc.on.doc")
                    Spacer()
                    // FT16 右下展开钮：2 行 → 4 行。
                    Image(systemName: model.cardTall ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(TourColor.ring.opacity(model.target == .expand ? 0.15 : 0)))
                        .tourPress(.expand, model: model)
                }
                .font(.system(size: 12))
                .foregroundStyle(GuideColor.secondary)
            }
        }
        .padding(8)
    }

    private var cardHeader: some View {
        let answer = model.cardMode == .answer
        let color = answer ? Color(light: 0x2F7BF6, dark: 0x5EA0FF) : TourColor.purple
        return HStack(spacing: 4) {
            if answer {
                AskIcon(size: 15)
            } else {
                PolishStars(size: 15, running: false, glowing: false, doneAt: nil, tint: color).frame(width: 15, height: 15)
            }
            Text(answer ? L("AI 回答", "AI answer", "AI の回答") + " · " + Self.answerStyles[model.cardAnswerStyle]
                 : L("AI 改写", "AI rewrite", "AI 書き換え") + " · " + promptNames[min(model.selectedPrompt, promptNames.count - 1)])
                .font(.system(size: 13, weight: .bold)).lineLimit(1)
            if answer { webTag.padding(.leading, 2) }
        }
        .foregroundStyle(color)
        .frame(height: 18)
        .animation(.easeOut(duration: 0.2), value: model.searched)
    }

    /// 问答标题后面的联网标签：联网前「未联网」浅灰，FT17 联网后换成「已联网」浅蓝（取代原来那行「已联网 · Kimi」）。
    private var webTag: some View {
        let on = model.searched
        return HStack(spacing: 3) {
            Image(systemName: "globe").font(.system(size: 11))
            Text(on ? L("已联网", "Web", "ウェブ検索済み") : L("未联网", "No web", "ウェブなし")).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(on ? Color(light: 0x2F7BF6, dark: 0x5EA0FF) : Color(light: 0x8A8A8E, dark: 0x98989D))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(on ? Color(light: 0xE3EEFE, dark: 0x1D2A44) : Color(light: 0xEEEEF1, dark: 0x3A3A3E)))
        .fixedSize()
    }

    /// 识意框（激活：紫色光标）；FT15–FT17 右边「使用联网查询」。联网后靠标题上的「已联网」标签，这里不再写。
    private var askRow: some View { askField }

    private var askField: some View {
        HStack(spacing: 8) {
            (Text(model.ask) + Text("▏").foregroundColor(TourColor.caret))
                .font(.system(size: 15))
                .foregroundStyle(GuideColor.text)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.canSearch, !model.searched {
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
        let gap: CGFloat = 6, height = keyHeight
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
            // 识意框里按回车：照上次点的那颗键执行。
            Text(L("执行", "Go", "実行")).font(.system(size: 16, weight: .bold))
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

    // MARK: 分词面板（FT19）

    private var wordPanel: some View {
        let script = model.script
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(model.picked.isEmpty
                     ? (compact ? L("点选，或横着划选", "Tap or swipe across", "タップか横になぞる")
                        : L("点选，或按住横着划选", "Tap, or hold and swipe across", "タップ、または長押しして横になぞる"))
                     : L("已选 \(model.picked.count) 个", "\(model.picked.count) selected", "\(model.picked.count) 個選択"))
                    .font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text(L("插入/复制后关闭", "Close after insert/copy", "挿入・コピー後に閉じる"))
                    .font(.system(size: 12)).foregroundStyle(GuideColor.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Capsule().fill(Color(hex: 0x5B4BE8))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: .trailing) { Circle().fill(.white).frame(width: 16, height: 16).padding(.trailing, 2) }
            }
            // 词多（问答的回答切出来二三十块）时面板放不下：词这一块在面板里上下滚，插入一排始终在底部，不顶出面板。
            // 自己滚，不用 ScrollView：选词手势按下就要接手，放进 ScrollView 会把它的滚动吃掉。
            // 一开始竖着拖的算滚动、不选词；横着划连续选；没怎么动就松手算点选。
            GeometryReader { box in
                FlowLayout(spacing: 6) {
                    ForEach(Array(script.words.enumerated()), id: \.offset) { index, word in
                        wordChip(index, word, hint: script.hints.contains(index) && model.picked.isEmpty, script: script)
                    }
                }
                .coordinateSpace(name: "tourWords")
                .onPreferenceChange(TourWordFramesKey.self) { wordFrames = $0 }
                .background(GeometryReader { Color.clear.preference(key: TourWordsHeightKey.self, value: $0.size.height) })
                .onPreferenceChange(TourWordsHeightKey.self) { wordsHeight = $0 }
                .offset(y: wordsOffset)
                .frame(width: box.size.width, height: box.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = abs(value.translation.width), dy = abs(value.translation.height)
                        if dragSelect == nil, !dragScrolling, dy > 8, dy > dx {
                            dragScrolling = true
                            scrollBase = wordsOffset
                        }
                        if dragScrolling {
                            let lowest = min(0, box.size.height - wordsHeight)
                            wordsOffset = min(0, max(lowest, scrollBase + value.translation.height))
                            return
                        }
                        if dragSelect == nil, dx <= 6 { return }
                        pick(at: content(value.startLocation))
                        pick(at: content(value.location))
                    }
                    .onEnded { value in
                        if !dragScrolling, dragSelect == nil, hypot(value.translation.width, value.translation.height) < 8 {
                            pick(at: content(value.location))
                        }
                        dragSelect = nil
                        dragScrolling = false
                    })
            }
            .frame(maxHeight: .infinity)
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
        .frame(height: 4 * keyHeight + 3 * 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(light: 0xF1F0FA, dark: 0x232325)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TourColor.ring.opacity(0.4), lineWidth: 1))
    }

    @State private var wordFrames: [Int: CGRect] = [:]
    /// 这一下手势是在选还是在取消。
    @State private var dragSelect: Bool?
    /// 这一下是竖着拖、在滚词，不选词。
    @State private var dragScrolling = false
    /// 词往上滚了多少（≤ 0）、这一下开始滚时的位置、词整块的高度。
    @State private var wordsOffset: CGFloat = 0
    @State private var scrollBase: CGFloat = 0
    @State private var wordsHeight: CGFloat = 0

    /// 手指在框里的位置换成词那一块里的位置（扣掉已经滚上去的）。
    private func content(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y - wordsOffset)
    }

    /// 手指下的那一块：第一块决定这一下是选还是取消。
    private func pick(at location: CGPoint) {
        guard let hit = wordFrames.first(where: { $0.value.insetBy(dx: -3, dy: -3).contains(location) })?.key else { return }
        let select = dragSelect ?? !model.picked.contains(hit)
        dragSelect = select
        model.toggleWord(hit, on: select)
    }

    private func wordChip(_ index: Int, _ word: String, hint: Bool, script: TourScript) -> some View {
        let picked = model.picked.contains(index)
        return Text(word)
            .font(.system(size: 14))
            .foregroundStyle(picked ? Color.white : GuideColor.text)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(picked ? TourColor.purple : TourColor.key))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(TourColor.ring, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .opacity(hint ? 1 : 0))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: TourWordFramesKey.self, value: [index: proxy.frame(in: .named("tourWords"))])
            })
            .modifier(TourWordAnchor(index: index, hints: script.hints))
    }
}

private struct TourWordsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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

// MARK: - 模拟的 App 提示词页（FT8–FT10）

/// 键盘上的「＋」本来就是去 App 管理提示词，演示里「假装跳转」：引导里画的一块模拟页面，不真的打开 App、不写用户的提示词。
private struct TourAppPage: View {
    @ObservedObject var model: TourModel

    private static let rows: [(String, String, Int)] = [
        (L("润色", "Polish", "整える"), L("不加额外要求，按原文的语气改顺、改通", "No extra instructions; smooths your text in its own tone", "追加の指示なし。元の口調のまま読みやすく"), 12),
        (L("正式", "Formal", "丁寧"), L("书面、得体、礼貌，适合工作沟通和对外发送", "Written, proper and polite; for work and outside contacts", "書き言葉で丁寧に。仕事や社外向け"), 5),
        (L("口语", "Casual", "カジュアル"), L("像本人平时说话一样自然随意", "Natural and relaxed, like you normally talk", "ふだんの話し言葉のように自然に"), 3),
        (L("简短", "Concise", "簡潔に"), L("只留核心意思，能一句说清就一句", "Keeps only the core point, in one sentence if possible", "要点だけ。一文で済むなら一文で"), 2),
        (L("结构", "Bullets", "箇条書き"), L("提炼关键信息，整理成编号要点", "Pulls out key information as numbered points", "要点を抜き出して番号付きで整理"), 1),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(TourColor.purple).frame(width: 6, height: 6)
                Text(model.appPage == .edit
                     ? L("飞地输入法 App · 添加润色风格（演示）", "Enclave app · Add Polish Style (demo)", "Enclave アプリ · 整えるスタイルを追加（デモ）")
                     : L("飞地输入法 App · 润色风格（演示）", "Enclave app · Polish styles (demo)", "Enclave アプリ · 整えるスタイル（デモ）"))
                    .font(.system(size: 11.5)).foregroundStyle(GuideColor.secondary)
            }
            .frame(height: 30)
            ZStack {
                if model.appPage == .edit {
                    editPage.transition(.move(edge: .trailing))
                } else {
                    listPage.transition(.move(edge: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        // 矮屏少 80：上面还有顶栏和说明，560 会把顶栏挤出屏幕。
        .frame(height: UIScreen.main.bounds.height < 700 ? 480 : 560)
        .background(TopRounded(radius: 22).fill(GuideColor.page).ignoresSafeArea(edges: .bottom))
        .animation(.easeOut(duration: 0.3), value: model.appPage)
    }

    // MARK: 提示词列表（FT8）

    private var listPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("5 条 · 默认「润色」", "5 styles · Default: Polish", "5 件 · 既定「整える」"))
                .font(.system(size: 12)).foregroundStyle(GuideColor.secondary)
            Text(L("润色风格", "Polish styles", "整えるスタイル")).font(.system(size: 26, weight: .bold)).foregroundStyle(GuideColor.text)
            HStack(spacing: 0) {
                Text(L("润色", "Polish", "整える"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(GuideColor.text)
                    .frame(maxWidth: .infinity).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(GuideColor.card))
                Text(L("问答", "Answer", "回答"))
                    .font(.system(size: 13)).foregroundStyle(GuideColor.secondary)
                    .frame(maxWidth: .infinity).frame(height: 28)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.secondary.opacity(0.12)))
            .onTapGesture { model.wrong() }
            VStack(spacing: 0) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.leading, 14) }
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.0).font(.system(size: 15.5)).foregroundStyle(GuideColor.text)
                                if index == 0 {
                                    Text(L("默认", "Default", "既定")).font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(GuideColor.chipText)
                                        .padding(.horizontal, 5).frame(height: 17)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(GuideColor.chipFill))
                                }
                            }
                            Text(row.1).font(.system(size: 12)).foregroundStyle(GuideColor.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(L("\(row.2) 次", "\(row.2)×", "\(row.2) 回")).font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14).frame(height: 50)
                    .contentShape(Rectangle())
                    .onTapGesture { model.wrong() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.card))
            Text(L("顺序就是键盘「润色 ▾」里的顺序。次数是本周的。", "The order matches Polish ▾ on the keyboard. Counts are for this week.", "並び順はキーボードの「整える ▾」と同じです。回数は今週分です。"))
                .font(.system(size: 11.5)).foregroundStyle(GuideColor.secondary)
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text(L("添加润色风格", "Add Polish Style", "整えるスタイルを追加")).font(.system(size: 15.5))
            }
            .foregroundStyle(TourColor.purple)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.card))
            .tourPress(.addPrompt, model: model)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    // MARK: 添加提示词（FT9、FT10）

    private var editPage: some View {
        let script = model.script
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        Text(L("润色风格", "Polish styles", "整えるスタイル")).font(.system(size: 15.5))
                    }
                    .foregroundStyle(TourColor.purple)
                    .onTapGesture { model.wrong() }
                    Spacer()
                    Text(L("添加润色风格", "Add Polish Style", "整えるスタイルを追加")).font(.system(size: 16, weight: .semibold)).foregroundStyle(GuideColor.text)
                    Spacer()
                    Text(L("完成", "Done", "完了")).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(TourColor.purple)
                        .padding(.horizontal, 6).frame(height: 30)
                        .tourPress(.done, model: model)
                }
                .frame(height: 40)
                label(L("名称", "Name", "名前"))
                HStack {
                    TextField("", text: $model.sheetName).font(.system(size: 16))
                    if !model.sheetName.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkle").font(.system(size: 9, weight: .bold)).foregroundStyle(AIVisuals.gold)
                            Text(model.sheetName).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(NebulaFill(palette: .join).clipShape(Capsule()))
                    }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.card))
                Text(L("显示在键盘 ✨ 旁边，四个字以内最好。", "Shows next to ✨ on the keyboard. Keep it short.", "キーボードの ✨ の横に表示されます。短めがおすすめです。"))
                    .font(.system(size: 11.5)).foregroundStyle(GuideColor.secondary)
                label(L("提示词内容", "Prompt", "プロンプトの内容"))
                TextField("", text: $model.sheetContent, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(2...4)
                    .padding(12)
                    .frame(minHeight: 64, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.card))
                HStack(spacing: 4) {
                    if model.improving {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkle").font(.system(size: 12, weight: .bold))
                    }
                    Text(L("AI 优化提示词", "Improve with AI", "AI でプロンプトを改善")).font(.system(size: 14.5, weight: .semibold))
                }
                .foregroundStyle(TourColor.purple)
                .frame(height: 32)
                .tourPress(.improve, model: model)
                if let improved = model.improved {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkle").font(.system(size: 11, weight: .bold))
                            Text(L("AI 优化结果", "AI suggestion", "AI の提案")).font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(TourColor.purple)
                        Text(improved).font(.system(size: 14)).foregroundStyle(GuideColor.text)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourColor.pillOn))
                        HStack(spacing: 14) {
                            Text(L("用这一版", "Use This", "これを使う")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 32)
                                .background(Capsule().fill(TourColor.purple))
                                .tourPress(.useVersion, model: model)
                            Text(L("不用了", "No Thanks", "使わない")).font(.system(size: 14)).foregroundStyle(GuideColor.secondary)
                                .onTapGesture { model.wrong() }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GuideColor.card))
                    .transition(.opacity)
                } else {
                    label("＋ " + L("建议", "Suggestions", "候補"))
                    FlowLayout(spacing: 6) {
                        ForEach(Array(script.tags.enumerated()), id: \.offset) { index, tag in
                            tagChip(index, tag)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(GuideColor.secondary).padding(.top, 4)
    }

    private func tagChip(_ index: Int, _ tag: String) -> some View {
        let picked = model.pickedTags.contains(index)
        return HStack(spacing: 3) {
            Image(systemName: picked ? "checkmark" : "plus").font(.system(size: 10, weight: .bold))
            Text(tag).font(.system(size: 13)).lineLimit(1)
        }
        .foregroundStyle(TourColor.purple)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(picked ? TourColor.pillOn : GuideColor.card))
        .overlay(Capsule().strokeBorder(TourColor.ring.opacity(picked ? 1 : 0.4), lineWidth: 1))
        .fixedSize()
        .tourPress(.tag(index), model: model)
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
