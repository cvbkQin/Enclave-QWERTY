import Foundation

/// 整句模型（万象语法模型，CC BY 4.0）：可选下载，放在共享目录的 Rime 用户目录里，部署时给方案加上 grammar 配置。
/// 内测包自带一份（见 bundledURL），只能停用不能删。
/// 引擎（librime-octagram）用 mmap 只读映射，只读用到的部分。键盘要开完全访问才读得到。
enum GrammarModel {
    static let language = "wanxiang-lts-zh-hans"
    /// 下载线路见 GrammarLine（Shared/DictUpdatePolicy.swift）：非中国大陆从万象的 GitHub 下，中国大陆从飞地服务器 enclavekb.cn 下。
    /// 11-26 起不能再手填地址（对齐清单第 99 条）；以前填过的，升级后清掉（GrammarDownloader 启动时）。
    static let legacyDownloadURLKey = "grammar.downloadURL"

    /// 下载前显示的大概大小：GitHub 上 LTS 那份 11-18 版 390,786,092 字节；服务器清单里有大小时用清单的。
    static let approximateSize: Int64 = 390_786_092

    /// 下载记录（已下载卡片的小字「非中国大陆线路 · 11 月 26 日下载」，有没有新版本）。
    static var downloadedLine: GrammarLine? {
        get { SharedStorage.defaults.string(forKey: "grammar.downloadedLine").flatMap(GrammarLine.init(rawValue:)) }
        set { SharedStorage.defaults.set(newValue?.rawValue, forKey: "grammar.downloadedLine") }
    }

    static var downloadedAt: Date? {
        get { SharedStorage.defaults.object(forKey: "grammar.downloadedAt") as? Date }
        set { SharedStorage.defaults.set(newValue, forKey: "grammar.downloadedAt") }
    }

    /// 下载时服务器清单里的模型版本（「2026-11-18」）；清单拉不到、更早下的没有。
    static var downloadedVersion: String? {
        get { SharedStorage.defaults.string(forKey: "grammar.downloadedVersion") }
        set { SharedStorage.defaults.set(newValue, forKey: "grammar.downloadedVersion") }
    }

    static var fileURL: URL? {
        RimeStore.paths?.user.appendingPathComponent(language + ".gram")
    }

    /// 下载过，或内测包自带（部署时才在用户目录放链接）。
    static var isInstalled: Bool {
        if isBundled { return true }
        guard let fileURL else { return false }
        return isValid(fileURL)
    }

    /// 内测包自带的那份（打包时 INTERNAL_BUILD=YES 由 scripts/fetch-grammar.sh 拷进键盘扩展）。
    /// 键盘里是自己的包；App 里去 PlugIns 下的键盘扩展里找。包里的文件只读，删不掉，只能停用。
    static let bundledURL: URL? = {
        let name = language + ".gram"
        var candidates = [Bundle.main.bundleURL.appendingPathComponent(name)]
        if let plugins = Bundle.main.builtInPlugInsURL,
           let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) {
            candidates += items.filter { $0.pathExtension == "appex" }.map { $0.appendingPathComponent(name) }
        }
        return candidates.first { isValid($0) }
    }()

    static var isBundled: Bool { bundledURL != nil }

    /// 包里带了模型：在 Rime 用户目录放一个指向它的链接，引擎照常在用户目录找到它、mmap 直接读包里那份，不再占一份空间。
    /// App 升级后包的路径会变，App 部署和键盘加载词库前都调一次，链接不对就重建。以前下载过的那份换成链接。
    static func linkBundled() {
        guard let bundledURL, let fileURL else { return }
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: fileURL.path)) == bundledURL.path { return }
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: fileURL)
        try? fm.createSymbolicLink(at: fileURL, withDestinationURL: bundledURL)
    }

    /// 下载后的开关：关掉时文件留着，部署时不用它（方便对比有没有模型）。默认开。
    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: "grammar.enabled") as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: "grammar.enabled") }
    }

    /// 已下载并且开着：部署时用上。
    static var isActive: Bool { isInstalled && isEnabled }

    static var installedSize: Int64? {
        guard let path = fileURL?.resolvingSymlinksInPath().path,
              let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// 文件头是 octagram 的格式标记「Rime::Grammar/」。
    static func isValid(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = Data("Rime::Grammar/".utf8)
        return (try? handle.read(upToCount: prefix.count)) == prefix
    }

    /// 写进已部署版本号的后缀：装上或删掉模型后要重新部署，键盘也跟着重新加载。
    static func versionTag(installed: Bool) -> String {
        installed ? "+gram" : ""
    }

    /// 在方案末尾加上 grammar 配置（参数和万象拼音自己的方案一样）。
    static func patchSchema(_ text: String) -> String {
        guard !text.contains("\ngrammar:") else { return text }
        return text + """

        # Enclave 整句模型（下载后才有）
        grammar:
          language: \(language)
          collocation_max_length: 6
          collocation_min_length: 2
          collocation_penalty: -14
          non_collocation_penalty: -6
          weak_collocation_penalty: -100
          rear_penalty: -18

        """
    }
}
