import SwiftUI

/// 试一试：几个预置内容的输入框，用来测试键盘的打字、润色和按要求改。
struct PlaygroundView: View {
    struct Sample: Identifiable {
        let id: Int
        let title: String
        let hint: String
        let text: String
    }

    static let samples: [Sample] = [
        Sample(id: 0, title: "润色口语", hint: "点 ✨润色，把随口说的话整理通顺。",
               text: "那个明天的会我可能去不了 家里有点事 你帮我跟老板说一下 不好意思啊"),
        Sample(id: 1, title: "按要求改", hint: "输入框里「//」后面是要求，点 ✨润色 按要求改；也可以点「要求」选一个。",
               text: "下周三下午三点在三楼会议室讨论新版本上线计划，大家提前看下文档 // 更正式一点"),
        Sample(id: 2, title: "帮我写", hint: "输入框留空，点「要求」，输入「帮我写一段请假说明，请两天」后执行。",
               text: ""),
        Sample(id: 3, title: "中英混合", hint: "试试拼音和英文切换，或者让它「翻成英文」。",
               text: "这个 bug 我今天下班前 fix 掉，明天早上再 sync 一下进度"),
        Sample(id: 4, title: "长段落纠错", hint: "有错别字的一段话，选中一部分只改选中的内容，或者整段润色。",
               text: "我们这次的活动非常成功，参加的人数比预计的多了一倍。大家的反溃都很好，特别是互动环节，很多人表示下次还要来。不过也有一些问题，比如签到太慢，饮料不够，下次需要提前准被。"),
    ]

    @State private var texts: [String] = Self.samples.map(\.text)
    @FocusState private var focused: Int?

    var body: some View {
        Form {
            Section {
                Text("点一个输入框，长按或点地球键 🌐 切换到 Enclave 键盘，然后按提示试。改乱了点「重置」恢复。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Self.samples) { sample in
                Section {
                    TextField("在这里输入…", text: $texts[sample.id], axis: .vertical)
                        .lineLimit(2...8)
                        .focused($focused, equals: sample.id)
                } header: {
                    HStack {
                        Text("\(sample.id + 1). \(sample.title)")
                        Spacer()
                        Button("重置") { texts[sample.id] = sample.text }
                            .font(.footnote)
                            .textCase(nil)
                            .disabled(texts[sample.id] == sample.text)
                    }
                } footer: {
                    Text(sample.hint)
                }
            }
        }
        .navigationTitle("试一试")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("全部重置") { texts = Self.samples.map(\.text) }
            }
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("收起键盘") { focused = nil }
                }
            }
        }
    }
}
