import SwiftUI

/// 常用语的一张卡（「标题和内容」「内容」两种方式）。键盘左栏和 App 里「键盘里看起来」共用（对齐清单第 62 条），scale 是 App 预览缩小用的。
struct PhraseCard: View {
    let phrase: KeyboardPhrase
    var showsTitle: Bool
    var accent: Color
    var fill: Color
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1 * scale) {
            if showsTitle, let title = phrase.displayTitle {
                Text(title)
                    .font(.system(size: 13 * scale, weight: .bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Text(phrase.flattened)
                    .font(.system(size: 12.5 * scale))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            } else {
                Text(phrase.text)
                    .font(.system(size: 13.5 * scale))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 7 * scale)
        .background(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).fill(fill))
        .contentShape(Rectangle())
    }
}

/// 「标题」方式的一个标签：标题紫色粗体；没标题的显示内容（次要色）。按内容宽，最多一行。
struct PhraseChip: View {
    let phrase: KeyboardPhrase
    var accent: Color
    var fill: Color
    var scale: CGFloat = 1

    var body: some View {
        let title = phrase.displayTitle
        Text(title ?? phrase.flattened)
            .font(.system(size: 13 * scale, weight: title == nil ? .regular : .bold))
            .foregroundStyle(title == nil ? Color.secondary : accent)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9 * scale)
            .frame(height: 30 * scale)
            .background(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).fill(fill))
            .contentShape(Rectangle())
    }
}

/// 一行排不下就换行的排法（「标题」方式的标签）。每个按自己的宽，最宽不超过一行。
struct PhraseFlow: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.maxX).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                                           proposal: ProposedViewSize(width: item.width, height: row.height))
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat = 0
        var maxX: CGFloat = 0
        var items: [(index: Int, x: CGFloat, width: CGFloat)] = []
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row(y: 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !row.items.isEmpty, row.maxX + spacing + itemWidth > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            let x = row.items.isEmpty ? 0 : row.maxX + spacing
            row.items.append((index, x, itemWidth))
            row.maxX = x + itemWidth
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
