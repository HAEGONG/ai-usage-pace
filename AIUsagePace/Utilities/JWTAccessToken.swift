import CryptoKit
import Foundation

enum JWTAccessToken {
    enum ParseError: Error, Equatable {
        case malformed
        case missingSubject
        case emptyOrControlCharacters
        case expired
    }

    static let expiryLeeway: TimeInterval = 60

    static func payload(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            throw ParseError.malformed
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let data = Data(base64Encoded: payload),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ParseError.malformed
        }
        return json
    }

    static func rejectIfExpired(payload: [String: Any], now: Date) throws {
        let expiration: Date?
        if let value = payload["exp"] as? Double {
            expiration = Date(timeIntervalSince1970: value)
        } else if let value = payload["exp"] as? Int {
            expiration = Date(timeIntervalSince1970: TimeInterval(value))
        } else {
            expiration = nil
        }
        guard let expiration else { return }
        if expiration.timeIntervalSince(now) <= expiryLeeway {
            throw ParseError.expired
        }
    }

    static func fingerprint(for subject: String) -> String {
        let digest = SHA256.hash(data: Data(subject.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func rejectEmptyOrControlCharacters(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.emptyOrControlCharacters
        }
        let hasControl = value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        if hasControl {
            throw ParseError.emptyOrControlCharacters
        }
    }
}
