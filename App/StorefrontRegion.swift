import Foundation
import StoreKit

/// App Store 店面所在地区。中国大陆店面要按国内规定调整（比如服务商预设不列 OpenAI）。
extension Storefront {
    private static let countryKey = "storefront.country"

    /// 上次读到的店面是不是中国大陆（CHN）。启动时 refreshCountry() 更新，没读到过按非大陆。
    static var isMainlandChina: Bool {
        UserDefaults.standard.string(forKey: countryKey) == "CHN"
    }

    #if DEBUG
    /// 截图用（-storefront CHN）：固定成某个店面，启动时不再去读真的。
    static func debugOverride(_ code: String) {
        UserDefaults.standard.set(code, forKey: countryKey)
        debugLocked = true
    }
    private(set) static var debugLocked = false
    #endif

    static func refreshCountry() async {
        #if DEBUG
        if debugLocked { return }
        #endif
        guard let code = await Storefront.current?.countryCode else { return }
        UserDefaults.standard.set(code, forKey: countryKey)
    }
}
