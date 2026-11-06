import SwiftUI

// MARK: - ^^ 键变「帮回」（T16，HB9）

/// 有新复制的内容时九宫格 ^^ 键的样子：绿色两段式。上段 15 高「↑ ^^ 颜文字」（黑 16% 叠色 + 下方 1pt 白 35% 分隔线），
/// 下段 logo 14pt +「帮回」13.5pt 粗白字，「回」右上角红点。
/// 生成中「帮回」两个字换成胶囊停止图标、logo 动、周围闪 7 颗白色小星、键下绿色柔投影；写好时白色对勾一笔画出（600ms）。
struct HelpReplyKey: View {
    let look: HelpKeyLook
    var pressed = false
    var crossShowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let topHeight: CGFloat = 15
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8.5, style: .continuous) }
    private var motion: Bool { look.moving && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                shape.fill(HelpStyle.gradient)
                VStack(spacing: 0) {
                    Text("↑ ^^ " + L("颜文字", "Kaomoji", "顔文字"))
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.topHeight)
                        .background(Color.black.opacity(0.16))
                    Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
                    lower
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .foregroundStyle(.white)
            }
            .clipShape(shape)
            .overlay {
                if look.running && motion {
                    KeySparkles(running: true, successAt: nil, textX: geo.size.width * 0.18,
                                textWidth: geo.size.width * 0.64, seed: 3, whiteOnly: true)
                        .padding(.top, Self.topHeight)
                }
            }
            .shadow(color: look.running ? HelpStyle.green.opacity(0.5) : .clear, radius: 4, y: 3)
            .opacity(pressed && !crossShowing ? 0.8 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(look.running ? L("停止帮回", "Stop Help Reply", "返信アシストを停止") : L("帮回", "Help Reply", "返信アシスト"))
        .accessibilityHint(L("点一下帮你写回复；上滑打开颜文字。", "Tap to draft replies; swipe up for kaomoji.",
                             "タップで返信を作成、上スワイプで顔文字。"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var lower: some View {
        HStack(spacing: 3) {
            HelpIcon(size: 14, running: look.running && motion)
            ZStack {
                if look.running {
                    AIStopIcon(running: true, moving: motion, tint: .white)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if let success = look.successAt {
                    SuccessDraw(since: success)
                } else {
                    label
                }
            }
            .animation(.easeOut(duration: 0.2), value: look.running)
        }
        .padding(.horizontal, 2)
    }

    private var label: some View {
        Text(L("帮回", "Reply", "返信"))
            .font(.system(size: 13.5, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .overlay(alignment: .topTrailing) {
                // 「回」右上角 3pt 红点，1pt 白边，只偏出字一点点。
                Circle().fill(HelpStyle.dot)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                    .offset(x: 3.5, y: -2.5)
            }
    }

    /// 写好：白色对勾 600ms 一笔画出，停住到 ^^ 淡回。
    private struct SuccessDraw: View {
        let since: Date

        var body: some View {
            TimelineView(.animation(minimumInterval: nil, paused: Date().timeIntervalSince(since) > 0.7)) { context in
                let p = min(max(context.date.timeIntervalSince(since) / 0.6, 0), 1)
                SuccessCheck()
                    .trim(from: 0, to: CGFloat(KeySuccessFrame.easeInOut(p)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 15)
            }
            .frame(width: 26, height: 17)
        }
    }
}

/// 按住帮回键弹出的「^^ 颜文字」格（盖住 ⌫），和普通键一样大；手指进格变 #5B4BE8 + 2pt 白描边 + 放大 1.06。
/// 帮回键本身盖在原来的键帽上，没滑开时它是选中的那个。
struct HelpCrossView: View {
    let popup: HelpCrossPopup
    let look: HelpKeyLook

    var body: some View {
        let frame = popup.upFrame
        let selected = popup.selected == .kaomoji
        let shape = RoundedRectangle(cornerRadius: 8.5, style: .continuous)
        ZStack(alignment: .topLeading) {
            Text("^^ " + L("颜文字", "Kaomoji", "顔文字"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(selected ? Color.white : Brand.deepPurple)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(width: frame.width, height: frame.height)
                .background(shape.fill(selected ? HelpStyle.kaomojiCell : KeyStyle.charKey))
                .overlay(shape.strokeBorder(Color.white, lineWidth: 2).opacity(selected ? 1 : 0))
                .compositingGroup()
                .shadow(color: .black.opacity(selected ? 0.35 : 0.22), radius: selected ? 8 : 6, y: selected ? 6 : 4)
                .scaleEffect(selected ? 1.06 : 1)
                .animation(.easeOut(duration: 0.12), value: selected)
                .offset(x: frame.minX, y: frame.minY)
            HelpReplyKey(look: look, crossShowing: true)
                .overlay(shape.strokeBorder(Color.white, lineWidth: 2).opacity(popup.selected == .help ? 1 : 0))
                .opacity(popup.selected == nil ? 0.6 : 1)
                .frame(width: popup.key.cap.width, height: popup.key.cap.height)
                .offset(x: popup.key.cap.minX, y: popup.key.cap.minY)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 剪贴板面板里的「帮回」小胶囊

/// 11.5pt 粗白字、绿渐变、圆角 10。
struct HelpChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 9, weight: .bold))
                Text(L("帮回", "Reply", "返信")).font(.system(size: 11.5, weight: .bold))
            }
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HelpStyle.gradient))
            .fixedSize()
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(L("帮回", "Help Reply", "返信アシスト"))
        .accessibilityHint(L("用这段话帮你写回复", "Draft replies to this text", "この文への返信を作成"))
    }
}

// MARK: - 绿色「AI 帮回」卡（HB1、HB2）

/// 卡片左边的「↵ 上屏」：点一下把这条放进对方输入框；上屏后变「✓ 已上屏」（浅绿底深绿字）。生成中 45% 不能点。
struct HelpInsertKey: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let state = model.helpReply
        let inserted = state?.currentInserted == true
        let enabled = state?.current != nil && state?.currentRunning == false
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button { model.helpInsert() } label: {
            VStack(spacing: 4) {
                Image(systemName: inserted ? "checkmark" : "return.left")
                    .font(.system(size: 13, weight: .bold))
                Text(inserted ? L("已上屏", "Sent", "入力済") : L("上屏", "Insert", "入力"))
                    .font(.system(size: 11.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 2)
            .foregroundStyle(inserted ? HelpStyle.softText : Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if inserted { shape.fill(HelpStyle.softFill) } else { shape.fill(HelpStyle.gradient) }
            }
            .contentShape(shape)
        }
        .buttonStyle(KeyPressStyle())
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled && !inserted)
        .accessibilityLabel(inserted ? L("已上屏", "Inserted", "入力済み") : L("上屏", "Insert", "入力"))
    }
}

struct HelpReplyCard: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        let state = model.helpReply
        let active = model.target == .instruction
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header(state)
                    .padding(.top, 7)
                    .padding(.horizontal, 10)
                content(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let message = state?.message {
                    Text(L("回：", "Re: ", "返信先：") + message.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .accessibilityLabel(L("回复对方：", "Replying to: ", "返信先：") + message)
                }
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(active ? Brand.askActiveLine : Brand.blockHair).frame(height: active ? 1 : 0.5)
            AskField(model: model)
                .frame(height: KeyboardMetrics.askBoxHeight - (active ? 1 : 0.5))
        }
        .background {
            shape.inset(by: -4).fill(HelpStyle.glow)
            shape.fill(KeyStyle.charKey)
            if !active {
                Brand.askInactiveFill
                    .frame(height: KeyboardMetrics.askBoxHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(shape)
            }
        }
        .overlay {
            if state?.running != nil, state?.streaming.isEmpty == true, model.settings.polishAnimation, !reduceMotion {
                SweepBand().clipShape(shape).allowsHitTesting(false)
            }
        }
        .overlay { shape.strokeBorder(HelpStyle.border, lineWidth: 1.5).allowsHitTesting(false) }
        .overlay(alignment: .topLeading) {
            if model.helpMenuOpen, let state { styleMenu(state) }
        }
    }

    // MARK: 卡头（HB17–HB19）

    private func header(_ state: HelpReplyState?) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                HelpIcon(size: 15, running: state?.running != nil && model.settings.polishAnimation)
                Text(L("AI 帮回", "Help Reply", "返信アシスト"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HelpStyle.title)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            if let state {
                // 放得下就挨着排、⌄ 紧跟在后面；放不下卡头可以左右滑，右边渐隐。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        tagRow(state)
                        menuButton
                    }
                    HStack(spacing: 2) {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                tagRow(state).padding(.trailing, 10)
                            }
                            // iOS 26 滚动区两头的渐变模糊会把标签糊掉（0.96_3 真机）：关掉，自己在右边做渐隐。
                            .hidingScrollEdgeEffect()
                            .mask(HStack(spacing: 0) {
                                Color.black
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 14)
                            })
                            .onAppear { if let id = state.currentTag?.id { proxy.scrollTo(id, anchor: .center) } }
                            .onChange(of: state.index) { _ in
                                guard let id = model.helpReply?.currentTag?.id else { return }
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                            }
                        }
                        menuButton
                    }
                }
                .frame(height: 20)
                .layoutPriority(-1)
            }
            Spacer(minLength: 0)
            if state?.currentInserted == true {
                Label(L("已上屏", "Inserted", "入力済み"), systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HelpStyle.title)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 20)
    }

    private func tagRow(_ state: HelpReplyState) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(state.tags.enumerated()), id: \.element.id) { index, tag in
                toneTag(tag.name, selected: index == state.index, look: look(of: tag, in: state)) { model.helpSelect(index) }
                    .id(tag.id)
            }
        }
        .fixedSize()
    }

    private var menuButton: some View {
        Button { model.helpMenuOpen.toggle() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(model.helpMenuOpen ? HelpStyle.softText : HelpStyle.tagText)
                .frame(width: 22, height: 18)
                .background {
                    if model.helpMenuOpen { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(HelpStyle.softFill) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(L("全部帮回风格", "All reply styles", "すべての返信スタイル"))
    }

    /// 标签（和下面的圆点）的几种样子：没写、正在写、写好了、写失败。
    private enum TagLook { case idle, running, done, failed }

    private func look(of tag: HelpReplyState.Tag, in state: HelpReplyState) -> TagLook {
        if state.running == tag.id { return .running }
        if state.isDone(tag) { return .done }
        if case .error? = state.notes[tag.id] { return .failed }
        return .idle
    }

    /// HB19：选中且写好绿渐变白字；写好没选中浅绿底深绿字、前面小 ✓（点了直接显示，不再请求）；
    /// 没写灰色（点了开始写）；正在写绿渐变 + 左到右扫光（1.2 秒一圈）+ 三个跳动小点；
    /// 写失败浅红底红字、前面「!」（点它重写）。停了的回到灰色。
    private func toneTag(_ title: String, selected: Bool, look: TagLook, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let filled = look == .running || (selected && look == .done)
        let color: Color = filled ? .white : look == .done ? HelpStyle.softText : look == .failed ? HelpStyle.failText : HelpStyle.tagText
        let moving = model.settings.polishAnimation && !reduceMotion
        return Button(action: action) {
            HStack(spacing: 2) {
                if look == .done && !selected {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy))
                } else if look == .failed {
                    Text("!").font(.system(size: 11.5, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                if look == .running { BouncingDots(moving: moving).padding(.leading, 1) }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background {
                switch look {
                case .running:
                    shape.fill(HelpStyle.gradient)
                        .overlay { if moving { TagShine().clipShape(shape) } }
                case .done:
                    if selected { shape.fill(HelpStyle.gradient) } else { shape.fill(HelpStyle.doneFill) }
                case .failed:
                    shape.fill(HelpStyle.failFill)
                case .idle:
                    shape.fill(HelpStyle.tagFill)
                }
            }
            // 现在这种停了、还没写：灰色，加一圈绿边看得出是它。
            .overlay { if selected && look == .idle { shape.strokeBorder(HelpStyle.green, lineWidth: 1) } }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(title + { () -> String in
            switch look {
            case .done: return L("，已写好", ", ready", "、作成済み")
            case .running: return L("，正在写", ", writing", "、作成中")
            case .failed: return L("，没写出来", ", failed", "、作成失敗")
            case .idle: return ""
            }
        }())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 正在写的标签上一道白色扫光，从左到右 1.2 秒一圈。
    private struct TagShine: View {
        var body: some View {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    shine(width: geo.size.width, time: context.date.timeIntervalSinceReferenceDate)
                }
            }
            .allowsHitTesting(false)
        }

        private func shine(width: CGFloat, time: Double) -> some View {
            let progress = CGFloat(time.truncatingRemainder(dividingBy: 1.2) / 1.2)
            let band: CGFloat = max(width * 0.35, 14)
            let colors: [Color] = [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)]
            return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .offset(x: (width + band) * progress - band)
        }
    }

    /// 三个跳动的小点（标签里、正文右下「正在写」前面）。
    private struct BouncingDots: View {
        var moving: Bool
        var size: CGFloat = 3

        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: !moving)) { context in
                dots(time: context.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: size + 2)
        }

        private func dots(time: Double) -> some View {
            HStack(spacing: size * 0.6) {
                ForEach(0..<3, id: \.self) { i in
                    dot(i, time: time)
                }
            }
        }

        /// 第 i 颗：0.9 秒一轮，后一颗晚 0.18 轮；不动时三颗由深到浅。
        private func dot(_ i: Int, time: Double) -> some View {
            let phase: Double = time / 0.9 - Double(i) * 0.18
            let wave: Double = moving ? max(0, sin(2 * Double.pi * phase)) : 0
            let opacity: Double = moving ? 0.45 + 0.55 * wave : 1 - Double(i) * 0.3
            return Circle()
                .frame(width: size, height: size)
                .opacity(opacity)
                .offset(y: CGFloat(-1.5 * wave))
        }
    }

    // MARK: 正文

    @ViewBuilder
    private func content(_ state: HelpReplyState?) -> some View {
        if let state {
            VStack(spacing: 0) {
                Group {
                    if let reply = state.current {
                        replyBody(text: reply.text, name: reply.name, direction: reply.direction, writing: false)
                    } else if state.currentRunning, !state.streaming.isEmpty {
                        // 边写边出字，末尾一根绿色光标。
                        replyBody(text: state.streaming, name: state.currentTag?.name ?? "", direction: state.direction, writing: true)
                    } else if let note = state.currentNote, let name = state.currentTag?.name {
                        retryRow(note, name: name, state: state)
                    } else {
                        placeholders
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer(state)
            }
        }
    }

    /// 生成中、还没出字：三条绿色扫光占位条。
    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 7) {
            bar(1)
            bar(0.72)
            bar(0.42)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityElement()
        .accessibilityLabel(L("正在写回复", "Writing a reply", "返信を作成中"))
    }

    private func bar(_ ratio: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule().fill(HelpStyle.placeholder).frame(width: geo.size.width * ratio)
        }
        .frame(height: 9)
    }

    private func replyBody(text: String, name: String, direction: String?, writing: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let direction {
                Text(L("方向：", "Aim: ", "方向：") + direction)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(HelpStyle.softText)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(HelpStyle.softFill))
                    .fixedSize()
            }
            (Text(text) + Text(writing ? "▏" : "").foregroundColor(HelpStyle.green))
                .font(.system(size: 15))
                .foregroundStyle(Color.primary)
                .lineLimit(3)
                .truncationMode(writing ? .head : .tail)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { if !writing { model.helpInsert() } }
        .gesture(DragGesture(minimumDistance: 16).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > abs(value.translation.height), abs(dx) > 24 else { return }
            model.helpTurn(dx < 0 ? 1 : -1)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + "：" + text)
        .accessibilityHint(writing ? "" : L("轻点两下放进输入框，上下轻扫换一种", "Double-tap to insert; swipe up or down for another style",
                                             "ダブルタップで入力、上下スワイプで切り替え"))
        .accessibilityAddTraits(writing ? [] : .isButton)
        .accessibilityAction { if !writing { model.helpInsert() } }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.helpTurn(1)
            case .decrement: model.helpTurn(-1)
            @unknown default: break
            }
        }
    }

    /// 正文最下面一行：中间圆点，右下「••• 正在写「客气」…」（卡头放不下，挪到这里）。
    @ViewBuilder
    private func footer(_ state: HelpReplyState) -> some View {
        let writing = state.currentRunning ? state.currentTag?.name : nil
        if state.tags.count > 1 || writing != nil {
            ZStack {
                if state.tags.count > 1 { dots(state) }
                if let writing {
                    HStack(spacing: 4) {
                        BouncingDots(moving: model.settings.polishAnimation && !reduceMotion)
                        Text(L("正在写「\(writing)」…", "Writing \"\(writing)\"…", "「\(writing)」を作成中…"))
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(HelpStyle.title)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                }
            }
            .frame(height: 12)
            .padding(.bottom, 2)
        }
    }

    /// 圆点：长条＝现在这种（正在写的是虚线长条），实心绿＝写好，空心＝还没写，红＝写失败。
    private func dots(_ state: HelpReplyState) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(state.tags.enumerated()), id: \.element.id) { index, tag in
                dot(look(of: tag, in: state), current: index == state.index)
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.index)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dot(_ look: TagLook, current: Bool) -> some View {
        if current && look == .running {
            HStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { _ in Rectangle().fill(HelpStyle.green).frame(width: 3) }
            }
            .frame(width: 12, height: 4)
            .clipShape(Capsule())
        } else if current {
            Capsule().fill(look == .failed ? HelpStyle.failText : HelpStyle.green).frame(width: 12, height: 4)
        } else {
            switch look {
            case .done, .running: Circle().fill(HelpStyle.green).frame(width: 4, height: 4)
            case .failed: Circle().fill(HelpStyle.failText).frame(width: 4, height: 4)
            case .idle: Circle().strokeBorder(HelpStyle.tagText.opacity(0.7), lineWidth: 0.8).frame(width: 4.5, height: 4.5)
            }
        }
    }

    /// 出错、停了（HB18 ⑥）：「「简短」没写出来（网络断了）」+「↻ 再写这条」，下面一行说写好的照样能用。
    private func retryRow(_ note: HelpReplyState.Note, name: String, state: HelpReplyState) -> some View {
        let title: String
        switch note {
        case .error(let reason):
            title = L("「\(name)」没写出来（\(reason)）", "\"\(name)\" didn't come through (\(reason))", "「\(name)」を作成できませんでした（\(reason)）")
        case .stopped:
            title = L("「\(name)」停了，没写完的不留", "\"\(name)\" stopped; the partial reply was dropped", "「\(name)」を停止しました（途中までの文は破棄）")
        }
        let done = state.tags.filter { state.isDone($0) }.map { "「\($0.name)」" }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button { model.retryHelpReply() } label: {
                    Label(L("再写这条", "Try again", "もう一度"), systemImage: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(HelpStyle.gradient))
                        .fixedSize()
                }
                .buttonStyle(KeyPressStyle())
            }
            if !done.isEmpty {
                Text(L("已写好的\(done.joined(separator: "、"))照样能点、能上屏", "Ready ones still work: tap to view or insert",
                       "作成済みの\(done.joined(separator: "、"))はそのまま使えます"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: ⌄ 全部帮回风格

    /// 打勾的在卡头上（打勾的几种 + 上次用的 + 这次加的），写好的后面标「已写」；点没勾的就加一个标签并开始写（只在这一次）。
    private func styleMenu(_ state: HelpReplyState) -> some View {
        let shown = Set(state.tags.map(\.id))
        let written = Set(state.results.keys)
        return ZStack(alignment: .topLeading) {
            // 点菜单外面只收起菜单。
            Color.black.opacity(0.001)
                .frame(width: 3000, height: 3000)
                .offset(x: -1500, y: -1500)
                .onTapGesture { model.helpMenuOpen = false }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.settings.replyStyles) { style in
                    let on = shown.contains(style.id)
                    Button { model.helpStylePicked(style) } label: {
                        HStack(spacing: 8) {
                            Text(style.displayName)
                                .font(.system(size: 14.5, weight: on ? .semibold : .regular))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            if written.contains(style.id) {
                                Text(L("已写", "Ready", "作成済"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(HelpStyle.softText)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(HelpStyle.doneFill))
                                    .fixedSize()
                            }
                            Spacer(minLength: 0)
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(HelpStyle.green)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Rectangle().fill(Brand.blockHair).frame(height: 0.5).padding(.vertical, 3)
                Text(L("打勾的在卡头上；点没勾的就加一个并开始写", "Checked ones are on the card; tap another to add it and start writing",
                       "チェックはカードにあるもの。ほかをタップで追加して作成"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            .frame(width: 168)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KeyStyle.charKey))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.blockHair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            .offset(x: 40, y: 30)
        }
    }
}
