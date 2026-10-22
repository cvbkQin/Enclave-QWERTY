import SwiftUI

/// 九宫格拼音：左边一列常用标点，中间 3×3 数字键，右边删除、重输、分词。
struct NineKeyView: View {
    @ObservedObject var model: KeyboardModel
    var spacing: CGFloat
    var rowHeight: CGFloat

    private static let keys: [[(digit: String, letters: String)]] = [
        [("1", "分词"), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
    ]

    private static let punctuation = ["，", "。", "？", "！", "、", "：", "…", "～", "；", "“", "”"]

    var body: some View {
        GeometryReader { geo in
            let side = (geo.size.width - spacing * 4) * 0.17
            HStack(spacing: spacing) {
                punctuationColumn
                    .frame(width: side)
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(Self.keys[row], id: \.digit) { key in
                                digitKey(key.digit, letters: key.letters)
                            }
                        }
                        .frame(height: rowHeight)
                    }
                }
                VStack(spacing: 8) {
                    RepeatingKey(systemImage: "delete.left") { model.deleteKey() }
                    FunctionKey(title: "重输") { model.clearComposition() }
                    FunctionKey(title: "0") { model.typeSymbol("0") }
                }
                .frame(width: side)
            }
        }
    }

    private var punctuationColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Self.punctuation, id: \.self) { mark in
                    Button { model.typeSymbol(mark) } label: {
                        Text(mark)
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                    .foregroundStyle(Color.primary)
                }
            }
        }
        .hidingScrollEdgeEffect()
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray3)))
    }

    private func digitKey(_ digit: String, letters: String) -> some View {
        Button {
            // 1 键是分词符，把连在一起的拼音切开，比如 xi'an。
            model.typeNineKey(digit == "1" ? "'" : digit)
        } label: {
            Text(letters)
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color.primary)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground)))
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(KeyPressStyle())
    }
}
