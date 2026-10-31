import Foundation

/// 已存方案：接口页上「保存」下来的地址、模型和 Key，点一下就恢复。润色和改写、问答两页共用一个列表。
/// 名字、地址、模型存在共享的 UserDefaults；Key 只存本机钥匙串（每条一个账户名），不进导出的配置和剪贴板。
struct SavedAPI: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var baseURL: String
    var model: String
    var savedAt = Date()

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
