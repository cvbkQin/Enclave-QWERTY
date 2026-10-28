import Foundation

/// 发送前的同意记录：按接口地址（域名加端口）记一条。只改模型名或 API Key 不用重新同意，换了地址要再问。
enum ConsentStore {
    private static let endpointKey = "consent.endpoint"
    private static let dateKey = "consent.date"

    /// 接口地址里的域名和端口，比如 api.deepseek.com、192.168.1.20:11434。
    static func endpoint(of baseURL: String) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              let host = url.host, !host.isEmpty else { return nil }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// 已同意的地址和时间。
    static var consented: (endpoint: String, date: Date)? {
        guard let endpoint = SharedStorage.defaults.string(forKey: endpointKey) else { return nil }
        let date = SharedStorage.defaults.object(forKey: dateKey) as? Date ?? Date()
        return (endpoint, date)
    }

    /// 润色和问答可以是两个接口：同意过的地址都记着（consented 是最近同意的那个）。
    private static let endpointsKey = "consent.endpoints"
    private static var endpoints: [String] { SharedStorage.defaults.stringArray(forKey: endpointsKey) ?? [] }

    static func isConsented(_ endpoint: String) -> Bool {
        consented?.endpoint == endpoint || endpoints.contains(endpoint)
    }

    static func grant(_ endpoint: String) {
        SharedStorage.defaults.set(endpoint, forKey: endpointKey)
        SharedStorage.defaults.set(Date(), forKey: dateKey)
        // 只留润色、问答最近用的两个，换了地址的旧地址要重新确认。
        let kept = Array((endpoints.filter { $0 != endpoint } + [endpoint]).suffix(2))
        SharedStorage.defaults.set(kept, forKey: endpointsKey)
    }

    static func revoke() {
        SharedStorage.defaults.removeObject(forKey: endpointKey)
        SharedStorage.defaults.removeObject(forKey: dateKey)
        SharedStorage.defaults.removeObject(forKey: endpointsKey)
    }
}
