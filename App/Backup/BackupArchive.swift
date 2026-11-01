import Compression
import Foundation

/// 备份文件（.enclave）就是一个 zip 包（B3）：系统没有现成的 zip 读写接口，这里自己写一个最小的。
/// 写：每个文件原样存（不压缩），文件名 UTF-8；读：认原样存和 deflate（用户拿别的工具重新打包过也能读），校验 CRC。
/// 不支持 zip64、加密、分卷，备份文件用不到。
enum BackupArchive {
    struct Error: Swift.Error, Equatable {
        let reason: String
    }

    static func write(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        let (time, date) = dosTimestamp(Date())
        for file in files {
            let name = Data(file.name.utf8)
            let crc = crc32(file.data)
            let offset = UInt32(out.count)
            // 本地文件头
            out.append(le32(0x0403_4B50))
            out.append(le16(20))          // 解压需要的版本
            out.append(le16(0x0800))      // 文件名是 UTF-8
            out.append(le16(0))           // 原样存
            out.append(le16(time))
            out.append(le16(date))
            out.append(le32(crc))
            out.append(le32(UInt32(file.data.count)))
            out.append(le32(UInt32(file.data.count)))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))
            out.append(name)
            out.append(file.data)
            // 中央目录里的这一项
            central.append(le32(0x0201_4B50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(0x0800))
            central.append(le16(0))
            central.append(le16(time))
            central.append(le16(date))
            central.append(le32(crc))
            central.append(le32(UInt32(file.data.count)))
            central.append(le32(UInt32(file.data.count)))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        // 中央目录结束
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(files.count)))
        out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    /// 读出全部文件：文件名 → 内容。不是 zip、内容坏了抛 Error。
    static func read(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw Error(reason: "too short") }
        // 从后往前找中央目录结束标记（后面可能有最长 65535 字节的注释）。
        var end = -1
        var index = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while index >= lowest {
            if u32(bytes, index) == 0x0605_4B50 {
                end = index
                break
            }
            index -= 1
        }
        guard end >= 0 else { throw Error(reason: "not a zip") }
        let count = Int(u16(bytes, end + 10))
        var cursor = Int(u32(bytes, end + 16))
        var files: [String: Data] = [:]
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, u32(bytes, cursor) == 0x0201_4B50 else { throw Error(reason: "bad directory") }
            let method = u16(bytes, cursor + 10)
            let crc = u32(bytes, cursor + 16)
            let compressedSize = Int(u32(bytes, cursor + 20))
            let size = Int(u32(bytes, cursor + 24))
            let nameLength = Int(u16(bytes, cursor + 28))
            let extraLength = Int(u16(bytes, cursor + 30))
            let commentLength = Int(u16(bytes, cursor + 32))
            let localOffset = Int(u32(bytes, cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw Error(reason: "bad name") }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x0403_4B50 else { throw Error(reason: "bad entry") }
            let start = localOffset + 30 + Int(u16(bytes, localOffset + 26)) + Int(u16(bytes, localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw Error(reason: "truncated") }
            let stored = Data(bytes[start..<(start + compressedSize)])
            if name.hasSuffix("/") { continue }
            let content: Data
            switch method {
            case 0: content = stored
            case 8: content = try inflate(stored, size: size)
            default: throw Error(reason: "unsupported method \(method)")
            }
            guard content.count == size, crc32(content) == crc else { throw Error(reason: "checksum") }
            files[name] = content
        }
        return files
    }

    // MARK: - 内部

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB 就是 zip 里的原始 deflate（不带 zlib 头）。
                return compression_decode_buffer(dstBase, size, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Error(reason: "inflate") }
        return output
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let year: Int = max(0, (c.year ?? 1980) - 1980), month: Int = c.month ?? 1, day: Int = c.day ?? 1
        let time: Int = (hour << 11) + (minute << 5) + second / 2
        let dosDate: Int = (year << 9) + (month << 5) + day
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: dosDate))
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        let low = UInt16(b[i]), high = UInt16(b[i + 1])
        return low | (high << 8)
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        let b0 = UInt32(b[i]), b1 = UInt32(b[i + 1]), b2 = UInt32(b[i + 2]), b3 = UInt32(b[i + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
