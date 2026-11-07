import SwiftUI

// MARK: - ^^ 键变「帮回」（T16，HB9）

/// 九宫格 ^^ 键常驻帮回（HB23）：低饱和浅灰绿两段式（K2）；有新复制时「回」带红点，帮回卡开着时键外一圈浅绿，
/// 识意框有待执行的要求时外圈加粗带光晕。上段 15 高「↑ ^^ 颜文字」窄条 + 1pt 分隔线，下段降饱和 logo 14pt +「帮回」13.5pt 半粗深绿字。
/// 生成中「帮回」两个字换成胶囊停止图标、logo 动、周围闪深绿小星；写好时深绿对勾一笔画出（600ms）。
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
                // K2（11-07）：低饱和浅灰绿纯色底、深绿字，不用渐变。
                shape.fill(HelpStyle.Key.fill)
                VStack(spacing: 0) {
                    Text("↑ ^^ " + L("颜文字", "Kaomoji", "顔文字"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(HelpStyle.Key.stripText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.topHeight)
                        .background(HelpStyle.Key.stripFill)
                    Rectangle().fill(HelpStyle.Key.stripLine).frame(height: 1)
                    lower
                        .foregroundStyle(HelpStyle.Key.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(shape)
            .overlay {
                if look.running && motion {
                    KeySparkles(running: true, successAt: nil, textX: geo.size.width * 0.18,
                                textWidth: geo.size.width * 0.64, seed: 3, whiteOnly: true, white: HelpStyle.Key.text)
                        .padding(.top, Self.topHeight)
                }
            }
            .opacity(pressed && !crossShowing ? 0.8 : 1)
            .background { ring }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(look.running ? L("停止帮回", "Stop Help Reply", "返信アシストを停止") : L("帮回", "Help Reply", "返信アシスト"))
        .accessibilityHint(L("点一下帮你写回复；上滑打开颜文字。", "Tap to draft replies; swipe up for kaomoji.",
                             "タップで返信を作成、上スワイプで顔文字。"))
        .accessibilityAddTraits(.isButton)
    }

    /// 外圈画在键外：2pt 键盘底色间隔，再一圈浅绿。亮起来（识意框里有没执行的要求，RG4）粗一点、带光晕；
    /// 帮回卡开着时细一圈、不发光。
    @ViewBuilder
    private var ring: some View {
        let armed = look.armed && !look.running
        if armed || look.open {
            let width: CGFloat = armed ? 4.5 : 4
            let gap: CGFloat = 2
            ZStack {
                RoundedRectangle(cornerRadius: 8.5 + gap + width, style: .continuous)
                    .fill(armed ? HelpStyle.Key.armedRing : HelpStyle.Key.openRing)
                    .padding(-(gap + width))
                    .shadow(color: armed ? HelpStyle.Key.armedGlow : .clear, radius: armed ? 10 : 0)
                RoundedRectangle(cornerRadius: 8.5 + gap, style: .continuous)
                    .fill(Brand.keyboardBack)
                    .padding(-gap)
            }
        }
    }

    @ViewBuilder
    private var lower: some View {
        HStack(spacing: 3) {
            HelpIcon(size: 14, running: look.running && motion, soft: true)
            ZStack {
                if look.running {
                    AIStopIcon(running: true, moving: motion, tint: HelpStyle.Key.text)
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
            .font(.system(size: 13.5, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .overlay(alignment: .topTrailing) {
                // 有新复制的内容（HB23）：「回」右上角 3pt 红点，1pt 白边，只偏出字一点点。
                if look.newCopy {
                Circle().fill(HelpStyle.dot)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                    .offset(x: 3.5, y: -2.5)
                }
            }
    }

    /// 写好：深绿对勾 600ms 一笔画出，停住到 ^^ 淡回。
    private struct SuccessDraw: View {
        let since: Date

        var body: some View {
            TimelineView(.animation(minimumInterval: nil, paused: Date().timeIntervalSince(since) > 0.7)) { context in
                let p = min(max(context.date.timeIntervalSince(since) / 0.6, 0), 1)
                SuccessCheck()
                    .trim(from: 0, to: CGFloat(KeySuccessFrame.easeInOut(p)))
                    .stroke(HelpStyle.Key.text, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
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


// MARK: - 帮回在回答卡里（方案 C，11-06）

/// 回答卡上半格，帮回时：标题行（↩ + 风格标签 + ⌄）、正文、右边复制 / 展开 / ▲▼。
/// 卡片外壳、识意框、左边的替换键都是润色、问答那一套，只是换成帮回绿；高度一样，切换不跳。
struct HelpCardContent: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var moving: Bool { model.settings.polishAnimation && !reduceMotion }

    var body: some View {
        if let state = model.helpReply {
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    // 收起时 60 高：标题行 5 + 18，正文两行整（不露半行）；展开四行。
                    HelpTagsHeader(model: model, state: state)
                        .padding(.leading, 10)
                        .padding(.top, 5)
                    main(state)
                        .padding(.leading, 14)
                        .padding(.top, 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                iconColumn(state)
                    .padding(.vertical, 5)
                if state.currentVersions.count > 1, state.running == nil {
                    pager(index: state.currentPage, count: state.currentVersions.count)
                        .contentShape(Rectangle())
                        .highPriorityGesture(swipe)
                }
            }
            .padding(.trailing, 4)
        }
    }

    // MARK: 正文

    @ViewBuilder
    private func main(_ state: HelpReplyState) -> some View {
        if state.currentRunning {
            if state.streaming.isEmpty {
                // 还没出字：一条绿色占位条。
                Capsule().fill(HelpStyle.placeholder).frame(height: 12).padding(.trailing, 30).padding(.top, 6)
                    .accessibilityLabel(L("正在写回复", "Writing a reply", "返信を作成中"))
            } else {
                // 边写边出字，末尾一根绿色光标。
                (Text(state.streaming) + Text("▍").foregroundColor(HelpStyle.green))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .lineLimit(model.cardTall ? 4 : 2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if let reply = state.current, state.currentNote == nil {
            replyText(reply)
        } else if let note = state.currentNote, let name = state.currentTag?.name {
            retryRow(note, name: name)
        } else {
            quote(state.message)
        }
    }

    /// 回复正文：上下滑翻版本、左右滑换风格、长按分词（和润色、问答一样）。用润色改出来的那版前面标「✨ 正式」（待定）。
    private func replyText(_ reply: HelpReplyState.Reply) -> some View {
        ScrollView {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let polish = reply.polish {
                    Text("✨ " + polish)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Brand.tagSelectedText)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Brand.softFill))
                        .fixedSize()
                }
                Text(reply.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .hidingScrollEdgeEffect()
        .contentShape(Rectangle())
        .gesture(swipe)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in model.openWordPanel() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reply.name + "：" + reply.text)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.helpTurnVersion(1)
            case .decrement: model.helpTurnVersion(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: L("分词", "Split into words", "単語に分ける")) { model.openWordPanel() }
    }

    /// 还没有回复（倒计时、等你写要求）：对方原话，灰色，左边一条绿色竖线。
    private func quote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule().fill(HelpStyle.border).frame(width: 3)
            Text(message.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(model.cardTall ? 4 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .gesture(swipe)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("回复对方：", "Replying to: ", "返信先：") + message)
    }

    /// 出错、停了（只影响这一种）：「「简短」没写出来（网络断了）」+「↻ 再写这条」。
    private func retryRow(_ note: HelpReplyState.Note, name: String) -> some View {
        let title: String
        switch note {
        case .error(let reason):
            title = L("「\(name)」没写出来（\(reason)）", "\"\(name)\" didn't come through (\(reason))", "「\(name)」を作成できませんでした（\(reason)）")
        case .stopped:
            title = L("「\(name)」停了，没写完的不留", "\"\(name)\" stopped; the partial reply was dropped", "「\(name)」を停止しました")
        }
        return HStack(spacing: 8) {
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
        .padding(.top, 2)
        .padding(.trailing, 4)
    }

    /// 上下滑翻版本，左右滑换风格。
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12).onEnded { value in
            let dx = value.translation.width
            let dy = abs(value.predictedEndTranslation.height) > abs(value.translation.height)
                ? value.predictedEndTranslation.height : value.translation.height
            if abs(dx) > abs(dy) {
                if abs(dx) > 24 { model.helpTurn(dx < 0 ? 1 : -1) }
            } else if dy < -20 {
                turn(1)
            } else if dy > 20 {
                turn(-1)
            }
        }
    }

    private func turn(_ offset: Int) {
        model.keyFeedback(for: .space)
        withAnimation(.easeOut(duration: 0.2)) { model.helpTurnVersion(offset) }
    }

    // MARK: 右边一列（和润色、问答一样）

    private func iconColumn(_ state: HelpReplyState) -> some View {
        VStack(spacing: 0) {
            iconButton(model.copied ? "doc.on.doc.fill" : "doc.on.doc", tint: model.copied ? HelpStyle.title : .secondary) {
                model.copy()
            }
            .disabled(!model.hasResult)
            .accessibilityLabel(model.copied ? L("已复制", "Copied", "コピーしました") : L("复制回复", "Copy reply", "返信をコピー"))
            Spacer(minLength: 0)
            iconButton(model.cardExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       tint: .secondary) {
                withAnimation(.easeOut(duration: 0.2)) { model.cardExpanded.toggle() }
            }
            .accessibilityLabel(model.cardExpanded ? L("缩小结果卡", "Shrink result card", "結果カードを縮小") : L("放大结果卡", "Enlarge result card", "結果カードを拡大"))
            .accessibilityHidden(model.landscape)
            .opacity(model.landscape ? 0 : 1)
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

    /// ▲ 2/3 ▼：这句话、这种风格的第几版（卡上唯一的数字）。
    private func pager(index: Int, count: Int) -> some View {
        VStack(spacing: 0) {
            Button { turn(-1) } label: {
                Image(systemName: "chevron.up").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel(L("上一版", "Previous version", "前のバージョン"))
            .disabled(index == 0)
            Text("\(index + 1)/\(count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.primary)
            Button { turn(1) } label: {
                Image(systemName: "chevron.down").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel(L("下一版", "Next version", "次のバージョン"))
            .disabled(index >= count - 1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(HelpStyle.title)
        .buttonStyle(.plain)
        .frame(width: 22)
        .padding(.vertical, 2)
    }
}

// MARK: - 标题行：风格标签（HB17、HB19）

/// ↩ 帮回 logo + 风格标签 + ⌄。标签放不下就左右滑、右边渐隐，卡片不加高；标签上不写版本数字。
struct HelpTagsHeader: View {
    @ObservedObject var model: KeyboardModel
    let state: HelpReplyState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var moving: Bool { model.settings.polishAnimation && !reduceMotion }

    var body: some View {
        HStack(spacing: 5) {
            HelpIcon(size: 14, running: state.running != nil && moving)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    tagRow
                    menuButton
                    Spacer(minLength: 0)
                }
                HStack(spacing: 2) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            tagRow.padding(.trailing, 10)
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
        }
        .frame(height: 18)
    }

    private var tagRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(state.tags.enumerated()), id: \.element.id) { index, tag in
                toneTag(tag.name, selected: index == state.index, look: look(of: tag)) { model.helpSelect(index) }
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

    /// 标签的几种样子：没写、正在写、写好了、写失败。
    private enum TagLook { case idle, running, done, failed }

    private func look(of tag: HelpReplyState.Tag) -> TagLook {
        if state.running == tag.id { return .running }
        if case .error? = state.notes[tag.id] { return .failed }
        if state.isDone(tag) { return .done }
        return .idle
    }

    /// HB19：选中且写好绿渐变白字；写好没选中浅绿底深绿字、前面小 ✓；没写灰色；
    /// 选中还没写（倒计时、停了、等你写要求）浅绿描边；正在写绿渐变 + 扫光 + 三个跳动小点；写失败浅红底红字「!」。
    private func toneTag(_ title: String, selected: Bool, look: TagLook, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let filled = look == .running || (selected && look == .done)
        let waiting = selected && look == .idle
        let color = Self.textColor(look, filled: filled, waiting: waiting)
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
                    if waiting { shape.fill(HelpStyle.doneFill.opacity(0.5)) } else { shape.fill(HelpStyle.tagFill) }
                }
            }
            .overlay { if waiting { shape.strokeBorder(HelpStyle.border, lineWidth: 1) } }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(title + Self.stateLabel(look))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func textColor(_ look: TagLook, filled: Bool, waiting: Bool) -> Color {
        if filled { return .white }
        if look == .done || waiting { return HelpStyle.softText }
        if look == .failed { return HelpStyle.failText }
        return HelpStyle.tagText
    }

    private static func stateLabel(_ look: TagLook) -> String {
        switch look {
        case .done: return L("，已写好", ", ready", "、作成済み")
        case .running: return L("，正在写", ", writing", "、作成中")
        case .failed: return L("，没写出来", ", failed", "、作成失敗")
        case .idle: return ""
        }
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

    /// 三个跳动的小点。
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
}

// MARK: - ⌄ 全部帮回风格

/// 打勾的在卡头上（打勾的几种 + 上次用的 + 这次加的），写好的后面标「已写」；点没勾的就加一个标签并开始写（只在这一句）。
struct HelpStyleMenu: View {
    @ObservedObject var model: KeyboardModel
    let state: HelpReplyState

    var body: some View {
        let shown = Set(state.tags.map(\.id))
        let written = Set(state.results.filter { !$0.value.isEmpty }.keys)
        ZStack(alignment: .topLeading) {
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
            .frame(width: 180)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KeyStyle.charKey))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.blockHair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            .offset(x: 30, y: 28)
        }
    }
}

// MARK: - 回哪句话（识意框左边的胶囊，RG2 ③）

/// 「回 这份方案… ⌄」：固定宽度、写要求时也不缩；点开是回哪句话列表。不读、不显示对方的名字。
struct HelpSentenceCapsule: View {
    @ObservedObject var model: KeyboardModel

    /// 规格「约 118 以内」：SE 上给右边的要求多留点，取 104。
    static let maxWidth: CGFloat = 104

    var body: some View {
        let message = model.helpReply?.message.replacingOccurrences(of: "\n", with: " ") ?? ""
        Button { model.helpListOpen.toggle() } label: {
            HStack(spacing: 3) {
                Text(L("回", "Re", "返"))
                    .font(.system(size: 12, weight: .bold))
                Text(message)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: model.helpListOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(HelpStyle.softText)
            .padding(.horizontal, 7)
            .frame(width: Self.maxWidth, height: 26, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HelpStyle.doneFill))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(L("回复对方：", "Replying to: ", "返信先：") + message)
        .accessibilityHint(L("轻点两下换一句", "Double-tap to pick another message", "ダブルタップで別の文を選ぶ"))
    }
}

/// 回哪句话列表：一种行——句子、时间，右边「客气 3 版」或「还没回」；当前这句浅绿底。点哪句就切到哪句。
struct HelpSentenceList: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        let rows = model.helpSentenceRows
        VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L("回哪句话", "Reply to", "返信先")).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(L("点一句就切过去", "Tap one to switch", "タップで切り替え")).font(.system(size: 11.5))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                ForEach(rows) { row in
                    Button { model.helpSentencePicked(row) } label: { line(row) }
                        .buttonStyle(KeyPressStyle())
                }
                Rectangle().fill(Brand.blockHair).frame(height: 0.5)
                Text(L("更早的在 App › AI 历史 › 帮回", "Older ones: app › AI History › Help Reply", "それより前は App › AI 履歴 › 返信"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
            }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KeyStyle.charKey))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.blockHair, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private func line(_ row: HelpSentenceRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(Self.when(row.date) + Self.origin(row))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(row.summary ?? L("还没回", "Not yet", "未返信"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(row.summary == nil ? HelpStyle.tagText : HelpStyle.softText)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(row.summary == nil ? HelpStyle.tagFill : HelpStyle.doneFill))
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(row.source == .current ? HelpStyle.doneFill.opacity(0.55) : Color.clear)
        .contentShape(Rectangle())
    }

    private static func origin(_ row: HelpSentenceRow) -> String {
        if case .clip = row.source { return L(" · 剪贴板里", " · clipboard", " · クリップボード") }
        return ""
    }

    /// 「刚刚」「12 分钟前」「3 小时前」「昨天」。
    static func when(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return L("刚刚", "Just now", "たった今") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return L("\(minutes) 分钟前", "\(minutes) min ago", "\(minutes) 分前") }
        let hours = minutes / 60
        if hours < 24 { return L("\(hours) 小时前", "\(hours) h ago", "\(hours) 時間前") }
        return L("\(hours / 24) 天前", "\(hours / 24) d ago", "\(hours / 24) 日前")
    }
}

// MARK: - 识意框里的倒计时（HB29 → 放进识意框）

/// 整条从左往右变绿、3 秒走完；左边小圆圈里是剩几秒。
struct HelpCountdownFill: View {
    let ends: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            GeometryReader { geo in
                let left = max(0, ends.timeIntervalSince(context.date))
                let progress = CGFloat(min(1, 1 - left / 3))
                HelpStyle.doneFill.opacity(0.85)
                    .frame(width: geo.size.width * progress)
            }
        }
        .allowsHitTesting(false)
    }
}

struct HelpCountdownBadge: View {
    let ends: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = Int(ceil(max(0, ends.timeIntervalSince(context.date))))
            Text("\(left)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(HelpStyle.title)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(HelpStyle.green, lineWidth: 1.5))
        }
        .accessibilityHidden(true)
    }
}
