import SwiftUI

/// 结果卡左边的替换 / 插入键（QA5、QA15–QA20）：宽 58，和卡片一样高，圆角 12。
/// 主功能（设置 › 键盘里选，默认替换）的图标和字固定在上下正中间，点一下就是它；另一个按设置的滑动方式换过去：
/// 滚轮——另一个在边上露半截，按住往那边滑像拨号盘一样跟着转，过 16pt 换过去、底色变、轻震，松手执行再弹回；
/// 弹出——主功能下面一个 ▾，往下划过 16pt 正下方浮出另一个按钮，松手时它被按下一下再执行。
/// 没滑够 16pt 松手是取消。生成中 45% 透明、点了没反应；在卡片里改结果时它是「✓ 完成修改」，不能滑。
/// 用过的那个显示「✓ 已替换 / ✓ 已插入」淡紫底、不能再点（露半截的提示也用 #4A3BD6），另一个照样能滑出来；两个都用过就不再换。
struct ResultKey: View {
    @ObservedObject var model: KeyboardModel
    /// 滚轮往设置的方向滚了多远，0 是原位；滚满一格是 step。
    @State private var roll: CGFloat = 0
    /// 滚轮滑过 16pt，换到另一个了。
    @State private var switched = false
    /// 弹出方式：另一个按钮浮出来了；松手时它缩一下像被按下。
    @State private var popped = false
    @State private var popPressed = false
    @State private var pressed = false
    /// 手指离开按下点超过 8pt 就不算「点」：没滑够 16pt 松手是取消，不执行主功能。
    @State private var moved = false

    /// 和 ✨、九宫格逗号键按住划出方向的距离一样。
    private static let flickDistance: CGFloat = 16
    private static let tapSlop: CGFloat = 8
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private var primary: ResultKeyAction { model.settings.resultKeyPrimary }
    private var other: ResultKeyAction { primary.other }
    private var usesWheel: Bool { model.settings.resultKeySwipe == .wheel }
    /// 滚轮上滑：另一个露在下面，往上推上来；下滑反过来。
    private var wheelUp: Bool { model.settings.resultKeyWheelUp }
    private var editing: Bool { model.target == .card }
    private var enabled: Bool { editing || model.hasResult }

    var body: some View {
        GeometryReader { geo in
            key(height: geo.size.height)
        }
    }

    private func key(height: CGFloat) -> some View {
        let shown = rolledOver ? other : primary
        let lifted = rolledOver || popShown
        return ZStack {
            shape.fill(fill(shown))
            if editing {
                face(title: L("完成修改", "Done", "完了"), systemImage: "checkmark", color: .white)
            } else if usesWheel {
                wheel(height: height, color: foreground(shown))
            } else {
                popFace(height: height, color: foreground(shown))
            }
        }
        .overlay { if lifted { shape.strokeBorder(Color.white, lineWidth: 2) } }
        .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: 6, y: 2)
        .scaleEffect(pressed && !moved && !lifted ? 0.96 : 1)
        .overlay(alignment: .top) {
            if popShown {
                popOption(height: height)
                    .offset(y: height + 6)
                    .transition(.asymmetric(insertion: .offset(y: -14).combined(with: .scale(scale: 0.9)).combined(with: .opacity),
                                            removal: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .opacity(model.isRunning ? 0.45 : 1)
        .contentShape(Rectangle())
        .gesture(drag(step: Self.step(height)))
        .allowsHitTesting(!model.isRunning && enabled)
        .background {
            // 使用指引的小手：替换、插入两步都指这颗键。
            ZStack {
                Color.clear.coachTarget(.replace, active: model.coachDisplay?.target == .replace)
                Color.clear.coachTarget(.insert, active: model.coachDisplay?.target == .insert)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { editing ? model.finishCardEdit() : perform(primary) }
        .accessibilityAction(named: other.title) { perform(other) }
    }

    // MARK: 滚轮

    /// 两个功能上下挨着，中心隔一格；另一个露在边上半截。
    private static func step(_ height: CGFloat) -> CGFloat { max(12, height / 2 - 9) }

    private func wheel(height: CGFloat, color: Color) -> some View {
        let step = Self.step(height)
        // 另一个在主功能的哪边：上滑时在下面（+），下滑时在上面（−）。滚动时整块往反方向挪。
        let side: CGFloat = wheelUp ? 1 : -1
        let shift = -side * displayRoll(step: step)
        return ZStack {
            faceOnWheel(primary, y: shift, step: step, color: color)
            Rectangle().fill(Color.white.opacity(0.5))
                .frame(width: 34, height: 1)
                .offset(y: side * step / 2 + shift)
            faceOnWheel(other, y: side * step + shift, step: step, color: color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 往上下两边渐隐，露在边上的只看得出半截。
        .mask(LinearGradient(stops: [.init(color: .black.opacity(0.1), location: 0),
                                     .init(color: .black, location: 0.32),
                                     .init(color: .black, location: 0.68),
                                     .init(color: .black.opacity(0.1), location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .clipShape(shape)
    }

    /// 离中间越远越淡、越虚：在边上时 55% 白、模糊 0.9pt。
    private func faceOnWheel(_ action: ResultKeyAction, y: CGFloat, step: CGFloat, color: Color) -> some View {
        let distance = min(abs(y) / step, 1)
        return face(action, color: color)
            .opacity(Double(1 - 0.45 * distance))
            .blur(radius: 0.9 * distance)
            .offset(y: y)
    }

    private func displayRoll(step: CGFloat) -> CGFloat {
        #if DEBUG
        if model.debugResultKeyPose == "rolled" { return step }
        #endif
        return roll
    }

    private var rolledOver: Bool {
        guard usesWheel, !editing else { return false }
        #if DEBUG
        if model.debugResultKeyPose == "rolled" { return true }
        #endif
        return switched
    }

    // MARK: 弹出

    private func popFace(height: CGFloat, color: Color) -> some View {
        ZStack {
            face(primary, color: color)
            VStack(spacing: 3) {
                Rectangle().fill(Color.white.opacity(0.5)).frame(width: 34, height: 1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
            .offset(y: 17)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var popShown: Bool {
        guard !usesWheel, !editing else { return false }
        #if DEBUG
        if model.debugResultKeyPose == "popped" { return true }
        #endif
        return popped
    }

    /// 键正下方 6pt 浮出的另一个：58×44，它自己的渐变，2pt 白描边加阴影。
    private func popOption(height: CGFloat) -> some View {
        let small = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return face(other, color: foreground(other))
            .frame(width: KeyboardMetrics.resultKeyWidth, height: 44)
            .background(small.fill(fill(other)))
            .overlay(small.strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .scaleEffect(popPressed ? 0.9 : 1)
    }

    // MARK: 手势

    private func drag(step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressed { pressed = true }
                let dx = value.translation.width, dy = value.translation.height
                if !moved, hypot(dx, dy) > Self.tapSlop { moved = true }
                guard !editing else { return }
                // 另一个已经用过了就不往那边换。
                let canSwitch = !used(other)
                if usesWheel {
                    let pull = wheelUp ? -dy : dy
                    if pull > Self.flickDistance, canSwitch {
                        // 滚满一格；再往前拖有阻尼。
                        let target = step + min((pull - Self.flickDistance) * 0.25, 8)
                        if !switched {
                            switched = true
                            model.keyFeedback(for: .space)
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) { roll = target }
                        } else {
                            roll = target
                        }
                    } else {
                        // 没过 16pt 跟着手指；往反方向几乎拖不动。
                        let target = pull >= 0 ? min(pull, Self.flickDistance) : pull * 0.12
                        if switched {
                            switched = false
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { roll = target }
                        } else {
                            roll = target
                        }
                    }
                } else {
                    let show = dy > Self.flickDistance && canSwitch
                    if show != popped {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) { popped = show }
                        if show { model.keyFeedback(for: .space) }
                    }
                }
            }
            .onEnded { _ in
                let tapped = !moved
                pressed = false
                moved = false
                if editing {
                    if tapped { model.finishCardEdit() }
                    return
                }
                if usesWheel {
                    let chosen = switched ? other : (tapped ? primary : nil)
                    if let chosen { perform(chosen) }
                    // 松手后带一点过冲转回原位。
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                        roll = 0
                        switched = false
                    }
                } else if popped {
                    // 浮出来的那个缩一下像被按下，再执行、淡出。
                    withAnimation(.easeOut(duration: 0.05)) { popPressed = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.05)) { popPressed = false }
                        perform(other)
                        withAnimation(.easeOut(duration: 0.2)) { popped = false }
                    }
                } else if tapped {
                    perform(primary)
                }
            }
    }

    private func perform(_ action: ResultKeyAction) {
        guard model.hasResult, !used(action) else { return }
        switch action {
        case .replace: model.replace()
        case .insert: model.insert()
        }
    }

    // MARK: 样子

    private func use(_ action: ResultKeyAction) -> KeyboardModel.ResultUse {
        action == .replace ? .replaced : .inserted
    }

    private func used(_ action: ResultKeyAction) -> Bool { model.resultUses.contains(use(action)) }

    private func face(_ action: ResultKeyAction, color: Color) -> some View {
        let done = used(action)
        let title = done ? (action == .replace ? L("已替换", "Replaced", "置き換え済み") : L("已插入", "Inserted", "挿入済み")) : action.title
        return face(title: title, systemImage: done ? "checkmark" : action.systemImage, color: color)
    }

    /// 图标 13pt、字 14pt bold，英文、日文太长就缩小。
    private func face(title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
            Text(title).font(.system(size: 14, weight: .bold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .foregroundStyle(color)
        .padding(.horizontal, 4)
    }

    /// 替换紫色、插入青蓝；用过的那个淡紫底 #ECEAFD、字 #4A3BD6；还没有结果时灰底。
    private func fill(_ action: ResultKeyAction) -> AnyShapeStyle {
        // 完成修改：润色渐变。
        if editing { return AnyShapeStyle(LinearGradient(colors: [Brand.gradient[0], Brand.gradient[1]],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)) }
        if !model.hasResult && !model.isRunning { return AnyShapeStyle(Brand.disabledFill) }
        if used(action) { return AnyShapeStyle(Brand.returnSoftFill) }
        return AnyShapeStyle(gradient(action))
    }

    private func foreground(_ action: ResultKeyAction) -> Color {
        if editing { return .white }
        if !model.hasResult && !model.isRunning { return Brand.disabledText }
        return used(action) ? Brand.deepPurple : .white
    }

    private func gradient(_ action: ResultKeyAction) -> LinearGradient {
        LinearGradient(colors: action == .replace ? Brand.resultKeyReplaceColors : Brand.resultKeyInsertColors,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var accessibilityLabel: String {
        if editing { return L("完成修改", "Done editing", "編集を完了") }
        let p = primary.title, o = other.title
        if !usesWheel {
            return L("\(p)，按住往下划\(o)", "\(p). Hold and slide down to \(o.lowercased())", "\(p)。長押しで下にスライドすると\(o)")
        }
        return wheelUp
            ? L("\(p)，按住上滑\(o)", "\(p). Hold and slide up to \(o.lowercased())", "\(p)。長押しで上にスライドすると\(o)")
            : L("\(p)，按住下滑\(o)", "\(p). Hold and slide down to \(o.lowercased())", "\(p)。長押しで下にスライドすると\(o)")
    }
}
