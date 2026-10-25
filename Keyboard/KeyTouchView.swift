import SwiftUI
import UIKit

/// 盖在按键上方的透明触摸层，照系统键盘的手感处理触摸：
/// 多指连打（新手指按下时先上屏上一个键）、手指滑到别的键上会跟着换、
/// Shift 和 123 按下就生效、从 123 滑到符号上松手直接打出来、
/// 删除键长按连删并加速、长按空格进入光标移动模式。
final class KeyTouchView: UIView {
    weak var model: KeyboardModel?
    var layout = KeyLayoutResult()

    private final class Tracking {
        var key: KeySpec
        var fired = false
        var timer: Timer?
        var repeats = 0
        var trackpadX: CGFloat?
        /// 从 123 键按下后滑到了符号上。
        var slidFromLayer = false
        /// 长按弹出了备选条，松手时打出选中的那个。
        var alternates = false
        /// 按下的位置，九宫格按住直接往外划用。
        var start: CGPoint = .zero

        init(key: KeySpec) { self.key = key }
    }

    private var tracking: [UITouch: Tracking] = [:]
    /// 九宫格按住划出多远算方向划。
    private static let flickDistance: CGFloat = 16

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 九宫格的拼音选择栏盖在这一层上面，那块区域的触摸交给它。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let column = layout.pinyinColumn, column.contains(point) { return false }
        if let column = layout.operatorColumn, column.contains(point) { return false }
        return super.point(inside: point, with: event)
    }

    private func key(at point: CGPoint) -> KeySpec? {
        if let hit = layout.keys.first(where: { $0.frame.contains(point) }) { return hit }
        // 落在缝隙或边缘外：取最近的键。
        return layout.keys.min { distance($0.frame, point) < distance($1.frame, point) }
    }

    private func distance(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return dx * dx + dy * dy
    }

    // MARK: - 触摸

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for touch in touches {
            guard let key = key(at: touch.location(in: self)) else { continue }
            // 另一根手指按下：之前还没松开的字符键先上屏，快速连打不丢字。
            for (_, other) in tracking where !other.fired && other.key.kind.typesCharacter {
                other.fired = true
                model.keyEventTime = touch.timestamp
                model.perform(other.key.kind)
                model.keyReleased(other.key.id)
            }
            let state = Tracking(key: key)
            state.start = touch.location(in: self)
            tracking[touch] = state
            model.keyPressed(key)

            switch key.kind {
            case .globe:
                model.controller?.handleInputModeList(from: self, with: event ?? UIEvent())
                state.fired = true
            case .shift, .layer:
                // 系统键盘按下就切换，方便接着滑到别的键上。
                model.perform(key.kind)
                state.fired = true
            case .delete:
                model.perform(.delete)
                state.fired = true
                startRepeating(state)
            case .space:
                state.timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak state] _ in
                    Task { @MainActor in
                        guard let self, let state, !state.fired, self.model?.isComposing == false else { return }
                        state.trackpadX = touch.location(in: self).x
                        state.fired = true
                        self.model?.setTrackpad(true)
                    }
                }
            case .toggleChinese:
                // 长按「中/英」弹出拼音布局菜单（P11）；短按照常切中英。
                state.timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self, weak state] _ in
                    Task { @MainActor in
                        guard let self, let state, !state.fired,
                              self.tracking.values.contains(where: { $0 === state }) else { return }
                        self.model?.showLayoutMenu(for: state.key, containerWidth: self.bounds.width)
                        state.alternates = true
                        state.fired = true
                    }
                }
            default:
                if key.kind.typesCharacter { scheduleAlternates(state) }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for touch in touches {
            guard let state = tracking[touch] else { continue }
            let point = touch.location(in: self)
            if state.alternates {
                model.moveAlternates(to: point)
                continue
            }
            // 九宫格和原生一样：按住直接往上下左右划，不用等长按，十字马上出来并选中那个方向。
            if !state.fired, state.key.kind.flicks(composing: model.isComposing),
               hypot(point.x - state.start.x, point.y - state.start.y) > Self.flickDistance,
               model.showAlternates(for: state.key, containerWidth: bounds.width, origin: state.start) {
                state.timer?.invalidate()
                state.alternates = true
                state.fired = true
                model.moveAlternates(to: point)
                continue
            }
            if state.key.kind == .globe {
                model.controller?.handleInputModeList(from: self, with: event ?? UIEvent())
                continue
            }
            if let lastX = state.trackpadX {
                // 光标移动：每 9pt 移一个字。
                let steps = Int((point.x - lastX) / 9)
                if steps != 0 {
                    model.moveCursor(by: steps)
                    state.trackpadX = lastX + CGFloat(steps) * 9
                }
                continue
            }
            let isLayerSlide: Bool = {
                if case .layer = state.key.kind { return true }
                return state.slidFromLayer
            }()
            guard (state.key.kind.typesCharacter && !state.fired) || isLayerSlide,
                  let next = key(at: point), next.id != state.key.id, next.kind.typesCharacter else { continue }
            // 手指滑到别的字符键上：气泡跟着换，松手时打出最后停留的那个。
            model.keyReleased(state.key.id)
            model.keyPressed(next, feedback: false)
            if isLayerSlide {
                state.slidFromLayer = true
                state.fired = false
            }
            state.key = next
            state.start = point
            state.timer?.invalidate()
            scheduleAlternates(state)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for touch in touches {
            guard let state = tracking.removeValue(forKey: touch) else { continue }
            state.timer?.invalidate()
            if state.key.kind == .globe {
                model.controller?.handleInputModeList(from: self, with: event ?? UIEvent())
            } else if state.alternates {
                model.commitAlternate()
            } else if state.trackpadX != nil {
                model.setTrackpad(false)
            } else if !state.fired {
                model.keyEventTime = touch.timestamp
                model.perform(state.key.kind)
                // 从 123 滑过来打的符号，打完回到字母。
                if state.slidFromLayer { model.switchLayer(.letters) }
            }
            model.keyReleased(state.key.id)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for touch in touches {
            guard let state = tracking.removeValue(forKey: touch) else { continue }
            state.timer?.invalidate()
            if state.trackpadX != nil { model.setTrackpad(false) }
            if state.alternates {
                model.alternates = nil
                model.cross = nil
                model.layoutMenu = nil
            }
            model.keyReleased(state.key.id)
        }
    }

    /// 字符键按住 0.4 秒弹出备选（九宫格的字母和数字、标点，全键盘的数字和带调字母）。
    private func scheduleAlternates(_ state: Tracking) {
        state.timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self, weak state] _ in
            Task { @MainActor in
                guard let self, let state, !state.fired,
                      self.tracking.values.contains(where: { $0 === state }),
                      self.model?.showAlternates(for: state.key, containerWidth: self.bounds.width,
                                                              origin: state.start) == true else { return }
                state.alternates = true
                state.fired = true
            }
        }
    }

    /// 删除键：按住 0.45 秒后开始连删，越删越快。
    private func startRepeating(_ state: Tracking) {
        state.timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak state] _ in
            Task { @MainActor in
                guard let self, let state else { return }
                self.repeatDelete(state)
            }
        }
    }

    private func repeatDelete(_ state: Tracking) {
        guard tracking.values.contains(where: { $0 === state }) else { return }
        model?.perform(.delete)
        state.repeats += 1
        let interval = state.repeats > 20 ? 0.04 : (state.repeats > 8 ? 0.07 : 0.1)
        state.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self, weak state] _ in
            Task { @MainActor in
                guard let self, let state else { return }
                self.repeatDelete(state)
            }
        }
    }
}

struct KeyTouchLayer: UIViewRepresentable {
    var model: KeyboardModel
    var layout: KeyLayoutResult

    func makeUIView(context: Context) -> KeyTouchView {
        let view = KeyTouchView(frame: .zero)
        view.model = model
        view.layout = layout
        return view
    }

    func updateUIView(_ view: KeyTouchView, context: Context) {
        view.model = model
        view.layout = layout
    }
}
