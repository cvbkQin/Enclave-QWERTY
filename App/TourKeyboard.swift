import SwiftUI

// 功能演示里画的键盘（T95，design/onboard-v2 第五节「模拟键盘」）：按选的布局画九宫格或全键盘，样子照真键盘。
// AI 栏（润色、问答、复制后弹出的帮回键、固定的风格、撤销重做）、回答卡和识意框、风格下拉、分词面板、
// 打字一章的长按一排 / 十字 / 触控板 / 常用与剪贴板，都只是画出来，不接真键盘的逻辑。只有触点指着的那一处能点。

// MARK: - 颜色

enum TourColor {
    static let keyboard = Color(light: 0xD9DAE0, dark: 0x2B2B2D)
    static let key = Color(light: 0xFFFFFF, dark: 0x5A5A5E)
    static let returnFill = Color(light: 0xE8E5FB, dark: 0x3A3550)
    static let purple = Color(light: 0x5B4BE8, dark: 0x8B80F9)
    static let purpleText = Color(light: 0x5B4BE8, dark: 0xB4A9FF)
    static let ring = Color(hex: 0x8B7CF6)
    static let answerRing = Color(hex: 0x38BDF8)
    static let bubble = Color(light: 0xF2F1F7, dark: 0x2C2C2E)
    static let hostCaret = Color(hex: 0x34C759)
    static let cardFill = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// 识意框：没激活时浅灰底、浅紫顶线；编辑中白底、紫顶线。
    static let askIdle = Color(light: 0xF4F4F7, dark: 0x242426)
    static let askLine = Color(light: 0xC9C0FF, dark: 0x5A4FA0)
    static let pillOn = Color(light: 0xEDEBFD, dark: 0x2E2766)
    static let answerBlue = Color(light: 0x2F7BF6, dark: 0x5EA0FF)
    static let webBlue = Color(light: 0x0369A1, dark: 0x7DD3FC)
}

// MARK: - 能点的地方

struct TourFramesKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 告诉触点这一处在哪。
    func tourTarget(_ target: TourTarget) -> some View {
        transformAnchorPreference(key: TourFramesKey.self, value: .bounds) { $0[target] = $1 }
    }

    /// 能点的一颗：按下缩 96%、变暗，抬起才算；触点示范按下时轻轻按下。
    func tourPress(_ id: TourTarget, model: TourModel, anchor: UnitPoint = .center) -> some View {
        modifier(TourPress(id: id, model: model, anchor: anchor))
    }
}

private struct TourPress: ViewModifier {
    let id: TourTarget
    @ObservedObject var model: TourModel
    /// 按下缩放的中心。整行能点、字靠左的（「AI 优化」）用 .leading，缩的时候字不往中间挪。
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        let pressed = model.pressed == id
        let demo = model.demoDown && model.target == id && model.pressed == nil
        content
            .scaleEffect(pressed ? 0.96 : demo ? 0.97 : 1, anchor: anchor)
            .brightness(pressed ? -0.08 : demo ? -0.04 : 0)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in model.pressBegan(id) }
                .onEnded { value in
                    let moved = abs(value.translation.width) + abs(value.translation.height)
                    model.pressEnded(id, inside: moved < 30)
                })
            .tourTarget(id)
    }
}

/// 键盘顶部的圆角，底边直角。
struct TopRounded: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 模拟键盘

struct TourKeyboard: View {
    @ObservedObject var model: TourModel
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let side: CGFloat = 6
    private let gap: CGFloat = 6
    /// 矮屏（SE 等）：按键行高 42 → 36，给对话卡让地方。
    private var compact: Bool { UIScreen.main.bounds.height < 700 }
    private var keyHeight: CGFloat { compact ? 36 : 42 }
    private var keysHeight: CGFloat { keyHeight * 4 + gap * 3 }
    private var bottomInset: CGFloat { compact ? 4 : 24 }

    /// 润色键在键盘里的位置，风格下拉和它左对齐。
    @State private var polishFrame: CGRect = .zero

    var body: some View {
        VStack(spacing: 8) {
            if model.expanded {
                TourAnswerCard(model: model, styleName: styleName)
                    .padding(.horizontal, side + 2)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            aiBar.padding(.horizontal, side + 2).zIndex(1)
            Group {
                if model.panel {
                    TourWordPanel(model: model, height: keysHeight)
                        .padding(.horizontal, side + 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    keysArea
                        .padding(.horizontal, side)
                        // 风格下拉从润色键下面往下弹，盖在按键上（同真键盘）。
                        .overlay(alignment: .topLeading) { dropdown }
                }
            }
            .zIndex(2)
        }
        .padding(.top, 8)
        // 不画地球、话筒那一行（演示里用不到），底下只留 24 给 Home 条，省出来的高给对话卡（OC1 ⑤）。
        // 矮屏（SE 等有 Home 键的）没有 Home 条，留 4。
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .coordinateSpace(name: "tourKeyboard")
        .background(
            TourColor.keyboard
                .clipShape(TopRounded(radius: compact ? 22 : 26))
                .contentShape(Rectangle())
                .onTapGesture { model.wrong() })
    }

    // MARK: 风格

    private var styleNames: [String] {
        var names = [L("润色", "Polish", "整える"), L("正式", "Formal", "丁寧"), L("口语", "Casual", "カジュアル"),
                     L("简短", "Concise", "簡潔に"), L("结构", "Bullets", "箇条書き")]
        if let custom = model.customPrompt { names.append(custom) }
        return names
    }

    private var styleName: String { styleNames[min(model.selectedPrompt, styleNames.count - 1)] }

    private var menuRow: CGFloat { compact ? 28 : 32 }

    @ViewBuilder
    private var dropdown: some View {
        if model.promptsOpen {
            let x = min(max(4, polishFrame.minX - side), UIScreen.main.bounds.width - 230)
            // 从润色键下面往下弹；按键下面放不下（矮屏、多了一条「英文」）就整个往上挪到放得下，盖住 AI 栏也行，
            // 不能掉出屏幕：SE 上「＋ 添加润色风格」原来在屏幕外，润色风格第 2 步点不到。
            let room = keysHeight + bottomInset - 4
            styleMenu
                .offset(x: x, y: min(4, room - styleMenuHeight))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    /// 下拉的高：上下各 5、小标题一行、每个风格一行、「＋ 添加润色风格」一行。
    private var styleMenuHeight: CGFloat {
        10 + (compact ? 20 : 24) + menuRow * CGFloat(styleNames.count + 1)
    }

    /// 宽 216、圆角 12：小标题，每条右边一颗图钉（演示里只有新加的那条的能点），当前那条打勾；最底下「＋ 添加润色风格」。
    private var styleMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("润色风格 · 点图钉固定到 AI 栏", "Polish style · Pin to the AI bar", "整えるスタイル · ピンで AI バーに固定"))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 10).frame(height: compact ? 20 : 24)
            ForEach(Array(styleNames.enumerated()), id: \.offset) { index, name in
                styleRow(index, name)
            }
            Label(L("添加润色风格", "Add Polish Style", "整えるスタイルを追加"), systemImage: "plus")
                .font(.system(size: 14.5)).foregroundStyle(TourColor.purpleText).lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: menuRow, alignment: .leading)
                .tourPress(.addStyle, model: model)
        }
        .padding(5)
        .frame(width: 216)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.cardFill)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6))
    }

    private func styleRow(_ index: Int, _ name: String) -> some View {
        let on = index == model.selectedPrompt
        let pinned = index == 5 && model.pinnedCustom
        return HStack(spacing: 6) {
            Text(name).font(.system(size: 14.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? TourColor.purpleText : .primary).lineLimit(1)
            if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(TourColor.purpleText) }
            Spacer(minLength: 4)
            Group {
                if index == 5 {
                    pinIcon(pinned).tourPress(.pin(5), model: model)
                } else {
                    pinIcon(false).onTapGesture { model.wrong() }
                }
            }
        }
        .padding(.leading, 10)
        .frame(height: menuRow)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? TourColor.pillOn : .clear))
        .transition(.opacity)
        .tourPress(.pill(index), model: model)
    }

    private func pinIcon(_ pinned: Bool) -> some View {
        Image(systemName: pinned ? "pin.fill" : "pin")
            .font(.system(size: 12, weight: .semibold))
            .rotationEffect(.degrees(45))
            .foregroundStyle(pinned ? TourColor.purpleText : Color.secondary.opacity(0.7))
            .frame(width: 30, height: menuRow)
            .contentShape(Rectangle())
    }

    // MARK: AI 栏

    /// ▭ ｜ 润色键、问答键、（复制后）帮回键、竖线、固定的风格 ｜ 撤销重做。窄屏放不下时中间那段跟着要点的键滚过去。
    private var aiBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "rectangle.tophalf.inset.filled")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(model.expanded ? TourColor.purpleText : .primary)
                .frame(width: 36, height: 34)
                .background(Capsule().fill(model.expanded ? TourColor.pillOn : TourColor.key))
                .overlay(Capsule().strokeBorder(TourColor.ring, lineWidth: model.expanded ? 1.5 : 0))
                .tourPress(.drawer, model: model)
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        mainKey(answer: false).id(TourTarget.sparkle)
                        mainKey(answer: true).id(TourTarget.askKey)
                        if model.helpShown {
                            TourHelpKey(model: model)
                                .id(TourTarget.helpKey)
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion: .scale(scale: 0.6).combined(with: .opacity)
                                        .animation(.spring(response: 0.42, dampingFraction: 0.72)),
                                    removal: .scale(scale: 0.8).combined(with: .opacity)
                                        .animation(.easeOut(duration: 0.2))))
                        }
                        if model.pinnedCustom && !model.promptsOpen {
                            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1, height: 20)
                            pinnedKey.id(TourTarget.pinned)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 44)
                }
                .scrollDisabled(true)
                .onChange(of: model.target) { target in
                    guard let target, [TourTarget.sparkle, .askKey, .helpKey, .pinned, .chevron].contains(target) else { return }
                    withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo(target == .chevron ? TourTarget.sparkle : target) }
                }
                .onChange(of: model.step) { _ in reader.scrollTo(TourTarget.sparkle, anchor: .leading) }
            }
            .frame(height: 44)
            undoRedo
        }
        .animation(.easeOut(duration: 0.2), value: model.pinnedCustom)
        .onPreferenceChange(TourPolishFrameKey.self) { frame in
            if frame != polishFrame { polishFrame = frame }
        }
    }

    private var undoRedo: some View {
        HStack(spacing: 0) {
            Image(systemName: "arrow.uturn.backward")
                .rotationEffect(.degrees(Double(model.undoTurns) * -180))
                .foregroundStyle(model.undoOn ? Color.primary : Color.secondary.opacity(0.6))
                .padding(.leading, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .tourPress(.undo, model: model)
            Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1, height: 16)
            Image(systemName: "arrow.uturn.forward")
                .foregroundStyle(model.redoOn ? Color.primary : Color.secondary.opacity(0.6))
                .padding(.trailing, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .tourPress(.redo, model: model)
        }
        .font(.system(size: 16, weight: .medium))
        .frame(width: 64, height: 34)
        .background(Capsule().fill(TourColor.key))
        .accessibilityElement(children: .contain)
    }

    /// 润色键「✨ 润色 ⌄」、问答键「[问答图标] 问答 ⌄」：竖线左边点了执行，右边 ⌄ 弹风格下拉。
    private func mainKey(answer: Bool) -> some View {
        let title = answer ? L("问答", "Ask", "質問") : styleName
        let running = answer ? model.askRunning : model.sparkRunning
        let done = running ? nil : (answer ? model.askDone : model.sparkDone)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]).width)
        return KeySuccessClock(since: done, reduced: reduceMotion) { fx in
            let animating = running || fx?.logoAnimating == true
            HStack(spacing: 0) {
                HStack(spacing: 3) {
                    if answer {
                        AskIcon(size: 17, running: animating, glowing: !reduceMotion, bounce: fx?.logoScale ?? 1)
                    } else {
                        PolishStars(size: 17, running: animating, glowing: !reduceMotion, doneAt: nil, tint: AIVisuals.gold)
                            .frame(width: 17, height: 17)
                            .scaleEffect(fx?.logoScale ?? 1)
                    }
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1).fixedSize()
                        .successText(fx)
                }
                .padding(.leading, 9).padding(.trailing, 5)
                .frame(maxHeight: .infinity)
                .tourPress(answer ? .askKey : .sparkle, model: model)
                Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1, height: 14)
                Image(systemName: !answer && model.promptsOpen ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                    .frame(width: 24).frame(maxHeight: .infinity)
                    .modifier(TourChevron(answer: answer, model: model))
            }
            .foregroundStyle(.white)
            .frame(height: 34)
            .overlay {
                if let fx { KeySuccessOverlay(frame: fx, checkCenter: CGPoint(x: 29 + textWidth / 2, y: 17)) }
            }
            .background(NebulaFill(palette: answer ? .answer : .rewrite).clipShape(Capsule()).runningShadow(running, answer: answer))
        }
        .overlay {
            if !reduceMotion {
                KeySparkles(running: running, successAt: done, textX: 29, textWidth: textWidth, seed: answer ? 2 : 1)
            }
        }
        .fixedSize()
        .background(GeometryReader { geo in
            Color.clear.preference(key: TourPolishFrameKey.self, value: answer ? .zero : geo.frame(in: .named("tourKeyboard")))
        })
    }

    /// 固定在 AI 栏的风格「✦ 英文」：浅紫底主色字，没有 ⌄；点了按这个风格出字。
    private var pinnedKey: some View {
        let title = model.customPrompt ?? model.script.promptName
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14.5, weight: .semibold)]).width)
        return KeySuccessClock(since: model.pinRunning ? nil : model.pinDone, reduced: reduceMotion) { fx in
            HStack(spacing: 4) {
                PolishStars(size: 15, running: model.pinRunning || fx?.logoAnimating == true, glowing: !reduceMotion, doneAt: nil, tint: TourColor.purple)
                    .frame(width: 15, height: 15)
                    .scaleEffect(fx?.logoScale ?? 1)
                Text(title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1).fixedSize()
                    .successText(fx)
            }
            .foregroundStyle(TourColor.purpleText)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay {
                if let fx { KeySuccessOverlay(frame: fx, checkCenter: CGPoint(x: 31 + textWidth / 2, y: 17)) }
            }
            .background(Capsule().fill(TourColor.pillOn).runningShadow(model.pinRunning, answer: false))
        }
        .overlay {
            if !reduceMotion {
                KeySparkles(running: model.pinRunning, successAt: model.pinRunning ? nil : model.pinDone, textX: 31, textWidth: textWidth, seed: 3)
            }
        }
        .tourPress(.pinned, model: model)
    }

    // MARK: 按键

    private var punctLabel: String { model.script.chinesePunct ? "，。" : ",." }

    @ViewBuilder
    private var keysArea: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                if model.layout == .nineKey {
                    nineKeys(width: width)
                } else {
                    qwertyKeys(width: width)
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(height: keysHeight)
        .coordinateSpace(name: "tourKeys")
    }

    // 全键盘

    private func qwertyKeys(width: CGFloat) -> some View {
        let letter = (width - gap * 9) / 10
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
        let punctLeft = store.settings.quickPunctSide == .left
        let fixed = letter * 1.3 + letter * 1.1 * 3 + letter * 1.9 + gap * 5
        let space = max(width - fixed, letter * 3)
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                ForEach(rows[0], id: \.self) { letterKey($0, width: letter) }
            }
            HStack(spacing: gap) {
                ForEach(rows[1], id: \.self) { letterKey($0, width: letter) }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: gap) {
                plainKey(Image(systemName: "shift"), width: letter * 1.3)
                Spacer(minLength: 0)
                HStack(spacing: gap) {
                    ForEach(rows[2], id: \.self) { letterKey($0, width: letter) }
                }
                Spacer(minLength: 0)
                plainKey(Image(systemName: "delete.left"), width: letter * 1.3)
            }
            HStack(spacing: gap) {
                plainKey(Text("123"), width: letter * 1.3, font: 15)
                plainKey(Image(systemName: "face.smiling"), width: letter * 1.1)
                plainKey(Text(L("中/英", "中/EN", "中/英")), width: letter * 1.1, font: 14)
                if punctLeft { punctKey(width: letter * 1.1) }
                plainKey(Text(L("空格", "space", "空白")), width: space, font: 15)
                if !punctLeft { punctKey(width: letter * 1.1) }
                returnKey.frame(width: letter * 1.9, height: keyHeight)
            }
        }
    }

    private func letterKey(_ letter: String, width: CGFloat) -> some View {
        plainKey(Text(letter), width: width, font: 22)
    }

    /// 底行的「，。」键（位置跟设置走，默认空格右边）。演示里不讲打字，只画出来。
    private func punctKey(width: CGFloat) -> some View {
        plainKey(Text(punctLabel).tracking(-1), width: width)
    }

    private func plainKey<Label: View>(_ label: Label, width: CGFloat, font: CGFloat = 17) -> some View {
        label
            .font(.system(size: font))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.primary)
            .frame(width: width, height: keyHeight)
            .background(TourKeyCap())
            .contentShape(Rectangle())
            .onTapGesture { model.wrong() }
    }

    // 九宫格

    private func nineKeys(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                GridRow {
                    gridKey(Text("123"))
                    gridKey(Text(model.script.chinesePunct ? "，。?!" : ",.?!"))
                    gridKey(Text("ABC"))
                    gridKey(Text("DEF"))
                }
                GridRow {
                    gridKey(Text("#@¥"))
                    gridKey(Text("GHI"))
                    gridKey(Text("JKL"))
                    gridKey(Text("MNO"))
                }
                GridRow {
                    clipKey
                    gridKey(Text("PQRS"))
                    gridKey(Text("TUV"))
                    gridKey(Text("WXYZ"))
                }
                GridRow {
                    gridKey(Image(systemName: "face.smiling"))
                    gridKey(Text(L("中/英", "中/EN", "中/英")))
                    gridKey(Text(L("空 格", "space", "空白"))).gridCellColumns(2)
                }
            }
            VStack(spacing: gap) {
                gridKey(Image(systemName: "delete.left"))
                gridKey(Text(L("重输", "Clear", "クリア")))
                returnKey.frame(height: keyHeight * 2 + gap)
            }
            .frame(width: min(66, width * 0.19))
        }
    }

    /// 「常 用 / 剪贴板」两行（和真键盘一致）。演示里不讲，只画出来。
    private var clipKey: some View {
        VStack(spacing: 0) {
            Text(L("常 用", "Saved", "定 型")).font(.system(size: 14))
            Text(L("剪贴板", "Clipboard", "クリップ")).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: keyHeight)
        .background(TourKeyCap())
        .contentShape(Rectangle())
        .onTapGesture { model.wrong() }
    }

    private func gridKey<Label: View>(_ label: Label) -> some View {
        label
            .font(.system(size: 17))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background(TourKeyCap())
            .contentShape(Rectangle())
            .onTapGesture { model.wrong() }
    }

    /// 回车位：要发的时候换成紫色「发送」；识意框编辑时是「执行」；平时浅紫回车。
    @ViewBuilder
    private var returnKey: some View {
        if model.sendReady {
            Text(L("发送", "Send", "送信"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.purple))
                .tourPress(.send, model: model)
                .transition(.opacity)
        } else if model.askEditing {
            Text(L("执行", "Go", "実行")).font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NebulaFill(palette: .ask).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
                .contentShape(Rectangle())
                .onTapGesture { model.wrong() }
        } else {
            Image(systemName: "return")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TourColor.purpleText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.returnFill))
                .contentShape(Rectangle())
                .onTapGesture { model.wrong() }
        }
    }
}

private struct TourPolishFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// 润色键的 ⌄ 能点（换风格、加风格）；问答键的 ⌄ 演示里不点。
private struct TourChevron: ViewModifier {
    let answer: Bool
    @ObservedObject var model: TourModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if answer {
            content.contentShape(Rectangle()).onTapGesture { model.wrong() }
        } else {
            content.tourPress(.chevron, model: model)
        }
    }
}

/// 键帽：白底圆角 8，底下 1pt 深一点的边（同真键盘）。
private struct TourKeyCap: View {
    var fill: Color = TourColor.key
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill)
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
    }
}

// MARK: - 帮回键（照第 89 条：标准样式、绿色、不带 ⌄）

private struct TourHelpKey: View {
    @ObservedObject var model: TourModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popBounce: CGFloat = 1

    private static let title = L("帮回", "Reply", "返信")

    var body: some View {
        let running = model.helpRunning
        let done = running ? nil : model.helpDone
        let textWidth = ceil((Self.title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]).width)
        return KeySuccessClock(since: done, reduced: reduceMotion) { fx in
            HStack(spacing: 3) {
                HelpIcon(size: 17, running: running || fx?.logoAnimating == true, bounce: (fx?.logoScale ?? 1) * popBounce, white: true,
                         doneAt: reduceMotion ? nil : done)
                    .frame(width: 17, height: 17)
                Text(Self.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).fixedSize()
                    .successText(fx)
            }
            .foregroundStyle(.white)
            .padding(.leading, 9).padding(.trailing, 12)
            .frame(height: 34)
            .overlay {
                if let fx { KeySuccessOverlay(frame: fx, checkCenter: CGPoint(x: 29 + textWidth / 2, y: 17)) }
            }
            .background(NebulaFill(palette: .help).clipShape(Capsule())
                .shadow(color: running ? HelpStyle.keyShadow : .clear, radius: 4.4, y: 2.8))
        }
        .overlay {
            if !reduceMotion {
                KeySparkles(running: running, successAt: done, textX: 29, textWidth: textWidth, seed: 7)
            }
        }
        .fixedSize()
        .tourPress(.helpKey, model: model)
        .onAppear {
            // 弹出后 logo 轻轻一跳（1 → 1.12 → 1）。
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.14).delay(0.32)) { popBounce = 1.12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                withAnimation(.easeInOut(duration: 0.22)) { popBounce = 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("帮回刚复制的那句话", "Help Reply to what you copied", "コピーした内容に返信"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 回答卡 + 识意框（照真键盘：上半格结果，下半格 40 高的识意框）

private struct TourAnswerCard: View {
    @ObservedObject var model: TourModel
    let styleName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var version: TourModel.Version? {
        model.versions.indices.contains(model.versionIndex) ? model.versions[model.versionIndex] : nil
    }

    /// 卡头跟着哪一种：有结果看结果，生成中看哪颗键在跑；帮回等待条走的时候、帮回生成中（含带要求重写）是帮回。
    private var mode: TourModel.CardMode? {
        if model.helpRunning || (model.helpWaitStart != nil && version == nil) { return .help }
        if model.regenerating || (model.sparkRunning && version == nil) { return .rewrite }
        if (model.askRunning || model.searching) && version == nil { return .answer }
        return version?.mode
    }

    /// 卡边：问答蓝，其余紫（帮回卡也是紫边，到位时绿光一闪，OM2）。
    private var ring: Color {
        mode == .answer ? TourColor.answerRing : TourColor.ring
    }

    /// 帮回等待条走的时候（还没到位）。
    private var helpWaiting: Bool { model.helpWaitStart != nil && model.helpArrived == nil }

    /// 识意框空着时的灰字：帮回等的时候、帮回出了一版以后各有一句（help-reply/again 第二节、二之二）。
    private var askPlaceholder: String {
        if helpWaiting {
            return L("先说要求？点这里，不点就自动回", "Add a request first? Tap here, or wait", "指示を書くならタップ。待つと自動で返信。")
        }
        if version?.mode == .help && !model.helpRunning {
            return L("补充要求，再点「帮回」重写", "Add a request, then tap Reply again", "指示を書いて、もう一度「返信」")
        }
        return L("写下要求或问题", "Type a request or question", "要望や質問を入力")
    }

    var body: some View {
        HStack(spacing: 6) {
            replaceKey
            VStack(spacing: 0) {
                top
                    .frame(height: model.cardTall ? 120 : 82)
                    // 帮回等待条：上半格（识意框以上）的绿色笔刷，在字的下面。减弱动态效果时不画，卡头右边写「2 秒后自动回」。
                    .background {
                        if let start = model.helpWaitStart, !reduceMotion {
                            TourHelpBrush(start: start, arrived: model.helpArrived)
                        }
                    }
                    .modifier(TourHoldable(enabled: true, target: .card, model: model))
                Rectangle().fill(model.askEditing ? TourColor.purple : TourColor.askLine).frame(height: 1)
                askRow.frame(height: 40)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.cardFill))
            .overlay {
                if let arrived = model.helpArrived, !reduceMotion { TourCardSheen(start: arrived) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ring, lineWidth: 1.5))
            .overlay {
                if let arrived = model.helpArrived, !reduceMotion { TourCardGlow(start: arrived) }
            }
            .animation(.easeInOut(duration: 0.25), value: mode)
        }
        .frame(height: model.cardTall ? 161 : 123)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88), value: model.cardTall)
    }

    /// 替换键：点一下替换；按住往上推是插入（演示只写在说明里）。
    private var replaceKey: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .bold))
            Text(L("替换", "Replace", "置き換え")).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Rectangle().fill(Color.white.opacity(0.5)).frame(width: 22, height: 1)
            Text(L("插入", "Insert", "挿入")).font(.system(size: 10, weight: .semibold)).opacity(0.55).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(width: 44)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.purple))
        .opacity(version == nil || model.generating || model.cardStream != nil || model.regenerating ? 0.45 : 1)
        .tourPress(.replace, model: model)
    }

    private var top: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let mode { header(mode).transition(.opacity) }
                bodyText
                    .font(.system(size: 14.5))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if model.versions.count > 1 { pager.transition(.move(edge: .trailing).combined(with: .opacity)) }
        }
        .padding(8)
    }

    @ViewBuilder
    private var bodyText: some View {
        if version == nil && (model.helpWaitStart != nil || model.helpRunning) {
            // 帮回还没出字：正文是要回的那句原话，灰字、左边 2pt 绿竖线，最多两行；开始帮回后虚掉。
            // 竖线放在 overlay 里，跟字一样高。
            Text(model.script.helpQuestion).foregroundStyle(.secondary).lineLimit(2)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous).fill(HelpStyle.green).frame(width: 2)
                }
            .opacity(model.helpRunning ? 0.35 : 1)
            .animation(.easeOut(duration: 0.2), value: model.helpRunning)
            .transition(.opacity)
        } else if model.generating {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text(L("生成中…", "Generating…", "生成中…")).foregroundStyle(.secondary)
            }
        } else if model.searching {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(TourColor.webBlue)
                    .rotationEffect(.degrees(reduceMotion || !model.searching ? 0 : 360))
                    .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: model.searching)
                Text(L("正在联网搜索…", "Searching the web…", "ウェブを検索しています…")).foregroundStyle(TourColor.webBlue)
            }
        } else if let version {
            let last = model.versionIndex == model.versions.count - 1
            Group {
                if let stream = model.cardStream, last {
                    TourStreamText(text: version.text, start: stream.start, perChar: stream.perChar)
                } else {
                    Text(version.text).foregroundColor(.primary)
                }
            }
            .lineLimit(model.cardTall ? 4 : 2)
            .opacity(model.regenerating ? 0.35 : 1)
            .id(model.versionIndex)
            .transition(.opacity)
        } else {
            Text(L("结果会出现在这里", "The result shows here", "結果はここに表示されます")).foregroundStyle(.tertiary)
        }
    }

    /// 卡头：改写「✦ AI 改写 · 润色」，帮回「回 AI 帮回 · 正式」（出了结果后面跟对方原话），问答「AI 回答 · 直击要害」+ 联网标签。
    /// 重新生成时换成「AI 正在改写…」，帮回生成中「AI 正在帮回…」，轻轻呼吸。
    private func header(_ mode: TourModel.CardMode) -> some View {
        HStack(spacing: 4) {
            switch mode {
            case .answer:
                AskIcon(size: 15)
                Text(L("AI 回答", "AI answer", "AI の回答") + " · " + L("直击要害", "To the point", "要点だけ"))
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                    .foregroundStyle(TourColor.answerBlue)
                webTag.padding(.leading, 2)
            case .help:
                if model.helpRunning {
                    PolishStars(size: 15, running: false, glowing: false, doneAt: nil, tint: TourColor.purple).frame(width: 15, height: 15)
                    TourBreathing(reduceMotion: reduceMotion) {
                        Text(L("AI 正在帮回…", "AI is replying…", "AI が返信中…"))
                            .font(.system(size: 13, weight: .bold)).lineLimit(1)
                            .foregroundStyle(TourColor.purpleText)
                    }
                } else {
                    Text(L("回", "R", "返"))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(HelpStyle.badgeText)
                        .frame(width: 16, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(HelpStyle.badgeFill))
                    // 帮回用自己的语气「正式」，不跟润色键选的风格走（说明.md 第三节帮回 2、3）。
                    Text(L("AI 帮回 · 正式", "AI reply · Formal", "AI 返信 · 丁寧"))
                        .font(.system(size: 13, weight: .bold)).lineLimit(1)
                        .foregroundStyle(TourColor.purpleText)
                        .fixedSize()
                    if version != nil {
                        // 出了结果：卡头后面跟对方原话（一行，放不下截断）。
                        Text(quoted(model.script.helpQuestion))
                            .font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    } else if helpWaiting && reduceMotion {
                        Spacer(minLength: 4)
                        Text(L("2 秒后自动回", "Replies in 2 s", "2 秒後に自動で返信"))
                            .font(.system(size: 12)).lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            case .rewrite:
                PolishStars(size: 15, running: false, glowing: false, doneAt: nil, tint: TourColor.purple).frame(width: 15, height: 15)
                if model.regenerating {
                    TourBreathing(reduceMotion: reduceMotion) {
                        Text(L("AI 正在改写…", "AI is rewriting…", "AI が書き換え中…"))
                            .font(.system(size: 13, weight: .bold)).lineLimit(1)
                            .foregroundStyle(TourColor.purpleText)
                    }
                } else {
                    Text(L("AI 改写", "AI rewrite", "AI 書き換え") + " · " + styleName)
                        .font(.system(size: 13, weight: .bold)).lineLimit(1)
                        .foregroundStyle(TourColor.purpleText)
                }
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.2), value: model.searched)
    }

    private func quoted(_ text: String) -> String {
        L("「\(text)」", "“\(text)”", "「\(text)」")
    }

    /// 问答标题后面的联网标签：联网前「未联网」浅灰，联网后「已联网」浅蓝。
    private var webTag: some View {
        let on = model.searched
        return HStack(spacing: 3) {
            Image(systemName: "globe").font(.system(size: 11))
            Text(on ? L("已联网", "Web", "ウェブ検索済み") : L("未联网", "No web", "ウェブなし")).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(on ? TourColor.answerBlue : Color(light: 0x8A8A8E, dark: 0x98989D))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(on ? Color(light: 0xE3EEFE, dark: 0x1D2A44) : Color(light: 0xEEEEF1, dark: 0x3A3A3E)))
        .fixedSize()
    }

    /// 右边翻版本：▲ 2/2 ▼。
    private var pager: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.up")
                .frame(width: 26, height: 22)
                .foregroundStyle(model.versionIndex > 0 ? Color.primary : Color.secondary.opacity(0.4))
                .contentShape(Rectangle())
                .onTapGesture { model.flipVersion(-1) }
            ZStack {
                Text("\(model.versionIndex + 1)/\(model.versions.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .id(model.versionIndex)
                    .transition(reduceMotion ? .opacity : .offset(x: 4).combined(with: .opacity))
            }
            Image(systemName: "chevron.down")
                .frame(width: 26, height: 22)
                .foregroundStyle(model.versionIndex < model.versions.count - 1 ? Color.primary : Color.secondary.opacity(0.4))
                .contentShape(Rectangle())
                .onTapGesture { model.flipVersion(1) }
        }
        .font(.system(size: 11, weight: .bold))
        .frame(maxHeight: .infinity)
    }

    /// 识意框：没激活时浅灰底、淡紫占位字、右边「点这里输入」；编辑中白底、光标 1 秒一闪（打字时常亮）。
    private var askRow: some View {
        HStack(spacing: 8) {
            Group {
                if model.ask.isEmpty && !model.askEditing {
                    Text(askPlaceholder)
                        .foregroundStyle(TourColor.askLine)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.75)
                } else {
                    HStack(spacing: 0) {
                        Text(model.ask)
                            .foregroundStyle(model.askDim ? Color.secondary : Color.primary)
                        if model.askEditing { TourCaret(color: TourColor.purpleText, typing: model.ask) }
                    }
                }
            }
            .font(.system(size: 15))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.canSearch, !model.searched {
                Label(L("使用联网查询", "Search the web", "ウェブで調べる"), systemImage: "globe")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(TourColor.webBlue)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(Color(light: 0xE0F2FE, dark: 0x0C3448)))
                    .fixedSize()
                    .tourPress(.search, model: model)
                    .transition(.opacity)
            } else if !model.askEditing && model.ask.isEmpty {
                Text(L("点这里输入", "Tap to type", "タップして入力"))
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(model.askEditing ? TourColor.cardFill : TourColor.askIdle)
        .animation(.easeOut(duration: 0.2), value: model.askEditing)
        .tourPress(.askField, model: model)
    }
}

// MARK: - 帮回等待条（帮回第 2 步，OM2；真键盘的样子见 design/help-reply/again 二之二、HW1–HW3）

/// 三次贝塞尔缓动：x 是时间、y 是进度，牛顿法反解（iOS 16 没有 UnitCurve）。
struct TourBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double

    func callAsFunction(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        var t = x
        for _ in 0..<8 {
            let error = Self.sample(t, x1, x2) - x
            let slope = Self.slope(t, x1, x2)
            if abs(error) < 1e-5 || abs(slope) < 1e-6 { break }
            t = min(max(t - error / slope, 0), 1)
        }
        return Self.sample(t, y1, y2)
    }

    private static func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private static func slope(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}

/// 固定的伪随机数（0…1）：同一个 i、salt 每帧都一样，笔触和光点不会乱跳。
private func tourNoise(_ i: Int, _ salt: Double) -> Double {
    let a = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
    return a - a.rounded(.down)
}

/// 上半格的绿色像干笔刷一样从左往右扫开（14:11 参考影之刃零加点）：一行行横向笔触长短不齐，前沿没有清楚的边，
/// 前面跑着一层更淡更糊的深色墨晕。2 秒碰到右边（cubic-bezier(.3,.45,.6,.92)，接近右边才放慢），碰到就触发。
/// 到位后：尽头一亮（0.46 秒），碎成 28 个绿色光点往右上散开（0.52–0.94 秒，起点错开 0.2 秒）；绿色 0.26 秒后 0.56 秒淡掉。
private struct TourHelpBrush: View {
    let start: Date
    let arrived: Date?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let start = self.start, arrived = self.arrived, dark = scheme == .dark
        return TimelineView(.animation) { timeline in
            let now = timeline.date
            Canvas { context, size in
                drawHelpBrush(&context, size: size, now: now, start: start, arrived: arrived, dark: dark)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 笔刷的节奏：cubic-bezier(.3,.45,.6,.92)，一半时间走到 68%，3/4 时间 90%，最后 1/4 慢慢挨近右边。
private let helpBrushCurve = TourBezier(x1: 0.3, y1: 0.45, x2: 0.6, y2: 0.92)
private let helpBrushRow: CGFloat = 2.5

/// 画一帧笔刷（放在文件层，Canvas 的画法闭包里不碰 View 自己的属性）。
private func drawHelpBrush(_ context: inout GraphicsContext, size: CGSize, now: Date, start: Date, arrived: Date?, dark: Bool) {
    let green = HelpStyle.green
    let width = size.width, height = size.height
    guard width > 0, height > 0 else { return }
    let elapsed = now.timeIntervalSince(start)
    let front = width * CGFloat(helpBrushCurve(elapsed / FeatureTour.helpWait))
    // 起步时整层 0.16 秒淡入；到位 0.26 秒后 0.56 秒淡掉。
    var layer = min(max(elapsed / 0.16, 0), 1)
    var after = -1.0
    if let arrived {
        after = now.timeIntervalSince(arrived)
        if after > 0.26 { layer *= max(0, 1 - (after - 0.26) / 0.56) }
    }

    if layer > 0 {
        // 墨晕：浅色 #047857 11%，深色 #6EE7B7 9%，比笔刷超前 40pt，糊 10pt。
        var ink = context
        ink.opacity = layer
        ink.addFilter(.blur(radius: 10))
        let inkColor = dark ? Color(hex: 0x6EE7B7).opacity(0.09) : Color(hex: 0x047857).opacity(0.11)
        let inkStart = max(0, front - 160), inkEnd = front + 40
        ink.fill(Path(CGRect(x: inkStart, y: 0, width: inkEnd - inkStart, height: height)),
                 with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0),
                                                        .init(color: inkColor, location: 0.7),
                                                        .init(color: .clear, location: 1)]),
                                       startPoint: CGPoint(x: inkStart, y: 0), endPoint: CGPoint(x: inkEnd, y: 0)))

        // 笔刷：一行一条笔触，每行的尽头在前沿前后错开、跟着进度慢慢变；行与行浓淡不一（66%–92%）。
        // 颜色帮回绿，左 18% → 右 24%（深色 24% → 32%），前沿后面 250pt 再浓 16%（深色 20%），尖上 30pt 淡出。
        var brush = context
        brush.opacity = layer
        brush.addFilter(.blur(radius: 1.2))
        let left = dark ? 0.24 : 0.18, right = dark ? 0.32 : 0.24, dense = dark ? 0.20 : 0.16
        let rows = Int((height / helpBrushRow).rounded(.up))
        for row in 0..<rows {
            let jitter = (tourNoise(row, 1) - 0.5) * 52 + 8 * sin(Double(front) / 37 + tourNoise(row, 2) * 2 * .pi)
            let end = max(0, front + CGFloat(jitter))
            guard end > 2 else { continue }
            let y = CGFloat(row) * helpBrushRow
            let strength = 0.66 + 0.26 * tourNoise(row, 3)
            let base = (left + (right - left) * Double(min(end / width, 1))) * strength
            let start250 = max(0, (end - 250) / end)
            let start30 = max(start250, (end - 30) / end)
            let stops: [Gradient.Stop] = [
                .init(color: green.opacity(left * strength), location: 0),
                .init(color: green.opacity(base), location: start250),
                .init(color: green.opacity(base + dense * strength), location: start30),
                .init(color: green.opacity(0), location: 1)]
            brush.fill(Path(CGRect(x: 0, y: y, width: end, height: helpBrushRow + 0.6)),
                       with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: end, y: y)))
        }
    }

    guard after >= 0 else { return }
    // 尽头一亮：右边一团白到绿的光晕，0.46 秒亮起又散掉。
    if after < 0.46 {
        let p = after / 0.46
        let glow = p < 0.25 ? p / 0.25 : 1 - (p - 0.25) / 0.75
        let radius = CGFloat(36 + 30 * p)
        let center = CGPoint(x: width - 6, y: height / 2)
        var flash = context
        flash.opacity = glow
        flash.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [.white.opacity(0.95), green.opacity(0.5), green.opacity(0)]),
                                         center: center, startRadius: 0, endRadius: radius))
    }
    // 碎成光点：白芯绿光晕，从笔刷后半段往右上飘 18–88pt，先放大再缩小消失。
    for i in 0..<28 {
        let delay = 0.2 * tourNoise(i, 11)
        let duration = 0.52 + 0.42 * tourNoise(i, 12)
        let u = (after - delay) / duration
        guard u > 0, u < 1 else { continue }
        let eased = 1 - (1 - u) * (1 - u)
        let distance = 18 + 70 * tourNoise(i, 13)
        let angle = (18 + 54 * tourNoise(i, 14)) * Double.pi / 180
        let x = width * CGFloat(0.5 + 0.5 * tourNoise(i, 15)) + CGFloat(cos(angle) * distance * eased)
        let y = height * CGFloat(tourNoise(i, 16)) - CGFloat(sin(angle) * distance * eased)
        let grow = u < 0.35 ? 1 + 0.6 * u / 0.35 : 1.6 * (1 - (u - 0.35) / 0.65)
        let dot = CGFloat((1.6 + 2.6 * tourNoise(i, 17)) * grow)
        let fade = 1 - u * u
        context.fill(Path(ellipseIn: CGRect(x: x - dot * 1.4, y: y - dot * 1.4, width: dot * 2.8, height: dot * 2.8)),
                     with: .color(green.opacity(0.4 * fade)))
        context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)),
                     with: .color(.white.opacity(0.95 * fade)))
    }
}

/// 到位时一道白色斜光带从左往右刷过整张卡：宽 96、斜 16°，中间白 78%（深色 26%），0.76 秒 cubic-bezier(.45,0,.25,1)。
private struct TourCardSheen: View {
    let start: Date
    @Environment(\.colorScheme) private var scheme

    private static let curve = TourBezier(x1: 0.45, y1: 0, x2: 0.25, y2: 1)

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start) / 0.76
                let p = CGFloat(Self.curve(t))
                LinearGradient(colors: [.white.opacity(0), .white.opacity(scheme == .dark ? 0.26 : 0.78), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 96, height: proxy.size.height * 1.6)
                    .rotationEffect(.degrees(16))
                    .position(x: -96 + (proxy.size.width + 192) * p, y: proxy.size.height / 2)
                    .opacity(t >= 1 ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 到位时卡边从紫变绿 #34D399 再变回，外面一圈 22pt 绿色柔光，0.9 秒。
private struct TourCardGlow: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(max(timeline.date.timeIntervalSince(start) / 0.9, 0), 1)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(hex: 0x34D399), lineWidth: 1.5)
                .shadow(color: Color(hex: 0x34D399).opacity(0.8), radius: 11)
                .opacity(t >= 1 ? 0 : sin(t * .pi))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 光标：1 秒一闪，打字时常亮。
private struct TourCaret: View {
    let color: Color
    let typing: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastChange = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let since = context.date.timeIntervalSince(lastChange)
            let on = reduceMotion || since < 0.5 || since.truncatingRemainder(dividingBy: 1) < 0.5
            Rectangle().fill(color).frame(width: 2, height: 18).opacity(on ? 1 : 0)
                .padding(.leading, 1)
        }
        .onChange(of: typing) { _ in lastChange = Date() }
    }
}

/// 「AI 正在改写…」轻轻呼吸，0.6 秒一次。
private struct TourBreathing<Content: View>: View {
    let reduceMotion: Bool
    @ViewBuilder var content: Content
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSince(start)
            content.opacity(reduceMotion ? 1 : 0.65 + 0.35 * cos(t * 2 * .pi / 0.6))
        }
    }
}

// MARK: - 分词面板（问答 3）

private struct TourWordPanel: View {
    @ObservedObject var model: TourModel
    let height: CGFloat

    @State private var wordFrames: [Int: CGRect] = [:]
    /// 这一下手势是在选还是在取消。
    @State private var dragSelect: Bool?
    /// 这一下是竖着拖、在滚词，不选词。
    @State private var dragScrolling = false
    /// 词往上滚了多少（≤ 0）、这一下开始滚时的位置、词整块的高度。
    @State private var wordsOffset: CGFloat = 0
    @State private var scrollBase: CGFloat = 0
    @State private var wordsHeight: CGFloat = 0

    private var compact: Bool { UIScreen.main.bounds.height < 700 }

    var body: some View {
        let script = model.script
        VStack(alignment: .leading, spacing: 10) {
            Text(model.picked.isEmpty
                 ? (compact ? L("点选，或横着划选", "Tap or swipe across", "タップか横になぞる")
                    : L("点选，或按住横着划选", "Tap, or hold and swipe across", "タップ、または長押しして横になぞる"))
                 : L("已选 \(model.picked.count) 个", "\(model.picked.count) selected", "\(model.picked.count) 個選択"))
                .font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
            // 自己滚，不用 ScrollView：选词手势按下就要接手。一开始竖着拖的算滚动；横着划连续选；没怎么动就松手算点选。
            GeometryReader { box in
                FlowLayout(spacing: 6) {
                    ForEach(Array(script.words.enumerated()), id: \.offset) { index, word in
                        chip(index, word, hint: script.hints.contains(index) && model.picked.isEmpty, first: index == script.hints.first)
                    }
                }
                .coordinateSpace(name: "tourWords")
                .onPreferenceChange(TourWordFramesKey.self) { wordFrames = $0 }
                .background(GeometryReader { Color.clear.preference(key: TourWordsHeightKey.self, value: $0.size.height) })
                .onPreferenceChange(TourWordsHeightKey.self) { wordsHeight = $0 }
                .offset(y: wordsOffset)
                .frame(width: box.size.width, height: box.size.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = abs(value.translation.width), dy = abs(value.translation.height)
                        if dragSelect == nil, !dragScrolling, dy > 8, dy > dx {
                            dragScrolling = true
                            scrollBase = wordsOffset
                        }
                        if dragScrolling {
                            let lowest = min(0, box.size.height - wordsHeight)
                            wordsOffset = min(0, max(lowest, scrollBase + value.translation.height))
                            return
                        }
                        if dragSelect == nil, dx <= 6 { return }
                        pick(at: content(value.startLocation))
                        pick(at: content(value.location))
                    }
                    .onEnded { value in
                        if !dragScrolling, dragSelect == nil, hypot(value.translation.width, value.translation.height) < 8 {
                            pick(at: content(value.location))
                        }
                        dragSelect = nil
                        dragScrolling = false
                    })
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                Label(L("插入", "Insert", "挿入"), systemImage: "text.insert")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TourColor.purple))
                    .opacity(model.picked.isEmpty ? 0.45 : 1)
                    .tourPress(.insert, model: model)
                Label(L("复制", "Copy", "コピー"), systemImage: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TourColor.key))
                    .opacity(model.picked.isEmpty ? 0.45 : 1)
                    .onTapGesture { model.wrong() }
                Text(L("全选", "All", "全選択")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    .frame(width: 64, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TourColor.key))
                    .onTapGesture { model.selectAll() }
            }
        }
        .padding(10)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(light: 0xF1F0FA, dark: 0x232325)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TourColor.ring.opacity(0.4), lineWidth: 1))
    }

    /// 手指在框里的位置换成词那一块里的位置（扣掉已经滚上去的）。
    private func content(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: point.y - wordsOffset)
    }

    /// 手指下的那一块：第一块决定这一下是选还是取消。
    private func pick(at location: CGPoint) {
        guard let hit = wordFrames.first(where: { $0.value.insetBy(dx: -3, dy: -3).contains(location) })?.key else { return }
        let select = dragSelect ?? !model.picked.contains(hit)
        dragSelect = select
        model.toggleWord(hit, on: select)
    }

    @ViewBuilder
    private func chip(_ index: Int, _ word: String, hint: Bool, first: Bool) -> some View {
        let picked = model.picked.contains(index)
        let view = Text(word)
            .font(.system(size: 14))
            .foregroundStyle(picked ? Color.white : Color.primary)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(picked ? TourColor.purple : TourColor.key))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(TourColor.ring, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .opacity(hint ? 1 : 0))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: TourWordFramesKey.self, value: [index: proxy.frame(in: .named("tourWords"))])
            })
        if first { view.tourTarget(.words) } else { view }
    }
}

private struct TourWordsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TourWordFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - 模拟的 App 风格页（润色风格 2）

/// 键盘上的「＋」本来就是去 App 管理风格，演示里「假装跳转」：画一块模拟页面，不真的打开 App、不写用户的风格。
struct TourAppPage: View {
    @ObservedObject var model: TourModel

    var body: some View {
        let script = model.script
        VStack(spacing: 0) {
            Text(L("飞地输入法 App · 添加润色风格（演示）", "Enclave app · Add Polish Style (demo)", "Enclave アプリ · 整えるスタイルを追加（デモ）"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(height: 30)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        Text(L("润色风格", "Polish styles", "整えるスタイル")).font(.system(size: 15))
                    }
                    .foregroundStyle(TourColor.purpleText)
                    .onTapGesture { model.wrong() }
                    Spacer()
                    Text(L("添加润色风格", "Add Polish Style", "整えるスタイルを追加")).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text(L("完成", "Done", "完了")).font(.system(size: 17, weight: .semibold)).foregroundStyle(TourColor.purpleText)
                        .padding(.horizontal, 6).frame(height: 30)
                        .tourPress(.done, model: model)
                }
                .frame(height: 40)
                label(L("名称", "Name", "名前"))
                Text(model.sheetName.isEmpty ? " " : model.sheetName)
                    .font(.system(size: 17))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourUI.group))
                label(L("提示词内容", "Prompt", "プロンプトの内容"))
                Text(model.sheetContent.isEmpty ? " " : model.sheetContent)
                    .font(.system(size: 15))
                    .lineLimit(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourUI.group))
                HStack(spacing: 4) {
                    if model.improving {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    }
                    Text(L("AI 优化", "Improve with AI", "AI で改善")).font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(TourColor.purpleText)
                // 整行都能点：原来只有图标和字那么宽（约 80pt），在模拟器上点「优化」两个字有一次没反应，点左半边才行（PR #109）。
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
                .tourPress(.improve, model: model, anchor: .leading)
                label(L("建议", "Suggestions", "候補"))
                FlowLayout(spacing: 6) {
                    ForEach(Array(script.tags.enumerated()), id: \.offset) { index, tag in
                        tagChip(index, tag)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
        // 矮屏少 80：上面还有顶栏和说明。
        .frame(height: UIScreen.main.bounds.height < 700 ? 480 : 560)
        .frame(maxWidth: .infinity)
        .background(TopRounded(radius: 22).fill(TourUI.page).shadow(color: .black.opacity(0.08), radius: 8, y: -2)
            .ignoresSafeArea(edges: .bottom))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4).padding(.leading, 4)
    }

    private func tagChip(_ index: Int, _ tag: String) -> some View {
        let picked = model.pickedTags.contains(index)
        return HStack(spacing: 3) {
            Image(systemName: picked ? "checkmark" : "plus").font(.system(size: 10, weight: .bold))
            Text(tag).font(.system(size: 13)).lineLimit(1)
        }
        .foregroundStyle(TourColor.purpleText)
        .padding(.horizontal, 10).frame(height: 30)
        .background(Capsule().fill(picked ? TourColor.pillOn : TourUI.group))
        .overlay(Capsule().strokeBorder(TourColor.ring.opacity(picked ? 1 : 0.4), lineWidth: 1))
        .fixedSize()
        .tourPress(.tag(index), model: model)
    }
}
