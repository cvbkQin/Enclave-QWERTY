#if DEBUG
import SwiftUI
import UIKit
import WebKit

/// 输入框测试台（只在开发版）：几种会让第三方键盘出问题的输入框，每种模仿一类真实 App。
/// 每次发版前在每个框里跑同一套动作（打拼音选词、删除、润色替换、回车），流程见 /mnt/project-files/test/host-compat.md。
struct HostCompatBench: View {
    @State private var swiftUIText = ""

    var body: some View {
        Form {
            Section {
                Text("每个框都打一句拼音（九宫格、全键盘各一次）、选词上屏、删除、润色替换、回车。上屏后不该留下拼音字母。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            bench("1. 普通 UITextField（基准）", note: "系统输入框，什么都应该正常。") { BenchField(kind: .plain) }
            bench("2. 普通 UITextView（多行基准）", note: "多行，回车换行。") { BenchTextView().frame(height: 80) }
            bench("3. SwiftUI 改写值的绑定", note: "setter 里截到 10 个字、去掉首尾空格（常用语标题框以前的写法）。") {
                TextField("比如：公司地址", text: Binding(get: { swiftUIText }, set: {
                    swiftUIText = String($0.trimmingCharacters(in: .whitespaces).prefix(10))
                }))
            }
            bench("4. 每次变化都重新赋值（React Native 受控输入框）", note: "内容一变就 text = text，正在拼的拼音会被当成正文。") {
                BenchField(kind: .controlled)
            }
            bench("5. 不认标记文字（亚朵姓名框）", note: "setMarkedText 直接当插入，拼音每更新一次就多插一遍。") {
                BenchField(kind: .noMarkedText)
            }
            bench("6. 空标记不清、插入不替换（闲鱼 Flutter）", note: "setMarkedText(\"\") 不清标记区，标记中 insertText 不替换。") {
                BenchField(kind: .flutterLike)
            }
            bench("7. 最多 10 个字（shouldChangeCharacters 限长）", note: "超过 10 个字的改动直接拒掉。") {
                BenchField(kind: .limited(10))
            }
            bench("8. 网页输入框（WKWebView）", note: "上面是 input，下面是 contenteditable。") {
                BenchWebView().frame(height: 120)
            }
            bench("9. 搜索框", note: "回车键是「搜索」。") { BenchField(kind: .returnKey(.search)) }
            bench("10. 发送键", note: "回车键是「发送」。") { BenchField(kind: .returnKey(.send)) }
            bench("11. 数字框", note: "应直接出数字键盘。") { BenchField(kind: .keyboard(.numberPad)) }
            bench("12. 邮箱框", note: "英文、不自动大写。") { BenchField(kind: .keyboard(.emailAddress)) }
        }
        .navigationTitle("输入框测试台")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private func bench<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title)
        } footer: {
            Text(note)
        }
    }
}

// MARK: - UIKit 输入框

private struct BenchField: UIViewRepresentable {
    enum Kind {
        case plain, controlled, noMarkedText, flutterLike
        case limited(Int)
        case returnKey(UIReturnKeyType)
        case keyboard(UIKeyboardType)
    }

    let kind: Kind

    func makeCoordinator() -> Coordinator { Coordinator(kind: kind) }

    func makeUIView(context: Context) -> UITextField {
        let field: UITextField
        switch kind {
        case .noMarkedText: field = NoMarkedTextField()
        case .flutterLike: field = FlutterLikeField()
        default: field = UITextField()
        }
        field.placeholder = "在这里打字"
        field.clearButtonMode = .always
        field.delegate = context.coordinator
        switch kind {
        case .controlled:
            field.addTarget(context.coordinator, action: #selector(Coordinator.reassign(_:)), for: .editingChanged)
        case .returnKey(let type):
            field.returnKeyType = type
        case .keyboard(let type):
            field.keyboardType = type
            field.autocapitalizationType = .none
        default:
            break
        }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {}

    final class Coordinator: NSObject, UITextFieldDelegate {
        let kind: Kind
        init(kind: Kind) { self.kind = kind }

        /// React Native 受控输入框：每次变化都把 text 重新赋一遍（会结束正在拼的拼音）。
        @objc func reassign(_ field: UITextField) {
            let text = field.text
            field.text = text
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard case .limited(let limit) = kind else { return true }
            let current = (textField.text ?? "") as NSString
            return current.replacingCharacters(in: range, with: string).count <= limit
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

/// 亚朵姓名框那一类：不支持标记文字，键盘发来的每次 setMarkedText 都当正文插入。
private final class NoMarkedTextField: UITextField {
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard let markedText, !markedText.isEmpty else { return }
        insertText(markedText)
    }

    // 键盘扩展发来的标记文字走的是这个（iOS 27 上 setMarkedText 不会被调到），两个都要接住才像真的。
    override func setAttributedMarkedText(_ markedText: NSAttributedString?, selectedRange: NSRange) {
        guard let markedText, markedText.length > 0 else { return }
        insertText(markedText.string)
    }

    override func unmarkText() {}
}

/// 闲鱼（Flutter）那一类：空的 setMarkedText 不清标记区；标记中 insertText 插在标记后面、不替换。
private final class FlutterLikeField: UITextField {
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        guard let markedText, !markedText.isEmpty else { return }
        super.setMarkedText(markedText, selectedRange: selectedRange)
    }

    // 键盘扩展发来的标记文字走的是这个（iOS 27 上 setMarkedText 不会被调到）：空的同样不管。
    override func setAttributedMarkedText(_ markedText: NSAttributedString?, selectedRange: NSRange) {
        guard let markedText, markedText.length > 0 else { return }
        super.setAttributedMarkedText(markedText, selectedRange: selectedRange)
    }

    override func insertText(_ text: String) {
        if markedTextRange != nil { super.unmarkText() }
        super.insertText(text)
    }
}

private struct BenchTextView: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}
}

private struct BenchWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.loadHTMLString("""
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font:17px -apple-system;margin:0;color:CanvasText;background:transparent}
        input,div{box-sizing:border-box;width:100%;border:1px solid #8884;border-radius:8px;padding:8px;margin:4px 0;font:inherit;color:inherit;background:transparent}
        div{min-height:44px}</style></head>
        <body><input placeholder="input"><div contenteditable="true"></div></body></html>
        """, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
