import Foundation

/// A key/value store whose entries expire.
///
/// Not thread-safe on its own — it lives inside the ``DevsAppClient`` actor,
/// which serializes access.
struct TTLCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let expiresAt: Date
    }

    private var entries: [Key: Entry] = [:]
    let ttl: TimeInterval

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    /// The value for `key`, or `nil` if absent or expired.
    func value(for key: Key, now: Date = Date()) -> Value? {
        guard let entry = entries[key], entry.expiresAt > now else { return nil }
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, now: Date = Date()) {
        guard ttl > 0 else { return }
        entries[key] = Entry(value: value, expiresAt: now.addingTimeInterval(ttl))
    }

    mutating func remove(_ key: Key) {
        entries.removeValue(forKey: key)
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    var count: Int { entries.count }
}
