import UIKit

/// 键盘里要去飞地输入法 App 设置的地方。键盘扩展不能打开别的 App（审核指南 4.4.1），只提示去 App 的哪一页（05 上架风险报告高 1）。
/// 路径照 App 的标签和页面名写：「接口和提示词」标签里分「接口」「提示词」两段，隐私政策在「设置 › 隐私」里。
/// iPad 上 App 是六个标签（PA1），「接口」「提示词」各是一个标签，路径照 iPad 的写（PK12 ③）。
enum AppPlace: Equatable {
    /// 出错卡「去设置」：接口地址、模型、Key。
    case api
    /// 问答要联网但联网被禁止时的「去开启」：接口页下面的联网搜索。
    case webSearch
    /// 风格菜单最后一行「添加润色风格 / 问答风格」。
    case prompts
    /// 首次发送同意卡上的「隐私政策」。
    case privacyPolicy

    var path: String {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        switch self {
        case .api:
            return pad ? L("接口", "API", "API") : L("接口和提示词 › 接口", "API & Prompts › API", "API とプロンプト › API")
        case .webSearch:
            return pad ? L("接口 › 联网搜索", "API › Web search", "API › ウェブ検索")
                : L("接口和提示词 › 接口 › 联网搜索", "API & Prompts › API › Web search", "API とプロンプト › API › ウェブ検索")
        case .prompts:
            return pad ? L("提示词", "Prompts", "プロンプト") : L("接口和提示词 › 提示词", "API & Prompts › Prompts", "API とプロンプト › プロンプト")
        case .privacyPolicy: return L("设置 › 隐私 › 隐私政策", "Settings › Privacy › Privacy Policy", "設定 › プライバシー › プライバシーポリシー")
        }
    }

    /// 键盘顶上那条提示。
    var hint: String {
        L("打开飞地输入法 App，进入「\(path)」", "Open the Enclave app and go to \(path)", "Enclave アプリを開いて「\(path)」へ")
    }
}
