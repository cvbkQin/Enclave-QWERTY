import Foundation
import UIKit
import UniformTypeIdentifiers

// 备份与恢复第一步（B3，对齐清单第 55 条，设计 design/backup/v2/BV0、BV2–BV4、design/backup/BK1、BK7）：
// 本地导出成 .enclave 文件、从文件恢复；iCloud 同步是第二步。
// 备份文件是 zip 包：manifest.json（格式版本、App 版本、设备、导出时间、各项数量）和每项一个文件；只有 Key 加密。
// 永远不备份：剪贴板记录、购买状态、试用日期、统计和诊断记录、下载的词库文件。

/// 「备份内容」里的几项（Key 不在这里，导出时单独选）。
enum BackupItem: String, CaseIterable, Codable, Identifiable {
    case settings, styles, commonWords, learnedWords, history

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .settings: return "settings.json"
        case .styles: return "styles.json"
        case .commonWords: return "common-words.json"
        case .learnedWords: return "learned-words.txt"
        case .history: return "ai-history.json"
        }
    }

    var title: String {
        switch self {
        case .settings: return L("设置", "Settings", "設定")
        case .styles: return L("润色风格 · 问答风格", "Polish · Answer styles", "整える・回答スタイル")
        case .commonWords: return L("常用词", "My words", "ユーザ辞書")
        case .learnedWords: return L("学到的词", "Learned words", "学習した語")
        case .history: return L("AI 历史", "AI history", "AI 履歴")
        }
    }

    var detail: String? {
        switch self {
        case .settings: return L("键盘、AI 接口（不含 Key）、通用", "Keyboard, AI API (no keys), General", "キーボード・AI API（キーなし）・一般")
        case .learnedWords: return L("打字时记住的词和顺序", "Words and order remembered as you type", "入力で覚えた語と順番")
        case .history: return L("原文和结果都在里面", "Includes your text and the results", "原文と結果を含みます")
        default: return nil
        }
    }

    /// AI 历史默认不带，其他默认带。
    static let defaultOn: Set<BackupItem> = [.settings, .styles, .commonWords, .learnedWords]
}

/// 备份页记住的东西：备份内容选了哪几项、上次导出的时间和位置。
enum BackupPrefs {
    private static let itemsKey = "backup.items"
    private static let lastExportKey = "backup.lastExport"
    private static let lastPlaceKey = "backup.lastExportPlace"

    static var items: Set<BackupItem> {
        get {
            guard let raw = SharedStorage.defaults.stringArray(forKey: itemsKey) else { return BackupItem.defaultOn }
            return Set(raw.compactMap(BackupItem.init(rawValue:)))
        }
        set { SharedStorage.defaults.set(newValue.map(\.rawValue).sorted(), forKey: itemsKey) }
    }

    static var lastExport: Date? {
        get { SharedStorage.defaults.object(forKey: lastExportKey) as? Date }
        set { SharedStorage.defaults.set(newValue, forKey: lastExportKey) }
    }

    /// 存到哪里：「文件」、隔空投送……认不出来时为 nil。
    static var lastExportPlace: String? {
        get { SharedStorage.defaults.string(forKey: lastPlaceKey) }
        set { SharedStorage.defaults.set(newValue, forKey: lastPlaceKey) }
    }
}

struct BackupManifest: Codable {
    struct KeyInfo: Codable {
        var count: Int
        var salt: String
        var iterations: Int
    }

    static let currentFormat = 1

    var format = BackupManifest.currentFormat
    var app: String
    var device: String
    var exportedAt: Date
    /// 每项的数量（BackupItem.rawValue → 数量；风格写 polishStyles、answerStyles 两项）。
    var counts: [String: Int]
    var items: [String]
    var keys: KeyInfo?
}

/// 各项现在有多少（备份页右边的数字、导出摘要）。
struct BackupCounts: Equatable {
    var polishStyles = 0
    var answerStyles = 0
    var commonWords = 0
    /// 要问拼音引擎，算好之前是 nil。
    var learnedWords: Int?
    var history = 0

    var styles: Int { polishStyles + answerStyles }

    static func current() -> BackupCounts {
        let settings = SettingsStore.load()
        return BackupCounts(polishStyles: settings.styles.count, answerStyles: settings.answerStyles.count,
                            commonWords: CommonWordStore.load().count, learnedWords: nil, history: AIHistory.load().count)
    }
}

/// 打开的备份文件：读出来、校验过，还没恢复。
struct BackupFile {
    var name: String
    var manifest: BackupManifest
    var files: [String: Data]

    /// 文件里实际有的项目，按页面顺序。
    var items: [BackupItem] { BackupItem.allCases.filter { manifest.items.contains($0.rawValue) && files[$0.fileName] != nil } }
    var keyCount: Int { files[BackupService.keysFile] == nil ? 0 : manifest.keys?.count ?? 0 }

    func count(_ item: BackupItem) -> Int? {
        item == .styles ? nil : manifest.counts[item.rawValue]
    }

    var polishStyles: Int { manifest.counts["polishStyles"] ?? 0 }
    var answerStyles: Int { manifest.counts["answerStyles"] ?? 0 }
}

/// 恢复完的结果（BK7）：每一行右边写什么。
struct BackupReport {
    struct Row: Identifiable {
        var id: String { title }
        var title: String
        var value: String
    }

    var rows: [Row] = []
    var keysRestored: Bool?
}

enum BackupError: LocalizedError {
    case notBackup, tooNew, damaged, wrongPassword, learnedWords, learnedWordsBusy, noAppGroup

    var errorDescription: String? {
        switch self {
        case .notBackup: return L("这不是飞地输入法的备份文件。", "This isn't an Enclave backup file.", "Enclave のバックアップファイルではありません。")
        case .tooNew: return L("这个备份来自更新版本的飞地输入法，请先更新 App。", "This backup is from a newer version of Enclave. Update the app first.", "新しいバージョンの Enclave で作られたバックアップです。先にアプリを更新してください。")
        case .damaged: return L("文件损坏了，读不出来。", "The file is damaged and can't be read.", "ファイルが壊れていて読み込めません。")
        case .wrongPassword: return L("密码不对", "Wrong password", "パスワードが違います")
        case .learnedWords: return L("拼音词库这会儿打不开，学到的词没能读写。稍后再试一次。", "Couldn't open the pinyin dictionary, so learned words couldn't be read or written. Try again later.", "ピンイン辞書を開けず、学習した語を読み書きできませんでした。あとでもう一度お試しください。")
        case .learnedWordsBusy: return L("键盘还在用拼音词库，学到的词这会儿读写不了。先把键盘收起来（离开正在打字的地方），再试一次。", "The keyboard is still using the pinyin dictionary, so learned words can't be read or written right now. Close the keyboard and try again.", "キーボードがピンイン辞書を使用中のため、学習した語を今は読み書きできません。キーボードを閉じてからもう一度お試しください。")
        case .noAppGroup: return L("App 和键盘的共享存储没有生效，读写不了键盘的数据。", "Shared storage between the app and keyboard isn't working.", "アプリとキーボードの共有ストレージが有効ではありません。")
        }
    }
}

enum BackupService {
    static let fileExtension = "enclave"
    static let manifestFile = "manifest.json"
    static let keysFile = "keys.enc"

    /// 在 Info.plist 里注册的文件类型（UTExportedTypeDeclarations），id 跟着 App 的 Bundle ID 走。
    static var contentType: UTType {
        let id = (Bundle.main.bundleIdentifier ?? "com.example.enclave") + ".backup"
        return UTType(id) ?? UTType(filenameExtension: fileExtension, conformingTo: .data) ?? .data
    }

    /// 设置一项里除了 EnclaveSettings 还带上的开关（都在 App Group 的 UserDefaults 里）。
    /// 不带：购买、试用、次数、统计、诊断、隐私同意、引导看过没有、剪贴板、下载的词库。
    static let settingsDefaultsKeys = [
        "prediction.enabled", "prediction.english", "prediction.spaceChain", "emojiSuggestions.enabled",
        "correction.qwerty", "correction.nineKey", "touch.calibration.enabled", "pick.autoClose",
        "history.enabled", "history.retentionDays", "appLanguage",
        "commonWords.useTextReplacement", "commonWords.useContacts", "grammar.enabled",
    ]

    /// 钥匙串里的 Key：润色、问答、「我的预设」每条一个。
    static func keyAccounts(savedAPIs: [SavedAPI] = SavedAPIStore.all) -> [String] {
        ["apiKey", "apiKey.answer"] + savedAPIs.map { "apiKey.saved.\($0.id.uuidString)" }
    }

    /// 现在钥匙串里有的 Key（导出面板副标题用：「润色 DeepSeek · 问答 Kimi」）。
    static func keySummary(settings: EnclaveSettings) -> (count: Int, text: String) {
        var parts: [String] = []
        if let key = SettingsStore.apiKey, !key.isEmpty {
            parts.append(L("润色", "Polish", "整える") + " " + ProviderName.of(settings.baseURL))
        }
        if let key = SettingsStore.answerApiKey, !key.isEmpty, settings.usesAnswerEndpoint {
            parts.append(L("问答", "Answer", "回答") + " " + ProviderName.of(settings.answerBaseURL))
        }
        let saved = SavedAPIStore.all.filter { ($0.apiKey ?? "").isEmpty == false }.count
        if saved > 0 { parts.append(L("我的预设 \(saved) 个", "\(saved) saved", "保存済み \(saved) 件")) }
        let count = keyAccounts().filter { !(Keychain.get($0) ?? "").isEmpty }.count
        return (count, parts.joined(separator: " · "))
    }

    // MARK: - 导出

    /// 做一个备份文件，写到临时目录，返回文件地址（系统分享面板用）。在后台线程调（学到的词、Key 加密都要一会儿）。
    static func export(items: Set<BackupItem>, keysPassword: String?, origin: Origin) throws -> URL {
        let data = try makeArchive(items: items, keysPassword: keysPassword, origin: origin)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("backup-export", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(defaultFileName())
        try data.write(to: url, options: .atomic)
        return url
    }

    static func defaultFileName(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return L("飞地输入法备份", "Enclave Backup", "Enclave バックアップ") + " " + formatter.string(from: date) + "." + fileExtension
    }

    /// 写进 manifest 的 App 版本和设备名：在主线程取好再传进来（导出、恢复都在后台线程做）。
    struct Origin {
        var app: String
        var device: String

        @MainActor static func current() -> Origin {
            Origin(app: AboutView.devLabel ?? AboutView.version, device: UIDevice.current.name)
        }
    }

    static func makeArchive(items: Set<BackupItem>, keysPassword: String?, origin: Origin) throws -> Data {
        var files: [(name: String, data: Data)] = []
        var counts: [String: Int] = [:]
        let settings = SettingsStore.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970

        for item in BackupItem.allCases where items.contains(item) {
            switch item {
            case .settings:
                var defaults: [String: Any] = [:]
                for key in settingsDefaultsKeys {
                    if let value = SharedStorage.defaults.object(forKey: key), JSONSerialization.isValidJSONObject([value]) {
                        defaults[key] = value
                    }
                }
                let saved = try JSONSerialization.jsonObject(with: encoder.encode(SavedAPIStore.all))
                let object: [String: Any] = ["settings": try BackupMerge.settingsObject(settings), "defaults": defaults, "savedAPIs": saved]
                files.append((item.fileName, try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])))
                counts[item.rawValue] = 1
            case .styles:
                let styles = StylesFile(polish: BackupMerge.Styles(list: settings.styles, selectedID: settings.selectedStyleID),
                                        answer: BackupMerge.Styles(list: settings.answerStyles, selectedID: settings.selectedAnswerStyleID))
                files.append((item.fileName, try encoder.encode(styles)))
                counts["polishStyles"] = settings.styles.count
                counts["answerStyles"] = settings.answerStyles.count
            case .commonWords:
                let words = CommonWordsFile(words: CommonWordStore.load(), keyboardTexts: CommonWordStore.keyboardTexts)
                files.append((item.fileName, try encoder.encode(words)))
                counts[item.rawValue] = words.words.count
            case .learnedWords:
                guard !LearnedWords.isBusy else { throw BackupError.learnedWordsBusy }
                guard let snapshot = LearnedWords.snapshot() else { throw BackupError.learnedWords }
                files.append((item.fileName, Data(snapshot.utf8)))
                counts[item.rawValue] = BackupMerge.learnedCount(snapshot)
            case .history:
                let entries = AIHistory.load()
                files.append((item.fileName, try encoder.encode(entries)))
                counts[item.rawValue] = entries.count
            }
        }

        var keyInfo: BackupManifest.KeyInfo?
        if let password = keysPassword, !password.isEmpty {
            var keys: [String: String] = [:]
            for account in keyAccounts() {
                if let value = Keychain.get(account), !value.isEmpty { keys[account] = value }
            }
            if !keys.isEmpty, let sealed = BackupCrypto.seal(try JSONEncoder().encode(keys), password: password) {
                files.append((keysFile, sealed.data))
                keyInfo = .init(count: keys.count, salt: sealed.salt.base64EncodedString(), iterations: sealed.iterations)
            }
        }

        let manifest = BackupManifest(app: origin.app, device: origin.device,
                                      exportedAt: Date(), counts: counts,
                                      items: BackupItem.allCases.filter { items.contains($0) }.map(\.rawValue), keys: keyInfo)
        files.insert((manifestFile, try encoder.encode(manifest)), at: 0)
        return BackupArchive.write(files)
    }

    // MARK: - 打开

    static func open(_ data: Data, name: String) throws -> BackupFile {
        guard let files = try? BackupArchive.read(data) else { throw BackupError.notBackup }
        guard let manifestData = files[manifestFile] else { throw BackupError.notBackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let manifest = try? decoder.decode(BackupManifest.self, from: manifestData) else { throw BackupError.damaged }
        guard manifest.format <= BackupManifest.currentFormat else { throw BackupError.tooNew }
        let title = (name as NSString).deletingPathExtension
        return BackupFile(name: title, manifest: manifest, files: files)
    }

    /// 试一下密码对不对（恢复前）。
    static func decryptKeys(_ file: BackupFile, password: String) -> [String: String]? {
        guard let info = file.manifest.keys, let data = file.files[keysFile], let salt = Data(base64Encoded: info.salt),
              let plain = BackupCrypto.open(.init(data: data, salt: salt, iterations: info.iterations), password: password)
        else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: plain)
    }

    // MARK: - 恢复

    /// 恢复选中的几项（BV4）。先把要用的内容全部读出来、校验过，再动现有数据；动之前在 App Group 里留一份当前数据的备份，
    /// 学到的词合并失败时用它退回去。在后台线程调。
    static func restore(_ file: BackupFile, items: Set<BackupItem>, keysPassword: String?, mode: BackupMerge.Mode, origin: Origin) throws -> (BackupReport, RestoredState) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        func data(_ item: BackupItem) throws -> Data {
            guard let data = file.files[item.fileName] else { throw BackupError.damaged }
            return data
        }

        // 1. 全部读出来。
        var settingsObject: [String: Any]?
        if items.contains(.settings) {
            guard let object = try JSONSerialization.jsonObject(with: data(.settings)) as? [String: Any] else { throw BackupError.damaged }
            settingsObject = object
        }
        let styles = items.contains(.styles) ? try decoder.decode(StylesFile.self, from: data(.styles)) : nil
        let words = items.contains(.commonWords) ? try decoder.decode(CommonWordsFile.self, from: data(.commonWords)) : nil
        let learned = items.contains(.learnedWords) ? String(decoding: try data(.learnedWords), as: UTF8.self) : nil
        let history = items.contains(.history) ? try decoder.decode([AIHistoryEntry].self, from: data(.history)) : nil
        // 键盘还开着词库：什么都先别动。
        if learned != nil, LearnedWords.isBusy { throw BackupError.learnedWordsBusy }
        var keys: [String: String]?
        if let password = keysPassword {
            guard let decrypted = decryptKeys(file, password: password) else { throw BackupError.wrongPassword }
            keys = decrypted
        }

        // 2. 留一份当前数据（不含 Key），出问题时能找回来。
        if let folder = safetyFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let all = Set(BackupItem.allCases).subtracting(learned == nil ? [.learnedWords] : [])
            if let archive = try? makeArchive(items: all, keysPassword: nil, origin: origin) {
                let stamp = Int(Date().timeIntervalSince1970)
                try? archive.write(to: folder.appendingPathComponent("before-restore-\(stamp).\(fileExtension)"), options: .atomic)
            }
            // 只留最近 3 份。
            let fm = FileManager.default
            let old = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("before-restore-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .dropFirst(3)
            for url in old { try? fm.removeItem(at: url) }
        }

        var report = BackupReport()
        var state = RestoredState()

        // 3. 学到的词先做：交给拼音引擎合并，失败了别的都还没动。
        if let learned {
            let before = LearnedWords.snapshot()
            let beforeCount = before.map(BackupMerge.learnedCount) ?? 0
            guard LearnedWords.importSnapshot(learned, replace: mode == .replace), let after = LearnedWords.snapshot() else {
                // 替换时已经清空了：用刚才的快照退回去。
                if mode == .replace, let before { _ = LearnedWords.importSnapshot(before, replace: true) }
                throw LearnedWords.isBusy ? BackupError.learnedWordsBusy : BackupError.learnedWords
            }
            // 备份里有词、合并完一个都没有：词库其实没打开（同步照样返回成功）。
            if BackupMerge.learnedCount(learned) > 0, BackupMerge.learnedCount(after) == 0 {
                if mode == .replace, let before { _ = LearnedWords.importSnapshot(before, replace: true) }
                throw BackupError.learnedWords
            }
            let delta = BackupMerge.learnedCount(after) - (mode == .replace ? 0 : beforeCount)
            report.rows.append(.init(title: BackupItem.learnedWords.title,
                                     value: L("+\(max(0, delta)) 个", "+\(max(0, delta))", "+\(max(0, delta)) 語")))
        }

        // 4. 设置：总是直接用备份里的。
        var settings = SettingsStore.load()
        if let settingsObject {
            if let object = settingsObject["settings"] as? [String: Any] {
                settings = try BackupMerge.restoreSettings(object, keepingStylesOf: settings)
            }
            if let defaults = settingsObject["defaults"] as? [String: Any] {
                for key in settingsDefaultsKeys {
                    if let value = defaults[key] { SharedStorage.defaults.set(value, forKey: key) } else { SharedStorage.defaults.removeObject(forKey: key) }
                }
            }
            if let saved = settingsObject["savedAPIs"],
               let list = try? decoder.decode([SavedAPI].self, from: JSONSerialization.data(withJSONObject: saved)) {
                let kept = Set(list.map(\.id))
                for old in SavedAPIStore.all where !kept.contains(old.id) { old.apiKey = nil }
                SavedAPIStore.replaceAll(list)
            }
            report.rows.append(.init(title: BackupItem.settings.title, value: L("已更新", "Updated", "更新しました")))
            state.settingsChanged = true
        }

        // 5. 风格。
        if let styles {
            let polish = BackupMerge.styles(current: .init(list: settings.styles, selectedID: settings.selectedStyleID), backup: styles.polish, mode: mode)
            let answer = BackupMerge.styles(current: .init(list: settings.answerStyles, selectedID: settings.selectedAnswerStyleID), backup: styles.answer, mode: mode)
            settings.styles = polish.styles.list
            settings.selectedStyleID = polish.styles.selectedID
            settings.answerStyles = answer.styles.list
            settings.selectedAnswerStyleID = answer.styles.selectedID
            report.rows.append(.init(title: L("润色风格", "Polish styles", "整えるスタイル"), value: L("+\(polish.added) 条", "+\(polish.added)", "+\(polish.added) 件")))
            report.rows.append(.init(title: L("问答风格", "Answer styles", "回答スタイル"), value: L("+\(answer.added) 条", "+\(answer.added)", "+\(answer.added) 件")))
            state.settingsChanged = true
        }
        if state.settingsChanged { SettingsStore.save(settings) }
        state.settings = settings

        // 6. 常用词和键盘常用语。
        if let words {
            let result = BackupMerge.commonWords(current: CommonWordStore.load(), backup: words.words, mode: mode)
            CommonWordStore.save(result.words)
            CommonWordStore.keyboardTexts = BackupMerge.keyboardTexts(current: CommonWordStore.keyboardTexts, backup: words.keyboardTexts, mode: mode)
            let value = result.existing > 0
                ? L("+\(result.added) 个，\(result.existing) 个已有", "+\(result.added), \(result.existing) already here", "+\(result.added) 語、\(result.existing) 語は登録済み")
                : L("+\(result.added) 个", "+\(result.added)", "+\(result.added) 語")
            report.rows.append(.init(title: BackupItem.commonWords.title, value: value))
        }

        // 7. AI 历史。
        if let history {
            let result = BackupMerge.history(current: AIHistory.load(), backup: history, mode: mode)
            AIHistory.replaceAll(result.entries)
            report.rows.append(.init(title: BackupItem.history.title, value: L("+\(result.added) 条", "+\(result.added)", "+\(result.added) 件")))
        }

        // 8. Key：「我的预设」的 Key 只给现在还在的那几条。
        if file.keyCount > 0 {
            if let keys {
                let accounts = Set(keyAccounts())
                var restored = 0
                for (account, value) in keys where accounts.contains(account) {
                    if Keychain.set(value, for: account) { restored += 1 }
                }
                state.keysChanged = restored > 0
                report.rows.append(.init(title: L("接口 Key", "API keys", "API キー"), value: L("已恢复 \(restored) 个", "\(restored) restored", "\(restored) 件復元")))
                report.keysRestored = true
            } else {
                report.rows.append(.init(title: L("接口 Key", "API keys", "API キー"), value: L("没有恢复", "Not restored", "復元していません")))
                report.keysRestored = false
            }
        }
        return (report, state)
    }

    /// 恢复前自动留的那份：App Group 里的 Backup/。
    static var safetyFolder: URL? {
        guard SharedStorage.isShared, let id = SharedStorage.appGroupID,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return container.appendingPathComponent("Backup", isDirectory: true)
    }

    /// 恢复完 App 这边要跟着更新的东西（AppStore 里的设置、Key）。
    struct RestoredState {
        var settingsChanged = false
        var keysChanged = false
        var settings: EnclaveSettings?
    }

    struct StylesFile: Codable {
        var polish: BackupMerge.Styles
        var answer: BackupMerge.Styles
    }

    struct CommonWordsFile: Codable {
        var words: [CommonWord]
        var keyboardTexts: [String]
    }
}

/// 学到的词（拼音学习记录，librime 的用户词库 enclave.userdb）：借 librime 的同步功能导出、导入。
/// 同步目录（用户目录下 sync/）每次用前清空、用完删掉，只放这一次要合并的快照：
/// 留着旧快照的话，下次同步会把删掉的词又合并回来。
enum LearnedWords {
    static let dictName = "enclave"
    private static let lock = NSLock()

    private static var paths: RimeStore.Paths? {
        guard let paths = RimeStore.paths, RimeStore.isDeployed else { return nil }
        return paths
    }

    private static func userdb(_ paths: RimeStore.Paths) -> URL {
        paths.user.appendingPathComponent("\(dictName).userdb", isDirectory: true)
    }

    /// 键盘正开着会话、拿着用户词库的锁。这时 librime 打不开库，同步还是返回成功，只是导出空的、合并不进去，所以先查。
    static var isBusy: Bool {
        guard let paths else { return false }
        let lockFile = userdb(paths).appendingPathComponent("LOCK")
        return FileManager.default.fileExists(atPath: lockFile.path) && enclave_userdb_locked(lockFile.path)
    }

    /// 导出当前学到的词（*.userdb.txt 的文本）；没打过字是空字符串，引擎打不开（包括键盘占着）时为 nil。
    static func snapshot() -> String? {
        guard let paths, !isBusy else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let sync = paths.user.appendingPathComponent("sync", isDirectory: true)
        let fm = FileManager.default
        try? fm.removeItem(at: sync)
        defer { try? fm.removeItem(at: sync) }
        guard RimeStore.withAppEngine({ enclave_rime_sync_user_data(paths.shared.path, paths.user.path, nil, nil) }) else { return nil }
        guard let found = fm.enumerator(at: sync, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == "\(dictName).userdb.txt" }) else {
            // 没打过字（没有用户词库）是空的；有词库却没导出来，说明没打开。
            return fm.fileExists(atPath: userdb(paths).path) ? nil : ""
        }
        return try? String(contentsOf: found, encoding: .utf8)
    }

    /// 把备份里的快照合并进来（两边都有的词取权重大的）；replace 时先清空现有的。
    static func importSnapshot(_ text: String, replace: Bool) -> Bool {
        // 键盘占着时连清空都不能做。
        guard let paths, !isBusy else { return false }
        lock.lock()
        defer { lock.unlock() }
        if replace { RimeStore.clearLearning() }
        let fm = FileManager.default
        let sync = paths.user.appendingPathComponent("sync", isDirectory: true)
        try? fm.removeItem(at: sync)
        defer { try? fm.removeItem(at: sync) }
        let folder = sync.appendingPathComponent("backup", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.write(to: folder.appendingPathComponent("\(dictName).userdb.txt"), atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        return RimeStore.withAppEngine {
            enclave_rime_sync_user_data(paths.shared.path, paths.user.path, nil, RimeStore.schemaID)
        }
    }
}

extension RimeStore {
    /// App 里用拼音引擎（部署、备份时导出导入学到的词）一次只做一件：librime 在一个进程里只有一份。
    private static let appEngineLock = NSLock()

    static func withAppEngine<T>(_ body: () -> T) -> T {
        appEngineLock.lock()
        defer { appEngineLock.unlock() }
        return body()
    }
}
