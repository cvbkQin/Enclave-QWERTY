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
        let enabled = state?.running == nil && state?.current != nil
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
            if state?.running != nil, model.settings.polishAnimation, !reduceMotion {
                SweepBand().clipShape(shape).allowsHitTesting(false)
            }
        }
        .overlay { shape.strokeBorder(HelpStyle.border, lineWidth: 1.5).allowsHitTesting(false) }
        .overlay(alignment: .topLeading) {
            if model.helpMenuOpen, let state { styleMenu(state) }
        }
    }

    // MARK: 卡头

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
            if let state, !state.replies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(state.replies.enumerated()), id: \.element.id) { index, reply in
                            toneTag(reply.name, selected: index == state.index) { model.helpSelect(index) }
                        }
                    }
                }
                // iOS 26 滚动区两头的渐变模糊会把标签糊掉（0.96_3 真机）：关掉。
                .hidingScrollEdgeEffect()
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)
            }
            if state?.running == nil {
                Button { model.helpMenuOpen.toggle() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HelpStyle.tagText)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(KeyPressStyle())
                .accessibilityLabel(L("全部帮回风格", "All reply styles", "すべての返信スタイル"))
            }
            Spacer(minLength: 0)
            trailing(state)
        }
        .frame(height: 20)
    }

    private func toneTag(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : HelpStyle.tagText)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(HelpStyle.gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(HelpStyle.tagFill)
                    }
                }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func trailing(_ state: HelpReplyState?) -> some View {
        if let state {
            if state.running != nil {
                Text(L("正在写 \(state.runningCount) 条…", "Writing \(state.runningCount)…", "\(state.runningCount) 件作成中…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            } else if state.currentInserted {
                Label(L("已上屏", "Inserted", "入力済み"), systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HelpStyle.title)
                    .lineLimit(1)
                    .fixedSize()
            } else if !state.replies.isEmpty {
                Text("\(state.index + 1) / \(state.replies.count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    // MARK: 正文

    @ViewBuilder
    private func content(_ state: HelpReplyState?) -> some View {
        if let state {
            if case .all = state.running {
                placeholders
            } else if let reply = state.current {
                replyBody(reply, state: state)
            } else if state.running != nil {
                placeholders
            } else if let error = state.error {
                retryRow(error, color: .red)
            } else if state.stopped {
                retryRow(L("已停止 · 再点「帮回」重写", "Stopped · tap Reply to try again", "停止しました · もう一度「返信」で作り直し"),
                         color: .secondary)
            } else {
                placeholders
            }
        }
    }

    /// 生成中：三条绿色扫光占位条。
    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 7) {
            bar(1)
            bar(0.72)
            bar(0.42)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityElement()
        .accessibilityLabel(L("正在写回复", "Writing replies", "返信を作成中"))
    }

    private func bar(_ ratio: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule().fill(HelpStyle.placeholder).frame(width: geo.size.width * ratio)
        }
        .frame(height: 9)
    }

    private func replyBody(_ reply: HelpReplyState.Reply, state: HelpReplyState) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let direction = reply.direction {
                    Text(L("方向：", "Aim: ", "方向：") + direction)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(HelpStyle.softText)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(HelpStyle.softFill))
                        .fixedSize()
                }
                Text(reply.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { model.helpInsert() }
            .gesture(DragGesture(minimumDistance: 16).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height), abs(dx) > 24 else { return }
                model.helpTurn(dx < 0 ? 1 : -1)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reply.name + "：" + reply.text)
            .accessibilityHint(L("轻点两下放进输入框，上下轻扫换一条", "Double-tap to insert; swipe up or down for another",
                                 "ダブルタップで入力、上下スワイプで切り替え"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.helpInsert() }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.helpTurn(1)
                case .decrement: model.helpTurn(-1)
                @unknown default: break
                }
            }
            if state.replies.count > 1 { dots(state) }
        }
    }

    /// 圆点：第几条，当前那颗拉长成绿色小胶囊。
    private func dots(_ state: HelpReplyState) -> some View {
        HStack(spacing: 3) {
            ForEach(state.replies.indices, id: \.self) { index in
                Capsule()
                    .fill(index == state.index ? HelpStyle.green : HelpStyle.tagFill)
                    .frame(width: index == state.index ? 12 : 4, height: 4)
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.index)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    private func retryRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button { model.retryHelpReply() } label: {
                Text(L("帮回", "Reply", "返信"))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(HelpStyle.gradient))
            }
            .buttonStyle(KeyPressStyle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: ⌄ 全部帮回风格

    /// 打勾的是这次一起写的；点没勾的用它多写一条，成为最后一个标签。
    private func styleMenu(_ state: HelpReplyState) -> some View {
        let shown = Set(state.replies.map(\.styleID))
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
                Text(L("打勾的是一起写的几种；点别的就多写一条", "Checked ones were written together; tap another to add one",
                       "チェックはまとめて作成したもの。ほかをタップで 1 件追加"))
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
