import Foundation

enum FidelityJSON {
    static func keyed(_ object: [String: Any]) -> [String: Any] {
        var map: [String: Any] = [:]
        for (key, value) in object {
            map[key.lowercased()] = value
        }
        return map
    }

    static func nested(_ object: [String: Any], _ keys: [String]) -> [String: Any] {
        let map = keyed(object)
        for key in keys {
            if let nested = map[key] as? [String: Any] {
                return keyed(nested)
            }
        }
        return [:]
    }

    static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let array = node as? [Any] {
            array.forEach { walk($0, visit: visit) }
            return
        }
        guard let object = node as? [String: Any] else { return }
        visit(object)
        object.values.forEach { walk($0, visit: visit) }
    }

    static func firstString(_ object: [String: Any], _ keys: [String]) -> String? {
        let map = keyed(object)
        for key in keys {
            if let value = string(unwrap(map[key])) {
                return value
            }
        }
        return nil
    }

    static func firstNumber(_ object: [String: Any], _ keys: [String]) -> Double {
        let map = keyed(object)
        for key in keys {
            let value = JSONValue.number(unwrap(map[key]))
            if value != 0 { return value }
        }
        return 0
    }

    static func string(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func getContextPerson(from jsons: [Any]) -> [String: Any]? {
        for json in jsons {
            guard let root = json as? [String: Any] else { continue }
            let ctx = (root["getContext"] as? [String: Any]) ?? keyed(root)["getcontext"] as? [String: Any]
            guard let ctx else { continue }
            let person = nested(ctx, ["person"])
            if !person.isEmpty { return person }
        }
        return nil
    }

    private static func unwrap(_ raw: Any?) -> Any? {
        guard let object = raw as? [String: Any] else { return raw }
        let map = keyed(object)
        return map["value"] ?? map["amount"] ?? raw
    }
}
