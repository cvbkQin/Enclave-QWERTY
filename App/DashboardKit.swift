import SwiftUI

// B 数据仪表盘的通用组件（功能对照表「App 页面精修」通用规范）。App 各页共用这一份，不另写。

/// 颜色含义：紫是 AI（提示词、接口、场景实验室），蓝是输入（键盘、常用词、拼音词库），
/// 橙是键盘常用语，绿是正常或已完成，灰是系统（隐私、关于）。
enum DashColor {
    static let ai = Color(hex: 0x5B4BE8)
    static let input = Color(hex: 0x007AFF)
    static let phrase = Color(hex: 0xFF9F0A)
    static let ok = Color(hex: 0x34C759)
    static let system = Color(hex: 0x8E8E93)
    /// 页面底：浅色 #F2F2F7，深色 #000。
    static let page = Color(.systemGroupedBackground)
    /// 卡片：浅色白，深色 #1C1C1E。
    static let card = Color(.secondarySystemGroupedBackground)
    /// 没有数据时的空柱、进度条没走到的格子。
    static let empty = Color(.systemGray5)
}

/// 没有数据时的那句话。
enum DashText {
    static var emptyStats: String {
        L("在键盘上点一次 ✨，这里就有数据了", "Tap ✨ on the keyboard once and your stats show up here.", "キーボードで ✨ を一度タップすると、ここに記録が表示されます。")
    }
}

/// 卡片：白底（深色 #1C1C1E），圆角 16，内边距 16。
struct DashCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DashColor.card))
    }
}

/// 卡片头：16pt 彩色图标 + 15pt semibold 标题，同一颜色；右边可放灰色 13pt 附注。
struct DashCardHeader: View {
    var icon: String
    var title: String
    var color: Color
    var note: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .foregroundStyle(color)
    }
}

/// 大数字：40pt bold，后面跟 15pt 灰色单位，比如「23 次 · 今天」。
struct DashBigNumber: View {
    var value: String
    var unit: String?
    var size: CGFloat = 40

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
            if let unit { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// 列表行图标：30pt 圆角 8 的方块，主色 12% 底，17pt 主色图标。
struct TintIcon: View {
    var systemName: String
    var color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.57, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.12)))
    }
}

/// 列表的一行：浅色图标方块、标题、右边灰字。
struct DashRow: View {
    var icon: String
    var color: Color
    var title: String
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemName: icon, color: color)
            Text(title)
            Spacer(minLength: 8)
            if let value { Text(value).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

/// 柱状图：最后一根（今天）用主色实心，其余是主色 25%；全是 0 时画灰色空柱。
struct DashBarChart: View {
    var values: [Int]
    var labels: [String]
    var color: Color = DashColor.ai
    var height: CGFloat = 64

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        let empty = values.allSatisfy { $0 == 0 }
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    let last = index == values.count - 1
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(empty ? DashColor.empty : (last ? color : color.opacity(0.25)))
                        .frame(height: empty ? height * 0.35 : max(4, height * CGFloat(values[index]) / CGFloat(top)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: 8) {
                ForEach(labels.indices, id: \.self) { index in
                    Text(labels[index]).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(values.map(String.init).joined(separator: ", "))
    }

    /// 最近 days 天的星期标签，今天在最后：「一 二 … 日」/ Mon…
    static func weekdayLabels(days: Int = 7) -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Loc.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: Date()).map { formatter.string(from: $0) }
        }
    }
}

/// 分格进度条：done 格主色，其余灰色，比如试用 7 格、场景 10 格。
struct DashSegments: View {
    var total: Int
    var done: Int
    var color: Color = DashColor.ai

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule().fill(index < done ? color : DashColor.empty).frame(height: 6)
            }
        }
    }
}

/// 小曲线：接口页最近 10 次请求的耗时，下面浅色填充。
struct DashSparkline: View {
    var values: [Double]
    var color: Color = DashColor.ok
    var height: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.15))
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else {
                    Capsule().fill(DashColor.empty).frame(height: 2).frame(maxHeight: .infinity)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let span = max(high - low, 0.001)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            // 耗时越短越靠上，留 4pt 上下边。
            let y = 4 + (size.height - 8) * CGFloat((value - low) / span)
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}

/// 小标签：「默认」「手动」「工作」这类，主色字、主色 12% 底。
struct DashTag: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.opacity(0.12)))
    }
}

/// 四个标签页共用的自绘标题（PH1–PH4）：上面一行 13pt semibold 灰字，下面 34pt bold 大标题。
/// 导航栏隐藏，左边距和顶部位置四页一样。
struct TabTitle: View {
    var caption: String
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(.footnote.weight(.semibold)).foregroundStyle(DashColor.system).lineLimit(1)
            Text(title).font(.largeTitle.bold()).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// 标签页的根页面：隐藏导航栏（标题自己画），列表顶部只留和首页一样的 8pt。
    @ViewBuilder
    func tabRootPage() -> some View {
        if #available(iOS 17.0, *) {
            self.toolbar(.hidden, for: .navigationBar)
                .contentMargins(.top, 8, for: .scrollContent)
        } else {
            self.toolbar(.hidden, for: .navigationBar)
        }
    }

    /// 把 B 卡片放进 Form / List 的分组页：用作 Section 的 header（header 不会被系统按分组大圆角裁掉），
    /// 去掉 header 的缩进、大写和灰色小字，左右和其他分组对齐，卡片自己的 16 圆角和描边完整。
    /// 不要放成列表行：iOS 会按分组圆角（iOS 26 上约 26pt）裁这一行，外角和描边会被切。
    func dashFormCard() -> some View {
        self
            .textCase(nil)
            .font(.body)
            .foregroundStyle(.primary)
            .listRowInsets(EdgeInsets())
    }
}

/// 卡片之间 12、左右 20 的页面骨架（和列表页的分组、首页卡片对齐），底色 #F2F2F7 / #000。
struct DashPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(DashColor.page)
    }
}
