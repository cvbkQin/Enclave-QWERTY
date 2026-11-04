import CommonCrypto
import CryptoKit
import Foundation

/// 备份文件里的接口 Key 加密（B3）：只用系统自带的库（出口合规声明不用改）。
/// 密码用 PBKDF2-HMAC-SHA256（随机 16 字节盐、310,000 次）派生 256 位密钥，再用 AES-GCM 加密；
/// 盐和次数写在 manifest 里，App 不保存密码。密码错了 AES-GCM 校验不过，open 返回 nil。
enum BackupCrypto {
    static let iterations = 310_000

    struct Sealed {
        var data: Data
        var salt: Data
        var iterations: Int
    }

    static func seal(_ plain: Data, password: String, iterations: Int = iterations) -> Sealed? {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess, let key = deriveKey(password: password, salt: salt, iterations: iterations),
              let box = try? AES.GCM.seal(plain, using: key), let combined = box.combined else { return nil }
        return Sealed(data: combined, salt: salt, iterations: iterations)
    }

    static func open(_ sealed: Sealed, password: String) -> Data? {
        guard let key = deriveKey(password: password, salt: sealed.salt, iterations: sealed.iterations),
              let box = try? AES.GCM.SealedBox(combined: sealed.data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey? {
        guard iterations > 0 else { return nil }
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int32 in
            salt.withUnsafeBytes { (saltBytes: UnsafeRawBufferPointer) -> Int32 in
                passwordData.withUnsafeBytes { (passwordBytes: UnsafeRawBufferPointer) -> Int32 in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordBytes.bindMemory(to: CChar.self).baseAddress, passwordData.count,
                                         saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         out.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: derived)
    }
}
