import Foundation

/// 纠错用的「按键串 → 可能性」表：词库最常用的 30 万词，按拼音连写（全键盘）或九宫格数字做键。
/// 由 scripts/correction/build_keylm.py 生成到 Vendor/KeyLM/，格式见那里；参考实现是 scripts/correction/corrector_ref.py。
/// 整份文件只读映射（mmap），不读进内存，不挤占键盘扩展的内存上限。不是线程安全的（查过的结果记在 memo 里）。
final class KeyLM {
    private let base: UnsafeRawPointer
    private let length: Int
    private let count: Int
    private let blockSize: Int
    private let blockCount: Int
    private let dataStart: Int
    /// 查过的串（≤ 12 个键时压成一个整数做键），一次按键里各种改法会反复查同样的段。
    private var memo: [UInt64: Entry] = [:]

    struct Entry {
        /// 这个串本身是一个词的键时的 cost，不是时为 nil。
        var exact: Double?
        /// 以这个串开头的词里最小的 cost；为 nil 时说明没有哪个词以它开头，逐段查表可以停了。
        var prefix: Double?
    }

    /// 词库自带的表：键盘扩展里是自己包里的 KeyLM/，App 里去 PlugIns 下的键盘扩展里找。
    static func bundled(nineKey: Bool) -> KeyLM? {
        let name = nineKey ? "t9.eklm" : "qw.eklm"
        var roots = [Bundle.main.bundleURL]
        if let plugins = Bundle.main.builtInPlugInsURL,
           let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) {
            roots += items.filter { $0.pathExtension == "appex" }
        }
        for root in roots {
            if let lm = KeyLM(url: root.appendingPathComponent("KeyLM").appendingPathComponent(name)) { return lm }
        }
        return nil
    }

    init?(url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 16 else { return nil }
        let length = Int(info.st_size)
        guard let mapped = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0), mapped != MAP_FAILED else { return nil }
        let base = UnsafeRawPointer(mapped)
        guard base.load(as: UInt8.self) == 0x45, (base + 1).load(as: UInt8.self) == 0x4B,
              (base + 2).load(as: UInt8.self) == 0x4C, (base + 3).load(as: UInt8.self) == 0x31 else {
            munmap(mapped, length)
            return nil
        }
        self.base = base
        self.length = length
        count = Int(Self.u32(base, 4))
        blockSize = Int(Self.u32(base, 8))
        blockCount = Int(Self.u32(base, 12))
        dataStart = 16 + 4 * blockCount
        guard blockCount > 0, dataStart <= length else {
            munmap(mapped, length)
            return nil
        }
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: base), length)
    }

    private static func u32(_ base: UnsafeRawPointer, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 { value |= UInt32((base + offset + index).load(as: UInt8.self)) << (8 * index) }
        return value
    }

    private func byte(_ offset: Int) -> UInt8 { (base + offset).load(as: UInt8.self) }

    private static func cost(_ value: UInt8) -> Double? {
        value == 255 ? nil : 2.0 + Double(value) * 0.05
    }

    /// 和一段内存比大小（字节序）：<0 内存里的小，0 相等，>0 内存里的大。
    private func compare(_ offset: Int, _ count: Int, _ key: ArraySlice<UInt8>) -> Int {
        var index = 0
        var position = key.startIndex
        while index < count && position < key.endIndex {
            let a = byte(offset + index), b = key[position]
            if a != b { return a < b ? -1 : 1 }
            index += 1
            position += 1
        }
        return count - key.count
    }

    func lookup(_ key: ArraySlice<UInt8>) -> Entry {
        let packed = key.count <= 12 ? Self.pack(key) : nil
        if let packed, let hit = memo[packed] { return hit }
        let found = find(key)
        if let packed {
            if memo.count > 200_000 { memo.removeAll(keepingCapacity: true) }
            memo[packed] = found
        }
        return found
    }

    private static func pack(_ key: ArraySlice<UInt8>) -> UInt64 {
        key.reduce(UInt64(0)) { $0 << 5 | UInt64($1 & 31) }
    }

    private func find(_ key: ArraySlice<UInt8>) -> Entry {
        // 先在每块的第一条上二分，找到最后一个 ≤ key 的块。
        var low = 0, high = blockCount - 1
        while low < high {
            let mid = (low + high + 1) / 2
            let offset = dataStart + Int(Self.u32(base, 16 + 4 * mid))
            if compare(offset + 2, Int(byte(offset + 1)), key) <= 0 { low = mid } else { high = mid - 1 }
        }
        var offset = dataStart + Int(Self.u32(base, 16 + 4 * low))
        var current: [UInt8] = []
        for index in 0..<blockSize where low * blockSize + index < count {
            let shared = Int(byte(offset)), suffix = Int(byte(offset + 1))
            current.removeSubrange(min(shared, current.count)...)
            for position in 0..<suffix { current.append(byte(offset + 2 + position)) }
            let exact = byte(offset + 2 + suffix), prefix = byte(offset + 3 + suffix)
            offset += 4 + suffix
            if current.elementsEqual(key) { return Entry(exact: Self.cost(exact), prefix: Self.cost(prefix)) }
            if current.lexicographicallyPrecedes(key) { continue }
            break
        }
        return Entry()
    }

    /// 整串拆成词的最小 cost（词级 Viterbi）；partial 时最后一个词可以没打完（最多 8 个键），用前缀 cost。拼不出时为 .infinity。
    func score(_ keys: [UInt8], partial: Bool = true) -> Double {
        let n = keys.count
        var best = [Double](repeating: .infinity, count: n + 1)
        best[0] = 0
        for i in 0..<n where best[i] < .infinity {
            for j in (i + 1)...n {
                let entry = lookup(keys[i..<j])
                guard entry.prefix != nil else { break }
                if let exact = entry.exact, best[i] + exact < best[j] { best[j] = best[i] + exact }
            }
        }
        var result = best[n]
        if partial {
            for i in max(0, n - 8)..<n where best[i] < .infinity {
                if let prefix = lookup(keys[i..<n]).prefix, best[i] + prefix < result { result = best[i] + prefix }
            }
        }
        return result
    }
}
