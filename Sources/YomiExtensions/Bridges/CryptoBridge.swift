import Foundation
import JavaScriptCore
import CryptoKit
import CommonCrypto

public enum CryptoBridge {
    /// Injects cryptographic helpers into JavaScriptCore.
    public static func inject(into context: JSContext) {
        
        // SHA-256 hash helper
        let sha256Block: @convention(block) (String) -> String = { input in
            guard let data = input.data(using: .utf8) else { return "" }
            let digest = SHA256.hash(data: data)
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        }
        context.setObject(sha256Block, forKeyedSubscript: "__yomi_sha256" as NSString)

        // MD5 hash helper
        let md5Block: @convention(block) (String) -> String = { input in
            guard let data = input.data(using: .utf8) else { return "" }
            var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            data.withUnsafeBytes { buffer in
                _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
            }
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        context.setObject(md5Block, forKeyedSubscript: "__yomi_md5" as NSString)

        // Base64 Decode helper
        let base64DecodeBlock: @convention(block) (String) -> String = { encoded in
            guard let data = Data(base64Encoded: encoded),
                  let str = String(data: data, encoding: .utf8) else { return "" }
            return str
        }
        context.setObject(base64DecodeBlock, forKeyedSubscript: "__yomi_base64Decode" as NSString)

        // Base64 Encode helper
        let base64EncodeBlock: @convention(block) (String) -> String = { plain in
            guard let data = plain.data(using: .utf8) else { return "" }
            return data.base64EncodedString()
        }
        context.setObject(base64EncodeBlock, forKeyedSubscript: "__yomi_base64Encode" as NSString)
    }
}
