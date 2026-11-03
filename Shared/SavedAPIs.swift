import Foundation

/// 接口配置（11-03 接口配置页重排 CF，原「我的预设」）：名字、服务商模板、地址、模型、Key、温度、最多字数。润色、问答两页共用一个列表，各自用其中一条。
/// 名字、地址、模型存在共享的 UserDefaults；Key 只存本机钥匙串（每条一个账户名），不进导出的配置和剪贴板。
/// 联网测试结果按「地址 + 模型」另存（WebSearchProbe）。
struct SavedAPI: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
    var savedAt = Date()
    /// 新建时选的服务商模板（ConfigTemplate 的 rawValue）；旧预设和自定义是 nil，按地址认。
    var template: String?
    /// 生成参数跟着配置走；旧预设没有，用的时候按当前设置。
    var temperature: Double?
    var maxTokens: Int?

    private var keyAccount: String { "apiKey.saved.\(id.uuidString)" }

    var apiKey: String? {
        get { Keychain.get(keyAccount) }
        nonmutating set { Keychain.set(newValue, for: keyAccount) }
    }

    /// 列表上只显示 Key 的尾号 4 位，没有 Key 时 nil。
    var keySuffix: String? {
        guard let key = apiKey, !key.isEmpty else { return nil }
        return String(key.suffix(4))
    }

    /// 地址、模型、Key 三样都一样。
    func matches(baseURL: String, model: String, apiKey: String?) -> Bool {
        SavedAPIStore.normalized(self.baseURL) == SavedAPIStore.normalized(baseURL)
            && self.model == model.trimmingCharacters(in: .whitespacesAndNewlines)
            && (self.apiKey ?? "") == (apiKey ?? "")
    }

    /// 默认名字：「Kimi · kimi-k3.1-pro」，认不出的服务商写主机名。
    static func defaultName(baseURL: String, model: String) -> String {
        let host = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host ?? baseURL
        let model = model.trimmingCharacters(in: .whitespaces)
        return model.isEmpty ? host : "\(host) · \(model)"
    }

    fileprivate func deleteKey() { Keychain.set(nil, for: keyAccount) }
}

enum SavedAPIStore {
    private static let key = "savedAPIs"

    static var all: [SavedAPI] {
        guard let data = SharedStorage.defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([SavedAPI].self, from: data) else { return [] }
        return list
    }

    private static func write(_ list: [SavedAPI]) {
        if let data = try? JSONEncoder().encode(list) { SharedStorage.defaults.set(data, forKey: key) }
    }

    /// 现在用的地址和模型存过预设的话，显示预设的名字（App 的 AI 页、首页、键盘出错卡等）。不比 Key：键盘里只要名字。
    static func name(baseURL: String, model: String) -> String? {
        let url = normalized(baseURL)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !model.isEmpty else { return nil }
        let name = all.first { normalized($0.baseURL) == url && $0.model == model }?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    static func normalized(_ url: String) -> String {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    enum SaveResult { case saved(SavedAPI), duplicate(SavedAPI) }

    /// 存一条，放在最后。地址、模型、Key 三样都和已有某条一样时不新增，返回那一条。
    @discardableResult
    static func save(name: String?, baseURL: String, model: String, apiKey: String?) -> SaveResult {
        var list = all
        if let existing = list.first(where: { $0.matches(baseURL: baseURL, model: model, apiKey: apiKey) }) {
            return .duplicate(existing)
        }
        let url = normalized(baseURL), model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? SavedAPI.defaultName(baseURL: url, model: model)
        let item = SavedAPI(name: name, baseURL: url, model: model)
        item.apiKey = apiKey
        list.append(item)
        write(list)
        return .saved(item)
    }

    /// 新加一条配置，放在最后（不查重：同样的地址和模型可以存两条不同的 Key / 参数）。
    @discardableResult
    static func add(_ item: SavedAPI, apiKey: String?) -> SavedAPI {
        var list = all
        var item = item
        item.baseURL = normalized(item.baseURL)
        item.model = item.model.trimmingCharacters(in: .whitespacesAndNewlines)
        item.apiKey = apiKey
        list.append(item)
        write(list)
        return item
    }

    /// 改一条配置（名字、地址、模型、参数），Key 一起写进钥匙串。
    static func update(_ item: SavedAPI, apiKey: String?) {
        var list = all
        guard let index = list.firstIndex(where: { $0.id == item.id }) else { return }
        var item = item
        item.baseURL = normalized(item.baseURL)
        item.model = item.model.trimmingCharacters(in: .whitespacesAndNewlines)
        list[index] = item
        item.apiKey = apiKey
        write(list)
    }

    /// 不和已有名字重复：「DeepSeek」已经有了就叫「DeepSeek 2」「DeepSeek 3」。
    static func uniqueName(_ base: String, in list: [SavedAPI] = all) -> String {
        let names = Set(list.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private static let migratedKey = "savedAPIs.configs.migrated"

    /// 接口配置页重排后第一次打开：原来润色、问答正在用的接口各存成一条配置（名字用服务商名，重名加 2）。
    /// 已经存成预设的不重复存。只做一次。providerName：地址 → 服务商名。
    static func migrateIfNeeded(current: [(baseURL: String, model: String, apiKey: String?, temperature: Double?, maxTokens: Int?)],
                                providerName: (String) -> String) {
        guard !SharedStorage.defaults.bool(forKey: migratedKey) else { return }
        SharedStorage.defaults.set(true, forKey: migratedKey)
        for endpoint in current {
            let url = normalized(endpoint.baseURL), model = endpoint.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, !model.isEmpty,
                  !all.contains(where: { $0.matches(baseURL: url, model: model, apiKey: endpoint.apiKey) }) else { continue }
            add(SavedAPI(name: uniqueName(providerName(url)), baseURL: url, model: model,
                         temperature: endpoint.temperature, maxTokens: endpoint.maxTokens), apiKey: endpoint.apiKey)
        }
    }

    static func rename(_ id: UUID, to name: String) {
        var list = all
        guard let index = list.firstIndex(where: { $0.id == id }),
              let name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return }
        list[index].name = name
        write(list)
    }

    /// 恢复备份时整份换掉（Key 另外恢复）。
    static func replaceAll(_ list: [SavedAPI]) { write(list) }

    static func delete(_ id: UUID) {
        var list = all
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list.remove(at: index).deleteKey()
        write(list)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
