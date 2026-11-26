import StoreKit
import SwiftUI

/// 一次买断和 14 天试用：StoreKit 2 读商品、购买、恢复，结果写进 App Group 给键盘用。
/// 试用是 0 元的非消耗型商品（审核指南 3.1.1，05 上架风险报告高 2）：点「开始 14 天免费试用」才开始，试用开始日取它的购买日，
/// 记录在 App Store，删了重装、换手机都不会重来。
@MainActor
final class UnlockStore: ObservableObject {
    static let shared = UnlockStore()

    @Published private(set) var access = AIAccess.current
    @Published private(set) var product: Product?
    @Published private(set) var trialProduct: Product?
    @Published private(set) var purchasing = false
    /// 购买或恢复之后给用户的一句话；用户在系统弹窗里取消时不提示。
    @Published var message: Message?

    enum Message: Identifiable, Equatable {
        /// unavailable：连上了 App Store，但没给这个商品（App Store Connect 里没配好，开发版、沙盒里常见）。
        /// 买成功、试用开始了都不提示：Apple 自己会弹「已完成」，解锁页原地变成新状态（DESIGN.md，R5 ②）。unlocked 只给「恢复购买」用。
        case unlocked, pending, notFound, offline, unavailable, failed(String)
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
        AIAccess.applyDevDefault()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        // 启动参数只在截图时给；不给时保留解锁页「测试」块里选的状态。
        if let i = args.firstIndex(of: "-aiAccess"), args.indices.contains(i + 1) {
            AIAccess.setDebug(args[i + 1])
        }
        #endif
    }

    /// 设置里改了测试用的购买状态：马上更新解锁页和设置卡片。
    func reloadAccess() {
        access = AIAccess.current
    }

    /// 价格用 StoreKit 给的本地化价格；还没拿到时显示美元档位。
    /// StoreKit 给的本地价格（中国区 ¥18）；商品还没加载出来时为 nil，按钮只写「解锁」，不写死美元价。
    var displayPrice: String? { product?.displayPrice }

    /// 解锁页的买断按钮：「US$2.99 一次买断」，没拿到价格时只写「一次买断」。
    var buyTitle: String {
        guard let price = displayPrice else { return L("一次买断", "Buy once", "買い切りで購入") }
        return L("\(price) 一次买断", "Buy once for \(price)", "\(price) で買い切り")
    }

    /// 「¥18 解锁」，没拿到价格时只写「解锁」。
    var unlockTitle: String {
        guard let price = displayPrice else { return L("解锁", "Unlock", "購入") }
        return L("\(price) 解锁", "Unlock \(price)", "\(price) で購入")
    }

    /// App 启动和回到前台时调用：读试用开始了没有、买过没有，更新键盘能看到的记录。
    func refresh() async {
        if case .verified(let app) = try? await AppTransaction.shared {
            AIAccess.recordStoreEnvironment(app.environment.rawValue)
            #if !DEBUG
            // 沙盒（TestFlight、App 审核）也按 App Store 的记录走，不再自动算已解锁：审核要能看到试用和购买流程，
            // 测试的人在沙盒里买是免费的。以前版本自动解锁时写下的状态清掉。
            if app.environment == .production ? AIAccess.debugValue != nil : AIAccess.debugValue == AIAccess.testFlightUnlock {
                AIAccess.setDebug(nil)
            }
            #endif
        }
        var purchased: Date?
        if case .verified(let transaction)? = await Transaction.currentEntitlement(for: AIAccess.productID),
           transaction.revocationDate == nil {
            purchased = transaction.purchaseDate
        }
        AIAccess.recordPurchase(unlocked: purchased != nil, date: purchased)
        // 试用商品：有记录就从它的购买日算；退款了当没领过。
        var trialStart: Date?
        if case .verified(let transaction)? = await Transaction.currentEntitlement(for: AIAccess.trialProductID),
           transaction.revocationDate == nil {
            trialStart = transaction.purchaseDate
        }
        AIAccess.recordTrial(start: trialStart)
        access = AIAccess.current
        if product == nil || trialProduct == nil {
            let products = (try? await Product.products(for: [AIAccess.productID, AIAccess.trialProductID])) ?? []
            if product == nil { product = products.first { $0.id == AIAccess.productID } }
            if trialProduct == nil { trialProduct = products.first { $0.id == AIAccess.trialProductID } }
        }
    }

    /// 「开始 14 天免费试用」：买 0 元的试用商品。系统会弹购买确认（价格 0）。
    func startTrial() async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            if trialProduct == nil {
                trialProduct = try await Product.products(for: [AIAccess.trialProductID]).first
            }
            guard let trialProduct else {
                message = .unavailable
                return
            }
            switch try await trialProduct.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
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

    func buy() async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            if product == nil { product = try await Product.products(for: [AIAccess.productID]).first }
            // 没抛错但列表是空的：网是通的，App Store 没给这个商品，不能说成连不上。
            guard let product else {
                message = .unavailable
                return
            }
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
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
