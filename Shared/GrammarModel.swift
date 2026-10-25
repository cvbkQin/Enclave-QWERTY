import Foundation

/// 整句模型（万象语法模型，CC BY 4.0）：可选下载，放在共享目录的 Rime 用户目录里，部署时给方案加上 grammar 配置。
/// 引擎（librime-octagram）用 mmap 只读映射，只读用到的部分。键盘要开完全访问才读得到。
enum GrammarModel {
    static let language = "wanxiang-lts-zh-hans"
    static let downloadURL = URL(string: "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram")!
    /// 下载前显示的大概大小。
    static let approximateSize: Int64 = 380 * 1_000_000

    static var fileURL: URL? {
        RimeStore.paths?.user.appendingPathComponent(language + ".gram")
    }

    static var isInstalled: Bool {
        guard let fileURL else { return false }
        return isValid(fileURL)
    }

    /// 下载后的开关：关掉时文件留着，部署时不用它（方便对比有没有模型）。默认开。
    static var isEnabled: Bool {
        get { SharedStorage.defaults.object(forKey: "grammar.enabled") as? Bool ?? true }
        set { SharedStorage.defaults.set(newValue, forKey: "grammar.enabled") }
    }

    /// 已下载并且开着：部署时用上。
    static var isActive: Bool { isInstalled && isEnabled }

    static var installedSize: Int64? {
        guard let path = fileURL?.path,
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
