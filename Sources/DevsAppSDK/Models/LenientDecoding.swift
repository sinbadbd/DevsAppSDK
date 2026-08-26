import Foundation

/// Forgiving accessors used by the models' `init(from:)`.
///
/// The API is stable, but a field that goes missing or changes type should not
/// blank a screen mid-scroll — every accessor falls back to a safe default, and
/// values that arrive as the wrong primitive are coerced where that is
/// unambiguous (`"14"` → `14`, `"true"` → `true`).
///
/// `try?` flattens the optional that `decodeIfPresent` returns, so a `nil` here
/// means "absent, null, or the wrong type" — all of which take the fallback.
extension KeyedDecodingContainer {
    func lenientString(_ key: Key, default fallback: String = "") -> String {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return fallback
    }

    /// Like ``lenientString(_:default:)``, but absent or empty becomes `nil`.
    func lenientOptionalString(_ key: Key) -> String? {
        let value = lenientString(key)
        return value.isEmpty ? nil : value
    }

    func lenientInt(_ key: Key, default fallback: Int = 0) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) ?? fallback }
        return fallback
    }

    func lenientBool(_ key: Key, default fallback: Bool = false) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            switch text.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return fallback
            }
        }
        return fallback
    }

    /// Drops nulls and non-strings rather than failing the whole object.
    func lenientStringArray(_ key: Key) -> [String] {
        guard let values = try? decodeIfPresent([String?].self, forKey: key) else { return [] }
        return values.compactMap { $0 }.filter { !$0.isEmpty }
    }

    func lenientArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        (try? decodeIfPresent([T].self, forKey: key)) ?? []
    }

    func lenientValue<T: Decodable>(_ type: T.Type, _ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
