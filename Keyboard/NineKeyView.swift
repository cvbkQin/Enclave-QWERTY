import SwiftUI

/// 九宫格拼音，布局参照 iOS 自带九宫格：
/// 左边一列常用标点，中间 3×3 字母键（1 是分词），右边删除、重输和占两行高的换行键。
struct NineKeyView: View {
    @ObservedObject var model: KeyboardModel
    var width: CGFloat

    private static let keys: [[(digit: String, letters: String)]] = [
        [("1", "分词"), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
    ]

    private static let punctuation = ["，", "。", "？", "！", "、", "：", "…", "～", "；", "“", "”"]

    var body: some View {
        let side = width * 0.18
        let middle = (width - side * 2) / 3
        let slot = KeyboardMetrics.slotHeight
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                punctuationColumn.frame(height: slot * 3)
                FunctionKey(title: "123") { model.switchLayer(.numbers) }.frame(height: slot)
            }
            .frame(width: side)

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(Self.keys[row], id: \.digit) { key in
                            digitKey(key.digit, letters: key.letters).frame(width: middle)
                        }
                    }
                    .frame(height: slot)
                }
                HStack(spacing: 0) {
                    FunctionKey(title: model.chineseMode ? "中" : "英") { model.toggleChinese() }
                        .frame(width: middle)
                    CharKey(title: model.spaceTitle, font: KeyStyle.functionFont) { model.spaceKey() }
                }
                .frame(height: slot)
            }

            VStack(spacing: 0) {
                RepeatingKey(systemImage: "delete.left") { model.deleteKey() }.frame(height: slot)
                FunctionKey(title: "重输") { model.clearComposition() }.frame(height: slot)
                FunctionKey(title: model.returnTitle, highlighted: model.returnHighlighted) { model.returnKey() }
                    .frame(height: slot * 2)
            }
            .frame(width: side)
        }
    }

    private var punctuationColumn: some View {
        KeyCap(fill: KeyStyle.functionKey) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Self.punctuation, id: \.self) { mark in
                        Button { model.typeSymbol(mark) } label: {
                            Text(mark)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
            }
            .hidingScrollEdgeEffect()
        }
    }

    private func digitKey(_ digit: String, letters: String) -> some View {
        // 1 键是分词符，把连在一起的拼音切开，比如 xi'an。
        CharKey(title: letters, font: .system(size: 18, weight: .medium)) {
            model.typeNineKey(digit == "1" ? "'" : digit)
        }
    }
}
