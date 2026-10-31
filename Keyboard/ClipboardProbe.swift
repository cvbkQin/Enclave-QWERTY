import SwiftUI
import UIKit

/// B1 剪贴板第一步（临时，测完删）：在真机上分别试三种读法，看哪一种会让系统弹「允许粘贴」、弹框里写的是谁的名字。
/// ① changeCount：只问剪贴板换没换过；② hasStrings：只问里面有没有文字；③ string：真正读出内容。
/// 键盘弹出时不自动读，只有点按钮才读，方便分清是哪一下弹的框。
struct ClipboardProbeStrip: View {
    @State private var result = "点一个按钮，看会不会弹「允许粘贴」"

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                probeButton("① changeCount") {
                    "changeCount = \(UIPasteboard.general.changeCount)"
                }
                probeButton("② hasStrings") {
                    "hasStrings = \(UIPasteboard.general.hasStrings)"
                }
                probeButton("③ 读内容") {
                    let text = UIPasteboard.general.string
                    return text.map { "string = \(String($0.prefix(30)))" } ?? "string = nil（没读到或被拒绝）"
                }
            }
            Text(result)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.82)))
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private func probeButton(_ title: String, _ read: @escaping () -> String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white))
            .onTapGesture {
                let start = Date()
                let text = read()
                result = "\(text)（\(Int(Date().timeIntervalSince(start) * 1000))ms）"
            }
    }
}
