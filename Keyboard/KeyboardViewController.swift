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

        // 展开、卡片展开、风格菜单都会改变高度；在变化之后的下一轮读新值。
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHeight() }
            .store(in: &cancellables)
    }

    private func updateHeight() {
        let target = model.keyboardHeight
        guard let heightConstraint, heightConstraint.constant != target else { return }
        heightConstraint.constant = target
        view.setNeedsLayout()
        view.superview?.setNeedsLayout()
        view.superview?.layoutIfNeeded()
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
        model.reload()
        model.applyDebugState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.engine.reset()
        model.syncEngine()
        model.pressedKeys = []
        model.trackpadActive = false
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
