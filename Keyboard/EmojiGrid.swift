import SwiftUI
import UIKit

/// 表情面板里的表情格子（bug #39）。
/// 原来是 SwiftUI LazyVGrid + Text：滑过的格子都留着不放，每个表情画出来的位图也跟着留着。从头滑到国旗，模拟器上
/// 键盘进程冲到 133 MB，关掉面板还留着 1,800 多张表情图，要等下次弹出才放掉；键盘扩展的内存上限远低于这个，真机上有被系统杀掉的风险。
/// 这里换成 UICollectionView：只画看得见的几排，滑出去的格子拿来重用，滑到哪儿内存都差不多。
/// 样子照原来：格子 40、表情 30pt（iPad 54、38）；一行放得下几个放几个，平均分；行距 2，左右各留 4；
/// 每类上面一行 12pt 灰色小标题，滑到顶上钉住。
/// 手感：按下马上变暗（同 KeyPressStyle），手指没滑走就在抬起时上屏；两只手交替点各算各的；
/// 面板还在惯性滚动时点一下只是让它停住，不上屏（同系统表情键盘）。
struct EmojiGrid: UIViewRepresentable {
    let sections: [EmojiPanelSection]
    let handle: EmojiGridHandle
    let onPick: (String) -> Void
    /// 手指滑动后顶上换成了哪一类。点底栏跳过去的不报，底栏那边自己已经选上了。
    let onCurrent: (String) -> Void

    func makeUIView(context: Context) -> EmojiGridView {
        let view = EmojiGridView(pad: KeyboardMetrics.pad != nil)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: EmojiGridView, context: Context) {
        handle.view = view
        view.onPick = onPick
        view.onCurrent = onCurrent
        view.update(sections: sections, pad: KeyboardMetrics.pad != nil)
    }
}

/// SymbolPanel 用它叫格子跳到某一类（点底栏的分类）。
final class EmojiGridHandle {
    weak var view: EmojiGridView?
}

final class EmojiGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onPick: ((String) -> Void)?
    var onCurrent: ((String) -> Void)?

    private let collection: UICollectionView
    private var sections: [EmojiPanelSection] = []
    private var pad: Bool
    /// 各类小标题没钉住时的顶边（内容坐标），布局宽度变了重算。
    private var tops: [CGFloat] = []
    private var topsWidth: CGFloat = -1
    /// 最后报给底栏的那一类。
    private var reported: String?
    /// 手指拖动、惯性滚动最后一次挪动的时刻：这之后 0.1 秒内按下算「让它停住」，不算点表情。
    private var lastMoved: CFTimeInterval = 0
    /// 点底栏分类后正在滚过去：起点、终点、开始时刻。
    private var jumpAnimation: (from: CGFloat, to: CGFloat, began: CFTimeInterval)?
    private var jumpLink: CADisplayLink?

    fileprivate static let headerFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    /// 小标题：一行 12pt 字，上下各 3（同原来 SwiftUI 的 .padding(.vertical, 3)）。
    fileprivate static let headerHeight: CGFloat = ceil(headerFont.lineHeight) + 6
    fileprivate static let side: CGFloat = 4
    private static let rowGap: CGFloat = 2
    /// 点分类滚过去用 0.2 秒（EP1）。
    private static let jumpDuration: CFTimeInterval = 0.2

    private static func cellSize(pad: Bool) -> CGFloat { pad ? 54 : 40 }
    private var font: UIFont { .systemFont(ofSize: pad ? 38 : 30) }

    init(pad: Bool) {
        self.pad = pad
        collection = UICollectionView(frame: .zero, collectionViewLayout: EmojiGridView.layout(cell: EmojiGridView.cellSize(pad: pad)))
        super.init(frame: .zero)
        backgroundColor = .clear
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        // 点表情由格子自己判断（见 EmojiCell），不用系统的选中。
        collection.allowsSelection = false
        collection.alwaysBounceVertical = true
        collection.showsVerticalScrollIndicator = false
        collection.showsHorizontalScrollIndicator = false
        collection.contentInsetAdjustmentBehavior = .never
        // 按下马上变暗，不等滚动视图那 0.15 秒；开始滑动时系统照样取消这一下。
        collection.delaysContentTouches = false
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuse)
        collection.register(EmojiHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                            withReuseIdentifier: EmojiHeader.reuse)
        // iOS 26 默认给滚动视图边缘加一层渐隐模糊，盖住顶上一排表情（同 hidingScrollEdgeEffect）。
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            for effect in [collection.topEdgeEffect, collection.bottomEdgeEffect, collection.leftEdgeEffect, collection.rightEdgeEffect] {
                effect.isHidden = true
            }
        }
        #endif
        addSubview(collection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 一行放 n 个：n = (宽 − 8) ÷ 格子 取整，同原来 GridItem(.adaptive(minimum: 格子))。
    /// 每格取整点宽，余下不到 n 点分到两边，表情落在整像素上不发虚。
    private static func layout(cell: CGFloat) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let inner = environment.container.effectiveContentSize.width - EmojiGridView.side * 2
            let columns = max(1, Int(inner / cell))
            let width = max(floor(inner / CGFloat(columns)), 1)
            let extra = max(inner - width * CGFloat(columns), 0)
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(width),
                                                                                 heightDimension: .absolute(cell)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(width * CGFloat(columns)), heightDimension: .absolute(cell)),
                repeatingSubitem: item, count: columns)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = EmojiGridView.rowGap
            let leading = EmojiGridView.side + floor(extra / 2)
            section.contentInsets = NSDirectionalEdgeInsets(top: EmojiGridView.rowGap, leading: leading, bottom: EmojiGridView.rowGap,
                                                            trailing: EmojiGridView.side + extra - floor(extra / 2))
            // 小标题铺满整宽，字从左边 4 开始（不跟着上面分到两边的余量挪）。
            section.supplementariesFollowContentInsets = false
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(EmojiGridView.headerHeight)),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            header.pinToVisibleBounds = true
            header.zIndex = 2
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if collection.frame != bounds { collection.frame = bounds }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopJump() }
    }

    func update(sections new: [EmojiPanelSection], pad newPad: Bool) {
        let padChanged = newPad != pad
        if padChanged {
            pad = newPad
            collection.setCollectionViewLayout(Self.layout(cell: Self.cellSize(pad: newPad)), animated: false)
        }
        guard padChanged || !Self.same(sections, new) else { return }
        stopJump()
        sections = new
        tops = []
        collection.reloadData()
        if !sections.contains(where: { $0.id == reported }) { reported = sections.first?.id }
    }

    private static func same(_ a: [EmojiPanelSection], _ b: [EmojiPanelSection]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.id == $1.id && $0.emoji == $1.emoji }
    }

    // MARK: 点表情

    /// 面板正在动（惯性滚动、点分类滚过去）时按下只是让它停住，不算点表情。手指拖动时系统会取消格子的触摸，不用这里管。
    fileprivate var acceptsTap: Bool { jumpLink == nil && CACurrentMediaTime() - lastMoved > 0.1 }

    fileprivate func picked(_ item: String) { onPick?(item) }

    // MARK: 数据

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuse, for: indexPath)
        if let cell = cell as? EmojiCell {
            cell.grid = self
            cell.show(sections[indexPath.section].emoji[indexPath.item], font: font)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: EmojiHeader.reuse, for: indexPath)
        (view as? EmojiHeader)?.label.text = sections[indexPath.section].title
        return view
    }

    // MARK: 跟着滑动选中底栏的分类

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 只看手指拖动和惯性；点分类滚过去、重排布局挪的不算。
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        lastMoved = CACurrentMediaTime()
        reportCurrent()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        stopJump()
    }

    /// 顶上露出的是哪一类：小标题已经滑到顶（离顶不到 4）的里面最靠下的那个；一个都没到顶就是第一类。同原来。
    private func reportCurrent() {
        guard jumpLink == nil, !sections.isEmpty else { return }
        let tops = sectionTops()
        let y = collection.contentOffset.y + collection.adjustedContentInset.top
        var index = 0
        for (i, top) in tops.enumerated() where top - y <= 4 { index = i }
        let id = sections[min(index, sections.count - 1)].id
        guard id != reported else { return }
        reported = id
        onCurrent?(id)
    }

    /// 各类小标题没钉住时的顶边 = 这一类第一个表情的顶边 − 行距 − 小标题高。
    private func sectionTops() -> [CGFloat] {
        if tops.count == sections.count, topsWidth == collection.bounds.width { return tops }
        tops = sections.indices.map { index in
            guard let first = collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: index)) else {
                return .greatestFiniteMagnitude
            }
            return first.frame.minY - Self.rowGap - Self.headerHeight
        }
        topsWidth = collection.bounds.width
        return tops
    }

    // MARK: 点分类滚过去

    /// 滚 0.2 秒到那一类的小标题贴顶（到底了就停在底）。隔得远的先瞬移到离目标大半屏处再滚最后一段：
    /// 一路上上千个表情不用每个都画一遍，滚起来不卡。
    func jump(to id: String) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        stopJump()
        // 正在惯性滚动的先停住。
        collection.setContentOffset(collection.contentOffset, animated: false)
        collection.layoutIfNeeded()
        let tops = sectionTops()
        guard index < tops.count, tops[index] < .greatestFiniteMagnitude else { return }
        let inset = collection.adjustedContentInset
        let lowest = -inset.top
        let highest = max(collection.contentSize.height + inset.bottom - collection.bounds.height, lowest)
        let target = min(max(tops[index] - inset.top, lowest), highest)
        var start = collection.contentOffset.y
        let reach = collection.bounds.height * 0.6
        if abs(target - start) > reach {
            start = target + (target > start ? -reach : reach)
            collection.contentOffset.y = start
        }
        reported = id
        guard abs(target - start) > 0.5 else {
            collection.contentOffset.y = target
            return
        }
        jumpAnimation = (start, target, CACurrentMediaTime())
        let link = CADisplayLink(target: self, selector: #selector(stepJump))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        jumpLink = link
    }

    @objc private func stepJump() {
        guard let animation = jumpAnimation else { return stopJump() }
        let t = min(1, (CACurrentMediaTime() - animation.began) / Self.jumpDuration)
        // 先快后慢（ease-out）。
        let eased = CGFloat(1 - pow(1 - t, 3))
        collection.contentOffset.y = animation.from + (animation.to - animation.from) * eased
        if t >= 1 { stopJump() }
    }

    private func stopJump() {
        jumpLink?.invalidate()
        jumpLink = nil
        jumpAnimation = nil
    }
}

/// 一格表情：UILabel 居中画表情，整格都能点。按下时换成一张压暗 12% 的同样的图（同 KeyPressStyle 的 brightness −0.12）。
private final class EmojiCell: UICollectionViewCell {
    static let reuse = "emoji"
    weak var grid: EmojiGridView?

    private let label = UILabel()
    private let pressedView = UIImageView()
    private var item = ""
    /// 这一下按下时面板是静止的，抬起时算不算点要看手指还在不在格子里。
    private var tracking = false
    private var pressed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.lineBreakMode = .byClipping
        label.isAccessibilityElement = false
        pressedView.isHidden = true
        contentView.addSubview(label)
        contentView.addSubview(pressedView)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ item: String, font: UIFont) {
        self.item = item
        if label.font != font { label.font = font }
        label.text = item
        accessibilityLabel = item
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        pressedView.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        tracking = false
        setPressed(false)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard grid?.acceptsTap == true else { return }
        tracking = true
        setPressed(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking, let touch = touches.first else { return }
        setPressed(bounds.contains(touch.location(in: self)))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking else { return }
        tracking = false
        let inside = touches.first.map { bounds.contains($0.location(in: self)) } ?? false
        setPressed(false)
        if inside { grid?.picked(item) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        tracking = false
        setPressed(false)
    }

    override func accessibilityActivate() -> Bool {
        grid?.picked(item)
        return true
    }

    private func setPressed(_ on: Bool) {
        guard on != pressed else { return }
        pressed = on
        if on, label.bounds.width > 0, label.bounds.height > 0 {
            let bounds = label.bounds
            let label = self.label
            pressedView.image = UIGraphicsImageRenderer(bounds: bounds).image { context in
                label.layer.render(in: context.cgContext)
                UIColor(white: 0, alpha: 0.12).setFill()
                context.fill(bounds, blendMode: .sourceAtop)
            }
        } else {
            pressedView.image = nil
        }
        pressedView.isHidden = !on
        label.isHidden = on
    }
}

/// 每类上面的小标题：12pt 中粗、次要色，左边 4，上下 3；底是透明的，钉在顶上时表情从字底下滑过（同原来）。
private final class EmojiHeader: UICollectionReusableView {
    static let reuse = "header"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = EmojiGridView.headerFont
        label.textColor = .secondaryLabel
        label.accessibilityTraits = .header
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: EmojiGridView.side, y: 3, width: max(bounds.width - EmojiGridView.side * 2, 0),
                             height: max(bounds.height - 6, 0))
    }
}
