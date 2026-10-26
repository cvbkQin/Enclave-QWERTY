import SwiftUI
import UIKit

/// 候选栏里横向滚动的候选词，用 UIKit 自己判定点击。
/// SwiftUI 的 Button 放在横向 ScrollView 里：按下要等一下才有反应，手指稍微一动就当成滑动、这一下不算，快打时常点不中。
/// 这里按下立刻高亮；松手时手指没拖动过就算点击，选手指落点所在（或最近）的那个候选，不要求正好点在字上。
final class CandidateStripView: UIScrollView, UIScrollViewDelegate {
    var onSelect: ((Int) -> Void)?
    /// 滑到已取到的最后几个候选附近：再往后取。
    var onNearEnd: (() -> Void)?

    private var labels: [CandidateLabel] = []
    private var words: [String] = []
    private var pressed: Int?
    private let dot = CALayer()
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
        dot.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
        dot.cornerRadius = 2.5
        dot.backgroundColor = UIColor(Brand.commonWordDot).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 换了一组候选：新的拼音从头显示，只是往后多取了候选就保持滚动位置。
    func update(words newWords: [String], firstColor: UIColor, firstIsCommon: Bool) {
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
        for index in 0..<min(filled, words.count) { style(index) }
        if firstIsCommon, let first = labels.first, !words.isEmpty {
            if dot.superlayer == nil { first.layer.addSublayer(dot) }
        } else {
            dot.removeFromSuperlayer()
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
            }
            if let first = frames.first {
                // 和原来一样：首选右上角，文字右边再往外 5pt。
                let textWidth = first.width - Self.padding * 2
                dot.position = CGPoint(x: Self.padding + textWidth + 5, y: first.midY - 10)
            }
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
        guard let touch = touches.first, !isDecelerating else { return }
        setPressed(index(at: touch.location(in: self)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        defer { setPressed(nil) }
        guard let touch = touches.first, !isDragging, let index = index(at: touch.location(in: self)) else { return }
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
            model.keyFeedback(for: .space)
            if model.isComposing { model.selectCandidate(index) } else { model.selectPrediction(index) }
        }
        view.onNearEnd = { [weak model] in model?.loadMoreCandidates() }
        return view
    }

    func updateUIView(_ view: CandidateStripView, context: Context) {
        // 没在打拼音时显示联想：不标常用词；开了「空格连续联想」时第一个也变色，和打字时一样提示按空格上屏的是它。
        guard model.isComposing else {
            view.update(words: model.predictions, firstColor: Predictor.spaceChains && model.chineseMode ? UIColor(Brand.purpleText) : .label,
                        firstIsCommon: false)
            return
        }
        let words = Array(model.candidates.prefix(60))
        view.update(words: words, firstColor: UIColor(Brand.purpleText),
                    firstIsCommon: words.first.map { model.commonWordTexts.contains($0) } ?? false)
    }
}
