import Foundation

enum JSONValue {
    static func number(_ raw: Any?) -> Double {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return money(value) ?? 0 }
        return 0
    }

    static func money(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil, !trimmed.contains("$") {
            return nil
        }
        let neg = trimmed.contains("(") || trimmed.hasPrefix("-")
        let cleaned = trimmed.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(cleaned), value > 0 || cleaned.contains(".") else { return nil }
        return neg ? -value : value
    }
}
