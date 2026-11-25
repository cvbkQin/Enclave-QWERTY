import Foundation

/// 简体转繁体（B5 繁体输出）。词表是 OpenCC 的 s2t（ver.1.1.9，Apache-2.0），由 scripts/build-s2t.py 整理成
/// Shared/Traditional/s2t-phrases.tsv、s2t-chars.tsv，随 App 打包，不联网。
/// 转法和 OpenCC 默认的 s2t 一样：从左往右，每个位置先找词表里最长的词（「头发」→「頭髮」、「干净」→「乾淨」），
/// 找不到再按单字转，单字有几个繁体时取 OpenCC 排第一的。
/// 词表 1 MB，按简体的 UTF-8 字节排好序，内存映射着二分查找，不整张读进内存（键盘扩展内存紧）；单字表 4 千条读进字典。
/// 词库和学习数据仍然按简体存，只在显示候选、联想和上屏时转换。
enum TraditionalChinese {
    private final class BundleMarker {}

    private static let lock = NSLock()
    private static var loaded = false
    private static var tables: Tables?
    /// 候选栏每次刷新都把几十个词转一遍，同样的词不用重新查。
    private static var cache: [String: String] = [:]

    /// 转成繁体；没有汉字的原样返回（英文、数字、符号不查表）。
    static func convert(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isHan) else { return text }
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[text] { return hit }
        if !loaded {
            loaded = true
            tables = Tables.load(from: Bundle(for: BundleMarker.self))
        }
        guard let tables else { return text }
        let result = tables.convert(text)
        if cache.count > 4000 { cache.removeAll(keepingCapacity: true) }
        cache[text] = result
        return result
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: return true
        default: return false
        }
    }

    private struct Tables {
        let chars: [Character: String]
        /// 词表原文（内存映射），每行「简体\t繁体\n」。
        let phrases: Data
        /// 每行开头的字节位置。
        let lineStarts: [Int32]
        /// 词表里最长的词有几个字。
        let maxLength: Int

        static func load(from bundle: Bundle) -> Tables? {
            guard let charsURL = bundle.url(forResource: "s2t-chars", withExtension: "tsv"),
                  let phrasesURL = bundle.url(forResource: "s2t-phrases", withExtension: "tsv"),
                  let charsText = try? String(contentsOf: charsURL, encoding: .utf8),
                  let phrases = try? Data(contentsOf: phrasesURL, options: .alwaysMapped) else { return nil }
            var chars: [Character: String] = [:]
            chars.reserveCapacity(4000)
            for line in charsText.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2, let key = parts[0].first, parts[0].count == 1 else { continue }
                chars[key] = String(parts[1])
            }
            var starts: [Int32] = []
            starts.reserveCapacity(50_000)
            var maxLength = 1
            phrases.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let bytes = raw.bindMemory(to: UInt8.self)
                var index = 0
                var lineStart = 0
                var keyChars = 0
                var inKey = true
                while index < bytes.count {
                    let byte = bytes[index]
                    if byte == 0x0A {
                        if index > lineStart { starts.append(Int32(lineStart)) }
                        lineStart = index + 1
                        keyChars = 0
                        inKey = true
                    } else if inKey {
                        if byte == 0x09 {
                            inKey = false
                            maxLength = max(maxLength, keyChars)
                        } else if byte & 0xC0 != 0x80 {
                            // UTF-8 的首字节：数字数（续字节 10xxxxxx 不算）。
                            keyChars += 1
                        }
                    }
                    index += 1
                }
                if index > lineStart { starts.append(Int32(lineStart)) }
            }
            return Tables(chars: chars, phrases: phrases, lineStarts: starts, maxLength: maxLength)
        }

        func convert(_ text: String) -> String {
            let characters = Array(text)
            var output = ""
            output.reserveCapacity(text.utf8.count)
            var i = 0
            while i < characters.count {
                var matched = false
                let longest = min(maxLength, characters.count - i)
                if longest >= 2 {
                    for length in stride(from: longest, through: 2, by: -1) {
                        if let value = lookup(String(characters[i..<(i + length)])) {
                            output += value
                            i += length
                            matched = true
                            break
                        }
                    }
                }
                if !matched {
                    let character = characters[i]
                    output += chars[character] ?? String(character)
                    i += 1
                }
            }
            return output
        }

        /// 二分查找词表：按简体的 UTF-8 字节比较。
        private func lookup(_ key: String) -> String? {
            let target = Array(key.utf8)
            return phrases.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
                let bytes = raw.bindMemory(to: UInt8.self)
                var low = 0
                var high = lineStarts.count - 1
                while low <= high {
                    let mid = (low + high) / 2
                    let start = Int(lineStarts[mid])
                    // 比较这一行的简体（到 \t 为止）和要找的词。
                    var position = start
                    var k = 0
                    var order = 0
                    while true {
                        let lineEnded = position >= bytes.count || bytes[position] == 0x09
                        if k == target.count {
                            order = lineEnded ? 0 : 1
                            break
                        }
                        if lineEnded {
                            order = -1
                            break
                        }
                        let a = bytes[position], b = target[k]
                        if a != b {
                            order = a < b ? -1 : 1
                            break
                        }
                        position += 1
                        k += 1
                    }
                    if order == 0 {
                        // position 停在 \t 上，值到行尾为止。
                        var end = position + 1
                        while end < bytes.count, bytes[end] != 0x0A { end += 1 }
                        return String(decoding: UnsafeBufferPointer(rebasing: bytes[(position + 1)..<end]), as: UTF8.self)
                    }
                    if order < 0 { low = mid + 1 } else { high = mid - 1 }
                }
                return nil
            }
        }
    }
}
