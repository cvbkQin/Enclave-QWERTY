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
        model.dropStaleSessionOnAppear()
        // 每次弹出都按输入框类型重新选一次页（数字框直接出数字键盘）。
        model.hostKeyboardType = nil
        model.reload()
        model.applyInputLanguage()
        model.applyDebugState()
        TouchCalibration.reload()
        Predictor.prepare()
        if !model.chineseMode || model.settings.inputLanguage != .chinese { EnglishPredictor.prepare() }
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
        model.needsGlobeKey = needsInputModeSwitchKey
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
