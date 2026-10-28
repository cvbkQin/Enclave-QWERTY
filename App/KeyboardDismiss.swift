import UIKit

/// App 里收起键盘：点输入框以外的地方就收起（滑动列表收起由根视图的 scrollDismissesKeyboard 负责）。
/// 加在窗口上、不吞掉点击：按钮、开关照常响应；点的是另一个输入框时不收，直接换过去。
final class KeyboardDismiss: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismiss()

    func install() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === self }) {
                let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss(_:)))
                tap.cancelsTouchesInView = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
            }
        }
    }

    @objc private func dismiss(_ tap: UITapGestureRecognizer) {
        tap.view?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
