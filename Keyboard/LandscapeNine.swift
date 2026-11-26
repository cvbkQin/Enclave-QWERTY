import SwiftUI

// 横屏九宫格（LN1，11-18 定稿，照 iOS 原生分左中右）：中间那块 340 宽、四行键那么高（146）。
// 平时第一行是 AI 栏，下面三行（108）是一块按键底色的面板：有联想放联想，刚弹出、还没打字时空着（cvbk 定）；
// 打字中整块（四行）都是候选；展开回答卡、提示卡时放在面板的位置。键盘一直不变高，按键不动。

/// 横屏九宫格中间那块。
struct LandscapeNineMiddle: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        if model.isComposing {
            // ② 打字中：AI 栏收起，整块是候选，上下滑。
            // 输入框不认标记文字（NM2）时拼音没处显示：候选上面加一行灰色拼音。
            VStack(spacing: 2) {
                if let pinyin = model.offFieldPinyin {
                    OffFieldPinyinText(text: pinyin, size: 14)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 20)
                }
                LandscapeWordPanel(model: model, words: model.displayWords(model.candidates), composing: true)
            }
        } else {
            VStack(spacing: KeyboardMetrics.nineRowGap) {
                Group {
                    if model.target == .card {
                        CardEditHint(model: model, inset: 0)
                    } else {
                        AIBar(model: model, inset: 0)
                    }
                }
                .frame(height: KeyboardMetrics.nineKeyHeight)
                // AI 栏的下拉框、按住 ✨ 弹出的问答要盖在下面的面板上。
                .zIndex(1)
                lower
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 识意框（横屏和卡片同一个位置）：左边模式列写「识意」，「切换」回到卡片。
    private var askCard: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 0) {
            LandscapeModeColumn(model: model, ask: true)
            AskField(model: model)
        }
        .background(shape.fill(KeyStyle.charKey))
        .overlay(shape.strokeBorder(Brand.askActiveLine, lineWidth: 1))
    }

    /// 下面三行那么高的一块（108）。
    @ViewBuilder
    private var lower: some View {
        if let gate = model.gate {
            // 提示卡比这块高：放进去上下滑。
            ScrollView(.vertical, showsIndicators: false) {
                GateCard(model: model, gate: gate)
                    .frame(height: KeyboardMetrics.gateHeight(gate))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if model.aiExpanded {
            // ④ 回答卡：左边替换键 52 宽；卡片 108 高、不带下半格的识意框，放不下在卡里滑；自由编辑时卡片占满。
            // 识意框和卡片在同一个位置：点卡里左边模式列的「切换」换过去，在识意框里打字时一直显示识意框。
            HStack(spacing: KeyboardMetrics.resultKeyGap) {
                if model.target != .card {
                    ResultKey(model: model)
                        .frame(width: 52)
                }
                if model.target == .instruction {
                    askCard
                } else {
                    ResultCard(model: model, compact: true)
                }
            }
        } else {
            // ① 平时放联想，点一个上屏；③ 刚弹出、还没打字时没有联想，面板空着。
            LandscapeWordPanel(model: model, words: model.showsPredictions ? model.displayWords(model.predictions) : [], composing: false)
        }
    }
}

/// 横屏结果卡最左边 34 宽的模式列（LN1 ④）：上面写现在是什么（AI 改写 / AI 回答 / 识意），下面「⇄ 切换」在卡片和识意框之间换。
struct LandscapeModeColumn: View {
    @ObservedObject var model: KeyboardModel
    /// 现在显示的是识意框。
    let ask: Bool

    var body: some View {
        let answer = !ask && model.session?.currentIsAnswer == true
        let tag = RoundedRectangle(cornerRadius: 7, style: .continuous)
        VStack(spacing: 3) {
            Text(ask ? L("识意", "Ask", "たずねる") : answer ? L("AI回答", "Answer", "回答") : L("AI改写", "Rewrite", "書換え"))
                .font(.system(size: 9.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundStyle(answer ? Brand.modeAnswerText : Brand.modeRewriteText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tag.fill(answer ? Brand.modeAnswerFill : Brand.modeRewriteFill))
            Button {
                if ask { model.focusHostAfterResult() } else { model.focusAsk() }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .semibold))
                    Text(L("切换", "Switch", "切替")).font(.system(size: 9.5))
                }
                .foregroundStyle(Brand.purpleText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tag.fill(Brand.askInactiveFill))
                .contentShape(Rectangle())
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel(ask ? L("回到结果", "Back to result", "結果に戻る") : L("换成识意框", "Switch to Ask", "たずねる欄に切り替え"))
        }
        .padding(4)
        .frame(width: 34)
    }
}

/// 中间那块的联想 / 候选面板：按键底色、圆角 10；每行 36 高，行间 0.5pt 细线，字 19；
/// 排法和展开的整页候选一样（CandidateRows），放不下上下滑，底部 22 渐隐。打字中第一个候选垫浅灰底。
struct LandscapeWordPanel: View {
    @ObservedObject var model: KeyboardModel
    let words: [String]
    let composing: Bool
    /// iPad 全宽 9 键（PadNineMiddle）：一排的高度按那块分（联想 3 排、候选 4 排），字大一点。
    var rowHeight: CGFloat = 36
    var fontSize: CGFloat = 19
    /// 一格最小多宽：iPad 9 键中间那块竖屏 52、横屏 58（PK6：竖屏一排 6 个左右、横屏 9 个左右）。
    var minimumCell: CGFloat = 64

    private static let fade: CGFloat = 22
    private static let sidePadding: CGFloat = 4

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        GeometryReader { geo in
            // iPhone 照旧按 20 号字量宽；iPad 按实际字号量。
            let rows = CandidateRows.rows(words, width: max(geo.size.width - Self.sidePadding * 2, 1), minimumCell: minimumCell,
                                          fontSize: KeyboardMetrics.pad == nil ? CandidateRows.fontSize : fontSize)
            let overflows = CGFloat(rows.count) * rowHeight > geo.size.height + 0.5
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            ForEach(row.cells, id: \.index) { cell in
                                Button { select(cell.index) } label: {
                                    Text(cell.word)
                                        .font(.system(size: fontSize))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .padding(.horizontal, CandidateRows.padding)
                                        .frame(width: cell.width, height: rowHeight)
                                        .background {
                                            if composing, cell.index == 0 {
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .fill(Color.primary.opacity(0.08))
                                                    .padding(.vertical, 3)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(KeyPressStyle())
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Self.sidePadding)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color(UIColor.separator)).frame(height: 0.5)
                        }
                        // 候选只先取了第一屏：滑到最后一行时再往后取。
                        .onAppear {
                            if composing, row.id == rows.last?.id { model.loadMoreCandidates() }
                        }
                    }
                }
            }
            .hidingScrollEdgeEffect()
            // 候选换了时格子直接换，不做动画。
            .transaction { $0.animation = nil }
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(overflows ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            }
        }
        .background(shape.fill(KeyStyle.charKey))
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(composing ? L("候选", "Candidates", "候補") : L("联想", "Suggestions", "予測候補"))
    }

    private func select(_ index: Int) {
        if composing {
            model.selectCandidate(index)
        } else {
            model.selectPrediction(index)
        }
    }
}
