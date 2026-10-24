import SwiftUI

/// 场景实验室（原「试一试」）：10 个真实场景，每个一页，带预填文字和两步提示，用来练键盘的打字、润色和按要求改。
struct LabScene: Identifiable {
    enum Category: String, CaseIterable {
        case work = "工作", client = "客户", social = "社交", life = "生活", language = "语言"

        /// 分类色：字色和浅底。
        var colors: (text: Color, fill: Color) {
            switch self {
            case .work: return (Color(hex: 0x5B4BE8), Color(hex: 0xECEAFD))
            case .client: return (Color(hex: 0x0E7490), Color(hex: 0xDDF3F7))
            case .social: return (Color(hex: 0xDB2777), Color(hex: 0xFCE7F3))
            case .life: return (Color(hex: 0xB45309), Color(hex: 0xFEF3C7))
            case .language: return (Color(hex: 0x047857), Color(hex: 0xD1FAE5))
            }
        }
    }

    let id: Int
    let category: Category
    let title: String
    let icon: String
    let tag: String
    let situation: String
    let text: String
    let steps: [String]

    static let all: [LabScene] = [
        LabScene(id: 0, category: .work, title: "回复领导", icon: "briefcase", tag: "润色",
                 situation: "领导让你看一份文件，你想回得清楚又不啰嗦。",
                 text: "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看",
                 steps: ["点「✨ 润色」", "看结果卡片，满意就点「替换」"]),
        LabScene(id: 1, category: .work, title: "委婉拒绝", icon: "checkmark.shield", tag: "按要求改",
                 situation: "同事催进度，但这周确实做不完。",
                 text: "周五前给不了，下周一吧",
                 steps: ["点「正式 ▾」，在「要求」里写「语气委婉一点」", "按键盘上的紫色「执行」"]),
        LabScene(id: 2, category: .work, title: "请假申请", icon: "calendar", tag: "帮我写",
                 situation: "什么都不用打，让 AI 起草一段请假理由。",
                 text: "",
                 steps: ["输入框留空，点「正式 ▾」", "在「要求」里写「请假一天的理由，给领导」，按「执行」"]),
        LabScene(id: 3, category: .client, title: "安抚客户", icon: "headphones", tag: "润色 · 正式",
                 situation: "客户催发货，你想道歉并给出明确时间。",
                 text: "不好意思啊 仓库那边最近爆单了 明天肯定给你发出去 别退款了哈",
                 steps: ["风格选「正式」，点「✨ 润色」", "不满意点「再润」换一版"]),
        LabScene(id: 4, category: .social, title: "朋友圈文案", icon: "camera", tag: "按要求改",
                 situation: "爬山回来，想发一条有点文艺感的朋友圈。",
                 text: "今天去爬山了 累死 但是山顶的风景真的绝了 值",
                 steps: ["点「正式 ▾」，在「要求」里写「写成朋友圈文案，文艺一点」", "按「执行」"]),
        LabScene(id: 5, category: .social, title: "和好道歉", icon: "heart", tag: "按要求改",
                 situation: "昨天和朋友吵了两句，想真诚地道个歉。",
                 text: "昨天是我说话太冲了 不是故意的 别生气了",
                 steps: ["在「要求」里写「真诚一点，别太肉麻」", "按「执行」，用 ▲▼ 翻看几版"]),
        LabScene(id: 6, category: .life, title: "闲置转卖", icon: "tag", tag: "帮我写",
                 situation: "把一台闲置 iPad 挂到二手平台。",
                 text: "九成新 iPad 买了没怎么用 2000 出 不刀",
                 steps: ["在「要求」里写「写成闲鱼商品描述，分点列出」", "按「执行」"]),
        LabScene(id: 7, category: .language, title: "英文邮件", icon: "globe", tag: "翻译",
                 situation: "约外国同事改会议时间，直接用中文写。",
                 text: "麻烦帮我确认一下下周二的会议时间，如果你不方便的话可以改到周三下午",
                 steps: ["在「要求」里写「翻成英文邮件」", "按「执行」，点「替换」"]),
        LabScene(id: 8, category: .language, title: "中英混打", icon: "keyboard", tag: "输入",
                 situation: "技术群里聊天，中文里夹着英文词。",
                 text: "这个 bug 我今天下班前 fix 掉，明天早上再 sync 一下进度",
                 steps: ["用拼音打中文", "点「中/英」切到全键盘打英文，再切回来"]),
        LabScene(id: 9, category: .life, title: "错字校对", icon: "doc.text.magnifyingglass", tag: "润色 · 多版本",
                 situation: "活动总结里有几个错别字，帮你一次找出来。",
                 text: "我们这次的活动非常成功，参加的人数比预计的多了一倍。大家的反溃都很好，特别是互动环节，很多人表示下次还要来。不过也有一些问题，比如签到太慢，饮料不够，下次需要提前准被。",
                 steps: ["点「✨ 润色」", "用卡片右边的 ▲▼ 翻看几版，长按卡片复制"]),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// 场景列表：分类筛选 + 两列卡片。
struct LabView: View {
    @State private var category: LabScene.Category?

    private var scenes: [LabScene] {
        LabScene.all.filter { category == nil || $0.category == category }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(LabScene.all.count) 个真实场景").font(.title.bold())
                    Text("挑一个点进去，切到 Enclave 跟着做一遍。").font(.subheadline).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, title: "全部", count: LabScene.all.count)
                        ForEach(LabScene.Category.allCases, id: \.self) { item in
                            filterChip(item, title: item.rawValue, count: LabScene.all.filter { $0.category == item }.count)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(scenes) { scene in
                        NavigationLink {
                            SceneView(index: scene.id)
                        } label: {
                            SceneCard(scene: scene)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("场景实验室")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func filterChip(_ item: LabScene.Category?, title: String, count: Int) -> some View {
        let selected = category == item
        return Button { category = item } label: {
            HStack(spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text("\(count)").opacity(0.6)
            }
            .font(.subheadline)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(selected ? Color.primary : Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}

private struct SceneCard: View {
    let scene: LabScene

    var body: some View {
        let colors = scene.category.colors
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: scene.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.text)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colors.fill))
                Spacer()
                Text(scene.category.rawValue).font(.caption.weight(.semibold)).foregroundStyle(colors.text)
            }
            .padding(.bottom, 4)
            Text(scene.title).font(.system(size: 15.5, weight: .semibold))
            Text(scene.situation)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Text(scene.tag)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(.systemGray6)))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// 一个场景一页：进来自动聚焦弹出键盘，右上「重置」恢复预填文字，底部上一个 / 下一个。
struct SceneView: View {
    @State private var index: Int
    @State private var text: String
    @FocusState private var focused: Bool

    init(index: Int) {
        _index = State(initialValue: index)
        _text = State(initialValue: LabScene.all[index].text)
    }

    private var scene: LabScene { LabScene.all[index] }

    var body: some View {
        let colors = scene.category.colors
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: scene.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colors.text)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(colors.fill))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(scene.category.rawValue) · 场景 \(index + 1)/\(LabScene.all.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(colors.text)
                        Text(scene.title).font(.system(size: 20, weight: .bold))
                    }
                }
                Text(scene.situation).font(.subheadline).foregroundStyle(.secondary)
                TextField(scene.text.isEmpty ? "输入框留空，按下面的提示让它帮你写" : "在这里输入…", text: $text, axis: .vertical)
                    .lineLimit(3...10)
                    .focused($focused)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColor.purple, lineWidth: focused ? 2 : 0))
                VStack(alignment: .leading, spacing: 10) {
                    Text("试试这样做").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(scene.steps.enumerated()), id: \.offset) { number, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(number + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColor.purple)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(AppColor.softFill))
                            Text(step).font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                HStack {
                    Button { go(index - 1) } label: { Label("上一个", systemImage: "chevron.left") }
                        .disabled(index == 0)
                    Spacer()
                    if index + 1 < LabScene.all.count {
                        Button { go(index + 1) } label: {
                            HStack(spacing: 4) {
                                Text("下一个：\(LabScene.all[index + 1].title)")
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .tint(AppColor.purple)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("场景实验室")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: index) {
            try? await Task.sleep(nanoseconds: 600_000_000)
            focused = true
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("重置") { text = scene.text }
            }
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("收起键盘") { focused = false }
                }
            }
        }
    }

    private func go(_ next: Int) {
        guard LabScene.all.indices.contains(next) else { return }
        index = next
        text = LabScene.all[next].text
    }
}
