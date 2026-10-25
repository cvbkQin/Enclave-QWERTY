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
            .sink { [weak self] _ in
                self?.updateHeight()
                self?.updateAppearance()
            }
            .store(in: &cancellables)
        updateAppearance()
    }

    /// App 里选了固定浅色或深色时，键盘不跟输入框的深浅走。系统的键盘底色改不了，自己铺一层底色。
    private func updateAppearance() {
        let style = model.settings.appearance.style
        guard view.overrideUserInterfaceStyle != style else { return }
        view.overrideUserInterfaceStyle = style
        view.backgroundColor = style == .unspecified ? nil : KeyStyle.keyboardBackground
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.dropStaleSessionOnAppear()
        // 每次弹出都按输入框类型重新选一次页（数字框直接出数字键盘）。
        model.hostKeyboardType = nil
        model.reload()
        model.applyDebugState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.engine.reset()
        model.syncEngine()
        model.pressedKeys = []
        model.trackpadActive = false
        TypingStats.flush()
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
