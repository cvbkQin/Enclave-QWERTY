import SwiftUI
import UIKit

// 设置 › 数据 › 备份与恢复 最上面的 iCloud 同步（设计 design/icloud-sync/IC1–IC4，文案见那里的说明.md）。
// 只在带 iCloud 能力的包里出现（ICloudSync.isAvailable，ICLOUD_SYNC = YES）。

enum SyncColor {
    static let blue = Color(light: 0x2F7BF6, dark: 0x5EA0FF)
    static let orange = Color(light: 0xF29B0C, dark: 0xF5B041)
    /// 状态行、说明块的橙字。
    static let warn = Color(light: 0xD97706, dark: 0xF2A65E)
    /// 说明块的浅橙底。
    static let note = Color(light: 0xFDEBD8, dark: 0x3A2612)
    static let ok = Color(light: 0x2BB673, dark: 0x4CD38A)
    static let grey = Color(light: 0xAEAEB2, dark: 0x5A5A60)
}

/// 设置页这一块的状态：开关、Key 同步、设备。同步本身的进度在 ICloudSyncMonitor。
@MainActor
final class ICloudSyncModel: ObservableObject {
    @Published private(set) var switchOn = ICloudSync.isSwitchOn
    @Published private(set) var paused = ICloudSync.isPaused
    @Published private(set) var keysOn = Keychain.syncsToICloud
    @Published private(set) var keyCount = 0
    /// 这台登录了 iCloud、飞地的 iCloud 没被关掉。查不出来时当能用。
    @Published var accountOK = true
    /// 打开开关后正在看 iCloud 里有没有别的设备的数据。
    @Published private(set) var probing = false
    /// 打开 Key 同步前正在同步、看 iCloud 里有没有别的设备的接口方案（⑪b）。
    @Published private(set) var keyProbing = false
    @Published private(set) var devices: [ICloudSync.Device] = []
    private var refreshNumber = 0

    /// 开关马上读（只是共享设置）；Key 个数、设备列表要读钥匙串、状态文件和每台设备的记录，放到后台（04 复审 B13）。
    func refresh() {
        switchOn = ICloudSync.isSwitchOn
        paused = ICloudSync.isPaused
        keysOn = Keychain.syncsToICloud
        refreshNumber += 1
        let number = refreshNumber
        Task {
            let devices = await ICloudSync.devices()
            let count = await Task.detached(priority: .userInitiated) {
                Keychain.syncedCount(accounts: BackupService.keyAccounts())
            }.value
            guard number == refreshNumber else { return }
            self.devices = devices
            keyCount = count
        }
    }

    /// 没有 iCloud 能力的包不查（会碰 CKContainer 闪退，04 复审 B1）。
    func checkAccount() async {
        guard ICloudSync.isAvailable else { return }
        accountOK = await ICloudSync.accountAvailable()
    }

    func probe() async -> ICloudSyncEngine.Probe {
        probing = true
        defer { probing = false }
        return await ICloudSyncEngine.shared.probe()
    }

    func enable(preferLocal: Bool) {
        ICloudSync.enable(preferLocal: preferLocal)
        started()
    }

    func resume() {
        ICloudSync.resume()
        started()
    }

    private func started() {
        UIApplication.shared.registerForRemoteNotifications()
        ICloudSyncScheduler.schedule()
        refresh()
        // 关了马上又开时，上一轮可能还在跑：等它跑完再跑一轮，重新加入在新的这一轮里做（04 复审 B9）。
        Task {
            _ = await ICloudSyncEngine.shared.run(again: true)
            refresh()
        }
    }

    func syncNow() {
        Task {
            await ICloudSync.syncNow()
            refresh()
        }
    }

    func disable() {
        ICloudSync.disable()
        ICloudSyncScheduler.schedule()
        ICloudSyncMonitor.shared.reset()
        refresh()
    }

    struct KeychainLocked: Error {}

    /// 关闭并删除 iCloud 里的数据（⑩）。removeKeys（「连 Key 一起删除」）：本机配的 Key 先复制回本机版，再从 iCloud 钥匙串
    /// 删掉，其他设备上的也会没有；钥匙串这会儿读不了时什么都不做，抛 KeychainLocked。
    func disableAndDelete(removeKeys: Bool) async throws {
        if removeKeys {
            guard Keychain.disableSync(accounts: BackupService.keyAccounts(), removeFromICloud: true) else { throw KeychainLocked() }
        }
        disable()
        try await ICloudSyncEngine.shared.deleteAll()
        refresh()
    }

    /// 打开 Key 同步前看 iCloud 里有没有别的设备的接口方案：有就问用哪边（⑪b），没有就 ⑪，没同步成就报错不往下走。
    enum KeyJoin {
        case empty
        case owner(name: String, date: Date)
        case failed(String)
    }

    /// 先同步一次再看（04 三审第 3 条）：没同步成时缓存可能是空的，当成「没有别的设备」就会弹 ⑪，点「同步」等于
    /// 选了「用这台的」，这台的 Key 和接口盖到所有设备。每次都真跑一轮（有一轮在跑就等它跑完再来一轮）：
    /// 这一轮 Key 同步还关着，会清掉上次的接口记录，刚关了 Key 同步马上又开时 ⑪b 的选择也算数（三审可选 6）。
    func keyJoin() async -> KeyJoin {
        guard ICloudSync.isEnabled else { return .failed(SyncText.keysOnFailed(nil)) }
        keyProbing = true
        defer { keyProbing = false }
        let status = await ICloudSyncEngine.shared.run(again: true)
        guard status.result == .ok || status.result == .keyboardBusy else { return .failed(SyncText.keysOnFailed(status.result)) }
        if let owner = await ICloudSyncEngine.shared.endpointOwner() { return .owner(name: owner.name, date: owner.date) }
        return .empty
    }

    /// 打开 Key 同步。useICloud：iCloud 里已经有别的设备的接口方案、选了「用 iCloud 里的」（⑪b）：本机的 Key 不往 iCloud 钥匙串写，
    /// 接口等那台的 Key 到了再换成那台的。否则（⑪，或 ⑪b 选了「用这台的」）这台的 Key 写进 iCloud 钥匙串，接口用这台的。
    /// 钥匙串这会儿读不了（开机后还没解锁过）时返回 false，开关不动。
    /// 暂停（换了 Apple 账户）或同步关着时不开，免得 Key 写进新账户的 iCloud 钥匙串（04 复审 B3）。
    func enableKeys(useICloud: Bool) -> Bool {
        guard ICloudSync.isEnabled else {
            refresh()
            return true
        }
        let ok = Keychain.enableSync(accounts: BackupService.keyAccounts(), iCloudWins: useICloud)
        if ok { ICloudSync.prefersLocalEndpoint = !useICloud }
        refresh()
        if ok { syncNow() }
        return ok
    }

    func disableKeys(removeFromICloud: Bool) -> Bool {
        let ok = Keychain.disableSync(accounts: BackupService.keyAccounts(), removeFromICloud: removeFromICloud)
        if ok { ICloudSync.prefersLocalEndpoint = false }
        refresh()
        // 接口不再跟着同步：下一次同步把本机这份从 iCloud 的设备记录里去掉。
        if ok { syncNow() }
        return ok
    }

    func removeDevice(_ device: ICloudSync.Device) async throws {
        try await ICloudSyncEngine.shared.removeDevice(device.id)
        refresh()
    }

    func rename(_ name: String) {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines) != ICloudSync.deviceName else { return }
        ICloudSync.deviceName = name
        refresh()
        if ICloudSync.isEnabled { syncNow() }
    }
}

enum SyncText {
    /// 「iPhone」「iPad」：弹窗里说「这台 iPhone」。
    @MainActor static var model: String { UIDevice.current.model }

    /// 打开 Key 同步前那次同步没成（04 三审第 3 条）：「没能打开 Key 同步」弹窗的正文，第一句写原因，第二句固定（02 说明「打开 Key 同步失败」）。
    @MainActor static func keysOnFailed(_ result: ICloudSyncStatus.Result?) -> String {
        let reason: String
        switch result {
        case .newerFormat:
            reason = L("有设备装了更新版本的飞地，先把这台也更新到最新版再打开。",
                       "A device has a newer version of Enclave. Update this device to the latest version first, then turn this on.",
                       "新しいバージョンの Enclave を使っているデバイスがあります。このデバイスも最新版に更新してからオンにしてください。")
        case .quotaExceeded:
            reason = L("iCloud 空间不够。去 iPhone 设置 › Apple 账户 › iCloud 清出一些空间，或者升级 iCloud+。",
                       "Not enough iCloud storage. Free up some space in Settings › Apple Account › iCloud, or upgrade to iCloud+.",
                       "iCloud の容量が足りません。設定 › Apple アカウント › iCloud で空き容量を増やすか、iCloud+ にアップグレードしてください。")
        case .noAccount:
            reason = L("这台 \(model) 没有登录 iCloud。", "This \(model) isn't signed in to iCloud.", "この \(model) は iCloud にサインインしていません。")
        default:
            reason = L("网络不通，没能确认 iCloud 里有没有别的设备的接口方案。联网后再打开一次。",
                       "No connection, so we couldn't check whether iCloud has API setups from your other devices. Try again when you're online.",
                       "ネットワークにつながらず、iCloud にほかのデバイスの API の設定があるか確認できませんでした。オンラインのときにもう一度オンにしてください。")
        }
        return reason + L("Key 同步还是关着，这台的 Key 不受影响。", " Key sync is still off, and this device's keys aren't affected.",
                          "キーの同期はオフのままで、このデバイスのキーはそのままです。")
    }

    /// 关同步时没删掉 iCloud 里的数据（⑩）：前半句固定，后半句按原因换（02 四审改文案）。
    @MainActor static func deleteFailed(_ failure: ICloudSyncFailure) -> String {
        let head = L("同步已经关了，但 iCloud 里的数据没删掉", "Sync is off, but the data in iCloud wasn't deleted", "同期はオフになりましたが、iCloud のデータは削除できませんでした")
        let tail: String
        switch failure {
        case .network:
            tail = L("：网络不通。联网后打开同步再关一次，选「关闭并删除 iCloud 里的数据」。",
                     ": no connection. When you're online, turn sync on and off again and choose “Turn Off and Delete iCloud Data”.",
                     "：ネットワークにつながりません。オンラインのときに同期をもう一度オンにしてからオフにし、「オフにして iCloud のデータを削除」を選んでください。")
        case .locked:
            tail = L("：\(model) 还没解锁过。解锁后打开同步再关一次，选「关闭并删除 iCloud 里的数据」。",
                     ": your \(model) hasn't been unlocked yet. After unlocking, turn sync on and off again and choose “Turn Off and Delete iCloud Data”.",
                     "：\(model) のロックがまだ解除されていません。ロックを解除してから同期をもう一度オンにしてからオフにし、「オフにして iCloud のデータを削除」を選んでください。")
        case .accountChanged:
            tail = L("：现在登录的是另一个账户。换回原来的账户后，打开同步再关一次，选「关闭并删除 iCloud 里的数据」。",
                     ": a different account is signed in now. Switch back to the original account, then turn sync on and off again and choose “Turn Off and Delete iCloud Data”.",
                     "：今は別のアカウントでサインインしています。元のアカウントに戻してから同期をもう一度オンにしてからオフにし、「オフにして iCloud のデータを削除」を選んでください。")
        case .other:
            tail = L("：iCloud 暂时出错。稍后打开同步再关一次，选「关闭并删除 iCloud 里的数据」。",
                     ": iCloud had a temporary error. Later, turn sync on and off again and choose “Turn Off and Delete iCloud Data”.",
                     "：iCloud で一時的なエラーが起きました。しばらくしてから同期をもう一度オンにしてからオフにし、「オフにして iCloud のデータを削除」を選んでください。")
        }
        return head + tail
    }

    /// 状态行和设备页的时间：一分钟内「刚刚」，一天内「N 分钟前」「N 小时前」，再早写日期和时间。
    static func time(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return L("刚刚", "just now", "たった今") }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return L("\(minutes) 分钟前", "\(minutes) min ago", "\(minutes) 分前")
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return L("\(hours) 小时前", "\(hours) hr ago", "\(hours) 時間前")
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// 超过 30 天没同步：「两个多月没同步」。没超过是 nil。
    static func stale(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let days = Int(now.timeIntervalSince(date) / 86400)
        guard days >= 30 else { return nil }
        let months = days / 30
        if months >= 12 { return L("一年多没同步", "not synced for over a year", "1 年以上同期していません") }
        let chinese = ["一", "两", "三", "四", "五", "六", "七", "八", "九", "十", "十一"][months - 1]
        return L("\(chinese)个多月没同步", months == 1 ? "not synced for over a month" : "not synced for over \(months) months",
                 "\(months) か月以上同期していません")
    }

    static var notSynced: String { L("不同步：接口 Key（下面单独开）、AI 历史、英文学到的词、模糊音和双拼、键盘布局、声音和外观、剪贴板记录、购买和试用。在键盘里删掉一个学到的词，只对这台设备生效。",
                             "Not synced: API keys (turn on below), AI history, learned English words, fuzzy pinyin and double pinyin, keyboard layout, sound and appearance, clipboard history, purchases and trial. Removing a learned word in the keyboard only affects this device.",
                             "同期しないもの：API キー（下で個別にオン）、AI 履歴、英語の学習語、あいまい入力と双拼、キーボード配列、サウンドと外観、クリップボード履歴、購入と試用。キーボードで学習語を削除しても、このデバイスだけに反映されます。") }
}

/// 备份与恢复页最上面的几组：同步卡片；开着时再加「同步的内容」、Key 开关和设备（IC1、IC2 ⑤）。
struct ICloudSyncSections: View {
    @ObservedObject var model: ICloudSyncModel
    @ObservedObject private var monitor = ICloudSyncMonitor.shared
    /// 学到的词个数（备份页算好的，算不出来是「—」）、常用词和键盘常用语个数。
    var learned: String
    var words: Int
    var phrases: Int

    @State private var join: JoinPrompt?
    @State private var confirmOff = false
    @State private var confirmDelete = false
    @State private var confirmKeysOn = false
    @State private var keyJoin: JoinPrompt?
    @State private var confirmKeysOff = false
    @State private var failure: String?
    /// 打开 Key 同步前那次同步没成（04 三审第 3 条）。
    @State private var keysOnFailure: String?

    private struct JoinPrompt: Equatable {
        var name: String
        var date: Date
    }

    /// 暂停（换了 Apple 账户）时只留卡片：同步的内容、Key 开关、设备都不显示，免得在新账户里开 Key 同步（04 复审 B3）。
    private var showsDetail: Bool { (model.switchOn || model.probing) && model.accountOK && !model.paused }

    private var keychainLocked: String {
        L("钥匙串这会儿读不了。解锁 \(SyncText.model) 后再试一次。", "The keychain can't be read right now. Unlock your \(SyncText.model) and try again.",
          "今はキーチェーンを読み込めません。\(SyncText.model) のロックを解除してからもう一度お試しください。")
    }

    var body: some View {
        Section {
            card
                .alert(L("iCloud 里已经有飞地的设置", "Enclave settings are already in iCloud", "iCloud にすでに Enclave の設定があります"),
                       isPresented: Binding(get: { join != nil }, set: { if !$0 { join = nil } }), presenting: join) { _ in
                    Button(L("用 iCloud 里的（推荐）", "Use iCloud's (Recommended)", "iCloud のものを使う（おすすめ）")) {
                        model.enable(preferLocal: false)
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(L("用这台 \(SyncText.model) 的", "Use This \(SyncText.model)'s", "この \(SyncText.model) のものを使う")) {
                        model.enable(preferLocal: true)
                    }
                    Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
                } message: { join in
                    // 加入时 Key 同步一定关着，接口方案不参与，只问风格（02 复审第 4 条；接口在 ⑪b 问）。
                    Text(L("来自「\(join.name)」，\(Loc.monthDay(join.date))。学到的词和常用词两边都会留着，自动合并。润色和问答风格只能留一份：",
                           "From “\(join.name)”, \(Loc.monthDay(join.date)). Learned words and your words are kept on both sides and merged. Polish and answer styles can only keep one copy:",
                           "「\(join.name)」から（\(Loc.monthDay(join.date))）。学習した語とユーザ辞書は両方残して自動で統合します。整えるスタイルと回答スタイルはどちらか一方だけ残せます："))
                }
                .confirmationDialog(L("关闭 iCloud 同步", "Turn Off iCloud Sync", "iCloud 同期をオフにする"), isPresented: $confirmOff, titleVisibility: .visible) {
                    Button(L("关闭，保留 iCloud 里的", "Turn Off, Keep iCloud Data", "オフにして iCloud のデータを残す")) { model.disable() }
                    // 暂停时（换了 Apple 账户）不给删：删的会是新账户里的数据（04 复审 B8）。
                    if !model.paused {
                        Button(L("关闭并删除 iCloud 里的数据", "Turn Off and Delete iCloud Data", "オフにして iCloud のデータを削除"), role: .destructive) {
                            // 操作表收起后再弹确认，不然系统会忽略这次弹出。
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { confirmDelete = true }
                        }
                    }
                    Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
                } message: {
                    Text(offMessage)
                }
                .alert(L("删除 iCloud 里飞地的数据？", "Delete Enclave's data in iCloud?", "iCloud の Enclave のデータを削除しますか？"), isPresented: $confirmDelete) {
                    if model.keysOn {
                        // Key 同步开着：Key 在 iCloud 钥匙串里，问要不要一起删（02 复审第 6 条）。
                        Button(L("删除数据，保留 Key", "Delete Data, Keep Keys", "データを削除してキーは残す")) { deleteAll(removeKeys: false) }
                        Button(L("连 Key 一起删除", "Delete Data and Keys", "キーも一緒に削除"), role: .destructive) { deleteAll(removeKeys: true) }
                    } else {
                        Button(L("删除", "Delete", "削除"), role: .destructive) { deleteAll(removeKeys: false) }
                    }
                    Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
                } message: {
                    Text(L("其他设备也同步不到这些数据了；如果它们还开着同步，会把自己的那份重新传上去。每台设备本机的词和设置都不受影响。",
                           "Other devices can't get this data anymore. If they still have sync on, they'll upload their own copy again. Words and settings on each device aren't affected.",
                           "ほかのデバイスもこのデータを同期できなくなります。同期をオンにしたままのデバイスは自分の分をもう一度アップロードします。各デバイスの語と設定には影響しません。")
                         + (model.keysOn
                            ? L("接口 Key 存在 iCloud 钥匙串里，要不要一起删？一起删的话，其他设备上的 Key 也会没有。",
                                " API keys are in iCloud Keychain. Delete them too? If you do, the keys on your other devices will be gone as well.",
                                "API キーは iCloud キーチェーンにあります。一緒に削除しますか？削除すると、ほかのデバイスのキーもなくなります。")
                            : ""))
                }
                .alert(L("没能完成", "Couldn't finish", "完了できませんでした"),
                       isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                    Button(L("好", "OK", "OK"), role: .cancel) {}
                } message: {
                    Text(failure ?? "")
                }
                .alert(L("没能打开 Key 同步", "Couldn't Turn On Key Sync", "キーの同期をオンにできませんでした"),
                       isPresented: Binding(get: { keysOnFailure != nil }, set: { if !$0 { keysOnFailure = nil } })) {
                    Button(L("好", "OK", "OK"), role: .cancel) {}
                } message: {
                    Text(keysOnFailure ?? "")
                }
        }
        if showsDetail {
            Section {
                SyncedItemRow(title: L("学到的词", "Learned words", "学習した語"),
                              detail: L("打字时记住的词和顺序", "Words and order remembered as you type", "入力中に覚えた語と順番"), value: learned)
                SyncedItemRow(title: L("常用词 · 键盘常用语", "Your words · Phrases", "ユーザ辞書 · 定型文"), detail: nil,
                              value: "\(words.formatted()) · \(phrases.formatted())")
                if !BuiltinAPI.available {
                    SyncedItemRow(title: model.keysOn
                                  ? L("AI 接口和风格", "AI settings and styles", "AI の設定とスタイル")
                                  : L("润色和问答风格", "Polish and answer styles", "整えるスタイルと回答スタイル"),
                                  detail: aiDetail, value: nil)
                }
            } header: {
                Text(L("同步的内容", "What syncs", "同期する内容"))
            }
            Section {
                if !BuiltinAPI.available { keyRow }
                NavigationLink {
                    ICloudDevicesView(model: model)
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemName: "iphone", color: SyncColor.blue)
                        Text(L("设备", "Devices", "デバイス"))
                        Spacer(minLength: 8)
                        Text(L("\(model.devices.count) 台", "\(model.devices.count)", "\(model.devices.count) 台")).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(SyncText.notSynced)
            }
        }
    }

    // MARK: 卡片（IC1 ①–③、IC2 ⑤）

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "icloud")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(model.accountOK ? SyncColor.blue : SyncColor.grey)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((model.accountOK ? SyncColor.blue : SyncColor.grey).opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(L("iCloud 同步", "iCloud Sync", "iCloud 同期")).font(.headline)
                        if !model.switchOn && model.accountOK { NewBadge() }
                    }
                    statusLine.font(.footnote)
                }
                Spacer(minLength: 8)
                if model.accountOK {
                    Toggle("", isOn: Binding(get: { model.switchOn || model.probing }, set: { on in
                        if on { turnOn() } else { confirmOff = true }
                    }))
                        .labelsHidden()
                        .tint(DashColor.ok)
                        .disabled(model.probing)
                } else {
                    // 没登录或受限：没开着就不能开；开着的照样能关（04 复审 B10）。
                    Toggle("", isOn: Binding(get: { model.switchOn }, set: { on in if !on { confirmOff = true } }))
                        .labelsHidden()
                        .tint(DashColor.ok)
                        .disabled(!model.switchOn)
                }
            }
            if !model.accountOK {
                Divider()
                Button(L("打开 iPhone 设置 ›", "Open iPhone Settings ›", "iPhone の設定を開く ›")) { AppSettings.open() }
                    .font(.subheadline)
                    .foregroundStyle(AppColor.purple)
                    .buttonStyle(.borderless)
            } else if !model.switchOn && !model.probing {
                Divider()
                Text(L("打开后，学到的词、常用词、AI 接口和风格会在你的 iPhone、iPad 之间保持一致。",
                       "When on, learned words, your words, AI settings and styles stay the same on your iPhone and iPad.",
                       "オンにすると、学習した語、ユーザ辞書、AI の設定とスタイルが iPhone と iPad で同じになります。"))
                    .font(.footnote).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.shield").foregroundStyle(SyncColor.ok)
                    (Text(L("端到端加密", "End-to-end encrypted", "エンドツーエンド暗号化")).fontWeight(.semibold).foregroundColor(.primary)
                     + Text(L("：存在你自己的 iCloud 里，我们和 Apple 都看不到。", ": stored in your own iCloud. Neither we nor Apple can see it.",
                              "：あなた自身の iCloud に保存され、私たちも Apple も見ることはできません。")))
                }
                .font(.footnote).foregroundStyle(.secondary)
            } else {
                if let note { noteBox(note) }
                if model.paused {
                    Button(L("在这个账户继续同步", "Keep Syncing with This Account", "このアカウントで同期を続ける")) { model.resume() }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { model.syncNow() } label: {
                        Label(L("立即同步", "Sync Now", "今すぐ同期"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(BackupSoftButtonStyle())
                    .disabled(syncing)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var syncing: Bool { monitor.running || model.probing || model.keyProbing }

    /// ⑨ 的说明：Key 同步开着时加一句（02 复审第 6 条）；暂停时不问删不删（只给「关闭」）。
    private var offMessage: String {
        var text = L("这台 \(SyncText.model) 上的词和设置都留着，只是不再同步。", "Words and settings on this \(SyncText.model) stay; they just stop syncing.",
                     "この \(SyncText.model) の語と設定はそのまま残り、同期だけ止まります。")
        if model.keysOn && !model.paused {
            text += L("接口 Key 也会停止同步，这台留一份本机的。", " API keys stop syncing too; this device keeps its own copy.",
                      "API キーの同期も止まり、このデバイスにはキーのコピーが残ります。")
        }
        if !model.paused {
            text += L("iCloud 里的数据要一起删掉吗？", " Delete the data in iCloud too?", "iCloud のデータも削除しますか？")
        }
        return text
    }

    @ViewBuilder private var statusLine: some View {
        if !model.accountOK {
            Text(L("这台 \(SyncText.model) 没有登录 iCloud", "This \(SyncText.model) isn't signed in to iCloud", "この \(SyncText.model) は iCloud にサインインしていません"))
                .foregroundStyle(SyncColor.warn)
        } else if !model.switchOn && !model.probing {
            Text(L("在登录同一个 Apple 账户的设备之间同步", "Syncs between devices signed in to the same Apple Account", "同じ Apple アカウントのデバイス間で同期"))
                .foregroundStyle(.secondary)
        } else if syncing {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                Text(L("正在同步…", "Syncing…", "同期中…"))
            }
            .foregroundStyle(.secondary)
        } else if model.paused {
            Text(L("已暂停：换了 Apple 账户", "Paused: Apple Account changed", "一時停止中：Apple アカウントが変わりました")).foregroundStyle(SyncColor.warn)
        } else if let status = monitor.status {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                statusText(status, now: context.date)
            }
        } else {
            Text(L("还没同步", "Not synced yet", "まだ同期していません")).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func statusText(_ status: ICloudSyncStatus, now: Date) -> some View {
        let time = SyncText.time(status.at, now: now)
        switch status.result {
        case .ok:
            dotLine(SyncColor.ok, L("已同步 · \(time)", "Synced · \(time)", "同期済み · \(time)"))
        case .keyboardBusy, .newerFormat:
            dotLine(SyncColor.warn, L("部分同步 · \(time)", "Partly synced · \(time)", "一部同期 · \(time)"))
        case .quotaExceeded:
            Text(L("iCloud 空间不够，没能上传", "Not enough iCloud storage to upload", "iCloud の容量が足りずアップロードできませんでした"))
                .foregroundStyle(SyncColor.warn)
        case .noAccount:
            Text(L("这台 \(SyncText.model) 没有登录 iCloud", "This \(SyncText.model) isn't signed in to iCloud", "この \(SyncText.model) は iCloud にサインインしていません"))
                .foregroundStyle(SyncColor.warn)
        case .accountChanged:
            Text(L("已暂停：换了 Apple 账户", "Paused: Apple Account changed", "一時停止中：Apple アカウントが変わりました")).foregroundStyle(SyncColor.warn)
        case .failed:
            dotLine(SyncColor.warn, L("没能同步 · \(time)", "Couldn't sync · \(time)", "同期できませんでした · \(time)"))
        }
    }

    private func dotLine(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }

    /// 卡片里的浅橙说明块（IC2 ⑤）。
    private var note: String? {
        if model.paused {
            return L("iCloud 里换成了另一个账户。为了不把这台的词合并进别人的账户，同步先停了；确认是你的账户后再打开。",
                     "iCloud is now signed in to a different account. Sync is paused so this device's words aren't merged into someone else's account. Continue once you've confirmed it's yours.",
                     "iCloud が別のアカウントに変わりました。このデバイスの語をほかの人のアカウントに統合しないよう、同期を止めています。自分のアカウントだと確認してから続けてください。")
        }
        guard !syncing, let status = monitor.status else { return nil }
        switch status.result {
        case .keyboardBusy:
            return L("键盘正在用拼音词库，这次没合并学到的词；收起键盘后会再同步。",
                     "The keyboard is using the pinyin dictionary, so learned words weren't merged this time. They'll sync after the keyboard closes.",
                     "キーボードがピンイン辞書を使用中のため、今回は学習した語を統合しませんでした。キーボードを閉じたあとにもう一度同期します。")
        case .newerFormat:
            return L("有设备装了更新版本的飞地，它的内容这次没合并；把这台也更新到最新版就好。",
                     "A device has a newer version of Enclave, so its data wasn't merged. Update this device to the latest version.",
                     "新しいバージョンの Enclave を使っているデバイスがあり、その内容は統合しませんでした。このデバイスも最新版に更新してください。")
        case .failed:
            // 按原因换（02 四审改文案）：网络不通、还没解锁过、其他 iCloud 错误。换了账户走「已暂停」。
            switch status.detail ?? "" {
            case ICloudSyncFailure.networkDetail:
                return L("检查网络后点「立即同步」再试一次。", "Check your connection, then tap Sync Now to try again.",
                         "ネットワークを確認してから「今すぐ同期」をタップして、もう一度お試しください。")
            case "locked":
                return L("\(SyncText.model) 解锁后会自动再同步。", "Sync will try again after you unlock your \(SyncText.model).",
                         "\(SyncText.model) のロックを解除すると、自動でもう一度同期します。")
            default:
                return L("iCloud 暂时出错，稍后点「立即同步」再试。", "iCloud had a temporary error. Tap Sync Now again later.",
                         "iCloud で一時的なエラーが起きました。しばらくしてから「今すぐ同期」をタップしてください。")
            }
        case .quotaExceeded:
            return L("iPhone 设置 › Apple 账户 › iCloud 里清出一些空间，或者升级 iCloud+。",
                     "Free up some space in Settings › Apple Account › iCloud, or upgrade to iCloud+.",
                     "設定 › Apple アカウント › iCloud で空き容量を増やすか、iCloud+ にアップグレードしてください。")
        default:
            return nil
        }
    }

    private func noteBox(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(SyncColor.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SyncColor.note))
    }

    /// AI 接口和风格那一行的小字：接口方案只在 Key 也同步时同步（04 审查 #75 第 2 条），关着时说清楚。
    private var aiDetail: String {
        model.keysOn
            ? L("接口方案、润色风格、问答风格；以最后改的那台为准", "API setups, polish and answer styles. The last device to change them wins.",
                "API の設定、整えるスタイル、回答スタイル。最後に変更したデバイスが優先されます。")
            : L("润色风格、问答风格；以最后改的那台为准。接口方案要和 Key 一起同步（下面打开）",
                "Polish and answer styles. The last device to change them wins. API setups sync together with keys (turn on below).",
                "整えるスタイルと回答スタイル。最後に変更したデバイスが優先されます。API の設定はキーと一緒に同期します（下でオン）。")
    }

    // MARK: 同步接口 Key（IC1 ④、IC3 ⑪、IC4 ⑫）

    private var keyRow: some View {
        Toggle(isOn: Binding(get: { model.keysOn || model.keyProbing }, set: { on in
            if on { keysOnTapped() } else { confirmKeysOff = true }
        })) {
            HStack(spacing: 12) {
                TintIcon(systemName: "key", color: SyncColor.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("同步接口 Key", "Sync API Keys", "API キーを同期"))
                    Text(keyCaption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(DashColor.ok)
        .disabled(model.keyProbing)
        // ⑪：iCloud 里没有别的设备的接口方案（02 复审第 4 条）。
        .alert(L("同步接口 Key？", "Sync API keys?", "API キーを同期しますか？"), isPresented: $confirmKeysOn) {
            Button(L("同步", "Sync", "同期")) { enableKeys(useICloud: false) }
                .keyboardShortcut(.defaultAction)
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(L("打开后，接口方案会和 Key 一起同步到登录同一 Apple 账户的设备：接口方案跟着 iCloud 同步，Key 走 iCloud 钥匙串，都是端到端加密。开着时，在任何一台上删掉一个接口方案，其他设备上它的 Key 也会一起删掉。要先在 iPhone 设置里打开「密码」的 iCloud 同步。",
                   "API setups sync together with their keys to devices signed in to the same Apple Account: setups sync with iCloud, keys go through iCloud Keychain, both end-to-end encrypted. While on, deleting an API setup on any device also deletes its key on the others. Turn on iCloud sync for Passwords in Settings first.",
                   "オンにすると、API の設定がキーと一緒に同じ Apple アカウントのデバイスに同期されます。設定は iCloud で、キーは iCloud キーチェーンで同期され、どちらもエンドツーエンドで暗号化されます。オンの間は、どれかのデバイスで API の設定を削除すると、ほかのデバイスのキーも削除されます。先に設定で「パスワード」の iCloud 同期をオンにしてください。"))
        }
        // ⑪b：iCloud 里已经有别的设备的接口方案，这时才是接口第一次加入，问用哪边（02 复审第 4 条）。
        .alert(L("同步接口 Key 和接口方案？", "Sync API keys and setups?", "API キーと API の設定を同期しますか？"),
               isPresented: Binding(get: { keyJoin != nil }, set: { if !$0 { keyJoin = nil } }), presenting: keyJoin) { _ in
            Button(L("用 iCloud 里的（推荐）", "Use iCloud's (Recommended)", "iCloud のものを使う（おすすめ）")) { enableKeys(useICloud: true) }
                .keyboardShortcut(.defaultAction)
            Button(L("用这台 \(SyncText.model) 的", "Use This \(SyncText.model)'s", "この \(SyncText.model) のものを使う")) { enableKeys(useICloud: false) }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: { owner in
            // 方案列表逐条合并、两边都留，只有正在用的接口选一边（02 三审改文案，三审可选 8）。
            Text(L("打开后，接口方案跟着 iCloud 同步，Key 走 iCloud 钥匙串，都是端到端加密。iCloud 里已经有「\(owner.name)」的接口方案（\(Loc.monthDay(owner.date))）。两边的方案都会留着，正在用的接口只能选一边：",
                   "API setups sync with iCloud and keys go through iCloud Keychain, both end-to-end encrypted. iCloud already has API setups from “\(owner.name)” (\(Loc.monthDay(owner.date))). Setups from both are kept, but the API in use can come from only one:",
                   "オンにすると、API の設定は iCloud で、キーは iCloud キーチェーンで同期され、どちらもエンドツーエンドで暗号化されます。iCloud にはすでに「\(owner.name)」の API の設定があります（\(Loc.monthDay(owner.date))）。両方の設定が残りますが、使用中の API はどちらか一方だけ選べます："))
        }
        .confirmationDialog(L("关闭接口 Key 同步", "Turn Off API Key Sync", "API キーの同期をオフにする"), isPresented: $confirmKeysOff, titleVisibility: .visible) {
            Button(L("只在这台关闭", "Turn Off on This Device", "このデバイスだけオフにする")) { keysOff(removeFromICloud: false) }
            Button(L("同时从 iCloud 钥匙串删除", "Also Delete from iCloud Keychain", "iCloud キーチェーンからも削除"), role: .destructive) { keysOff(removeFromICloud: true) }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(L("这台 \(SyncText.model) 上的 Key 会留一份本机的，以后不再同步。从 iCloud 钥匙串删除的话，其他设备上的 Key 也会删掉。",
                   "This \(SyncText.model) keeps its own copy of the keys and stops syncing them. Deleting them from iCloud Keychain also deletes them on your other devices.",
                   "この \(SyncText.model) にはキーのコピーが残り、以後は同期しません。iCloud キーチェーンから削除すると、ほかのデバイスのキーも削除されます。"))
        }
    }

    /// Key 那一行的小字（IC1 ④）；开着时加删方案连带删 Key 的提醒（02 复审第 4 条：⑪b 里没写，放在这里）。
    private var keyCaption: String {
        guard model.keysOn else {
            return L("通过 iCloud 钥匙串，端到端加密", "Through iCloud Keychain, end-to-end encrypted", "iCloud キーチェーンで、エンドツーエンド暗号化")
        }
        let count = model.keyCount > 0
            ? L("\(model.keyCount) 个 Key 通过 iCloud 钥匙串同步", "\(model.keyCount) keys sync with iCloud Keychain", "\(model.keyCount) 個のキーを iCloud キーチェーンで同期")
            : L("通过 iCloud 钥匙串，端到端加密", "Through iCloud Keychain, end-to-end encrypted", "iCloud キーチェーンで、エンドツーエンド暗号化")
        return count + "\n" + L("开着时删掉一个接口方案，其他设备上它的 Key 也会删掉", "Deleting an API setup while this is on also deletes its key on your other devices",
                                 "オンの間に API の設定を削除すると、ほかのデバイスのキーも削除されます")
    }

    /// 打开 Key 同步：先同步一次看 iCloud 里有没有别的设备的接口方案，有就问用哪边（⑪b），没有就 ⑪。
    private func keysOnTapped() {
        Task {
            switch await model.keyJoin() {
            case .owner(let name, let date): keyJoin = JoinPrompt(name: name, date: date)
            case .empty: confirmKeysOn = true
            case .failed(let message): keysOnFailure = message
            }
        }
    }

    private func enableKeys(useICloud: Bool) {
        if !model.enableKeys(useICloud: useICloud) { failure = keychainLocked }
    }

    private func keysOff(removeFromICloud: Bool) {
        if !model.disableKeys(removeFromICloud: removeFromICloud) { failure = keychainLocked }
    }

    // MARK: 打开、关闭

    /// 打开开关：iCloud 里已经有别的设备的数据就问风格和接口用哪份（IC3 ⑧），没有就直接打开。
    private func turnOn() {
        Task {
            switch await model.probe() {
            case .noAccount: model.accountOK = false
            case .empty: model.enable(preferLocal: false)
            case .existing(let name, let date): join = JoinPrompt(name: name, date: date)
            }
        }
    }

    private func deleteAll(removeKeys: Bool) {
        Task {
            do {
                try await model.disableAndDelete(removeKeys: removeKeys)
            } catch is ICloudSyncModel.KeychainLocked {
                // 钥匙串读不了：什么都没动，同步还开着。
                failure = keychainLocked
            } catch {
                // 错误原文只进系统日志（连 Mac 的「控制台」能看到），不放进给用户看的句子里。
                NSLog("ICloudSync: deleteAll failed: %@", String(describing: error))
                failure = SyncText.deleteFailed(ICloudSyncFailure.of(error))
            }
        }
    }
}

/// 「同步的内容」一行：左边绿勾、标题和灰色说明，右边个数。
private struct SyncedItemRow: View {
    var title: String
    var detail: String?
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(SyncColor.ok)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).foregroundStyle(.secondary).monospacedDigit().lineLimit(1) }
        }
    }
}

/// 「这台」小标：和「新」一样大小。
private struct ThisDeviceBadge: View {
    var body: some View {
        Text(L("这台", "This", "この端末"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColor.deepPurple)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(AppColor.chipSelectedFill))
    }
}

// MARK: - 设备页（IC2 ⑥⑦）

struct ICloudDevicesView: View {
    @ObservedObject var model: ICloudSyncModel
    @State private var name = ""
    @State private var removing: ICloudSync.Device?
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                ForEach(model.devices) { device in
                    DeviceRow(device: device) { removing = device }
                        .swipeActions {
                            if !device.isThis {
                                Button { removing = device } label: { Text(L("删除", "Delete", "削除")) }.tint(.red)
                            }
                        }
                }
            } header: {
                Text(L("参与同步的设备", "Syncing devices", "同期しているデバイス"))
            } footer: {
                Text(L("每台设备学到的词都会合并到其他设备。不用的旧设备删掉，它的词就不再合并进来；已经合并进来的词还在。",
                       "Each device's learned words merge into the others. Delete an old device you no longer use to stop merging its words. Words already merged stay.",
                       "各デバイスの学習した語はほかのデバイスに統合されます。使わなくなった古いデバイスを削除すると、その語は統合されなくなります。統合済みの語は残ります。"))
            }
            Section {
                HStack {
                    Text(L("设备名", "Device name", "デバイス名"))
                    TextField(UIDevice.current.name, text: $name)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .onSubmit { model.rename(name) }
                }
            } header: {
                Text(L("这台设备", "This device", "このデバイス"))
            } footer: {
                Text(L("从整机备份恢复的新手机会自动当成一台新设备，不会顶掉旧手机。",
                       "A new iPhone restored from a full backup counts as a new device and won't replace the old one.",
                       "フルバックアップから復元した新しい iPhone は新しいデバイスとして扱われ、古い iPhone と置き換わりません。"))
            }
        }
        .navigationTitle(L("设备", "Devices", "デバイス"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = ICloudSync.deviceName
            model.refresh()
        }
        .onDisappear { model.rename(name) }
        .alert(L("删除「\(removing?.name ?? "")」？", "Delete “\(removing?.name ?? "")”?", "「\(removing?.name ?? "")」を削除しますか？"),
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { device in
            Button(L("删除", "Delete", "削除"), role: .destructive) { remove(device) }
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: { device in
            Text(L("它以后不再参与同步，它学到的词不再合并进来。已经合并到这台的词还在。要是这台 \(device.name) 还开着同步，下次同步时会自己重新加回来。",
                   "It stops syncing and its learned words are no longer merged. Words already merged here stay. If \(device.name) still has sync on, it'll add itself back next time it syncs.",
                   "このデバイスは同期に参加しなくなり、その学習した語は統合されなくなります。統合済みの語は残ります。\(device.name) で同期がオンのままなら、次の同期で自動的に戻ります。"))
        }
        .alert(L("没能删除", "Couldn't delete", "削除できませんでした"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(L("好", "OK", "OK"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func remove(_ device: ICloudSync.Device) {
        Task {
            do {
                try await model.removeDevice(device)
            } catch {
                NSLog("ICloudSync: removeDevice failed: %@", String(describing: error))
                failure = L("网络不通或 iCloud 出错，联网后再试一次。", "No connection or an iCloud error. Try again when you're online.",
                            "ネットワークまたは iCloud のエラーです。オンラインのときにもう一度お試しください。")
            }
        }
    }
}

private struct DeviceRow: View {
    var device: ICloudSync.Device
    var onRemove: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let stale = device.isThis ? nil : SyncText.stale(device.syncedAt, now: context.date)
            HStack(spacing: 12) {
                TintIcon(systemName: device.isPad ? "ipad" : "iphone", color: stale == nil ? SyncColor.blue : SyncColor.grey)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name).lineLimit(1)
                        if device.isThis { ThisDeviceBadge() }
                    }
                    Text(subtitle(stale: stale, now: context.date))
                        .font(.caption)
                        .foregroundStyle(stale == nil ? Color.secondary : SyncColor.warn)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !device.isThis {
                    Button(L("删除", "Delete", "削除"), action: onRemove)
                        .foregroundStyle(Color(hex: 0xE5484D))
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private func subtitle(stale: String?, now: Date) -> String {
        var parts: [String] = []
        if let date = device.syncedAt {
            let time = SyncText.time(date, now: now)
            parts.append(device.isThis && now.timeIntervalSince(date) < 60 ? L("刚刚同步", "Just synced", "たった今同期") : time)
        } else {
            parts.append(L("还没同步", "Not synced yet", "まだ同期していません"))
        }
        if !device.appVersion.isEmpty { parts.append(device.appVersion) }
        if let stale { parts.append(stale) }
        return parts.joined(separator: " · ")
    }
}
