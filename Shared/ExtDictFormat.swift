import Foundation

/// 扩展词库（B6）的文件格式：读细胞词库（.scel）和 Rime 词库（.dict.yaml），统一写成 Rime 词库，
/// 部署时接进 enclave.dict.yaml 的 import_tables。全在本机做，不联网。
enum ExtDictFormat {
    struct Entry: Equatable {
        var word: String
        var code: String
        var weight: Int
    }

    struct Parsed {
        /// 细胞词库里写的词库名；Rime 词库没有。
        var title: String?
        var entries: [Entry]
    }

    enum ParseError: Error, Equatable {
        /// 不是细胞词库也不是 Rime 词库。
        case unsupported
        /// 格式对，但一个带拼音的词都没读到。
        case empty
    }

    /// 按后缀认格式；后缀不对或内容读不出词都算失败。
    static func parse(_ data: Data, fileName: String) throws -> Parsed {
        let lower = fileName.lowercased()
        let parsed: Parsed
        if lower.hasSuffix(".scel") {
            parsed = try parseScel(data)
        } else if lower.hasSuffix(".dict.yaml") || lower.hasSuffix(".yaml") || lower.hasSuffix(".txt") {
            guard let text = String(data: data, encoding: .utf8) else { throw ParseError.unsupported }
            parsed = Parsed(title: nil, entries: parseRime(text))
        } else {
            throw ParseError.unsupported
        }
        guard !parsed.entries.isEmpty else { throw ParseError.empty }
        return parsed
    }

    // MARK: - 细胞词库（.scel）

    /// 细胞词库的结构（公开格式说明，自己实现）：
    /// 0x130 起 UTF-16LE 词库名；0x1540 起拼音表（音节编号 → 音节）；0x2628 起词条，
    /// 每组是同一串拼音的若干个词：词数、拼音编号串、再逐个是词（UTF-16LE）和附加信息（前两字节是词频）。
    static func parseScel(_ data: Data) throws -> Parsed {
        let bytes = [UInt8](data)
        let pinyinStart = 0x1540, wordStart = 0x2628
        guard bytes.count > wordStart, bytes[0] == 0x40, bytes[1] == 0x15, bytes[2] == 0, bytes[3] == 0 else {
            throw ParseError.unsupported
        }
        func u16(_ offset: Int) -> Int? {
            offset + 1 < bytes.count ? Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 : nil
        }
        func utf16(_ offset: Int, _ length: Int) -> String? {
            guard length >= 0, offset + length <= bytes.count, length % 2 == 0 else { return nil }
            let units = stride(from: offset, to: offset + length, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
            return String(utf16CodeUnits: units, count: units.count)
        }
        let title = utf16(0x130, 0x338 - 0x130)?.components(separatedBy: "\0").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var syllables: [Int: String] = [:]
        var offset = pinyinStart + 4
        let syllableCount = u16(pinyinStart) ?? 0
        while syllables.count < syllableCount, offset < wordStart, let index = u16(offset), let length = u16(offset + 2),
              let text = utf16(offset + 4, length) {
            syllables[index] = text
            offset += 4 + length
        }
        guard !syllables.isEmpty else { throw ParseError.unsupported }

        var raw: [(word: String, code: String, freq: Int)] = []
        offset = wordStart
        while let same = u16(offset), let codeLength = u16(offset + 2), same > 0 {
            offset += 4
            let indexes = stride(from: offset, to: offset + codeLength, by: 2).compactMap(u16)
            offset += codeLength
            let parts = indexes.map { syllables[$0] }
            let code = parts.contains(nil) ? nil : normalizeCode(parts.compactMap { $0 }.joined(separator: " "))
            var complete = true
            for _ in 0..<same {
                guard let wordLength = u16(offset), let word = utf16(offset + 2, wordLength),
                      let extLength = u16(offset + 2 + wordLength) else { complete = false; break }
                let freq = extLength >= 2 ? u16(offset + 4 + wordLength) ?? 0 : 0
                offset += 4 + wordLength + extLength
                if let code, isWord(word) { raw.append((word, code, freq)) }
            }
            if !complete || offset > bytes.count { break }
        }
        let top = raw.map(\.freq).max() ?? 0
        return Parsed(title: title?.isEmpty == false ? title : nil,
                      entries: dedupe(raw.map { Entry(word: $0.word, code: $0.code, weight: weight(freq: $0.freq, top: top)) }))
    }

    // MARK: - Rime 词库（.dict.yaml）

    /// 读「...」之后的词条：词 \t 拼音 [\t 词频]。拼音带声调的（万象格式）去掉声调；没有拼音的行跳过。
    static func parseRime(_ text: String) -> [Entry] {
        var lines = text.components(separatedBy: .newlines)
        if let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "..." }) {
            lines.removeSubrange(...end)
        }
        var raw: [(word: String, code: String, freq: Int)] = []
        for line in lines where !line.isEmpty && !line.hasPrefix("#") {
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 2, isWord(fields[0]), let code = normalizeCode(fields[1]) else { continue }
            let freq = fields.count > 2 ? Int(fields[2].prefix { $0.isNumber }) ?? 0 : 0
            raw.append((fields[0], code, freq))
        }
        let top = raw.map(\.freq).max() ?? 0
        return dedupe(raw.map { Entry(word: $0.word, code: $0.code, weight: weight(freq: $0.freq, top: top)) })
    }

    /// 去声调、ü 写成 v、全小写，音节之间一个空格；不是纯拼音字母的返回 nil。
    static func normalizeCode(_ code: String) -> String? {
        // 先拆开组合字符，ü、ǜ 这类都变成 u + 分音符，再换成 v；剩下的声调符号去掉。
        let folded = code.decomposedStringWithCanonicalMapping
            // .literal：按 Unicode 标量比，不然 ǜ 拆成的 u + ¨ + ` 是一个字形，「u + ¨」匹配不上。
            .replacingOccurrences(of: "u\u{308}", with: "v", options: .literal).replacingOccurrences(of: "U\u{308}", with: "v", options: .literal)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "'" })
            .joined(separator: " ")
        guard !folded.isEmpty, folded.allSatisfy({ ("a"..."z").contains($0) || $0 == " " }) else { return nil }
        return folded
    }

    /// 只收汉字词（可以夹·），英文、数字、符号交给别的词库。
    static func isWord(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 20 && text.unicodeScalars.allSatisfy { scalar in
            scalar == "·" || (0x3400...0x9FFF).contains(scalar.value) || (0x20000...0x2FFFF).contains(scalar.value)
        }
    }

    /// 词频压到 1–9：按对数，最常用的 9。万象基础词库的词频都在 60 以上，扩展词不抢首选。
    static func weight(freq: Int, top: Int) -> Int {
        guard top > 1 else { return 5 }
        // 词频都在 1–9 以内：已经是压过的（自己写出的扩展词库），原样留着，读回来不变。
        if top <= 9 { return max(1, freq) }
        let scaled = 1 + 8 * log(Double(max(freq, 0) + 1)) / log(Double(top + 1))
        return max(1, min(9, Int(scaled.rounded())))
    }

    private static func dedupe(_ entries: [Entry]) -> [Entry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.word + "\t" + $0.code).inserted }
    }

    // MARK: - 写文件、接进部署

    /// 写成 Rime 词库，词库名 ext_<id>。
    static func rimeText(_ entries: [Entry], id: String, source: String, version: String) -> String {
        var text = "# 飞地输入法扩展词库 · 来源：\(source)\n---\nname: ext_\(id)\nversion: \"\(version)\"\nsort: by_weight\n...\n"
        for entry in entries {
            text += "\(entry.word)\t\(entry.code)\t\(entry.weight)\n"
        }
        return text
    }

    /// 词库文件里的词条数（「...」后面的非空非注释行）。
    static func entryCount(_ text: String) -> Int {
        guard let end = text.range(of: "\n...\n") else { return 0 }
        return text[end.upperBound...].split(separator: "\n").filter { !$0.hasPrefix("#") }.count
    }

    /// 在 import_tables 列表最后加上扩展词库（tables 是相对共享目录的路径，不带 .dict.yaml）。找不到列表就原样返回。
    static func patchImportTables(_ text: String, tables: [String]) -> String {
        guard !tables.isEmpty, let header = text.range(of: "\nimport_tables:\n") else { return text }
        var insertAt = header.upperBound
        var rest = text[insertAt...]
        while rest.hasPrefix("  - "), let newline = rest.firstIndex(of: "\n") {
            insertAt = text.index(after: newline)
            rest = text[insertAt...]
        }
        var patched = text
        patched.insert(contentsOf: tables.map { "  - \($0)\n" }.joined(), at: insertAt)
        return patched
    }
}
