import Foundation

/// 隐私政策全文（P07），中英日三份；App 里的隐私政策页和仓库里的 PRIVACY.md 用同一份文字。
/// 开发者名称和联系邮箱在 LegalInfo 里改。
enum PrivacyPolicy {
    static let effectiveDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 25).date ?? Date()

    static func text(_ language: AppLanguage) -> String {
        let raw: String
        switch language {
        case .en: raw = en
        case .ja: raw = ja
        case .zh, .system: raw = zh
        }
        return raw.replacingOccurrences(of: "{developer}", with: LegalInfo.developer)
            .replacingOccurrences(of: "{email}", with: LegalInfo.email)
    }

    private static let zh = """
## 引言

Enclave（以下简称“本应用”）由 {developer}（以下简称“我们”）提供。我们重视您的个人信息和隐私保护。本政策说明本应用在您使用过程中如何处理相关信息，以及您享有的权利。

本政策适用于 Enclave 应用及其附带的键盘扩展。请您在使用本应用前仔细阅读并充分理解本政策。

## 一、我们收集的信息

本应用不设账号体系，不收集、不存储、也不向我们的服务器上传您的个人信息。我们没有为本应用设置任何用于接收用户数据的服务器。

## 二、各项功能的信息处理方式

### （一）文字输入

拼音输入、候选词计算及输入习惯学习均在您的设备本地完成，不通过网络传输任何内容。

### （二）AI 润色

仅在您主动点击“润色”或“再润”时，本应用会将以下信息直接发送至您自行配置的模型服务接口：

1. 当前输入框中的文字；如您已选中部分文字，则仅发送所选部分；
2. 您填写的润色要求；
3. 您所选风格的说明文字。

上述信息由您所选择的模型服务提供方依据其隐私政策进行处理，不经过我们的服务器，我们无法访问相关内容。

在首次发送前，以及您更换接口地址后，本应用将向您展示信息的发送对象，并单独征得您的同意。未经您同意，本应用不会发送任何内容。

### （三）试用与购买

本应用提供 14 天免费试用，试用结束后 AI 功能每天可免费使用一定次数，也可通过 App Store 一次性购买解锁。付款由 Apple 处理，我们不会获得您的付款信息。本应用通过 Apple 提供的接口读取本应用的首次下载日期和购买记录，用于计算试用期和确认是否已购买；每日使用次数只记录在您的设备上。

## 三、在设备本地存储的信息

以下信息仅保存在您的设备上：

1. 模型服务的 API 密钥，保存在系统钥匙串中；
2. 润色历史，包括原文与生成结果；
3. 拼音输入学习记录；
4. 您的风格、键盘、接口及语言设置；
5. 试用开始日期、购买状态和当日 AI 使用次数。

您可以在“设置 › 隐私”中清除润色历史和拼音输入学习记录。卸载本应用后，上述信息将一并删除（购买记录由 App Store 保存，重新安装后可恢复）。

## 四、权限说明

**允许完全访问：** 键盘扩展仅将该权限用于连接模型服务接口、提供按键振动反馈，以及与本应用同步设置。未开启该权限时，拼音及英文输入功能均可正常使用，仅 AI 润色功能不可用。

**通讯录（可选）：** 仅在您开启“使用通讯录里的名字”后，键盘通过系统接口读取联系人姓名用作候选词，不读取电话号码等其他信息，也不会上传。

## 五、第三方服务

本应用未集成任何第三方统计、广告或崩溃报告工具。

AI 润色功能所使用的模型服务由您自行选择和配置。您与该服务提供方之间的数据处理关系受其服务条款和隐私政策约束，建议您在使用前查阅。购买由 Apple 的 App Store 处理，适用 Apple 的隐私政策。

## 六、您的权利

1. **撤回同意：** 您可以随时在“设置 › 隐私”中撤回发送同意。撤回后，本应用在下一次发送前将再次征求您的同意。
2. **删除信息：** 您可以随时清除设备本地保存的润色历史和输入学习记录。
3. **关闭权限：** 您可以随时在系统设置中关闭“允许完全访问”。

## 七、未成年人保护

本应用不面向 14 周岁以下的未成年人。未成年人应在监护人的指导下使用本应用。

## 八、本政策的更新

我们可能适时修订本政策。修订后的政策将在本应用内发布，并更新上方的生效日期。如修订涉及信息处理方式的重大变更，我们将在本应用内以显著方式通知您。

## 九、联系我们

如您对本政策有任何疑问、意见或建议，可通过以下方式与我们联系：

电子邮箱：{email}

我们将在收到您的反馈后 15 个工作日内予以答复。
"""

    private static let en = """
## Introduction

Enclave (the "App") is provided by {developer} ("we", "us"). This Privacy Policy explains how information is handled when you use the App and its keyboard extension, and describes your rights.

## 1. Information We Collect

The App has no user accounts. We do not collect or store your personal information, and we do not upload it to any server we operate. We operate no server for receiving user data.

## 2. How Each Feature Handles Information

### Typing

Pinyin input, candidate generation and input learning are performed entirely on your device. No content is transmitted over the network.

### AI Polish

Only when you tap Polish or Rewrite, the App sends the following directly to the model service endpoint that you have configured:

- the text in the current input field, or only the selected portion if text is selected;
- any prompt you have entered;
- the description of the selected style.

This information is processed by the model service provider you have chosen, under that provider's privacy policy. It does not pass through our servers, and we have no access to it.

Before the first transmission, and whenever you change the endpoint address, the App shows you where the text will be sent and asks for your separate consent. Nothing is sent without your consent.

### Free Trial and Purchase

The App offers a 14-day free trial. After the trial, AI features can be used a limited number of times per day for free, or unlocked with a one-time purchase on the App Store. Payment is handled by Apple, and we never receive your payment details. The App uses Apple's interfaces to read the App's original download date and your purchase record, to calculate the trial and confirm the purchase. Daily usage counts are stored only on your device.

## 3. Information Stored on Your Device

The following is stored only on your device:

- your model service API key, in the system Keychain;
- your polish history, including the original text and the results;
- your pinyin input learning data;
- your style, keyboard, endpoint and language settings;
- the trial start date, purchase status and today's AI usage count.

You can clear the polish history and the input learning data under Settings › Privacy. Deleting the App removes all of this information (your purchase is kept by the App Store and can be restored after reinstalling).

## 4. Permissions

**Allow Full Access.** The keyboard extension uses this permission only to connect to the model service endpoint, provide haptic feedback and sync settings with the App. Without it, Chinese and English typing work normally; only AI Polish is unavailable.

**Contacts (optional).** Only if you turn on "Use names from Contacts", the keyboard reads contact names through the system interface to offer them as candidates. It does not read phone numbers or other details, and nothing is uploaded.

## 5. Third-Party Services

The App contains no third-party analytics, advertising or crash-reporting SDKs. The model service used for AI Polish is chosen and configured by you. Its terms of service and privacy policy govern how it processes your data. Purchases are processed by Apple's App Store under Apple's privacy policy.

## 6. Your Rights

- **Withdraw consent:** under Settings › Privacy, at any time. The App will ask again before the next transmission.
- **Delete data:** clear the locally stored polish history and input learning data at any time.
- **Disable permissions:** turn off Allow Full Access in the system Settings at any time.

## 7. Children

The App is not directed at children under 14. Minors should use the App under the guidance of a parent or guardian.

## 8. Changes to This Policy

We may update this Privacy Policy from time to time. Updates will be published in the App with a revised effective date. We will notify you prominently in the App of any material change to how information is handled.

## 9. Contact Us

Email: {email}

We will respond within 15 business days.
"""

    private static let ja = """
## はじめに

Enclave（以下「本アプリ」）は {developer}（以下「当方」）が提供します。本ポリシーは、本アプリおよび付属のキーボード拡張をご利用いただく際の情報の取り扱いと、お客様の権利について説明するものです。

## 1. 収集する情報

本アプリにはアカウント機能がなく、当方はお客様の個人情報を収集・保存せず、当方のサーバーへ送信することもありません。本アプリのためにユーザーデータを受け取るサーバーは運用していません。

## 2. 機能ごとの情報の取り扱い

### 文字入力

ピンイン入力、候補の生成、入力の学習はすべてお客様の端末上で行われ、内容がネットワークで送信されることはありません。

### AI 機能

お客様が「整える」または「別の案」をタップしたときに限り、本アプリは次の情報を、お客様が設定したモデルサービスの API に直接送信します。

- 現在の入力欄の文章（一部を選択している場合は選択部分のみ）
- お客様が入力した指示
- 選択した文体の説明文

これらの情報は、お客様が選択したモデルサービスの提供者が、その提供者のプライバシーポリシーに従って処理します。当方のサーバーを経由することはなく、当方が内容にアクセスすることはできません。

初回の送信前、および API の URL を変更したときは、送信先を表示したうえで個別に同意をいただきます。同意なく内容を送信することはありません。

### 無料体験と購入

本アプリには 14 日間の無料体験があり、終了後も AI 機能は 1 日に一定回数まで無料で使えます。App Store での買い切り購入で回数制限がなくなります。支払いは Apple が処理し、当方がお支払い情報を受け取ることはありません。無料体験の期間計算と購入の確認のため、本アプリは Apple の仕組みを通じて初回ダウンロード日と購入履歴を読み取ります。1 日の使用回数はお客様の端末にのみ記録されます。

## 3. 端末に保存される情報

次の情報はお客様の端末にのみ保存されます。

- モデルサービスの API キー（システムのキーチェーンに保存）
- 整えた履歴（元の文章と結果）
- ピンイン入力の学習データ
- 文体、キーボード、API、言語の設定
- 無料体験の開始日、購入状況、当日の AI 使用回数

整えた履歴と入力の学習データは「設定 › プライバシー」で消去できます。本アプリを削除すると、これらの情報もすべて削除されます（購入履歴は App Store が保持しており、再インストール後に復元できます）。

## 4. 権限について

**フルアクセスを許可：** キーボード拡張はこの権限を、モデルサービスへの接続、触覚フィードバック、本アプリとの設定の同期にのみ使用します。オフでも中国語・英語の入力は通常どおり使え、AI 機能のみ使えなくなります。

**連絡先（任意）：** 「連絡先の名前を使う」をオンにした場合に限り、キーボードはシステムの仕組みを通じて連絡先の名前を候補として読み込みます。電話番号などの情報は読み取らず、送信もしません。

## 5. 第三者のサービス

本アプリには、第三者の分析・広告・クラッシュレポートのツールは組み込まれていません。AI 機能で使うモデルサービスはお客様が選択・設定するもので、そのサービスの利用規約とプライバシーポリシーが適用されます。購入は Apple の App Store が処理し、Apple のプライバシーポリシーが適用されます。

## 6. お客様の権利

- **同意の撤回：**「設定 › プライバシー」からいつでも撤回できます。撤回後は、次回の送信前にあらためて同意をお願いします。
- **情報の削除：** 端末に保存された整えた履歴と入力の学習データはいつでも消去できます。
- **権限の無効化：** システムの設定で「フルアクセスを許可」をいつでもオフにできます。

## 7. 未成年の方

本アプリは 14 歳未満の方を対象としていません。未成年の方は保護者の指導のもとでご利用ください。

## 8. 本ポリシーの変更

本ポリシーは必要に応じて改定することがあります。改定後のポリシーは本アプリ内で公開し、施行日を更新します。情報の取り扱いに重要な変更がある場合は、本アプリ内でわかりやすくお知らせします。

## 9. お問い合わせ

メール：{email}

お問い合わせには 15 営業日以内に回答します。
"""
}

/// 上架前填写：App Store 上显示的开发者名称、对外联系邮箱。
enum LegalInfo {
    static let developer = "［开发者名称］"
    static let email = "［联系邮箱］"
}
