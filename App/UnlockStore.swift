import StoreKit
import SwiftUI

/// 一次买断：StoreKit 2 读商品、购买、恢复，结果写进 App Group 给键盘用。
/// 试用开始日取 AppTransaction 的首次下载日，删了重装也不会重置。
@MainActor
final class UnlockStore: ObservableObject {
    static let shared = UnlockStore()

    @Published private(set) var access = AIAccess.current
    @Published private(set) var product: Product?
    @Published private(set) var purchasing = false
    /// 购买或恢复之后给用户的一句话；用户在系统弹窗里取消时不提示。
    @Published var message: Message?

    enum Message: Identifiable, Equatable {
        case unlocked, pending, notFound, offline, failed(String)
        var id: String { "\(self)" }
    }

    private var updates: Task<Void, Never>?

    private init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-aiAccess"), args.indices.contains(i + 1) {
            AIAccess.setDebug(args[i + 1])
        } else {
            AIAccess.setDebug(nil)
        }
        #endif
    }

    /// 价格用 StoreKit 给的本地化价格；还没拿到时显示美元档位。
    var displayPrice: String { product?.displayPrice ?? "US$2.99" }

    /// App 启动和回到前台时调用：读首次下载日、买过没有，更新键盘能看到的记录。
    func refresh() async {
        if case .verified(let app) = try? await AppTransaction.shared {
            AIAccess.recordTrialStart(app.originalPurchaseDate)
        }
        var purchased: Date?
        if case .verified(let transaction)? = await Transaction.currentEntitlement(for: AIAccess.productID),
           transaction.revocationDate == nil {
            purchased = transaction.purchaseDate
        }
        AIAccess.recordPurchase(unlocked: purchased != nil, date: purchased)
        access = AIAccess.current
        if product == nil {
            product = try? await Product.products(for: [AIAccess.productID]).first
        }
    }

    func buy() async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            if product == nil { product = try await Product.products(for: [AIAccess.productID]).first }
            guard let product else {
                message = .offline
                return
            }
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
                message = .unlocked
            case .success(.unverified(_, let error)):
                message = .failed(error.localizedDescription)
            case .pending:
                message = .pending
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = Self.isOffline(error) ? .offline : .failed(error.localizedDescription)
        }
    }

    func restore() async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            try await StoreKit.AppStore.sync()
            await refresh()
            if case .unlocked = access { message = .unlocked } else { message = .notFound }
        } catch StoreKitError.userCancelled {
            // 系统登录弹窗里取消：什么都不提示。
        } catch {
            message = Self.isOffline(error) ? .offline : .failed(error.localizedDescription)
        }
    }

    private static func isOffline(_ error: Error) -> Bool {
        if case StoreKitError.networkError = error { return true }
        return (error as NSError).domain == NSURLErrorDomain
    }
}
