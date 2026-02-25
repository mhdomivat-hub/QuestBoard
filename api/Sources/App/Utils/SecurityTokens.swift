import Foundation
import Crypto
import Vapor

func sha256Hex(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func generateOpaqueToken(byteCount: Int = 32) -> String {
    let bytes = [UInt8].random(count: byteCount)
    let data = Data(bytes)
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
