import SwiftUI

/// 使用指引（原「场景实验室」「试一试」）：10 个真实场景，每个一页，带预填文字和两步提示，用来练键盘的打字、润色和按要求改。
/// 每个场景标出用法（LM1–LM8）：快速（面板收起，点一下直接改好）、替换 / 插入（展开看结果再用）、打字。
struct LabScene: Identifiable {
    enum Mode {
        case quick, replace, insert, typing

        var title: String {
            switch self {
            case .quick: return L("快速", "Quick", "クイック")
            case .replace: return L("替换", "Replace", "置き換え")
            case .insert: return L("插入", "Insert", "挿入")
            case .typing: return L("打字", "Typing", "入力")
            }
        }

        var icon: String {
            switch self {
            case .quick: return "bolt.fill"
            case .replace: return "arrow.left.arrow.right"
            case .insert: return "text.insert"
            case .typing: return "keyboard"
            }
        }

        /// 字色和浅底；深色模式字用浅一档、底用字色 20%。
        var colors: (text: Color, fill: Color) {
            let (light, dark, fill): (UInt32, UInt32, UInt32) = {
                switch self {
                case .quick: return (0xC2410C, 0xFDBA74, 0xFFEDD5)
                case .replace: return (0x5B4BE8, 0xB4A9FF, 0xECEAFD)
                case .insert: return (0x0E7490, 0x67E8F9, 0xDDF3F7)
                case .typing: return (0x636366, 0xAEAEB2, 0xEFEFF4)
                }
            }()
            return (Color(light: light, dark: dark), Color(light: fill, dark: dark, darkOpacity: 0.2))
        }

        /// 详情页「试试这样做」下面的说明条。
        var explanation: String? {
            switch self {
            case .quick: return L("面板收起，点一下直接改好输入框里的话，不满意点 ↶ 撤销", "Panel stays closed. One tap rewrites the text in place. Tap ↶ to undo.", "パネルは閉じたまま。ワンタップで入力欄を書き換え、↶ で元に戻せます")
            case .replace: return L("先展开看结果，满意再点「替换」换掉原文", "Open the result first, then tap Replace if you like it.", "結果を開いて確認し、よければ「置き換え」")
            case .insert: return L("先展开看结果，点「插入」加在光标处，原文留着", "Open the result first, then tap Insert to add it at the cursor. Your text stays.", "結果を開いて確認し、「挿入」でカーソル位置に追加。元の文は残ります")
            case .typing: return nil
            }
        }
    }

    enum Category: String, CaseIterable {
        case work, client, social, life, language

        var name: String {
            switch self {
            case .work: return L("工作", "Work", "仕事")
            case .client: return L("客户", "Customers", "お客様")
            case .social: return L("社交", "Social", "交流")
            case .life: return L("生活", "Life", "暮らし")
            case .language: return L("语言", "Language", "言語")
            }
        }

        /// 分类色：字色和浅底。
        var colors: (text: Color, fill: Color) {
            switch self {
            case .work: return (Color(hex: 0x5B4BE8), Color(hex: 0xECEAFD))
            case .client: return (Color(hex: 0x0E7490), Color(hex: 0xDDF3F7))
            case .social: return (Color(hex: 0xDB2777), Color(hex: 0xFCE7F3))
            case .life: return (Color(hex: 0xB45309), Color(hex: 0xFEF3C7))
            case .language: return (Color(hex: 0x047857), Color(hex: 0xD1FAE5))
            }
        }
    }

    let id: Int
    let category: Category
    let mode: Mode
    let title: String
    let icon: String
    let tag: String
    let situation: String
    let text: String
    let steps: [String]
    /// 「一键应用」要设成的状态：选哪条提示词（按内置名字认，nil 不改）、「要求」框里填什么。都为 nil 的场景不显示按钮。
    var preset: Preset? = nil

    struct Preset {
        var style: String?
        var instruction: String
        /// 要用 ▲▼ 翻看几版再替换（和好道歉、错字校对）。
        var versions = false
    }

    /// 场景文字跟着界面语言；练习用的原文保持中文（拼音键盘练的就是中文）。
    /// 步骤里的 {style} 换成当前提示词的名字。
    static var all: [LabScene] { [
        LabScene(id: 0, category: .work, mode: .quick, title: L("回复领导", "Reply to your manager", "上司への返信"), icon: "briefcase",
                 tag: L("润色", "Polish", "整える"),
                 situation: L("领导让你看一份文件，你想回得清楚又不啰嗦。", "Your manager asked you to review a file. You want a clear, brief reply.",
                              "上司に資料の確認を頼まれました。簡潔でわかりやすく返したいときに。"),
                 text: "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看",
                 steps: [L("点 ✨", "Tap ✨", "✨ をタップ"),
                         L("输入框里的话直接换成改好的；不满意点 ↶ 撤销", "The text is rewritten in place. Tap ↶ to undo", "入力欄がそのまま書き換わります。↶ で元に戻せます")],
                 preset: Preset(style: "润色", instruction: "")),
        LabScene(id: 1, category: .work, mode: .quick, title: L("委婉拒绝", "Say no politely", "やんわり断る"), icon: "checkmark.shield",
                 tag: L("按要求改", "Custom changes", "指示して直す"),
                 situation: L("同事催进度，但这周确实做不完。", "A coworker is pushing for progress, but you really can't finish this week.",
                              "同僚に進捗を急かされたけれど、今週中には終わらないときに。"),
                 text: "周五前给不了，下周一吧",
                 steps: [L("点「识意 ▾」，写「语气委婉一点」", "Tap Ask ▾ and type \"softer\"", "「たずねる ▾」をタップし、「やわらかく」と入力"),
                         L("点 ✨，输入框直接改好；不满意点 ↶ 撤销", "Tap ✨ and the text is rewritten in place. Tap ↶ to undo", "✨ をタップすると入力欄が書き換わります。↶ で元に戻せます")],
                 preset: Preset(style: "润色", instruction: L("语气委婉一点", "softer", "やわらかく"))),
        LabScene(id: 2, category: .work, mode: .insert, title: L("请假申请", "Ask for a day off", "休暇の申請"), icon: "calendar",
                 tag: L("帮我写", "Help me write", "下書きを作成"),
                 situation: L("什么都不用打，让 AI 起草一段请假理由。", "Type nothing and let AI draft a reason for a day off.",
                              "何も入力せずに、AI に休暇の理由を下書きしてもらいます。"),
                 text: "",
                 steps: [L("输入框留空，在「要求」里写「请假一天的理由，给领导」", "Leave the field empty and type \"reason for a day off, to my manager\" in Prompt",
                           "入力欄を空のまま、「指示」に「上司宛て、1 日休む理由」と入力"),
                         L("点 ✨，看完点「插入」", "Tap ✨, check the result, then tap Insert", "✨ をタップし、結果を見て「挿入」")],
                 preset: Preset(style: "润色", instruction: L("请假一天的理由，给领导", "reason for a day off, to my manager", "上司宛て、1 日休む理由"))),
        LabScene(id: 3, category: .client, mode: .quick, title: L("安抚客户", "Calm a customer", "お客様へのお詫び"), icon: "headphones",
                 tag: L("润色 · 正式", "Polish · Formal", "整える · 丁寧"),
                 situation: L("客户催发货，你想道歉并给出明确时间。", "A customer is chasing a delivery. You want to apologize and give a clear time.",
                              "発送を急かすお客様に、お詫びとはっきりした日時を伝えたいときに。"),
                 text: "不好意思啊 仓库那边最近爆单了 明天肯定给你发出去 别退款了哈",
                 steps: [L("润色风格选「正式」，点 ✨", "Choose the Formal polish style and tap ✨", "整えるスタイルで「丁寧」を選び、✨ をタップ"),
                         L("直接改好；不满意点 ↶ 撤销", "The text is rewritten in place. Tap ↶ to undo", "そのまま書き換わります。↶ で元に戻せます")],
                 preset: Preset(style: "正式", instruction: "")),
        LabScene(id: 4, category: .social, mode: .replace, title: L("朋友圈文案", "Social post", "SNS の投稿"), icon: "camera",
                 tag: L("按要求改", "Custom changes", "指示して直す"),
                 situation: L("爬山回来，想发一条有点文艺感的朋友圈。", "Back from a hike and want to post something a little poetic.",
                              "山登りから帰って、少し情緒のある投稿をしたいときに。"),
                 text: "今天去爬山了 累死 但是山顶的风景真的绝了 值",
                 steps: [L("在「要求」里写「写成朋友圈文案，文艺一点」", "In Prompt, type \"social post, a bit poetic\"",
                           "「指示」に「SNS 投稿風に、少し情緒的に」と入力"),
                         L("点 ✨，看完点「替换」", "Tap ✨, check the result, then tap Replace", "✨ をタップし、結果を見て「置き換え」")],
                 preset: Preset(style: "润色", instruction: L("写成朋友圈文案，文艺一点", "social post, a bit poetic", "SNS 投稿風に、少し情緒的に"))),
        LabScene(id: 5, category: .social, mode: .replace, title: L("和好道歉", "Make up with a friend", "仲直りのお詫び"), icon: "heart",
                 tag: L("按要求改", "Custom changes", "指示して直す"),
                 situation: L("昨天和朋友吵了两句，想真诚地道个歉。", "You argued with a friend yesterday and want to apologize sincerely.",
                              "昨日友達と言い合いになり、素直に謝りたいときに。"),
                 text: "昨天是我说话太冲了 不是故意的 别生气了",
                 steps: [L("在「要求」里写「真诚一点，别太肉麻」", "In Prompt, type \"sincere, not too sappy\"", "「指示」に「誠実に、でも大げさにしない」と入力"),
                         L("点 ✨，用 ▲▼ 翻看几版，选好点「替换」", "Tap ✨, flip through versions with ▲▼, then tap Replace", "✨ をタップし、▲▼ で案を見比べて「置き換え」")],
                 preset: Preset(style: "润色", instruction: L("真诚一点，别太肉麻", "sincere, not too sappy", "誠実に、でも大げさにしない"), versions: true)),
        LabScene(id: 6, category: .life, mode: .replace, title: L("闲置转卖", "Sell something used", "不用品の出品"), icon: "tag",
                 tag: L("帮我写", "Help me write", "下書きを作成"),
                 situation: L("把一台闲置 iPad 挂到二手平台。", "List a spare iPad on a secondhand marketplace.", "使っていない iPad をフリマに出品します。"),
                 text: "九成新 iPad 买了没怎么用 2000 出 不刀",
                 steps: [L("在「要求」里写「写成闲鱼商品描述，分点列出」", "In Prompt, type \"marketplace listing, as bullets\"", "「指示」に「フリマの商品説明に、箇条書きで」と入力"),
                         L("点 ✨，看完点「替换」", "Tap ✨, check the result, then tap Replace", "✨ をタップし、結果を見て「置き換え」")],
                 preset: Preset(style: "润色", instruction: L("写成闲鱼商品描述，分点列出", "marketplace listing, as bullets", "フリマの商品説明に、箇条書きで"))),
        LabScene(id: 7, category: .language, mode: .insert, title: L("英文邮件", "Email in English", "英語のメール"), icon: "globe",
                 tag: L("翻译", "Translate", "翻訳"),
                 situation: L("约外国同事改会议时间，直接用中文写。", "Ask a coworker abroad to move a meeting, writing in Chinese.",
                              "海外の同僚に会議の変更をお願いします。中国語のまま書きます。"),
                 text: "麻烦帮我确认一下下周二的会议时间，如果你不方便的话可以改到周三下午",
                 steps: [L("在「要求」里写「翻成英文邮件」", "In Prompt, type \"English email\"", "「指示」に「英語のメールに」と入力"),
                         L("点 ✨，看完点「插入」，英文接在中文后面", "Tap ✨, check the result, then tap Insert. The English goes after your Chinese", "✨ をタップし、結果を見て「挿入」。英語が中国語の後ろに入ります")],
                 preset: Preset(style: "润色", instruction: L("翻成英文邮件", "English email", "英語のメールに"))),
        LabScene(id: 8, category: .language, mode: .typing, title: L("中英混打", "Mix Chinese and English", "中国語と英語を混ぜる"), icon: "keyboard",
                 tag: L("输入", "Typing", "入力"),
                 situation: L("技术群里聊天，中文里夹着英文词。", "Chatting with engineers, with English words in Chinese.", "技術チャットで、中国語に英単語を混ぜて書きます。"),
                 text: "这个 bug 我今天下班前 fix 掉，明天早上再 sync 一下进度",
                 steps: [L("用拼音打中文", "Type Chinese with pinyin", "ピンインで中国語を入力"),
                         L("点「中/英」切到全键盘打英文，再切回来", "Tap 中/英 to switch to QWERTY for English, then back", "「中/英」で QWERTY に切り替えて英語を入力し、また戻します")]),
        LabScene(id: 9, category: .life, mode: .replace, title: L("错字校对", "Fix typos", "誤字のチェック"), icon: "doc.text.magnifyingglass",
                 tag: L("润色 · 多版本", "Polish · Versions", "整える · 複数案"),
                 situation: L("活动总结里有几个错别字，帮你一次找出来。", "An event recap has a few typos. Find them all at once.",
                              "イベントの報告に誤字がいくつか。まとめて見つけます。"),
                 text: "我们这次的活动非常成功，参加的人数比预计的多了一倍。大家的反溃都很好，特别是互动环节，很多人表示下次还要来。不过也有一些问题，比如签到太慢，饮料不够，下次需要提前准被。",
                 steps: [L("点 ✨", "Tap ✨", "✨ をタップ"),
                         L("用 ▲▼ 翻看几版，选好点「替换」", "Flip through versions with ▲▼, then tap Replace",
                           "▲▼ で案を見比べ、よければ「置き換え」")],
                 preset: Preset(style: "润色", instruction: "", versions: true)),
    ] }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// 浅色用 light，深色用 dark（可带透明度）。
    init(light: UInt32, dark: UInt32, darkOpacity: CGFloat = 1) {
        func ui(_ hex: UInt32, _ alpha: CGFloat) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? ui(dark, darkOpacity) : ui(light, 1) })
    }
}

/// 场景用法标签：快速 / 替换 / 插入 / 打字（高 22、圆角 11）。
struct LabModeLabel: View {
    let mode: LabScene.Mode
    var height: CGFloat = 22
    var fontSize: CGFloat = 11.5
    var fill: Color?

    var body: some View {
        let colors = mode.colors
        HStack(spacing: 3) {
            Image(systemName: mode.icon).font(.system(size: fontSize - 0.5, weight: .semibold))
            Text(mode.title).font(.system(size: fontSize, weight: .semibold))
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, 7)
        .frame(height: height)
        .background(Capsule().fill(fill ?? colors.fill))
        .accessibilityElement(children: .combine)
    }
}

/// 使用指引（PB6，原「场景实验室」）：试过几个和进度格、下一个推荐、压力测试上次结果，场景按分类分组，试过的打绿勾。
struct LabView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var tried = UsageStats.labTried

    private var next: LabScene? { LabScene.all.first { !tried.contains(String($0.id)) } }

    var body: some View {
        DashPage {
            tourCard
            progressCard
            modesCard
            ForEach(LabScene.Category.allCases, id: \.self) { category in
                let scenes = LabScene.all.filter { $0.category == category }
                if !scenes.isEmpty {
                    Text(category.name).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.leading, 4).padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(scenes) { scene in
                            NavigationLink {
                                SceneView(index: scene.id)
                            } label: {
                                SceneCard(scene: scene, tried: tried.contains(String(scene.id)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("使用指引", "Guide", "使い方ガイド"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tried = UsageStats.labTried
        }
    }

    /// 再玩一次首次打开时的功能演示（模拟键盘、预设结果，不调用 API）。
    private var tourCard: some View {
        Button { router.setupGuide = .tourReplay } label: {
            DashCard {
                HStack(spacing: 12) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x8A7BFF), Color(hex: 0x5B4BE8)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("功能演示 · 约 4 分钟", "Feature Tour · About 4 min", "機能デモ · 約 4 分")).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(L("用模拟键盘把润色、改写、润色风格、问答、分词插入点一遍，不调用 API", "Try Polish, Rewrite, Polish styles, Answer and word picking on a simulated keyboard. No API calls", "模擬キーボードで整える・書き換え・整えるスタイル・回答・単語挿入を試せます。API は使いません")).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var progressCard: some View {
        DashCard {
            DashCardHeader(icon: "flask", title: L("使用指引", "Guide", "使い方ガイド"), color: DashColor.ai)
            HStack(alignment: .firstTextBaseline) {
                DashBigNumber(value: "\(LabScene.triedCount(tried))",
                              unit: L("/ \(LabScene.all.count) 个场景试过", "of \(LabScene.all.count) tried", "/ \(LabScene.all.count) 試した"))
                Spacer(minLength: 8)
                if let next {
                    NavigationLink {
                        SceneView(index: next.id)
                    } label: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L("下一个推荐", "Up next", "次のおすすめ")).font(.caption).foregroundStyle(.secondary)
                            Text(next.title).font(.footnote.weight(.semibold)).foregroundStyle(DashColor.ai)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            DashSegments(total: LabScene.all.count, done: LabScene.triedCount(tried))
        }
    }

    /// 两种用法：快速（面板收起直接改好）和替换 / 插入（展开看结果再用）。
    private var modesCard: some View {
        DashCard {
            DashCardHeader(icon: "hand.tap", title: L("两种用法", "Two ways to use it", "2 つの使い方"), color: DashColor.ai)
            modeRow([.quick], L("面板收起，点一下直接改好输入框", "Panel closed. One tap rewrites the text in place", "パネルを閉じたまま、ワンタップで入力欄を書き換え"))
            modeRow([.replace, .insert], L("展开看结果，满意再替换或插入", "Open the result, then replace or insert it", "結果を開いて確認し、置き換えか挿入"))
            // AI 生成内容提示（大陆上架合规第 3 项）。
            Text(L("润色结果由你配置的大模型生成，请自行核对。", "Results come from the model you set up. Please check them.", "結果は設定したモデルが生成します。内容をご確認ください。"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeRow(_ modes: [LabScene.Mode], _ text: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(modes, id: \.self) { LabModeLabel(mode: $0) }
            }
            Text(text).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// 测试工具 › 压力测试（原使用指引页底部那张卡）：「开始测试」进 TypingTestView。
struct StressTestCard: View {
    @State private var lastTest = TypingTestRecord.load().first

    var body: some View {
        card.onAppear { lastTest = TypingTestRecord.load().first }
    }

    private var card: some View {
        NavigationLink {
            TypingTestView()
        } label: {
            DashCard {
                DashCardHeader(icon: "speedometer", title: L("压力测试", "Stress test", "負荷テスト"), color: DashColor.input,
                               note: lastTest.map { L("上次 \(Loc.monthDay($0.date))", "Last \(Loc.monthDay($0.date))", "前回 \(Loc.monthDay($0.date))") })
                if let lastTest {
                    HStack(alignment: .top) {
                        stat("\(lastTest.speed)", L("字 / 分钟", "chars/min", "字／分"))
                        stat(lastTest.slowTotal.map { "\(Int($0.rounded())) ms" } ?? "–", L("较慢的 10% 按键", "slowest 10% of keys", "遅い 10% のキー"))
                        stat(lastTest.memoryPeak.map { "\(Int($0)) MB" } ?? "–", L("键盘内存", "keyboard memory", "キーボードのメモリ"))
                    }
                } else {
                    Text(L("照着文章连续打字，看速度、卡顿和键盘内存", "Type a passage nonstop and see speed, lag and keyboard memory", "文章を続けて入力し、速さ・遅延・メモリを確認"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension LabScene {
    /// 一键应用后小手依次指的按钮：快速只指一步；替换 / 插入一路指到「替换」「插入」。
    var coachSteps: [LabCoachMark.Step] {
        guard let preset else { return [] }
        let first: LabCoachMark.Step = preset.instruction.isEmpty ? .sparkle : .run
        switch mode {
        case .quick: return [first]
        case .replace: return preset.versions ? [first, .versions, .replace] : [first, .replace]
        case .insert: return [first, .insert]
        case .typing: return []
        }
    }

    /// 试过的场景数，设置页「试过 N/10」也用。
    static func triedCount(_ tried: Set<String> = UsageStats.labTried) -> Int {
        all.filter { tried.contains(String($0.id)) }.count
    }

    static var triedCount: Int { triedCount() }
}

private struct SceneCard: View {
    let scene: LabScene
    var tried = false

    var body: some View {
        let colors = scene.category.colors
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: scene.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.text)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.fill))
                Spacer()
                if tried {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(DashColor.ok)
                        .accessibilityLabel(L("试过", "Tried", "試した"))
                }
            }
            .padding(.bottom, 4)
            Text(scene.title).font(.system(size: 15.5, weight: .semibold))
            Text(scene.situation)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 5) {
                LabModeLabel(mode: scene.mode)
                Text(scene.tag)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(.tertiarySystemFill)))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// 一个场景一页：进来自动聚焦弹出键盘，右上「重置」恢复预填文字，底部上一个 / 下一个。
struct SceneView: View {
    @EnvironmentObject private var store: AppStore
    @State private var index: Int
    @State private var text: String
    @FocusState private var focused: Bool
    /// 点过「一键应用」：按钮变成绿色「已应用」，换场景时复原。
    @State private var applied = false

    init(index: Int) {
        _index = State(initialValue: index)
        _text = State(initialValue: LabScene.all[index].text)
    }

    private var scene: LabScene { LabScene.all[index] }

    var body: some View {
        let colors = scene.category.colors
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: scene.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colors.text)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(colors.fill))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("\(scene.category.name) · 场景 \(index + 1)/\(LabScene.all.count)", "\(scene.category.name) · Scene \(index + 1)/\(LabScene.all.count)", "\(scene.category.name) · シーン \(index + 1)/\(LabScene.all.count)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.text)
                        Text(scene.title).font(.system(size: 20, weight: .bold))
                    }
                }
                Text(scene.situation).font(.subheadline).foregroundStyle(.secondary)
                TextField(scene.text.isEmpty ? L("输入框留空，按下面的提示让它帮你写", "Leave this empty and follow the steps below to have it written for you", "空欄のまま、下の手順で書いてもらいます") : L("在这里输入…", "Type here…", "ここに入力…"), text: $text, axis: .vertical)
                    .submitLabel(.return)
                    .lineLimit(3...10)
                    .focused($focused)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColor.purple, lineWidth: focused ? 2 : 0))
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("试试这样做", "Try this", "試してみましょう")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if let preset = scene.preset { applyButton(preset) }
                    }
                    if let explanation = scene.mode.explanation {
                        HStack(alignment: .top, spacing: 8) {
                            LabModeLabel(mode: scene.mode, height: 26, fontSize: 13, fill: Color(.secondarySystemGroupedBackground))
                            Text(explanation).font(.system(size: 13)).foregroundStyle(scene.mode.colors.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(scene.mode.colors.fill))
                    }
                    ForEach(Array(scene.steps.enumerated()), id: \.offset) { number, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(number + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColor.purple)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(AppColor.softFill))
                            // ✨ 旁边显示的是当前提示词的名字，提示里跟着写。
                            Text(step.replacingOccurrences(of: "{style}",
                                                           with: store.settings.selectedStyle?.displayName ?? L("润色", "Polish", "整える")))
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                HStack {
                    Button { go(index - 1) } label: { Label(L("上一个", "Previous", "前へ"), systemImage: "chevron.left") }
                        .disabled(index == 0)
                    Spacer()
                    if index + 1 < LabScene.all.count {
                        Button { go(index + 1) } label: {
                            HStack(spacing: 4) {
                                Text(L("下一个：\(LabScene.all[index + 1].title)", "Next: \(LabScene.all[index + 1].title)", "次へ：\(LabScene.all[index + 1].title)"))
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .tint(AppColor.purple)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L("使用指引", "Guide", "使い方ガイド"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: index) {
            // 点进来就算试过这个场景（使用指引列表打绿勾、进度 N / 10）。
            UsageStats.markLabTried(String(index))
            try? await Task.sleep(nanoseconds: 600_000_000)
            focused = true
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L("重置", "Reset", "リセット")) { text = scene.text }
            }
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button(L("收起键盘", "Hide keyboard", "キーボードを閉じる")) { focused = false }
                }
            }
        }
    }

    private func go(_ next: Int) {
        guard LabScene.all.indices.contains(next) else { return }
        index = next
        text = LabScene.all[next].text
        applied = false
    }

    /// 「一键应用」：选好这个场景要用的提示词、把要求填进键盘的「要求」框，再把键盘收起重开，让它读到新状态。
    private func applyButton(_ preset: LabScene.Preset) -> some View {
        Button {
            apply(preset)
        } label: {
            Label(applied ? L("已应用", "Applied", "適用済み") : L("一键应用", "Apply", "ワンタップで適用"),
                  systemImage: applied ? "checkmark" : "wand.and.stars")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(applied ? DashColor.ok : DashColor.ai)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill((applied ? DashColor.ok : DashColor.ai).opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("选好润色风格并填好要求", "Picks the polish style and fills in the request", "整えるスタイルを選び、指示を入力します"))
    }

    private func apply(_ preset: LabScene.Preset) {
        if let name = preset.style, let style = store.settings.styles.first(where: { $0.name == name }) {
            store.settings.selectedStyleID = style.id
        }
        SharedStorage.defaults.set(preset.instruction, forKey: SettingsStore.instructionKey)
        // 键盘弹出来时摆好面板（快速模式收起、替换 / 插入展开），在要点的按钮上放小手指（不自动执行）。
        LabCoachMark(scene: scene.id, steps: scene.coachSteps, expanded: scene.mode != .quick,
                     menuOpen: !preset.instruction.isEmpty).write()
        applied = true
        // 键盘只在出现时读设置：收起再弹出来。
        focused = false
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            focused = true
        }
    }
}
