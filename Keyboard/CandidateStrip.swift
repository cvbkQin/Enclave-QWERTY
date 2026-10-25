import SwiftUI
import UIKit

/// 候选栏里横向滚动的候选词，用 UIKit 自己判定点击。
/// SwiftUI 的 Button 放在横向 ScrollView 里：按下要等一下才有反应，手指稍微一动就当成滑动、这一下不算，快打时常点不中。
/// 这里按下立刻高亮；松手时手指没拖动过就算点击，选手指落点所在（或最近）的那个候选，不要求正好点在字上。
final class CandidateStripView: UIScrollView, UIScrollViewDelegate {
    var onSelect: ((Int) -> Void)?
    /// 滑到已取到的最后几个候选附近：再往后取。
    var onNearEnd: (() -> Void)?

    private var labels: [UILabel] = []
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
                let label = UILabel()
                label.font = Self.font
                label.textAlignment = .center
                addSubview(label)
                labels.append(label)
            }
            for (index, label) in labels.enumerated() {
                label.isHidden = index >= words.count
                if index < words.count { label.text = words[index] }
            }
            pressed = nil
            if !continued { contentOffset = .zero }
            setNeedsLayout()
        }
        for (index, label) in labels.enumerated() where index < words.count {
            label.textColor = index == 0 ? firstColor : .label
            label.alpha = index == pressed ? 0.45 : 1
        }
        if firstIsCommon, let first = labels.first, !words.isEmpty {
            if dot.superlayer == nil { first.layer.addSublayer(dot) }
        } else {
            dot.removeFromSuperlayer()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x = Self.leading
        for (index, label) in labels.enumerated() where index < words.count {
            let width = ceil((words[index] as NSString).size(withAttributes: [.font: Self.font]).width) + Self.padding * 2
            label.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
        }
        if let first = labels.first, !words.isEmpty {
            // 和原来一样：首选右上角，文字右边再往外 5pt。
            let textWidth = first.bounds.width - Self.padding * 2
            dot.position = CGPoint(x: Self.padding + textWidth + 5, y: first.bounds.midY - 10)
        }
        contentSize = CGSize(width: x, height: bounds.height)
    }

    /// 手指落点对应的候选：在哪个词的范围里就是哪个，落在两头外面取最近的。
    private func index(at point: CGPoint) -> Int? {
        let visible = labels.prefix(words.count)
        guard !visible.isEmpty else { return nil }
        if let hit = visible.firstIndex(where: { $0.frame.minX <= point.x && point.x < $0.frame.maxX }) { return hit }
        return point.x < (visible.first?.frame.minX ?? 0) ? 0 : visible.count - 1
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

struct CandidateStrip: UIViewRepresentable {
    @ObservedObject var model: KeyboardModel

    func makeUIView(context: Context) -> CandidateStripView {
        let view = CandidateStripView()
        view.onSelect = { [weak model] index in
            model?.keyFeedback(for: .space)
            model?.selectCandidate(index)
        }
        view.onNearEnd = { [weak model] in model?.loadMoreCandidates() }
        return view
    }

    func updateUIView(_ view: CandidateStripView, context: Context) {
        let words = Array(model.candidates.prefix(60))
        view.update(words: words, firstColor: UIColor(Brand.purpleText),
                    firstIsCommon: words.first.map { model.commonWordTexts.contains($0) } ?? false)
    }
}
