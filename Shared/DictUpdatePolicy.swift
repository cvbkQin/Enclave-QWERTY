import Foundation

/// 热门词库自动更新、整句模型下载线路的判断（对齐清单第 99 条，specs/整句模型下载与热门词库自动更新-方案.md 二、三）。
/// 只放纯逻辑（单测在 Tests/DictUpdatePolicyTests.swift），联网、存文件在 App 的 DictAutoUpdate.swift、GrammarDownloader.swift。
enum DictUpdatePolicy {
    /// 自动检查的间隔：7 天。
    static let interval: TimeInterval = 7 * 86400
    /// 检查失败（没网、服务器出错）不算一次检查，过 1 天再试。
    static let retryAfterFailure: TimeInterval = 86400

    /// 该不该自动查一次：开关开着；上次成功检查满 7 天（从没查过也算）；上次失败的话要过 1 天。
    static func isDue(now: Date, lastCheck: Date?, lastFailure: Date?, enabled: Bool) -> Bool {
        guard enabled else { return false }
        if let lastFailure, now.timeIntervalSince(lastFailure) < retryAfterFailure,
           lastCheck.map({ lastFailure.isAfter($0) }) ?? true {
            return false
        }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// 服务器上的这一份是不是新的：两边都有 sha256 就看 sha256 变没变；老记录没有 sha256 的按版本字符串比。
    /// 版本是「2026-11-26」，同一天第二次改写成「2026-11-26.2」，按字符串比大小也是新的在后。
    static func isNewer(remoteSHA: String?, remoteVersion: String, localSHA: String?, localVersion: String) -> Bool {
        if let remote = remoteSHA?.lowercased(), !remote.isEmpty, let local = localSHA?.lowercased(), !local.isEmpty {
            return remote != local
        }
        return compare(remoteVersion, localVersion) == .orderedDescending
    }

    /// 版本比大小：日期部分按字符串，「.2」「.3」这种同一天的序号按数字。
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func split(_ v: String) -> (String, Int) {
            let parts = v.split(separator: ".", maxSplits: 1).map(String.init)
            return (parts.first ?? "", parts.count > 1 ? Int(parts[1]) ?? 0 : 1)
        }
        let (da, na) = split(a), (db, nb) = split(b)
        if da != db { return da < db ? .orderedAscending : .orderedDescending }
        if na != nb { return na < nb ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    /// 内置词库用哪一份：服务器下的那份比 App 自带的新才用它（App 升级后自带的更新了，就回到自带的）。
    static func usesServerCopy(serverVersion: String?, bundledVersion: String?) -> Bool {
        guard let serverVersion, !serverVersion.isEmpty else { return false }
        guard let bundledVersion, !bundledVersion.isEmpty else { return true }
        return compare(serverVersion, bundledVersion) == .orderedDescending
    }

    /// 服务器新加的词库（「可以下载」里标「新」）：清单里有、以前没看到过的。第一次（还没记过）不标。
    static func newIDs(catalog: [String], seen: Set<String>?) -> Set<String> {
        guard let seen else { return [] }
        return Set(catalog).subtracting(seen)
    }
}

/// 整句模型的两条下载线路（DU1）：非中国大陆（万象 GitHub）排第一，中国大陆（飞地服务器 enclavekb.cn）第二。
enum GrammarLine: String, CaseIterable, Codable, Identifiable {
    case global, cn

    var id: String { rawValue }

    /// 默认按 App Store 地区：大陆店面默认中国大陆，其他默认非中国大陆。
    static func defaultLine(mainland: Bool) -> GrammarLine { mainland ? .cn : .global }

    /// catalog.json 的 grammar.urls 里的键。
    var catalogKey: String { rawValue }

    var defaultURL: URL {
        switch self {
        case .global: return URL(string: "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram")!
        case .cn: return URL(string: "https://enclavekb.cn/grammar/wanxiang-lts-zh-hans.gram")!
        }
    }

    var other: GrammarLine { self == .global ? .cn : .global }

    /// sha256 只在大陆线路上校验：GitHub 那份会被万象随时更新（方案二之 4）。
    var verifiesSHA: Bool { self == .cn }
}
