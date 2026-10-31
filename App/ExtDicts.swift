import CryptoKit
import Foundation
import StoreKit
import SwiftUI

/// 扩展词库（B6）：内置、从在线词库下载、从文件导入三种放在「我的词库」一起管。
/// 内置的随 App 带（Configs/ExtDicts），下载和导入的放 App Group 的 Rime/ext_dicts/。
/// 部署时把打开的词库拷进共享副本、加进 import_tables（见 RimeDeployer）；装、删、开关都重新部署。
enum ExtDict {
    enum Kind: String, Codable {
        case builtin, downloaded, imported
    }

    /// 来源和许可：决定署名文字。
    enum License: String, Codable {
        /// 飞地自己整理的游戏、流行语。
        case own
        /// THUOCL 清华大学开放中文词库，MIT。
        case thuocl
        /// 维基百科词条整理（fcitx5-pinyin-zhwiki），CC BY-SA 4.0。
        case wiki
    }

    /// 下载和导入的词库记在这里；内置的只记关掉和删掉了哪些（升级 App 后保持原状，新加的内置默认打开）。
    struct Installed: Codable, Identifiable, Equatable {
        var id: String
        var kind: Kind
        var name: String
        var entries: Int
        var size: Int64
        /// 在线词库的版本日期（yyyy-MM-dd）；导入的写导入时间。
        var version: String
        var license: License?
        /// 导入时的原文件名。
        var fileName: String?
        var addedAt: Date
    }

    /// 随 App 带的词库。词条数和版本读 builtin.json（scripts/build-ext-dicts.py 生成）。
    struct Builtin: Identifiable {
        let id: String
        let name: String
        let category: String
        let blurb: String
        let license: License
    }

    static var builtins: [Builtin] {
        let game = L("游戏", "Game", "ゲーム")
        let gameBlurb = L("英雄、角色、装备、技能名。随 App 更新，不用单独下载。", "Heroes, characters, items and skills. Updated with the app; no separate download.", "ヒーロー、キャラクター、装備、スキル名。アプリと一緒に更新され、別途ダウンロードは不要です。")
        return [
            Builtin(id: "lol", name: L("英雄联盟", "League of Legends", "リーグ・オブ・レジェンド"), category: game, blurb: gameBlurb, license: .own),
            Builtin(id: "wzry", name: L("王者荣耀", "Honor of Kings", "王者栄耀"), category: game, blurb: gameBlurb, license: .own),
            Builtin(id: "genshin", name: L("原神", "Genshin Impact", "原神"), category: game, blurb: gameBlurb, license: .own),
            Builtin(id: "dota2", name: "Dota 2", category: game, blurb: gameBlurb, license: .own),
            Builtin(id: "hpjy", name: L("和平精英", "Peacekeeper Elite", "和平精英"), category: game, blurb: gameBlurb, license: .own),
            Builtin(id: "meme", name: L("网络流行语", "Internet slang", "ネット流行語"), category: "",
                    blurb: L("近年的网络流行语。随 App 更新，不用单独下载。", "Recent internet slang. Updated with the app; no separate download.", "最近のネット流行語。アプリと一緒に更新され、別途ダウンロードは不要です。"), license: .own),
            Builtin(id: "chengyu", name: L("成语", "Idioms", "成語"), category: "THUOCL",
                    blurb: L("常用成语。随 App 更新，不用单独下载。", "Common four-character idioms. Updated with the app; no separate download.", "よく使う成語。アプリと一緒に更新され、別途ダウンロードは不要です。"), license: .thuocl),
            Builtin(id: "diming", name: L("地名", "Place names", "地名"), category: "THUOCL",
                    blurb: L("省市区县、乡镇、景点。随 App 更新，不用单独下载。", "Provinces, cities, counties, towns and sights. Updated with the app; no separate download.", "省・市・県、町村、観光地。アプリと一緒に更新され、別途ダウンロードは不要です。"), license: .thuocl),
            Builtin(id: "it", name: "IT", category: "THUOCL",
                    blurb: L("互联网、软件、硬件术语。随 App 更新，不用单独下载。", "Internet, software and hardware terms. Updated with the app; no separate download.", "インターネット、ソフトウェア、ハードウェアの用語。アプリと一緒に更新され、別途ダウンロードは不要です。"), license: .thuocl),
            Builtin(id: "caijing", name: L("财经", "Finance", "財経"), category: "THUOCL",
                    blurb: L("金融、经济、公司术语。随 App 更新，不用单独下载。", "Finance, economics and business terms. Updated with the app; no separate download.", "金融、経済、企業の用語。アプリと一緒に更新され、別途ダウンロードは不要です。"), license: .thuocl),
        ]
    }

    struct BuiltinManifest: Decodable {
        struct Item: Decodable {
            let id: String
            let entries: Int
            let version: String
            let size: Int64
        }
        let dicts: [Item]
    }

    static let builtinFolder = Bundle.main.url(forResource: "ExtDicts", withExtension: nil)

    static let builtinManifest: [String: BuiltinManifest.Item] = {
        guard let url = builtinFolder?.appendingPathComponent("builtin.json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(BuiltinManifest.self, from: data) else { return [:] }
        return Dictionary(manifest.dicts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }()

    /// 有文件的内置词库（builtin.json 里有的才算）。
    static var availableBuiltins: [Builtin] {
        builtins.filter { builtinManifest[$0.id] != nil }
    }

    // MARK: - 存储（App Group defaults，部署时也要读）

    private static let installedKey = "extDicts.installed"
    private static let offKey = "extDicts.off"
    private static let removedKey = "extDicts.removedBuiltins"

    static var installed: [Installed] {
        get {
            guard let data = SharedStorage.defaults.data(forKey: installedKey) else { return [] }
            return (try? JSONDecoder().decode([Installed].self, from: data)) ?? []
        }
        set { SharedStorage.defaults.set(try? JSONEncoder().encode(newValue), forKey: installedKey) }
    }

    static var off: Set<String> {
        get { Set(SharedStorage.defaults.stringArray(forKey: offKey) ?? []) }
        set { SharedStorage.defaults.set(newValue.sorted(), forKey: offKey) }
    }

    static var removedBuiltins: Set<String> {
        get { Set(SharedStorage.defaults.stringArray(forKey: removedKey) ?? []) }
        set { SharedStorage.defaults.set(newValue.sorted(), forKey: removedKey) }
    }

    /// 下载、导入的词库文件夹：Rime/ext_dicts/（共享副本每次部署整份替换，所以不放 shared 里）。
    static var folder: URL? {
        RimeStore.paths?.shared.deletingLastPathComponent().appendingPathComponent("ext_dicts", isDirectory: true)
    }

    static func fileURL(id: String, kind: Kind) -> URL? {
        let name = "ext_\(id).dict.yaml"
        return kind == .builtin ? builtinFolder?.appendingPathComponent(name) : folder?.appendingPathComponent(name)
    }

    /// 部署时要接进去的词库：打开着、文件在的。
    static var active: [(id: String, version: String, url: URL)] {
        let off = off
        let removed = removedBuiltins
        var list: [(String, String, URL)] = []
        for item in installed where !off.contains(item.id) {
            if let url = fileURL(id: item.id, kind: item.kind), FileManager.default.fileExists(atPath: url.path) {
                list.append((item.id, item.version + "@" + String(Int(item.addedAt.timeIntervalSince1970)), url))
            }
        }
        for builtin in availableBuiltins where !off.contains(builtin.id) && !removed.contains(builtin.id) {
            if let url = fileURL(id: builtin.id, kind: .builtin), let manifest = builtinManifest[builtin.id] {
                list.append((builtin.id, manifest.version, url))
            }
        }
        return list
    }

    /// 写进已部署版本号的后缀：装、删、开关、内置词库随 App 更新，都会变，触发重新部署。
    static func versionTag(_ active: [(id: String, version: String, url: URL)]) -> String {
        active.isEmpty ? "" : "+ext:" + active.map { "\($0.id)@\($0.version)" }.sorted().joined(separator: ",")
    }

    /// 打开着的扩展词库一共多少词（首页「扩展 N」、组标题用）。
    static var activeCount: Int {
        let off = off
        let removed = removedBuiltins
        return installed.filter { !off.contains($0.id) }.count
            + availableBuiltins.filter { !off.contains($0.id) && !removed.contains($0.id) }.count
    }
}

// MARK: - 在线词库清单

/// enclavekb.cn/dicts/catalog.json：名称、内容、词条数、大小、许可、版本、sha256、下载地址。
/// 只在打开词库页时拉一次，不后台联网；拉不到用上次的，第一次用 App 里带的这份。
struct ExtDictCatalog: Codable, Equatable {
    struct Text: Codable, Equatable {
        var zh: String
        var en: String?
        var ja: String?
        var value: String { L(zh, en ?? zh, ja ?? zh) }
    }

    struct Item: Codable, Identifiable, Equatable {
        var id: String
        var name: Text
        var summary: Text?
        var license: ExtDict.License
        var entries: Int
        var size: Int64
        var version: String
        var sha256: String?
        /// 空着表示还没上线：显示「准备中」，不能下载。
        var url: String?

        /// 大陆界面「百科词库」，其他地区「维基百科词库」（05 许可结论）。
        var displayName: String {
            guard license == .wiki else { return name.value }
            return Storefront.isMainlandChina ? L("百科词库", "Encyclopedia", "百科辞書") : L("维基百科词库", "Wikipedia", "ウィキペディア辞書")
        }
    }

    var dicts: [Item]

    static var baseURL: URL {
        #if DEBUG
        // 模拟器里用本机的服务器测下载：-extDictBase http://localhost:8765/
        if let value = UserDefaults.standard.string(forKey: "extDictBase"), let url = URL(string: value) { return url }
        #endif
        return URL(string: "https://enclavekb.cn/dicts/")!
    }

    /// App 里带的清单（服务器拉不到时用）。百科词库等敏感词过滤、上传后在服务器清单里补上地址。
    static let fallback = ExtDictCatalog(dicts: [
        Item(id: "baike", name: Text(zh: "百科词库", en: "Wikipedia", ja: "ウィキペディア辞書"),
             summary: Text(zh: "人名、地名、作品、游戏角色", en: "People, places, works and game characters", ja: "人名、地名、作品、ゲームキャラクター"),
             license: .wiki, entries: 200_000, size: 3_100_000, version: "", sha256: nil, url: nil),
        Item(id: "medical", name: Text(zh: "医学", en: "Medicine", ja: "医学"), summary: nil, license: .thuocl,
             entries: 18_749, size: 621_185, version: "2026-10-30", sha256: nil, url: "ext_medical.dict.yaml"),
        Item(id: "law", name: Text(zh: "法律", en: "Law", ja: "法律"), summary: nil, license: .thuocl,
             entries: 9_896, size: 586_983, version: "2026-10-30", sha256: nil, url: "ext_law.dict.yaml"),
        Item(id: "poem", name: Text(zh: "诗词", en: "Poetry", ja: "詩詞"), summary: nil, license: .thuocl,
             entries: 13_703, size: 633_806, version: "2026-10-30", sha256: nil, url: "ext_poem.dict.yaml"),
        Item(id: "lishimingren", name: Text(zh: "历史名人", en: "Historical figures", ja: "歴史上の人物"), summary: nil, license: .thuocl,
             entries: 13_658, size: 305_944, version: "2026-10-30", sha256: nil, url: "ext_lishimingren.dict.yaml"),
    ])

    private static let cacheKey = "extDicts.catalog"

    static var cached: ExtDictCatalog {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let catalog = try? JSONDecoder().decode(ExtDictCatalog.self, from: data) else { return fallback }
        return catalog
    }

    static func fetch() async -> ExtDictCatalog? {
        var request = URLRequest(url: baseURL.appendingPathComponent("catalog.json"))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let catalog = try? JSONDecoder().decode(ExtDictCatalog.self, from: data) else { return nil }
        UserDefaults.standard.set(data, forKey: cacheKey)
        return catalog
    }

    /// 相对地址按清单所在目录解析。
    static func downloadURL(_ item: Item) -> URL? {
        guard let url = item.url, !url.isEmpty else { return nil }
        return URL(string: url, relativeTo: baseURL)?.absoluteURL
    }
}

// MARK: - 管理：开关、删除、恢复、下载、导入

@MainActor
final class ExtDictStore: NSObject, ObservableObject {
    static let shared = ExtDictStore()

    /// 「我的词库」的一行。
    struct Row: Identifiable, Equatable {
        var id: String
        var kind: ExtDict.Kind
        var name: String
        var subtitle: String
        var entries: Int
        var enabled: Bool
        var hasUpdate: Bool
    }

    @Published private(set) var installed = ExtDict.installed
    @Published private(set) var off = ExtDict.off
    @Published private(set) var removedBuiltins = ExtDict.removedBuiltins
    @Published private(set) var catalog = ExtDictCatalog.cached
    /// 正在下载的：id → (已下, 总共) 字节。
    @Published private(set) var downloads: [String: (received: Int64, expected: Int64)] = [:]
    @Published var downloadError: String?
    /// 导入：文件选择器开着、等确认的、没认出来的文件名。
    @Published var picking = false
    @Published var draft: ImportDraft?
    @Published var failedFile: String?

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var deployTask: Task<Void, Never>?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    // MARK: 列表

    /// 下载、导入的在前（新加的在最上），内置的在后（固定顺序）。
    var rows: [Row] {
        let added = installed.sorted { $0.addedAt > $1.addedAt }.map { item -> Row in
            let detail: String
            switch item.kind {
            case .imported:
                detail = Self.entryText(item.entries) + " · " + (item.fileName ?? "")
            default:
                detail = Self.entryText(item.entries) + " · " + Self.sizeText(item.size) + " · " + Self.versionText(item.version)
            }
            return Row(id: item.id, kind: item.kind, name: displayName(item), subtitle: detail, entries: item.entries,
                       enabled: !off.contains(item.id), hasUpdate: update(for: item) != nil)
        }
        let builtin = ExtDict.availableBuiltins.filter { !removedBuiltins.contains($0.id) }.map { pack -> Row in
            let entries = ExtDict.builtinManifest[pack.id]?.entries ?? 0
            var parts = [pack.category, Self.entryText(entries)].filter { !$0.isEmpty }
            if pack.id == "meme" { parts.append(L("随 App 更新", "Updated with the app", "アプリと一緒に更新")) }
            return Row(id: pack.id, kind: .builtin, name: pack.name, subtitle: parts.joined(separator: " · "), entries: entries,
                       enabled: !off.contains(pack.id), hasUpdate: false)
        }
        return added + builtin
    }

    func displayName(_ item: ExtDict.Installed) -> String {
        if item.license == .wiki, let entry = catalog.dicts.first(where: { $0.id == item.id }) { return entry.displayName }
        return item.name
    }

    var enabledEntries: Int { rows.filter(\.enabled).reduce(0) { $0 + $1.entries } }

    /// 删掉的内置词库：出现在「在线词库」第一行，点「恢复」加回来。
    var removedBuiltinPacks: [ExtDict.Builtin] {
        ExtDict.availableBuiltins.filter { removedBuiltins.contains($0.id) }
    }

    func isDownloaded(_ id: String) -> Bool { installed.contains { $0.id == id } }

    /// 服务器上有新版：返回清单里的那一项。
    func update(for item: ExtDict.Installed) -> ExtDictCatalog.Item? {
        guard item.kind == .downloaded, let entry = catalog.dicts.first(where: { $0.id == item.id }),
              ExtDictCatalog.downloadURL(entry) != nil, entry.version > item.version else { return nil }
        return entry
    }

    // MARK: 改动（每次改完都排一次部署）

    func setEnabled(_ id: String, _ value: Bool) {
        if value { off.remove(id) } else { off.insert(id) }
        ExtDict.off = off
        scheduleDeploy()
    }

    func remove(_ id: String) {
        if ExtDict.availableBuiltins.contains(where: { $0.id == id }) && !installed.contains(where: { $0.id == id }) {
            removedBuiltins.insert(id)
            ExtDict.removedBuiltins = removedBuiltins
        } else if let item = installed.first(where: { $0.id == id }) {
            if let url = ExtDict.fileURL(id: id, kind: item.kind) { try? FileManager.default.removeItem(at: url) }
            installed.removeAll { $0.id == id }
            ExtDict.installed = installed
        }
        off.remove(id)
        ExtDict.off = off
        scheduleDeploy()
    }

    func restore(_ id: String) {
        removedBuiltins.remove(id)
        ExtDict.removedBuiltins = removedBuiltins
        off.remove(id)
        ExtDict.off = off
        scheduleDeploy()
    }

    /// 连着改几个开关合并成一次部署：最后一次改动 1.5 秒后才开始。部署中又改了，部署完会自己再来一次。
    private func scheduleDeploy() {
        deployTask?.cancel()
        deployTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.deployTask = nil
            RimeDeployer.shared.deploy()
        }
    }

    func refreshCatalog() async {
        if let fresh = await ExtDictCatalog.fetch() { catalog = fresh }
    }

    // MARK: 导入

    struct ImportDraft: Identifiable {
        let id = UUID()
        var fileName: String
        var format: String
        var fileSize: Int64
        var name: String
        var entries: [ExtDictFormat.Entry]
    }

    /// 读用户选的文件；不认识的格式返回 nil。
    nonisolated static func readImport(_ url: URL) -> ImportDraft? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let parsed = try? ExtDictFormat.parse(data, fileName: url.lastPathComponent) else { return nil }
        let scel = url.pathExtension.lowercased() == "scel"
        var name = url.lastPathComponent
        for suffix in [".scel", ".dict.yaml", ".yaml", ".txt"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return ImportDraft(fileName: url.lastPathComponent,
                           format: scel ? L("细胞词库", "Cell dictionary", "セル辞書") : L("Rime 词库", "Rime dictionary", "Rime 辞書"),
                           fileSize: Int64(data.count), name: parsed.title ?? name, entries: parsed.entries)
    }

    func commitImport(_ draft: ImportDraft) throws {
        guard let folder = ExtDict.folder else { throw ImportError.noAppGroup }
        let id = "imp" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let version = ISO8601DateFormatter().string(from: Date())
        let text = ExtDictFormat.rimeText(draft.entries, id: id, source: draft.fileName, version: version)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("ext_\(id).dict.yaml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        Self.excludeFromBackup(url)
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        installed.append(ExtDict.Installed(id: id, kind: .imported, name: name.isEmpty ? draft.fileName : name,
                                           entries: draft.entries.count, size: Int64(text.utf8.count), version: version,
                                           license: nil, fileName: draft.fileName, addedAt: Date()))
        ExtDict.installed = installed
        scheduleDeploy()
    }

    enum ImportError: LocalizedError {
        case noAppGroup
        var errorDescription: String? {
            L("App Group 没有生效，放不了词库。", "The App Group isn't working, so the dictionary can't be saved.", "App Group が有効でないため、辞書を保存できません。")
        }
    }

    // MARK: 下载

    func download(_ item: ExtDictCatalog.Item) {
        guard tasks[item.id] == nil, let url = ExtDictCatalog.downloadURL(item) else { return }
        guard ExtDict.folder != nil else {
            downloadError = ImportError.noAppGroup.errorDescription
            return
        }
        downloadError = nil
        let task = session.downloadTask(with: url)
        task.taskDescription = item.id
        tasks[item.id] = task
        downloads[item.id] = (0, item.size)
        task.resume()
    }

    func cancelDownload(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        downloads[id] = nil
    }

    private func finishDownload(id: String, location: URL) {
        guard let item = catalog.dicts.first(where: { $0.id == id }), let folder = ExtDict.folder else { return }
        do {
            let data = try Data(contentsOf: location)
            if let expected = item.sha256, !expected.isEmpty {
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actual == expected.lowercased() else { throw DownloadError.corrupt }
            }
            guard let text = String(data: data, encoding: .utf8), text.contains("name: ext_\(id)") else { throw DownloadError.corrupt }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("ext_\(id).dict.yaml")
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try data.write(to: target, options: .atomic)
            Self.excludeFromBackup(target)
            let entry = ExtDict.Installed(id: id, kind: .downloaded, name: item.name.zh, entries: ExtDictFormat.entryCount(text),
                                          size: Int64(data.count), version: item.version, license: item.license, fileName: nil,
                                          addedAt: installed.first(where: { $0.id == id })?.addedAt ?? Date())
            installed.removeAll { $0.id == id }
            installed.append(entry)
            ExtDict.installed = installed
            off.remove(id)
            ExtDict.off = off
            scheduleDeploy()
        } catch {
            downloadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private enum DownloadError: LocalizedError {
        case corrupt
        var errorDescription: String? {
            L("下载的文件不完整，请再试一次。", "The downloaded file is incomplete. Please try again.", "ダウンロードしたファイルが不完全です。もう一度お試しください。")
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
    }

    // MARK: 文字

    static func entryText(_ count: Int) -> String {
        L("约 ", "About ", "約 ") + wordsText(count)
    }

    /// 「8,500 词」「4.5 万词」（万后面不再空格）/「45k words」。
    static func wordsText(_ count: Int) -> String {
        let number = countText(count)
        return number + (number.hasSuffix("万") ? L("词", " words", "語") : L(" 词", " words", " 語"))
    }

    /// 「8,500」「4.5 万」/「8,500」「45k」。
    static func countText(_ count: Int) -> String {
        let rounded = count >= 1000 ? (count + 50) / 100 * 100 : count
        if count >= 10_000 {
            let tenThousands = Double(rounded) / 10_000
            let zh = (tenThousands >= 10 ? String(Int(tenThousands.rounded())) : String(format: "%.1f", tenThousands)).replacingOccurrences(of: ".0", with: "") + " 万"
            let thousands = Double(rounded) / 1000
            let en = (thousands >= 100 ? String(Int(thousands.rounded())) : String(format: "%.1f", thousands)).replacingOccurrences(of: ".0", with: "") + "k"
            return L(zh, en, zh)
        }
        return rounded.formatted()
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 「10月30日版」。
    static func versionText(_ version: String) -> String {
        guard let date = parseVersion(version) else { return version }
        return L("\(Loc.monthDay(date))版", "\(Loc.monthDay(date)) edition", "\(Loc.monthDay(date))版")
    }

    static func parseVersion(_ version: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(version.prefix(10)))
    }
}

extension ExtDictStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            guard let id = downloadTask.taskDescription, tasks[id] === downloadTask else { return }
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (downloads[id]?.expected ?? 0)
            downloads[id] = (totalBytesWritten, expected)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        MainActor.assumeIsolated {
            guard let id = downloadTask.taskDescription, tasks[id] === downloadTask else { return }
            tasks[id] = nil
            downloads[id] = nil
            if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
                downloadError = L("下载失败（HTTP \(response.statusCode)）。", "Download failed (HTTP \(response.statusCode)).", "ダウンロードに失敗しました（HTTP \(response.statusCode)）。")
                return
            }
            finishDownload(id: id, location: location)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let error, let id = task.taskDescription, tasks[id] === task else { return }
            tasks[id] = nil
            downloads[id] = nil
            if (error as? URLError)?.code == .cancelled { return }
            downloadError = L("下载中断了：\(error.localizedDescription)。请再试一次。", "Download interrupted: \(error.localizedDescription). Please try again.", "ダウンロードが中断しました：\(error.localizedDescription)。もう一度お試しください。")
        }
    }
}
