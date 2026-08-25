import Foundation

enum ISO8601Timestamp {
    static func date(from raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) {
            return date
        }

        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        if let date = withoutFractional.date(from: raw) {
            return date
        }

        if let trimmed = trimmedFractionalSeconds(raw), trimmed != raw {
            return withFractional.date(from: trimmed) ?? withoutFractional.date(from: trimmed)
        }
        return nil
    }

    private static func trimmedFractionalSeconds(_ raw: String) -> String? {
        guard let dot = raw.firstIndex(of: ".") else { return nil }
        let afterDot = raw.index(after: dot)
        let timezoneIndex = raw[afterDot...].firstIndex { character in
            character == "Z" || character == "+" || character == "-"
        }
        guard let timezoneIndex, timezoneIndex > afterDot else { return nil }
        let fraction = raw[afterDot..<timezoneIndex]
        guard fraction.count > 3, fraction.allSatisfy(\.isNumber) else { return nil }
        let kept = fraction.prefix(3)
        return String(raw[raw.startIndex..<afterDot]) + kept + String(raw[timezoneIndex...])
    }
}
