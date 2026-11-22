import Foundation

/// 界面语言：跟随 iPhone / 简体中文 / English / 日本語，在 App 设置里选，马上生效。
/// 键盘开了完全访问时读 App Group 里的选择，没开时跟随 iPhone。拼音按键、用户写的内容和 AI 输出不翻。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en, ja

    var id: Self { self }

    /// 语言名永远用各自的语言写。
    var nativeName: String {
        switch self {
        case .system: return L("跟随 iPhone", "Use iPhone Language", "iPhone の言語に合わせる")
        case .zh: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}

enum Loc {
    private static let key = "appLanguage"

    static var setting: AppLanguage {
        get { AppLanguage(rawValue: SharedStorage.defaults.string(forKey: key) ?? "") ?? .system }
        set { SharedStorage.defaults.set(newValue.rawValue, forKey: key) }
    }

    /// 键盘没开完全访问时设为 true，只看 iPhone 的语言。
    static var followSystemOnly = false

    /// 实际用的语言：跟随 iPhone 时系统是中文用中文、日文用日文，其他用英文。
    static var current: AppLanguage {
        let chosen = followSystemOnly ? .system : setting
        if chosen != .system { return chosen }
        return system
    }

    static var system: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "zh"
        if preferred.hasPrefix("zh") { return .zh }
        if preferred.hasPrefix("ja") { return .ja }
        return .en
    }

    /// 日期、价格等格式化用的地区。
    static var locale: Locale {
        switch current {
        case .zh, .system: return Locale(identifier: "zh_CN")
        case .en: return Locale(identifier: "en_US")
        case .ja: return Locale(identifier: "ja_JP")
        }
    }

    /// 「11 月 3 日」/「Nov 3」/「11月3日」。
    static func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

/// 三种语言的文字写在一起，按当前语言取一个。术语按 design/keyboard/v3/英文对照表.md。
func L(_ zh: String, _ en: String, _ ja: String) -> String {
    switch Loc.current {
    case .en: return en
    case .ja: return ja
    case .zh, .system: return zh
    }
}

extension Loc {
    /// 系统设置里显示的 App 名和键盘名（02 定，11-22，对齐清单第 84 条）：按 iPhone 的语言挑 InfoPlist.strings 里的
    /// CFBundleDisplayName（中文「飞地输入法」，英文、日文「Enclave」），和系统设置里看到的一样，不跟 App 里选的语言。
    /// 只用在带用户去系统设置的文字和插图里；路径里的其他词照旧跟 App 语言（L）。App 自己界面里的品牌名不用它。
    /// App 和键盘扩展的 InfoPlist.strings 写的是同一个名字，在哪边调用都一样。
    static var nameInSettings: String {
        let bundle = Bundle.main
        let localization = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: Locale.preferredLanguages).first
        if let localization,
           let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: localization),
           let strings = NSDictionary(contentsOfFile: path), let name = strings["CFBundleDisplayName"] as? String, !name.isEmpty {
            return name
        }
        return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Enclave"
    }
}
