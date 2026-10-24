import Foundation

/// The answer to a slow check, kept for `lifetime` so that asking every tick
/// doesn't run the check every tick.
public struct CachedCheck<Value> {
    public let lifetime: Duration
    private var last: (value: Value, at: ContinuousClock.Instant)?

    public init(lifetime: Duration) {
        self.lifetime = lifetime
    }

    /// The last answer if it's recent enough, otherwise a fresh one from `check`.
    public mutating func value(at now: ContinuousClock.Instant = .now, _ check: () -> Value) -> Value {
        if let last, now - last.at < lifetime { return last.value }
        let value = check()
        last = (value, now)
        return value
    }
}
