import Combine
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var model = KeyboardModel(controller: self)
    private var heightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()


    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: KeyboardView(model: model))
        // 铺一层不透明的键盘底色，不再几乎透明：在 Chrome 里从系统键盘（英文、日文等）切回来时，
        // 系统键盘的按键会残留在我们下面，透明的话从键缝里透出来。不透明也保证键缝能接到触摸。
        host.view.backgroundColor = Brand.keyboardBackUI
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

        // 键盘高度只由这一条必需约束决定。allowsSelfSizing 让系统按我们的约束算高度，
        // 而不是套用它自己的固定高度——否则展开后系统仍按旧高度摆放，面板顶部和最后一排键会被裁掉。
        inputView?.allowsSelfSizing = true
        let height = view.heightAnchor.constraint(equalToConstant: model.keyboardHeight)
        height.priority = .required
        height.isActive = true
        heightConstraint = height

        // 展开、卡片展开、风格菜单一改就同步改高度：等到下一轮的话，SwiftUI 先按旧高度画出新内容，
        // 系统再把高度变化做成动画，风格浮层展开时内容会错位、按键被挤到底下。
        model.heightMayChange = { [weak self] in self?.updateHeight() }
        // 其余会影响高度的变化（比如配置好接口后卡片变矮）在下一轮补上。
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHeight() }
            .store(in: &cancellables)
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
        model.fieldDidChange()
    }

    /// 换到别的输入框、移动光标时也更新一下发送键（有没有字、回车键类型）。
    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        model.refreshHostState()
        // 挪了光标，英文补全按新位置重算。
        if !model.chineseMode { model.updateEnglishSuggestions() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 先定下有没有地球键，免得键盘滑出来的途中按键再换一次排法。
        updateGlobeKey()
        model.dropStaleSessionOnAppear()
        // 每次弹出都按输入框类型重新选一次页（数字框直接出数字键盘）。
        model.hostKeyboardType = nil
        model.reload()
        model.applyInputLanguage()
        model.applyDebugState()
        TouchCalibration.reload()
        // 震动发生器提前建好、预热：不然第一次按键时才创建，第一个键会顿一下。
        if model.settings.keyHaptics && model.hasFullAccess { model.haptic.prepare() }
        if !model.chineseMode || model.settings.inputLanguage != .chinese { EnglishPredictor.prepare() }
        // 高度和内容在滑出来之前就定好：reload 可能改了高度（比如试用提醒条），这里同步改掉，不等下一轮；
        // 再让 SwiftUI 先排一遍，系统做弹出动画时画的就是完整的键盘，AI 栏不会等滑出来以后才冒出来。
        updateHeight()
        view.layoutIfNeeded()
        #if DEBUG
        NSLog("EnclaveHeight willAppear: view %.1f, target %.1f", view.bounds.height, model.keyboardHeight)
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        NSLog("EnclaveHeight didAppear: view %.1f, target %.1f", view.bounds.height, model.keyboardHeight)
        #endif
        // 常用词要读系统文本替换和通讯录、可能重写词库里的短语表，不影响键盘长什么样，放到弹出以后再做，
        // 不占弹出前的那一段主线程。
        model.refreshCommonWords()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.engine.reset()
        model.syncEngine()
        model.pressedKeys = []
        model.trackpadActive = false
        TypingStats.flush()
        TouchCalibration.flush()
        model.dismissPredictions()
        EnglishPredictor.flush()
        DailyStats.flush()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        model.noteMemoryWarning()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateGlobeKey()
    }

    /// 只在变了的时候设：needsGlobeKey 是 @Published，设一次（哪怕值一样）整个键盘就重画一遍、高度也要重算，
    /// 而每次布局都会走到这里，弹出动画途中会连着重画好多次，看起来就是卡。
    private func updateGlobeKey() {
        let needs = needsInputModeSwitchKey
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
