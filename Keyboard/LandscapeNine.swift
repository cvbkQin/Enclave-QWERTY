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
            // ④ 回答卡：左边替换键 52 宽；自由编辑时卡片占满。
            HStack(spacing: KeyboardMetrics.resultKeyGap) {
                if model.target != .card {
                    ResultKey(model: model)
                        .frame(width: 52)
                }
                ResultCard(model: model)
            }
        } else {
            // ① 平时放联想，点一个上屏；③ 刚弹出、还没打字时没有联想，面板空着。
            LandscapeWordPanel(model: model, words: model.showsPredictions ? model.displayWords(model.predictions) : [], composing: false)
        }
    }
}

/// 中间那块的联想 / 候选面板：按键底色、圆角 10；每行 36 高，行间 0.5pt 细线，字 19；
/// 排法和展开的整页候选一样（CandidateRows），放不下上下滑，底部 22 渐隐。打字中第一个候选垫浅灰底。
struct LandscapeWordPanel: View {
    @ObservedObject var model: KeyboardModel
    let words: [String]
    let composing: Bool

    private static let rowHeight: CGFloat = 36
    private static let fade: CGFloat = 22
    private static let sidePadding: CGFloat = 4

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        GeometryReader { geo in
            let rows = CandidateRows.rows(words, width: max(geo.size.width - Self.sidePadding * 2, 1))
            let overflows = CGFloat(rows.count) * Self.rowHeight > geo.size.height + 0.5
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            ForEach(row.cells, id: \.index) { cell in
                                Button { select(cell.index) } label: {
                                    Text(cell.word)
                                        .font(.system(size: 19))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .padding(.horizontal, CandidateRows.padding)
                                        .frame(width: cell.width, height: Self.rowHeight)
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
