import SwiftUI

/// 键盘主体。
/// AI 栏永远紧贴按键上方，收起和展开是同一条：[抽屉] [✨] [改写风格 ▾] [问答风格 ▾] … [撤销|重做]；打拼音时这一行换成候选。
/// 展开抽屉时 AI 栏上面是回答卡和识意框一整块，左边一颗替换 / 插入键（MG2）；风格键在展开时换掉识意框，收着时往上浮起一行。
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel

    private var inset: CGFloat { KeyboardMetrics.sidePadding + KeyboardMetrics.keyInsetX }

    var body: some View {
        VStack(spacing: 0) {
            if let gate = model.gate {
                // 提示卡单独占上方，结果卡片和展开的一行先让开。
                GateCard(model: model, gate: gate)
                    .frame(height: KeyboardMetrics.gateHeight(gate))
                    .padding(.horizontal, inset)
                    .padding(.top, KeyboardMetrics.panelTop)
            } else if model.aiExpanded {
                // 替换 / 插入键在结果卡左边，和卡片一样高；弹出方式的另一个按钮浮在下面一行上，所以这一块叠在最上层。
                // 自由编辑时左边的键收起，编辑框占满整行、连识意框那块一起用（FE3）。
                let freeEdit = model.target == .card
                HStack(spacing: KeyboardMetrics.resultKeyGap) {
                    if !freeEdit {
                        ResultKey(model: model)
                            .frame(width: KeyboardMetrics.resultKeyWidth)
                    }
                    ResultCard(model: model)
                }
                .frame(height: freeEdit
                       ? KeyboardMetrics.cardHeight(tall: model.freeEditTall, aiLabel: model.showsAILabel) + KeyboardMetrics.freeEditExtra
                       : KeyboardMetrics.cardHeight(tall: model.cardTall, aiLabel: model.showsAILabel) + KeyboardMetrics.askBoxHeight)
                .overlay(alignment: .top) {
                    if model.freeEditToast {
                        FreeEditToast().offset(y: -2).transition(.opacity).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.top, KeyboardMetrics.panelTop)
                .zIndex(2)
            }
            if model.showsTrialReminder {
                TrialReminderStrip(model: model)
                    .frame(height: KeyboardMetrics.trialReminderHeight)
                    .padding(.horizontal, inset)
                    .padding(.top, KeyboardMetrics.panelTop)
            }
            // 拼音行一直占位，平时空着；打字时出拼音和细线，键盘高度不变（PY7）。
            // 拼音显示在侧边（F12）时没有这一行，拼音在九宫格左列 / 全键盘候选栏左边的拼音键里。
            if !model.pinyinSide {
                ZStack {
                    if model.pinyinRowShown { PinyinRow(model: model) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: KeyboardMetrics.pinyinRowHeight)
            }
            ZStack {
                // 候选栏一直留着、不打字时藏起来：放在 if 里的话每打完一个词它就被拆掉，下一个字母再整个重建（连同里面的滚动视图）。
                candidateBar
                    .opacity(showsCandidateBar ? 1 : 0)
                    .allowsHitTesting(showsCandidateBar)
                    .accessibilityHidden(!showsCandidateBar)
                if !showsCandidateBar {
                    if model.target == .card {
                        cardEditHint
                    } else {
                        aiBar
                    }
                }
            }
            .frame(height: KeyboardMetrics.topRow)
            // 长按候选的小气泡朝下，盖在按键上（键盘画不到候选栏上面）。
            .overlay(alignment: .topLeading) {
                if let menu = model.candidateMenu {
                    GeometryReader { geo in
                        CandidateMenuBubble(model: model, menu: menu, barWidth: geo.size.width)
                    }
                }
            }
            // 拼音键的弹框（F12）：往下盖在按键上（键盘收着时上面没有地方可画），选完或点框外收起。
            .overlay(alignment: .topLeading) {
                if model.pinyinPopoverOpen, model.pinyinKeyTitle != nil {
                    PinyinKeyPopover(model: model)
                        .padding(.leading, 4)
                        .offset(y: KeyboardMetrics.topRow + 4)
                }
            }
            // 按住 ✨ 弹出的「问答」盖在按键上面；弹出时「改写」还要盖在回答卡（zIndex 2）上面。
            .zIndex(model.askHoldShowing || model.pinyinPopoverOpen ? 3 : 1)
            KeysView(model: model)
                // 横屏九宫格居中 420 宽，不拉宽。
                .frame(maxWidth: model.landscape && model.nineGrid ? KeyboardMetrics.landscapeNineWidth : .infinity)
                .padding(.horizontal, KeyboardMetrics.sidePadding)
                .layoutPriority(1)
                // 气泡开着时点按键区别处只关气泡，不打字。
                .overlay {
                    if model.candidateMenu != nil {
                        Color.black.opacity(0.001).onTapGesture { model.dismissCandidateMenu() }
                    }
                    if model.pinyinPopoverOpen {
                        Color.black.opacity(0.001).onTapGesture { model.pinyinPopoverOpen = false }
                    }
                }
                // 长按弹出的十字 / 备选 / 布局菜单会伸到上面一排：这时按键区整块盖在 AI 栏和回答卡上面，不被 ✨、风格键压住。
                // 剪贴板的长按菜单也一样（往上可以盖到 AI 栏）。
                .zIndex(model.cross != nil || model.alternates != nil || model.layoutMenu != nil || model.clipMenu != nil ? 4 : 0)
        }
        // 横屏两边各留 48 给刘海 / 灵动岛。
        .padding(.horizontal, model.landscape ? KeyboardMetrics.landscapeSideMargin : 0)
        // 系统给的高度不够时从顶上裁，按键始终完整贴在底部。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(boardBackground)
        // 使用指引「一键应用」后的小手指，画在键盘里面。
        .coachHandOverlay(model)
        // 润色风格 / 问答风格的下拉框（KB1、KB2）：从被点的那颗键下面往下弹，盖在按键上；点框外收起，被盖住的键不响应。
        .overlay(alignment: .topLeading) {
            if let row = model.aiRow, let chip = chipFrames[row] {
                GeometryReader { geo in
                    let x = min(max(chip.minX, 4), geo.size.width - StyleDropdown.width - 4)
                    let y = chip.maxY + 4
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.001)
                            .onTapGesture { model.aiRow = nil }
                        StyleDropdown(model: model, row: row, maxHeight: geo.size.height - y - 6)
                            .offset(x: x, y: y)
                    }
                }
            }
        }
        // 长按固定键弹的「取消固定」（AK5）：从那颗键下面弹出，点框外收起。
        .overlay(alignment: .topLeading) {
            if let id = model.pinMenu, let pin = model.settings.pinnedStyles.first(where: { $0.style.id == id }), let frame = pinFrames[id] {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.001)
                            .onTapGesture { model.pinMenu = nil }
                        UnpinBubble(model: model, style: pin.style)
                            .fixedSize()
                            .offset(x: min(max(frame.minX, 4), geo.size.width - 130), y: frame.maxY + 4)
                    }
                }
            }
        }
        // 键盘里拉不起 App 时（有的系统版本、有的 App 里不让）：请人自己打开。
        .overlay(alignment: .top) {
            if model.openAppFailed {
                Text(L("打不开飞地输入法 App，请回到主屏幕手动打开它", "Couldn't open the Enclave app. Open it from the Home Screen.", "Enclave アプリを開けませんでした。ホーム画面から開いてください。"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.78)))
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        // B1 剪贴板实测条（临时）：盖在 AI 栏上。
        .overlay(alignment: .top) {
            if model.settings.clipboardProbe { ClipboardProbeStrip() }
        }
        .coordinateSpace(name: "keyboard")
        .onPreferenceChange(PinFrameKey.self) { frames in
            if frames != pinFrames { pinFrames = frames }
        }
        .onPreferenceChange(RowChipFrameKey.self) { frames in
            // 打拼音时 AI 栏换成候选栏、按钮不在了，沿用上次的位置。
            if !frames.isEmpty, frames != chipFrames { chipFrames = frames }
        }
        .clipped()
    }

    /// 键盘底色。拼音行在最上面时，键盘最顶上一截（拼音行那么高）从上往下由透明渐变到不透明，
    /// 接上系统键盘顶上那截液态玻璃，不留硬边；再往下全是不透明底色，盖住 Chrome 切回时系统按键的残影（GL1）。
    /// 系统给的高度比 keyboardHeight 多时，渐变不跟着拉长：多出来的那截和拼音行一样是不透明底色，不露一截渐变空白。
    /// 回答卡、风格一排、提示卡在最上面时整块不透明。
    @ViewBuilder
    private var boardBackground: some View {
        // #19（对齐清单 53）：键盘自己不画底色，露出系统给键盘的毛玻璃（和顶上 17 的系统条、地球键那条是同一块），
        // 顶边、底边都没有线，也不用渐变。按键、回答卡、识意框、拼音列、下拉框、菜单和面板各自的底色照旧。
        // 测试开关关掉时（Chrome 切回有系统按键残影）退回原来的不透明底色。
        // 不能用 .clear：完全透明的地方系统不把触摸交给键盘（同 KeyTouchView），候选栏 ⌄ 只有箭头线条点得中，
        // 整页候选只有按在字上才滑得动。垫一层 0.001 透明度的底，看起来照样透出毛玻璃，整块键盘都接触摸。
        if model.settings.keyboardGlass {
            Color.black.opacity(0.001)
        } else {
            opaqueBackground
        }
    }

    private var opaqueBackground: some View {
        let fades = model.gate == nil && !model.aiExpanded && model.aiRow == nil && !model.showsTrialReminder && !model.pinyinSide
        return VStack(spacing: 0) {
            LinearGradient(stops: [
                .init(color: Brand.keyboardBack.opacity(0), location: 0),
                .init(color: Brand.keyboardBack.opacity(0.28), location: 0.30),
                .init(color: Brand.keyboardBack.opacity(0.72), location: 0.65),
                .init(color: Brand.keyboardBack, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .opacity(fades ? 1 : 0)
            .background(fades ? Color.clear : Brand.keyboardBack)
            .frame(height: KeyboardMetrics.pinyinRowHeight)
            Brand.keyboardBack
        }
        .ignoresSafeArea()
    }

    /// 两颗风格键在键盘里的位置，下拉框从它下面弹出。
    @State private var chipFrames: [KeyboardModel.AIRow: CGRect] = [:]
    /// 固定键在键盘里的位置，「取消固定」从它下面弹出。
    @State private var pinFrames: [UUID: CGRect] = [:]

    // MARK: - AI 栏

    /// 在卡片里改结果时 AI 栏换成提示。
    /// 自由编辑中（FE3）：左边「✎ 正在修改 AI 结果」，右边「取消修改」「✓ 完成修改」，完成在最右。
    private var cardEditHint: some View {
        HStack(spacing: 8) {
            Label(L("正在修改 AI 结果", "Editing AI result", "AI の結果を編集中"), systemImage: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.modeRewriteText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Brand.modeRewriteFill))
            Spacer(minLength: 0)
            Button { model.cancelCardEdit() } label: {
                Text(L("取消修改", "Cancel", "キャンセル"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.primary)
                    .frame(width: 84, height: KeyboardMetrics.chipHeight)
                    .background(Capsule().fill(KeyStyle.charKey))
            }
            .buttonStyle(KeyPressStyle())
            Button { model.finishCardEdit() } label: {
                Label(L("完成修改", "Done", "完了"), systemImage: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .frame(width: 104, height: KeyboardMetrics.chipHeight)
                    .background(Capsule().fill(LinearGradient(colors: Brand.insertGradient, startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(KeyPressStyle())
        }
        .padding(.horizontal, inset)
    }

    /// 收起和展开同一排（AK4、AK5）：▭ 抽屉（固定）｜ 中间滑动区：润色键、问答键、1×20 竖线、固定的风格键 ｜ 撤销 / 重做（固定）。
    /// 放不下就左右滑，哪边还有被遮住的内容哪边渐隐（AIKeyStrip）。没固定任何风格时不显示竖线。
    /// 方案 A（v309）：间距 5、▭ 宽 36、撤销重做小胶囊约 64，402 宽的屏上至少完整露出一颗两字固定键。
    /// 滑动区自带左右 5 的内边（给亮边留地方），所以它和 ▭、撤销重做之间不再加间距，看上去也是 5。
    private var aiBar: some View {
        let pins = model.settings.pinnedStyles
        return HStack(spacing: 0) {
            PanelToggleButton(expanded: model.aiExpanded, hasNew: model.showsNewResult) {
                model.endCoach()
                model.setAIExpanded(!model.aiExpanded)
            }
            AIKeyStrip {
                HStack(spacing: 5) {
                    StyleKey(model: model, row: .prompts)
                    StyleKey(model: model, row: .answerStyles)
                    if !pins.isEmpty {
                        Rectangle().fill(Color(UIColor.separator)).frame(width: 1, height: 20)
                            .padding(.horizontal, -1)
                        ForEach(pins, id: \.style.id) { pin in
                            PinnedStyleKey(model: model, style: pin.style, answer: pin.answer)
                        }
                    }
                }
            }
            .frame(height: KeyboardMetrics.topRow)
            UndoRedoPair(model: model)
        }
        .padding(.horizontal, inset)
    }

    /// 打拼音、或者上屏后有联想时显示候选栏。
    private var showsCandidateBar: Bool { model.isComposing || model.showsPredictions }

    /// 「✓ 已删除「xx」」+ 右边「撤销」胶囊。
    private func candidateUndoBar(_ undo: KeyboardModel.CandidateUndo) -> some View {
        let word = model.outputText(undo.word)
        return HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.success)
            Text(undo.restored
                 ? L("已恢复默认位置「\(word)」", "“\(word)” back to its default spot", "「\(word)」を元の位置に戻しました")
                 : L("已删除「\(word)」", "Deleted “\(word)”", "「\(word)」を削除しました"))
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button { model.undoCandidateDelete() } label: {
                Text(L("撤销", "Undo", "取り消す"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.deepPurple)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Brand.returnSoftFill))
            }
            .buttonStyle(KeyPressStyle())
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    /// 打拼音时的候选栏，右边的箭头展开整页候选；显示联想时箭头换成关闭。
    private var candidateBar: some View {
        let predicting = !model.isComposing
        return HStack(spacing: 0) {
            // 全键盘拼音在侧边（F12）：最左边一颗拼音键显示现在的切法，点开选切法 / 纠正读法。
            if let title = model.pinyinKeyTitle {
                PinyinKey(model: model, title: title)
                Rectangle().fill(Color(UIColor.separator)).frame(width: 1, height: 22)
            } else if model.pinyinSide, model.showsNineKey, let pinyin = model.offFieldPinyin {
                // 侧边九宫格、输入框不认标记文字（NM2）：整串拼音放在候选栏最左边，后面一条竖线再接候选。
                OffFieldPinyinText(text: pinyin, size: 16)
                    .padding(.leading, KeyboardMetrics.nineSideMargin + 10)
                    .padding(.trailing, 10)
                    .frame(maxWidth: 170, alignment: .leading)
                    .layoutPriority(1)
                Rectangle().fill(Color(UIColor.separator)).frame(width: 1, height: 22)
            }
            // 点击判定在 UIKit 里做，见 CandidateStrip。删了候选后 3 秒内换成撤销条（CL4）。
            ZStack {
                CandidateStrip(model: model)
                    .opacity(model.candidateUndo == nil ? 1 : 0)
                    .allowsHitTesting(model.candidateUndo == nil)
                if let undo = model.candidateUndo {
                    candidateUndoBar(undo)
                }
            }
            Divider().frame(height: 22)
            Button {
                if predicting {
                    model.dismissPredictions()
                } else {
                    // 照系统键盘：展开从候选栏下面往下拉开，收起往上卷回，弹性很小、不拖泥带水；动画中途再点立刻反向。
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) { model.candidatesExpanded.toggle() }
                }
            } label: {
                // 展开、收起是同一个箭头转半圈，不换图。
                Image(systemName: predicting ? "xmark" : "chevron.down")
                    .rotationEffect(.degrees(!predicting && model.candidatesExpanded ? 180 : 0))
                    // 联想时的关闭键小一号、灰色：联想只是建议，关闭键不和字抢眼（UI 稿 KP1）。
                    .font(.system(size: predicting ? 15 : 17, weight: predicting ? .medium : .regular))
                    .foregroundStyle(predicting ? Color.secondary : Color.primary)
                    // 放宽到 54pt，靠右边缘也好按。
                    .frame(width: 54)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeyPressStyle())
        }
    }
}

// MARK: - AI 栏的按钮

/// 展开/收起 AI 面板（回答卡和识意框一整块 + 替换 / 插入），AI 栏最左边 44×34 的面板图标胶囊（方案 B）。
/// 收起时有没看过的新结果：图标变紫、右上角紫点；展开时浅紫底紫描边，和选择器打开时一样。
struct PanelToggleButton: View {
    var expanded: Bool
    var hasNew: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "rectangle.tophalf.inset.filled")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(expanded ? Brand.toggleOpenIcon : (hasNew ? Brand.newResultIcon : Color.primary))
                .frame(width: 36, height: KeyboardMetrics.chipHeight)
                .background(Capsule().fill(expanded ? Brand.toggleOpenFill : KeyStyle.charKey))
                .overlay(Capsule().strokeBorder(Brand.toggleOpenStroke, lineWidth: expanded ? 1.5 : 0))
                .overlay(alignment: .topTrailing) {
                    if hasNew {
                        Circle().fill(Brand.newResultDot)
                            .frame(width: 10, height: 10)
                            .padding(2)
                            .background(Circle().fill(Brand.keyboardBack))
                            .offset(x: 3, y: -3)
                    }
                }
                // 点按区上下各扩 5pt，至少 44×44。
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .padding(.vertical, -5)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = expanded ? L("收起结果", "Hide result", "結果を隠す") : L("展开结果", "Show result", "結果を表示")
        return hasNew ? base + L("，有新结果", ", new result", "、新しい結果あり") : base
    }
}

/// 撤销和重做拼成一个胶囊，中间一条细线。AI 栏最右边，收起和展开都在。
struct UndoRedoPair: View {
    @ObservedObject var model: KeyboardModel

    /// 高 34、圆角 17（和栏里别的键一样高，v307）。方案 A（v309）缩成小胶囊：左右内边 9、16pt 箭头、中间 1×16 细竖线，总宽 64。
    static let halfWidth: CGFloat = 31.5
    static var width: CGFloat { halfWidth * 2 + 1 }
    static var height: CGFloat { KeyboardMetrics.chipHeight }

    var body: some View {
        HStack(spacing: 0) {
            half("arrow.uturn.backward", enabled: model.canUndo, leading: true) { model.undo() }
            Rectangle().fill(Color(UIColor.separator)).frame(width: 1, height: 16)
            half("arrow.uturn.forward", enabled: model.canRedo, leading: false) { model.redo() }
        }
        .frame(width: Self.width, height: Self.height)
        .background(Capsule().fill(KeyStyle.charKey))
    }

    private func half(_ systemImage: String, enabled: Bool, leading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                // 箭头离外边 9，两个箭头靠向中间的竖线。
                .padding(leading ? .leading : .trailing, 9)
                .frame(width: Self.halfWidth, height: Self.height, alignment: leading ? .leading : .trailing)
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(leading ? L("撤销", "Undo", "取り消す") : L("重做", "Redo", "やり直す"))
    }
}

/// 点「润色」时 AI 栏上方的提示卡。
/// 没开完全访问（P02）：说明打字不受影响，「去开启」打开 App 再跳到系统设置。
/// 首次发送前确认（P03/P04）：写明发到哪个地址、发什么，「同意并润色」记下地址并开始。
struct GateCard: View {
    @ObservedObject var model: KeyboardModel
    let gate: KeyboardModel.AIGate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch gate {
            case .fullAccess: fullAccess
            case .privacy: privacy
            case .noKey: noKey
            case .consent(let endpoint, let previous): consent(endpoint, previous: previous)
            case .quotaUsed: quotaUsed
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.panelFill)
            .shadow(color: .black.opacity(0.06), radius: 0.5)
            .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.10), radius: 10, y: 6))
    }

    @ViewBuilder
    private var fullAccess: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brand.deepPurple)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Brand.returnSoftFill))
            Text(L("AI 润色需要开启「允许完全访问」", "AI Polish needs Allow Full Access", "AI 機能には「フルアクセスを許可」が必要です")).font(.system(size: 14, weight: .semibold))
        }
        Text(L("打字不受影响。开启后才能用 AI 润色，App 里的键盘设置也会同步过来。", "Typing still works. Turn it on to use AI Polish and to sync keyboard settings from the app.", "入力はそのまま使えます。オンにすると AI 機能が使え、アプリのキーボード設定も同期されます。"))
            .font(.system(size: 13))
            .foregroundStyle(Brand.cardBody)
            .fixedSize(horizontal: false, vertical: true)
        // 没开完全访问时 iOS 不让键盘打开任何 App，只能把路径写出来。
        VStack(alignment: .leading, spacing: 3) {
            Text(L("在系统设置里开启", "Turn it on in Settings", "設定でオンにする")).font(.system(size: 11.5)).foregroundStyle(Brand.disabledText)
            settingsPath.font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.tagFill))
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Text(L("也可以打开飞地输入法 App 按指引开启", "Or open the Enclave app for a guide", "Enclave アプリの案内からも設定できます"))
                .font(.system(size: 12))
                .foregroundStyle(Brand.disabledText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            GateButton(title: L("知道了", "Got it", "OK"), primary: true) { model.dismissGate() }
        }
    }

    /// 仅基础功能时点 ✨ /「执行」（CP7）：不发请求，说明去 App 里同意。点卡片或开始打字就收起。
    private var privacy: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.deepPurple)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.returnSoftFill))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("用 AI 之前，先同意隐私政策", "Agree to the Privacy Policy to use AI", "AI を使う前にプライバシーポリシーに同意してください"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L("打开「飞地输入法」App，在「设置 › 隐私」里点「阅读并同意」。拼音输入不受影响。",
                       "Open the Enclave app and tap Read and Agree in Settings › Privacy. Pinyin input still works.",
                       "Enclave アプリの「設定 › プライバシー」で「読んで同意する」をタップしてください。ピンイン入力はそのまま使えます。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.cardBody)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.dismissGate() }
    }

    /// 还没填 API Key 时点 ✨ /「执行」（OB9）：不发请求，引导去 App 首页跟着教程设置。点卡片或开始打字就收起。
    private var noKey: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0xE9 / 255, blue: 0xA8 / 255))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient(
                    colors: [Color(red: 0x8A / 255, green: 0x7B / 255, blue: 1), Brand.purple],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("AI 要先填你自己的 API Key", "Add your own API key to use AI", "AI を使うには自分の API キーが必要です"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L("打开「飞地输入法」App，首页点「跟着教程设置」，大约 3 分钟。拼音输入不受影响。",
                       "Open the Enclave app and tap Follow the Guide on Home. About 3 minutes. Pinyin input still works.",
                       "Enclave アプリのホームで「ガイドで設定」をタップ。約 3 分です。ピンイン入力はそのまま使えます。"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.cardBody)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.dismissGate() }
    }

    /// 试用结束后今天的免费次数用完（K2）：打字照常，明天 0 点恢复。
    /// 审核 4.4.1：键盘里不提购买、不引导去买，只说明情况和在 App 哪里能看到详情。
    @ViewBuilder
    private var quotaUsed: some View {
        let uses = AIAccess.dailyFreeUses
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brand.deepPurple)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Brand.returnSoftFill))
            Text(L("今天的 \(uses) 次用完了", "You’ve used today’s \(uses) free uses", "今日の無料分（\(uses) 回）を使い切りました"))
                .font(.system(size: 14, weight: .semibold))
        }
        Text(L("试用结束后每天可以免费用 \(uses) 次，明天 0 点恢复。打字、拼音、常用词一直可以用，不受影响。",
               "After the trial you get \(uses) free uses a day, reset at midnight. Typing, pinyin and My Words keep working as usual.",
               "無料体験のあとも 1 日 \(uses) 回まで無料で使えます（0 時にリセット）。入力・ピンイン・ユーザ辞書はそのまま使えます。"))
            .font(.system(size: 13))
            .foregroundStyle(Brand.cardBody)
            .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 3) {
            Text(L("详细说明", "Details", "詳しくは")).font(.system(size: 11.5)).foregroundStyle(Brand.disabledText)
            (Text(L("打开飞地输入法", "Open Enclave", "Enclave を開く")).foregroundColor(Brand.cardBody)
                + Text(" › ").foregroundColor(Brand.pathSeparator)
                + Text(L("设置", "Settings", "設定")).foregroundColor(Brand.cardBody)
                + Text(" › ").foregroundColor(Brand.pathSeparator)
                + Text("AI").fontWeight(.semibold).foregroundColor(Brand.deepPurple))
                .font(.system(size: 13))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.tagFill))
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Spacer(minLength: 4)
            GateButton(title: L("知道了", "Got it", "OK"), primary: true) { model.dismissGate() }
        }
    }

    /// 设置 › 通用 › 键盘 › 键盘 › Enclave › 允许完全访问：分隔符浅灰，最后一项深紫加粗。
    private var settingsPath: Text {
        let steps = [L("设置", "Settings", "設定"), L("通用", "General", "一般"), L("键盘", "Keyboard", "キーボード"), L("键盘", "Keyboards", "キーボード"), "Enclave"]
        var text = Text("")
        for step in steps {
            text = text + Text(step).foregroundColor(Brand.cardBody) + Text(" > ").foregroundColor(Brand.pathSeparator)
        }
        return text + Text(L("允许完全访问", "Allow Full Access", "フルアクセスを許可")).fontWeight(.semibold).foregroundColor(Brand.deepPurple)
    }

    @ViewBuilder
    private func consent(_ endpoint: String, previous: String?) -> some View {
        HStack(spacing: 6) {
            SparkleMark(size: 14, color: Brand.tagSelectedText)
            Text(previous == nil ? L("润色前确认一下", "Before you polish", "整える前に確認") : L("接口地址变了，再确认一次", "The API URL changed. Please confirm again", "API の URL が変わりました。もう一度確認してください")).font(.system(size: 14, weight: .semibold))
        }
        HStack(spacing: 6) {
            Text(L("文字会发送到", "Text will be sent to", "文章の送信先")).font(.system(size: 13)).foregroundStyle(Brand.cardBody)
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 11, weight: .semibold))
                Text(endpoint).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).lineLimit(1)
            }
            .foregroundStyle(Brand.deepPurple)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(Brand.returnSoftFill))
        }
        if let previous {
            (Text(L("原来是 ", "Was ", "以前は ")) + Text(previous).strikethrough())
                .font(.system(size: 12))
                .foregroundStyle(Brand.panelLabel.opacity(0.7))
        }
        Text(L("只在你点「✨」或「执行」时发送：输入框里的文字（选中时只发选中的部分）和你写的要求。由这个接口处理后返回结果；无第三方中转，飞地输入法不保存你的文字。", "Sent only when you tap ✨ or Run: the text in the field (just the selection, if any) and your prompt. This API processes it and returns the result. No third-party relay; Enclave doesn't keep your text.", "「✨」か「実行」をタップしたときだけ、入力欄の文章（選択時はその部分だけ）と指示を送ります。この API が処理して結果を返します。第三者の中継はなく、Enclave は文章を保存しません。"))
            .font(.system(size: 12))
            .foregroundStyle(Brand.cardNote)
            .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            Button { model.openContainingApp("enclave://privacy-policy") } label: {
                Text(L("隐私政策", "Privacy Policy", "プライバシーポリシー")).font(.system(size: 12)).foregroundStyle(Brand.tagSelectedText)
            }
            .buttonStyle(.plain)
            Spacer()
            GateButton(title: L("取消", "Cancel", "キャンセル"), primary: false) { model.dismissGate() }
            GateButton(title: L("同意并润色", "Agree and Polish", "同意して整える"), primary: true) { model.acceptConsent() }
        }
    }
}

/// 试用最后 3 天 AI 栏上方的白条（K3）：一句提示 + ✕，每天最多出现一次。
struct TrialReminderStrip: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.deepPurple)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.cardBody)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button { model.dismissTrialReminder() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.disabledText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("关闭", "Close", "閉じる"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.panelFill))
    }

    private var text: String {
        let days: Int
        if case .trial(let left, _) = AIAccess.current { days = left } else { days = 0 }
        let uses = AIAccess.dailyFreeUses
        return L("AI 试用还剩 \(days) 天，之后每天免费 \(uses) 次", "\(days) days left in your trial, then \(uses) free uses a day",
                 "無料体験は残り \(days) 日。その後は 1 日 \(uses) 回まで無料")
    }
}

/// 提示卡右下的按钮：高 30、圆角 15，主按钮用润色的蓝紫渐变。
struct GateButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary ? Color.white : Brand.cardBody)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background {
                    if primary {
                        Capsule().fill(LinearGradient(colors: [Brand.gradient[0], Brand.gradient[1]],
                                                      startPoint: .leading, endPoint: .trailing))
                    } else {
                        Capsule().fill(Brand.tagFill)
                    }
                }
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 结果卡片里点到第几个字，以及修改时的光标图形。和卡片文字一样用 15pt 系统字体排版。
enum CardTextHit {
    /// 2pt 宽的光标，模板图，颜色跟着文字前景色。
    static let caret: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 18)).image { context in
        UIColor.black.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 18))
    }.withRenderingMode(.alwaysTemplate)

    static func index(at point: CGPoint, in text: String, width: CGFloat) -> Int {
        guard !text.isEmpty, width > 0 else { return 0 }
        let storage = NSTextStorage(string: text, attributes: [.font: UIFont.systemFont(ofSize: 15)])
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        if point.y > layout.usedRect(for: container).maxY { return text.count }
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        var utf16 = layout.characterIndexForGlyph(at: glyph)
        if fraction > 0.5 { utf16 += 1 }
        // UTF-16 位置换成第几个字（表情等占两个单位）。
        var count = 0
        var offset = 0
        for character in text {
            if offset >= utf16 { break }
            offset += character.utf16.count
            count += 1
        }
        return count
    }
}

// MARK: - 结果卡片

/// 结果卡片：提示、出错、首次使用清单也都显示在这个位置。
/// 有结果时右边一列是 ✦ 状态、复制、展开，多个版本时再加一列 ▲ 2/3 ▼。
struct ResultCard: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// 文字区宽度，点文字时换算成第几个字。
    @State private var textWidth: CGFloat = 200

    private enum Look { case checklist, error(String), hint(String?), running, fresh, faded, editing, search(KeyboardModel.SearchPrompt), partial }

    private var look: Look {
        if model.aiBlocked { return .checklist }
        if model.target == .card { return .editing }
        if model.partialResult != nil, !model.isRunning { return .partial }
        if let error = model.errorMessage { return .error(error) }
        if let prompt = model.searchPrompt { return .search(prompt) }
        if model.isRunning { return .running }
        if model.session?.current != nil {
            return model.resultUse != nil || model.resultStale ? .faded : .fresh
        }
        return .hint(model.notice)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    /// 只在生成中播放；App 里关了动画或系统开了「减弱动态效果」就不播。
    private var animating: Bool { model.isRunning && model.searchPrompt == nil && model.settings.polishAnimation && !reduceMotion }

    var body: some View {
        let look = look
        VStack(spacing: 0) {
            content(look)
            // 下半格是识意框（MG3）；自由编辑时整块变成编辑框。
            if model.target != .card {
                // 激活（打字进识意框）：顶上 1pt 紫线；未激活：0.5pt 细线，下半格浅灰底（FC1–FC4）。
                let active = askActive
                Rectangle().fill(active ? Brand.askActiveLine : Brand.blockHair).frame(height: active ? 1 : 0.5)
                lowerHalf.frame(height: KeyboardMetrics.askBoxHeight - (active ? 1 : 0.5))
            }
        }
        .background {
            // 修改中：外面一圈 4pt 淡紫光。
            if case .editing = look { shape.inset(by: -4).fill(editStroke.opacity(0.15)) }
            shape.fill(KeyStyle.charKey)
            if model.target != .card, !askActive {
                Brand.askInactiveFill
                    .frame(height: KeyboardMetrics.askBoxHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(shape)
            }
            if case .error = look, model.failure == nil { shape.fill(Color.red.opacity(0.07)) }
        }
        .overlay {
            if animating { SweepBand().clipShape(shape).allowsHitTesting(false) }
        }
        .overlay { border(look).allowsHitTesting(false) }
    }

    /// 识意框激活：打字进识意框。选风格改成下拉框（KB2）后下半格一直是识意框。
    private var askActive: Bool { model.target == .instruction }

    private var lowerHalf: some View {
        AskField(model: model)
    }

    /// 上半格：回答卡。
    private func content(_ look: Look) -> some View {
        Group {
            switch look {
            case .checklist: checklist
            case .error(let message): errorView(message)
            case .partial: partialView
            case .hint(let notice): hintView(notice)
            case .running, .fresh, .faded: resultView(faded: { if case .faded = look { return true } else { return false } }())
            case .editing: editView
            case .search(let prompt): searchPromptView(prompt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if let note = model.replaceNote {
                Text(note == .partial
                     ? L("只替换了读到的一段，整段请先全选", "Only the part read was replaced. Select all for the whole text", "読んだ部分だけ置き換えました。全体は全選択から")
                     : L("输入框改过了，没有替换，可以改用插入", "The text changed, so nothing was replaced. Try Insert instead", "入力欄が変わったため置き換えていません。挿入をお使いください"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.75)))
                    .padding(6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if model.copied {
                Label(L("已复制", "Copied", "コピーしました"), systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Brand.purple))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: 结果

    /// 自由编辑框描边：当前模式的颜色（问答天蓝，其余紫）。
    private var editStroke: Color { model.session?.currentIsAnswer == true ? Brand.answerBorder : Brand.tagSelectedText }

    /// 正文左边距 14（AK2：左边模式格去掉，正文往左占满）。
    private var textLeading: CGFloat { 14 }

    private func resultView(faded: Bool) -> some View {
        HStack(alignment: .top, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
            // 出结果后正文上面一行标题（AK2）：改写「✨ AI 改写 · 正式」主色，问答「[问答图标] AI 回答 · 直击要害」蓝色 + 联网标签。
            if !model.isRunning, let session = model.session, session.current != nil {
                ResultHeader(answer: session.currentIsAnswer,
                             style: session.versionInfo?[String(session.currentIndex)]?.style,
                             searched: session.currentSearchedBy != nil)
                    .padding(.leading, textLeading)
                    .padding(.top, 8)
                    .opacity(faded ? 0.6 : 1)
            }
            // 生成中第一行是流光小字「AI 正在改写… / 正在回答…」（QA10），出结果后这行字消失，
            // 「AI 生成」标签（CP8）放在正文第一行开头，只在界面上标，不往正文里插任何标记。
            if model.isRunning {
                HStack(spacing: 6) {
                    RunningLabel(text: runningTitle, color: runningColor, animating: animating)
                    // 8 秒还没出第一个字（ER4）：后面加灰字「模型响应较慢」，右边小「取消」。
                    if model.responseSlow {
                        Text(L("模型响应较慢", "Slow to respond", "応答が遅れています"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button { model.stop() } label: {
                            Text(L("取消", "Cancel", "キャンセル"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 10)
                                .frame(height: 22)
                                .background(Capsule().fill(Brand.searchDeclineFill))
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
                .padding(.leading, textLeading)
                .padding(.top, 8)
            }
            resultText(faded: faded)
                .padding(.leading, textLeading)
                .padding(.top, model.isRunning || model.session?.current != nil ? 4 : 8)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                // 文字区上下滑留给滚动（展开、收起都一样），翻版本在右边的 ▲▼ 上滑；只有收起时生成中整块滑动翻版本。长按复制。
                // 滑动放在主手势、长按放在同时识别，onLongPressGesture 会把拖动吞掉。
                .gesture(swipeToTurn, including: model.cardTall || !model.isRunning ? .subviews : .all)
                // 长按打开分词面板（BB1），复制全文用右边的小复制按钮。
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in model.openWordPanel() })
                // 连点 3 下进自由编辑（FE1），光标放在第三下点的位置；点一下、两下都不进。
                .simultaneousGesture(SpatialTapGesture(count: 3).onEnded { value in
                    guard model.hasResult, let text = model.session?.current else { return }
                    // 减掉文字区的内边距；展开卡片滚动过时按未滚动估算，进入后可以再点一次调整。
                    let point = CGPoint(x: value.location.x - textLeading, y: value.location.y - 4)
                    model.beginFreeEdit(caret: CardTextHit.index(at: point, in: text, width: textWidth))
                })
                // VoiceOver 用不了滑动、长按、连点三下：上下轻扫（可调整）翻版本，「操作」里有分词和修改。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(resultAccessibilityLabel)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: turn(1)
                    case .decrement: turn(-1)
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: L("分词", "Split into words", "単語に分ける")) { model.openWordPanel() }
                .accessibilityAction(named: L("修改", "Edit", "編集")) {
                    if model.hasResult, let text = model.session?.current { model.beginFreeEdit(caret: text.count) }
                }
            }
            iconColumn(faded: faded)
                .padding(.vertical, 5)
            if let session = model.session, session.versions.count > 1, !model.isRunning {
                pager(index: session.currentIndex, count: session.versions.count)
                    .coachTarget(.versions, active: model.coachDisplay?.target == .versions)
                    .contentShape(Rectangle())
                    // 优先于 ▲▼ 按钮：手指在按钮里滑一下松开，按钮也会算一次点击，就翻了两页。
                    .highPriorityGesture(swipeToTurn)
            }
        }
        .padding(.trailing, 4)
    }

    // MARK: 要联网时（WB1–WB3）

    /// 和结果卡一样大的选择卡：左边 🌐 标题 + 灰字说明，右边两颗按钮；没有右边修改 / 复制 / 展开三个图标。
    private func searchPromptView(_ prompt: KeyboardModel.SearchPrompt) -> some View {
        let name = prompt.provider.name
        let firstTime = !prompt.disabled && model.settings.webSearchMode == .on
        let title: String, detail: String, decline: String, accept: String
        if prompt.disabled {
            title = L("要联网才答得准", "Needs the web to answer well", "ウェブ検索が必要です")
            detail = L("联网调用已禁止", "Web search is off", "ウェブ検索はオフ")
            decline = L("直接回答", "Answer anyway", "そのまま回答")
            accept = L("去开启", "Turn on", "オンにする")
        } else if firstTime {
            title = L("第一次用 \(name) 联网", "Use \(name) web search?", "\(name) のウェブ検索を使いますか？")
            detail = L("约 ¥0.01 一次 · 允许后不再问", "First time only · won't ask again once allowed", "初回のみ確認 · 許可すると次から聞きません")
            decline = L("拒绝", "Don't allow", "許可しない")
            accept = L("允许", "Allow", "許可")
        } else {
            title = L("要联网搜索吗？", "Search the web?", "ウェブで検索しますか？")
            let modelName = model.settings.forAnswers.searchModelLabel
            detail = L("调用 \(modelName) 联网搜索 · 约 ¥0.01", "Searches with \(modelName)", "\(modelName) でウェブ検索")
            decline = L("拒绝", "Don't allow", "許可しない")
            accept = L("允许", "Allow", "許可")
        }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    // 禁止时地球上加一道斜线（WB3）。
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .semibold))
                        .overlay {
                            if prompt.disabled {
                                Capsule().frame(width: 1.8, height: 19).rotationEffect(.degrees(-45))
                            }
                        }
                        .foregroundStyle(Brand.answerText)
                    // 标题不截断（太长就缩小一点），副标题放不下截断加省略号。
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .layoutPriority(1)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Button { model.resolveSearchPrompt(allow: false) } label: {
                Text(decline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.searchDeclineFill))
            }
            .buttonStyle(.plain)
            Button {
                if prompt.disabled { model.openContainingApp("enclave://api-answer") } else { model.resolveSearchPrompt(allow: true) }
            } label: {
                Text(accept)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: Brand.insertGradient, startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningTitle: String {
        guard model.askRunning else { return L("AI 正在润色…", "AI is polishing…", "AI が整えています…") }
        if model.askSearching {
            let name = model.settings.answerSearch?.name ?? ""
            return L("正在用 \(name) 联网搜索…", "Searching the web with \(name)…", "\(name) でウェブを検索しています…")
        }
        switch model.askKind {
        case .answer: return L("AI 正在回答…", "AI is answering…", "AI が回答しています…")
        case .rewrite: return L("AI 正在改写…", "AI is rewriting…", "AI が書き換えています…")
        case nil: return L("AI 正在理解…", "AI is reading…", "AI が考えています…")
        }
    }

    private var runningColor: Color { model.askKind == .answer ? Brand.answerText : Brand.purpleText }

    @ViewBuilder
    private func resultText(faded: Bool) -> some View {
        // 「AI 生成」小标签不再放正文开头：出结果后正文上面有标题行（ResultHeader）。
        let text = Text(model.displayText) + Text(model.isRunning ? "▍" : "").foregroundColor(runningColor)
        Group {
            if model.isRunning && model.displayText.isEmpty {
                // 还没出字：灰条占位，两行高的卡片里一条，展开时两条。
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Brand.skeleton).frame(height: 12).frame(maxWidth: .infinity)
                        .padding(.trailing, 30)
                    if model.cardTall {
                        Capsule().fill(Brand.skeleton).frame(height: 12).frame(maxWidth: .infinity)
                            .padding(.trailing, 110)
                    }
                }
                .padding(.top, 6)
            } else if model.cardTall || !model.isRunning {
                // 展开的四行和收起的两行都能上下滚着看全文（收起时翻版本靠右边的 ▲▼）。
                ScrollView {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                }
                .hidingScrollEdgeEffect()
            } else {
                // 两行高、生成中：第一行是「AI 正在…」，正文只露最新的一行。
                text.lineLimit(1).truncationMode(.head)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(faded ? Color.secondary : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { textWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { textWidth = $0 }
        })
    }

    // MARK: 修改中

    /// 卡片里的文字可以直接改：光标前、正在拼的拼音（紫色下划线）、闪烁的光标、光标后。
    private var editView: some View {
        HStack(alignment: .top, spacing: 2) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        editText
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GeometryReader { proxy in
                                Color.clear.onAppear { textWidth = proxy.size.width }
                            })
                            .contentShape(Rectangle())
                            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                                model.beginCardEdit(caret: CardTextHit.index(at: value.location, in: model.cardDraft,
                                                                             width: textWidth))
                            })
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .hidingScrollEdgeEffect()
                .onChange(of: model.cardDraft) { _ in
                    // 在末尾打字时跟着滚到最下面。
                    if model.cardCaret >= model.cardDraft.count - 1 { reader.scrollTo("end", anchor: .bottom) }
                }
                .onAppear {
                    if model.cardCaret >= model.cardDraft.count { reader.scrollTo("end", anchor: .bottom) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var editText: some View {
        let draft = model.cardDraft
        let split = draft.index(draft.startIndex, offsetBy: min(model.cardCaret, draft.count))
        return TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 || model.isComposing
            (Text(draft[..<split])
                + Text(model.composition).underline(color: Brand.tagSelectedText)
                + Text(Image(uiImage: CardTextHit.caret)).foregroundColor(visible ? Brand.tagSelectedText : .clear)
                    .baselineOffset(-3)
                + Text(draft[split...]))
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
        }
    }

    /// ✦ 状态、复制、展开：15pt 线性图标，24×18 点击区，上中下对齐。
    private func iconColumn(faded: Bool) -> some View {
        VStack(spacing: 0) {
            if model.isRunning {
                SparkleMark(size: 15, color: Brand.purpleText, animating: animating)
                    .frame(width: 24, height: 18)
                    .background(Capsule().fill(Brand.softFill))
                Spacer(minLength: 0)
            }
            // 编辑笔去掉了（FE1）：图标列只剩复制、展开，上下两端对齐；连点 3 下正文进自由编辑。
            iconButton(model.copied ? "doc.on.doc.fill" : "doc.on.doc", tint: model.copied ? Brand.purpleText : .secondary) {
                model.copy()
            }
            .disabled(!model.hasResult)
            .accessibilityLabel(model.copied ? L("已复制", "Copied", "コピーしました") : L("复制结果", "Copy result", "結果をコピー"))
            Spacer(minLength: 0)
            iconButton(model.cardExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       tint: .secondary) {
                withAnimation(.easeOut(duration: 0.2)) { model.cardExpanded.toggle() }
            }
            .accessibilityLabel(model.cardExpanded ? L("缩小结果卡", "Shrink result card", "結果カードを縮小") : L("放大结果卡", "Enlarge result card", "結果カードを拡大"))
            .accessibilityHidden(model.landscape)
            // 横屏结果卡固定 2 行，不能展开。
            .opacity(model.landscape ? 0 : 1)
            // 分词面板开着时结果卡固定 2 行。
            .disabled(model.landscape || model.keysPanel == .words)
        }
        .frame(width: 24)
    }

    private func iconButton(_ systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 结果正文读成「AI 生成的结果，第 2 版，共 3 版：正文」。
    private var resultAccessibilityLabel: String {
        guard let session = model.session, let text = session.current, !model.isRunning else {
            return model.isRunning ? runningTitle : ""
        }
        let head = session.currentIsAnswer ? L("AI 的回答", "AI answer", "AI の回答") : L("AI 生成的结果", "AI result", "AI の結果")
        let page = session.versions.count > 1
            ? L("，第 \(session.currentIndex + 1) 版，共 \(session.versions.count) 版", ", version \(session.currentIndex + 1) of \(session.versions.count)",
                "、\(session.versions.count) 件中 \(session.currentIndex + 1) 件目")
            : ""
        return head + page + "：" + text
    }

    /// 多个版本：▲ 2/3 ▼。
    private func pager(index: Int, count: Int) -> some View {
        VStack(spacing: 0) {
            Button { turn(-1) } label: {
                Image(systemName: "chevron.up").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel(L("上一版", "Previous version", "前のバージョン"))
            .disabled(index == 0)
            pageNumber(index: index, count: count)
            if model.session?.currentIsEdited == true {
                Text(L("已改", "Edited", "編集済み")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Brand.deepPurple)
            }
            Button { turn(1) } label: {
                Image(systemName: "chevron.down").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel(L("下一版", "Next version", "次のバージョン"))
            .disabled(index >= count - 1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.secondary)
        .buttonStyle(.plain)
        .frame(width: 22)
        .padding(.vertical, 2)
    }

    /// 页码（PG1）：总数 1–9 横排「2/2」；总数 ≥10 上下两行，当前页 / 12 宽细线 / 总数，超过 99 写 99。
    /// 按总数切换版式，从第 9 翻到第 10 条时不跳。
    @ViewBuilder
    private func pageNumber(index: Int, count: Int) -> some View {
        if count < 10 {
            Text("\(index + 1)/\(count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.primary)
        } else {
            VStack(spacing: 1) {
                Text("\(min(index + 1, 99))").foregroundStyle(Color.primary).frame(height: 11)
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 12, height: 1)
                Text("\(min(count, 99))").foregroundStyle(Color.secondary).frame(height: 11)
            }
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(index + 1)/\(count)")
        }
    }

    /// 上滑看下一版，下滑看上一版。
    private var swipeToTurn: some Gesture {
        DragGesture(minimumDistance: 12).onEnded { value in
            // 快速轻扫移动距离短，用预测的终点算。
            let dy = abs(value.predictedEndTranslation.height) > abs(value.translation.height)
                ? value.predictedEndTranslation.height : value.translation.height
            guard abs(dy) > abs(value.translation.width) else { return }
            if dy < -20 { turn(1) } else if dy > 20 { turn(-1) }
        }
    }

    private func turn(_ offset: Int) {
        model.keyFeedback(for: .space)
        withAnimation(.easeOut(duration: 0.2)) { model.showVersion(offset: offset) }
    }

    // MARK: 边框

    @ViewBuilder
    private func border(_ look: Look) -> some View {
        switch look {
        case .running:
            if animating {
                FlowingBorder(shape: shape, colors: model.askKind == .answer ? Brand.answerRing : Brand.gradient)
            } else {
                shape.strokeBorder((model.askKind == .answer ? Brand.answerBorder : Brand.purpleText).opacity(0.5), lineWidth: 1)
            }
        case .fresh:
            // 整块描边跟着结果：问答天蓝，改写（润色也算）紫（MG3、MG4）。
            shape.strokeBorder(resultRing, lineWidth: 1.5)
        case .faded:
            shape.strokeBorder(resultRing.opacity(0.45), lineWidth: 1.5)
        case .error:
            if model.failure != nil {
                shape.strokeBorder(Brand.rowStroke, lineWidth: 1.5)
            } else {
                shape.strokeBorder(Color.red.opacity(0.35), lineWidth: 0.8)
            }
        case .partial:
            shape.strokeBorder(Brand.rowStroke, lineWidth: 1.5)
        case .editing:
            shape.strokeBorder(editStroke, lineWidth: 2)
        case .search:
            shape.strokeBorder(Brand.answerBorder, lineWidth: 1.5)
        case .checklist, .hint:
            shape.strokeBorder(Brand.rewriteRing, lineWidth: 1.5)
        }
    }

    private var resultRing: Color { model.session?.currentIsAnswer == true ? Brand.answerBorder : Brand.rewriteRing }

    // MARK: 提示、出错、检查清单

    private func hintView(_ notice: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let notice {
                Text(notice).font(.system(size: 13)).foregroundStyle(Color.primary)
            } else {
                // 还没结果（MG2）：灰字说明，结果出来后整块高度不变。
                Text(L("点润色键，按当前风格改输入框里的话；点「问答」，回答下面写的问题。结果出现在这里",
                     "Tap the polish key to edit your text in the current style; tap Ask to answer the question below. The result shows here",
                     "整えるキーで入力欄の文章を今のスタイルで直し、「質問」で下に書いた質問に答えます。結果はここに表示されます"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Brand.askPlaceholder)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: 出错（ER0–ER5）

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        if let failure = model.failure {
            failureCard(failure)
        } else {
            plainErrorView(message)
        }
    }

    /// 和结果卡一样大的出错卡：⚠ 标题 + 灰字说明「· 详情」，右边「去设置」「重试」。
    /// 点「· 详情」卡片展开到 4 行高，下面灰底框里是服务商原文（11pt 等宽，可长按复制）。
    private func failureCard(_ failure: LLMFailure) -> some View {
        let provider = model.failureProvider
        let header = HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                    Text(failure.title(provider: provider))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if !model.failureDetailShown {
                    (Text(failure.note(provider: provider))
                     + Text(model.failureDetail == nil ? "" : L(" · 详情", " · Details", "・詳細")))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .onTapGesture {
                            guard model.failureDetail != nil else { return }
                            withAnimation(.easeOut(duration: 0.2)) { model.failureDetailShown = true }
                        }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            if failure.needsSettings {
                cardButton(L("去设置", "Settings", "設定"), primary: false) { model.openAPISettings() }
            }
            cardButton(L("重试", "Retry", "再試行"), primary: true) { model.retryLastRun() }
        }
        return VStack(alignment: .leading, spacing: 8) {
            header
            if model.failureDetailShown, let detail = model.failureDetail {
                ScrollView {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.aiTagFill))
                .contextMenu {
                    Button(L("复制", "Copy", "コピー")) { UIPasteboard.general.string = detail }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.failureDetailShown ? .topLeading : .leading)
    }

    /// 出了一半断了（ER3）：第一行保留已出的字（带模式标签），第二行橙字 ⚠「没写完，连接断了」+ 右边小「重试」。
    private var partialView: some View {
        let partial = model.partialResult
        return HStack(alignment: .top, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if partial?.answer == nil {
                            Text(Image(uiImage: AIGeneratedTag.image(dark: colorScheme == .dark))) + Text(partial?.text ?? "")
                        } else {
                            Text(partial?.text ?? "")
                        }
                    }
                    .font(.system(size: 15))
                    .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold))
                        Text(L("没写完，连接断了", "Cut off before finishing", "途中で接続が切れました"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button { model.retryLastRun() } label: {
                            Text(L("重试", "Retry", "再試行"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 24)
                                .background(Capsule().fill(LinearGradient(colors: Brand.insertGradient, startPoint: .topLeading, endPoint: .bottomTrailing)))
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                    .foregroundStyle(Brand.warning)
                }
            }
            .padding(.leading, partial?.answer == nil ? 10 : 6)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            iconColumn(faded: false)
                .padding(.vertical, 5)
        }
        .padding(.trailing, 4)
    }

    /// 出错卡右边的按钮：高 32、圆角 9、14pt semibold；主按钮紫色渐变白字，次按钮灰底。
    private func cardButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primary ? Color.white : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(primary ? AnyShapeStyle(LinearGradient(colors: Brand.insertGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Brand.searchDeclineFill)))
        }
        .buttonStyle(.plain)
    }

    private func plainErrorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(L("出错了", "Something went wrong", "エラーが発生しました"), systemImage: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// 首次使用：没开完全访问或没配置 API 时，卡片位置列出还差的几步，✨ 置灰，打字不受影响。
    private var checklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                SparkleMark(size: 12, color: Brand.purpleText)
                Text(L("还差几步就能用 AI，打字不受影响", "A few steps to use AI. Typing works now", "あと数ステップで AI が使えます。入力はすぐに使えます")).font(.system(size: 13, weight: .semibold))
            }
            checkRow(1, L("打开「允许完全访问」", "Turn on Allow Full Access", "「フルアクセスを許可」をオン"), done: model.hasFullAccess)
            HStack {
                checkRow(2, L("配置模型 API", "Set up a model API", "モデル API を設定"), done: model.settings.isConfigured)
                Spacer(minLength: 0)
                if !model.settings.isConfigured && SharedStorage.usesClipboardConfig {
                    Button { model.importConfigFromPasteboard() } label: {
                        Text(L("从剪贴板导入", "Import from clipboard", "クリップボードから読み込む"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.purpleText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(Brand.softFill))
                    }
                    .buttonStyle(KeyPressStyle())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func checkRow(_ number: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.green)
            } else {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Brand.purple))
            }
            Text(title).font(.system(size: 13)).foregroundStyle(done ? Color.secondary : Color.primary)
        }
    }
}

// MARK: - 润色动画（方案 A）

/// 生成中的边框：品牌渐变沿边框转一圈，周期 1.6 秒；外圈淡紫光晕轻微明暗。
struct FlowingBorder: View {
    var shape: RoundedRectangle
    var lineWidth: CGFloat = 1.6
    /// 问答时换成天蓝一圈。
    var colors: [Color] = Brand.gradient

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let wave = (1 - cos(2 * .pi * phase)) / 2
            ZStack {
                shape.stroke(colors[1].opacity(0.18 + 0.14 * wave), lineWidth: 4).blur(radius: 3)
                shape.strokeBorder(AngularGradient(colors: colors + [colors[0]], center: .center,
                                                   angle: .degrees(phase * 360)),
                                   lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 卡片里的扫光：约 300pt 宽的斜向光带从左往右匀速扫过，中间最深（#7C3AED 16%），一趟 1.6 秒，和边框同步。
struct SweepBand: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let band: CGFloat = 300
                LinearGradient(colors: [Brand.violet.opacity(0), Brand.violet.opacity(0.16), Brand.violet.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: band, height: geo.size.height * 2)
                    .rotationEffect(.degrees(18))
                    .offset(x: -band + (geo.size.width + band) * phase, y: -geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// iOS 26 会在滚动区顶部加一层渐变模糊，盖住预览区的第一行，这里关掉它。
    @ViewBuilder
    func hidingScrollEdgeEffect() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
        #else
        self
        #endif
    }
}


/// 结果正文第一行开头的「AI 生成」标签（CP8，TG3、TG4）：高 15、圆角 4、左右内边距 5，字 10pt semibold，灰底灰字，没有星星。
/// Text 里只能嵌图片，嵌不了视图，所以画成图片拼进正文。
enum AIGeneratedTag {
    private static var images: [String: UIImage] = [:]

    /// 对齐（TG4）：标签上下中线 = 第一行汉字的中线 = 基线 + 正文字体 capHeight / 2。
    /// 和 NSTextAttachment 的 bounds.origin.y = capHeight/2 − 15/2 一样：用图片自己的基线（withBaselineOffset），
    /// 让标签往基线下面伸约 2.2pt，落在正文的下行空间里，第一行不会被撑高（不用 baselineOffset 往上抬）。
    /// 图片右边多画 6pt 透明，就是标签和正文的间距。
    static func image(dark: Bool, bodySize: CGFloat = 15) -> UIImage {
        let label = L("AI 生成", "AI-generated", "AI 生成")
        let key = "\(dark)\(label)\(bodySize)"
        if let image = images[key] { return image }
        let fill = dark ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
            : UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
        let ink = dark ? UIColor(red: 0xAE / 255, green: 0xAE / 255, blue: 0xB2 / 255, alpha: 1)
            : UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x73 / 255, alpha: 1)
        let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let textSize = (label as NSString).size(withAttributes: [.font: font])
        let height: CGFloat = 15
        let tagWidth = ceil(5 + textSize.width + 5)
        let size = CGSize(width: tagWidth + 6, height: height)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            fill.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: tagWidth, height: height), cornerRadius: 4).fill()
            (label as NSString).draw(at: CGPoint(x: 5, y: (height - textSize.height) / 2),
                                     withAttributes: [.font: font, .foregroundColor: ink])
        }
        let capHeight = UIFont.systemFont(ofSize: bodySize).capHeight
        let below = max(0, height / 2 - capHeight / 2)
        let image = rendered.withBaselineOffset(fromBottom: below)
        images[key] = image
        return image
    }
}

/// 进自由编辑时结果卡上方浮出的深色小胶囊（FE2）：32 高、圆角 16，1.5 秒后淡掉。
struct FreeEditToast: View {
    var body: some View {
        Label(L("已开启自由编辑", "Free editing on", "自由編集をオン"), systemImage: "pencil")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Brand.candidateMenuText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(Brand.candidateMenuFill))
            .shadow(color: .black.opacity(0.22), radius: 9, y: 6)
    }
}

/// 回答卡正文上面一行标题（AK2，取代左边的模式格）：13pt 粗体。
/// 改写「✨ AI 改写 · 正式」主色；问答「[问答图标] AI 回答 · 直击要害」蓝色，后面跟联网标签（只是状态，不能点）。
/// 手改的那版没有风格名，只写「AI 改写」。
struct ResultHeader: View {
    var answer: Bool
    var style: String?
    var searched: Bool

    var body: some View {
        let color = answer ? Brand.answerText : Brand.purpleText
        let head = answer ? L("AI 回答", "AI answer", "AI の回答") : L("AI 改写", "AI rewrite", "AI 書き換え")
        HStack(spacing: 0) {
            Group {
                if answer {
                    AskIcon(size: 15)
                } else {
                    PolishStars(size: 15, running: false, glowing: false, doneAt: nil, tint: color)
                        .frame(width: 15, height: 15)
                }
            }
            .padding(.trailing, 4)
            Text(style.map { "\(head) · \($0)" } ?? head)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
            if answer {
                WebTag(on: searched).padding(.leading, 6).fixedSize()
            }
        }
        .foregroundStyle(color)
        .frame(height: 18)
        .accessibilityElement(children: .combine)
    }
}

/// 问答标题后面的联网标签：高 18、圆角 9、11pt 600、前面 11pt 地球线框。
/// 已联网浅蓝底蓝字（深色 #1d2a44 / #5EA0FF），未联网浅灰底灰字（深色 #2c2c30 / #98989d）。
struct WebTag: View {
    var on: Bool

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
    static let onFill = dynamic(0xE3EEFE, 0x1D2A44)
    static let onText = dynamic(0x2F7BF6, 0x5EA0FF)
    static let offFill = dynamic(0xEEEEF1, 0x2C2C30)
    static let offText = dynamic(0x8A8A8E, 0x98989D)

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "globe").font(.system(size: 11, weight: .regular))
            Text(on ? L("已联网", "Web", "ウェブ検索済み") : L("未联网", "No web", "ウェブなし"))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(on ? Self.onText : Self.offText)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(on ? Self.onFill : Self.offFill))
    }
}

/// 生成中卡片第一行的流光小字（QA10）：星星 +「AI 正在改写… / 正在回答…」，一道亮光从左扫到右。
struct RunningLabel: View {
    var text: String
    var color: Color
    var animating: Bool

    var body: some View {
        let label = HStack(spacing: 5) {
            Image(systemName: "sparkle").font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .frame(height: 18)
        if animating {
            label.overlay {
                GeometryReader { geo in
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 40)
                            .offset(x: -40 + (geo.size.width + 40) * phase)
                    }
                }
                .mask(label)
                .allowsHitTesting(false)
            }
        } else {
            label
        }
    }
}

/// 没字时点 ✨、快速模式失败时被点那颗键的动效（NC2、对齐清单第 61 条）：按下缩到 96%，60 ms 后回弹，同时左右 ±3pt 晃两下共 240 ms。减弱动态效果时不动。
struct EmptyTapShake: ViewModifier {
    var trigger: Int
    @State private var scale: CGFloat = 1
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(x: offset)
            .onChange(of: trigger) { _ in
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.06)) { scale = 0.96 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { scale = 1 }
                }
                // 240 ms 里 +3、−3、+3、−3、0 五段，每段 48 ms。
                for (k, x) in [3, -3, 3, -3, 0].enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 + 0.048 * Double(k)) {
                        withAnimation(.easeInOut(duration: 0.048)) { offset = CGFloat(x) }
                    }
                }
            }
    }
}

