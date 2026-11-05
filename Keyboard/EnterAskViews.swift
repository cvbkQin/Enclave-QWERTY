import SwiftUI

/// 回答卡展开、焦点在识意框时的回车（第 70 条，EA1 / EA2）。
enum EnterAskStyle {
    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// 整颗底色：识意渐变 #8B5CF6 → #EC4899，160°（CSS 角度，从上偏左到下偏右）。
    static let keyGradient = LinearGradient(colors: [hex(0x8B5CF6), hex(0xEC4899)],
                                            startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97))
    /// 上段「↑ ✨ 润色」#6D4AE8，下段「← 问答」#2F6FEA。
    static let polishSegment = hex(0x6D4AE8)
    static let askSegment = hex(0x2F6FEA)
    /// 十字里的两格：润色键紫渐变 #8B5CF6 → #6D4AE8，问答键蓝渐变 #3B82F6 → #4F7FE8。
    static let polishCell = LinearGradient(colors: [hex(0x8B5CF6), hex(0x6D4AE8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let askCell = LinearGradient(colors: [hex(0x3B82F6), hex(0x4F7FE8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cornerRadius: CGFloat = 8.5
    static let segmentHeight: CGFloat = 22
    /// 十字里选中那一段长到 40 高。
    static let segmentHighlightHeight: CGFloat = 40

    static var accessibilityLabel: String {
        L("识意", "Smart Ask", "意図を読む")
    }

    static var accessibilityHint: String {
        L("点一下识意；上滑润色，左滑问答。", "Tap to let AI decide; swipe up to polish, swipe left to ask.",
          "タップで AI が判断、上スワイプで推敲、左スワイプで質問。")
    }
}

/// 回车键本身：三段式（上润色、中识意、下问答）；执行中整颗换成停止图标；识意框空着是灰色「识意」。
/// 全键盘的回车只有一行高，放不下三段：只画中段，十字里选中哪个就写哪个。
struct EnterAskKey: View {
    let ai: KeyboardModel.EnterAI
    var pressed = false
    /// 十字弹出时回车同步亮起对应的段。
    var highlight: EnterCrossPopup.Choice?
    var crossShowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < Self.segmentedMinHeight
            ZStack {
                if ai.empty && !ai.running {
                    RoundedRectangle(cornerRadius: EnterAskStyle.cornerRadius, style: .continuous)
                        .fill(Brand.returnSoftFill)
                    middleLabel.foregroundStyle(Color.secondary).opacity(0.6)
                } else {
                    RoundedRectangle(cornerRadius: EnterAskStyle.cornerRadius, style: .continuous)
                        .fill(EnterAskStyle.keyGradient)
                    if ai.running {
                        AIStopIcon(running: true, moving: ai.moving && !reduceMotion, tint: .white)
                    } else if compact {
                        compactLabel.foregroundStyle(.white)
                    } else {
                        segments(height: geo.size.height).foregroundStyle(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: EnterAskStyle.cornerRadius, style: .continuous))
            .opacity(pressed && !crossShowing ? 0.8 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EnterAskStyle.accessibilityLabel)
        .accessibilityHint(EnterAskStyle.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    /// 上下两段 22 + 中段至少 30 才画三段。
    static let segmentedMinHeight: CGFloat = 76

    private func segments(height: CGFloat) -> some View {
        let polishHeight = highlight == .polish ? EnterAskStyle.segmentHighlightHeight : EnterAskStyle.segmentHeight
        let askHeight = highlight == .ask ? EnterAskStyle.segmentHighlightHeight : EnterAskStyle.segmentHeight
        // 拖到上 / 左格时，回车对应那段亮起、其余两段 40% 透明。
        let dimmed = highlight == .polish || highlight == .ask
        return VStack(spacing: 0) {
            if ai.polish {
                HStack(spacing: 2) {
                    Text("↑ ✨").font(.system(size: 10.5, weight: .bold))
                    Text(L("润色", "Polish", "推敲")).font(.system(size: 10.5, weight: .bold))
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: polishHeight)
                .background(EnterAskStyle.polishSegment)
                .opacity(dimmed && highlight != .polish ? 0.4 : 1)
                divider
            }
            middleLabel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(dimmed ? 0.4 : 1)
            if ai.ask {
                divider
                HStack(spacing: 2) {
                    Text("←").font(.system(size: 10.5, weight: .bold))
                    AskIcon(size: 12)
                    Text(L("问答", "Ask", "質問")).font(.system(size: 10.5, weight: .bold))
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: askHeight)
                .background(EnterAskStyle.askSegment)
                .opacity(dimmed && highlight != .ask ? 0.4 : 1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: highlight)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1)
    }

    /// 中段：放大镜 +「识意」，同一行。
    private var middleLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .regular))
            Text(EnterAskStyle.accessibilityLabel).font(.system(size: 15, weight: .bold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var compactLabel: some View {
        switch highlight {
        case .polish?:
            Text("✨ " + L("润色", "Polish", "推敲")).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        case .ask?:
            HStack(spacing: 3) {
                AskIcon(size: 14)
                Text(L("问答", "Ask", "質問")).font(.system(size: 15, weight: .bold))
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        default:
            middleLabel
        }
    }
}

/// 按住回车弹出的十字（EA2）：正上方「✨ 润色」、左边「问答」，中间回车照旧三段式、跟着选中的段亮起。
struct EnterCrossView: View {
    let popup: EnterCrossPopup
    let ai: KeyboardModel.EnterAI

    var body: some View {
        ZStack(alignment: .topLeading) {
            if popup.polish {
                cell(popup.upFrame, selected: popup.selected == .polish, fill: EnterAskStyle.polishCell) {
                    Text("✨ " + L("润色", "Polish", "推敲"))
                }
            }
            if popup.ask {
                cell(popup.leftFrame, selected: popup.selected == .ask, fill: EnterAskStyle.askCell) {
                    HStack(spacing: 4) {
                        AskIcon(size: 15)
                        Text(L("问答", "Ask", "質問"))
                    }
                }
            }
            // 回车盖在原来的键帽上，跟着选中的段亮起。
            EnterAskKey(ai: ai, highlight: popup.selected, crossShowing: true)
                .frame(width: popup.key.cap.width, height: popup.key.cap.height)
                .offset(x: popup.key.cap.minX, y: popup.key.cap.minY)
        }
        .allowsHitTesting(false)
    }

    /// 两格白字 15pt 粗、圆角 8.5、投影 0 4 12 25% 黑；选中加 2pt 白内描边、放大 1.06、投影加深，没选中的饱和度 75%（不透明）。
    private func cell<Label: View>(_ frame: CGRect, selected: Bool, fill: LinearGradient,
                                   @ViewBuilder label: () -> Label) -> some View {
        let shape = RoundedRectangle(cornerRadius: EnterAskStyle.cornerRadius, style: .continuous)
        return label()
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .frame(width: frame.width, height: frame.height)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Color.white, lineWidth: 2).opacity(selected ? 1 : 0))
            .saturation(selected ? 1 : 0.75)
            .compositingGroup()
            .shadow(color: .black.opacity(selected ? 0.38 : 0.25), radius: selected ? 8 : 6, x: 0, y: selected ? 6 : 4)
            .scaleEffect(selected ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: selected)
            .offset(x: frame.minX, y: frame.minY)
    }
}
