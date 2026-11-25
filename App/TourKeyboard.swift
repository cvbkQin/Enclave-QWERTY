import SwiftUI

// 功能演示里画的键盘（T95，design/onboard-v2 第五节「模拟键盘」）：按选的布局画九宫格或全键盘，样子照真键盘。
// AI 栏（润色、问答、复制后弹出的帮回键、固定的风格、撤销重做）、回答卡和识意框、风格下拉、分词面板、
// 打字一章的长按一排 / 十字 / 触控板 / 常用与剪贴板，都只是画出来，不接真键盘的逻辑。只有触点指着的那一处能点。

// MARK: - 颜色

enum TourColor {
    static let keyboard = Color(light: 0xD9DAE0, dark: 0x2B2B2D)
    static let key = Color(light: 0xFFFFFF, dark: 0x5A5A5E)
    static let pressedKey = Color(light: 0xB9BCC6, dark: 0x3F3F43)
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
    func tourPress(_ id: TourTarget, model: TourModel) -> some View {
        modifier(TourPress(id: id, model: model))
    }
}

private struct TourPress: ViewModifier {
    let id: TourTarget
    @ObservedObject var model: TourModel

    func body(content: Content) -> some View {
        let pressed = model.pressed == id
        let demo = model.demoDown && model.target == id && model.pressed == nil
        content
            .scaleEffect(pressed ? 0.96 : demo ? 0.97 : 1)
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
                .overlay(Color.gray.opacity(model.trackpad ? 0.18 : 0))
                .clipShape(TopRounded(radius: compact ? 22 : 26))
                .contentShape(Rectangle())
                .onTapGesture { model.wrong() })
        .animation(.easeOut(duration: 0.2), value: model.trackpad)
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
                TourPopupView(model: model, containerWidth: width, keyHeight: keyHeight)
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
                ForEach(rows[0], id: \.self) { letterKey($0, width: letter, containerWidth: width) }
            }
            HStack(spacing: gap) {
                ForEach(rows[1], id: \.self) { letterKey($0, width: letter, containerWidth: width) }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: gap) {
                plainKey(Image(systemName: "shift"), width: letter * 1.3)
                Spacer(minLength: 0)
                HStack(spacing: gap) {
                    ForEach(rows[2], id: \.self) { letterKey($0, width: letter, containerWidth: width) }
                }
                Spacer(minLength: 0)
                plainKey(Image(systemName: "delete.left"), width: letter * 1.3)
            }
            HStack(spacing: gap) {
                plainKey(Text("123"), width: letter * 1.3, font: 15)
                plainKey(Image(systemName: "face.smiling"), width: letter * 1.1)
                plainKey(Text(L("中/英", "中/EN", "中/英")), width: letter * 1.1, font: 14)
                if punctLeft { punctKey(width: letter * 1.1, containerWidth: width) }
                TourSpaceKey(model: model, title: L("空格", "space", "空白"), height: keyHeight)
                    .frame(width: space)
                if !punctLeft { punctKey(width: letter * 1.1, containerWidth: width) }
                returnKey.frame(width: letter * 1.9, height: keyHeight)
            }
        }
    }

    @ViewBuilder
    private func letterKey(_ letter: String, width: CGFloat, containerWidth: CGFloat) -> some View {
        if letter == "e" {
            TourHoldKey(hit: .letter, model: model, height: keyHeight, containerWidth: containerWidth) {
                Text(letter).font(.system(size: 22))
            }
            .frame(width: width)
        } else {
            plainKey(Text(letter), width: width, font: 22)
        }
    }

    private func punctKey(width: CGFloat, containerWidth: CGFloat) -> some View {
        TourHoldKey(hit: .punct, model: model, height: keyHeight, containerWidth: containerWidth) {
            Text(punctLabel).font(.system(size: 17)).tracking(-1)
        }
        .frame(width: width)
    }

    private func plainKey<Label: View>(_ label: Label, width: CGFloat, font: CGFloat = 17) -> some View {
        label
            .font(.system(size: font))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.primary)
            .opacity(model.trackpad ? 0 : 1)
            .frame(width: width, height: keyHeight)
            .background(TourKeyCap())
            .contentShape(Rectangle())
            .onTapGesture { model.wrong() }
    }

    // 九宫格

    private func nineKeys(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            if model.clipboardOpen {
                TourClipboardPanel(model: model)
                    .frame(maxWidth: .infinity)
                    .frame(height: keysHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                    GridRow {
                        gridKey(Text("123"))
                        TourHoldKey(hit: .punct, model: model, height: keyHeight, containerWidth: width) {
                            Text(model.script.chinesePunct ? "，。?!" : ",.?!").font(.system(size: 17))
                        }
                        gridKey(Text("ABC"))
                        TourHoldKey(hit: .letter, model: model, height: keyHeight, containerWidth: width) {
                            Text("DEF").font(.system(size: 17))
                        }
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
                .transition(.opacity)
            }
            VStack(spacing: gap) {
                gridKey(Image(systemName: "delete.left"))
                gridKey(Text(L("重输", "Clear", "クリア")))
                returnKey.frame(height: keyHeight * 2 + gap)
            }
            .frame(width: min(66, width * 0.19))
        }
    }

    /// 「常 用 / 剪贴板」两行（和真键盘一致）：打开左边常用语、右边剪贴板的面板。
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
        .tourPress(.clipKey, model: model)
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
                .opacity(model.trackpad ? 0 : 1)
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

    /// 卡头跟着哪一种：有结果看结果，生成中看哪颗键在跑。
    private var mode: TourModel.CardMode? {
        if model.regenerating || (model.sparkRunning && version == nil) { return .rewrite }
        if model.helpRunning && version == nil { return .help }
        if (model.askRunning || model.searching) && version == nil { return .answer }
        return version?.mode
    }

    private var ring: Color {
        switch mode {
        case .answer: return TourColor.answerRing
        case .help: return HelpStyle.green
        default: return TourColor.ring
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            replaceKey
            VStack(spacing: 0) {
                top
                    .frame(height: model.cardTall ? 120 : 82)
                    .modifier(TourHoldable(enabled: true, target: .card, model: model))
                Rectangle().fill(model.askEditing ? TourColor.purple : TourColor.askLine).frame(height: 1)
                askRow.frame(height: 40)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TourColor.cardFill))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ring, lineWidth: 1.5))
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
        if model.generating {
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

    /// 卡头：改写「✦ AI 改写 · 润色」，帮回「回 AI 帮回 · 润色」，问答「AI 回答 · 直击要害」+ 联网标签。
    /// 重新生成时换成「AI 正在改写…」，轻轻呼吸。
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
                Text(L("回", "R", "返"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(HelpStyle.badgeText)
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(HelpStyle.badgeFill))
                Text(L("AI 帮回", "AI reply", "AI 返信") + " · " + styleName)
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                    .foregroundStyle(TourColor.purpleText)
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
                    Text(L("写下要求或问题", "Type a request or question", "要望や質問を入力"))
                        .foregroundStyle(TourColor.askLine)
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

// MARK: - 打字一章：按住的键、空格触控板、弹出层、常用与剪贴板

/// 按住才弹出的键（全键盘「，。」、e；九宫格「，。?!」、DEF）：按下 → holdBegan，滑 → holdMoved，松手 → holdEnded。
private struct TourHoldKey<Label: View>: View {
    let hit: TourTarget
    @ObservedObject var model: TourModel
    let height: CGFloat
    /// 键区的宽：弹出的一排不出键区。
    let containerWidth: CGFloat
    @ViewBuilder var label: Label

    @State private var frame: CGRect = .zero
    @State private var began = false

    var body: some View {
        let demo = model.demoDown && model.target == hit && model.pressed == nil && model.popup == nil
        let holding = began && model.popup != nil
        label
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.primary)
            .opacity(model.trackpad || holding ? 0 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(TourKeyCap(fill: holding ? TourColor.pressedKey : TourColor.key))
            .scaleEffect(demo ? 0.97 : 1)
            .brightness(demo ? -0.04 : 0)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .named("tourKeys")) }
                    .onChange(of: geo.frame(in: .named("tourKeys"))) { frame = $0 }
            })
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !began {
                        began = true
                        model.holdBegan(hit, key: frame, containerWidth: containerWidth)
                    } else {
                        model.holdMoved(value.translation, containerWidth: containerWidth)
                    }
                }
                .onEnded { _ in
                    began = false
                    model.holdEnded(containerWidth: containerWidth)
                })
            .tourTarget(hit)
    }
}

/// 全键盘按住空格：键盘变灰成触控板，左右滑挪光标。
private struct TourSpaceKey: View {
    @ObservedObject var model: TourModel
    let title: String
    let height: CGFloat
    @State private var began = false

    var body: some View {
        let demo = model.demoDown && model.target == .space && model.pressed == nil && !model.trackpad
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .opacity(model.trackpad ? 0 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(TourKeyCap(fill: model.trackpad ? TourColor.pressedKey : TourColor.key))
            .scaleEffect(demo ? 0.98 : 1)
            .brightness(demo ? -0.04 : 0)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !began {
                        began = true
                        model.trackpadBegan()
                    } else {
                        model.trackpadMoved(value.translation.width)
                    }
                }
                .onEnded { _ in
                    began = false
                    model.trackpadEnded()
                })
            .tourTarget(.space)
    }
}

/// 按住弹出来的：全键盘一排（第 88 条：默认那格正对按键、一弹出就选中），九宫格十字（左上右下，中间松手取消）。
private struct TourPopupView: View {
    @ObservedObject var model: TourModel
    let containerWidth: CGFloat
    let keyHeight: CGFloat

    var body: some View {
        if let popup = model.popup {
            switch popup.kind {
            case .row(let row):
                rowView(row, popup: popup)
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            case .cross(let options, let center):
                crossView(options, center: center, popup: popup)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    private func rowView(_ row: AlternatesRow, popup: TourModel.Popup) -> some View {
        let key = popup.key
        let arranged = row.arranged(centerX: key.midX, cellWidth: key.width, containerWidth: containerWidth)
        let height = keyHeight + 4
        return HStack(spacing: 0) {
            ForEach(Array(arranged.options.enumerated()), id: \.offset) { index, option in
                let on = index == popup.index
                Text(option)
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .frame(width: key.width, height: height - 8)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? TourColor.purple : .clear))
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TourColor.key)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2))
        .offset(x: arranged.minX - 4, y: key.minY - height - 6)
        .accessibilityHidden(true)
    }

    private func crossView(_ options: [TourModel.CrossArm: String], center: String, popup: TourModel.Popup) -> some View {
        let key = popup.key
        let w = key.width, h = key.height
        return ZStack {
            // 托盘：中间那格加四个方向。
            ForEach([TourModel.CrossArm.left, .up, .right, .down], id: \.self) { arm in
                if let text = options[arm] {
                    let on = popup.arm == arm
                    Text(text)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(width: w - 4, height: h - 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? TourColor.purple : TourColor.key)
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 1))
                        .offset(x: offset(arm).width * w, y: offset(arm).height * h)
                }
            }
            Text(center)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: w - 4, height: h - 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TourColor.pressedKey))
        }
        .frame(width: w, height: h)
        .offset(x: key.minX, y: key.minY)
        .accessibilityHidden(true)
    }

    private func offset(_ arm: TourModel.CrossArm) -> CGSize {
        switch arm {
        case .left: return CGSize(width: -1, height: 0)
        case .up: return CGSize(width: 0, height: -1)
        case .right: return CGSize(width: 1, height: 0)
        case .down: return CGSize(width: 0, height: 1)
        }
    }
}

/// 九宫格「常用 / 剪贴板」面板：左边常用语，右边最近拷贝的内容，点一条即上屏。
private struct TourClipboardPanel: View {
    @ObservedObject var model: TourModel

    var body: some View {
        let script = model.script
        HStack(spacing: 6) {
            column(L("常用", "Saved", "定型"), items: script.phrases, anchorFirst: false)
            column(L("剪贴板", "Clipboard", "クリップボード"), items: script.clips, anchorFirst: true)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(light: 0xF1F0FA, dark: 0x232325)))
    }

    private func column(_ title: String, items: [String], anchorFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let row = Text(item)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(TourColor.key))
                    .contentShape(Rectangle())
                if anchorFirst && index == 0 {
                    row.onTapGesture { model.pickClip(item) }.tourTarget(.clipItem)
                } else {
                    row.onTapGesture { model.pickClip(item) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
                .frame(height: 32)
                .tourPress(.improve, model: model)
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
