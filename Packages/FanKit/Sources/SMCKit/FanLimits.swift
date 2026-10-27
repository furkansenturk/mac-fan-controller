/// The checks a fan write must pass. Shared by the app and the privileged helper, which must not trust
/// the values it is sent: an invalid index traps when building a key, and an unreadable range reads as 0.
public enum FanLimits {
    /// Indices that have four-character keys (`F0Ac` … `F9Ac`).
    public static let addressable = 0..<10

    /// The fans to address for a fan count read from `FNum`, which may be missing or nonsense.
    public static func indices(count: Double?) -> Range<Int> {
        guard let count, count.isFinite, count >= 1 else { return 0..<0 }
        return 0..<Int(min(count, Double(addressable.upperBound)))
    }

    /// Whether a fan's reported range can be used to compute a speed. Unreadable keys come back as 0, and a
    /// speed computed from such a range could stop the fan. A minimum of 0 is valid: some fans may stop by design.
    public static func isUsableRange(minimum: Double, maximum: Double) -> Bool {
        minimum.isFinite && maximum.isFinite && minimum >= 0 && maximum > 0 && maximum >= minimum
    }

    /// The speed to write for a request of `rpm`, clamped to the fan's range, or `nil` when the request
    /// can't be honoured safely: the speed isn't a number or the range couldn't be read.
    public static func target(rpm: Double, minimum: Double?, maximum: Double?) -> Double? {
        guard rpm.isFinite, let minimum, let maximum,
              isUsableRange(minimum: minimum, maximum: maximum) else { return nil }
        return min(max(rpm, minimum), maximum)
    }
}
