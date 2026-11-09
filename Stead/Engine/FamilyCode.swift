import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// A rotating 6-digit code shared by two family members, like a bank token.
/// The secret is exchanged in person (QR) and never leaves the two phones.
enum FamilyCode {
    /// Codes change every 60 seconds: long enough for an older person to type it in.
    static let step: TimeInterval = 60

    static func newSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func code(secret: Data, at date: Date = .now) -> String {
        code(secret: secret, counter: UInt64(date.timeIntervalSince1970 / step))
    }

    /// Seconds until the current code changes.
    static func secondsLeft(at date: Date = .now) -> Int {
        Int(step - date.timeIntervalSince1970.truncatingRemainder(dividingBy: step))
    }

    /// Accepts the current code and the one before/after, to allow for reading it out and typing.
    static func verify(_ input: String, secret: Data, at date: Date = .now) -> Bool {
        let digits = input.filter(\.isNumber)
        guard digits.count == 6 else { return false }
        let now = UInt64(date.timeIntervalSince1970 / step)
        return [now &- 1, now, now + 1].contains { code(secret: secret, counter: $0) == digits }
    }

    private static func code(secret: Data, counter: UInt64) -> String {
        var big = counter.bigEndian
        let message = Data(bytes: &big, count: 8)
        let mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let value = (UInt32(mac[offset] & 0x7f) << 24) | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8) | UInt32(mac[offset + 3])
        return String(format: "%06d", value % 1_000_000)
    }

    /// "482913" → "482 913"
    static func pretty(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }
}

/// Keeps family secrets in the Keychain, on this device only (never synced to iCloud).
enum SecretVault {
    private static let service = "com.qawi.stead.familycode"

    static func save(_ secret: Data, id: UUID) {
        delete(id: id)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: secret,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(id: UUID) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Face ID (or the passcode) before showing a family code.
enum OwnerCheck {
    static func confirm(reason: String) async -> Bool {
        #if targetEnvironment(simulator)
        return true // The simulator has no enrolled face; real devices always ask.
        #else
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        #endif
    }
}

/// What the QR code carries from the protected person's phone to the family member's phone.
struct PairingPayload: Codable, Equatable {
    let v: Int
    let id: UUID          // the pairing (one per family member)
    let protectedName: String
    let memberName: String
    let color: String
    let secret: Data
    /// Single-use Supabase invite code, so scanning also joins the family circle. Optional:
    /// older QRs and offline pairing have none. The family-code secret never goes to the server.
    var invite: String? = nil

    static let prefix = "STEAD1:"

    var encoded: String {
        let json = (try? JSONEncoder().encode(self)) ?? Data()
        return Self.prefix + json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> PairingPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        var b64 = String(trimmed.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONDecoder().decode(PairingPayload.self, from: data)
    }
}
