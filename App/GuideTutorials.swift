import SwiftUI

/// 每个预设服务商的分步教程（OB3–OB6 的写法）：前三步在服务商网站上做，第 4 步回到 App 粘贴 Key 并测试。
/// 菜单名和链接按各家 2026-10 的开放平台写；大陆店面用国内站，其他地区用国际站（Key 不通用）。
/// Ollama 没有教程（cvbk：不会的就不会了）。
struct GuideTutorial {
    struct Step {
        var title: String
        var items: [String]
        var link: (title: String, url: String)?
        /// 编号步骤下面的灰字说明（TQ2）。
        var note: String? = nil
        /// 橙色提醒框（TZ3）。
        var warning: String? = nil
    }

    /// 进度条旁边的「DeepSeek 教程」。
    var name: String
    /// 示意图地址栏里的域名。
    var domain: String
    /// 第 4 步「地址」后面的域名。
    var apiHost: String
    /// 顶部站点小胶囊：大陆站 / 国际站；只有一个站的不显示。
    var site: String? = nil
    /// 示意图里按钮的颜色。
    var accent: Color
    /// 示意图第 1 步登录框的标题。
    var signIn: String
    /// 示意图控制台左边一列（4 项）：第 2 步标 topUpIndex，第 3 步标 keysIndex。
    var sidebar: [String]
    var topUpIndex: Int
    var keysIndex: Int
    /// 第 3 步示意图里「创建」按钮上的字。
    var createLabel: String
    var steps: [Step]

    static func of(_ provider: Provider) -> GuideTutorial? {
        let china = Storefront.isMainlandChina
        switch provider {
        case .deepseek: return deepseek
        case .kimi: return china ? kimiChina : kimiGlobal
        case .qwen: return china ? qwenChina : qwenGlobal
        case .glm: return china ? glmChina : glmGlobal
        case .ollama, .openai, .custom: return nil
        }
    }

    // MARK: DeepSeek

    static let deepseek = GuideTutorial(
        name: L("DeepSeek 教程", "DeepSeek guide", "DeepSeek ガイド"),
        domain: "platform.deepseek.com",
        apiHost: "api.deepseek.com",
        accent: Color(hex: 0x4D6BFE),
        signIn: L("登录 DeepSeek 开放平台", "Sign in to DeepSeek Platform", "DeepSeek Platform にログイン"),
        sidebar: [L("用量信息", "Usage", "使用量"), "API keys", L("充值", "Top up", "Top up"), L("接口文档", "Docs", "Docs")],
        topUpIndex: 2, keysIndex: 1,
        createLabel: L("创建 API key", "Create API key", "Create API key"),
        steps: [
            Step(title: L("注册并登录", "Sign up and sign in", "登録してログイン"),
                 items: [L("在 Safari 里打开 DeepSeek 开放平台", "Open the DeepSeek Platform in Safari", "Safari で DeepSeek Platform を開く"),
                         L("手机号或邮箱收验证码，第一次登录就是注册", "Get a code by phone or email. Your first sign-in creates the account", "電話番号かメールでコードを受け取る。初回ログインで登録完了"),
                         L("登录好了回到这里", "Come back here once you're signed in", "ログインしたらここに戻る")],
                 link: (L("打开 platform.deepseek.com", "Open platform.deepseek.com", "platform.deepseek.com を開く"), "https://platform.deepseek.com")),
            Step(title: L("充一点钱", "Add a little credit", "少しチャージする"),
                 items: [L("左边点「充值」", "Tap Top up on the left", "左の「Top up」をタップ"),
                         L("充最少的金额就行，用支付宝或微信付", "The smallest amount is enough", "最小金額で十分です")],
                 link: (L("打开充值页", "Open Top up", "チャージページを開く"), "https://platform.deepseek.com/top_up")),
            Step(title: L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー"),
                 items: [L("左边点「API keys」", "Tap API keys on the left", "左の「API keys」をタップ"),
                         L("点「创建 API key」，名字填「飞地输入法」", "Tap Create API key and name it Enclave", "「Create API key」で名前を Enclave に"),
                         L("点「复制」。Key 只显示这一次", "Tap Copy. The key is shown only once", "「Copy」をタップ。キーは一度しか表示されません")],
                 link: (L("打开 API keys 页", "Open API keys", "API keys ページを開く"), "https://platform.deepseek.com/api_keys")),
        ])

    // MARK: Kimi（月之暗面）

    static let kimiChina = GuideTutorial(
        name: L("Kimi 教程", "Kimi guide", "Kimi ガイド"),
        domain: "platform.moonshot.cn",
        apiHost: "api.moonshot.cn", site: L("大陆站", "China site", "中国本土版"),
        accent: Color(hex: 0x16191E),
        signIn: L("登录 Kimi 开放平台", "Sign in to Kimi Platform", "Kimi Platform にログイン"),
        sidebar: [L("账户总览", "Overview", "概要"), "API Key", L("充值", "Top up", "チャージ"), L("用量", "Usage", "使用量")],
        topUpIndex: 2, keysIndex: 1,
        createLabel: L("新建 API Key", "New API Key", "新規 API Key"),
        steps: [
            Step(title: L("注册并登录", "Sign up and sign in", "登録してログイン"),
                 items: [L("在 Safari 里打开 Kimi 开放平台（月之暗面）", "Open the Kimi Platform (Moonshot AI) in Safari", "Safari で Kimi Platform（Moonshot AI）を開く"),
                         L("手机号收验证码登录，第一次登录就是注册", "Sign in with a code sent to your phone. Your first sign-in creates the account", "電話番号に届くコードでログイン。初回ログインで登録完了"),
                         L("登录好了回到这里", "Come back here once you're signed in", "ログインしたらここに戻る")],
                 link: (L("打开 platform.moonshot.cn", "Open platform.moonshot.cn", "platform.moonshot.cn を開く"), "https://platform.moonshot.cn/console")),
            Step(title: L("充一点钱", "Add a little credit", "少しチャージする"),
                 items: [L("控制台左边点「充值」", "Tap Top up on the left of the console", "コンソール左の「チャージ」をタップ"),
                         L("充最少的金额就行，用支付宝或微信付", "The smallest amount is enough", "最小金額で十分です")],
                 link: (L("打开充值页", "Open Top up", "チャージページを開く"), "https://platform.moonshot.cn/console")),
            Step(title: L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー"),
                 items: [L("左边点「API Key 管理」", "Tap API Key on the left", "左の「API Key」をタップ"),
                         L("点「新建 API Key」，名字填「飞地输入法」", "Tap New API Key and name it Enclave", "「新規 API Key」で名前を Enclave に"),
                         L("点「复制」，Key 只显示这一次", "Tap Copy. The key is shown only once", "「コピー」をタップ。キーは一度しか表示されません")],
                 link: (L("打开 API Key 管理页", "Open API Key management", "API Key 管理ページを開く"), "https://platform.moonshot.cn/console/api-keys")),
        ])

    static let kimiGlobal = GuideTutorial(
        name: L("Kimi 教程", "Kimi guide", "Kimi ガイド"),
        domain: "platform.moonshot.ai",
        apiHost: "api.moonshot.ai", site: L("国际站", "International site", "国際版"),
        accent: Color(hex: 0x16191E),
        signIn: L("登录 Moonshot AI 平台", "Sign in to Moonshot AI", "Moonshot AI にログイン"),
        sidebar: [L("总览", "Overview", "概要"), "API Keys", L("充值", "Recharge", "チャージ"), L("用量", "Usage", "使用量")],
        topUpIndex: 2, keysIndex: 1,
        createLabel: "Create API Key",
        steps: [
            Step(title: L("注册并登录", "Sign up and sign in", "登録してログイン"),
                 items: [L("在 Safari 里打开 Moonshot AI 平台", "Open the Moonshot AI platform in Safari", "Safari で Moonshot AI のプラットフォームを開く"),
                         L("点「Get Started」，用 Google 账号或邮箱登录", "Tap Get Started and sign in with Google or email", "「Get Started」から Google かメールでログイン"),
                         L("登录好了回到这里", "Come back here once you're signed in", "ログインしたらここに戻る")],
                 link: (L("打开 platform.moonshot.ai", "Open platform.moonshot.ai", "platform.moonshot.ai を開く"), "https://platform.moonshot.ai")),
            Step(title: L("充一点钱", "Add a little credit", "少しチャージする"),
                 items: [L("进控制台，点「Recharge」", "In the console, tap Recharge", "コンソールで「Recharge」をタップ"),
                         L("最少充 1 美元激活，累计充满 5 美元送 5 美元券", "A $1 minimum activates the API. Reach $5 in total and you get a $5 voucher", "最低 1 ドルで有効化。累計 5 ドルで 5 ドル分のクーポン")],
                 link: (L("打开控制台", "Open the console", "コンソールを開く"), "https://platform.moonshot.ai/console")),
            Step(title: L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー"),
                 items: [L("左边点「API Keys」", "Tap API Keys on the left", "左の「API Keys」をタップ"),
                         L("点「Create API Key」，名字填「Enclave」，项目选 default", "Tap Create API Key, name it Enclave and pick the default project", "「Create API Key」で名前を Enclave、プロジェクトは default に"),
                         L("点「Copy」，Key 只显示这一次", "Tap Copy. The key is shown only once", "「Copy」をタップ。キーは一度しか表示されません")],
                 link: (L("打开 API Keys 页", "Open API Keys", "API Keys ページを開く"), "https://platform.moonshot.ai/console/api-keys")),
        ])

    // MARK: 通义千问（阿里云百炼）

    static let qwenChina = GuideTutorial(
        name: L("通义千问教程", "Qwen guide", "Qwen ガイド"),
        domain: "bailian.console.aliyun.com",
        apiHost: "dashscope.aliyuncs.com", site: L("大陆站", "China site", "中国本土版"),
        accent: Color(hex: 0x615CED),
        signIn: L("登录阿里云", "Sign in to Alibaba Cloud", "Alibaba Cloud にログイン"),
        sidebar: [L("模型广场", "Models", "モデル"), "API-Key", L("费用", "Billing", "料金"), L("文档", "Docs", "Docs")],
        topUpIndex: 2, keysIndex: 1,
        createLabel: L("创建 API-Key", "Create API-Key", "API-Key を作成"),
        steps: [
            Step(title: L("登录并开通百炼", "Sign in and turn on Model Studio", "ログインして Model Studio を有効化"),
                 items: [L("在 Safari 里打开阿里云百炼，用阿里云账号登录（没有就注册）", "Open Alibaba Cloud Model Studio in Safari and sign in with an Alibaba Cloud account (or sign up)", "Safari で Alibaba Cloud Model Studio を開き、Alibaba Cloud アカウントでログイン（なければ登録）"),
                         L("第一次进百炼，勾选同意服务协议，点「确认开通」", "The first time, accept the service agreement and tap Activate", "初回は利用規約に同意して「有効化」をタップ"),
                         L("开通好了回到这里", "Come back here once it's on", "有効になったらここに戻る")],
                 link: (L("打开 bailian.console.aliyun.com", "Open bailian.console.aliyun.com", "bailian.console.aliyun.com を開く"), "https://bailian.console.aliyun.com")),
            Step(title: L("先用免费额度", "Start with the free quota", "まずは無料枠で"),
                 items: [L("开通后每个模型送约 100 万 tokens，90 天内有效，现在就能用", "Each model comes with about 1M free tokens for 90 days. You can use them right away", "各モデルに約 100 万トークンの無料枠（90 日間）。すぐに使えます"),
                         L("额度用完后，要先实名认证再充值才能继续（支付宝、银联、网银）", "After that, verify your identity and top up to keep going (Alipay, UnionPay or online banking)", "使い切ったら本人確認とチャージで継続（Alipay・銀聯・ネットバンキング）")],
                 link: nil,
                 note: L("App 里的通义千问用北京地域地址，正好用得上这份免费额度。", "Enclave's Qwen preset uses the Beijing region, so this free quota applies.", "Enclave の Qwen は北京リージョンを使うので、この無料枠が使えます。")),
            Step(title: L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー"),
                 items: [L("百炼控制台点「API-Key」", "In Model Studio, tap API-Key", "Model Studio で「API-Key」をタップ"),
                         L("点「创建 API-Key」，名字填「飞地输入法」", "Tap Create API-Key and name it Enclave", "「API-Key を作成」で名前を Enclave に"),
                         L("点「复制」", "Tap Copy", "「コピー」をタップ")],
                 link: (L("打开 API-Key 页", "Open API-Key", "API-Key ページを開く"), "https://bailian.console.aliyun.com")),
        ])

    static let qwenGlobal = GuideTutorial(
        name: L("通义千问教程", "Qwen guide", "Qwen ガイド"),
        domain: "modelstudio.console.alibabacloud.com",
        apiHost: "dashscope-intl.aliyuncs.com", site: L("国际站", "International site", "国際版"),
        accent: Color(hex: 0x615CED),
        signIn: L("登录 Alibaba Cloud", "Sign in to Alibaba Cloud", "Alibaba Cloud にログイン"),
        sidebar: [L("模型", "Models", "モデル"), "API Key", L("费用", "Billing", "料金"), L("文档", "Docs", "Docs")],
        topUpIndex: 2, keysIndex: 1,
        createLabel: "Create API Key",
        steps: [
            Step(title: L("登录并开通 Model Studio", "Sign in and turn on Model Studio", "ログインして Model Studio を有効化"),
                 items: [L("在 Safari 里打开 Alibaba Cloud Model Studio（新加坡）", "Open Alibaba Cloud Model Studio (Singapore) in Safari", "Safari で Alibaba Cloud Model Studio（シンガポール）を開く"),
                         L("用 Alibaba Cloud 国际站账号登录，没有就注册一个", "Sign in with an Alibaba Cloud international account, or create one", "Alibaba Cloud 国際版アカウントでログイン。なければ作成"),
                         L("第一次进来同意服务协议就开通了", "Accept the service agreement the first time. That turns it on", "初回に利用規約に同意すると有効になります")],
                 link: (L("打开 Model Studio", "Open Model Studio", "Model Studio を開く"), "https://modelstudio.console.alibabacloud.com")),
            Step(title: L("添加付款方式", "Add a payment method", "支払い方法を追加"),
                 items: [L("新账号有一份免费额度，先用它试", "New accounts get a free quota to try with", "新規アカウントには無料枠があります"),
                         L("在账号的「Billing」里绑一张卡，额度用完后按量扣费", "Add a card under Billing so it keeps working after the quota", "「Billing」でカードを登録すると、無料枠のあとも従量課金で使えます")],
                 link: (L("打开 Model Studio", "Open Model Studio", "Model Studio を開く"), "https://modelstudio.console.alibabacloud.com")),
            Step(title: L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー"),
                 items: [L("在 Model Studio 打开「API Key」页", "Open the API Key page in Model Studio", "Model Studio で「API Key」ページを開く"),
                         L("点「Create API Key」，描述填「Enclave」", "Tap Create API Key and describe it as Enclave", "「Create API Key」で説明を Enclave に"),
                         L("点「View」再复制", "Tap View, then copy it", "「View」を押してからコピー")],
                 link: (L("打开 Model Studio", "Open Model Studio", "Model Studio を開く"), "https://modelstudio.console.alibabacloud.com")),
        ])

    // MARK: 智谱 GLM

    static let glmChina = GuideTutorial(
        name: L("智谱 GLM 教程", "Zhipu GLM guide", "Zhipu GLM ガイド"),
        domain: "open.bigmodel.cn",
        apiHost: "open.bigmodel.cn", site: L("大陆站", "China site", "中国本土版"),
        accent: Color(hex: 0x2D55E0),
        signIn: L("登录智谱开放平台", "Sign in to Zhipu Open Platform", "Zhipu Open Platform にログイン"),
        sidebar: [L("个人中心", "Account", "アカウント"), "API Keys", L("财务", "Billing", "料金"), L("文档", "Docs", "Docs")],
        topUpIndex: 2, keysIndex: 1,
        createLabel: L("添加新的 API Key", "Add API Key", "API Key を追加"),
        steps: [
            Step(title: L("注册并登录", "Sign up and sign in", "登録してログイン"),
                 items: [L("在 Safari 里打开智谱开放平台", "Open the Zhipu Open Platform in Safari", "Safari で Zhipu Open Platform を開く"),
                         L("点右上角「注册/登录」，手机号收验证码", "Tap Sign up / Log in at the top right and get a code by phone", "右上の「注册/登录」から電話番号でコードを受け取る"),
                         L("登录好了回到这里", "Come back here once you're signed in", "ログインしたらここに戻る")],
                 link: (L("打开 bigmodel.cn", "Open bigmodel.cn", "bigmodel.cn を開く"), "https://open.bigmodel.cn")),
            Step(title: L("先用赠送额度", "Start with the free credit", "まずは無料分で"),
                 items: [L("新用户通常有赠送额度，可以先用", "New users usually get free credit to start with", "新規ユーザーは無料分があることが多いので、まずそれを"),
                         L("用完了在控制台实名认证、充值", "When it runs out, verify your identity and top up in the console", "使い切ったらコンソールで本人確認とチャージ")],
                 link: (L("打开控制台", "Open the console", "コンソールを開く"), "https://bigmodel.cn/usercenter")),
            Step(title: L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー"),
                 items: [L("右上角头像 › 个人中心，点「API Keys」", "Avatar at the top right › Account, then tap API Keys", "右上のアイコン › アカウント で「API Keys」をタップ"),
                         L("点「添加新的 API Key」，名字填「飞地输入法」", "Tap Add API Key and name it Enclave", "「API Key を追加」で名前を Enclave に"),
                         L("点「复制」", "Tap Copy", "「コピー」をタップ")],
                 link: (L("打开 API Keys 页", "Open API Keys", "API Keys ページを開く"), "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"),
                 warning: L("要建普通 API Key。编程套餐、团队套餐的 Key 是另一套，填进来用不了。", "Create a regular API key. Coding Plan and team plan keys are separate and won't work here.", "通常の API Key を作ってください。コーディングプラン・チームプランのキーは別物で、ここでは使えません。")),
        ])

    static let glmGlobal = GuideTutorial(
        name: L("智谱 GLM 教程", "Zhipu GLM guide", "Zhipu GLM ガイド"),
        domain: "z.ai",
        apiHost: "api.z.ai", site: L("国际站", "International site", "国際版"),
        accent: Color(hex: 0x2D55E0),
        signIn: L("登录 Z.ai", "Sign in to Z.ai", "Z.ai にログイン"),
        sidebar: [L("总览", "Overview", "概要"), "API Keys", L("充值", "Billing", "料金"), L("文档", "Docs", "Docs")],
        topUpIndex: 2, keysIndex: 1,
        createLabel: "Create API Key",
        steps: [
            Step(title: L("注册并登录", "Sign up and sign in", "登録してログイン"),
                 items: [L("在 Safari 里打开 Z.ai 开放平台（智谱国际站）", "Open the Z.ai platform (Zhipu's international site) in Safari", "Safari で Z.ai（Zhipu の国際版）を開く"),
                         L("用 Google 账号或邮箱注册登录", "Sign up with Google or email", "Google かメールで登録・ログイン"),
                         L("登录好了回到这里", "Come back here once you're signed in", "ログインしたらここに戻る")],
                 link: (L("打开 z.ai", "Open z.ai", "z.ai を開く"), "https://z.ai")),
            Step(title: L("充一点钱", "Add a little credit", "少しチャージする"),
                 items: [L("在账号的「Billing」里充最少的金额就行", "Top up the smallest amount under Billing", "「Billing」で最小金額をチャージ")],
                 link: (L("打开 z.ai", "Open z.ai", "z.ai を開く"), "https://z.ai")),
            Step(title: L("创建 Key 并复制", "Create a key and copy it", "キーを作ってコピー"),
                 items: [L("打开「API Keys」页", "Open the API Keys page", "「API Keys」ページを開く"),
                         L("点「Create API Key」，名字填「Enclave」", "Tap Create API Key and name it Enclave", "「Create API Key」で名前を Enclave に"),
                         L("点「复制」", "Tap Copy", "「コピー」をタップ")],
                 link: (L("打开 z.ai", "Open z.ai", "z.ai を開く"), "https://z.ai"),
                 warning: L("要建普通 API Key。编程套餐的 Key 是另一套，填进来用不了。", "Create a regular API key. Coding Plan keys are separate and won't work here.", "通常の API Key を作ってください。コーディングプランのキーは別物で、ここでは使えません。")),
        ])
}
