import NaturalLanguage
import SwiftUI

/// 分词面板拆出来的一块：词或标点，按原文顺序。
struct WordToken: Identifiable, Equatable {
    let id: Int
    let text: String
    let punctuation: Bool
    /// 拉丁字母的词：拼起来时和前一个英文词之间加空格。
    let latin: Bool

    /// 用系统分词（NLTokenizer）拆，英文按词；词和词中间的标点各成一块，空白丢掉。
    static func split(_ text: String) -> [WordToken] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var pieces: [(String, Bool)] = []
        var cursor = text.startIndex
        func addGap(_ gap: Substring) {
            for char in gap where !char.isWhitespace { pieces.append((String(char), true)) }
        }
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            addGap(text[cursor..<range.lowerBound])
            pieces.append((String(text[range]), false))
            cursor = range.upperBound
            return true
        }
        addGap(text[cursor...])
        return pieces.enumerated().map { index, piece in
            WordToken(id: index, text: piece.0, punctuation: piece.1,
                      latin: !piece.1 && piece.0.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) })
        }
    }

    /// 按原顺序拼起来，中间不加空格，两个英文词之间加一个空格。
    static func join(_ tokens: [WordToken]) -> String {
        var out = ""
        var previousLatin = false
        for token in tokens {
            if token.latin && previousLatin { out += " " }
            out += token.text
            previousLatin = token.latin
        }
        return out
    }
}

/// 长按结果卡打开的分词面板（BB1–BB5）：盖住按键区，直角框里是提示行、词块、底栏。
/// 词块区是 UIKit 自己滚动（WordGridView），划选和点选也在那边判定，SwiftUI 这里只管选了哪些。
struct WordPanel: View {
    @ObservedObject var model: KeyboardModel
    @State private var tokens: [WordToken] = []
    @State private var selected: Set<Int> = []

    var body: some View {
        VStack(spacing: 8) {
            hintRow
            WordGrid(tokens: tokens, selected: $selected, haptics: model.settings.keyHaptics && model.hasFullAccess)
            bottomBar
        }
        .padding(8)
        .background(Rectangle().fill(Brand.wordPanelFill))
        .overlay(Rectangle().strokeBorder(Brand.wordPanelStroke, lineWidth: 1))
        .onAppear { tokens = WordToken.split(model.wordPanelText) }
    }

    private var hintRow: some View {
        HStack {
            Text(selected.isEmpty
                 ? L("点选，或按住横着划选；竖着划是滚动", "Tap or drag sideways to select; swipe up and down to scroll", "タップか横になぞって選択、縦はスクロール")
                 : L("已选 \(selected.count) 个", "\(selected.count) selected", "\(selected.count) 個選択"))
            Spacer(minLength: 8)
            Text(L("长按结果卡打开", "Long-press the result to open", "結果を長押しで開く"))
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        // VoiceOver 读不了「划选」：换成能照着做的一句。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selected.isEmpty
            ? L("分词面板。轻点两下选中一个词，再点插入或复制", "Word panel. Double-tap words to select them, then Insert or Copy", "単語パネル。ダブルタップで単語を選び、挿入かコピーを押します")
            : L("已选 \(selected.count) 个", "\(selected.count) selected", "\(selected.count) 個選択"))
    }

    private var chosenText: String {
        WordToken.join(tokens.filter { selected.contains($0.id) })
    }

    private var bottomBar: some View {
        GeometryReader { geo in
            // 插入、复制一样大；「全选」和「×」一样大，宽度比 1.5 : 1。
            let gap: CGFloat = 6
            let unit = (geo.size.width - gap * 3) / 5
            let empty = selected.isEmpty
            let all = !tokens.isEmpty && selected.count == tokens.count
            HStack(spacing: gap) {
                barButton(L("插入", "Insert", "挿入"), fill: AnyShapeStyle(LinearGradient(colors: Brand.insertGradient, startPoint: .topLeading, endPoint: .bottomTrailing)),
                          text: .white, width: unit * 1.5, enabled: !empty) { model.insertWords(chosenText) }
                barButton(L("复制", "Copy", "コピー"), fill: AnyShapeStyle(LinearGradient(colors: Brand.copyGradient, startPoint: .topLeading, endPoint: .bottomTrailing)),
                          text: .white, width: unit * 1.5, enabled: !empty) { model.copyWords(chosenText) }
                barButton(all ? L("全不选", "None", "全解除") : L("全选", "All", "全選択"), fill: AnyShapeStyle(KeyStyle.charKey),
                          text: .primary, width: unit, enabled: !tokens.isEmpty) {
                    selected = all ? [] : Set(tokens.map(\.id))
                }
                barButton("", icon: "xmark", fill: AnyShapeStyle(KeyStyle.charKey), text: .primary, width: unit, enabled: true) {
                    model.closeWordPanel()
                }
                .accessibilityLabel(L("关闭", "Close", "閉じる"))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 34)
    }

    private func barButton(_ title: String, icon: String? = nil, fill: AnyShapeStyle, text: Color, width: CGFloat,
                           enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                } else {
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(text)
            .frame(width: width, height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// 词块区：系统滚动 + 只在横着划时才开始的划选手势（BB5）。
private struct WordGrid: UIViewRepresentable {
    let tokens: [WordToken]
    @Binding var selected: Set<Int>
    let haptics: Bool

    func makeUIView(context: Context) -> WordGridView {
        let view = WordGridView()
        view.onChange = { selected = $0 }
        return view
    }

    func updateUIView(_ view: WordGridView, context: Context) {
        view.onChange = { selected = $0 }
        view.haptics = haptics
        view.update(tokens: tokens, selected: selected)
    }
}

/// 词块排成流式多行，自己滚动。
/// - 手指走过 10pt 按方向定：|dy| ≥ 0.6|dx| 交给系统滚动（按下的词不变色）；更平才进划选。
/// - 划选：从起点词按阅读顺序一路选到手指下的词，能跨行；起点原来没选就加选，选了就取消选；靠近上下边 32pt 自动滚；每变一个词轻震。
/// - 点选：10pt 内抬起算一下，抬起时变色（0.12 秒过渡），不缩放、不改大小。按下时只轻微变暗。
final class WordGridView: UIScrollView {
    var onChange: ((Set<Int>) -> Void)?
    var haptics = false

    private var tokens: [WordToken] = []
    private var selected: Set<Int> = []
    private var chips: [UILabel] = []
    private var frames: [CGRect] = []
    private var laidOutWidth: CGFloat = -1

    private static let font = UIFont.systemFont(ofSize: 14)
    private static let chipHeight: CGFloat = 30
    private static let gap: CGFloat = 5
    private static let lineGap: CGFloat = 6
    private static let fadeTop: CGFloat = 18
    private static let fadeBottom: CGFloat = 22

    /// 划选：起点、是加选还是取消选、划之前的选中、上次手指所在的词。
    private var sweep: (start: Int, adding: Bool, base: Set<Int>, last: Int)?
    private var sweepPoint: CGPoint?
    private var autoScroll: CADisplayLink?
    private let feedback = UISelectionFeedbackGenerator()
    private var pressed: Int?
    private let fadeMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        alwaysBounceVertical = true
        delaysContentTouches = false
        showsHorizontalScrollIndicator = false
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            for effect in [topEdgeEffect, bottomEdgeEffect, leftEdgeEffect, rightEdgeEffect] { effect.isHidden = true }
        }
        #endif
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSweep(_:)))
        sweepGate.view = self
        pan.delegate = sweepGate
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        // 滚动等划选先表态：划选只在横着划时开始，竖着划它不开始，滚动接着走。
        panGestureRecognizer.require(toFail: pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        // 上下渐隐：底部一直有（提示下面还有），滚下来后顶部也有。
        fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        layer.mask = fadeMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(tokens newTokens: [WordToken], selected newSelected: Set<Int>) {
        if newTokens != tokens {
            tokens = newTokens
            chips.forEach { $0.removeFromSuperview() }
            chips = tokens.map { token in
                let label = UILabel()
                label.text = token.text
                label.font = Self.font
                label.textAlignment = .center
                label.layer.cornerRadius = 7
                label.layer.cornerCurve = .continuous
                label.layer.masksToBounds = true
                label.isAccessibilityElement = true
                label.accessibilityTraits = .button
                addSubview(label)
                return label
            }
            laidOutWidth = -1
            setNeedsLayout()
        }
        // 划选进行中以这里自己的状态为准，SwiftUI 回传的旧值不覆盖。
        guard sweep == nil, newSelected != selected else { return }
        let changed = selected.symmetricDifference(newSelected)
        selected = newSelected
        for index in changed where index < chips.count { style(index, animated: true) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = CGRect(origin: contentOffset, size: bounds.size)
        let h = max(bounds.height, 1)
        let top = contentOffset.y > 1 ? Self.fadeTop / h : 0
        fadeMask.colors = [UIColor.black.withAlphaComponent(top > 0 ? 0 : 1).cgColor, UIColor.black.cgColor,
                           UIColor.black.cgColor, UIColor.black.withAlphaComponent(contentSize.height > bounds.height + 1 ? 0 : 1).cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(top)), NSNumber(value: Double(1 - Self.fadeBottom / h)), 1]
        CATransaction.commit()
        guard bounds.width != laidOutWidth else { return }
        laidOutWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0
        frames = tokens.map { token in
            let padding: CGFloat = token.punctuation ? 5 : 8
            let text = ceil((token.text as NSString).size(withAttributes: [.font: Self.font]).width)
            let width = min(max(text + padding * 2, token.punctuation ? 22 : 30), bounds.width)
            if x > 0 && x + width > bounds.width {
                x = 0
                y += Self.chipHeight + Self.lineGap
            }
            defer { x += width + Self.gap }
            return CGRect(x: x, y: y, width: width, height: Self.chipHeight)
        }
        for (index, chip) in chips.enumerated() {
            chip.frame = frames[index]
            style(index, animated: false)
        }
        contentSize = CGSize(width: bounds.width, height: (frames.last?.maxY ?? 0) + Self.fadeBottom)
        if contentSize.height > bounds.height { flashScrollIndicators() }
    }

    private func style(_ index: Int, animated: Bool) {
        let chip = chips[index], token = tokens[index]
        let on = selected.contains(index)
        let apply = {
            var fill = on ? UIColor(Brand.purple) : UIColor(KeyStyle.charKey)
            if index == self.pressed && !on {
                fill = fill.blended(with: self.traitCollection.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.06))
            }
            chip.backgroundColor = fill
            chip.textColor = on ? .white : (token.punctuation ? .secondaryLabel : .label)
        }
        chip.accessibilityTraits = on ? [.button, .selected] : .button
        if animated {
            UIView.transition(with: chip, duration: 0.12, options: [.transitionCrossDissolve, .allowUserInteraction], animations: apply)
        } else {
            apply()
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        for index in chips.indices { style(index, animated: false) }
    }

    // MARK: 按下变暗、点选

    private func index(at point: CGPoint) -> Int? {
        frames.firstIndex { $0.insetBy(dx: -2.5, dy: -3).contains(point) }
    }

    private func setPressed(_ index: Int?) {
        let old = pressed
        pressed = index
        for i in [old, index].compactMap({ $0 }) where i < chips.count { style(i, animated: false) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first, !isDecelerating { setPressed(index(at: touch.location(in: self))) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if isDragging, pressed != nil { setPressed(nil) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        setPressed(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        setPressed(nil)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let index = index(at: recognizer.location(in: self)) else { return }
        setPressed(nil)
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        style(index, animated: true)
        if haptics { feedback.selectionChanged() }
        onChange?(selected)
    }

    // MARK: 划选

    private let sweepGate = SweepGate()

    /// 划选手势能不能开始：手指走过约 10pt 时看方向，|dy| ≥ 0.6|dx| 偏竖就不开始（交给滚动），起点要在词上。
    fileprivate func sweepShouldBegin(_ pan: UIPanGestureRecognizer) -> Bool {
        let t = pan.translation(in: self)
        guard abs(t.y) < 0.6 * abs(t.x) else { return false }
        let point = pan.location(in: self)
        return index(at: CGPoint(x: point.x - t.x, y: point.y - t.y)) != nil || index(at: point) != nil
    }

    @objc private func handleSweep(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: self)
        switch pan.state {
        case .began:
            setPressed(nil)
            let t = pan.translation(in: self)
            let origin = CGPoint(x: point.x - t.x, y: point.y - t.y)
            guard let start = index(at: origin) ?? index(at: point) else { return }
            sweep = (start, !selected.contains(start), selected, start)
            if haptics { feedback.prepare() }
            extendSweep(to: point)
            startAutoScroll()
        case .changed:
            sweepPoint = point
            extendSweep(to: point)
        default:
            stopAutoScroll()
            sweep = nil
            sweepPoint = nil
            onChange?(selected)
        }
        sweepPoint = point
    }

    /// 手指下的词：落在两个词之间时取同一行左边那个，行外取最近的一行。
    private func nearestIndex(to point: CGPoint) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let hit = index(at: point) { return hit }
        let rowY = frames.map(\.midY).min { abs($0 - point.y) < abs($1 - point.y) } ?? 0
        let row = frames.indices.filter { frames[$0].midY == rowY }
        return row.last { frames[$0].minX <= point.x } ?? row.first
    }

    private func extendSweep(to point: CGPoint) {
        guard var current = sweep, let target = nearestIndex(to: point) else { return }
        guard target != current.last else { return }
        current.last = target
        sweep = current
        let range = Set(min(current.start, target)...max(current.start, target))
        let next = current.adding ? current.base.union(range) : current.base.subtracting(range)
        let changed = selected.symmetricDifference(next)
        guard !changed.isEmpty else { return }
        selected = next
        for index in changed { style(index, animated: false) }
        if haptics { feedback.selectionChanged() }
        onChange?(selected)
    }

    private func startAutoScroll() {
        guard autoScroll == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick))
        link.add(to: .main, forMode: .common)
        autoScroll = link
    }

    private func stopAutoScroll() {
        autoScroll?.invalidate()
        autoScroll = nil
    }

    /// 手指在面板上下边 32pt 以内：越靠边滚得越快。
    @objc private func autoScrollTick() {
        guard let point = sweepPoint else { return }
        let y = point.y - contentOffset.y
        let edge: CGFloat = 32
        var speed: CGFloat = 0
        if y < edge { speed = -(edge - y) / edge * 8 } else if y > bounds.height - edge { speed = (y - (bounds.height - edge)) / edge * 8 }
        guard speed != 0 else { return }
        let maxY = max(contentSize.height - bounds.height, 0)
        let newY = min(max(contentOffset.y + speed, 0), maxY)
        guard newY != contentOffset.y else { return }
        let delta = newY - contentOffset.y
        contentOffset.y = newY
        sweepPoint = CGPoint(x: point.x, y: point.y + delta)
        extendSweep(to: sweepPoint!)
    }
}

/// 划选手势的代理：滚动视图自己已经是它自带 pan 的代理，划选另用一个小对象判断。
private final class SweepGate: NSObject, UIGestureRecognizerDelegate {
    weak var view: WordGridView?

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, let view else { return false }
        return view.sweepShouldBegin(pan)
    }
}

private extension UIColor {
    /// 在自己上面叠一层半透明色。
    func blended(with overlay: UIColor) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        overlay.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 * (1 - a2) + r2 * a2, green: g1 * (1 - a2) + g2 * a2, blue: b1 * (1 - a2) + b2 * a2, alpha: a1)
    }
}
