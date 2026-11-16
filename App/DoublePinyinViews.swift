import Photos
import SwiftUI

// 「双拼方案」页上的几块（双拼调研 P1–P2，设计稿 SP5、SP8）：零声母卡、键位图、存到相册。

/// 小键帽：白底圆角、等宽字母。零声母卡、练习页、键位图都用。
struct MiniKeycap: View {
    let letter: String
    var size: CGFloat = 13
    var fill: Color = Color(.systemBackground)
    var stroke: Color = Color(.separator)

    var body: some View {
        Text(letter)
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .frame(minWidth: size * 1.45, minHeight: size * 1.6)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(stroke, lineWidth: 0.5))
    }
}

/// 零声母卡（SP5 ②）：12 个字排 4 列，每格「字 + 两颗小键帽」；分隔线下面灰字写「首字母 + 韵母键」的另一种按法和 ü 打 v。
struct ZeroInitialCard: View {
    let scheme: DoublePinyin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("零声母（没有声母的字）", "Syllables without an initial", "声母のない音節"))
                    .font(.headline)
                Text(L("按两下：第一下按韵母的首字母，第二下照常按韵母", "Two keys: the first letter of the final, then the final as usual",
                       "2 回押します：1 回目は韻母の先頭の文字、2 回目はいつもどおり韻母"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(scheme.zeroInitialExamples, id: \.syllable) { example in
                    HStack(spacing: 4) {
                        Text(example.example).font(.system(size: 16))
                        Spacer(minLength: 2)
                        ForEach(Array(example.code.enumerated()), id: \.offset) { _, key in MiniKeycap(letter: String(key), size: 11) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemBackground)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(example.example) \(example.code)")
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                (Text(L("也可以按「首字母 + 韵母键」：", "Also works as first letter + final key: ", "「先頭の文字 + 韻母のキー」でも OK：")) + Self.pairs(alternates) + Text(L("。", ".", "。")))
                (Text(L("j、q、x、y 后面的 ü 可以按 v：", "After j, q, x, y, ü can be typed as v: ", "j・q・x・y のあとの ü は v でも OK：")) + Self.pairs([("jv", "ju"), ("xv", "xu")]) + Text(L("。", ".", "。")))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var alternates: [(String, String)] {
        scheme.zeroInitialExamples.flatMap { example in example.alternates.map { ($0, example.syllable) } }
    }

    /// 「ad=ai、aj=an」：按键加粗等宽。
    static func pairs(_ items: [(String, String)]) -> Text {
        var text = Text("")
        for (index, item) in items.enumerated() {
            if index > 0 { text = text + Text(L("、", ", ", "、")) }
            text = text + Text(item.0).font(.footnote.weight(.bold).monospaced()).foregroundColor(.primary) + Text("=\(item.1)")
        }
        return text
    }
}

/// 存到相册的键位图（SP8）：竖图，宽 600pt 按 2 倍出图 = 1200 像素，跟着当前方案和深浅色。
struct DoublePinyinKeymapPoster: View {
    let scheme: DoublePinyin
    let dark: Bool

    static let width: CGFloat = 600

    /// 出图：在主线程用 ImageRenderer 画。
    @MainActor
    static func render(scheme: DoublePinyin, dark: Bool) -> UIImage? {
        let renderer = ImageRenderer(content: DoublePinyinKeymapPoster(scheme: scheme, dark: dark)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.uiImage
    }

    private var page: Color { dark ? Color(white: 0.07) : Color(red: 0.98, green: 0.98, blue: 0.99) }
    private var keyFill: Color { dark ? Color(white: 0.28) : .white }
    private var board: Color { dark ? Color(white: 0.17) : Color(red: 0.89, green: 0.89, blue: 0.91) }
    private var text: Color { dark ? .white : .black }
    private var sub: Color { dark ? Color(white: 0.62) : Color(white: 0.45) }
    private var purple: Color { dark ? Color(red: 0xB4 / 255, green: 0xA9 / 255, blue: 1) : Color(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255) }
    private var cellStroke: Color { dark ? Color(white: 0.25) : Color(white: 0.88) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("\(scheme.title) 键位图", "\(scheme.title) layout", "\(scheme.title) キー配置"))
                    .font(.system(size: 30, weight: .heavy))
                Text(L("每个字按两下：第一下声母，第二下韵母。紫色是 zh / ch / sh，灰字是这个键的韵母。",
                       "Two keys per character: initial, then final. Purple is zh / ch / sh; gray is the key's finals.",
                       "1 文字 2 キー：1 回目が声母、2 回目が韻母。紫は zh / ch / sh、灰色はそのキーの韻母。"))
                    .font(.system(size: 12.5)).foregroundStyle(sub)
            }
            keyboard
            VStack(alignment: .leading, spacing: 10) {
                Text(L("零声母（没有声母的字）", "Syllables without an initial", "声母のない音節")).font(.system(size: 15, weight: .bold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 6), spacing: 7) {
                    ForEach(scheme.zeroInitialExamples, id: \.syllable) { example in
                        VStack(spacing: 3) {
                            Text(example.example).font(.system(size: 18))
                            Text(example.code).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(purple)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(keyFill))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(cellStroke, lineWidth: 1))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L("记住这几条", "Remember", "覚えておくこと")).font(.system(size: 15, weight: .bold))
                Group {
                    bullet(Text(L("b p m f d t n l g k h j q x r z c s y w 这些声母就按本键。",
                                  "Initials b p m f d t n l g k h j q x r z c s y w are their own keys.",
                                  "声母 b p m f d t n l g k h j q x r z c s y w はそのままのキー。")))
                    bullet(Text(L("单个韵母按两下（", "Single vowels twice (", "単母音は 2 回（")) + codes([("aa", "啊"), ("ee", "鹅"), ("oo", "哦")])
                        + Text(L("）；ang、eng 按首字母 + 韵母键（", "); ang, eng as first letter + final key (", "）。ang・eng は先頭の文字 + 韻母のキー（"))
                        + codes([("ah", "昂"), ("eg", "鞥")]) + Text(L("）。", ").", "）。")))
                    bullet(Text(L("也可以按「首字母 + 韵母键」：", "Also first letter + final key: ", "「先頭の文字 + 韻母のキー」でも OK："))
                        + codes(scheme.zeroInitialExamples.flatMap { example in example.alternates.map { ($0, "=" + example.syllable) } }) + Text(L("。", ".", "。")))
                    bullet(Text(L("j q x y 后面的 ü 可以按 v（", "After j q x y, ü can be v (", "j q x y のあとの ü は v でも OK（")) + codes([("jv", "=ju")]) + Text(L("）。", ").", "）。")))
                    bullet(Text(L("例：你好 = ", "e.g. 你好 = ", "例：你好 = ")) + example(["ni", "hao"]) + Text(L("，双拼 = ", ", 双拼 = ", "、双拼 = ")) + example(["shuang", "pin"]) + Text(L("。", ".", "。")))
                }
                .font(.system(size: 13))
                .foregroundStyle(sub)
            }
            Rectangle().fill(cellStroke).frame(height: 1)
            HStack {
                Text(L("飞地输入法 · 双拼", "Enclave · Double pinyin", "Enclave · 双拼"))
                Spacer()
                Text(L("设置 › 键盘 › 双拼方案", "Keyboard › Double pinyin", "キーボード › 双拼"))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(sub)
        }
        .foregroundStyle(text)
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
        .frame(width: Self.width)
        .background(page)
    }

    private var keyboard: some View {
        VStack(spacing: 7) {
            ForEach(["qwertyuiop", "asdfghjkl", "zxcvbnm"], id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(Array(row), id: \.self) { letter in
                        posterKey(letter).frame(width: 47)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(board))
    }

    private func posterKey(_ letter: Character) -> some View {
        let lines = scheme.keyHints[letter] ?? []
        return VStack(spacing: 0) {
            ForEach(lines, id: \.self) { line in
                let initial = ["zh", "ch", "sh"].contains(line)
                Text(line)
                    .font(.system(size: 9.5, weight: initial ? .bold : .medium))
                    .foregroundStyle(initial ? purple : sub)
            }
            Spacer(minLength: 0)
            Text(String(letter)).font(.system(size: 22))
        }
        .padding(.top, 5)
        .padding(.bottom, 6)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(keyFill))
    }

    private func bullet(_ content: Text) -> some View {
        (Text("· ") + content).fixedSize(horizontal: false, vertical: true)
    }

    /// 「aa 啊、ee 鹅」：按键加粗。
    private func codes(_ items: [(String, String)]) -> Text {
        var out = Text("")
        for (index, item) in items.enumerated() {
            if index > 0 { out = out + Text(L("、", ", ", "、")) }
            out = out + Text(item.0).bold().foregroundColor(text) + Text(item.1.hasPrefix("=") ? item.1 : " " + item.1)
        }
        return out
    }

    /// 「ni + hc」。
    private func example(_ syllables: [String]) -> Text {
        let parts = syllables.compactMap(scheme.code(for:))
        return Text(parts.joined(separator: " + ")).bold().foregroundColor(text)
    }
}

/// 把图存进相册：只要「添加照片」权限（不读相册）。completion 在主线程回调。
enum PhotoSaver {
    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            })
        }
    }
}
