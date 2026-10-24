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
        Sample(id: 0, title: "润色口语", hint: "点「✨ 润色」，再点「替换」。",
               text: "那个文件我看了一下大概没啥问题就是第三页有个数好像不太对你再看看"),
        Sample(id: 1, title: "按要求改", hint: "点「✨ 润色」右边的风格按钮，在「要求」里写「语气委婉一点」，按键盘上的紫色「执行」。",
               text: "周五前给不了，下周一吧"),
        Sample(id: 2, title: "帮我写", hint: "输入框留空，在「要求」里写「请假一天的理由，给领导」。",
               text: ""),
        Sample(id: 3, title: "中英混合", hint: "用拼音打中文，点「中/英」切全键盘打英文，看候选和切换。",
               text: "这个 bug 我今天下班前 fix 掉，明天早上再 sync 一下进度"),
        Sample(id: 4, title: "长段落纠错", hint: "润色后用卡片右边的 ▲▼ 翻看几版结果，长按卡片复制。",
               text: "我们这次的活动非常成功，参加的人数比预计的多了一倍。大家的反溃都很好，特别是互动环节，很多人表示下次还要来。不过也有一些问题，比如签到太慢，饮料不够，下次需要提前准被。"),
    ]

    /// 从链接打开时自动聚焦第一个输入框，让键盘直接弹出来。
    var autoFocusToken: UUID?

    @State private var texts: [String] = Self.samples.map(\.text)
    @FocusState private var focused: Int?

    init(autoFocusToken: UUID? = nil) {
        self.autoFocusToken = autoFocusToken
    }

    var body: some View {
        Form {
            Section {
                Text("每个例子点进输入框，切到 Enclave，按提示操作。改乱了点「重置」恢复。")
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
        .navigationBarTitleDisplayMode(.inline)
        .task(id: autoFocusToken) {
            guard autoFocusToken != nil else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            focused = 0
        }
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
