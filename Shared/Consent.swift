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

    static func isConsented(_ endpoint: String) -> Bool {
        consented?.endpoint == endpoint
    }

    static func grant(_ endpoint: String) {
        SharedStorage.defaults.set(endpoint, forKey: endpointKey)
        SharedStorage.defaults.set(Date(), forKey: dateKey)
    }

    static func revoke() {
        SharedStorage.defaults.removeObject(forKey: endpointKey)
        SharedStorage.defaults.removeObject(forKey: dateKey)
    }
}
