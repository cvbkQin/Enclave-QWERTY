import Combine
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var model = KeyboardModel(controller: self)
    private var heightConstraint: NSLayoutConstraint?
    /// 根视图（UIInputView）。控制器释放后系统还一直留着它（见 tearDown），释放时要找得到它来清空。
    private weak var rootForTeardown: UIView?
    private var cancellables = Set<AnyCancellable>()


    override func viewDidLoad() {
        super.viewDidLoad()
        loadStart = CACurrentMediaTime()
        loadBusy = MainWake.busySinceWake(now: loadStart)
        wakeTracked = MainWake.isInstalled
        MainWake.install()
        MainStalls.start()
        if Self.popupsInProcess == 0, let start = TypingStats.processStartDate {
            loadSinceProcess = Date().timeIntervalSince(start) * 1000
        }
        defer { loadMs = (CACurrentMediaTime() - loadStart) * 1000 }
        snapshotOn = PopupSnapshot.enabled
        // 宿主（连同它的约束）一开始就装上，键盘的视图结构从第一帧起就定了，开不开截图都一样。
        // 「先显示截图」开着时宿主里先放空占位，真键盘的内容留到进了窗口再定（见 viewIsAppearing）。
        installHost(placeholder: snapshotOn)

        // 键盘高度只由这一条必需约束决定。allowsSelfSizing 让系统按我们的约束算高度，
        // 而不是套用它自己的固定高度——否则展开后系统仍按旧高度摆放，面板顶部和最后一排键会被裁掉。
        inputView?.allowsSelfSizing = true
        let height = view.heightAnchor.constraint(equalToConstant: model.keyboardHeight)
        height.priority = .required
        height.isActive = true
        heightConstraint = height
        rootForTeardown = view

        // 展开、卡片展开、风格菜单一改就同步改高度：等到下一轮的话，SwiftUI 先按旧高度画出新内容，
        // 系统再把高度变化做成动画，风格浮层展开时内容会错位、按键被挤到底下。
        model.heightMayChange = { [weak self] in self?.updateHeight() }
        // 其余会影响高度的变化（比如配置好接口后卡片变矮）在下一轮补上。
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHeight() }
            .store(in: &cancellables)

        // 键盘开着时对方 App 退到后台（上滑回桌面、切 App），系统不一定调 viewDidDisappear，扩展直接被挂起；
        // Rime 会话还开着就还锁着 App Group 里的用户词库，挂起时被杀（0xDEAD10CC）。退后台时也关掉，回前台再建。
        NotificationCenter.default.publisher(for: .NSExtensionHostDidEnterBackground)
            .sink { [weak self] _ in self?.releaseEngine() }
            .store(in: &cancellables)
        // 对方要退后台了：这之后（包括随后的 viewDidDisappear）清输入框里下划线拼音那一下会被丢掉，见 releaseEngine。
        NotificationCenter.default.publisher(for: .NSExtensionHostWillResignActive)
            .sink { [weak self] _ in self?.hostInactive = true }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSExtensionHostDidBecomeActive)
            .sink { [weak self] _ in
                self?.hostInactive = false
                // 真机上回前台不一定再走 viewDidAppear，这里也清一次。
                DispatchQueue.main.async {
                    self?.clearStaleMarkedText()
                    self?.model.checkClipboard()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSExtensionHostWillEnterForeground)
            .sink { [weak self] _ in
                guard let self, self.view.window != nil else { return }
                self.model.selectEngine()
            }
            .store(in: &cancellables)
    }

    private var hostInactive = false

    // MARK: 弹出记录（开发版，PopupLog）
    /// 这个进程里弹出过几次。
    private static var popupsInProcess = 0
    /// 控制器建出来的时刻：到 viewDidLoad 之间是系统在准备（热启动时也有）。
    private let createdAt = CACurrentMediaTime()
    /// viewDidLoad 开始时，主线程从上次醒来起醒着干活的合计（毫秒）：和「叫醒到开始建键盘」那一行同一段。
    private var loadBusy: Double = 0
    /// viewDidLoad 之前主线程醒睡就已经在量了（冷启动第一次是在 viewDidLoad 里才装上观察器，那一圈量不全）。
    private var wakeTracked = false
    private var loadStart: CFTimeInterval = 0
    private var loadSinceProcess: Double?
    private var loadMs: Double = 0
    /// 这个控制器第一次弹出时记的一条，viewDidAppear 后补齐再存。
    private var popupRecord: PopupRecord?
    /// 这次弹出途中的几个时刻（第一帧、换下截图、键盘高度变化），每个控制器一份，不会被下一次弹出盖掉。
    private let marks = PopupMarks()
    private var popupRecorded = false

    /// 对方输入框的 documentIdentifier。不能直接读 textDocumentProxy.documentIdentifier：Swift 里它是非可选的 UUID，
    /// 键盘收起时系统还会调一次 textDidChange，这时它是 nil，桥接直接崩（SIGTRAP）。从 0.96_4 起每次收起都崩，
    /// 下次弹出全是冷启动，「弹出变卡」就是这个。这里绕开桥接，按可选值读。
    private var hostDocumentID: UUID? {
        let selector = NSSelectorFromString("documentIdentifier")
        guard textDocumentProxy.responds(to: selector),
              let object = textDocumentProxy.perform(selector)?.takeUnretainedValue() else { return nil }
        return (object as? NSUUID).map { $0 as UUID }
    }
    /// 键盘开着时每秒看一眼 changeCount（不读内容、不弹横幅）：在对方 App 里不收键盘直接复制一句，帮回键红点、紫点也跟着出来。
    /// 不能在这里直接读 UIPasteboard.general：属性初始值在控制器创建时就算，键盘还没弹出，
    /// 第一次碰剪贴板要连系统的剪贴板服务，会压在弹出前的主线程上。第一次轮询时才记。
    private var clipboardPoll: Timer?
    private var polledChangeCount: Int?

    /// 退后台时输入框里还挂着、没清成的拼音，记下的时间。放在实例外面：回前台时系统常新建一个 KeyboardViewController，
    /// 旧实例的 textDocumentProxy 已经断开、随后被释放，只有新实例清得掉（bug #15）。
    private static var staleMarkedAt: Date?
    /// 记下时对方输入框的 documentIdentifier（收起时记；退后台时不记）。下次弹出还是这个框才清，换了框不碰。
    private static var staleMarkedDocument: UUID?
    private var staleClearScheduled = false

    /// 收起键盘时还在打拼音（bug #11）：趁 viewWillDisappear 时和输入框还连着，把组字清掉、输入框里的下划线拼音清掉。
    /// 原来要等 viewDidDisappear 或收起 0.4 秒后的补做（releaseEngine）才清，那时输入框多半已经断开，清的那一下被丢掉，
    /// 下次弹出拼音还挂在框里。万一这一下也没清成，记下来，下次在同一个框弹出时再清（clearStaleMarkedText）。
    private func clearMarkedTextOnHide() {
        guard !hostInactive, model.isComposing || model.hasMarkedText else { return }
        if model.hasMarkedText {
            Self.staleMarkedAt = Date()
            Self.staleMarkedDocument = hostDocumentID
        }
        model.engine.reset()
        model.syncEngine()
    }

    /// 回前台后清掉退后台时没清成的下划线拼音：没选中字、没在打字时清一次标记区，隔 0.3 秒、1 秒再清两次（宿主刚回前台可能还没接上）。
    /// 光标前的字靠不住（信息不算标记区、空框给 nil），不拿它判断；宿主已经把拼音落成正文的，就只能留着，绝不按长度往回删。
    /// 记录只给退后台后 60 秒内第一个弹出的实例用一次，排完就丢。
    private func clearStaleMarkedText() {
        // 只给正显示着的实例用：旧实例回前台也会收到 didBecomeActive，但已经不在窗口里，别让它把记录用掉。
        guard let at = Self.staleMarkedAt, !staleClearScheduled, view.window != nil else { return }
        let document = Self.staleMarkedDocument
        Self.staleMarkedAt = nil
        Self.staleMarkedDocument = nil
        if let document {
            // 收起时记的：只在同一个输入框里清（隔多久都清，拼音一直挂在那儿）；换了框或者认不出是哪个框，不碰。
            guard hostDocumentID == document else { return }
        } else {
            guard Date().timeIntervalSince(at) < 60 else { return }
        }
        staleClearScheduled = true
        for delay in [0, 0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // 又开始打字、或者选中了字（空的 setMarkedText 会把选中的字换掉）：不清。
                guard let self, !self.hostInactive, !self.model.isComposing,
                      (self.textDocumentProxy.selectedText ?? "").isEmpty else { return }
                self.model.hasMarkedText = true
                self.model.clearMarkedText()
            }
        }
    }

    /// 清掉组字、关掉 Rime 会话：收起和退后台都走这里。下次弹出（selectEngine）或按键时重建。
    private func releaseEngine() {
        // 只在对方退后台时记：正常收起时清得掉；而且下次弹出可能已经换了输入框，那边没拼音可清。
        if hostInactive, model.hasMarkedText {
            Self.staleMarkedAt = Date()
            Self.staleMarkedDocument = nil
        }
        model.engine.reset()
        QueuedEngine.shared.closeSession()
        model.syncEngine()
    }

    /// 横屏用简版尺寸。键盘扩展里拿不到界面方向：有窗口时按屏幕宽高比，还没进窗口时看竖向尺寸类（iPhone 横屏是 compact）。
    /// iPad：全宽时按键盘宽和屏幕定 iPad 尺寸（PadMetrics，11 寸 / 13 寸、横竖屏）；浮动键盘（宽约 320）照 iPhone 竖屏排，
    /// 不用 iPhone 横屏的扁按键。还没进窗口时先沿用这个进程上次的 iPad 尺寸，进了窗口再核（scheduleOrientationCheck）。
    private func updateOrientation() {
        if let geometry = currentGeometry() {
            model.setLandscape(geometry.landscape, pad: geometry.pad, floating: isPad && geometry.pad == nil)
        } else if isPad {
            let width = view.bounds.width
            let pad = width > 0 && width < 500 ? nil
                : KeyboardMetrics.padBase ?? PadMetrics.make(isPad: true, width: 820, screen: CGSize(width: 820, height: 1180))
            model.setLandscape(false, pad: pad, floating: pad == nil)
        } else {
            model.setLandscape(traitCollection.verticalSizeClass == .compact)
        }
        // 浮动和全宽来回换时 🌐 跟着变（浮动时不画自己的），不等下一次布局。
        updateGlobeKey()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// 进了窗口以后按屏幕和键盘宽算出来的方向和 iPad 尺寸；还没进窗口时为 nil。
    private func currentGeometry() -> (landscape: Bool, pad: PadMetrics?)? {
        guard let screen = view.window?.windowScene?.screen.bounds.size else { return nil }
        let width = view.bounds.width > 0 ? view.bounds.width : screen.width
        let pad = PadMetrics.make(isPad: isPad, width: width, screen: screen)
        return (!isPad && screen.width > screen.height, pad)
    }

    /// 方向复查：弹出时（viewWillAppear）往往还没进窗口，只能看尺寸类，而键盘进程里留着的旧值可能还是上次横屏的 compact；
    /// 在横屏 App 里弹过键盘、回到竖屏再弹（比如桌面搜索），转屏是在键盘收起时发生的，不会走 viewWillTransition，
    /// 键盘就一直卡在横屏的扁高度。进了窗口以后每次布局都按屏幕宽高比再核一次，不对就改；
    /// 布局途中不直接改高度约束（updateHeight 会让父视图立刻重排），放到下一轮做。
    private var orientationCheckScheduled = false
    private func scheduleOrientationCheck() {
        guard !orientationCheckScheduled, let geometry = currentGeometry(),
              geometry.landscape != model.landscape || geometry.landscape != KeyboardMetrics.landscape
                || geometry.pad != model.pad || geometry.pad != KeyboardMetrics.padBase
        else { return }
        orientationCheckScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.orientationCheckScheduled = false
            self.updateOrientation()
            self.updateHeight()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iPad 换成浮动键盘、换回全宽时横向尺寸类会变，也重排一次。
        guard previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass
                || previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateOrientation()
            self?.updateHeight()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateOrientation()
            self?.updateHeight()
        }
    }

    private func updateHeight() {
        let target = model.keyboardHeight
        guard let heightConstraint, heightConstraint.constant != target else { return }
        UIView.performWithoutAnimation {
            heightConstraint.constant = target
            view.setNeedsLayout()
            view.superview?.setNeedsLayout()
            view.superview?.layoutIfNeeded()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 长按空格拖光标时，每移一下对方都会通知；这时不读输入框，松手再补（setTrackpad(false)）。
        if model.trackpadActive { return }
        model.noteHostDocument(hostDocumentID)
        // 点对方输入框挪光标时，系统有时只通知文字变了、不通知光标变了（iOS 27 模拟器上就是这样），两处都接。
        model.hostSelectionChanged()
        model.fieldDidChange()
        // 双拼练习页按对、清空练习框后，「跟着按键变」的提示跟着框里的字母换（见 KeyboardModel.practiceContextPhase）。
        if model.doublePinyin != nil, model.settings.doublePinyinHintMode == .dynamic, model.practiceActive { model.objectWillChange.send() }
    }

    /// 换到别的输入框、移动光标时也更新一下发送键（有没有字、回车键类型）。
    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if model.trackpadActive { return }
        model.noteHostDocument(hostDocumentID)
        // 用户点了对方输入框：抽屉开着时打字换回对方输入框。
        model.hostSelectionChanged()
        model.refreshHostState()
        // 挪了光标，英文补全按新位置重算。
        if !model.chineseMode { model.updateEnglishSuggestions() }
    }

    /// 键盘整棵 SwiftUI 视图。系统每次弹出都新建一个 KeyboardViewController；下滑收起时只走 viewWillDisappear，
    /// 不走 viewDidDisappear，约 1 秒后控制器 deinit。但宿主视图被 SwiftUI 内部（显示链）拿着不放，
    /// 它的 rootView 又拿着 KeyboardModel，于是整棵视图、键帽、model 都留在内存里，同一进程每弹一次涨约 3.5 MB
    /// （0.96_3 就有，之前每次收起都崩所以没显出来），涨到上限就被系统杀掉、又变冷启动。
    /// 所以 deinit 和 viewDidDisappear 里都把 rootView 换成空视图，宿主就算还被拿着也只剩个空壳。
    private var host: UIHostingController<AnyView>?
    /// 宿主里放的是不是真键盘（「先显示截图」时先放空占位，第一帧交出去以后再填）。
    private var hostFilled = false

    deinit {
        let host = host, poll = clipboardPoll, root = rootForTeardown
        if Thread.isMainThread {
            // 不在这里关 Rime 会话：会话是整个进程共用的，收起后 1 秒内又弹出时新控制器已经开好了，这里一关就打不出候选。
            MainActor.assumeIsolated { Self.tearDown(host: host, poll: poll, root: root) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { Self.tearDown(host: host, poll: poll, root: root) } }
        }
    }

    /// 剪贴板轮询也要停：定时器在 RunLoop 里一直跑、一直被拿着（每个旧控制器多留一个）。
    /// 光换空视图不够：旧控制器的根视图 UIInputView 被系统留着，宿主视图挂在它下面，已经画好的图层、
    /// 键帽触摸层、候选条（它们的 SwiftUI 包装拿着 model）都跟着留下，每次还是 +1 MB。把宿主视图从旧根视图上摘掉。
    ///
    /// 旧根视图本身也被系统留着：iOS 用关联对象拿着每一次弹出的 UIInputView，空白键盘也一样（模拟器每弹一次约 50 KB，bug #38），
    /// 我们改不掉。我们的根视图上还挂着高度约束和它带出来的布局引擎、图层，每次约 200 KB。控制器释放时根视图早已不在窗口里，
    /// 把挂在它上面的约束、剩下的子视图都摘掉，系统留着的只剩个空壳。
    private static func tearDown(host: UIHostingController<AnyView>?, poll: Timer?, root: UIView?) {
        poll?.invalidate()
        if let host {
            let start = CACurrentMediaTime()
            host.rootView = AnyView(EmptyView())
            host.view.removeFromSuperview()
            let end = CACurrentMediaTime()
            PopupLog.lastTeardownMs = (end - start) * 1000
            PopupLog.lastTeardownDone = end
        }
        if let root, root.window == nil {
            NSLayoutConstraint.deactivate(root.constraints)
            root.subviews.forEach { $0.removeFromSuperview() }
        }
    }

    /// placeholder：先放空占位（「先显示截图」时），真键盘等 fillHost 再填。宿主视图和约束照样现在就装好。
    private func installHost(placeholder: Bool = false) {
        guard host == nil else { return }
        let host = UIHostingController(rootView: placeholder ? AnyView(Color.clear) : AnyView(KeyboardView(model: model)))
        hostFilled = !placeholder
        // 底色由 KeyboardView 自己画：拼音行以下不透明（Chrome 从系统键盘切回来时，系统按键会残留在我们下面，
        // 透明的话从键缝里透出来；不透明也保证键缝能接到触摸），最上面拼音行那截渐变接上系统液态玻璃。
        host.view.backgroundColor = .clear
        // 键盘区域不需要安全区留白，否则预览区内容会被额外内边距推开。
        if #available(iOS 16.4, *) {
            host.safeAreaRegions = []
        }
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host
    }

    /// 空占位换成真键盘：只换 SwiftUI 的内容，宿主视图和它的约束不动。
    /// 原来开着截图时宿主在第一帧之后才装上，键盘的视图结构在弹出途中变了一次；真机上第一次下拉搜索时，
    /// 搜索框先按矮约 24pt 的键盘停下，动画结束才跳到对的位置（11-23 录屏），「光标闪一下」。
    private func fillHost() {
        guard !hostFilled else { return }
        guard let host else { return installHost() }
        host.rootView = AnyView(KeyboardView(model: model))
        hostFilled = true
    }

    // MARK: 先显示截图（试验，PopupSnapshot）

    /// 测试工具里的「弹出时先显示截图」开关，viewDidLoad 时读一次。
    private var snapshotOn = false
    /// 弹出时先放着的上次键盘的截图；真键盘建好、交出一帧以后拿掉。
    private var snapshotView: UIImageView?
    /// 截图放上时还没进窗口：第一帧交不出去，等进了窗口再排建真键盘。
    private var snapshotWaitingWindow = false
    /// 用不用截图还没判断（viewWillAppear 里先不判断，等进了窗口）。
    private var snapshotDecisionPending = false
    /// 判断时的样子：0.4 秒后截图前再比一次，看判断时读到的是不是还没定下来的值（写进弹出记录）。
    private var decidedSnapshotKey: PopupSnapshot.Key?

    /// 现在键盘长什么样（宽、高、深浅色、回车键……），和截图时的对得上才用那张图。
    private func snapshotKey() -> PopupSnapshot.Key? {
        let width = view.bounds.width
        guard width > 0 else { return nil }
        return PopupSnapshot.Key(size: CGSize(width: width, height: model.keyboardHeight),
                                 style: traitCollection.userInterfaceStyle,
                                 appearance: textDocumentProxy.keyboardAppearance ?? .default,
                                 returnKey: model.hostReturnKey, hasText: model.hostHasText,
                                 nineKey: model.showsNineKey, layer: model.layer, chinese: model.chineseMode,
                                 landscape: model.landscape, settings: model.settings)
    }

    /// 用不用截图在进了窗口（viewIsAppearing）时才判断：viewWillAppear 时往往还没进窗口，深浅色还是系统的，
    /// 不是对方 App 的（小红书这类固定浅色的 App，系统深色时就对不上）；输入框的回车键、外观也可能还没换成这个框的。
    /// 0.97_7 的记录里，没用上截图的多半写着深浅色、回车键、输入框要的键盘外观「和上次不一样」，
    /// 可其中不少 0.4 秒后并没有再截新图，说明那时样子又和已有的图对上了：是判断得太早。
    /// 进了窗口、第一帧交出去之前，深浅色已经跟着对方 App 换了，这时再读一遍输入框（回车键、有没有字、数字框），然后判断。
    private func decideSnapshot() {
        guard snapshotDecisionPending else { return }
        snapshotDecisionPending = false
        guard snapshotOn, !hostFilled else { return }
        model.refreshHostState()
        let key = snapshotKey()
        decidedSnapshotKey = key
        if let key, let image = PopupSnapshot.image(for: key) {
            showSnapshot(image)
        } else {
            if !popupRecorded { popupRecord?.snapshotMiss = key.map(PopupSnapshot.missReason) ?? "键盘宽度还是 0，没法比" }
            fillHost()
            view.layoutIfNeeded()
        }
    }

    /// 截图前看一眼：现在的样子和判断时的比，变了说明判断时有的值还没定（或者用户这 0.4 秒里换了什么）。
    private func checkSnapshotDrift() {
        guard let decided = decidedSnapshotKey else { return }
        decidedSnapshotKey = nil
        guard PopupLog.enabled, let now = snapshotKey() else { return }
        let names = now.differences(from: decided)
        if !names.isEmpty { marks.snapshotDrift = names.joined(separator: "、") }
    }

    private func showSnapshot(_ image: UIImage) {
        removeSnapshot()
        let imageView = UIImageView(image: image)
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleToFill
        view.addSubview(imageView)
        snapshotView = imageView
        if view.window != nil { buildHostAfterNextFrame() } else { snapshotWaitingWindow = true }
    }

    /// 这一圈主线程睡下时，Core Animation 已经把带着截图的第一帧提交了；下一轮再建真键盘。
    private func buildHostAfterNextFrame() {
        snapshotWaitingWindow = false
        Self.afterNextCommit { [weak self] in self?.replaceSnapshot() }
    }

    /// 主线程这一圈睡下时（这时这一圈的 Core Animation 提交已经做完）排到下一轮做。
    private static func afterNextCommit(_ action: @escaping () -> Void) {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { _, _ in
            DispatchQueue.main.async(execute: action)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// 建真键盘、排好。真键盘盖在截图上面；截图等真键盘这一帧也交出去了再拿掉：
    /// 万一 SwiftUI 这一圈还没画完，露出来的也是截图，不会空一帧。
    private func replaceSnapshot() {
        guard snapshotView != nil, !hostFilled else { return }
        fillHost()
        view.layoutIfNeeded()
        snapshotWaitingWindow = false
        if PopupLog.enabled { marks.snapshotSwap = CACurrentMediaTime() }
        let shot = snapshotView
        Self.afterNextCommit { [weak self] in
            guard let self, self.snapshotView === shot else { return }
            self.removeSnapshot()
        }
    }

    private func removeSnapshot() {
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        snapshotWaitingWindow = false
    }

    /// 弹出 0.4 秒后（滑完了、多半还没开始打字）把真键盘的样子截下来，留给下次弹出先显示。已经有对得上的就不截。
    private func captureSnapshotIfNeeded() {
        guard snapshotOn, let host, hostFilled, view.window != nil, snapshotView == nil,
              !model.isComposing, model.keysPanel == nil, model.layoutMenu == nil,
              let key = snapshotKey(), PopupSnapshot.image(for: key) == nil,
              abs(host.view.bounds.height - key.size.height) < 0.5, abs(host.view.bounds.width - key.size.width) < 0.5
        else { return }
        let start = CACurrentMediaTime()
        guard let image = PopupSnapshot.capture(host.view) else { return }
        PopupSnapshot.store(image, for: key)
        if PopupLog.enabled { marks.snapshotCapture = (CACurrentMediaTime() - start) * 1000 }
    }

    private func removeHost() {
        guard let host else { return }
        // 先换成空视图：就算宿主视图被 SwiftUI 内部（显示链）多拿一会儿，键盘那棵视图图和 model 的引用也先放掉。
        host.rootView = AnyView(EmptyView())
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        self.host = nil
        hostFilled = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Self.appearCount += 1
        hiddenCleanupDone = false
        let willStart = CACurrentMediaTime()
        // 收起时拆掉了宿主，同一个控制器再弹出时重新装上。
        installHost(placeholder: snapshotOn)
        // 「先显示截图」：进了窗口再判断（viewIsAppearing）。样子和上次截的图对得上，就先放图、下一轮再把真键盘填进宿主；
        // 对不上就在那时填。
        let deferHost = snapshotOn && !hostFilled
        let hostDone = CACurrentMediaTime()
        // 先定下有没有地球键，免得键盘滑出来的途中按键再换一次排法。
        updateGlobeKey()
        updateOrientation()
        model.dropStaleSessionOnAppear()
        // 换了输入框重新试标记文字（上一个框不认，不代表这个也不认）。
        model.inlinePinyinOff = false
        model.hostDocumentID = hostDocumentID
        model.stoppedAnswer = nil
        // 上一个框留下的联想不带到这个框。
        model.dismissPredictions()
        // iPad 9 键中间那块（PK17）每次弹出都回到联想。
        model.padMiddle = nil
        model.lastMarkedText = ""
        // 弹出时系统会通知一次文字变了，那次不算点了输入框：先不记光标，下一次通知只记下来。
        model.hostCaret = nil
        // 每次弹出都按输入框类型重新选一次页（数字框直接出数字键盘）。
        model.hostKeyboardType = nil
        let reloadStart = CACurrentMediaTime()
        model.reload()
        let reloadDone = CACurrentMediaTime()
        model.applyInputLanguage()
        model.applyDebugState()
        // 高度和内容在滑出来之前就定好：reload 可能改了高度（比如试用提醒条），这里同步改掉，不等下一轮；
        // 再让 SwiftUI 先排一遍，系统做弹出动画时画的就是完整的键盘，AI 栏不会等滑出来以后才冒出来。
        let layoutStart = CACurrentMediaTime()
        updateHeight()
        view.layoutIfNeeded()
        decidedSnapshotKey = nil
        if deferHost { snapshotDecisionPending = true } else { removeSnapshot() }
        #if DEBUG
        heightLog("willAppear")
        #endif
        startPopupRecord(willStart: willStart, hostDone: hostDone, reload: reloadDone - reloadStart, layoutStart: layoutStart)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        decideSnapshot()
    }

    private func startPopupRecord(willStart: CFTimeInterval, hostDone: CFTimeInterval, reload: CFTimeInterval, layoutStart: CFTimeInterval) {
        guard PopupLog.enabled, !popupRecorded, popupRecord == nil else { return }
        let now = CACurrentMediaTime()
        // 这一圈主线程睡下时，Core Animation 已经把第一帧提交了：记下来，看系统那边空底板等的是不是我们。
        let marks = marks
        MainWake.onNextSleep = { marks.firstFrame = CACurrentMediaTime() }
        Self.popupsInProcess += 1
        let hide = PopupLog.lastHide
        // 这个控制器建出来之前 5 秒内主线程醒过（闲置 / 挂起后），才算这次弹出叫醒的。
        // 而且要在上次收起之后：收起后主线程没闲下来过（马上又弹出）就量不到，不拿更早的醒来充数。
        let wake = MainWake.lastWake.flatMap { $0 <= createdAt && createdAt - $0 < 5 && $0 > PopupLog.lastHideMono ? $0 : nil }
        let stalls = MainStalls.summary(from: createdAt - 2, to: createdAt)
        popupRecord = PopupRecord(
            at: Date(), nth: Self.popupsInProcess,
            processToLoad: Self.popupsInProcess == 1 ? loadSinceProcess : nil,
            initToLoad: (loadStart - createdAt) * 1000,
            idleBeforeWake: wake.map { _ in MainWake.lastIdle * 1000 }, wakeToInit: wake.map { (createdAt - $0) * 1000 },
            wakeBusy: wake.map { _ in loadBusy },
            stallLongest: stalls?.longest, stallTotal: stalls?.total,
            lastCleanupMs: PopupLog.lastCleanupMs, lastTeardownMs: PopupLog.lastTeardownMs,
            lastCleanupBefore: PopupLog.lastCleanupDone.map { (createdAt - $0) * 1000 },
            lastTeardownBefore: PopupLog.lastTeardownDone.map { (createdAt - $0) * 1000 },
            load: loadMs, willAppear: (now - willStart) * 1000, willHost: (hostDone - willStart) * 1000,
            willReload: reload * 1000, willLayout: (now - layoutStart) * 1000,
            loadToAppear: 0, snapshotMiss: nil, didClipboard: 0, didCommonWords: 0, engineReady: nil, memoryMB: nil,
            sinceHide: hide.map { Date().timeIntervalSince($0.at) },
            sameProcess: hide.map { $0.pid == ProcessInfo.processInfo.processIdentifier },
            lastCleanup: hide?.cleanup, nineKey: model.showsNineKey)
    }

    /// viewDidAppear 后补上出现时间、内存；再等 1.5 秒看拼音引擎好了没有，然后存。
    private func finishPopupRecord(clipboard: Double, commonWords: Double) {
        guard var finished = popupRecord, !popupRecorded else { return }
        popupRecorded = true
        finished.loadToAppear = (CACurrentMediaTime() - loadStart) * 1000
        // 控制器建出来以后主线程睡过半秒以上：主线程每 50 毫秒就被 MainStalls 叫醒一次，睡这么久只能是进程被系统挂起了。
        if let wake = MainWake.lastWake, wake > createdAt {
            finished.paused = MainWake.lastIdle * 1000
            // 醒来早于开始建键盘：挂起落在控制器建出来到 viewDidLoad 之间，说明写在「准备」那一行。
            if wake <= loadStart { finished.pausedBeforeLoad = true }
        }
        // 建键盘到显示出来这段主线程干了多少活：没被挂起、建键盘之前就在量，才算得准。
        if wakeTracked, finished.paused == nil { finished.appearBusy = max(0, MainWake.busySinceWake() - loadBusy) }
        finished.didClipboard = clipboard * 1000
        finished.didCommonWords = commonWords * 1000
        finished.memoryMB = TypingStats.footprintMB()
        // 只算显示出来之前排上队的准备：之后用户切中英、换布局，或者 1.5 秒里收起又弹出的新键盘排的，不是这次弹出的。
        let appeared = CACurrentMediaTime()
        let loadStart = loadStart, createdAt = createdAt, partial = finished, hideMono = PopupLog.lastHideMono, marks = marks
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak model] in
            var record = partial
            func since(_ time: CFTimeInterval) -> Double { (time - loadStart) * 1000 }
            record.firstFrame = marks.firstFrame.map(since)
            record.snapshotSwap = marks.snapshotSwap.map(since)
            record.snapshotCapture = marks.snapshotCapture
            record.snapshotDrift = marks.snapshotDrift
            record.heights = marks.heightsText(from: loadStart)
            record.wantedHeight = model.map { Double($0.keyboardHeight) }
            if let ready = model?.engineReadyAt, ready >= loadStart { record.engineReady = since(ready) }
            // 这次弹出以后的每一次准备：排队取第一次的，准备时间加起来，做了什么按先后列出；
            // 准备了不止一次时，每次写上第几毫秒排上队、做了多久，看后面那次是谁排的。
            let prepares = QueuedEngine.shared.recentPrepares.filter { $0.queued >= loadStart && $0.queued <= appeared }
            if let first = prepares.first {
                record.engineWait = (first.started - first.queued) * 1000
                record.engineRun = prepares.map { ($0.finished - $0.started) * 1000 }.reduce(0, +)
                if prepares.count == 1 {
                    record.engineWork = first.work
                } else {
                    record.engineWork = prepares.map {
                        "\($0.work)（第 \(String(format: "%.0f", since($0.queued))) 毫秒排上，做了 \(String(format: "%.0f", ($0.finished - $0.started) * 1000))）"
                    }.joined(separator: " → ") + "（准备了 \(prepares.count) 次）"
                }
            }
            // 旧键盘常常在新的弹出以后才拆（deinit 晚一点），这时补上；期间又收起过就不补（已经是下一次的了）。
            if PopupLog.lastHideMono == hideMono {
                if record.lastCleanupMs == nil, let done = PopupLog.lastCleanupDone {
                    record.lastCleanupMs = PopupLog.lastCleanupMs
                    record.lastCleanupBefore = (createdAt - done) * 1000
                }
                if record.lastTeardownMs == nil, let done = PopupLog.lastTeardownDone {
                    record.lastTeardownMs = PopupLog.lastTeardownMs
                    record.lastTeardownBefore = (createdAt - done) * 1000
                }
            }
            PopupLog.append(record)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 万一没走 viewIsAppearing、还没判断：第一帧已经交出去了，不用截图，直接填真键盘。
        if snapshotDecisionPending {
            snapshotDecisionPending = false
            fillHost()
            view.layoutIfNeeded()
        }
        // 截图还挂着（下一轮还没轮到）：现在就换成真键盘，后面的事都要用到它。
        replaceSnapshot()
        if snapshotOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.checkSnapshotDrift()
                self?.captureSnapshotIfNeeded()
            }
        }
        #if DEBUG
        heightLog("didAppear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.heightLog("settled") }
        #endif
        TypingStats.noteLaunchAppeared()
        // 先弹出、后载入：键盘长什么样用不到的准备，都等它显示出来以后的下一轮再做，不压在弹出前的主线程上。
        DispatchQueue.main.async { [weak self] in self?.prepareAfterAppear() }
        // 弹出前没进窗口时方向是按尺寸类猜的，进了窗口按屏幕再核一次。
        scheduleOrientationCheck()
        clearStaleMarkedText()
        let clipboardStart = CACurrentMediaTime()
        // 剪贴板换没换过（只看 changeCount、hasStrings，不读内容）：「常用」键上的紫点。
        model.checkClipboard()
        startClipboardPoll()
        let wordsStart = CACurrentMediaTime()
        // 常用词要读系统文本替换和通讯录、可能重写词库里的短语表，不影响键盘长什么样，放到弹出以后再做，
        // 不占弹出前的那一段主线程。
        model.refreshCommonWords()
        let wordsDone = CACurrentMediaTime()
        finishPopupRecord(clipboard: wordsStart - clipboardStart, commonWords: wordsDone - wordsStart)
    }

    /// 弹出后再做的准备：崩溃记录订阅（冷启动时要读一遍以前的诊断包）、按键落点校准、震动预热、英文补全词表。
    /// 都在第一个按键之前就做完了（显示出来以后的下一轮），只是不再挡在键盘显示出来之前。
    private func prepareAfterAppear() {
        CrashLog.shared.start(source: "keyboard")
        TouchCalibration.reload()
        // 震动发生器提前建好、预热：不然第一次按键时才创建，第一个键会顿一下。
        if model.settings.keyHaptics && model.hasFullAccess { model.haptic.prepare() }
        if !model.chineseMode || model.settings.inputLanguage != .chinese { EnglishPredictor.prepare() }
    }

    /// 每有一个键盘页面要弹出就 +1（整个进程共用）。收起后补做清理前看它变没变：变了说明又弹出来了，会话归新页面用。
    private static var appearCount = 0
    private var hiddenCleanupDone = false

    /// 下滑收起、桌面搜索收起时系统只调这里，不调 viewDidDisappear（模拟器实测，见 f9142d5），约 1 秒后控制器直接释放。
    /// 于是 viewDidDisappear 里那些收尾一直没做：Rime 会话开着、App Group 里用户词库的 LOCK 一直锁着，
    /// 扩展一被挂起就被系统杀掉（0xDEAD10CC），下次弹出又是冷启动：先空着约 0.75 秒，再整块蹦出来（11-14 录屏）。
    /// 收起 0.4 秒后还没有新页面弹出来，就把 viewDidDisappear 的收尾补上；控制器已经释放了，至少关掉会话、写掉统计。
    /// 这 0.4 秒用 performExpiringActivity 向系统要着，免得还没补完就被挂起。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        PopupLog.noteHide(cleanup: "未收尾")
        PopupLog.lastHideMono = CACurrentMediaTime()
        PopupLog.lastCleanupMs = nil
        PopupLog.lastTeardownMs = nil
        PopupLog.lastCleanupDone = nil
        PopupLog.lastTeardownDone = nil
        clearMarkedTextOnHide()
        let count = Self.appearCount
        let done = DispatchSemaphore(value: 0)
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Finish hiding keyboard") { expired in
            guard !expired else { return }
            _ = done.wait(timeout: .now() + 2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            defer { done.signal() }
            guard Self.appearCount == count else { return }
            if let self {
                self.cleanUpAfterHiding(how: "补做")
            } else {
                QueuedEngine.shared.closeSession()
                Self.flushShared()
                PopupLog.noteHide(cleanup: "补做(已释放)")
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cleanUpAfterHiding(how: "didDisappear")
    }

    /// 键盘收起后的收尾，viewDidDisappear 或收起后补做，只做一次（再弹出时重置）。
    private func cleanUpAfterHiding(how: String) {
        guard !hiddenCleanupDone else { return }
        hiddenCleanupDone = true
        let start = CACurrentMediaTime()
        defer {
            let end = CACurrentMediaTime()
            PopupLog.lastCleanupMs = (end - start) * 1000
            PopupLog.lastCleanupDone = end
        }
        PopupLog.noteHide(cleanup: how)
        clipboardPoll?.invalidate()
        clipboardPoll = nil
        // 收起时关掉 Rime 会话，放开共享容器里用户词库的锁，免得挂起时被系统杀（0xDEAD10CC）。下次弹出 selectEngine 会重建。
        releaseEngine()
        model.pressedKeys = []
        if !model.keyPresses.flicked.isEmpty { model.keyPresses.flicked = [] }
        model.trackpadActive = false
        model.dismissPredictions()
        Self.flushShared()
        removeSnapshot()
        removeHost()
    }

    /// 攒在内存里的打字统计、触摸校准、英文用词，收起时写进共享存储。
    private static func flushShared() {
        TypingStats.flush()
        TouchCalibration.flush()
        EnglishPredictor.flush()
        DailyStats.flush()
    }

    /// 弹出以后才开始，第一次在 1 秒后；没开完全访问时读不了剪贴板，不轮询。
    private func startClipboardPoll() {
        clipboardPoll?.invalidate()
        clipboardPoll = nil
        guard hasFullAccess else { return }
        polledChangeCount = nil
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 帮回：记下键盘还看着剪贴板的时间，收起以后剪贴板换了，复制时间最早算到这里。
            self.model.noteClipboardLook()
            let count = UIPasteboard.general.changeCount
            guard let last = self.polledChangeCount else {
                self.polledChangeCount = count
                return
            }
            guard count != last else { return }
            self.polledChangeCount = count
            self.model.checkClipboard()
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        clipboardPoll = timer
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        model.noteMemoryWarning()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // 截图放上时还没进窗口：进了窗口，这一圈的第一帧才交得出去，交完再建真键盘。
        if snapshotWaitingWindow, view.window != nil { buildHostAfterNextFrame() }
        updateGlobeKey()
        scheduleOrientationCheck()
    }

    #if DEBUG
    private static var lastLoggedHeight: CGFloat = 0
    #endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = view.bounds.height
        // 弹出记录：建键盘后 3 秒内系统给的高度每变一次记一条（记录在显示出来 1.5 秒后存，存之前的都写得进去）。
        if PopupLog.enabled {
            let now = CACurrentMediaTime()
            if now - loadStart < 3 { marks.noteHeight(Double(height), at: now) }
        }
        #if DEBUG
        // 系统给的高度一变就记一条：查键盘顶边有时高出约 17pt（拼音行 + 候选行固定高度规格）。
        guard height != Self.lastLoggedHeight else { return }
        Self.lastLoggedHeight = height
        heightLog("layout")
        #endif
    }

    /// 只在变了的时候设：needsGlobeKey 是 @Published，设一次（哪怕值一样）整个键盘就重画一遍、高度也要重算，
    /// 而每次布局都会走到这里，弹出动画途中会连着重画好多次，看起来就是卡。
    private func updateGlobeKey() {
        // iPad 浮动键盘（PK13）：系统在键盘下面自己画一排 🌐 … 🎤（模拟器 iPadOS 27.2 实测），needsInputModeSwitchKey
        // 却还是 true，照它画就有两个 🌐。浮动时不画自己的，26 键底排没有 🌐、9 键左下回到 ☺。全宽时系统下面没有这一排，照样画。
        let needs = needsInputModeSwitchKey && !KeyboardMetrics.floating
        if model.needsGlobeKey != needs { model.needsGlobeKey = needs }
    }
}

/// 系统要求的「切换键盘」按钮，必须由 UIKit 处理触摸事件才能弹出键盘列表。
struct NextKeyboardButton: UIViewRepresentable {
    weak var controller: UIInputViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        if let controller {
            button.addTarget(controller,
                             action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                             for: .allTouchEvents)
        }
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

#if DEBUG
extension KeyboardViewController {
    /// 调试真机弹出高度：除了 NSLog，再追加到 App Group 里的 Library/Diagnostics/debug-height.log（只留最后 60 行），
    /// 真机上不用 root 也能用 devicectl 拷出来。
    func heightLog(_ stage: String) {
        let inWindow = view.window.map { view.convert(view.bounds, to: $0) } ?? .zero
        // 往上几层父视图的高度：看系统多给的那截是在我们的 view 里，还是在外面的容器（键盘玻璃底）里。
        var supers: [String] = []
        var parent = view.superview
        while let p = parent, supers.count < 4 {
            supers.append(String(format: "%@ %.1f", String(describing: type(of: p)), p.bounds.height))
            parent = p.superview
        }
        let line = String(format: "%@ EnclaveHeight %@: view %.1f, target %.1f, inWindow y %.1f h %.1f, window h %.1f, safe top %.1f, supers [%@], iOS %@",
                          ISO8601DateFormatter().string(from: Date()), stage, view.bounds.height, model.keyboardHeight,
                          inWindow.minY, inWindow.height, view.window?.bounds.height ?? -1, view.safeAreaInsets.top,
                          supers.joined(separator: ", "), UIDevice.current.systemVersion)
        NSLog("%@", line)
        guard let id = SharedStorage.appGroupID,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return }
        // devicectl 只能拷 App Group 里 Library、Documents、tmp 下的文件，放在 Library/Diagnostics。
        let folder = dir.appendingPathComponent("Library/Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("debug-height.log")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = (old.split(separator: "\n").map(String.init) + [line]).suffix(60)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
