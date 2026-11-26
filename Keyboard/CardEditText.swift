import SwiftUI
import UIKit

/// 修改模式里的正文：可以放光标、选中、拖动调范围（用户 11-26：修改时要能选中、多选、复制、粘贴）。
/// 键盘扩展里不能用系统自己的文字编辑：系统不会给键盘里的输入框再弹一个键盘，系统的选择气泡菜单也会被键盘顶边切掉。
/// 所以这里的 UITextView 只管排版和上下滚动（不可编辑、不可选），光标、选区底色、两头的拖柄都自己画，
/// 手势自己处理：点 = 放光标；长按 = 选中点到的词，按住不放再拖 = 从这个词拖到手指处；拖两头的拖柄 = 调范围。
/// 复制、剪切、粘贴、全选的按钮在下面那一行（CardEditHint）。
struct CardEditText: UIViewRepresentable {
    @ObservedObject var model: KeyboardModel
    /// 光标、选区、拖柄、拼音下划线的颜色。
    var tint: Color

    func makeUIView(context: Context) -> CardEditTextView {
        let view = CardEditTextView()
        view.model = model
        return view
    }

    func updateUIView(_ view: CardEditTextView, context: Context) {
        view.model = model
        view.tint = UIColor(tint)
        view.render()
    }
}

final class CardEditTextView: UIView {
    weak var model: KeyboardModel?
    var tint: UIColor = .systemBlue

    /// 和结果卡上没在修改时的正文一样：15pt 系统字体。
    static let font = UIFont.systemFont(ofSize: 15)
    /// 和原来 SwiftUI 版的内边一样：左右 12、上下 8。拖柄的圆点画在这块内边里，不会被切掉。
    static let inset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    private let textView = UITextView(usingTextLayoutManager: false)
    private let caret = UIView()
    private let startHandle = CardSelectionHandle(isStart: true)
    private let endHandle = CardSelectionHandle(isStart: false)
    private let pressGesture = UILongPressGestureRecognizer()

    private struct Shown: Equatable {
        var display: String
        var composition: String
        /// 显示出来的文字里光标在第几个字后面（有拼音时在拼音后面）。
        var caret: Int
        /// 显示出来的文字里选中的一段；正在打拼音时不显示选区（拼音替换选区，选区先藏起来）。
        var selection: Range<Int>?
        var tint: UIColor
    }

    private var shown: Shown?
    private var needsScrollToCaret = true
    /// 长按选中的那个词：按住拖动时它总在选区里，往前拖从手指到词尾，往后拖从词头到手指。
    private var pressAnchor: Range<Int>?
    /// 拖拖柄时手指和拖柄所在那一行中点的差，拖的时候按这一行的位置算，手指不挡字。
    private var grabOffset: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = Self.inset
        textView.textContainer.lineFragmentPadding = 0
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.font = Self.font
        textView.isAccessibilityElement = true
        addSubview(textView)

        caret.isUserInteractionEnabled = false
        caret.layer.cornerRadius = 1
        textView.addSubview(caret)

        for handle in [startHandle, endHandle] {
            handle.isHidden = true
            textView.addSubview(handle)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(dragHandle(_:)))
            handle.addGestureRecognizer(pan)
            textView.panGestureRecognizer.require(toFail: pan)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        textView.addGestureRecognizer(tap)
        pressGesture.addTarget(self, action: #selector(pressed(_:)))
        pressGesture.minimumPressDuration = 0.35
        textView.addGestureRecognizer(pressGesture)
        // 按住不动 0.35 秒才算长按；手指一动就是滚动，长按跟着失败。
        textView.panGestureRecognizer.require(toFail: pressGesture)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if textView.frame != bounds { textView.frame = bounds }
        placeMarks()
        if needsScrollToCaret, bounds.height > 0 {
            needsScrollToCaret = false
            scrollToCaret()
        }
    }

    // MARK: 显示

    func render() {
        guard let model else { return }
        let draft = model.cardDraft
        let composition = model.composition
        var shown: Shown
        if let selection = model.cardSelection, !composition.isEmpty {
            // 选中时打拼音：拼音先显示在选区的位置，上屏时换掉选区。
            let removed = CardTextEditing.replacing(selection, in: draft, with: composition)
            shown = Shown(display: removed.text, composition: composition, caret: removed.caret, selection: nil, tint: tint)
        } else {
            let caret = min(max(model.cardCaret, 0), draft.count)
            let display = CardTextEditing.replacing(caret..<caret, in: draft, with: composition)
            shown = Shown(display: display.text, composition: composition, caret: display.caret,
                          selection: composition.isEmpty ? model.cardSelection : nil, tint: tint)
        }
        guard shown != self.shown else { return }
        let caretMoved = shown.caret != self.shown?.caret || shown.display != self.shown?.display
        self.shown = shown

        let attributed = NSMutableAttributedString(string: shown.display,
                                                   attributes: [.font: Self.font, .foregroundColor: UIColor.label])
        if !shown.composition.isEmpty {
            let start = shown.caret - shown.composition.count
            attributed.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: tint],
                                     range: nsRange(start..<shown.caret, in: shown.display))
        }
        if let selection = shown.selection {
            attributed.addAttribute(.backgroundColor, value: tint.withAlphaComponent(0.25),
                                    range: nsRange(selection, in: shown.display))
        }
        textView.attributedText = attributed
        textView.accessibilityValue = shown.display
        placeMarks()
        // 打字、删除、挪光标时让光标留在看得见的地方；拖选区时由拖动自己滚。
        if caretMoved, shown.selection == nil {
            if bounds.height > 0 { scrollToCaret() } else { needsScrollToCaret = true }
        }
    }

    private func placeMarks() {
        guard let shown else { return }
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        if let selection = shown.selection {
            caret.isHidden = true
            caret.layer.removeAllAnimations()
            startHandle.place(line: edgeRect(before: selection.lowerBound, in: shown.display), tint: shown.tint)
            endHandle.place(line: edgeRect(after: selection.upperBound, in: shown.display), tint: shown.tint)
            startHandle.isHidden = false
            endHandle.isHidden = false
        } else {
            startHandle.isHidden = true
            endHandle.isHidden = true
            let line = caretRect(at: shown.caret, in: shown.display)
            let height = min(18, line.height)
            let frame = CGRect(x: line.minX - 1, y: line.midY - height / 2, width: 2, height: height)
            let moved = caret.frame != frame || caret.isHidden
            caret.frame = frame
            caret.backgroundColor = shown.tint
            caret.isHidden = false
            // 打拼音时光标常亮；挪过以后重新从亮开始闪，和原来一样 0.5 秒一换。
            if !shown.composition.isEmpty {
                caret.layer.removeAllAnimations()
            } else if moved || caret.layer.animation(forKey: "blink") == nil {
                let blink = CAKeyframeAnimation(keyPath: "opacity")
                blink.values = [1, 1, 0, 0]
                blink.keyTimes = [0, 0.5, 0.5, 1]
                blink.duration = 1
                blink.repeatCount = .infinity
                caret.layer.removeAllAnimations()
                caret.layer.add(blink, forKey: "blink")
            }
        }
    }

    private func scrollToCaret() {
        guard let shown else { return }
        let rect = caretRect(at: shown.caret, in: shown.display)
        textView.scrollRectToVisible(rect.insetBy(dx: -2, dy: -Self.inset.top), animated: false)
    }

    // MARK: 排版位置（textView 内容坐标，含内边）

    /// 第 index 个字前面的光标位置：宽 0、高一行。
    private func caretRect(at index: Int, in text: String) -> CGRect {
        let layout = textView.layoutManager
        let length = (text as NSString).length
        let offset = CardTextEditing.utf16Offset(index, in: text)
        var rect: CGRect
        if length == 0 {
            rect = CGRect(x: 0, y: 0, width: 0, height: Self.font.lineHeight)
        } else if offset < length {
            let glyph = layout.glyphIndexForCharacter(at: offset)
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = layout.location(forGlyphAt: glyph)
            rect = CGRect(x: line.minX + location.x, y: line.minY, width: 0, height: line.height)
        } else if !layout.extraLineFragmentRect.isEmpty {
            // 最后是换行：光标在新的一行开头。
            let line = layout.extraLineFragmentRect
            rect = CGRect(x: line.minX, y: line.minY, width: 0, height: line.height)
        } else {
            return edgeRect(after: index, in: text)
        }
        return rect.offsetBy(dx: Self.inset.left, dy: Self.inset.top)
    }

    /// 选区开头：第 index 个字的左边，在这个字所在的那一行。
    private func edgeRect(before index: Int, in text: String) -> CGRect {
        caretRect(at: index, in: text)
    }

    /// 选区末尾：第 index - 1 个字的右边，在这个字所在的那一行（不跑到下一行开头）。
    private func edgeRect(after index: Int, in text: String) -> CGRect {
        let layout = textView.layoutManager
        guard index > 0, !text.isEmpty else { return caretRect(at: 0, in: text) }
        let end = CardTextEditing.utf16Offset(index, in: text)
        let start = CardTextEditing.utf16Offset(index - 1, in: text)
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: start, length: end - start), actualCharacterRange: nil)
        guard glyphs.length > 0 else { return caretRect(at: index, in: text) }
        let line = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let bounds = layout.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
        let x = text[text.index(text.startIndex, offsetBy: index - 1)].isNewline ? bounds.minX : bounds.maxX
        return CGRect(x: x, y: line.minY, width: 0, height: line.height)
            .offsetBy(dx: Self.inset.left, dy: Self.inset.top)
    }

    /// 手指点到的位置换成第几个字。between = true 时是两个字之间（放光标用，过了一个字的一半算到它后面）；
    /// false 时是压着的那个字（选词用）。
    private func characterIndex(at point: CGPoint, between: Bool) -> Int {
        guard let shown, !shown.display.isEmpty else { return 0 }
        let text = shown.display
        let layout = textView.layoutManager
        let container = textView.textContainer
        layout.ensureLayout(for: container)
        let local = CGPoint(x: point.x - Self.inset.left, y: point.y - Self.inset.top)
        if between, local.y > layout.usedRect(for: container).maxY { return text.count }
        if between, local.y < 0 { return 0 }
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        var offset = layout.characterIndexForGlyph(at: glyph)
        let string = text as NSString
        if between, fraction > 0.5, offset < string.length {
            let composed = string.rangeOfComposedCharacterSequence(at: offset)
            // 点在一行最右边、这一行以换行结束时，光标停在换行前面，不跑到下一行。
            if string.substring(with: composed) != "\n" { offset = NSMaxRange(composed) }
        }
        let index = CardTextEditing.characterIndex(utf16: offset, in: text)
        return between ? index : min(index, text.count - 1)
    }

    private func nsRange(_ range: Range<Int>, in text: String) -> NSRange {
        let start = CardTextEditing.utf16Offset(range.lowerBound, in: text)
        let end = CardTextEditing.utf16Offset(range.upperBound, in: text)
        return NSRange(location: start, length: max(0, end - start))
    }

    // MARK: 手势

    /// 正在打拼音时点、长按：先把拼音上屏，再按上屏后的文字算位置（不然位置会差拼音和汉字的长度差）。
    private func settleComposition() {
        guard let model, model.isComposing else { return }
        model.finishComposition()
        render()
        textView.layoutManager.ensureLayout(for: textView.textContainer)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let model else { return }
        settleComposition()
        model.beginCardEdit(caret: characterIndex(at: gesture.location(in: textView), between: true))
    }

    @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
        guard let model else { return }
        let point = gesture.location(in: textView)
        switch gesture.state {
        case .began:
            settleComposition()
            guard let word = CardTextEditing.wordRange(at: characterIndex(at: point, between: false), in: model.cardDraft)
            else { return }
            pressAnchor = word
            model.selectInCard(word)
            model.keyFeedback(for: .space)
        case .changed:
            guard let anchor = pressAnchor else { return }
            let index = characterIndex(at: point, between: true)
            if index < anchor.lowerBound {
                model.selectInCard(index..<anchor.upperBound)
            } else if index > anchor.upperBound {
                model.selectInCard(anchor.lowerBound..<index)
            } else {
                model.selectInCard(anchor)
            }
            autoScroll(near: point)
        default:
            pressAnchor = nil
        }
    }

    @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
        guard let model, let handle = gesture.view as? CardSelectionHandle else { return }
        let point = gesture.location(in: textView)
        switch gesture.state {
        case .began:
            grabOffset = CGPoint(x: handle.lineMid.x - point.x, y: handle.lineMid.y - point.y)
        case .changed:
            guard let selection = model.cardSelection else { return }
            let target = CGPoint(x: point.x + grabOffset.x, y: point.y + grabOffset.y)
            let index = characterIndex(at: target, between: true)
            // 两头拖过了对方就停在对方前一个字，至少留一个字。
            if handle.isStart {
                model.selectInCard(min(index, selection.upperBound - 1)..<selection.upperBound)
            } else {
                model.selectInCard(selection.lowerBound..<max(index, selection.lowerBound + 1))
            }
            autoScroll(near: point)
        default:
            break
        }
    }

    /// 拖到卡片上下边缘时往那边滚一点，选得到看不见的字。
    private func autoScroll(near point: CGPoint) {
        let visible = point.y - textView.contentOffset.y
        let maxOffset = max(0, textView.contentSize.height - textView.bounds.height)
        var offset = textView.contentOffset.y
        if visible < 14 {
            offset = max(0, offset - 6)
        } else if visible > textView.bounds.height - 14 {
            offset = min(maxOffset, offset + 6)
        }
        if offset != textView.contentOffset.y { textView.contentOffset.y = offset }
    }
}

/// 选区两头的拖柄：一条 2pt 竖线和这一行一样高，开头的圆点在上面、末尾的在下面（和系统一样）。
/// 看得见的部分很细，能按到的范围是 30 宽、上下各多 6，手指好按。
final class CardSelectionHandle: UIView {
    let isStart: Bool
    /// 拖柄所在那一行的中点（textView 内容坐标），拖的时候按它算位置。
    private(set) var lineMid: CGPoint = .zero
    private let stem = UIView()
    private let knob = UIView()
    private static let knobSize: CGFloat = 8
    private static let width: CGFloat = 30

    init(isStart: Bool) {
        self.isStart = isStart
        super.init(frame: .zero)
        backgroundColor = .clear
        stem.isUserInteractionEnabled = false
        knob.isUserInteractionEnabled = false
        knob.layer.cornerRadius = Self.knobSize / 2
        addSubview(stem)
        addSubview(knob)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func place(line: CGRect, tint: UIColor) {
        let knobSize = Self.knobSize
        frame = CGRect(x: line.minX - Self.width / 2, y: line.minY - knobSize,
                       width: Self.width, height: line.height + knobSize * 2)
        stem.frame = CGRect(x: Self.width / 2 - 1, y: knobSize, width: 2, height: line.height)
        knob.frame = CGRect(x: (Self.width - knobSize) / 2, y: isStart ? 0 : knobSize + line.height,
                            width: knobSize, height: knobSize)
        stem.backgroundColor = tint
        knob.backgroundColor = tint
        lineMid = CGPoint(x: line.minX, y: line.midY)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -6).contains(point)
    }
}
