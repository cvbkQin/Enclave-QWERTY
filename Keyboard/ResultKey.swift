import SwiftUI

/// 结果卡左边的替换 / 插入键（QA5、QA15–QA24、NW36）：宽 36，和卡片一样高，圆角 12。图标在上、字在下，卡片展开 4 行时一起放大。
/// 主功能（设置 › 键盘里选，默认替换）的图标和字固定在上下正中间，点一下就是它；另一个按设置的滑动方式换过去：
/// 滚轮——另一个在边上露半截，按住往那边滑像拨号盘一样跟着转，过 16pt 换过去、底色变、轻震，松手执行再弹回；
/// 弹出——主功能下面一个 ▾，往下划过 16pt 正下方浮出另一个按钮，松手时它被按下一下再执行。
/// 没滑够 16pt 松手是取消。生成中 45% 透明、点了没反应；在卡片里改结果时它是「✓ 完成修改」，不能滑。
/// 用过的那个样子不变，字的右下角加一个小绿圈勾；按住滑动时它的图标换成同样的勾，滑过去松手只轻震一下、不再执行。
/// 识意要联网、回答框换成选择卡时（searchPrompt）也 45% 变淡不能点。
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
    /// 卡片展开 4 行（键高 100）时图标、字、间距跟着放大。
    private var tall: Bool { model.cardTall }
    /// 生成中、要联网的选择卡、出错卡（含没写完）时 45% 变淡不能点。
    private var blocked: Bool { model.isRunning || model.searchPrompt != nil || model.errorMessage != nil || model.partialResult != nil }

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
                face(title: L("完成修改", "Done", "完了"), systemImage: "checkmark", color: .white, large: tall)
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
        // 生成中、还没结果时变淡不能点（MG2）。
        .opacity(blocked || !enabled ? 0.45 : 1)
        .contentShape(Rectangle())
        .gesture(drag(step: step))
        .allowsHitTesting(!blocked && enabled)
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

    /// 「图标 + 字」整块高 h：收起 13 + 12.5 + 1，展开 17 + 15 + 3。
    private var blockHeight: CGFloat { tall ? 35 : 26.5 }
    /// 两个功能中心隔一格：收起 h + 8，展开 h + 16；另一个露在边上半截（键 overflow 裁掉）。
    private var step: CGFloat { blockHeight + (tall ? 16 : 8) }
    /// 细线中心离主功能中心：收起 h/2 + 4，展开 h/2 + 7。
    private var dividerGap: CGFloat { blockHeight / 2 + (tall ? 7 : 4) }

    private func wheel(height: CGFloat, color: Color) -> some View {
        // 另一个在主功能的哪边：上滑时在下面（+），下滑时在上面（−）。滚动时整块往反方向挪。
        let side: CGFloat = wheelUp ? 1 : -1
        let shift = -side * displayRoll(step: step)
        return ZStack {
            faceOnWheel(primary, y: shift, step: step, color: color)
            Rectangle().fill(Color.white.opacity(0.5))
                .frame(width: 22, height: 1)
                .offset(y: side * dividerGap + shift)
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

    /// 主功能下面细线 + 小 ▾（10pt，展开 12pt），▾ 在细线下 8pt（展开 11pt）。
    private func popFace(height: CGFloat, color: Color) -> some View {
        ZStack {
            face(primary, color: color)
            Rectangle().fill(Color.white.opacity(0.5)).frame(width: 22, height: 1)
                .offset(y: dividerGap)
            Image(systemName: "chevron.down")
                .font(.system(size: tall ? 12 : 10, weight: .bold))
                .foregroundStyle(color)
                .offset(y: dividerGap + (tall ? 11 : 8))
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

    /// 键正下方 6pt 浮出的另一个：36×44（图标 13 + 字 10.5 竖排），它自己的渐变，2pt 白描边加阴影。
    private func popOption(height: CGFloat) -> some View {
        let small = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return face(other, color: foreground(other), large: false, swiping: true)
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
                // 另一个用过了也能滑过去（图标换成小绿圈勾），松手只轻震一下。
                let canSwitch = true
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
        guard model.hasResult else { return }
        guard !used(action) else {
            model.keyFeedback(for: .space)
            return
        }
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

    /// 用过的：字的右下角一个小绿圈勾；滑动中（手指按着、露出两个功能时）图标也换成同样大小的勾。
    private func face(_ action: ResultKeyAction, color: Color, large: Bool? = nil, swiping: Bool? = nil) -> some View {
        let done = used(action)
        let isSwiping = swiping ?? (pressed && moved)
        return face(title: action.title, systemImage: action.systemImage, color: color,
                    large: large ?? tall, tick: done, iconTick: done && isSwiping)
    }

    /// 图标在上、字在下：收起图标 13pt、字 10.5pt bold（行高 12.5）、间距 1；展开图标 17pt、字 13pt（行高 15）、间距 3。
    /// 英文、日文太长就缩小。tick：字的右下角小绿圈勾（收起 6pt、展开 7pt），圆心对准字框右下角，不出键边。
    private func face(title: String, systemImage: String, color: Color,
                      large: Bool = false, tick: Bool = false, iconTick: Bool = false) -> some View {
        let icon: CGFloat = large ? 17 : 13
        return VStack(spacing: large ? 3 : 1) {
            Group {
                if iconTick {
                    UsedTick().frame(width: icon, height: icon)
                } else {
                    Image(systemName: systemImage).font(.system(size: icon, weight: .bold))
                }
            }
            .frame(height: icon)
            Text(title)
                .font(.system(size: large ? 13 : 10.5, weight: .bold))
                .frame(height: large ? 15 : 12.5)
                .overlay(alignment: .bottomTrailing) {
                    if tick {
                        let size: CGFloat = large ? 7 : 6
                        // 收起：圆右边超出字框 2.5pt、底边低 1.5pt；展开：右边超出 2pt、底边低 2pt。
                        UsedTick()
                            .frame(width: size, height: size)
                            .shadow(color: .black.opacity(0.35), radius: 0.8, y: 0.5)
                            .offset(x: large ? 2 : 2.5, y: large ? 2 : 1.5)
                    }
                }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .foregroundStyle(color)
        .padding(.horizontal, 3)
    }

    /// 替换紫色、插入青蓝（用过的也一样，只加小绿圈勾）；还没有结果时灰底。
    private func fill(_ action: ResultKeyAction) -> AnyShapeStyle {
        // 完成修改：润色渐变。
        if editing { return AnyShapeStyle(LinearGradient(colors: [Brand.gradient[0], Brand.gradient[1]],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)) }
        if !model.hasResult && !model.isRunning { return AnyShapeStyle(Brand.disabledFill) }
        return AnyShapeStyle(gradient(action))
    }

    private func foreground(_ action: ResultKeyAction) -> Color {
        if editing { return .white }
        if !model.hasResult && !model.isRunning { return Brand.disabledText }
        return .white
    }

    private func gradient(_ action: ResultKeyAction) -> LinearGradient {
        LinearGradient(colors: action == .replace ? Brand.resultKeyReplaceColors : Brand.resultKeyInsertColors,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var accessibilityLabel: String {
        if editing { return L("完成修改", "Done editing", "編集を完了") }
        let p = primary.title, o = other.title
        let label: String
        if !usesWheel {
            label = L("\(p)，按住往下划\(o)", "\(p). Hold and slide down to \(o.lowercased())", "\(p)。長押しで下にスライドすると\(o)")
        } else {
            label = wheelUp
                ? L("\(p)，按住上滑\(o)", "\(p). Hold and slide up to \(o.lowercased())", "\(p)。長押しで上にスライドすると\(o)")
                : L("\(p)，按住下滑\(o)", "\(p). Hold and slide down to \(o.lowercased())", "\(p)。長押しで下にスライドすると\(o)")
        }
        return model.resultUses.isEmpty ? label : label + L("（已用过）", " (used)", "（使用済み）")
    }
}

/// 用过的小绿圈勾：圆和勾画成一个图标整体缩放，勾一定在圆正中（24 网格：圆 r12 填 #34C759，
/// 白勾 M6.8 12.4 l3.6 3.6 6.8-7.2，线粗 3.4，圆头）。
struct UsedTick: View {
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 24
            ZStack {
                Circle().fill(Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255))
                Path { path in
                    path.move(to: CGPoint(x: 6.8, y: 12.4))
                    path.addLine(to: CGPoint(x: 10.4, y: 16))
                    path.addLine(to: CGPoint(x: 17.2, y: 8.8))
                }
                .applying(CGAffineTransform(scaleX: scale, y: scale))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 24 * scale, height: 24 * scale)
        }
    }
}
