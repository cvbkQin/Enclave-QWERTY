import SwiftUI
import UIKit

/// 候选栏里横向滚动的候选词，用 UIKit 自己判定点击。
/// SwiftUI 的 Button 放在横向 ScrollView 里：按下要等一下才有反应，手指稍微一动就当成滑动、这一下不算，快打时常点不中。
/// 这里按下立刻高亮；松手时手指没拖动过就算点击，选手指落点所在（或最近）的那个候选，不要求正好点在字上。
final class CandidateStripView: UIScrollView, UIScrollViewDelegate {
    var onSelect: ((Int) -> Void)?
    /// 滑到已取到的最后几个候选附近：再往后取。
    var onNearEnd: (() -> Void)?
    /// 长按 0.45 秒：第几个、它在候选栏可见区域里的中心横坐标。
    var onLongPress: ((Int, CGFloat) -> Void)?

    private var labels: [CandidateLabel] = []
    private var words: [String] = []
    private var pressed: Int?
    /// 长按出气泡后这一下松手不算点击。
    private var longPressed = false
    /// 常用词右上角的橙点（每个常用词一个），和长按时被按的词的浅色底。
    private var dots: [CALayer] = []
    private var commonWords: Set<String> = []
    private let highlight = CALayer()
    private var highlighted: Int?
    private static let font = UIFont.systemFont(ofSize: 20)
    private static let padding: CGFloat = 11
    private static let leading: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        delaysContentTouches = false
        delegate = self
        // 不能完全透明，否则候选词之间、字旁边的空白点了没反应（同 KeyTouchView）。
        backgroundColor = UIColor(white: 0, alpha: 0.001)
        // iOS 26 默认给滚动视图边缘加一层渐隐模糊，候选栏这么矮会整条糊掉（和 SwiftUI 那边的 hidingScrollEdgeEffect 一样关掉）。
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            for effect in [topEdgeEffect, bottomEdgeEffect, leftEdgeEffect, rightEdgeEffect] {
                effect.isHidden = true
            }
        }
        #endif
        highlight.cornerRadius = 6
        highlight.isHidden = true
        layer.insertSublayer(highlight, at: 0)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        press.minimumPressDuration = 0.45
        press.cancelsTouchesInView = false
        addGestureRecognizer(press)
    }

    @objc private func longPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, !isDragging, let index = index(at: recognizer.location(in: self)),
              index < frames.count else { return }
        longPressed = true
        setPressed(nil)
        onLongPress?(index, frames[index].midX - contentOffset.x)
    }

    /// 长按气泡开着时被按的词浅色底：比字外扩 6、圆角 6。
    func setHighlighted(_ index: Int?) {
        guard index != highlighted else { return }
        highlighted = index
        guard let index, index < frames.count, index < words.count else {
            highlight.isHidden = true
            return
        }
        let textWidth = frames[index].width - Self.padding * 2
        let height = min(bounds.height - 4, Self.font.lineHeight + 12)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.backgroundColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.08) }.resolvedColor(with: traitCollection).cgColor
        highlight.frame = CGRect(x: frames[index].midX - textWidth / 2 - 6, y: (bounds.height - height) / 2,
                                 width: textWidth + 12, height: height)
        highlight.isHidden = false
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 换了一组候选：新的拼音从头显示，只是往后多取了候选就保持滚动位置。
    func update(words newWords: [String], firstColor: UIColor, commonWords newCommon: Set<String>) {
        let continued = !words.isEmpty && newWords.count > words.count && Array(newWords.prefix(words.count)) == words
        if newWords != words {
            words = newWords
            while labels.count < words.count {
                let label = CandidateLabel()
                label.font = Self.font
                label.textAlignment = .center
                label.index = labels.count
                label.isHidden = true
                label.onActivate = { [weak self] index in self?.onSelect?(index) }
                // VoiceOver 没法长按：「更多操作」打开同一个气泡（删除 / 置顶 / 从常用词移除）。
                label.onMore = { [weak self] index in
                    guard let self, index < self.frames.count else { return }
                    self.onLongPress?(index, self.frames[index].midX - self.contentOffset.x)
                }
                addSubview(label)
                labels.append(label)
            }
            // 前面几个词没变的话（往后多取了候选）不用重填。
            filled = continued ? filled : 0
            pressed = nil
            if !continued { contentOffset = .zero }
            setNeedsLayout()
        }
        self.firstColor = firstColor
        if newCommon != commonWords {
            commonWords = newCommon
            for index in 0..<min(filled, words.count) { placeDot(index) }
        }
        for index in 0..<min(filled, words.count) { style(index) }
    }

    /// 常用词标记：候选词框内侧右上角 5pt 橙点（#FF9F0A），相对文字右边 −3、上边 −2，不碰字。
    private func placeDot(_ index: Int) {
        while dots.count <= index {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
            dot.cornerRadius = 2.5
            dot.backgroundColor = UIColor(Brand.warning).cgColor
            dot.actions = ["position": NSNull(), "hidden": NSNull()]
            dots.append(dot)
        }
        let dot = dots[index], label = labels[index]
        let common = index < words.count && commonWords.contains(words[index])
        if common {
            if dot.superlayer !== label.layer { label.layer.addSublayer(dot) }
            let textWidth = label.bounds.width - Self.padding * 2
            let textTop = (label.bounds.height - Self.font.lineHeight) / 2
            dot.position = CGPoint(x: Self.padding + textWidth + 3 - 2.5, y: textTop - 2 + 2.5)
            dot.isHidden = false
        } else {
            dot.isHidden = true
        }
    }

    private var firstColor: UIColor = .label
    /// 前面这么多个候选已经填好了字。快打时每个键都换一组候选，一次只填看得见的（加上往后一屏），
    /// 后面的滑过去时再填：给 60 个词设字、排字是候选栏最慢的地方。
    private var filled = 0

    /// 没变就不设：设一次就要重画这个词。
    private func style(_ index: Int) {
        let label = labels[index]
        let color = index == 0 ? firstColor : .label
        if label.textColor != color { label.textColor = color }
        let alpha: CGFloat = index == pressed ? 0.45 : 1
        if label.alpha != alpha { label.alpha = alpha }
    }

    /// 词宽：都是汉字时按字数乘一个字宽算，不用每次让 CoreText 排一遍；有字母、符号的才量，量过的记下来。
    private static var widthCache: [String: CGFloat] = [:]
    private static let hanWidth = ("中" as NSString).size(withAttributes: [.font: font]).width

    private static func width(of word: String) -> CGFloat {
        if word.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }) {
            return ceil(hanWidth * CGFloat(word.unicodeScalars.count)) + padding * 2
        }
        if let cached = widthCache[word] { return cached }
        if widthCache.count > 500 { widthCache.removeAll() }
        let width = ceil((word as NSString).size(withAttributes: [.font: font]).width) + padding * 2
        widthCache[word] = width
        return width
    }

    /// 上次排版时的候选和高度：滚动时 layoutSubviews 每帧都会调，没变就不重新算字宽、摆位置。
    private var laidOut: (words: [String], height: CGFloat)?
    private var frames: [CGRect] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        let changed = laidOut == nil || laidOut!.words != words || laidOut!.height != bounds.height
        if changed {
            laidOut = (words, bounds.height)
            var x = Self.leading
            frames = words.map { word in
                let width = Self.width(of: word)
                defer { x += width }
                return CGRect(x: x, y: 0, width: width, height: bounds.height)
            }
            for (index, label) in labels.enumerated() where index < filled && index < words.count {
                label.frame = frames[index]
                placeDot(index)
            }
            highlighted = nil
            highlight.isHidden = true
            contentSize = CGSize(width: x, height: bounds.height)
        }
        fill(upTo: contentOffset.x + bounds.width * 2)
        if changed {
            // 这次没填到的（包括上一组多出来的）先藏起来，免得滑过去看到上一组的词。
            for label in labels.dropFirst(filled) where !label.isHidden { label.isHidden = true }
        }
    }

    /// 把右边到 maxX 为止的候选填上字。
    private func fill(upTo maxX: CGFloat) {
        while filled < words.count, filled < frames.count, frames[filled].minX < maxX {
            let label = labels[filled]
            if label.text != words[filled] { label.text = words[filled] }
            label.frame = frames[filled]
            label.isHidden = false
            placeDot(filled)
            style(filled)
            filled += 1
        }
    }

    /// 手指落点对应的候选：在哪个词的范围里就是哪个，落在两头外面取最近的。
    private func index(at point: CGPoint) -> Int? {
        let visible = frames.prefix(filled)
        guard !visible.isEmpty else { return nil }
        if let hit = visible.firstIndex(where: { $0.minX <= point.x && point.x < $0.maxX }) { return hit }
        return point.x < (visible.first?.minX ?? 0) ? 0 : visible.count - 1
    }

    private func setPressed(_ index: Int?) {
        if let old = pressed, old < labels.count { labels[old].alpha = 1 }
        pressed = index
        if let index { labels[index].alpha = 0.45 }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        longPressed = false
        guard let touch = touches.first, !isDecelerating else { return }
        setPressed(index(at: touch.location(in: self)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        defer { setPressed(nil) }
        guard let touch = touches.first, !isDragging, !longPressed, let index = index(at: touch.location(in: self)) else { return }
        onSelect?(index)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        setPressed(nil)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if pressed != nil && isDragging { setPressed(nil) }
        if contentOffset.x + bounds.width > contentSize.width - 60 { onNearEnd?() }
    }
}

/// 一个候选词。VoiceOver 和 UI 测试按按钮读出、点按它。
private final class CandidateLabel: UILabel {
    var index = 0
    var onActivate: ((Int) -> Void)?
    var onMore: ((Int) -> Void)?

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            [UIAccessibilityCustomAction(name: L("更多操作", "More actions", "その他の操作")) { [weak self] _ in
                guard let self else { return false }
                self.onMore?(self.index)
                return true
            }]
        }
        set {}
    }

    override var isAccessibilityElement: Bool { get { !isHidden } set {} }
    override var accessibilityTraits: UIAccessibilityTraits { get { .button } set {} }

    override func accessibilityActivate() -> Bool {
        onActivate?(index)
        return true
    }
}

struct CandidateStrip: UIViewRepresentable {
    @ObservedObject var model: KeyboardModel

    func makeUIView(context: Context) -> CandidateStripView {
        let view = CandidateStripView()
        view.onSelect = { [weak model] index in
            guard let model else { return }
            if model.candidateMenu != nil { return model.dismissCandidateMenu() }
            model.keyFeedback(for: .space)
            if model.isComposing { model.selectCandidate(index) } else { model.selectPrediction(index) }
        }
        view.onNearEnd = { [weak model] in model?.loadMoreCandidates() }
        view.onLongPress = { [weak model] index, midX in
            guard let model, model.isComposing else { return }
            model.showCandidateMenu(index: index, midX: midX)
        }
        return view
    }

    func updateUIView(_ view: CandidateStripView, context: Context) {
        // 没在打拼音时显示联想：不标常用词；开了「空格连续联想」时第一个也变色，和打字时一样提示按空格上屏的是它。
        guard model.isComposing else {
            view.update(words: model.predictions, firstColor: Predictor.spaceChains && model.chineseMode ? UIColor(Brand.purpleText) : .label,
                        commonWords: [])
            view.setHighlighted(nil)
            return
        }
        let words = Array(model.candidates.prefix(60))
        view.update(words: words, firstColor: UIColor(Brand.purpleText), commonWords: model.commonWordTexts)
        view.setHighlighted(model.candidateMenu?.index)
    }
}

/// 长按候选弹出的深色小气泡（CL1–CL3）：在候选栏下方，尖角朝上指着被按的词；38 高、圆角 10，项之间 0.5pt 分隔线。
struct CandidateMenuBubble: View {
    @ObservedObject var model: KeyboardModel
    let menu: KeyboardModel.CandidateMenu
    let barWidth: CGFloat

    private static let arrow: CGFloat = 6

    private func title(_ action: KeyboardModel.CandidateMenu.Action) -> String {
        switch action {
        case .delete: return L("删除", "Delete", "削除")
        case .pin: return L("置顶", "Pin", "トップに固定")
        case .removeCommon: return L("从常用词移除", "Remove from My Words", "よく使う言葉から削除")
        }
    }

    var body: some View {
        let items = HStack(spacing: 0) {
            ForEach(Array(menu.actions.enumerated()), id: \.offset) { offset, action in
                if offset > 0 {
                    Rectangle().fill(Brand.candidateMenuText.opacity(0.3)).frame(width: 0.5, height: 22)
                }
                Button { model.performCandidateMenu(action) } label: {
                    Text(title(action))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Brand.candidateMenuText)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KeyPressStyle())
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.candidateMenuFill))
        .fixedSize()

        let top = KeyboardMetrics.topRow - 2
        return ZStack(alignment: .topLeading) {
            Triangle()
                .fill(Brand.candidateMenuFill)
                .frame(width: Self.arrow * 2, height: Self.arrow)
                .offset(x: menu.midX - Self.arrow, y: top)
            items
                .alignmentGuide(.leading) { d in
                    // 气泡居中对准被按的词，两边不出键盘（各留 6）。
                    -min(max(menu.midX - d.width / 2, 6), max(barWidth - d.width - 6, 6))
                }
                .offset(y: top + Self.arrow)
        }
        .frame(width: barWidth, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

/// 尖角朝上的小三角。
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
