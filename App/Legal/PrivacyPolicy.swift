import Foundation

/// 隐私政策全文（P07），中英日三份；中文是中国大陆备案版（beian/隐私政策-中国大陆版.md）。网页 docs/privacy.html 和 PRIVACY.md 由 scripts/gen-privacy.py 从这里生成，改完运行一次。
/// 开发者名称和联系邮箱在 LegalInfo 里改。
enum PrivacyPolicy {
    static let effectiveDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 30).date ?? Date()

    static func text(_ language: AppLanguage) -> String {
        let raw: String
        switch language {
        case .en: raw = en
        case .ja: raw = ja
        case .zh, .system: raw = zh
        }
        return raw.replacingOccurrences(of: "{developer}", with: language == .en || language == .ja ? LegalInfo.developer : LegalInfo.developerZh)
            .replacingOccurrences(of: "{email}", with: LegalInfo.email)
    }

    private static let zh = """
## 引言

飞地输入法（英文名 Enclave，以下简称“本应用”）是由个人开发者{developer}（以下简称“我们”）开发和提供的中文输入法应用，包含 App 主程序及其附带的键盘扩展。

我们深知个人信息对您的重要性，并依照《中华人民共和国个人信息保护法》等法律法规处理与您相关的信息。本政策说明本应用如何处理信息、您享有哪些权利以及如何联系我们。请您在使用本应用前仔细阅读，特别是以**加粗**方式标示的内容。

首次打开本应用时，我们会通过弹窗向您展示本政策的要点，您点击“同意”后才会启用 AI 相关功能。您不同意的，仍可使用拼音、英文等基础输入功能。

## 一、核心原则

1. **本应用不设账号体系。您的 AI 请求由设备直接发送给您选择的服务商，无第三方中转；我们不收集、不上传您的输入内容。我们的服务器仅用于接收您主动提交的反馈（见第二条第（七）项）和提供可选的词库文件下载。**
2. 打字、候选词计算和输入习惯学习全部在您的设备本地完成。
3. 只有在您主动使用 AI 功能时，相关文字才会发送到**您自己填写**的模型服务接口，且不经过我们。

## 二、各项功能如何处理信息

### （一）文字输入

拼音输入、候选词计算、联想预测和输入习惯学习均在您的设备本地完成，不通过网络传输任何内容。

如您在拼音设置中主动选择下载“整句模型”等词库文件，本应用会从文件服务器（中国大陆店面为我们的服务器 enclavekb.cn，其他地区为 GitHub）下载该文件。下载请求不包含您的输入内容；我们的服务器会依法记录访问日志（IP 地址、时间、请求地址、设备标识），保存 6 个月后删除。

### （二）AI 功能（点 ✨ 执行提示词，例如润色、翻译、改写）

**仅在您主动点击 ✨ 或“执行”时**，本应用会将以下信息直接发送至您自行配置的模型服务接口：

1. 当前输入框中的文字；如您已选中部分文字，则仅发送所选部分；
2. 您填写的要求；
3. 您所选提示词的说明文字。

上述信息由您选择的模型服务提供方依据其服务条款和隐私政策处理，不经过我们的服务器，我们无法访问。**在首次发送前，以及您更换接口地址后，本应用会展示信息将发送到的地址，并单独征得您的同意，未经同意不会发送任何内容。**

**AI 生成内容提示：** AI 功能返回的文字由您配置的大模型生成，本应用会在界面上以“AI 生成”“AI改写”“AI问答”等标签提示。生成内容可能不准确，请您自行核对后使用。我们不会在您的正文中插入任何标记。

本应用预设的模型服务仅为方便填写，您可以自由选择其他服务。我们建议您选择依法完成备案的模型服务。

### （三）识意问答与联网（联网仅在问答接口为千问、Kimi、智谱或腾讯混元时可用）

**仅在您主动在键盘里提问时**，本应用会将您输入的问题，以及输入框中的文字（如有，选中时仅为选中部分），直接发送至您为识意问答配置的模型服务接口。您可以在“接口”页的“问答”中单独设置识意问答使用的接口（服务商、地址、模型和 API 密钥均由您填写），未单独设置时使用上述主接口。问答接口地址同样会在首次发送前单独征得您的同意。

“识意问答联网”分为“开”“每次询问”“禁止”三档，中国大陆默认“禁止”，其他地区默认“开”，您可以随时在“问答”页更改。中国大陆地区预设的问答服务商均为已完成生成式人工智能服务备案的境内服务商。联网只在识意问答时使用，改写不调用联网搜索。是否需要联网由模型根据问题先行判断；需要联网时，选“开”且已同意过该服务商的会直接联网，选“每次询问”或首次使用该服务商时会先在回答框中征得您的同意，选“禁止”时不会联网，仅提示您可前往开启。各服务商的方式和发送内容如下：

1. **Kimi（北京月之暗面科技有限公司）：** 模型判断需要最新信息时，键盘使用**您自己填写的 Kimi API 密钥**，将**您输入的问题本身**（原文，不包含输入框中的其他文字、通讯录或其他个人信息）直接发送至 Kimi 的联网搜索接口，再把搜索结果连同问题发给模型生成回答。
2. **通义千问（阿里云）、智谱 GLM（北京智谱华章科技股份有限公司）、腾讯混元（深圳市腾讯计算机系统有限公司，经腾讯云 TokenHub）：** 联网由服务商自带的搜索功能完成。键盘另发一次开启联网的问答请求，其中**仅包含您输入的问题本身**（不包含输入框中的其他文字、通讯录或其他个人信息），由服务商根据问题生成搜索词、检索公开网页信息并生成回答。

以上请求均使用**您自己填写的 API 密钥**直接发送给对应服务商，不经过我们的服务器。征得同意时，键盘会提示内容将发送给哪家服务商及收费方式。

联网搜索按次计费，费用由对应服务商从**您在该服务商的账户**扣除（Kimi、智谱目前约每次 0.01 元，千问按阿里云百炼的价格，腾讯混元按腾讯云 TokenHub 的价格，均以官方价格为准），我们不收取任何费用。

选择“禁止”或在回答框中拒绝联网时，问题只发送给模型本身，不会联网搜索。回答同样以“AI问答”标签提示，内容可能不准确或过时，请您自行核对。

### （四）试用与购买

本应用提供 14 天免费试用，试用结束后 AI 功能每天可免费使用一定次数，也可通过 App Store 一次性购买解锁。付款由 Apple 处理，我们不会获得您的付款信息。本应用通过 Apple 提供的接口读取本应用的首次下载日期和购买记录，用于计算试用期和确认是否已购买。

### （五）通讯录（可选）

仅在您开启“使用通讯录里的名字”后，键盘通过系统接口读取联系人姓名作为候选词，不读取电话号码等其他信息，也不会上传。您可以随时关闭该开关或在系统设置中撤回通讯录权限。

### （六）使用统计

为了在 App 首页向您展示使用情况，本应用按天记录 AI 使用次数、常用词上屏次数等计数，**只保存在您的设备上，保留 30 天，不上传**。计数不包含您输入的具体内容。

### （七）反馈

**仅在您在“反馈问题”页面主动填写并点击提交时**，本应用会通过加密连接（HTTPS）将以下信息发送至我们位于中国大陆的服务器（enclavekb.cn）：您填写的反馈内容和反馈类型；您选填的联系方式（用于回复您）；您选择附上的截图（最多 3 张）；App 版本、设备型号、系统版本、界面语言和 App Store 地区；以及在您选择附上时，本机的诊断记录（闪退、卡顿记录，不含您输入的文字）。

服务器收到后立即通过邮件服务（腾讯 QQ 邮箱）转发给我们，**服务器上不保存反馈内容**。为防止滥用，服务器会按 IP 地址限制提交频率，计数仅保存在内存中，24 小时内清除。反馈邮件保存在我们的邮箱中，仅用于处理您的问题和改进本应用，处理完毕后最长保存 12 个月；您可以随时发邮件至 {email} 要求删除。**您的反馈信息将传输至中国境外，由我们使用的 Google 邮箱（Google LLC，美国）接收处理**；在中国大陆店面，提交前本应用会以单独勾选的方式征得您的同意，您不勾选的，无法提交反馈。不提交反馈不影响您使用本应用的任何功能。

## 三、在设备本地存储的信息

以下信息仅保存在您的设备上：

1. 您填写的模型服务 API 密钥（包括主接口、问答接口及您保存的接口方案），保存在系统钥匙串中；
2. AI 历史记录，包括原文与生成结果；
3. 拼音输入学习记录；
4. 您的提示词、常用词、键盘、接口及语言设置；
5. 试用开始日期、购买状态、当日 AI 使用次数和按天使用统计；
6. 您同意本政策的版本和时间。

您可以在“设置 › 隐私”中清除 AI 历史记录和拼音输入学习记录。**卸载本应用后，上述信息将全部删除**（购买记录由 App Store 保存，重新安装后可恢复）。

## 四、权限说明

**允许完全访问（键盘）：** 用于联网调用您配置的模型接口、按键振动、与 App 同步设置。不开启时，拼音和英文输入正常，AI 功能不可用。

**通讯录（可选）：** 用于读取联系人姓名作为候选词。不开启时，候选词中不出现联系人姓名。

本应用不申请定位、相机、麦克风、相册等权限。

## 五、第三方服务

1. 本应用**未集成任何第三方统计、广告、推送或崩溃报告 SDK**。本应用使用的开源输入引擎 Rime 在本地运行，不联网。
2. AI 功能所使用的模型服务由您自行选择和配置，您与该服务提供方之间的数据处理关系受其服务条款和隐私政策约束。
3. 如您开启识意问答联网，联网搜索由您选择的问答服务商（千问、Kimi、智谱或腾讯混元）完成，适用该服务商的服务条款和隐私政策。
4. 购买由 Apple 的 App Store 处理，适用 Apple 的隐私政策。
5. 您提交的反馈通过腾讯 QQ 邮箱的发信服务转发给我们，适用腾讯的隐私政策。

## 六、您的权利

1. **查阅和删除：** 您的信息都保存在您的设备上，您可以在本应用内查看 AI 历史记录和设置，并随时在“设置 › 隐私”中清除，或卸载本应用删除全部信息。
2. **撤回同意：** 您可以在“设置 › 隐私”中撤回对本政策的同意，撤回后本应用回到基础输入功能模式；也可以撤回对某个接口地址的发送同意，撤回后下一次发送前会再次征求您的同意。撤回同意不影响撤回前基于您的同意已进行的处理。
3. **关闭权限：** 您可以随时在系统设置中关闭“允许完全访问”或通讯录权限。
4. **联系我们：** 对以上权利的行使有任何问题，可通过第九条的方式联系我们。

由于我们不持有您的任何个人信息，无法也无需为您提供账号注销服务。

## 七、未成年人保护

本应用不面向 14 周岁以下的未成年人。若您是 14 周岁以下的未成年人，请在监护人的陪同和同意下使用本应用。

## 八、本政策的更新

我们可能适时修订本政策，修订后的政策将在本应用内发布，并更新版本号和生效日期。**如修订涉及信息处理方式的重大变更，我们将在您下次打开本应用时以弹窗方式通知您并重新征求您的同意。**

## 九、联系我们

开发者：{developer}（个人开发者）
电子邮箱：{email}
ICP 备案号：皖ICP备2026038401号-1A

我们将在收到您的反馈后 15 个工作日内答复。如您对我们的答复不满意，可以向网信、工信等有关主管部门投诉或举报。
"""

    private static let en = """
## Introduction

Enclave (the "App") is provided by {developer} ("we", "us"). This Privacy Policy explains how information is handled when you use the App and its keyboard extension, and describes your rights.

## 1. Information We Collect

The App has no user accounts. Your AI requests go straight from your device to the provider you chose, with no third-party relay, and we never collect or upload what you type. Our own server is used only to receive feedback you choose to send (see "Feedback" below) and to offer optional dictionary downloads.

## 2. How Each Feature Handles Information

### Typing

Pinyin input, candidate generation and input learning are performed entirely on your device. No content is transmitted over the network.

If you choose to download an optional dictionary file such as the sentence model in the Pinyin settings, the App downloads it from a file server (our server enclavekb.cn for the mainland China storefront, GitHub elsewhere). The download request contains nothing you type; our server keeps access logs (IP address, time, requested address, device identifier) for 6 months as required by law, then deletes them.

### AI Polish

Only when you tap Polish or Rewrite, the App sends the following directly to the model service endpoint that you have configured:

- the text in the current input field, or only the selected portion if text is selected;
- any prompt you have entered;
- the description of the selected style.

This information is processed by the model service provider you have chosen, under that provider's privacy policy. It does not pass through our servers, and we have no access to it.

Before the first transmission, and whenever you change the endpoint address, the App shows you where the text will be sent and asks for your separate consent. Nothing is sent without your consent.

**AI-generated content:** Text returned by AI features is generated by the model you configured, and the App labels it on screen with tags such as "AI-generated", "AI edit" and "AI Q&A". It may be inaccurate, so please check it before use. We never insert any marker into your text.

### Ask Answers and Web Search (web search only with a Qwen, Kimi, Zhipu or Tencent Hunyuan answers API)

**Only when you actively ask a question in the keyboard**, the App sends your question, plus the text in the input field if any (just the selection, if there is one), directly to the model service API you configured for Ask answers. On the API page, under Answers, you can set a separate API for Ask answers (you enter the provider, URL, model and API key); if you don't, the main API above is used. Before the first transmission to an answers API address, the App also asks for your separate consent.

Web search in Ask has three settings: On, Ask each time and Off. It is Off by default in mainland China and On in other regions, and you can change it at any time on the Answers page. In mainland China, the preset answer providers are all domestic providers that have completed generative AI service filing. Web search is used only for answers; rewrites never call web search. The model first decides from the question whether it needs the web. If it does: with On, and once you have agreed for that provider, it searches; with Ask each time, or the first time you use a provider, the keyboard asks for your consent in the answer box first; with Off, nothing is searched and the keyboard only tells you where to turn it on. How each provider searches and what is sent:

1. **Kimi (Beijing Moonshot AI Technology Co., Ltd.):** When the model needs current information, the keyboard uses **the Kimi API key you entered** to send **only your question itself**, as typed (no other text in the input field, no contacts or other personal information), directly to Kimi's web search API, then sends the results with the question to the model to produce an answer.
2. **Qwen (Alibaba Cloud), Zhipu GLM (Beijing Zhipu Huazhang Technology Co., Ltd.) and Tencent Hunyuan (Shenzhen Tencent Computer Systems Co., Ltd., via Tencent Cloud TokenHub):** Search is built into the provider's service. The keyboard sends a separate answer request with search turned on that contains **only your question itself** (no other text in the input field, no contacts or other personal information). The provider generates search terms from the question, searches public web pages and produces an answer.

All of these requests go directly to the provider using **the API key you entered** and do not pass through our servers. When asking for consent, the keyboard tells you which provider will receive the content and how it is billed.

Each search is billed by the provider to **your account with that provider** (Kimi and Zhipu currently about ¥0.01 per search, Qwen per Alibaba Cloud Model Studio pricing, Tencent Hunyuan per Tencent Cloud TokenHub pricing; see each provider's official pricing). We charge nothing.

When web search is Off, or you decline it in the answer box, your question goes only to the model. Answers are labeled "AI Q&A" and may be inaccurate or out of date, so please check them yourself.

### Free Trial and Purchase

The App offers a 14-day free trial. After the trial, AI features can be used a limited number of times per day for free, or unlocked with a one-time purchase on the App Store. Payment is handled by Apple, and we never receive your payment details. The App uses Apple's interfaces to read the App's original download date and your purchase record, to calculate the trial and confirm the purchase. Daily usage counts are stored only on your device.

### Feedback

**Only when you fill in and submit the form on the Send Feedback page**, the App sends the following over an encrypted connection (HTTPS) to our server in mainland China (enclavekb.cn): your feedback and its category; the contact details you choose to add, so we can reply; any screenshots you choose to attach (up to 3); the App version, device model, OS version, interface language and App Store region; and, if you choose to attach them, the diagnostic records on your device (crash and hang records, which never include what you type).

The server forwards it to us by email right away (sent through Tencent QQ Mail) and **does not store your feedback**. To prevent abuse, the server limits how often each IP address can submit; these counts are kept only in memory and cleared within 24 hours. The feedback email stays in our mailbox, is used only to handle your request and improve the App, and is kept for at most 12 months after your request is handled. You can ask us to delete it at any time by writing to {email}. Your feedback is received and handled in our Google mailbox (Google LLC, United States). For the mainland China storefront, this means it is transferred outside mainland China, and the App asks you to tick a separate consent box before you can submit. You can use every feature of the App without sending feedback.

## 3. Information Stored on Your Device

The following is stored only on your device:

- the model service API keys you entered (for the main API, the answers API and any API setups you saved), in the system Keychain;
- your polish history, including the original text and the results;
- your pinyin input learning data;
- your style, keyboard, endpoint and language settings;
- the trial start date, purchase status and today's AI usage count.

You can clear the polish history and the input learning data under Settings › Privacy. Deleting the App removes all of this information (your purchase is kept by the App Store and can be restored after reinstalling).

## 4. Permissions

**Allow Full Access.** The keyboard extension uses this permission only to connect to the model service endpoint, provide haptic feedback and sync settings with the App. Without it, Chinese and English typing work normally; only AI Polish is unavailable.

**Contacts (optional).** Only if you turn on "Use names from Contacts", the keyboard reads contact names through the system interface to offer them as candidates. It does not read phone numbers or other details, and nothing is uploaded.

## 5. Third-Party Services

The App contains no third-party analytics, advertising or crash-reporting SDKs. The model service used for AI Polish is chosen and configured by you. Its terms of service and privacy policy govern how it processes your data. If you use web search in Ask, the search is done by the answer provider you chose (Qwen, Kimi, Zhipu or Tencent Hunyuan) under that provider's terms of service and privacy policy. Purchases are processed by Apple's App Store under Apple's privacy policy. Feedback you send is forwarded to us through Tencent QQ Mail under Tencent's privacy policy.

## 6. Your Rights

- **Withdraw consent:** under Settings › Privacy, at any time. The App will ask again before the next transmission.
- **Delete data:** clear the locally stored polish history and input learning data at any time.
- **Disable permissions:** turn off Allow Full Access in the system Settings at any time.

## 7. Children

The App is not directed at children under 13. Minors should use the App under the guidance of a parent or guardian.

## 8. Changes to This Policy

We may update this Privacy Policy from time to time. Updates will be published in the App with a revised effective date. We will notify you prominently in the App of any material change to how information is handled.

## 9. Contact Us

Email: {email}
ICP filing: 皖ICP备2026038401号-1A

We will respond within 15 business days.
"""

    private static let ja = """
## はじめに

Enclave（以下「本アプリ」）は {developer}（以下「当方」）が提供します。本ポリシーは、本アプリおよび付属のキーボード拡張をご利用いただく際の情報の取り扱いと、お客様の権利について説明するものです。

## 1. 収集する情報

本アプリにはアカウント機能がありません。AI へのリクエストは端末から選択したサービスへ直接送信され、第三者の中継はありません。入力内容を当方が収集・送信することはありません。当方のサーバーは、お客様が送信したフィードバックの受け取り（下記「フィードバック」）と任意の辞書ファイルの配布にのみ使います。

## 2. 機能ごとの情報の取り扱い

### 文字入力

ピンイン入力、候補の生成、入力の学習はすべてお客様の端末上で行われ、内容がネットワークで送信されることはありません。

ピンイン設定で整句モデルなどの辞書ファイルをダウンロードすることを選んだ場合、本アプリはファイルサーバー（中国本土のストアは当方の enclavekb.cn、その他の地域は GitHub）からダウンロードします。リクエストに入力内容は含まれません。当方のサーバーは法令に基づきアクセスログ（IP アドレス、日時、リクエスト先、端末識別情報）を 6 か月保存した後に削除します。

### AI 機能

お客様が「整える」または「別の案」をタップしたときに限り、本アプリは次の情報を、お客様が設定したモデルサービスの API に直接送信します。

- 現在の入力欄の文章（一部を選択している場合は選択部分のみ）
- お客様が入力した指示
- 選択した文体の説明文

これらの情報は、お客様が選択したモデルサービスの提供者が、その提供者のプライバシーポリシーに従って処理します。当方のサーバーを経由することはなく、当方が内容にアクセスすることはできません。

初回の送信前、および API の URL を変更したときは、送信先を表示したうえで個別に同意をいただきます。同意なく内容を送信することはありません。

**AI 生成コンテンツの表示：** AI 機能が返す文章は、お客様が設定したモデルが生成したもので、本アプリは画面上で「AI 生成」「AI書換」「AI回答」などのラベルで表示します。不正確な場合があるため、ご自身で確認してからお使いください。お客様の文章に目印を入れることはありません。

### 質問への回答とウェブ検索（ウェブ検索は回答用 API が Qwen・Kimi・Zhipu・Tencent Hunyuan のときのみ）

**お客様がキーボードで自分から質問したときだけ**、入力した質問と、あれば入力欄の文章（選択している場合はその部分だけ）を、質問への回答用に設定したモデルサービスの API に直接送信します。API ページの「回答」で回答用の API を別に設定できます（サービス、URL、モデル、API キーはお客様が入力します）。設定しない場合は上記のメインの API を使います。回答用 API の URL にも、初回の送信前に個別に同意をいただきます。

「質問でウェブ検索」には「オン」「毎回確認」「オフ」の 3 段階があり、中国大陸では初期設定で「オフ」、その他の地域では「オン」です。「回答」ページでいつでも変更できます。中国大陸でプリセットしている回答用サービスは、すべて生成 AI サービスの届出を済ませた国内のサービスです。検索するのは回答のときだけで、書き換えではウェブ検索を使いません。検索が必要かどうかは、まず質問をもとにモデルが判断します。必要な場合、「オン」でそのサービスに同意済みなら検索し、「毎回確認」またはそのサービスを初めて使うときは回答欄で先に同意を求め、「オフ」では検索せず、オンにできる場所をお知らせするだけです。サービスごとの方法と送信内容は次のとおりです。

1. **Kimi（北京月之暗面科技有限公司）：** 最新の情報が必要とモデルが判断したとき、キーボードが**お客様が入力した Kimi の API キー**を使い、**入力した質問そのもの**（原文のみ。入力欄のほかの文章、連絡先、その他の個人情報は含みません）を Kimi のウェブ検索 API へ直接送り、検索結果を質問とともにモデルに送って回答を作ります。
2. **Qwen（Alibaba Cloud）・Zhipu GLM（北京智譜華章科技股份有限公司）・Tencent Hunyuan（深圳市腾讯计算机系统有限公司、Tencent Cloud TokenHub 経由）：** 検索はサービス側の機能で行います。キーボードは検索をオンにした回答リクエストを別に送り、その中身は**入力した質問そのものだけ**です（入力欄のほかの文章、連絡先、その他の個人情報は含みません）。サービス側が質問から検索語を作り、公開されているウェブページを検索して回答を作ります。

いずれも**お客様が入力した API キー**で各サービスに直接送信し、当方のサーバーは経由しません。同意を求める際は、送信先のサービスと課金方法をキーボードで示します。

検索は 1 回ごとに各サービスが**お客様のそのサービスのアカウント**に課金します（Kimi・Zhipu は現在 1 回約 0.01 元、Qwen は Alibaba Cloud Model Studio の料金、Tencent Hunyuan は Tencent Cloud TokenHub の料金。各サービスの公式料金をご確認ください）。当方が料金を受け取ることはありません。

「オフ」のとき、または回答欄で検索を断ったときは、質問はモデルにのみ送られます。回答には「AI回答」と表示され、不正確または古い可能性があるため、ご自身でご確認ください。

### 無料体験と購入

本アプリには 14 日間の無料体験があり、終了後も AI 機能は 1 日に一定回数まで無料で使えます。App Store での買い切り購入で回数制限がなくなります。支払いは Apple が処理し、当方がお支払い情報を受け取ることはありません。無料体験の期間計算と購入の確認のため、本アプリは Apple の仕組みを通じて初回ダウンロード日と購入履歴を読み取ります。1 日の使用回数はお客様の端末にのみ記録されます。

### フィードバック

**「フィードバックを送る」画面でお客様が入力して送信した場合に限り**、本アプリは暗号化された通信（HTTPS）で、中国本土にある当方のサーバー（enclavekb.cn）へ次の情報を送信します：フィードバックの内容と種類、返信用に任意で入力された連絡先、添付を選んだスクリーンショット（最大 3 枚）、アプリのバージョン・端末の機種・OS のバージョン・表示言語・App Store の地域、および添付を選んだ場合は端末内の診断記録（クラッシュやフリーズの記録で、入力した文字は含みません）。

サーバーは受け取った内容をすぐにメール（Tencent QQ メール経由）で当方へ転送し、**フィードバックの内容をサーバーに保存しません**。不正利用を防ぐため、IP アドレスごとに送信回数を制限しますが、この記録はメモリ上にのみ保持し、24 時間以内に消去します。フィードバックのメールは当方のメールボックスに保管され、お問い合わせへの対応と本アプリの改善にのみ使い、対応完了後最長 12 か月で削除します。削除のご依頼は {email} までいつでもどうぞ。フィードバックは当方が使用する Google のメールボックス（Google LLC、米国）で受信・処理されます。中国本土のストアでは中国本土の外への移転となるため、送信前に別途同意のチェックをお願いしています。フィードバックを送らなくても、本アプリのすべての機能をご利用いただけます。

## 3. 端末に保存される情報

次の情報はお客様の端末にのみ保存されます。

- お客様が入力したモデルサービスの API キー（メインの API、回答用 API、保存した API の設定を含む。システムのキーチェーンに保存）
- 整えた履歴（元の文章と結果）
- ピンイン入力の学習データ
- 文体、キーボード、API、言語の設定
- 無料体験の開始日、購入状況、当日の AI 使用回数

整えた履歴と入力の学習データは「設定 › プライバシー」で消去できます。本アプリを削除すると、これらの情報もすべて削除されます（購入履歴は App Store が保持しており、再インストール後に復元できます）。

## 4. 権限について

**フルアクセスを許可：** キーボード拡張はこの権限を、モデルサービスへの接続、触覚フィードバック、本アプリとの設定の同期にのみ使用します。オフでも中国語・英語の入力は通常どおり使え、AI 機能のみ使えなくなります。

**連絡先（任意）：** 「連絡先の名前を使う」をオンにした場合に限り、キーボードはシステムの仕組みを通じて連絡先の名前を候補として読み込みます。電話番号などの情報は読み取らず、送信もしません。

## 5. 第三者のサービス

本アプリには、第三者の分析・広告・クラッシュレポートのツールは組み込まれていません。AI 機能で使うモデルサービスはお客様が選択・設定するもので、そのサービスの利用規約とプライバシーポリシーが適用されます。質問のウェブ検索を使う場合、検索はお客様が選んだ回答用サービス（Qwen・Kimi・Zhipu・Tencent Hunyuan）が行い、そのサービスの利用規約とプライバシーポリシーが適用されます。購入は Apple の App Store が処理し、Apple のプライバシーポリシーが適用されます。送信されたフィードバックは Tencent QQ メールの送信サービスを通じて当方へ転送され、Tencent のプライバシーポリシーが適用されます。

## 6. お客様の権利

- **同意の撤回：**「設定 › プライバシー」からいつでも撤回できます。撤回後は、次回の送信前にあらためて同意をお願いします。
- **情報の削除：** 端末に保存された整えた履歴と入力の学習データはいつでも消去できます。
- **権限の無効化：** システムの設定で「フルアクセスを許可」をいつでもオフにできます。

## 7. 未成年の方

本アプリは 13 歳未満の方を対象としていません。未成年の方は保護者の指導のもとでご利用ください。

## 8. 本ポリシーの変更

本ポリシーは必要に応じて改定することがあります。改定後のポリシーは本アプリ内で公開し、施行日を更新します。情報の取り扱いに重要な変更がある場合は、本アプリ内でわかりやすくお知らせします。

## 9. お問い合わせ

メール：{email}
ICP 届出番号：皖ICP备2026038401号-1A

お問い合わせには 15 営業日以内に回答します。
"""
}

/// 上架前填写：App Store 上显示的开发者名称、对外联系邮箱。
enum LegalInfo {
    static let developer = "Gengyun Qin"
    /// 中文政策（大陆备案版）里写中文姓名。
    static let developerZh = "秦耕耘"
    static let email = "cvbk.qin@gmail.com"
    /// ICP 备案号（App 备案，2026-10-30 通过）。关于页显示，点开工信部备案网站。
    static let icpNumber = "皖ICP备2026038401号-1A"
}
